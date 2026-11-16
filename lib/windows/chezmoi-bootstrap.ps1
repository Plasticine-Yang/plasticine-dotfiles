# PowerShell equivalent of lib/chezmoi-bootstrap.sh: same ownership routes,
# same reuse rules, and the same reviewed pinned artifact contract.

. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'publish.ps1')
. (Join-Path $PSScriptRoot 'acl.ps1')

$PlasticineChezmoiVersion = '2.72.1'
$PlasticineChezmoiAssets = @{
    'chezmoi_2.72.1_windows_amd64.zip' = '75b22917f6baa0a40fec7bf9ad16fd8ea8cf4943f8d8cc1ddb07586d4376bf34'
}
# The official Windows zip also ships the license, a readme and shell
# completions; only chezmoi.exe is published, but the reviewed archive layout
# covers every top-level member so an unexpected addition still stops.
$PlasticineChezmoiArchiveMember = @('LICENSE', 'README.md', 'completions', 'chezmoi.exe')

function Stop-PlasticineChezmoi {
    param([Parameter(Mandatory = $true)][string]$Message)
    Stop-Plasticine "chezmoi prerequisite: $Message"
}

function Invoke-PlasticineChezmoiBootstrap {
    param(
        [Parameter(Mandatory = $true)][string]$HomeDirectory,
        [string]$Explicit
    )
    if (-not [IO.Path]::IsPathRooted($HomeDirectory)) { Stop-PlasticineChezmoi 'HOME must be absolute.' }
    $localDir = Join-Path $HomeDirectory '.local'
    $installDir = Join-Path $localDir 'bin'
    $target = Join-Path $installDir 'chezmoi.exe'
    $parents = @($HomeDirectory, $localDir, $installDir)
    Assert-PlasticineInstallDestination -Parent $parents -Target $target

    $bin = $null
    $owner = 'missing'
    if ($Explicit) {
        if ($Explicit -match '[\\/]') { $bin = $Explicit } else { $bin = Get-PlasticineCommandPath $Explicit }
        if (-not $bin -or -not (Test-Path -LiteralPath $bin -PathType Leaf)) {
            Stop-PlasticineChezmoi "explicit executable was not found: $Explicit"
        }
        $owner = 'explicit'
    } else {
        $found = Get-PlasticineCommandPath 'chezmoi'
        if ($found) {
            $bin = $found
            $owner = 'external'
        } elseif (Get-PlasticineItem $target) {
            $bin = $target
            $owner = 'direct'
        }
    }
    $observed = 'missing'
    if ($bin) {
        $bin = [IO.Path]::GetFullPath($bin)
        if ($owner -eq 'external' -and $bin -eq $target) { $owner = 'direct' }
        $observed = Get-PlasticineExecutableVersion $bin
        if (-not $observed) {
            Stop-PlasticineChezmoi "existing executable is unhealthy or has an unverifiable/prerelease version: $bin; repair its owner, then retry."
        }
    }
    if ($owner -eq 'explicit') {
        if ((Compare-PlasticineVersion $observed $PlasticineChezmoiVersion) -lt 0) {
            Stop-PlasticineChezmoi "explicit executable lacks the required chezmoi interface: $bin"
        }
        Write-PlasticineLog "Using explicit chezmoi executable override without ownership mutation: $bin ($observed)."
        return $bin
    }

    $action = 'install'
    if ($observed -ne 'missing') {
        if ((Compare-PlasticineVersion $observed $PlasticineChezmoiVersion) -ge 0) {
            Write-PlasticineLog "chezmoi prerequisite: pinned baseline $PlasticineChezmoiVersion is satisfied by $bin ($observed); reusing it without release traffic."
            return $bin
        }
        if ($owner -ne 'direct') {
            Stop-PlasticineChezmoi "$bin is below the supported baseline ($observed < $PlasticineChezmoiVersion) but owned by the $owner route; update it through that owner. It was left untouched and no shadow copy was installed."
        }
        $action = 'update'
    }

    Assert-PlasticineWindowsPlatform
    $asset = 'chezmoi_' + $PlasticineChezmoiVersion + '_windows_amd64.zip'
    if (-not $PlasticineChezmoiAssets.ContainsKey($asset)) {
        Stop-PlasticineChezmoi "no reviewed artifact tuple for $asset"
    }
    $expected = $PlasticineChezmoiAssets[$asset]
    $observedHash = ''
    if ($owner -eq 'direct') { $observedHash = Get-PlasticineFileHash $target }

    Write-PlasticineLog 'Maintaining chezmoi prerequisite before source acquisition and Feature confirmation; cancellation will not undo this work.'
    $work = New-PlasticineTempDirectory 'plasticine-chezmoi'
    try {
        Write-PlasticineLog "chezmoi prerequisite: source=reviewed official GitHub Release tuple; observed=$observed; target=$PlasticineChezmoiVersion; action=$action."
        $url = 'https://github.com/twpayne/chezmoi/releases/download/v' + $PlasticineChezmoiVersion + '/' + $asset
        $archive = Join-Path $work $asset
        Invoke-PlasticineDownload -Url $url -Destination $archive `
            -FailureMessage 'chezmoi prerequisite: release archive download failed; existing executable preserved.'
        if ((Get-PlasticineFileHash $archive) -ne $expected) {
            Stop-PlasticineChezmoi 'release archive SHA-256 mismatch; existing executable preserved.'
        }
        $candidateDir = Join-Path $work 'candidate'
        Expand-PlasticineArchive -Archive $archive -Destination $candidateDir -Member $PlasticineChezmoiArchiveMember
        $candidate = Join-Path $candidateDir 'chezmoi.exe'
        if ((Get-PlasticineExecutableVersion $candidate) -ne $PlasticineChezmoiVersion) {
            Stop-PlasticineChezmoi 'release candidate failed version/health validation; existing executable preserved.'
        }

        Assert-PlasticineInstallDestination -Parent $parents -Target $target
        foreach ($directory in @($localDir, $installDir)) {
            if (-not (Get-PlasticineItem $directory)) {
                New-Item -ItemType Directory -Path $directory -ErrorAction Stop | Out-Null
                Set-PlasticineOwnerOnlyAcl -Path $directory
            }
        }
        Assert-PlasticineInstallDestination -Parent $parents -Target $target
        $stage = Join-Path $installDir ('.chezmoi.plasticine.' + [IO.Path]::GetRandomFileName())
        try {
            Copy-Item -LiteralPath $candidate -Destination $stage -ErrorAction Stop
            if ($action -eq 'install') {
                Publish-PlasticineNewFile -Candidate $stage -Target $target
            } else {
                Update-PlasticineFile -Candidate $stage -Target $target -ExpectedHash $observedHash
            }
        } finally {
            if (Get-PlasticineItem $stage) { Remove-Item -LiteralPath $stage -Force -ErrorAction SilentlyContinue }
        }
        if ((Get-PlasticineExecutableVersion $target) -ne $PlasticineChezmoiVersion) {
            Stop-PlasticineChezmoi "published executable failed health validation and was retained at $target; repair it before retrying."
        }
        Write-PlasticineLog "chezmoi prerequisite: $action completed at $target ($PlasticineChezmoiVersion)."
        return $target
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}