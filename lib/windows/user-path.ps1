# Only the user-level PATH is touched. The registry value kind is preserved so
# existing %VAR% entries keep expanding, and existing entries keep their order.

if (-not (Get-Command Write-PlasticineLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'common.ps1')
}
if (Get-Command Get-PlasticineUserPath -ErrorAction SilentlyContinue) { return }

$PlasticineUserEnvironmentSubKey = 'Environment'
$PlasticineUserPathLengthLimit = 2047

function Get-PlasticineUserPath {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($PlasticineUserEnvironmentSubKey)
    if (-not $key) { return '' }
    try {
        return [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    } finally {
        $key.Dispose()
    }
}

function Get-PlasticineUserPathValueKind {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($PlasticineUserEnvironmentSubKey)
    if (-not $key) { return [Microsoft.Win32.RegistryValueKind]::ExpandString }
    try {
        try { return $key.GetValueKind('Path') } catch { return [Microsoft.Win32.RegistryValueKind]::ExpandString }
    } finally {
        $key.Dispose()
    }
}

# One comparison key for both forms: quoted entries, %VAR% entries and entries
# with a trailing separator must all match their normalised absolute value.
function Get-PlasticineUserPathComparisonKey {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Entry)
    $value = $Entry.Trim().Trim('"').Trim()
    if ($value -match '%[^%]+%') {
        try { $value = [Environment]::ExpandEnvironmentVariables($value) } catch { }
    }
    try { $value = [IO.Path]::GetFullPath($value) } catch { }
    return $value.TrimEnd('\').ToLowerInvariant()
}

# A %VAR% entry is appended verbatim so it keeps expanding, but its expanded
# form must still be an absolute directory path; quoting is tolerated for
# comparison and validation only and never copied into the registry value.
function Get-PlasticineExpandedUserPathEntry {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Directory)
    $value = $Directory.Trim().Trim('"').Trim()
    if ($value -match '%[^%]+%') {
        try { return [Environment]::ExpandEnvironmentVariables($value) } catch { }
    }
    return $value
}

function Resolve-PlasticineUserPathAdditionForRaw {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Raw,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Directory
    )
    $wanted = Get-PlasticineUserPathComparisonKey -Entry $Directory
    foreach ($entry in ($Raw -split ';')) {
        if ((Get-PlasticineUserPathComparisonKey -Entry $entry) -eq $wanted) { return $null }
    }
    if ($Raw -eq '') { return $Directory }
    if ($Raw.EndsWith(';')) { return $Raw + $Directory }
    return $Raw + ';' + $Directory
}

function Resolve-PlasticineUserPathAddition {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Directory)
    $null = Assert-PlasticineAbsolutePath -Path (Get-PlasticineExpandedUserPathEntry -Directory $Directory) -Name 'user PATH entry'
    return (Resolve-PlasticineUserPathAdditionForRaw -Raw (Get-PlasticineUserPath) -Directory $Directory)
}

# Save the value that was present before the first managed write. The first
# backup wins, so an installer that runs twice keeps the pristine user PATH.
function Backup-PlasticineUserPath {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$BackupDirectory)
    $null = Assert-PlasticineAbsolutePath -Path $BackupDirectory -Name 'user PATH backup directory'
    if (-not (Get-PlasticineItem $BackupDirectory)) {
        New-Item -ItemType Directory -Path $BackupDirectory -ErrorAction Stop | Out-Null
    }
    Assert-PlasticineRealDirectory $BackupDirectory
    $valueFile = Join-Path $BackupDirectory 'user-path.txt'
    if (-not (Test-Path -LiteralPath $valueFile)) {
        [IO.File]::WriteAllText($valueFile, (Get-PlasticineUserPath))
        [IO.File]::WriteAllText((Join-Path $BackupDirectory 'user-path.kind'), (Get-PlasticineUserPathValueKind).ToString())
    }
    return $valueFile
}

# Best-effort WM_SETTINGCHANGE broadcast so running shells and launchers can
# refresh their environment; a refused broadcast never fails the installation.
function Send-PlasticineEnvironmentSettingChange {
    param([ValidateRange(0, 60000)][int]$TimeoutMilliseconds = 5000)
    if (-not ('PlasticineEnvironmentBroadcast' -as [type])) {
        Add-Type -WarningAction SilentlyContinue -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PlasticineEnvironmentBroadcast {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, UIntPtr wParam, string lParam, uint flags, uint timeout, out UIntPtr result);
    public static bool Broadcast(uint timeoutMilliseconds) {
        UIntPtr result;
        return SendMessageTimeout(new IntPtr(0xffff), 0x001A, UIntPtr.Zero, "Environment", 0x0002, timeoutMilliseconds, out result) != IntPtr.Zero;
    }
}
'@
    }
    try {
        return [PlasticineEnvironmentBroadcast]::Broadcast([uint32]$TimeoutMilliseconds)
    } catch {
        return $false
    }
}

function Add-PlasticineUserPathEntry {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Directory,
        [string]$BackupDirectory,
        [switch]$NoBroadcast,
        [switch]$PassThru
    )
    $null = Assert-PlasticineAbsolutePath -Path (Get-PlasticineExpandedUserPathEntry -Directory $Directory) -Name 'user PATH entry'
    $raw = Get-PlasticineUserPath
    $updated = Resolve-PlasticineUserPathAdditionForRaw -Raw $raw -Directory $Directory
    if ($null -eq $updated) {
        if ($PassThru) {
            return [pscustomobject]@{ Changed = $false; PreviousPath = $raw; Path = $raw; BackupFile = $null }
        }
        return $false
    }
    $backupFile = $null
    if ($BackupDirectory) {
        $backupFile = Backup-PlasticineUserPath -BackupDirectory $BackupDirectory
    }
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($PlasticineUserEnvironmentSubKey, $true)
    if (-not $key) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($PlasticineUserEnvironmentSubKey)
    }
    try {
        $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
        try { $kind = $key.GetValueKind('Path') } catch { }
        $key.SetValue('Path', $updated, $kind)
    } finally {
        $key.Dispose()
    }
    if (-not $NoBroadcast) { $null = Send-PlasticineEnvironmentSettingChange }
    $limit = 2047
    if ($PlasticineUserPathLengthLimit) { $limit = [int]$PlasticineUserPathLengthLimit }
    if ($updated.Length -gt $limit) {
        Write-PlasticineLog "user PATH is $($updated.Length) characters long and may exceed the Windows PATH limit of $limit characters; shorten it so every entry keeps working."
    }
    if ($PassThru) {
        return [pscustomobject]@{ Changed = $true; PreviousPath = $raw; Path = $updated; BackupFile = $backupFile }
    }
    return $true
}
