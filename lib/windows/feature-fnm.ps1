# PowerShell equivalent of lib/fnm-bootstrap.sh for the Windows route. Upstream
# publishes no checksums and its installer resolves "latest" dynamically, so the
# Windows release pins the stable asset, its SHA-256 and the executable contract;
# Node versions, defaults and FNM_DIR stay outside this route.

if (-not (Get-Command Write-PlasticineLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'common.ps1')
}
if (-not (Get-Command Publish-PlasticineNewFile -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'publish.ps1')
}
if (-not (Get-Command Set-PlasticineOwnerOnlyAcl -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'acl.ps1')
}
if (Get-Command Get-PlasticineFnmPlan -ErrorAction SilentlyContinue) { return }

$PlasticineFnmVersion = '1.39.0'
$PlasticineFnmAsset = 'fnm-windows.zip'
# Reviewed from the official v1.39.0 GitHub Release asset on 2026-11-15; upstream
# publishes no checksum list, so this digest is the only review anchor.
$PlasticineFnmDigest = '8183bed4348cb78fdfd8abb3d1247fbeab7b2082f941363929c61e747c001e10'
$PlasticineFnmReleaseBase = 'https://github.com/Schniz/fnm/releases/download/v1.39.0'
$PlasticineFnmArchiveMember = @('fnm.exe')

function Stop-PlasticineFnm {
    param([Parameter(Mandatory = $true)][string]$Message)
    Stop-Plasticine "fnm: $Message"
}

function Resolve-PlasticineFnmExecutable {
    param([Parameter(Mandatory = $true)][string]$Target)
    $found = Get-PlasticineCommandPath 'fnm'
    if ($found) { return [IO.Path]::GetFullPath($found) }
    $item = Get-PlasticineItem $Target
    if ($item -and -not $item.PSIsContainer -and -not (Test-PlasticineReparsePoint $item)) {
        return [IO.Path]::GetFullPath($Target)
    }
    return $null
}

function Get-PlasticineFnmPlan {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    $null = Assert-PlasticineAbsolutePath -Path $HomeDirectory -Name 'home directory'
    Assert-PlasticineWindowsPlatform
    $localDirectory = Join-Path $HomeDirectory '.local'
    $installDirectory = Join-Path $localDirectory 'bin'
    $target = Join-Path $installDirectory 'fnm.exe'
    Assert-PlasticineInstallDestination -Parent @($HomeDirectory, $localDirectory, $installDirectory) -Target $target
    return [pscustomobject]@{
        Version          = $PlasticineFnmVersion
        Asset            = $PlasticineFnmAsset
        Digest           = $PlasticineFnmDigest
        ReleaseUrl       = $PlasticineFnmReleaseBase + '/' + $PlasticineFnmAsset
        Member           = $PlasticineFnmArchiveMember
        HomeDirectory    = $HomeDirectory
        LocalDirectory   = $localDirectory
        InstallDirectory = $installDirectory
        Target           = $target
        Observed         = Resolve-PlasticineFnmExecutable -Target $target
    }
}

function Write-PlasticineFnmPreview {
    param([Parameter(Mandatory = $true)]$Plan)
    Write-PlasticineLog ("fnm: observed windows/amd64; pinned baseline $($Plan.Version) from its exact official release asset.")
    Write-PlasticineLog '  Fixed supported baseline: fnm 1.39.0 from the reviewed fnm-windows.zip; upstream publishes no checksum list.'
    Write-PlasticineLog '  A missing tool is installed; an authorized outdated direct installation is safely replaced; a current tool is retained.'
    Write-PlasticineLog '  Existing prerelease, custom, unhealthy, ambiguous, and unsupported-owner installations are not replaced.'
    Write-PlasticineLog '  network during apply: HTTPS to the pinned github.com/Schniz/fnm release asset only when replacement is needed.'
    Write-PlasticineLog '  commands during apply: curl.exe download; Get-FileHash SHA-256 against the reviewed pinned digest; Expand-Archive of the reviewed member set.'
    Write-PlasticineLog "  destination: $($Plan.Target) (fresh atomic no-clobber publication; authorized upgrades use checked same-directory atomic replacement)."
    Write-PlasticineLog '  package manager: none; privilege: none; credentials: none; terminal prompt: none.'
    Write-PlasticineLog '  Node versions, defaults, project declarations, FNM_DIR, and native fnm runtime data are not inspected or changed.'
    Write-PlasticineLog "  Standalone selection does not edit shell startup; ensure $($Plan.InstallDirectory) is on PATH and let the powershell feature add fnm activation."
    if ($Plan.Observed) {
        Write-PlasticineLog "  Observed executable: $($Plan.Observed); its version and owner will be classified during apply."
    }
}

