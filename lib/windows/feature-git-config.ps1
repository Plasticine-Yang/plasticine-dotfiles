# PowerShell equivalent of the Unix whole-file protection for ~/.gitconfig.
# chezmoi owns the file and renders the reviewed dot_gitconfig; this Windows
# route only validates the target shape and keeps the Owner's pre-apply bytes in
# ~/.plasticine/backups/git-config. Windows has no execute bit, so the Unix
# pending-mode journal and its restore step are intentionally absent.
#
# The provider follows the Windows Feature convention: Get-...Plan observes
# without changing native state, Write-...Preview reports, and the apply script
# calls Invoke-...Apply before chezmoi replaces the managed file.
#
# This file is ASCII only: Windows PowerShell 5.1 reads BOM-less scripts with the
# ANSI code page, so non-ASCII literals would break on some machines.

if (-not (Get-Command Write-PlasticineLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'common.ps1')
}
if (-not (Get-Command Publish-PlasticineNewFile -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'publish.ps1')
}
if (-not (Get-Command Set-PlasticineOwnerOnlyAcl -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'acl.ps1')
}
if (-not (Get-Command Assert-PlasticineConfigFile -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'config-apply.ps1')
}
if (Get-Command Get-PlasticineGitConfigPlan -ErrorAction SilentlyContinue) { return }

$PlasticineGitConfigSourceFile = 'dot_gitconfig'
$PlasticineGitConfigBackupLabel = '.gitconfig'

function Stop-PlasticineGitConfig {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Message)
    Stop-Plasticine "git-config: $Message"
}

# One place resolves every path so the provider, the apply script and the suite
# cannot disagree about the backup name. The first backup is the only one kept.
function Get-PlasticineGitConfigPaths {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory)
    $null = Assert-PlasticineAbsolutePath -Path $HomeDirectory -Name 'home directory'
    $backupRoot = Join-Path $HomeDirectory '.plasticine\backups'
    $backupDirectory = Join-Path $backupRoot 'git-config'
    return [pscustomobject]@{
        HomeDirectory   = $HomeDirectory
        Target          = Join-Path $HomeDirectory '.gitconfig'
        BackupRoot      = $backupRoot
        BackupDirectory = $backupDirectory
        BackupLabel     = $PlasticineGitConfigBackupLabel
        BackupPath      = Join-Path $backupDirectory ($PlasticineGitConfigBackupLabel + '.plasticine-backup')
    }
}

# Observation only: every invalid shape is reported with the exact path so the
# preview can explain the conflict before anything is changed.
function Get-PlasticineGitConfigObservation {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory)
    $paths = Get-PlasticineGitConfigPaths -HomeDirectory $HomeDirectory
    $invalid = New-Object System.Collections.ArrayList
    foreach ($directory in @($paths.BackupRoot, $paths.BackupDirectory)) {
        $item = Get-PlasticineItem $directory
        if ($item -and (-not $item.PSIsContainer -or (Test-PlasticineReparsePoint $item))) {
            [void]$invalid.Add($directory)
        }
    }
    $targetItem = Get-PlasticineItem $paths.Target
    $exists = [bool]$targetItem
    $isRegularFile = $false
    if ($targetItem) {
        if ($targetItem.PSIsContainer -or (Test-PlasticineReparsePoint $targetItem)) {
            [void]$invalid.Add($paths.Target)
        } else {
            $isRegularFile = $true
        }
    }
    $backupItem = Get-PlasticineItem $paths.BackupPath
    $backupExists = $false
    if ($backupItem) {
        if ($backupItem.PSIsContainer -or (Test-PlasticineReparsePoint $backupItem)) {
            [void]$invalid.Add($paths.BackupPath)
        } else {
            $backupExists = $true
        }
    }
    return [pscustomobject]@{
        Paths         = $paths
        Exists        = $exists
        IsRegularFile = $isRegularFile
        BackupExists  = $backupExists
        InvalidPaths  = @($invalid)
    }
}

# Shared validation used by the validate script, the apply script and preview.
# The Unix route reports the same two shapes: a non-regular target and a backup
# parent that is not a real directory.
function Assert-PlasticineGitConfigConfiguration {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory)
    $paths = Get-PlasticineGitConfigPaths -HomeDirectory $HomeDirectory
    $null = Assert-PlasticineConfigFile -Path $paths.Target -Label 'git-config'
    foreach ($directory in @($paths.BackupRoot, $paths.BackupDirectory)) {
        $null = Assert-PlasticineConfigDirectory -Path $directory -Label 'git-config'
    }
    $backupItem = Get-PlasticineItem $paths.BackupPath
    if ($backupItem) {
        if ($backupItem.PSIsContainer -or (Test-PlasticineReparsePoint $backupItem)) {
            Stop-PlasticineConfig -Label 'git-config' -Message "$($paths.BackupPath) must be a regular file."
        }
    }
    return $paths
}

