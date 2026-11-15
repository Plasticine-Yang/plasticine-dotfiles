# PowerShell equivalent of lib/release-payload.sh: verified Release assets are the
# only network seam a released installer uses for source and managed plugins.

. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'publish.ps1')

function Stop-PlasticineRelease {
    param([Parameter(Mandatory = $true)][string]$Message)
    Stop-Plasticine "release payload: $Message"
}

function Invoke-PlasticineGitCommand {
    param([Parameter(Mandatory = $true)][string[]]$Argument, [string]$Directory)
    $previousPrompt = $env:GIT_TERMINAL_PROMPT
    $previousPreference = $ErrorActionPreference
    $env:GIT_TERMINAL_PROMPT = '0'
    $ErrorActionPreference = 'Continue'
    try {
        # git for Windows still checks MAX_PATH unless long paths are enabled for
        # the command: the released source bundle is restored into a staging
        # directory whose object paths exceed 260 characters even when the
        # LongPathsEnabled policy is on. Every call goes through this seam, so the
        # override cannot drift between the restore, the checkout and the tests.
        if ($Directory) { $output = & git -C $Directory -c core.longpaths=true @Argument 2>&1 }
        else { $output = & git -c core.longpaths=true @Argument 2>&1 }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
        $env:GIT_TERMINAL_PROMPT = $previousPrompt
    }
    return [pscustomobject]@{ ExitCode = $code; Output = @($output | ForEach-Object { [string]$_ }) }
}

