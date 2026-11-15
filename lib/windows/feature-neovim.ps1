# PowerShell equivalent of lib/neovim-bootstrap.sh for the Windows route, with
# one deliberate deviation. The Unix route publishes a command symlink, but on
# Windows nvim.exe loads lua51.dll and DbgHelp.dll from its own directory and
# resolves its runtime as ../share/nvim/runtime, so neither a hard link nor a
# copy placed in ~/.local/bin can run. The managed distribution therefore stays
# private under ~/.local/opt/neovim and its bin directory is the published
# command path; the user-level PATH entry is the only native effect outside
# ~/.local.

if (-not (Get-Command Write-PlasticineLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'common.ps1')
}
if (-not (Get-Command Publish-PlasticineNewDirectory -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'publish.ps1')
}
if (-not (Get-Command Set-PlasticineOwnerOnlyAcl -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'acl.ps1')
}
if (-not (Get-Command Add-PlasticineUserPathEntry -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'user-path.ps1')
}
if (Get-Command Get-PlasticineNeovimPlan -ErrorAction SilentlyContinue) { return }

$PlasticineNeovimVersion = '0.12.5'
$PlasticineNeovimAsset = 'nvim-win64.zip'
# Reviewed from the official v0.12.5 GitHub Release asset on 2026-11-15.
$PlasticineNeovimDigest = 'de8625ba8cf65ebf40eb80a388ba1ec8e9c15b30218821e2c639119b05920de1'
$PlasticineNeovimReleaseBase = 'https://github.com/neovim/neovim/releases/download/v0.12.5'
$PlasticineNeovimArchiveRoot = 'nvim-win64'

function Stop-PlasticineNeovim {
    param([Parameter(Mandatory = $true)][string]$Message)
    Stop-Plasticine "neovim: $Message"
}

# The only version line this route trusts is the first "NVIM vX.Y.Z" line; the
# build banner also carries LuaJIT and library versions that are not targets.
function Get-PlasticineNeovimVersion {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $output = & $Path --version 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    $first = ''
    foreach ($line in @($output)) { $first = ([string]$line).Trim(); break }
    if ($first -notmatch '^NVIM v([0-9]+\.[0-9]+\.[0-9]+)$') { return $null }
    return $Matches[1]
}

function Resolve-PlasticineNeovimExecutable {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string]$InstallDirectory
    )
    $found = Get-PlasticineCommandPath 'nvim'
    if ($found) { return [IO.Path]::GetFullPath($found) }
    $item = Get-PlasticineItem $Command
    if ($item -and -not $item.PSIsContainer -and -not (Test-PlasticineReparsePoint $item)) {
        return [IO.Path]::GetFullPath($Command)
    }
    return $null
}

function Assert-PlasticineNeovimDistribution {
    param([Parameter(Mandatory = $true)][string]$InstallDirectory)
    $item = Get-PlasticineItem $InstallDirectory
    if (-not $item) { return $false }
    if (-not $item.PSIsContainer -or (Test-PlasticineReparsePoint $item)) {
        Stop-PlasticineNeovim "distribution target is not a regular directory: $InstallDirectory; left untouched."
    }
    return $true
}

function Get-PlasticineNeovimManagedIdentity {
    param([Parameter(Mandatory = $true)][string]$InstallDirectory)
    $command = Join-Path $InstallDirectory 'bin\nvim.exe'
    if (-not (Test-Path -LiteralPath $command -PathType Leaf)) { return '' }
    return (Get-PlasticineFileHash $command)
}

function Get-PlasticineNeovimPlan {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    $null = Assert-PlasticineAbsolutePath -Path $HomeDirectory -Name 'home directory'
    Assert-PlasticineWindowsPlatform
    $localDirectory = Join-Path $HomeDirectory '.local'
    $optDirectory = Join-Path $localDirectory 'opt'
    $installDirectory = Join-Path $optDirectory 'neovim'
    $pathDirectory = Join-Path $installDirectory 'bin'
    $command = Join-Path $pathDirectory 'nvim.exe'
    Assert-PlasticineInstallDestination -Parent @($HomeDirectory, $localDirectory, $optDirectory)
    $null = Assert-PlasticineNeovimDistribution -InstallDirectory $installDirectory
    return [pscustomobject]@{
        Version          = $PlasticineNeovimVersion
        Asset            = $PlasticineNeovimAsset
        Digest           = $PlasticineNeovimDigest
        ReleaseUrl       = $PlasticineNeovimReleaseBase + '/' + $PlasticineNeovimAsset
        ArchiveRoot      = $PlasticineNeovimArchiveRoot
        HomeDirectory    = $HomeDirectory
        LocalDirectory   = $localDirectory
        OptDirectory     = $optDirectory
        InstallDirectory = $installDirectory
        PathDirectory    = $pathDirectory
        Command          = $command
        PathMissing      = ($null -ne (Resolve-PlasticineUserPathAddition -Directory $pathDirectory))
        Observed         = Resolve-PlasticineNeovimExecutable -Command $command -InstallDirectory $installDirectory
    }
}

