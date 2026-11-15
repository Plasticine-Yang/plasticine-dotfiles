# Coverage for the Windows entry point: option parsing and exit codes, the
# preview/confirm/apply contract, and the conflict report. Every native effect
# runs against a disposable home, a fixture source repository and a stub
# chezmoi, so no real installation happens.

$repoDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'harness.ps1')
$PlasticineTestName = 'windows installer'
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$repoInstall = Join-Path $repoDir 'install.ps1'
$savedPath = $env:PATH
$savedUserProfile = $env:USERPROFILE
$gitDirectory = Split-Path -Parent (Get-Command git -CommandType Application | Select-Object -First 1).Source

function Invoke-Entry {
    param(
        [Parameter(Mandatory = $true)][string]$EntryScript,
        [string[]]$Argument = @(),
        [hashtable]$Environment = @{}
    )
    $stdout = Join-Path $PlasticineTestRoot ([guid]::NewGuid().ToString('N') + '.out')
    $stderr = Join-Path $PlasticineTestRoot ([guid]::NewGuid().ToString('N') + '.err')
    $saved = @{}
    foreach ($name in $Environment.Keys) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, [string]$Environment[$name], 'Process')
    }
    try {
        $argumentLine = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $EntryScript) + $Argument
        $process = Start-Process -FilePath $windowsPowerShell -ArgumentList $argumentLine -Wait -PassThru `
            -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $output = ''
        $errorText = ''
        if (Test-Path -LiteralPath $stdout) { $output = [IO.File]::ReadAllText($stdout) }
        if (Test-Path -LiteralPath $stderr) { $errorText = [IO.File]::ReadAllText($stderr) }
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $output; Error = $errorText }
    } finally {
        foreach ($name in $saved.Keys) {
            [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process')
        }
    }
}

function New-ChezmoiStub {
    param([Parameter(Mandatory = $true)][string]$Path)
    $source = @'
using System;
using System.Collections.Generic;
using System.IO;
public class Program {
    static int Main(string[] args) {
        var log = Environment.GetEnvironmentVariable("PLASTICINE_TEST_CHEZMOI_LOG");
        if (log != null) { File.AppendAllText(log, string.Join(" ", args) + "\n"); }
        var list = new List<string>(args);
        if (list.Contains("--version")) { Console.WriteLine("chezmoi version v2.72.1"); return 0; }
        int configIndex = list.IndexOf("-c");
        if (list.Contains("init")) {
            if (configIndex >= 0 && configIndex + 1 < list.Count) {
                var selected = Environment.GetEnvironmentVariable("PLASTICINE_TOOLS");
                var tools = string.IsNullOrWhiteSpace(selected) ? new[] { "npmrc" } : selected.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
                var quoted = new List<string>();
                foreach (var tool in tools) { quoted.Add("\"" + tool + "\""); }
                File.WriteAllText(list[configIndex + 1], "tools = [" + string.Join(", ", quoted) + "]\n");
            }
            return 0;
        }
        if (list.Contains("apply")) {
            var code = Environment.GetEnvironmentVariable("PLASTICINE_TEST_APPLY_EXIT");
            int parsed;
            return int.TryParse(code, out parsed) ? parsed : 0;
        }
        if (list.Contains("status")) {
            Console.WriteLine(" M .npmrc");
            Console.WriteLine("R  .gitconfig");
            return 0;
        }
        if (list.Contains("diff")) { Console.WriteLine("diff --git a/.npmrc b/.npmrc"); return 0; }
        return 0;
    }
}
'@
    Add-Type -OutputAssembly $Path -OutputType ConsoleApplication -TypeDefinition $source -ErrorAction Stop
}

# The fixture root mirrors a source checkout: a real install.ps1 plus the real
# shared library, with one stub Feature provider that only records its calls.
function New-InstallerFixture {
    param([Parameter(Mandatory = $true)][string]$Name)
    $root = New-TestDirectory $Name
    $library = Join-Path $root 'lib\windows'
    New-Item -ItemType Directory -Path $library -Force | Out-Null
    Copy-Item -LiteralPath $repoInstall -Destination (Join-Path $root 'install.ps1') -Force
    # Mirror the real library directory (except the Feature providers, which the
    # fixture replaces with one recording stub), so a new installer module can
    # never be missing from the fixture without failing here.
    Get-ChildItem -LiteralPath (Join-Path $repoDir 'lib\windows') -Filter '*.ps1' |
        Where-Object { $_.Name -notlike 'feature-*' } |
        Copy-Item -Destination $library -Force
    $stub = @'
$PlasticineTestFeatureLog = $env:PLASTICINE_TEST_FEATURE_LOG
function Add-TestFeatureLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    if ($PlasticineTestFeatureLog) { Add-Content -LiteralPath $PlasticineTestFeatureLog -Value $Message }
}
function Get-PlasticineNpmrcPlan {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    Add-TestFeatureLog ('plan:' + $HomeDirectory)
    return [pscustomobject]@{ HomeDirectory = $HomeDirectory }
}
function Write-PlasticineNpmrcPreview {
    param([Parameter(Mandatory = $true)]$Plan)
    Add-TestFeatureLog 'preview'
    Write-PlasticineLog 'npmrc: fixture preview'
}
'@
    Set-Content -LiteralPath (Join-Path $library 'feature-npmrc.ps1') -Value $stub -Encoding UTF8
    $caseHome = Join-Path $root 'home'
    New-Item -ItemType Directory -Path $caseHome -Force | Out-Null
    $sourceRepo = Join-Path $root 'source-repo'
    New-Item -ItemType Directory -Path $sourceRepo -Force | Out-Null
    & git -C $sourceRepo init -q -b main
    if ($LASTEXITCODE -ne 0) { throw 'could not initialise the fixture source repository' }
    Set-Content -LiteralPath (Join-Path $sourceRepo '.chezmoi.toml.tmpl') -Value 'sourceDir = "{{ .chezmoi.sourceDir }}"' -NoNewline
    Set-Content -LiteralPath (Join-Path $sourceRepo 'dot_npmrc') -Value 'registry=https://example.invalid/' -NoNewline
    & git -C $sourceRepo add -A
    & git -C $sourceRepo -c user.name=test -c user.email=test@example.com commit -qm fixture
    if ($LASTEXITCODE -ne 0) { throw 'could not commit the fixture source repository' }
    $chezmoi = Join-Path $root 'chezmoi.exe'
    New-ChezmoiStub -Path $chezmoi
    return [pscustomobject]@{
        Root       = $root
        Entry      = (Join-Path $root 'install.ps1')
        Home       = $caseHome
        SourceRepo = $sourceRepo
        Chezmoi    = $chezmoi
        CallsLog   = (Join-Path $root 'chezmoi-calls.log')
        FeatureLog = (Join-Path $root 'feature-calls.log')
    }
}

function New-EntryEnvironment {
    param([Parameter(Mandatory = $true)]$Fixture)
    return @{
        PATH                           = $gitDirectory + ';' + (Join-Path $env:SystemRoot 'System32')
        USERPROFILE                    = $Fixture.Home
        PLASTICINE_CHEZMOI_BIN         = $Fixture.Chezmoi
        PLASTICINE_DOTFILES_REPO_URL   = $Fixture.SourceRepo
        PLASTICINE_LONG_PATHS_ENABLED  = '1'
        PLASTICINE_ELEVATED            = '0'
        PLASTICINE_TEST_CHEZMOI_LOG    = $Fixture.CallsLog
        PLASTICINE_TEST_FEATURE_LOG    = $Fixture.FeatureLog
        PLASTICINE_TOOLS               = ''
    }
}

try {
    # --- Help and usage errors exit with the documented codes. ---
    $run = Invoke-Entry -EntryScript $repoInstall -Argument @('-Help') -Environment @{ PATH = $savedPath }
    Assert-Equal 0 $run.ExitCode 'the help entry point did not exit zero'
    Assert-True ($run.Output -match 'Usage: install\.ps1') 'the help text is missing the usage line'
    Assert-True ($run.Output -match 'Windows does not provide the shell') 'the help text is missing the Windows limits'

    $run = Invoke-Entry -EntryScript $repoInstall -Argument @('--help') -Environment @{ PATH = $savedPath }
    Assert-Equal 0 $run.ExitCode 'the --help alias did not exit zero'

    $run = Invoke-Entry -EntryScript $repoInstall -Argument @('--unknown') -Environment @{ PATH = $savedPath }
    Assert-Equal 2 $run.ExitCode 'an unknown option did not exit with the usage code'
    Assert-True ($run.Error -match 'Unknown option: --unknown') 'the unknown option was not reported'

    $run = Invoke-Entry -EntryScript $repoInstall -Argument @('-Npmrc') -Environment @{ PATH = $savedPath }
    Assert-Equal 2 $run.ExitCode 'a tool option without -Yes did not exit with the usage code'
    Assert-True ($run.Error -match 'Tool options require -Yes') 'the missing -Yes was not reported'

    $run = Invoke-Entry -EntryScript $repoInstall -Argument @('-Yes', '-GithubSsh') -Environment @{ PATH = $savedPath }
    Assert-Equal 2 $run.ExitCode '-GithubSsh without a key did not exit with the usage code'
    Assert-True ($run.Error -match 'GithubSsh') 'the missing SSH key was not reported'

    $run = Invoke-Entry -EntryScript $repoInstall -Argument @('-Yes', '-GithubSshKey', 'key') -Environment @{ PATH = $savedPath }
    Assert-Equal 2 $run.ExitCode 'a GitHub SSH key without -GithubSsh did not exit with the usage code'
    Assert-True ($run.Error -match 'GitHub SSH options require -GithubSsh') 'the orphan SSH key option was not reported'

    # --- A confirmed run clones, previews and applies through the real entry. ---
    $fixture = New-InstallerFixture 'apply'
    $environment = New-EntryEnvironment -Fixture $fixture
    $run = Invoke-Entry -EntryScript $fixture.Entry -Argument @('-Yes', '-Npmrc') -Environment $environment
    Assert-Equal 0 $run.ExitCode "the confirmed install failed: $($run.Error)"
    Assert-True ($run.Output -match 'Selecting tools') 'the install did not run chezmoi init'
    Assert-True ($run.Output -match 'Selected tools: npmrc') 'the selected tool was not reported'
    Assert-True ($run.Output -match 'Previewing npmrc') 'the selected Feature was not previewed'
    Assert-True ($run.Output -match 'Applying changes') 'the install did not apply'
    Assert-True ($run.Output -match 'Done\.') 'the install did not report completion'
    $calls = @(Get-Content -LiteralPath $fixture.CallsLog)
    Assert-True (@($calls | Where-Object { $_ -match ' init' }).Count -eq 1) 'chezmoi init was not called exactly once'
    Assert-True (@($calls | Where-Object { $_ -match ' apply' }).Count -eq 1) 'chezmoi apply was not called exactly once'
    Assert-True (@($calls | Where-Object { $_ -match ' diff' }).Count -eq 1) 'the preview diff was not generated'
    $featureCalls = @(Get-Content -LiteralPath $fixture.FeatureLog)
    Assert-True (@($featureCalls | Where-Object { $_ -match '^plan:' }).Count -eq 1) 'the Feature plan was not requested'
    Assert-True ($featureCalls -contains 'preview') 'the Feature preview was not requested'
    Assert-True (Test-Path -LiteralPath (Join-Path $fixture.Home '.local\share\chezmoi\.git')) 'the fixture source was not cloned'
    $config = Join-Path $fixture.Home '.config\chezmoi\chezmoi.toml'
    Assert-True (Test-Path -LiteralPath $config -PathType Leaf) 'the generated chezmoi config is missing'
    $configAcl = (Get-Acl -LiteralPath $config).Sddl
    Assert-True ($configAcl -match 'D:PAI') "the generated chezmoi config is not owner-only: $configAcl"

    # --- A refused apply reports the conflicting paths and exits non-zero. ---
    $fixture = New-InstallerFixture 'apply-conflict'
    $environment = New-EntryEnvironment -Fixture $fixture
    $environment['PLASTICINE_TEST_APPLY_EXIT'] = '1'
    $run = Invoke-Entry -EntryScript $fixture.Entry -Argument @('-Yes', '-Npmrc') -Environment $environment
    Assert-Equal 1 $run.ExitCode 'a refused apply did not exit non-zero'
    Assert-True ($run.Error -match 'apply did not complete; managed paths that still differ') 'the conflict report was not printed'
    Assert-True ($run.Error -match 'M \.npmrc') 'the conflicting path was not listed'
    Assert-True (-not ($run.Error -match 'R  \.gitconfig')) 'a retained path was reported as a conflict'
    Assert-True ($run.Error -match 'inspect with: chezmoi') 'the recovery guidance was not printed'

    # --- A selected Feature without a Windows provider stops before apply. ---
    $fixture = New-InstallerFixture 'missing-feature'
    $environment = New-EntryEnvironment -Fixture $fixture
    $run = Invoke-Entry -EntryScript $fixture.Entry -Argument @('-Yes', '-Lazygit') -Environment $environment
    Assert-Equal 1 $run.ExitCode 'a selected Feature without a provider did not exit non-zero'
    Assert-True ($run.Error -match 'lazygit') 'the missing Feature provider was not reported'
    $calls = @(Get-Content -LiteralPath $fixture.CallsLog)
    Assert-True (@($calls | Where-Object { $_ -match ' apply' }).Count -eq 0) 'an apply ran without a previewable Feature'

    Complete-Test 'windows installer tests passed'
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
} finally {
    $env:PATH = $savedPath
    $env:USERPROFILE = $savedUserProfile
    Remove-Item -LiteralPath $PlasticineTestRoot -Recurse -Force -ErrorAction SilentlyContinue
}