function Invoke-PlasticineGitConfigValidate {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory)
    $null = Assert-PlasticineGitConfigConfiguration -HomeDirectory $HomeDirectory
}

function Get-PlasticineGitConfigPlan {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory)
    Assert-PlasticineWindowsPlatform
    $observation = Get-PlasticineGitConfigObservation -HomeDirectory $HomeDirectory
    $paths = $observation.Paths
    return [pscustomobject]@{
        HomeDirectory   = $paths.HomeDirectory
        Target          = $paths.Target
        BackupRoot      = $paths.BackupRoot
        BackupDirectory = $paths.BackupDirectory
        BackupPath      = $paths.BackupPath
        Exists          = $observation.Exists
        IsRegularFile   = $observation.IsRegularFile
        BackupExists    = $observation.BackupExists
        # The apply script can still skip the backup when the managed bytes
        # already match; this only reports whether a backup could be needed.
        BackupPending   = ($observation.Exists -and -not $observation.BackupExists)
        InvalidPaths    = @($observation.InvalidPaths)
    }
}

function Write-PlasticineGitConfigPreview {
    param([Parameter(Mandatory = $true)]$Plan)
    if (@($Plan.InvalidPaths).Count -gt 0) {
        foreach ($path in @($Plan.InvalidPaths)) {
            Write-PlasticineError "git-config: configuration path has the wrong shape and must be repaired: $path"
        }
        Stop-Plasticine 'git-config: refusing to continue while a configuration path is a directory, a symlink or another reparse point; nothing was changed.'
    }
    Write-PlasticineLog 'git-config: chezmoi owns ~/.gitconfig and renders the reviewed dot_gitconfig; this Feature never publishes or edits it.'
    if (-not $Plan.Exists) {
        Write-PlasticineLog "git-config: $($Plan.Target) does not exist yet; chezmoi will create it and no backup is needed."
    } elseif ($Plan.BackupExists) {
        Write-PlasticineLog "git-config: an earlier backup is retained at $($Plan.BackupPath); no second backup is added."
    } else {
        Write-PlasticineLog "git-config: will back up the current $($Plan.Target) once to $($Plan.BackupDirectory) before chezmoi replaces it, if the managed bytes differ."
    }
    Write-PlasticineLog 'git-config: unchanged content is not rewritten and does not add a backup; the backup directory and copy are owner-only.'
    Write-PlasticineLog 'git-config: Windows has no execute bit, so no file mode is recorded, changed or restored.'
}

# Called by the Windows apply script after every selected tool was prepared and
# before chezmoi renders the managed file. It never writes ~/.gitconfig: the
# only mutation is the first-backup-wins copy of the previous Owner bytes.
function Invoke-PlasticineGitConfigApply {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$SourceDirectory
    )
    $null = Assert-PlasticineAbsolutePath -Path $SourceDirectory -Name 'source directory'
    $paths = Assert-PlasticineGitConfigConfiguration -HomeDirectory $HomeDirectory
    $candidatePath = Join-Path $SourceDirectory $PlasticineGitConfigSourceFile
    $candidateItem = Get-PlasticineItem $candidatePath
    if (-not $candidateItem -or $candidateItem.PSIsContainer -or (Test-PlasticineReparsePoint $candidateItem)) {
        Stop-PlasticineGitConfig "managed source is not a regular file: $candidatePath"
    }
    $result = [pscustomobject]@{
        Target        = $paths.Target
        Changed       = $false
        BackupPath    = $null
        BackupCreated = $false
    }
    if (-not (Get-PlasticineItem $paths.Target)) {
        Write-PlasticineLog "git-config: $($paths.Target) does not exist; chezmoi will create it and no backup is needed."
        return $result
    }
    $candidate = Read-PlasticineConfigText $candidatePath
    $current = Read-PlasticineConfigText $paths.Target
    if (Test-PlasticineConfigTextEqual $candidate $current) {
        Write-PlasticineLog "git-config: $($paths.Target) already matches the managed content; no rewrite and no backup."
        return $result
    }
    $backupExisted = Test-Path -LiteralPath $paths.BackupPath -PathType Leaf
    $backup = Save-PlasticineConfigBackup -Path $paths.Target -BackupDirectory $paths.BackupDirectory `
        -Label $paths.BackupLabel
    $result.Changed = $true
    $result.BackupPath = $backup
    $result.BackupCreated = -not $backupExisted
    if ($backupExisted) {
        Write-PlasticineLog "git-config: kept the earlier backup at $backup; the current file is not backed up twice."
    } else {
        Write-PlasticineLog "git-config: backed up the previous configuration to $backup."
    }
    return $result
}