function Write-PlasticineNeovimPreview {
    param([Parameter(Mandatory = $true)]$Plan)
    Write-PlasticineLog ("neovim: observed windows/amd64; official archive $($Plan.Asset); pinned baseline $($Plan.Version).")
    Write-PlasticineLog '  Fixed supported baseline: Neovim 0.12.5 from its exact official versioned GitHub Release asset.'
    Write-PlasticineLog '  Missing Neovim is installed; an outdated managed distribution is safely replaced; a current installation is retained.'
    Write-PlasticineLog '  Current external owners may be used without mutation; outdated, prerelease, custom, unhealthy, or ambiguous owners are refused.'
    Write-PlasticineLog '  network during apply: the pinned github.com/neovim/neovim archive only when replacement is needed; plugins come from the verified Plasticine Release snapshot when one is selected.'
    Write-PlasticineLog "  distribution: $($Plan.InstallDirectory) (fresh atomic no-clobber directory publication; authorized upgrades use a rename swap with rollback)."
    if ($Plan.PathMissing) {
        Write-PlasticineLog "  command path: $($Plan.PathDirectory) (will be appended to the user-level PATH; nvim.exe needs its sibling DLLs and runtime)."
    } else {
        Write-PlasticineLog "  command path: $($Plan.PathDirectory) (already on the user-level PATH)."
    }
    Write-PlasticineLog '  package manager/privilege: none.'
    Write-PlasticineLog '  LSP and formatter tools are installed by the managed configuration on first start; a missing Node toolchain degrades to the markdown/shell subset.'
    if ($Plan.Observed) {
        Write-PlasticineLog "  Observed executable: $($Plan.Observed); its version and owner will be classified during apply."
    }
}

