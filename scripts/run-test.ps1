# Windows equivalent of scripts/run-test.sh: run one command with a hard
# timeout, print `START test:` / `PASS test:` for the operator, and fail with a
# non-zero exit code. On timeout the complete process tree is terminated so a
# hung suite cannot leak child processes. No POSIX shell is required.

[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$TimeoutSeconds = '',
    [Parameter(Position = 1)][string]$TestName = '',
    [Parameter(Position = 2)][string]$FilePath = '',
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Argument = @(),
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

function Write-TestError {
    param([Parameter(Mandatory = $true)][string]$Message)
    [Console]::Error.WriteLine($Message)
}

function Write-TestUsage {
    Write-TestError 'usage: scripts/run-test.ps1 <timeout-seconds> <test-name> <command> [argument ...]'
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

# A suite can leave grandchildren behind (background helpers, fixture servers),
# so the timeout has to terminate the whole tree, not only the suite leader.
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
            # Fall back to the direct kill below.
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

if ($Help) {
    [Console]::Out.WriteLine('usage: scripts/run-test.ps1 <timeout-seconds> <test-name> <command> [argument ...]')
    exit 0
}
if (-not $TimeoutSeconds -or -not $TestName -or -not $FilePath) {
    Write-TestUsage
    exit 2
}
if ($TimeoutSeconds -notmatch '^[0-9]+$') {
    Write-TestError 'test timeout must be a positive integer'
    exit 2
}
$limit = [int64]0
if (-not [int64]::TryParse($TimeoutSeconds, [ref]$limit) -or $limit -le 0) {
    Write-TestError 'test timeout must be a positive integer'
    exit 2
}

$argumentLine = (@(@($Argument) | ForEach-Object { ConvertTo-TestArgument ([string]$_) }) -join ' ')

# Test fixtures create disposable repositories and must not invoke the
# operator's global hooks or Trace2 sink. Command-scope overrides preserve
# HOME-scoped Git config tests while keeping local and CI execution equivalent.
# NUL is the Windows equivalent of the /dev/null target used by run-test.sh.
# PLASTICINE_TEST_SUITE lets tests/windows/harness.ps1 name the running suite.
$environmentOverrides = [ordered]@{
    GIT_CONFIG_COUNT          = '2'
    GIT_CONFIG_KEY_0          = 'core.hooksPath'
    GIT_CONFIG_VALUE_0        = 'NUL'
    GIT_CONFIG_KEY_1          = 'trace2.eventTarget'
    GIT_CONFIG_VALUE_1        = 'NUL'
    PLASTICINE_TEST_SUITE     = $TestName
}
$savedEnvironment = @{}
foreach ($name in $environmentOverrides.Keys) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

[Console]::Out.WriteLine("START test: $TestName")
$startedAt = [DateTime]::UtcNow
$status = 0
$process = $null
try {
    foreach ($name in $environmentOverrides.Keys) {
        [Environment]::SetEnvironmentVariable($name, [string]$environmentOverrides[$name], 'Process')
    }
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = $argumentLine
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $false
    $startInfo.WorkingDirectory = [IO.Directory]::GetCurrentDirectory()
    try {
        $process = [System.Diagnostics.Process]::Start($startInfo)
    } catch {
        Write-TestError "test command failed to start: $($_.Exception.Message)"
        $status = 127
    }
    if ($process) {
        $timedOut = $false
        while (-not $process.WaitForExit(50)) {
            if (([DateTime]::UtcNow - $startedAt).TotalSeconds -ge $limit) {
                $timedOut = $true
                break
            }
        }
        if ($timedOut) {
            Stop-TestProcessTree -Process $process
            $status = 124
        } else {
            $process.WaitForExit()
            $process.Refresh()
            $status = $process.ExitCode
        }
    }
} finally {
    if ($process) {
        try { $process.Dispose() } catch { }
    }
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
}
$elapsed = [int]([DateTime]::UtcNow - $startedAt).TotalSeconds

switch ($status) {
    0 { [Console]::Out.WriteLine("PASS test: $TestName (${elapsed}s)") }
    124 { Write-TestError "TIMEOUT test: $TestName ($($TimeoutSeconds)s limit)" }
    default { Write-TestError "FAIL test: $TestName (exit $status)" }
}
exit $status
