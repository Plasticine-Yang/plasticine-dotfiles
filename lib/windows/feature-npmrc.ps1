# PowerShell equivalent of lib/npmrc-configuration.sh for the Windows route.
# Only the script-approval preference belongs to Plasticine. The Owner file is
# never printed anywhere: ~/.npmrc may contain registry credentials. No Node or
# npm executable is needed.
#
# The compose step is a line-for-line port of the awk program in the Unix file:
# every unrelated byte survives (CRLF, comments and a missing final newline
# included), quoted keys and array spellings are replaced instead of duplicated,
# keys inside a section are left to the section owner, and exactly one scalar
# preference is published. The apply step backs up the previous bytes, publishes
# through a same-directory atomic replace, applies an owner-only DACL and stops
# when the file changed after it was read.
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
if (Get-Command Get-PlasticineNpmrcPlan -ErrorAction SilentlyContinue) { return }

$PlasticineNpmrcTargetLeaf = '.npmrc'
$PlasticineNpmrcBackupLabel = '.npmrc'
$PlasticineNpmrcKey = 'dangerously-allow-all-scripts'
$PlasticineNpmrcCanonicalLine = 'dangerously-allow-all-scripts=true'

function Stop-PlasticineNpmrc {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Message)
    Stop-Plasticine "npmrc: $Message"
}

function Get-PlasticineNpmrcPaths {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory)
    $null = Assert-PlasticineAbsolutePath -Path $HomeDirectory -Name 'home directory'
    $backupRoot = Join-Path $HomeDirectory '.plasticine\backups'
    $backupDirectory = Join-Path $backupRoot 'npmrc'
    return [pscustomobject]@{
        HomeDirectory   = $HomeDirectory
        Target          = Join-Path $HomeDirectory $PlasticineNpmrcTargetLeaf
        BackupRoot      = $backupRoot
        BackupDirectory = $backupDirectory
        BackupLabel     = $PlasticineNpmrcBackupLabel
        BackupPath      = Join-Path $backupDirectory ($PlasticineNpmrcBackupLabel + '.plasticine-backup')
    }
}

# The awk program joins emitted records with a single LF and only appends a
# final newline when the input ended with one (or when it had to append the
# managed key). Keep the exact same framing here.
function Add-PlasticineNpmrcComposedLine {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Line
    )
    if ($State.Count -gt 0) { [void]$State.Builder.Append("`n") }
    [void]$State.Builder.Append($Line)
    $State.Count = $State.Count + 1
}

# Byte-for-byte equivalent of plasticine_npmrc_compose in
# lib/npmrc-configuration.sh. The input arrives as a Latin1 string so offsets and
# bytes agree; the caller writes the result back with the same encoding.
function New-PlasticineNpmrcContent {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $records = New-Object System.Collections.ArrayList
    if ($Text.Length -gt 0) {
        $position = 0
        while ($position -lt $Text.Length) {
            $newline = $Text.IndexOf([char]10, $position)
            if ($newline -lt 0) {
                [void]$records.Add($Text.Substring($position))
                break
            }
            [void]$records.Add($Text.Substring($position, $newline - $position))
            $position = $newline + 1
        }
    }
    # The awk program learns CRLF from the first record only, and treats an
    # input whose last byte is not LF as having no final newline.
    $carriageReturn = ''
    if ($records.Count -gt 0 -and $records[0].EndsWith([string][char]13)) {
        $carriageReturn = [string][char]13
    }
    $finalNewline = $true
    if ($Text.Length -gt 0 -and $Text[$Text.Length - 1] -ne [char]10) { $finalNewline = $false }

    $canonical = $PlasticineNpmrcCanonicalLine
    $quote = [string][char]39
    $targetPattern = '^[ \t]*(' + $PlasticineNpmrcKey + '|"' + $PlasticineNpmrcKey + '"|' +
        $quote + $PlasticineNpmrcKey + $quote + ')(\[\])?[ \t]*(=|\r?$)'
    $sectionPattern = '^[ \t]*\[.*\][ \t]*(;.*|#.*)?\r?$'

    $state = [pscustomobject]@{
        Builder = (New-Object System.Text.StringBuilder)
        Count   = 0
    }
    $seen = 0
    $inSection = $false
    foreach ($record in $records) {
        if ([regex]::IsMatch($record, $sectionPattern)) {
            if ($seen -eq 0) {
                Add-PlasticineNpmrcComposedLine -State $state -Line ($canonical + $carriageReturn)
                $seen = 1
            }
            $inSection = $true
            Add-PlasticineNpmrcComposedLine -State $state -Line $record
            continue
        }
        if ([regex]::IsMatch($record, $targetPattern)) {
            if ($inSection) {
                Add-PlasticineNpmrcComposedLine -State $state -Line $record
                continue
            }
            if ($seen -eq 0) {
                Add-PlasticineNpmrcComposedLine -State $state -Line ($canonical + $carriageReturn)
            }
            $seen = $seen + 1
            continue
        }
        Add-PlasticineNpmrcComposedLine -State $state -Line $record
    }
    if ($seen -eq 0) {
        Add-PlasticineNpmrcComposedLine -State $state -Line ($canonical + $carriageReturn)
        $finalNewline = $true
    }
    if ($finalNewline) { [void]$state.Builder.Append("`n") }
    return $state.Builder.ToString()
}

