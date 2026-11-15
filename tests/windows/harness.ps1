# Shared harness for the Windows suites. Every suite is started by
# scripts/run-test.ps1 as its own `powershell -File tests/windows/<suite>.ps1`
# process, runs in a disposable root under the isolated TEMP, and fails through
# a non-zero exit code with the diagnostic on stderr.

$ErrorActionPreference = 'Stop'

$PlasticineTestRepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# scripts/run-test.ps1 exports the suite name it was given, so failure messages
# name the suite even before the suite narrows $PlasticineTestName itself.
$PlasticineTestSuite = $env:PLASTICINE_TEST_SUITE
if (-not $PlasticineTestSuite) { $PlasticineTestSuite = 'windows' }
$PlasticineTestName = 'windows ' + $PlasticineTestSuite
$PlasticineTestSafeSuite = $PlasticineTestSuite -replace '[^A-Za-z0-9_.-]', '-'

$tempBase = $env:TEMP
if (-not $tempBase) { $tempBase = [IO.Path]::GetTempPath() }
if (-not (Test-Path -LiteralPath $tempBase)) {
    New-Item -ItemType Directory -Path $tempBase -Force -ErrorAction Stop | Out-Null
}
$PlasticineTestRoot = [IO.Path]::GetFullPath((Join-Path $tempBase `
    ('plasticine-windows-test.' + $PlasticineTestSafeSuite + '.' + [IO.Path]::GetRandomFileName())))
New-Item -ItemType Directory -Path $PlasticineTestRoot -ErrorAction Stop | Out-Null

# A failure throws, which the suite turns into exit code 1 through its own
# `catch`/`Stop-Test`; nothing may report success without Complete-Test.
function Fail {
    param([Parameter(Mandatory = $true)][string]$Message)
    throw "$PlasticineTestName tests: $Message"
}

function Stop-Test {
    param([Parameter(Mandatory = $true)][string]$Message)
    [Console]::Error.WriteLine($Message)
    exit 1
}

function Assert-True {
    param([bool]$Condition, [Parameter(Mandatory = $true)][string]$Message)
    if (-not $Condition) { Fail $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [Parameter(Mandatory = $true)][string]$Message)
    if ($Expected -ne $Actual) { Fail "$Message (expected '$Expected', observed '$Actual')" }
}

function New-TestDirectory {
    param([Parameter(Mandatory = $true)][string]$Name)
    $path = Join-Path $PlasticineTestRoot $Name
    New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop | Out-Null
    return $path
}

# Expected failures must not leak their diagnostics into the suite output.
function Assert-Throws {
    param([Parameter(Mandatory = $true)][scriptblock]$Body, [Parameter(Mandatory = $true)][string]$Message)
    $captured = New-Object IO.StringWriter
    $previous = [Console]::Error
    [Console]::SetError($captured)
    $threw = $false
    try {
        & $Body
    } catch {
        $threw = $true
    } finally {
        [Console]::SetError($previous)
    }
    if (-not $threw) { Fail $Message }
    return $captured.ToString()
}

function Assert-ExitCode {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [int]$Expected = 0,
        [Parameter(Mandatory = $true)][string]$Message
    )
    Assert-Equal $Expected $Result.ExitCode $Message
}

function New-TestStub {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Version,
        [switch]$Unhealthy
    )
    $body = if ($Unhealthy) { 'Environment.Exit(9);' }
    else { 'Console.WriteLine("chezmoi version v' + $Version + '"); return;' }
    $source = @"
using System;
class Program {
    static void Main(string[] args) {
        if (args.Length > 0 && args[0] == "--version") { $body }
        Environment.Exit(9);
    }
}
"@
    Add-Type -OutputAssembly $Path -OutputType ConsoleApplication -TypeDefinition $source -ErrorAction Stop
}

function New-TestZip {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$File,
        [string[]]$ExtraEntry
    )
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
    Compress-Archive -LiteralPath $File -DestinationPath $Path -ErrorAction Stop
    if ($ExtraEntry) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Update)
        try {
            foreach ($name in $ExtraEntry) {
                $entry = $zip.CreateEntry($name)
                $stream = $entry.Open()
                try {
                    $bytes = [Text.Encoding]::UTF8.GetBytes('payload')
                    $stream.Write($bytes, 0, $bytes.Length)
                } finally { $stream.Dispose() }
            }
        } finally { $zip.Dispose() }
    }
}

function Complete-Test {
    param([Parameter(Mandatory = $true)][string]$Message)
    $global:PlasticineTestCompleted = $true
    [Console]::Out.WriteLine($Message)
}

# The libraries write diagnostics straight to the process streams, so a scenario
# captures both of them together with the returned value and the failure flag.
function Invoke-TestCapture {
    param([Parameter(Mandatory = $true)][scriptblock]$Body)
    $out = New-Object IO.StringWriter
    $err = New-Object IO.StringWriter
    $previousOut = [Console]::Out
    $previousError = [Console]::Error
    [Console]::SetOut($out)
    [Console]::SetError($err)
    $threw = $false
    $value = $null
    $message = ''
    try {
        $value = & $Body
    } catch {
        $threw = $true
        $message = $_.Exception.Message
    } finally {
        [Console]::SetOut($previousOut)
        [Console]::SetError($previousError)
    }
    return [pscustomobject]@{
        Output  = $out.ToString()
        Error   = $err.ToString()
        Threw   = $threw
        Value   = $value
        Message = $message
    }
}

# ProcessStartInfo.Arguments is a single string, so each argument needs the
# quoting rules the C runtime applies when it splits a command line.
function ConvertTo-TestArgument {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
    if ($Value.Length -eq 0) { return '""' }
    $needsQuoting = $false
    for ($index = 0; $index -lt $Value.Length; $index++) {
        if ([char]::IsWhiteSpace($Value[$index]) -or $Value[$index] -eq '"') {
            $needsQuoting = $true
            break
        }
    }
    if (-not $needsQuoting) { return $Value }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    for ($index = 0; $index -lt $Value.Length; $index++) {
        $character = $Value[$index]
        if ($character -eq '\') {
            $backslashes++
            continue
        }
        if ($character -eq '"') {
            # A quote inside a quoted argument is preceded by 2n + 1 backslashes.
            [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
            [void]$builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append(('\' * $backslashes))
            $backslashes = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) { [void]$builder.Append(('\' * ($backslashes * 2))) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Stop-TestProcessTree {
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process)
    $systemRoot = $env:SystemRoot
    if (-not $systemRoot) { $systemRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows) }
    $taskkill = Join-Path $systemRoot 'System32\taskkill.exe'
    if (Test-Path -LiteralPath $taskkill -PathType Leaf) {
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $null = & $taskkill /PID $Process.Id /T /F 2>&1
        } catch {
        } finally {
            $ErrorActionPreference = $previousPreference
        }
    }
    try {
        if (-not $Process.HasExited) { $Process.Kill() }
    } catch {
    }
    try { $null = $Process.WaitForExit(5000) } catch { }
}

# Runs one child process with both streams captured and a hard timeout, and
# reports its exit code. Environment entries with a $null value are removed
# from the inherited block.
function Invoke-TestProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [hashtable]$Environment = @{},
        [string]$WorkingDirectory = '',
        [int]$TimeoutSeconds = 300
    )
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = (@(@($ArgumentList) | ForEach-Object { ConvertTo-TestArgument ([string]$_) }) -join ' ')
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    if ($WorkingDirectory) { $startInfo.WorkingDirectory = $WorkingDirectory }
    foreach ($name in $Environment.Keys) {
        $value = $Environment[$name]
        if ($null -eq $value) { [void]$startInfo.EnvironmentVariables.Remove([string]$name) }
        else { $startInfo.EnvironmentVariables[[string]$name] = [string]$value }
    }
    $process = $null
    try {
        $process = [System.Diagnostics.Process]::Start($startInfo)
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $exited = $process.WaitForExit($TimeoutSeconds * 1000)
        $timedOut = $false
        if ($exited) {
            $process.WaitForExit()
            $process.Refresh()
        } else {
            $timedOut = $true
            Stop-TestProcessTree -Process $process
        }
        $output = ''
        $error = ''
        if ($outputTask.Wait(5000) -and $errorTask.Wait(5000)) {
            $output = $outputTask.Result
            $error = $errorTask.Result
        }
        $exitCode = $null
        if (-not $timedOut) { $exitCode = $process.ExitCode }
        return [pscustomobject]@{
            FilePath = $FilePath
            ExitCode = $exitCode
            TimedOut = $timedOut
            Output   = [string]$output
            Error    = [string]$error
        }
    } finally {
        if ($process) {
            try { $process.Dispose() } catch { }
        }
    }
}

# Runs another PowerShell script in a child host (for installer-level and
# command-line scenarios) and returns { ExitCode, Output, Error, TimedOut }.
function Invoke-TestScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$ArgumentList = @(),
        [hashtable]$Environment = @{},
        [string]$WorkingDirectory = '',
        [int]$TimeoutSeconds = 300
    )
    $hostName = 'powershell.exe'
    if ($PSVersionTable.PSEdition -eq 'Core') { $hostName = 'pwsh.exe' }
    $hostExe = Join-Path $PSHOME $hostName
    if (-not (Test-Path -LiteralPath $hostExe -PathType Leaf)) {
        Fail "the current PowerShell host was not found: $hostExe"
    }
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Path) + @($ArgumentList)
    return Invoke-TestProcess -FilePath $hostExe -ArgumentList $arguments -Environment $Environment `
        -WorkingDirectory $WorkingDirectory -TimeoutSeconds $TimeoutSeconds
}
