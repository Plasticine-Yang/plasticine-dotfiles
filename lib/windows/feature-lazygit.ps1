# PowerShell equivalent of lib/lazygit-bootstrap.sh for the Windows route: the
# same pinned stable baseline, the same reuse and authorized-replacement rules,
# and the same reviewed artifact tuple. The archive is the official Windows zip
# and the published target is lazygit.exe.

if (-not (Get-Command Write-PlasticineLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'common.ps1')
}
if (-not (Get-Command Publish-PlasticineNewFile -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'publish.ps1')
}
if (-not (Get-Command Set-PlasticineOwnerOnlyAcl -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'acl.ps1')
}
if (Get-Command Get-PlasticineLazygitPlan -ErrorAction SilentlyContinue) { return }

$PlasticineLazygitVersion = '0.65.1'
$PlasticineLazygitAsset = 'lazygit_0.65.1_windows_x86_64.zip'
# Reviewed from the official v0.65.1 GitHub Release asset on 2026-11-15.
$PlasticineLazygitDigest = 'bed669be29204932560836a58dc6519ba43c10ea7dc7df63af8a1d96424e191d'
$PlasticineLazygitReleaseBase = 'https://github.com/jesseduffield/lazygit/releases/download/v0.65.1'
# The official zip also carries the license and readme; the archive helper only
# extracts an archive whose complete member set was reviewed.
$PlasticineLazygitArchiveMember = @('LICENSE', 'README.md', 'lazygit.exe')

function Stop-PlasticineLazygit {
    param([Parameter(Mandatory = $true)][string]$Message)
    Stop-Plasticine "lazygit: $Message"
}

# Lazygit reports a comma-separated field list ("..., version=0.65.1, os=...")
# rather than a single version token, so the generic executable helper cannot
# classify it. Exactly one field may carry the version.
function Get-PlasticineLazygitVersion {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $output = & $Path --version 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    $version = $null
    $seen = 0
    $invalid = $false
    foreach ($line in @($output)) {
        foreach ($field in ([string]$line -split ',')) {
            $value = $field.Trim()
            if ($value -match '^version=(.*)$') {
                $value = $Matches[1].Trim()
            } elseif ($value -match '^lazygit version\s+(.*)$') {
                $value = $Matches[1].Trim()
            } else {
                continue
            }
            $seen++
            if ($value -match '^v?[0-9]+\.[0-9]+\.[0-9]+$') {
                $version = $value -replace '^v', ''
            } else {
                $invalid = $true
            }
        }
    }
    if ($seen -eq 1 -and -not $invalid) { return $version }
    return $null
}