# Observation only: shapes, presence and the composed comparison. The content is
# read but never stored on the plan object, so a preview can never leak it.
function Get-PlasticineNpmrcObservation {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory)
    $paths = Get-PlasticineNpmrcPaths -HomeDirectory $HomeDirectory
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
    $satisfied = $false
    if ($targetItem) {
        if ($targetItem.PSIsContainer -or (Test-PlasticineReparsePoint $targetItem)) {
            [void]$invalid.Add($paths.Target)
        } else {
            $isRegularFile = $true
            $current = Read-PlasticineConfigText $paths.Target
            $satisfied = Test-PlasticineConfigTextEqual (New-PlasticineNpmrcContent -Text $current) $current
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
        Satisfied     = $satisfied
        BackupExists  = $backupExists
        InvalidPaths  = @($invalid)
    }
}

function Assert-PlasticineNpmrcConfiguration {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory)
    $paths = Get-PlasticineNpmrcPaths -HomeDirectory $HomeDirectory
    foreach ($directory in @($paths.BackupRoot, $paths.BackupDirectory)) {
        $null = Assert-PlasticineConfigDirectory -Path $directory -Label 'npmrc'
    }
    $null = Assert-PlasticineConfigFile -Path $paths.Target -Label 'npmrc'
    $backupItem = Get-PlasticineItem $paths.BackupPath
    if ($backupItem) {
        if ($backupItem.PSIsContainer -or (Test-PlasticineReparsePoint $backupItem)) {
            Stop-PlasticineConfig -Label 'npmrc' -Message "$($paths.BackupPath) must be a regular file."
        }
    }
    return $paths
}

function Invoke-PlasticineNpmrcValidate {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory)
    $null = Assert-PlasticineNpmrcConfiguration -HomeDirectory $HomeDirectory
}

function Get-PlasticineNpmrcPlan {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory)
    Assert-PlasticineWindowsPlatform
    $observation = Get-PlasticineNpmrcObservation -HomeDirectory $HomeDirectory
    $paths = $observation.Paths
    return [pscustomobject]@{
        HomeDirectory   = $paths.HomeDirectory
        Target          = $paths.Target
        BackupRoot      = $paths.BackupRoot
        BackupDirectory = $paths.BackupDirectory
        BackupPath      = $paths.BackupPath
        Exists          = $observation.Exists
        IsRegularFile   = $observation.IsRegularFile
        Satisfied       = $observation.Satisfied
        BackupExists    = $observation.BackupExists
        BackupPending   = ($observation.Exists -and $observation.IsRegularFile -and
            -not $observation.Satisfied -and -not $observation.BackupExists)
        InvalidPaths    = @($observation.InvalidPaths)
    }
}

function Write-PlasticineNpmrcPreview {
    param([Parameter(Mandatory = $true)]$Plan)
    if (@($Plan.InvalidPaths).Count -gt 0) {
        foreach ($path in @($Plan.InvalidPaths)) {
            Write-PlasticineError "npmrc: configuration path has the wrong shape and must be repaired: $path"
        }
        Stop-Plasticine 'npmrc: refusing to continue while ~/.npmrc or a backup path is a directory, a symlink or another reparse point; nothing was changed.'
    }
    if (-not $Plan.Exists) {
        Write-PlasticineLog 'npmrc: ~/.npmrc is missing; will create it with only dangerously-allow-all-scripts=true.'
    } elseif ($Plan.Satisfied) {
        Write-PlasticineLog 'npmrc: ~/.npmrc already has dangerously-allow-all-scripts=true.'
    } else {
        Write-PlasticineLog 'npmrc: set dangerously-allow-all-scripts=true in ~/.npmrc; preserve all other settings.'
    }
    Write-PlasticineLog 'npmrc: the file may carry registry credentials; its content is never printed and no npm command is run.'
    Write-PlasticineLog 'npmrc: every unrelated byte is preserved, including CRLF, comments and a missing final newline.'
    if ($Plan.Exists -and -not $Plan.Satisfied) {
        if ($Plan.BackupExists) {
            Write-PlasticineLog "npmrc: an earlier backup is retained at $($Plan.BackupPath); no second backup is added."
        } else {
            Write-PlasticineLog "npmrc: the previous ~/.npmrc is backed up once to $($Plan.BackupDirectory) before the atomic replacement."
        }
    }
    Write-PlasticineLog 'npmrc: the published file gets an owner-only DACL; a converged rerun neither rewrites the file nor adds a backup.'
}

