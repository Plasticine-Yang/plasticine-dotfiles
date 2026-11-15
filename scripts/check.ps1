# Windows equivalent of scripts/check.sh: discover the tests/windows suites,
# verify their dependencies, then run each one through scripts/run-test.ps1 in an
# isolated environment. No POSIX shell, no host PATH and no real HOME is used.

[CmdletBinding()]
param(
    [Parameter(Position = 0)][string[]]$Suite = @(),
    [switch]$All,
    [switch]$Help,
    [ValidateRange(1, 86400)][int]$TimeoutSeconds = 180,
    [string]$PowerShell = ''
)

$ErrorActionPreference = 'Stop'

$repoDir = Split-Path -Parent $PSScriptRoot
$testsDir = Join-Path $repoDir 'tests\windows'
$runnerPath = Join-Path $PSScriptRoot 'run-test.ps1'

function Write-CheckError {
    param([Parameter(Mandatory = $true)][string]$Message)
    [Console]::Error.WriteLine($Message)
}

function Get-CheckSuiteNames {
    if (-not (Test-Path -LiteralPath $testsDir -PathType Container)) { return @() }
    $names = @()
    foreach ($item in (Get-ChildItem -LiteralPath $testsDir -Filter '*.ps1' -ErrorAction Stop)) {
        if ($item.PSIsContainer) { continue }
        if ($item.BaseName -eq 'harness') { continue }
        $names += $item.BaseName
    }
    return @($names | Sort-Object -Property Name)
}

function Show-CheckUsage {
    param([string[]]$KnownSuite)
    [Console]::Out.WriteLine('usage: scripts/check.ps1 [-All | [-Suite] <suite> [<suite> ...]] [-TimeoutSeconds <seconds>] [-PowerShell <path>] [-Help]')
    [Console]::Out.WriteLine('suites: ' + ($KnownSuite -join ' '))
}

# Every suite shares one entry contract: it dot-sources tests/windows/harness.ps1
# and reports success through Complete-Test, while failures leave the process
# with a non-zero exit code. A file that breaks the contract is a hard error, so
# a malformed suite can never be silently skipped.
function Test-CheckSuiteContract {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $content = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ($content -notmatch '(?m)^\s*\.\s+.*harness\.ps1') {
        Write-CheckError "check: test suite '$Name' does not follow the suite entry contract: $Path must dot-source tests/windows/harness.ps1"
        return $false
    }
    if ($content -notmatch '\bComplete-Test\b') {
        Write-CheckError "check: test suite '$Name' does not follow the suite entry contract: $Path must report success with Complete-Test"
        return $false
    }
    return $true
}

# Resolve a dependency to an absolute path without assuming the operator keeps
# a tidy PATH: the resolved directory is the only non-system PATH entry the
# suites receive.
function Resolve-CheckExecutable {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Candidate)
    if (-not $Candidate) { return $null }
    if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
        return (Resolve-Path -LiteralPath $Candidate).ProviderPath
    }
    $command = Get-Command -Name $Candidate -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) { return $command.Source }
    return $null
}

$allSuites = @(Get-CheckSuiteNames)

if ($Help) {
    Show-CheckUsage $allSuites
    exit 0
}
$Suite = @($Suite | Where-Object { -not [string]::IsNullOrEmpty($_) })
if ($All -and $Suite.Count -gt 0) {
    Write-CheckError '-All takes no additional suites'
    exit 2
}
if (-not $All -and $Suite.Count -eq 0) { $All = $true }

$selectedSuites = @()
if ($All) {
    $selectedSuites = @($allSuites)
} else {
    foreach ($name in $Suite) {
        if (-not ($allSuites -contains $name)) {
            Write-CheckError "unknown test suite: $name"
            exit 2
        }
        $selectedSuites += $name
    }
}
if ($selectedSuites.Count -eq 0) {
    Write-CheckError "no Windows test suites found in $testsDir"
    exit 1
}

$suitePaths = @{}
foreach ($name in $allSuites) { $suitePaths[$name] = Join-Path $testsDir ($name + '.ps1') }
if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) {
    Write-CheckError "missing check dependency: test runner ($runnerPath)"
    exit 1
}
$malformedSuites = @()
foreach ($name in $selectedSuites) {
    if (-not (Test-CheckSuiteContract -Name $name -Path $suitePaths[$name])) {
        $malformedSuites += $name
    }
}
if ($malformedSuites.Count -gt 0) {
    Write-CheckError "check: refusing to run malformed suite(s): $($malformedSuites -join ', ')"
    exit 1
}