function Test-PlasticineLazygitHealth {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $null = & $Path --version 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Resolve-PlasticineLazygitExecutable {
    param([Parameter(Mandatory = $true)][string]$Target)
    $found = Get-PlasticineCommandPath 'lazygit'
    if ($found) { return [IO.Path]::GetFullPath($found) }
    $item = Get-PlasticineItem $Target
    if ($item -and -not $item.PSIsContainer -and -not (Test-PlasticineReparsePoint $item)) {
        return [IO.Path]::GetFullPath($Target)
    }
    return $null
}

function Get-PlasticineLazygitPlan {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    $null = Assert-PlasticineAbsolutePath -Path $HomeDirectory -Name 'home directory'
    Assert-PlasticineWindowsPlatform
    $localDirectory = Join-Path $HomeDirectory '.local'
    $installDirectory = Join-Path $localDirectory 'bin'
    $target = Join-Path $installDirectory 'lazygit.exe'
    Assert-PlasticineInstallDestination -Parent @($HomeDirectory, $localDirectory, $installDirectory) -Target $target
    return [pscustomobject]@{
        Version          = $PlasticineLazygitVersion
        Asset            = $PlasticineLazygitAsset
        Digest           = $PlasticineLazygitDigest
        ReleaseUrl       = $PlasticineLazygitReleaseBase + '/' + $PlasticineLazygitAsset
        Member           = $PlasticineLazygitArchiveMember
        HomeDirectory    = $HomeDirectory
        LocalDirectory   = $localDirectory
        InstallDirectory = $installDirectory
        Target           = $target
        Observed         = Resolve-PlasticineLazygitExecutable -Target $target
    }
}

function Write-PlasticineLazygitPreview {
    param([Parameter(Mandatory = $true)]$Plan)
    Write-PlasticineLog ("lazygit: observed windows/amd64; archive mapping windows/x86_64; pinned baseline $($Plan.Version).")
    Write-PlasticineLog '  Fixed supported baseline: Lazygit 0.65.1 from its exact official Windows zip release asset.'
    Write-PlasticineLog '  A missing tool is installed; an authorized outdated direct installation is safely replaced; a current tool is retained.'
    Write-PlasticineLog '  Existing prerelease, custom, unhealthy, ambiguous, and unsupported-owner installations are not replaced.'
    Write-PlasticineLog '  network during apply: HTTPS to the pinned github.com/jesseduffield/lazygit release asset only when replacement is needed.'
    Write-PlasticineLog '  commands during apply: curl.exe download; Get-FileHash SHA-256 against the reviewed pinned digest; Expand-Archive of the reviewed member set.'
    Write-PlasticineLog "  destination: $($Plan.Target) (fresh atomic no-clobber publication; authorized upgrades use checked atomic replacement)."
    Write-PlasticineLog '  package manager: none; privilege: none; credentials: none; terminal prompt: none.'
    if ($Plan.Observed) {
        Write-PlasticineLog "  Observed executable: $($Plan.Observed); its version and owner will be classified during apply."
    }
}

function Invoke-PlasticineLazygitPrepare {
    param([Parameter(Mandatory = $true)]$Plan)
    Assert-PlasticineWindowsPlatform

    # Re-observe at confirmed apply: only the managed direct pathname is an
    # authorized replacement owner. A current executable elsewhere is retained,
    # but it cannot be updated by publishing a shadowing second copy.
    $bin = Resolve-PlasticineLazygitExecutable -Target $Plan.Target
    $publication = 'fresh'
    $observedHash = ''
    if ($bin) {
        if (-not (Test-PlasticineLazygitHealth $bin)) {
            Stop-PlasticineLazygit "existing executable is unhealthy and was left untouched: $bin; repair its installation owner, then retry. No fallback."
        }
        $observedVersion = Get-PlasticineLazygitVersion $bin
        if (-not $observedVersion) {
            Stop-PlasticineLazygit "existing executable has a custom, prerelease, or unparseable version and was left untouched: $bin; use its owner to select the stable channel."
        }
        $comparison = Compare-PlasticineVersion $observedVersion $Plan.Version
        if ($comparison -ge 0) {
            Write-PlasticineLog "lazygit: pinned baseline $($Plan.Version) is satisfied by stable $observedVersion at $bin; no release request or replacement."
            return
        }
        if ($bin -ne [IO.Path]::GetFullPath($Plan.Target)) {
            Stop-PlasticineLazygit "outdated Lazygit $observedVersion at unsupported owner path $bin; update it with its owner or remove it from PATH before retrying. No shadow installation was created."
        }
        $publication = 'upgrade'
        $observedHash = Get-PlasticineFileHash $Plan.Target
    }

    $work = New-PlasticineTempDirectory 'plasticine-lazygit'
    try {
        $archive = Join-Path $work $Plan.Asset
        Invoke-PlasticineDownload -Url $Plan.ReleaseUrl -Destination $archive `
            -FailureMessage 'lazygit: release archive download failed; active installation was left untouched.'
        if ((Get-PlasticineFileHash $archive) -ne $Plan.Digest) {
            Stop-PlasticineLazygit 'release archive SHA-256 mismatch; active installation was left untouched.'
        }
        $candidateDir = Join-Path $work 'candidate'
        Expand-PlasticineArchive -Archive $archive -Destination $candidateDir -Member $Plan.Member
        $candidate = Join-Path $candidateDir 'lazygit.exe'
        $candidateVersion = Get-PlasticineLazygitVersion $candidate
        if (-not $candidateVersion) {
            Stop-PlasticineLazygit 'extracted Lazygit has an unparseable version; active installation was left untouched.'
        }
        if ($candidateVersion -ne $Plan.Version) {
            Stop-PlasticineLazygit "extracted Lazygit version $candidateVersion does not match resolved target $($Plan.Version); active installation was left untouched."
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

        $stage = Join-Path $Plan.InstallDirectory ('.lazygit.plasticine.' + [IO.Path]::GetRandomFileName())
        try {
            Copy-Item -LiteralPath $candidate -Destination $stage -ErrorAction Stop
            if ($publication -eq 'fresh') {
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

    $resultVersion = Get-PlasticineLazygitVersion $Plan.Target
    if (-not $resultVersion) {
        Stop-PlasticineLazygit "the executable retained at $($Plan.Target) failed post-publication version verification; repair the Owner file, or remove it if it is the failed publication, before rerunning. Configuration was not applied."
    }
    if ($resultVersion -ne $Plan.Version) {
        Stop-PlasticineLazygit "post-publication version $resultVersion does not match resolved target $($Plan.Version); configuration was not applied."
    }
    Write-PlasticineLog "lazygit: $publication completed at stable target $($Plan.Version): $($Plan.Target)"
}