function Get-PlasticineReleaseAsset {
    param(
        [Parameter(Mandatory = $true)][string]$HomeDirectory,
        [Parameter(Mandatory = $true)][string]$Base,
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Digest
    )
    $assetDir = Join-Path (Join-Path (Join-Path (Join-Path $HomeDirectory '.cache') 'plasticine') 'releases') $Version
    if (-not (Get-PlasticineItem $assetDir)) {
        New-Item -ItemType Directory -Path $assetDir -Force -ErrorAction Stop | Out-Null
    }
    Assert-PlasticineRealDirectory $assetDir
    $assetPath = Join-Path $assetDir $Name
    $existing = Get-PlasticineItem $assetPath
    if ($existing -and -not $existing.PSIsContainer -and -not (Test-PlasticineReparsePoint $existing)) {
        if ((Get-PlasticineFileHash $assetPath) -eq $Digest) { return $assetPath }
    }
    if ($existing) { Remove-Item -LiteralPath $assetPath -Force -ErrorAction Stop }

    $localDir = $env:PLASTICINE_RELEASE_ASSET_DIR
    if ($localDir) {
        if (-not [IO.Path]::IsPathRooted($localDir)) {
            Stop-PlasticineRelease 'PLASTICINE_RELEASE_ASSET_DIR must be absolute.'
        }
        $localAsset = Join-Path $localDir $Name
        $localItem = Get-PlasticineItem $localAsset
        if (-not $localItem -or $localItem.PSIsContainer -or (Test-PlasticineReparsePoint $localItem)) {
            Stop-PlasticineRelease "local Release asset is unavailable: $localAsset"
        }
        if ((Get-PlasticineFileHash $localAsset) -ne $Digest) {
            Stop-PlasticineRelease "SHA-256 mismatch: $Name"
        }
        $localStage = Join-Path $assetDir ('.plasticine-release.' + [IO.Path]::GetRandomFileName())
        try {
            Copy-Item -LiteralPath $localAsset -Destination $localStage -ErrorAction Stop
            Publish-PlasticineNewFile -Candidate $localStage -Target $assetPath
        } finally {
            if (Get-PlasticineItem $localStage) { Remove-Item -LiteralPath $localStage -Force -ErrorAction SilentlyContinue }
        }
        return $assetPath
    }

    $stage = Join-Path $assetDir ('.plasticine-release.' + [IO.Path]::GetRandomFileName())
    try {
        Invoke-PlasticineDownload -Url ($Base + '/' + $Name) -Destination $stage `
            -FailureMessage "release payload: download failed: $Base/$Name"
        if ((Get-PlasticineFileHash $stage) -ne $Digest) {
            Stop-PlasticineRelease "SHA-256 mismatch: $Name"
        }
        Publish-PlasticineNewFile -Candidate $stage -Target $assetPath
    } finally {
        if (Get-PlasticineItem $stage) { Remove-Item -LiteralPath $stage -Force -ErrorAction SilentlyContinue }
    }
    return $assetPath
}

function Test-PlasticineReleaseBundle {
    param([Parameter(Mandatory = $true)][string]$Bundle)
    $parent = Split-Path -Parent ([IO.Path]::GetFullPath($Bundle))
    $repo = Join-Path $parent ('.plasticine-bundle-verify.' + [IO.Path]::GetRandomFileName())
    try {
        $init = Invoke-PlasticineGitCommand -Argument @('init', '-q', '--bare', $repo)
        if ($init.ExitCode -ne 0) { return $false }
        $verify = Invoke-PlasticineGitCommand -Directory $repo -Argument @('bundle', 'verify', $Bundle)
        return ($verify.ExitCode -eq 0)
    } finally {
        if (Get-PlasticineItem $repo) { Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Invoke-PlasticineReleaseSourceAcquisition {
    param(
        [Parameter(Mandatory = $true)][string]$HomeDirectory,
        [Parameter(Mandatory = $true)][string]$Base,
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][string]$SourceDigest,
        [Parameter(Mandatory = $true)][string]$Revision,
        [Parameter(Mandatory = $true)][string]$Origin,
        [Parameter(Mandatory = $true)][string]$SourceDir
    )
    $bundle = Get-PlasticineReleaseAsset -HomeDirectory $HomeDirectory -Base $Base -Version $Version `
        -Name 'plasticine-source.bundle' -Digest $SourceDigest
    if (-not (Test-PlasticineReleaseBundle $bundle)) {
        Stop-PlasticineRelease 'source Git bundle verification failed.'
    }

    $existing = Get-PlasticineItem $SourceDir
    if ($existing) {
        $gitDir = Join-Path $SourceDir '.git'
        $gitItem = Get-PlasticineItem $gitDir
        if (-not $gitItem -or -not $gitItem.PSIsContainer -or (Test-PlasticineReparsePoint $existing)) {
            Stop-PlasticineRelease "existing chezmoi source is not a Git checkout: $SourceDir"
        }
        $remote = Invoke-PlasticineGitCommand -Directory $SourceDir -Argument @('remote', 'get-url', 'origin')
        $existingOrigin = ($remote.Output -join '').Trim()
        if ($remote.ExitCode -ne 0 -or $existingOrigin -ne $Origin) {
            Stop-PlasticineRelease "existing chezmoi source belongs to another repository: $existingOrigin"
        }
        $status = Invoke-PlasticineGitCommand -Directory $SourceDir -Argument @('status', '--porcelain')
        if ($status.ExitCode -ne 0 -or ($status.Output -join '').Trim() -ne '') {
            Stop-PlasticineRelease "existing chezmoi source has local changes: $SourceDir"
        }
        $fetch = Invoke-PlasticineGitCommand -Directory $SourceDir -Argument @('fetch', '--no-tags', $bundle, 'HEAD')
        if ($fetch.ExitCode -ne 0) { Stop-PlasticineRelease 'could not fetch the released source bundle.' }
        $head = Invoke-PlasticineGitCommand -Directory $SourceDir -Argument @('rev-parse', 'FETCH_HEAD')
        if (($head.Output -join '').Trim() -ne $Revision) {
            Stop-PlasticineRelease 'source bundle does not contain the released revision.'
        }
        $checkout = Invoke-PlasticineGitCommand -Directory $SourceDir -Argument @('checkout', '--detach', $Revision)
        if ($checkout.ExitCode -ne 0) { Stop-PlasticineRelease 'could not check out the released revision.' }
        return $SourceDir
    }

    $parent = Split-Path -Parent $SourceDir
    if (-not (Get-PlasticineItem $parent)) {
        New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
    }
    Assert-PlasticineRealDirectory $parent
    $stage = Join-Path $parent ('.plasticine-source.' + [IO.Path]::GetRandomFileName())
    try {
        $clone = Invoke-PlasticineGitCommand -Argument @('clone', '-q', '--no-checkout', $bundle, $stage)
        if ($clone.ExitCode -ne 0) { Stop-PlasticineRelease 'could not restore the released source bundle.' }
        $commit = Invoke-PlasticineGitCommand -Directory $stage -Argument @('cat-file', '-e', ($Revision + '^{commit}'))
        $checkout = Invoke-PlasticineGitCommand -Directory $stage -Argument @('checkout', '-q', '--detach', $Revision)
        $head = Invoke-PlasticineGitCommand -Directory $stage -Argument @('rev-parse', 'HEAD')
        if ($commit.ExitCode -ne 0 -or $checkout.ExitCode -ne 0 -or ($head.Output -join '').Trim() -ne $Revision) {
            Stop-PlasticineRelease 'restored source does not match the released revision.'
        }
        $remote = Invoke-PlasticineGitCommand -Directory $stage -Argument @('remote', 'set-url', 'origin', $Origin)
        if ($remote.ExitCode -ne 0) { Stop-PlasticineRelease 'could not set the released source origin.' }
        Publish-PlasticineNewDirectory -Candidate $stage -Target $SourceDir
    } finally {
        if (Get-PlasticineItem $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    }
    return $SourceDir
}

function Invoke-PlasticineReleasePluginAcquisition {
    param(
        [Parameter(Mandatory = $true)][string]$HomeDirectory,
        [Parameter(Mandatory = $true)][string]$Base,
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][string]$Digest
    )
    return Get-PlasticineReleaseAsset -HomeDirectory $HomeDirectory -Base $Base -Version $Version `
        -Name 'plasticine-managed-plugins.tar.gz' -Digest $Digest
}