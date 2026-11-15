# Shared Windows helpers for every Plasticine module.
# Baseline is Windows PowerShell 5.1; PowerShell 7+ syntax is forbidden.
# Every module dot-sources this file before its own definitions, so loading it a
# second time must not reset the seams below.

if (Get-Command Write-PlasticineLog -ErrorAction SilentlyContinue) { return }

$PlasticineCurlCommand = Join-Path $env:SystemRoot 'System32\curl.exe'
$PlasticineDownloadTimeoutSeconds = 600
$PlasticineDownloadConnectTimeoutSeconds = 30
$PlasticineDownloadMaxBytes = 1073741824

# Stop-Plasticine already writes its diagnostic to stderr. The installer needs to
# tell that reported stop apart from an unexpected exception without printing it
# twice, so the exception carries a recognisable type.
if (-not ('PlasticineStopException' -as [type])) {
    Add-Type -WarningAction SilentlyContinue -TypeDefinition @'
public class PlasticineStopException : System.Exception {
    public PlasticineStopException(string message) : base(message) { }
    public string PlasticineMessage { get { return this.Message; } }
}
'@
}

function Write-PlasticineLog {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Message)
    [Console]::Out.WriteLine("plasticine-dotfiles: $Message")
}

function Write-PlasticineError {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Message)
    [Console]::Error.WriteLine("plasticine-dotfiles: $Message")
}

# The message is already on stderr, so a caller that catches this only owes an exit code.
function Stop-Plasticine {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Message)
    Write-PlasticineError $Message
    throw (New-Object PlasticineStopException ($Message))
}

# Path parameters are absolute everywhere in the Windows route; reject anything
# else before it can resolve against the process working directory.
function Assert-PlasticineAbsolutePath {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path,
        [ValidateNotNullOrEmpty()][string]$Name = 'path'
    )
    $rooted = $false
    try { $rooted = [IO.Path]::IsPathRooted($Path) } catch { $rooted = $false }
    if (-not $rooted) {
        Stop-Plasticine "$Name must be absolute: $Path"
    }
    return $Path
}

function Assert-PlasticineWindowsPlatform {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        Stop-Plasticine 'the Windows route requires Windows.'
    }
    $architecture = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $architecture = $env:PROCESSOR_ARCHITEW6432 }
    if ($architecture -ne 'AMD64') {
        Stop-Plasticine "unsupported Windows architecture: $architecture; this release supports x64 only. Use an x64 host, or run the macOS/Linux installer on that platform."
    }
    if ($PSVersionTable.PSVersion -lt [Version]'5.1') {
        Stop-Plasticine "unsupported PowerShell version: $($PSVersionTable.PSVersion); Windows PowerShell 5.1 or newer is required."
    }
}

function Get-PlasticineCommandPath {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Name)
    $command = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) { return $command.Source }
    return $null
}

function Get-PlasticineItem {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path)
    $null = Assert-PlasticineAbsolutePath -Path $Path -Name 'path'
    return Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

function Test-PlasticineReparsePoint {
    param([Parameter(Mandatory = $true)]$Item)
    return [bool]($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Assert-PlasticineRealDirectory {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path)
    $item = Get-PlasticineItem $Path
    if (-not $item -or -not $item.PSIsContainer -or (Test-PlasticineReparsePoint $item)) {
        Stop-Plasticine "not a real directory: $Path"
    }
}

function Assert-PlasticineInstallDestination {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string[]]$Parent,
        [string]$Target
    )
    foreach ($path in $Parent) {
        $null = Assert-PlasticineAbsolutePath -Path $path -Name 'installation parent'
        $item = Get-PlasticineItem $path
        if ($item) {
            if (-not $item.PSIsContainer -or (Test-PlasticineReparsePoint $item)) {
                Stop-Plasticine "installation parent is not a real directory: $path"
            }
        }
    }
    if ($Target) {
        $null = Assert-PlasticineAbsolutePath -Path $Target -Name 'installation target'
        $item = Get-PlasticineItem $Target
        if ($item) {
            if ($item.PSIsContainer -or (Test-PlasticineReparsePoint $item)) {
                Stop-Plasticine "installation target is not a regular file: $Target; left untouched."
            }
        }
    }
}