# Called by the Windows apply script after every selected tool was prepared.
# Mirrors plasticine_npmrc_apply: validate, compose, compare, back up the first
# changed version, re-check that the file did not move under us, then replace it
# atomically. The target itself is never printed.
function Invoke-PlasticineNpmrcApply {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory)
    $paths = Assert-PlasticineNpmrcConfiguration -HomeDirectory $HomeDirectory
    $existed = [bool](Get-PlasticineItem $paths.Target)
    $current = Read-PlasticineConfigText $paths.Target
    $candidate = New-PlasticineNpmrcContent -Text $current
    $result = [pscustomobject]@{
        Target        = $paths.Target
        Changed       = $false
        BackupPath    = $null
        BackupCreated = $false
    }
    if ($existed -and (Test-PlasticineConfigTextEqual $candidate $current)) {
        # The file may carry registry credentials, so even a converged rerun
        # enforces the owner-only DACL; the bytes and the backup are untouched.
        Set-PlasticineOwnerOnlyAcl -Path $paths.Target
        Write-PlasticineLog 'npmrc: ~/.npmrc already has dangerously-allow-all-scripts=true; nothing to change.'
        return $result
    }
    # Re-validate after composing so a path that changed shape meanwhile is
    # reported instead of replaced.
    $null = Assert-PlasticineNpmrcConfiguration -HomeDirectory $HomeDirectory
    if ($existed) {
        # The bytes that produced the candidate must still be the bytes on disk;
        # otherwise another writer (or the Owner) won the race.
        if (-not (Test-PlasticineConfigTextEqual (Read-PlasticineConfigText $paths.Target) $current)) {
            Stop-PlasticineNpmrc '~/.npmrc changed during apply; retry.'
        }
        $backupExisted = Test-Path -LiteralPath $paths.BackupPath -PathType Leaf
        $backup = Save-PlasticineConfigBackup -Path $paths.Target -BackupDirectory $paths.BackupDirectory `
            -Label $paths.BackupLabel
        $result.BackupPath = $backup
        $result.BackupCreated = -not $backupExisted
        if ($backupExisted) {
            Write-PlasticineLog "npmrc: kept the earlier backup at $backup; a rerun does not back up twice."
        } else {
            Write-PlasticineLog "npmrc: backed up the previous ~/.npmrc to $backup."
        }
    }
    if ($existed) {
        # Restrict the retained file before the new secret bytes land, then
        # replace it; File.Replace keeps the destination DACL, so the published
        # file is owner-only from the first moment it holds credentials.
        Set-PlasticineOwnerOnlyAcl -Path $paths.Target
    }
    $changed = Publish-PlasticineConfigFile -Path $paths.Target -Text $candidate -Label 'npmrc' `
        -OwnerOnly -OriginalText $current
    if (-not $changed) {
        Write-PlasticineLog 'npmrc: ~/.npmrc already has dangerously-allow-all-scripts=true; nothing to change.'
        return $result
    }
    # File.Replace keeps the replaced file's security descriptor, so the
    # owner-only DACL prepared on the staging file must be applied again after
    # an update. A freshly created file already inherited it through the hard
    # link, but re-applying is idempotent.
    Set-PlasticineOwnerOnlyAcl -Path $paths.Target
    $result.Changed = $true
    if ($existed) {
        Write-PlasticineLog "npmrc: set dangerously-allow-all-scripts=true in $($paths.Target); every other setting was preserved."
    } else {
        Write-PlasticineLog "npmrc: created $($paths.Target) with only dangerously-allow-all-scripts=true and an owner-only DACL."
    }
    return $result
}
