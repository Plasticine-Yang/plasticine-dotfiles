# Shared helpers for the Windows configuration apply scripts. The Unix route
# leans on chmod/mv/cmp and a mode-restore journal; Windows owns no execute bits,
# so the Windows equivalent is: validate the target shape, back up the previous
# bytes before replacement, and publish through a same-directory atomic replace.
# Secrets additionally get the owner-only DACL from acl.ps1.

if (-not (Get-Command Write-PlasticineLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'common.ps1')
}
if (-not (Get-Command Set-PlasticineOwnerOnlyAcl -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'acl.ps1')
}
if (-not (Get-Command Publish-PlasticineNewFile -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'publish.ps1')
}
if (Get-Command Assert-PlasticineConfigFile -ErrorAction SilentlyContinue) { return }

# Latin1 round-trips every byte, so composed candidates keep the Owner's CRLF and
# any non-UTF-8 bytes intact.
function Get-PlasticineLatin1Encoding {
    return [Text.Encoding]::GetEncoding(28591)
}

function Stop-PlasticineConfig {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Label,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Message
    )
    Stop-Plasticine ($Label + ': ' + $Message)
}

function Assert-PlasticineConfigFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $item = Get-PlasticineItem $Path
    if (-not $item) { return $false }
    if ($item.PSIsContainer -or (Test-PlasticineReparsePoint $item)) {
        Stop-PlasticineConfig -Label $Label -Message "$Path must be a regular file."
    }
    return $true
}

function Assert-PlasticineConfigDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $item = Get-PlasticineItem $Path
    if (-not $item) { return $false }
    if (-not $item.PSIsContainer -or (Test-PlasticineReparsePoint $item)) {
        Stop-PlasticineConfig -Label $Label -Message "$Path must be a regular directory."
    }
    return $true
}

function Read-PlasticineConfigText {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    return [IO.File]::ReadAllText($Path, (Get-PlasticineLatin1Encoding))
}

function Test-PlasticineConfigTextEqual {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Left,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Right
    )
    return [string]::Equals($Left, $Right, [StringComparison]::Ordinal)
}

# The first backup wins per label, mirroring the Unix journal: rerunning apply
# never overwrites the pristine copy with an already-managed file.
function Save-PlasticineConfigBackup {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$BackupDirectory,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    Assert-PlasticineConfigDirectory -Path $BackupDirectory -Label $Label | Out-Null
    Assert-PlasticineConfigDirectory -Path (Split-Path -Parent $BackupDirectory) -Label $Label | Out-Null
    if (-not (Get-PlasticineItem $BackupDirectory)) {
        New-Item -ItemType Directory -Path $BackupDirectory -Force -ErrorAction Stop | Out-Null
        Set-PlasticineOwnerOnlyAcl -Path $BackupDirectory
    }
    $backupPath = Join-Path $BackupDirectory ($Label + '.plasticine-backup')
    if (Test-Path -LiteralPath $backupPath -PathType Leaf) { return $backupPath }
    Copy-Item -LiteralPath $Path -Destination $backupPath -ErrorAction Stop
    Set-PlasticineOwnerOnlyAcl -Path $backupPath
    return $backupPath
}

# Publish exact bytes: a same-directory staging file is hashed back before the
# target is replaced, so a partially written candidate never goes live.
function Publish-PlasticineConfigFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$Label,
        [switch]$OwnerOnly,
        [string]$BackupDirectory,
        [AllowEmptyString()][string]$OriginalText
    )
    $null = Assert-PlasticineAbsolutePath -Path $Path -Name 'configuration target'
    $existed = Assert-PlasticineConfigFile -Path $Path -Label $Label
    if ($existed -and (Test-PlasticineConfigTextEqual (Read-PlasticineConfigText $Path) $Text)) {
        if ($OwnerOnly) { Set-PlasticineOwnerOnlyAcl -Path $Path }
        return $false
    }
    $parent = Split-Path -Parent $Path
    if (-not (Get-PlasticineItem $parent)) {
        New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
    }
    Assert-PlasticineConfigDirectory -Path $parent -Label $Label | Out-Null
    if ($BackupDirectory -and $existed) {
        $null = Save-PlasticineConfigBackup -Path $Path -BackupDirectory $BackupDirectory -Label $Label
    }
    $leaf = Split-Path -Leaf $Path
    $stage = Join-Path $parent ('.' + $leaf + '.plasticine-' + [IO.Path]::GetRandomFileName())
    try {
        [IO.File]::WriteAllText($stage, $Text, (Get-PlasticineLatin1Encoding))
        if ($OwnerOnly) { Set-PlasticineOwnerOnlyAcl -Path $stage }
        if ($existed) {
            # The bytes that produced the candidate must still be the bytes on
            # disk; otherwise another writer (or the Owner) won the race.
            if (-not (Test-PlasticineConfigTextEqual (Read-PlasticineConfigText $Path) $OriginalText)) {
                Stop-PlasticineConfig -Label $Label -Message "$Path changed during apply; retry."
            }
            [IO.File]::Replace($stage, $Path, [NullString]::Value)
        } else {
            if (Test-Path -LiteralPath $Path) {
                Stop-PlasticineConfig -Label $Label -Message "$Path appeared during apply; left untouched."
            }
            Publish-PlasticineNewFile -Candidate $stage -Target $Path
        }
    } finally {
        if (Get-PlasticineItem $stage) { Remove-Item -LiteralPath $stage -Force -ErrorAction SilentlyContinue }
    }
    return $true
}

# Compose a candidate from the current bytes with a caller supplied transform;
# the transform runs on the Latin1 string so every untouched byte survives.
function New-PlasticineConfigCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][scriptblock]$Transform
    )
    $current = Read-PlasticineConfigText $Path
    return [string](& $Transform $current)
}