function New-PlasticineTempDirectory {
    param([ValidateNotNullOrEmpty()][string]$Prefix = 'plasticine')
    $path = Join-Path $env:TEMP ($Prefix + '.' + [IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $path -ErrorAction Stop | Out-Null
    return $path
}

# curl gets a hard connect timeout and a hard total timeout, and the finished
# file must stay under the size cap before a caller may hash and publish it.
function Invoke-PlasticineDownload {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Url,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Destination,
        [string]$FailureMessage,
        [ValidateRange(1, 86400)][int]$TimeoutSeconds = $(if ($PlasticineDownloadTimeoutSeconds) { [int]$PlasticineDownloadTimeoutSeconds } else { 600 }),
        [ValidateRange(1, 86400)][int]$ConnectTimeoutSeconds = $(if ($PlasticineDownloadConnectTimeoutSeconds) { [int]$PlasticineDownloadConnectTimeoutSeconds } else { 30 }),
        [ValidateRange(1, 2147483647)][int]$MaxBytes = $(if ($PlasticineDownloadMaxBytes) { [int]$PlasticineDownloadMaxBytes } else { 1073741824 })
    )
    if (-not $FailureMessage) { $FailureMessage = "download failed: $Url" }
    $null = Assert-PlasticineAbsolutePath -Path $Destination -Name 'download destination'
    $curl = $PlasticineCurlCommand
    if (-not $curl) { $curl = Join-Path $env:SystemRoot 'System32\curl.exe' }
    if (-not (Test-Path -LiteralPath $curl -PathType Leaf)) {
        Stop-Plasticine "missing system curl: $curl"
    }
    & $curl --proto '=https' --proto-redir '=https' --connect-timeout $ConnectTimeoutSeconds --max-time $TimeoutSeconds -fsSL -o $Destination $Url | Out-Null
    if ($LASTEXITCODE -ne 0) {
        if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue }
        Stop-Plasticine $FailureMessage
    }
    $item = Get-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
    if (-not $item -or $item.PSIsContainer) {
        Stop-Plasticine $FailureMessage
    }
    if ($item.Length -gt $MaxBytes) {
        Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
        Stop-Plasticine "$FailureMessage (download exceeded the $MaxBytes-byte size limit)"
    }
}

function Get-PlasticineFileHash {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path)
    $null = Assert-PlasticineAbsolutePath -Path $Path -Name 'hash path'
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

# Archives arrive from the network, so member names are checked before anything is written.
function Expand-PlasticineArchive {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Archive,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Destination,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string[]]$Member
    )
    $null = Assert-PlasticineAbsolutePath -Path $Archive -Name 'archive path'
    $null = Assert-PlasticineAbsolutePath -Path $Destination -Name 'archive destination'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    $observed = @()
    try {
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName
            if ([IO.Path]::IsPathRooted($name) -or $name -match '(^|[\\/])\.\.([\\/]|$)') {
                Stop-Plasticine "archive member escapes the candidate directory: $name"
            }
            $top = ($name -split '[\\/]')[0]
            if ($top -and $observed -notcontains $top) { $observed += $top }
        }
    } finally {
        $zip.Dispose()
    }
    $missing = @($Member | Where-Object { $observed -notcontains $_ })
    $extra = @($observed | Where-Object { $Member -notcontains $_ })
    if ($missing.Count -gt 0 -or $extra.Count -gt 0) {
        Stop-Plasticine "archive members do not match the reviewed layout: expected $($Member -join ', '); observed $($observed -join ', ')"
    }
    Expand-Archive -LiteralPath $Archive -DestinationPath $Destination -Force -ErrorAction Stop
}

function Get-PlasticineExecutableVersion {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path)
    $null = Assert-PlasticineAbsolutePath -Path $Path -Name 'executable path'
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $output = & $Path --version 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    $version = $null
    $seen = 0
    foreach ($line in @($output)) {
        foreach ($token in ([string]$line -split '\s+')) {
            $value = $token -replace '^v', '' -replace '[,;]$', ''
            if ($value -match '^[0-9]+\.[0-9]+\.[0-9]+$') { $seen++; $version = $value }
        }
    }
    if ($seen -eq 1) { return $version }
    return $null
}

function Compare-PlasticineVersion {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Left,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Right
    )
    $a = $Left.Split('.')
    $b = $Right.Split('.')
    for ($i = 0; $i -lt 3; $i++) {
        if ([int]$a[$i] -lt [int]$b[$i]) { return -1 }
        if ([int]$a[$i] -gt [int]$b[$i]) { return 1 }
    }
    return 0
}