function Invoke-PlasticineFnmPrepare {
    param([Parameter(Mandatory = $true)]$Plan)
    Assert-PlasticineWindowsPlatform

    # Re-observe at confirmed apply: only the managed direct pathname is an
    # authorized replacement owner.
    $bin = Resolve-PlasticineFnmExecutable -Target $Plan.Target
    $publication = 'install'
    $observedHash = ''
    if ($bin) {
        $observedVersion = Get-PlasticineExecutableVersion $bin
        if (-not $observedVersion) {
            Stop-PlasticineFnm "existing executable is unhealthy or has an unverifiable/prerelease/custom version: $bin; repair its owner. Left untouched."
        }
        if ((Compare-PlasticineVersion $observedVersion $Plan.Version) -ge 0) {
            Write-PlasticineLog "fnm: pinned baseline $($Plan.Version) is satisfied by stable $observedVersion at $bin; no release request or replacement."
            return
        }
        if ($bin -ne [IO.Path]::GetFullPath($Plan.Target)) {
            Stop-PlasticineFnm "outdated $bin is owned by an unsupported route; update it there to $($Plan.Version). No shadow copy installed."
        }
        $publication = 'update'
        $observedHash = Get-PlasticineFileHash $Plan.Target
    }

    $work = New-PlasticineTempDirectory 'plasticine-fnm'
    try {
        $archive = Join-Path $work $Plan.Asset
        Invoke-PlasticineDownload -Url $Plan.ReleaseUrl -Destination $archive `
            -FailureMessage 'fnm: release archive download failed; existing executable preserved.'
        if ((Get-PlasticineFileHash $archive) -ne $Plan.Digest) {
            Stop-PlasticineFnm 'release archive SHA-256 mismatch; existing executable preserved.'
        }
        $candidateDirectory = Join-Path $work 'candidate'
        Expand-PlasticineArchive -Archive $archive -Destination $candidateDirectory -Member $Plan.Member
        $candidate = Join-Path $candidateDirectory 'fnm.exe'
        $candidateVersion = Get-PlasticineExecutableVersion $candidate
        if (-not $candidateVersion) {
            Stop-PlasticineFnm 'release candidate is unhealthy or not stable; existing executable preserved.'
        }
        if ($candidateVersion -ne $Plan.Version) {
            Stop-PlasticineFnm "release candidate version $candidateVersion does not match resolved target $($Plan.Version); existing executable preserved."
        }

        $parents = @($Plan.HomeDirectory, $Plan.LocalDirectory, $Plan.InstallDirectory)
        Assert-PlasticineInstallDestination -Parent $parents -Target $Plan.Target
        foreach ($directory in @($Plan.LocalDirectory, $Plan.InstallDirectory)) {
            if (-not (Get-PlasticineItem $directory)) {
                New-Item -ItemType Directory -Path $directory -ErrorAction Stop | Out-Null
                Set-PlasticineOwnerOnlyAcl -Path $directory
            }
        }
        Assert-PlasticineInstallDestination -Parent $parents -Target $Plan.Target

        $stage = Join-Path $Plan.InstallDirectory ('.fnm.plasticine.' + [IO.Path]::GetRandomFileName())
        try {
            Copy-Item -LiteralPath $candidate -Destination $stage -ErrorAction Stop
            if ($publication -eq 'install') {
                Publish-PlasticineNewFile -Candidate $stage -Target $Plan.Target
            } else {
                Update-PlasticineFile -Candidate $stage -Target $Plan.Target -ExpectedHash $observedHash
            }
        } finally {
            if (Get-PlasticineItem $stage) { Remove-Item -LiteralPath $stage -Force -ErrorAction SilentlyContinue }
        }
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }

    $resultVersion = Get-PlasticineExecutableVersion $Plan.Target
    if (-not $resultVersion) {
        Stop-PlasticineFnm "published fnm failed final health check at $($Plan.Target); repair it and retry."
    }
    if ($resultVersion -ne $Plan.Version) {
        Stop-PlasticineFnm "post-publication version $resultVersion does not match resolved target $($Plan.Version); configuration was not applied."
    }
    Write-PlasticineLog "fnm: source=reviewed GitHub Release tuple; target=$($Plan.Version); action=$publication; result=$($Plan.Target)."
}