function Invoke-PlasticineNeovimPrepare {
    param([Parameter(Mandatory = $true)]$Plan)
    Assert-PlasticineWindowsPlatform

    # Re-observe at confirmed apply and classify the owner before any download.
    $bin = Resolve-PlasticineNeovimExecutable -Command $Plan.Command -InstallDirectory $Plan.InstallDirectory
    $publication = 'fresh'
    $originalIdentity = ''
    $managed = $false
    if ($bin) {
        $observedVersion = Get-PlasticineNeovimVersion $bin
        if (-not $observedVersion) {
            Stop-PlasticineNeovim "existing editor is unhealthy or has a prerelease/custom/unverifiable version: $bin; repair its owner. Left untouched."
        }
        $managedCommand = [IO.Path]::GetFullPath($Plan.Command)
        $managed = ($bin -eq $managedCommand)
        if ((Compare-PlasticineVersion $observedVersion $Plan.Version) -ge 0) {
            if ($managed) { Assert-PlasticineNeovimPathEntry -Plan $Plan }
            Write-PlasticineLog "neovim: pinned baseline $($Plan.Version) is satisfied by stable $observedVersion at $bin; distribution retained without editor release traffic."
            return
        }
        if (-not $managed) {
            Stop-PlasticineNeovim "outdated Neovim $observedVersion at unsupported owner path $bin; update it with its owner. No shadow installation was created."
        }
        $publication = 'upgrade'
        $originalIdentity = Get-PlasticineNeovimManagedIdentity -InstallDirectory $Plan.InstallDirectory
    } elseif (Assert-PlasticineNeovimDistribution -InstallDirectory $Plan.InstallDirectory) {
        Stop-PlasticineNeovim 'an unowned distribution exists at the managed destination; remove or repair it explicitly. Left untouched.'
    }

    $work = New-PlasticineTempDirectory 'plasticine-neovim'
    try {
        $archive = Join-Path $work $Plan.Asset
        Invoke-PlasticineDownload -Url $Plan.ReleaseUrl -Destination $archive `
            -FailureMessage 'neovim: official archive download failed; active installation was left untouched.'
        if ((Get-PlasticineFileHash $archive) -ne $Plan.Digest) {
            Stop-PlasticineNeovim 'GitHub Release asset SHA-256 digest mismatch; active installation was left untouched.'
        }
        $extract = Join-Path $work 'extract'
        Expand-PlasticineArchive -Archive $archive -Destination $extract -Member @($Plan.ArchiveRoot)
        $candidate = Join-Path $extract $Plan.ArchiveRoot
        $candidateCommand = Join-Path $candidate 'bin\nvim.exe'
        $candidateRuntime = Join-Path $candidate 'share\nvim\runtime\filetype.lua'
        if (-not (Test-Path -LiteralPath $candidateCommand -PathType Leaf) -or
            -not (Test-Path -LiteralPath $candidateRuntime -PathType Leaf)) {
            Stop-PlasticineNeovim 'archive is not a complete Neovim distribution; active installation was left untouched.'
        }
        $candidateVersion = Get-PlasticineNeovimVersion $candidateCommand
        if (-not $candidateVersion) {
            Stop-PlasticineNeovim 'candidate editor failed its version health check; active installation was left untouched.'
        }
        if ($candidateVersion -ne $Plan.Version) {
            Stop-PlasticineNeovim "candidate version $candidateVersion does not match target $($Plan.Version); active installation was left untouched."
        }

        foreach ($directory in @($Plan.LocalDirectory, $Plan.OptDirectory)) {
            if (-not (Get-PlasticineItem $directory)) {
                New-Item -ItemType Directory -Path $directory -ErrorAction Stop | Out-Null
                Set-PlasticineOwnerOnlyAcl -Path $directory
            }
        }
        Assert-PlasticineInstallDestination -Parent @($Plan.HomeDirectory, $Plan.LocalDirectory, $Plan.OptDirectory)
        $null = Assert-PlasticineNeovimDistribution -InstallDirectory $Plan.InstallDirectory

        $stage = Join-Path $Plan.OptDirectory ('.neovim.plasticine.' + [IO.Path]::GetRandomFileName())
        if (Get-PlasticineItem $stage) {
            Stop-PlasticineNeovim 'private publication pathname unexpectedly exists; active installation was left untouched.'
        }
        try {
            Copy-Item -LiteralPath $candidate -Destination $stage -Recurse -ErrorAction Stop
            if ($publication -eq 'fresh') {
                Publish-PlasticineNewDirectory -Candidate $stage -Target $Plan.InstallDirectory
            } else {
                if ((Get-PlasticineNeovimManagedIdentity -InstallDirectory $Plan.InstallDirectory) -ne $originalIdentity) {
                    Stop-PlasticineNeovim 'authorized distribution changed during preparation; replacement aborted.'
                }
                Update-PlasticineDirectory -Candidate $stage -Target $Plan.InstallDirectory
            }
        } finally {
            if (Get-PlasticineItem $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
        }
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }

    $resultVersion = Get-PlasticineNeovimVersion $Plan.Command
    if (-not $resultVersion) {
        Stop-PlasticineNeovim 'published editor failed final health verification; configuration was not applied. Inspect the retained distribution.'
    }
    if ($resultVersion -ne $Plan.Version) {
        Stop-PlasticineNeovim 'published editor does not match the resolved target; configuration was not applied.'
    }
    Assert-PlasticineNeovimPathEntry -Plan $Plan
    Write-PlasticineLog "neovim: $publication completed at stable target $($Plan.Version) with complete runtime: $($Plan.InstallDirectory)"
}

# The command path has to survive a distribution replacement, so the managed
# bin directory is published through the user PATH instead of a copied command.
function Assert-PlasticineNeovimPathEntry {
    param([Parameter(Mandatory = $true)]$Plan)
    if ($null -eq (Resolve-PlasticineUserPathAddition -Directory $Plan.PathDirectory)) { return }
    $backupDirectory = Join-Path $Plan.HomeDirectory '.plasticine\backups\user-path'
    $added = Add-PlasticineUserPathEntry -Directory $Plan.PathDirectory -BackupDirectory $backupDirectory
    if ($added) {
        Write-PlasticineLog "neovim: added $($Plan.PathDirectory) to the user-level PATH; reopen the terminal to pick it up."
    } else {
        Write-PlasticineLog "neovim: the user-level PATH already contains $($Plan.PathDirectory); nothing to change."
    }
}