# Every suite shares the same base dependency: the fixtures build disposable Git
# repositories with the resolved git, never with a tool shim from the operator.
$requiredTools = @('git')
$toolDirectories = @()
$missing = $false
foreach ($tool in $requiredTools) {
    $candidate = $tool
    if ($tool -eq 'git' -and $env:GIT_BIN) { $candidate = $env:GIT_BIN }
    $resolved = Resolve-CheckExecutable $candidate
    if (-not $resolved) {
        Write-CheckError "missing check dependency: $tool ($candidate)"
        $missing = $true
        continue
    }
    $toolDirectory = Split-Path -Parent $resolved
    if (-not ($toolDirectories -contains $toolDirectory)) { $toolDirectories += $toolDirectory }
}
if ($missing) { exit 1 }

$systemRoot = $env:SystemRoot
if (-not $systemRoot) { $systemRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows) }
if (-not $PowerShell) {
    $PowerShell = Join-Path $systemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
}
$interpreter = Resolve-CheckExecutable $PowerShell
if (-not $interpreter) {
    Write-CheckError "missing check dependency: Windows PowerShell ($PowerShell)"
    exit 1
}

# Disposable run root, mirroring .agent-tmp/checks in scripts/check.sh.
$taskParent = Join-Path $repoDir '.agent-tmp\checks'
if (-not (Test-Path -LiteralPath $taskParent -PathType Container)) {
    New-Item -ItemType Directory -Path $taskParent -Force -ErrorAction Stop | Out-Null
}
$taskRoot = Join-Path $taskParent ('run.' + [IO.Path]::GetRandomFileName())
$binDir = Join-Path $taskRoot 'bin'
$homeDir = Join-Path $taskRoot 'home'
$tempDir = Join-Path $taskRoot 'tmp'
$appDataDir = Join-Path $homeDir 'AppData\Roaming'
$localAppDataDir = Join-Path $homeDir 'AppData\Local'
# A real profile always carries Documents, and Windows derives both $PROFILE and
# the Known Folder lookup from it. Without it an isolated home makes every
# profile path resolve to nothing, which is an artefact of the run root rather
# than a defect the suites are meant to observe.
$documentsDir = Join-Path $homeDir 'Documents'
foreach ($directory in @($binDir, $homeDir, $documentsDir, $tempDir, $appDataDir, $localAppDataDir)) {
    New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
}

$isolatedNames = @('PATH', 'HOME', 'USERPROFILE', 'APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'GIT_CONFIG_GLOBAL')
$savedEnvironment = @{}
foreach ($name in $isolatedNames) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

$systemDirectories = @(
    (Join-Path $systemRoot 'System32'),
    $systemRoot,
    (Join-Path $systemRoot 'System32\WindowsPowerShell\v1.0')
)
$isolatedPath = (@($binDir) + $toolDirectories + $systemDirectories) -join ';'

$passedSuites = @()
$failedSuites = @()
$startedAt = [DateTime]::UtcNow
try {
    [Environment]::SetEnvironmentVariable('PATH', $isolatedPath, 'Process')
    [Environment]::SetEnvironmentVariable('HOME', $homeDir, 'Process')
    [Environment]::SetEnvironmentVariable('USERPROFILE', $homeDir, 'Process')
    [Environment]::SetEnvironmentVariable('APPDATA', $appDataDir, 'Process')
    [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $localAppDataDir, 'Process')
    [Environment]::SetEnvironmentVariable('TEMP', $tempDir, 'Process')
    [Environment]::SetEnvironmentVariable('TMP', $tempDir, 'Process')
    [Environment]::SetEnvironmentVariable('GIT_CONFIG_GLOBAL', (Join-Path $homeDir '.gitconfig'), 'Process')

    foreach ($name in $selectedSuites) {
        $suitePath = $suitePaths[$name]
        $runnerParameters = @{
            TimeoutSeconds = $TimeoutSeconds
            TestName       = $name
            FilePath       = $interpreter
            Argument       = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $suitePath)
        }
        $status = 1
        try {
            & $runnerPath @runnerParameters
            $status = $LASTEXITCODE
        } catch {
            Write-CheckError "check: could not run the $name suite: $($_.Exception.Message)"
        }
        if ($status -eq 0) { $passedSuites += $name } else { $failedSuites += $name }
    }
} finally {
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
    Remove-Item -LiteralPath $taskRoot -Recurse -Force -ErrorAction SilentlyContinue
}
$elapsed = [int]([DateTime]::UtcNow - $startedAt).TotalSeconds

if ($failedSuites.Count -eq 0) {
    [Console]::Out.WriteLine("check: $($passedSuites.Count)/$($selectedSuites.Count) Windows suites passed (${elapsed}s): $($passedSuites -join ' ')")
    exit 0
}
Write-CheckError "check: $($passedSuites.Count)/$($selectedSuites.Count) Windows suites passed; failed: $($failedSuites -join ', ')"
exit 1
