# Coverage for the Windows rust route. The official rustup-init.exe checksum
# sidecar, the candidate installation, the stable toolchain maintenance, reuse,
# refusal, and failure branches all run against offline fixtures: the download
# seam copies fixture files, the two command seams simulate the installer and the
# toolchain install, and the rustup/rustc/proxy stubs are compiled PE files. No
# real network, no real user PATH, no real user home, no real HKCU.

$repoDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'harness.ps1')
$PlasticineTestName = 'windows rust'
. (Join-Path $repoDir 'lib\windows\common.ps1')
. (Join-Path $repoDir 'lib\windows\publish.ps1')
. (Join-Path $repoDir 'lib\windows\acl.ps1')
. (Join-Path $repoDir 'lib\windows\user-path.ps1')
. (Join-Path $repoDir 'lib\windows\features.ps1')
. (Join-Path $repoDir 'lib\windows\feature-rust.ps1')

# The rust route publishes its command directory through the user-level PATH.
# Every write stays inside a disposable registry subkey, and the environment
# broadcast is a no-op so a test process never touches the real desktop.
$savedUserEnvironmentSubKey = $PlasticineUserEnvironmentSubKey
$testUserEnvironmentSubKey = 'Software\PlasticineWindowsTests\' + [guid]::NewGuid().ToString('N')
$script:PlasticineUserEnvironmentSubKey = $testUserEnvironmentSubKey
function Send-PlasticineEnvironmentSettingChange {
    param([ValidateRange(0, 60000)][int]$TimeoutMilliseconds = 5000)
    return $true
}

$callsFile = Join-Path $PlasticineTestRoot 'download-calls'
$runnerFile = Join-Path $PlasticineTestRoot 'runner-calls'
$fixture = New-TestDirectory 'fixture'
$savedPath = $env:PATH
$savedArchitecture = $env:PROCESSOR_ARCHITECTURE
$savedArchitecture6432 = $env:PROCESSOR_ARCHITEW6432
# Every scenario gets a PATH that cannot resolve a rust tool the operator
# happens to have installed, so "missing" and "found" are fixture decisions.
$emptyPath = New-TestDirectory 'empty-path'

function Reset-Calls { Set-Content -LiteralPath $callsFile -Value @() }
function Get-Calls {
    if (Test-Path -LiteralPath $callsFile) { return @(Get-Content -LiteralPath $callsFile) }
    return @()
}
function Reset-Runners { Set-Content -LiteralPath $runnerFile -Value @() }
function Get-Runners {
    if (Test-Path -LiteralPath $runnerFile) { return @(Get-Content -LiteralPath $runnerFile) }
    return @()
}

# The only network seam: record the URL and copy the reviewed fixture bytes.
function Invoke-PlasticineDownload {
    param(
        [string]$Url,
        [string]$Destination,
        [string]$FailureMessage,
        [int]$TimeoutSeconds = 600,
        [int]$ConnectTimeoutSeconds = 30,
        [int]$MaxBytes = 1073741824
    )
    Add-Content -LiteralPath $callsFile -Value $Url
    if ($env:PLASTICINE_TEST_DOWNLOAD_FAIL) { Stop-Plasticine $FailureMessage }
    Copy-Item -LiteralPath (Join-Path $fixture (Split-Path -Leaf $Url)) -Destination $Destination -ErrorAction Stop
}

# The rust command seam replaces only the network-mutating command groups. The
# default provider still verifies the candidate with compiled stubs, so the
# success path exercises the real plan -> init -> verify -> toolchain -> publish
# sequence without running the official installer or touching the network.
$script:runnerLog = $runnerFile
$script:rustHostTuple = 'x86_64-pc-windows-gnu'
$script:initRunnerMode = 'ok'
$script:toolchainRunnerMode = 'ok'
$script:lastInitSetup = $null
$script:lastToolchainSetup = $null
$script:rustupStubPath = ''
$script:rustupNewerStubPath = ''
$script:rustupMsvcStubPath = ''
$script:rustupInitStubPath = ''
$script:rustProxyStubPath = ''
$script:rustcStubPath = ''
$script:cargoStubPath = ''
$script:rustfmtStubPath = ''
$script:clippyStubPath = ''

$script:PlasticineRustInitRunner = {
    param($Setup)
    Add-Content -LiteralPath $script:runnerLog -Value ('init:' + (Split-Path -Leaf $Setup.RustupInit))
    $script:lastInitSetup = $Setup
    if ($script:initRunnerMode -eq 'fail') {
        Stop-PlasticineRust 'simulated rustup-init failure; partial native effects were retained in the candidate directory and nothing was published.'
    }
    if ($script:initRunnerMode -eq 'broken') { return }
    $bin = Join-Path $Setup.CargoHome 'bin'
    New-Item -ItemType Directory -Path $bin -Force -ErrorAction Stop | Out-Null
    Copy-Item -LiteralPath $script:rustupStubPath -Destination (Join-Path $bin 'rustup.exe') -Force
    Copy-Item -LiteralPath $script:rustcStubPath -Destination (Join-Path $bin 'rustc.exe') -Force
    Copy-Item -LiteralPath $script:cargoStubPath -Destination (Join-Path $bin 'cargo.exe') -Force
    Copy-Item -LiteralPath $script:rustfmtStubPath -Destination (Join-Path $bin 'rustfmt.exe') -Force
    Copy-Item -LiteralPath $script:clippyStubPath -Destination (Join-Path $bin 'clippy-driver.exe') -Force
    foreach ($name in @('rustdoc', 'cargo-fmt', 'cargo-clippy', 'rust-analyzer', 'rust-gdb', 'rust-gdbgui', 'rust-lldb')) {
        Copy-Item -LiteralPath $script:rustProxyStubPath -Destination (Join-Path $bin ($name + '.exe')) -Force
    }
    New-Item -ItemType Directory -Path $Setup.RustupHome -Force -ErrorAction Stop | Out-Null
    Set-Content -LiteralPath (Join-Path $Setup.RustupHome 'settings.toml') -Value @(
        'version = "12"',
        ('default_host_tuple = "' + $script:rustHostTuple + '"'),
        'profile = "minimal"',
        '',
        '[overrides]'
    )
}

$script:PlasticineRustToolchainRunner = {
    param($Setup)
    Add-Content -LiteralPath $script:runnerLog -Value ('toolchain:' + $Setup.Toolchain)
    $script:lastToolchainSetup = $Setup
    if ($script:toolchainRunnerMode -eq 'fail') {
        Stop-PlasticineRust 'simulated stable toolchain installation failure; native effects are retained for retry and no configuration was applied.'
    }
    if ($script:toolchainRunnerMode -eq 'broken') { return }
    $toolchain = Join-Path $Setup.RustupHome ('toolchains\stable-' + $script:rustHostTuple)
    New-Item -ItemType Directory -Path $toolchain -Force -ErrorAction Stop | Out-Null
    Set-Content -LiteralPath (Join-Path $toolchain 'components.ok') -Value 'rustfmt clippy' -NoNewline
}

# MSVC Build Tools are probed only through vswhere in the provider; the suite
# pins the answer so the branch is deterministic on every host.
$script:PlasticineTestMsvc = $false
function Test-PlasticineRustMsvcBuildTools { return [bool]$script:PlasticineTestMsvc }

function New-RustupStub {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Version = '1.29.3',
        [string]$HostTuple = 'x86_64-pc-windows-gnu',
        [switch]$Unhealthy,
        [switch]$NoHost,
        [switch]$RunFail
    )
    $source = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;

class Program {
    const string RustupVersion = "__VERSION__";
    const string HostTuple = "__HOST__";
    static readonly bool ForceUnhealthy = __UNHEALTHY__;
    static readonly bool OmitHost = __NOHOST__;
    static readonly bool FailRun = __RUNFAIL__;

    static string SettingsFile() {
        string home = Environment.GetEnvironmentVariable("RUSTUP_HOME");
        if (String.IsNullOrEmpty(home)) { return null; }
        return Path.Combine(home, "settings.toml");
    }

    static string ReadDefault() {
        string file = SettingsFile();
        if (file == null || !File.Exists(file)) { return ""; }
        foreach (string line in File.ReadAllLines(file)) {
            string trimmed = line.Trim();
            if (trimmed.StartsWith("default_toolchain")) {
                int first = trimmed.IndexOf('"');
                int last = trimmed.LastIndexOf('"');
                if (first >= 0 && last > first) { return trimmed.Substring(first + 1, last - first - 1); }
            }
        }
        return "";
    }

    static void WriteDefault(string name) {
        string file = SettingsFile();
        if (file == null) { return; }
        Directory.CreateDirectory(Path.GetDirectoryName(file));
        List<string> lines = new List<string>();
        bool written = false;
        if (File.Exists(file)) {
            foreach (string line in File.ReadAllLines(file)) {
                if (line.Trim().StartsWith("default_toolchain")) {
                    if (!written) { lines.Add("default_toolchain = \"" + name + "\""); written = true; }
                } else {
                    lines.Add(line);
                }
            }
        }
        if (!written) { lines.Add("default_toolchain = \"" + name + "\""); }
        File.WriteAllLines(file, lines.ToArray());
    }

    static void ClearDefault() {
        string file = SettingsFile();
        if (file == null || !File.Exists(file)) { return; }
        List<string> lines = new List<string>();
        foreach (string line in File.ReadAllLines(file)) {
            if (line.Trim().StartsWith("default_toolchain")) { continue; }
            lines.Add(line);
        }
        File.WriteAllLines(file, lines.ToArray());
    }

    static int Main(string[] args) {
        if (args.Length > 0 && args[0] == "--version") {
            if (ForceUnhealthy) { return 9; }
            Console.WriteLine("rustup " + RustupVersion + " (edbc831ce 2026-11-02)");
            return 0;
        }
        string home = Environment.GetEnvironmentVariable("RUSTUP_HOME");
        string toolchain = null;
        if (!String.IsNullOrEmpty(home)) {
            toolchain = Path.Combine(home, "toolchains", "stable-" + HostTuple);
        }
        bool installed = toolchain != null && Directory.Exists(toolchain);
        if (args.Length == 0) {
            Console.WriteLine("rustup " + RustupVersion);
            return 0;
        }
        if (args[0] == "show") {
            if (!OmitHost) { Console.WriteLine("Default host: " + HostTuple); }
            if (home == null) { home = ""; }
            Console.WriteLine("rustup home:  " + home);
            Console.WriteLine("");
            Console.WriteLine("installed toolchains");
            Console.WriteLine("--------------------");
            if (installed) { Console.WriteLine("stable-" + HostTuple); } else { Console.WriteLine("no installed toolchains"); }
            return 0;
        }
        if (args[0] == "toolchain" && args.Length > 1 && args[1] == "list") {
            if (installed) { Console.WriteLine("stable-" + HostTuple); } else { Console.WriteLine("no installed toolchains"); }
            return 0;
        }
        if (args[0] == "toolchain" && args.Length > 1 && args[1] == "install") {
            if (toolchain == null) { return 1; }
            Directory.CreateDirectory(toolchain);
            File.WriteAllText(Path.Combine(toolchain, "components.ok"), "rustfmt clippy");
            return 0;
        }
        if (args[0] == "default") {
            if (args.Length > 1) {
                if (args[1] == "none") { ClearDefault(); return 0; }
                WriteDefault(args[1] + "-" + HostTuple);
                return 0;
            }
            string current = ReadDefault();
            if (current == "") {
                Console.Error.WriteLine("error: no default toolchain is configured");
                return 1;
            }
            Console.WriteLine(current + " (default)");
            return 0;
        }
        if (args[0] == "component" && args.Length > 1 && args[1] == "list") {
            if (!installed) {
                Console.Error.WriteLine("error: rustup could not choose a version of rustup to run");
                return 1;
            }
            Console.WriteLine("cargo-" + HostTuple);
            Console.WriteLine("rustc-" + HostTuple);
            if (File.Exists(Path.Combine(toolchain, "components.ok"))) {
                Console.WriteLine("rustfmt-" + HostTuple);
                Console.WriteLine("clippy-" + HostTuple);
            }
            return 0;
        }
        if (args[0] == "run" && args.Length > 2) {
            if (!installed || FailRun) {
                Console.Error.WriteLine("error: toolchain 'stable' is not installed");
                return 1;
            }
            string cargo = Environment.GetEnvironmentVariable("CARGO_HOME");
            string command = args[2];
            string executable = null;
            if (!String.IsNullOrEmpty(cargo)) { executable = Path.Combine(cargo, "bin", command + ".exe"); }
            if (executable != null && File.Exists(executable)) {
                ProcessStartInfo start = new ProcessStartInfo(executable, "--version");
                start.UseShellExecute = false;
                start.RedirectStandardOutput = true;
                start.RedirectStandardError = true;
                start.CreateNoWindow = true;
                using (Process process = Process.Start(start)) {
                    string output = process.StandardOutput.ReadToEnd();
                    process.WaitForExit();
                    Console.Write(output);
                    return process.ExitCode;
                }
            }
            Console.WriteLine(command + " 1.85.0 (simulated)");
            return 0;
        }
        Console.WriteLine("rustup " + RustupVersion);
        return 0;
    }
}
'@
    $unhealthyValue = 'false'
    if ($Unhealthy) { $unhealthyValue = 'true' }
    $noHostValue = 'false'
    if ($NoHost) { $noHostValue = 'true' }
    $runFailValue = 'false'
    if ($RunFail) { $runFailValue = 'true' }
    $source = $source.Replace('__VERSION__', $Version).Replace('__HOST__', $HostTuple).
        Replace('__UNHEALTHY__', $unhealthyValue).Replace('__NOHOST__', $noHostValue).Replace('__RUNFAIL__', $runFailValue)
    New-TestExecutable -Path $Path -Source $source
}

function New-RustCommandStub {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$VersionLine)
    $source = @'
using System;

class Program {
    static void Main(string[] args) {
        Console.WriteLine("__LINE__");
        return;
    }
}
'@
    $source = $source.Replace('__LINE__', $VersionLine)
    New-TestExecutable -Path $Path -Source $source
}

function New-Scenario {
    param([Parameter(Mandatory = $true)][string]$Name)
    $scenarioHome = Join-Path (New-TestDirectory $Name) 'home'
    New-Item -ItemType Directory -Path $scenarioHome -ErrorAction Stop | Out-Null
    $env:PATH = $emptyPath
    Reset-Calls
    Reset-Runners
    $script:initRunnerMode = 'ok'
    $script:toolchainRunnerMode = 'ok'
    $script:rustHostTuple = 'x86_64-pc-windows-gnu'
    $script:lastInitSetup = $null
    $script:lastToolchainSetup = $null
    return $scenarioHome
}

function Get-RustCargoHome {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    return Join-Path $HomeDirectory '.local\opt\.cargo'
}
function Get-RustRustupHome {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    return Join-Path $HomeDirectory '.local\opt\.rustup'
}
function Get-RustRustupCommand {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    return Join-Path $HomeDirectory '.local\opt\.cargo\bin\rustup.exe'
}
function Get-RustBinDirectory {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    return Join-Path $HomeDirectory '.local\opt\.cargo\bin'
}

# Seeds an installation that looks exactly like one this route publishes, so
# reuse, maintenance, ownership and refusal decisions are driven by files.
function Add-ManagedRust {
    param(
        [Parameter(Mandatory = $true)][string]$HomeDirectory,
        [Parameter(Mandatory = $true)][string]$RustupStub,
        [string]$HostTuple = 'x86_64-pc-windows-gnu',
        [switch]$StableToolchain,
        [switch]$Components,
        [string]$DefaultToolchain = 'stable'
    )
    $bin = Get-RustBinDirectory -HomeDirectory $HomeDirectory
    New-Item -ItemType Directory -Path $bin -Force -ErrorAction Stop | Out-Null
    Copy-Item -LiteralPath $RustupStub -Destination (Join-Path $bin 'rustup.exe') -Force
    Copy-Item -LiteralPath $script:rustcStubPath -Destination (Join-Path $bin 'rustc.exe') -Force
    Copy-Item -LiteralPath $script:cargoStubPath -Destination (Join-Path $bin 'cargo.exe') -Force
    Copy-Item -LiteralPath $script:rustfmtStubPath -Destination (Join-Path $bin 'rustfmt.exe') -Force
    Copy-Item -LiteralPath $script:clippyStubPath -Destination (Join-Path $bin 'clippy-driver.exe') -Force
    foreach ($name in @('rustdoc', 'cargo-fmt', 'cargo-clippy', 'rust-analyzer', 'rust-gdb', 'rust-gdbgui', 'rust-lldb')) {
        Copy-Item -LiteralPath $script:rustProxyStubPath -Destination (Join-Path $bin ($name + '.exe')) -Force
    }
    $rustupHome = Get-RustRustupHome -HomeDirectory $HomeDirectory
    New-Item -ItemType Directory -Path $rustupHome -Force -ErrorAction Stop | Out-Null
    $settings = @(
        'version = "12"',
        ('default_host_tuple = "' + $HostTuple + '"'),
        'profile = "minimal"',
        '',
        '[overrides]'
    )
    if ($DefaultToolchain -and $DefaultToolchain -ne 'none') {
        $settings += ('default_toolchain = "' + $DefaultToolchain + '-' + $HostTuple + '"')
    }
    Set-Content -LiteralPath (Join-Path $rustupHome 'settings.toml') -Value $settings
    if ($StableToolchain) {
        New-Item -ItemType Directory -Path (Join-Path $rustupHome ('toolchains\stable-' + $HostTuple)) -Force | Out-Null
    }
    if ($Components) {
        Set-Content -LiteralPath (Join-Path (Join-Path $rustupHome ('toolchains\stable-' + $HostTuple)) 'components.ok') `
            -Value 'rustfmt clippy' -NoNewline
    }
}

# Rebuilds the reviewed rustup-init.exe fixture and its official-style sidecar;
# each scenario therefore checks exactly the artifact it exercises offline.
function Set-RustFixture {
    param([string]$SidecarContent = '')
    Copy-Item -LiteralPath $script:rustupInitStubPath -Destination (Join-Path $fixture 'rustup-init.exe') -Force
    if (-not $SidecarContent) {
        $SidecarContent = Get-PlasticineFileHash (Join-Path $fixture 'rustup-init.exe')
    }
    Set-Content -LiteralPath (Join-Path $fixture 'rustup-init.exe.sha256') -Value $SidecarContent -NoNewline
}

function Assert-RustNoNativeHomes {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    Assert-True (-not (Test-Path -LiteralPath (Get-RustCargoHome -HomeDirectory $HomeDirectory))) 'a failed run created the native command directory'
    Assert-True (-not (Test-Path -LiteralPath (Get-RustRustupHome -HomeDirectory $HomeDirectory))) 'a failed run created the native rustup directory'
}

function Assert-RustNoStaging {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    Assert-Equal 0 (@(Get-ChildItem -LiteralPath $HomeDirectory -Force -Filter '.plasticine-rust.*').Count) `
        'a run left a staging directory behind'
}

function Assert-RustPathEntry {
    param(
        [Parameter(Mandatory = $true)][string]$HomeDirectory,
        [switch]$Present
    )
    $bin = (Get-RustBinDirectory -HomeDirectory $HomeDirectory).TrimEnd('\')
    $found = $false
    foreach ($entry in @((Get-PlasticineUserPath) -split ';')) {
        if ($entry.Trim().Trim('"').TrimEnd('\') -ieq $bin) { $found = $true }
    }
    if ($Present) {
        Assert-True $found "the rust command directory is missing from the user PATH: $bin"
    } else {
        Assert-True (-not $found) "the rust command directory reached the user PATH: $bin"
    }
}

$proxyNames = @('rustdoc', 'cargo-fmt', 'cargo-clippy', 'rust-analyzer', 'rust-gdb', 'rust-gdbgui', 'rust-lldb')

try {
    $stubDirectory = New-TestDirectory 'stubs'
    $script:rustupStubPath = Join-Path $stubDirectory 'rustup-gnu.exe'
    New-RustupStub -Path $script:rustupStubPath -Version '1.29.3' -HostTuple 'x86_64-pc-windows-gnu'
    $script:rustupNewerStubPath = Join-Path $stubDirectory 'rustup-newer.exe'
    New-RustupStub -Path $script:rustupNewerStubPath -Version '9.9.9' -HostTuple 'x86_64-pc-windows-gnu'
    $script:rustupMsvcStubPath = Join-Path $stubDirectory 'rustup-msvc.exe'
    New-RustupStub -Path $script:rustupMsvcStubPath -Version '1.29.3' -HostTuple 'x86_64-pc-windows-msvc'
    $script:rustupInitStubPath = Join-Path $stubDirectory 'rustup-init-stub.exe'
    New-RustCommandStub -Path $script:rustupInitStubPath -VersionLine 'rustup-init 1.29.3 (simulated official installer)'
    $script:rustcStubPath = Join-Path $stubDirectory 'rustc.exe'
    New-RustCommandStub -Path $script:rustcStubPath -VersionLine 'rustc 1.85.0 (4d91de4e4 2025-02-17)'
    $script:cargoStubPath = Join-Path $stubDirectory 'cargo.exe'
    New-RustCommandStub -Path $script:cargoStubPath -VersionLine 'cargo 1.85.0 (d73d2caf9 2024-12-31)'
    $script:rustfmtStubPath = Join-Path $stubDirectory 'rustfmt.exe'
    New-RustCommandStub -Path $script:rustfmtStubPath -VersionLine 'rustfmt 1.8.0-stable (4d91de4e4 2025-02-17)'
    $script:clippyStubPath = Join-Path $stubDirectory 'clippy-driver.exe'
    New-RustCommandStub -Path $script:clippyStubPath -VersionLine 'clippy 0.1.85 (4d91de4e4 2025-02-17)'
    $script:rustProxyStubPath = Join-Path $stubDirectory 'rust-proxy.exe'
    New-RustCommandStub -Path $script:rustProxyStubPath -VersionLine 'proxied rust command 1.85.0 (simulated)'
    Set-RustFixture

    # --- The provider is reachable through the feature registry names. ---
    Assert-Equal 'Get-PlasticineRustPlan' (Get-PlasticineFeaturePlanFunction 'rust') 'the rust plan function name is not resolvable'
    Assert-Equal 'Write-PlasticineRustPreview' (Get-PlasticineFeaturePreviewFunction 'rust') 'the rust preview function name is not resolvable'
    Assert-Equal 'Invoke-PlasticineRustPrepare' (Get-PlasticineFeaturePrepareFunction 'rust') 'the rust prepare function name is not resolvable'

    # --- Plan and preview describe the reviewed route without touching state. ---
    $scenarioHome = New-Scenario 'plan'
    $beforePath = Get-PlasticineUserPath
    $plan = Get-PlasticineRustPlan -HomeDirectory $scenarioHome
    Assert-Equal 'x86_64-pc-windows-gnu' $plan.DefaultHost 'the plan lost the settled default host'
    Assert-Equal 'rustup-init.exe' $plan.Asset 'the plan lost the reviewed installer asset name'
    Assert-Equal 'https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-gnu/rustup-init.exe' $plan.AssetUrl `
        'the plan did not pin the official gnu rustup-init.exe URL'
    Assert-Equal ($plan.AssetUrl + '.sha256') $plan.SidecarUrl 'the plan did not pin the official checksum sidecar URL'
    Assert-Equal 'stable' $plan.Toolchain 'the plan lost the stable toolchain baseline'
    Assert-Equal 'minimal' $plan.Profile 'the plan lost the minimal profile baseline'
    Assert-Equal 'rustfmt clippy' (@($plan.Component) -join ' ') 'the plan lost the reviewed component set'
    Assert-Equal 'missing' $plan.Owner 'a missing rustup was reported as owned'
    Assert-True ($null -eq $plan.Observed) 'a missing rustup was reported as observed'
    Assert-True (-not $plan.MsvcDetected) 'the suite MSVC probe was not used by the plan'
    Assert-True $plan.PathMissing 'a fresh user PATH was not reported as missing the command directory'
    Assert-Equal (Get-RustCargoHome -HomeDirectory $scenarioHome) $plan.CargoHome 'the plan did not target the private CARGO_HOME'
    Assert-Equal (Get-RustRustupHome -HomeDirectory $scenarioHome) $plan.RustupHome 'the plan did not target the private RUSTUP_HOME'
    Assert-Equal (Get-RustRustupCommand -HomeDirectory $scenarioHome) $plan.RustupCommand 'the plan did not target the managed rustup.exe'
    $preview = Invoke-TestCapture { Write-PlasticineRustPreview -Plan $plan }
    Assert-True (-not $preview.Threw) "the preview failed: $($preview.Message)"
    Assert-True ($preview.Output -match 'Fixed supported baseline') 'the preview lost the fixed baseline'
    Assert-True ($preview.Output -match 'static\.rust-lang\.org') 'the preview lost the network contract'
    Assert-True ($preview.Output -match 'rustup-init\.exe') 'the preview lost the installer asset'
    Assert-True ($preview.Output -match '--no-modify-path') 'the preview lost --no-modify-path'
    Assert-True ($preview.Output -match '--default-toolchain none') 'the preview lost --default-toolchain none'
    Assert-True ($preview.Output -match '--default-host x86_64-pc-windows-gnu') 'the preview lost the reviewed default host'
    Assert-True ($preview.Output -match '--profile minimal') 'the preview lost the minimal profile'
    Assert-True ($preview.Output -match 'toolchain install stable') 'the preview lost the toolchain install contract'
    Assert-True ($preview.Output -match '--component rustfmt') 'the preview lost the rustfmt component'
    Assert-True ($preview.Output -match '--component clippy') 'the preview lost the clippy component'
    Assert-True ($preview.Output -match '--no-self-update') 'the preview lost the no-self-update contract'
    Assert-True ($preview.Output -match 'trust boundary') 'the preview lost the unversioned asset trust boundary'
    Assert-True ($preview.Output -match 'MSVC Build Tools: not detected') 'the preview did not report the missing MSVC toolchain'
    Assert-True ($preview.Output -match 'Visual Studio') 'the preview lost the MSVC install guidance'
    Assert-True ($preview.Output -match 'user-level PATH') 'the preview lost the PATH contract'
    Assert-True ($preview.Output -match [regex]::Escape($plan.CargoHome)) 'the preview did not name CARGO_HOME'
    Assert-True ($preview.Output -match [regex]::Escape($plan.RustupHome)) 'the preview did not name RUSTUP_HOME'
    Assert-True ($preview.Output -match 'reuse') 'the preview lost the reuse rule'
    Assert-True ($preview.Output -match 'refusal') 'the preview lost the refusal rules'
    Assert-Equal 0 (@(Get-Calls).Count) 'the plan or preview made a download request'
    Assert-Equal 0 (@(Get-Runners).Count) 'the plan or preview ran a preparation command'
    Assert-Equal $beforePath (Get-PlasticineUserPath) 'the plan or preview changed the user PATH'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $scenarioHome '.local'))) 'the plan or preview created native homes'
    Assert-RustNoStaging $scenarioHome

    # --- A missing rustup installs the reviewed installer and the stable toolchain. ---
    $scenarioHome = New-Scenario 'fresh'
    Set-RustFixture
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'rust' -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the fresh rust install failed: $($run.Message)"
    Assert-True ($run.Output -match 'rust: rustup-init installed rustup 1\.29\.3 for host x86_64-pc-windows-gnu') `
        'the fresh install did not verify the installer candidate'
    Assert-True ($run.Output -match 'rust: install completed with rustup 1\.29\.3 and stable host x86_64-pc-windows-gnu') `
        'the fresh install was not reported'
    $calls = @(Get-Calls)
    Assert-Equal 2 $calls.Count 'the fresh install made an unexpected number of downloads'
    Assert-Equal $plan.AssetUrl $calls[0] 'the reviewed rustup-init.exe URL was not selected'
    Assert-Equal ($plan.AssetUrl + '.sha256') $calls[1] 'the official checksum sidecar was not downloaded'
    $runners = @(Get-Runners)
    Assert-Equal 2 $runners.Count 'the fresh install ran an unexpected number of preparation commands'
    Assert-Equal 'init:rustup-init.exe' $runners[0] 'the reviewed installer was not executed first'
    Assert-Equal 'toolchain:stable' $runners[1] 'the stable toolchain install did not follow the installer'
    Assert-Equal '-y --no-modify-path --default-toolchain none --profile minimal --default-host x86_64-pc-windows-gnu' `
        (@($script:lastInitSetup.Argument) -join ' ') 'the reviewed rustup-init argument vector changed'
    Assert-Equal 'toolchain install stable --profile minimal --component rustfmt --component clippy --no-self-update' `
        (@($script:lastToolchainSetup.Argument) -join ' ') 'the reviewed toolchain install argument vector changed'
    Assert-True $script:lastToolchainSetup.NoSelfUpdate 'the toolchain install lost the no-self-update contract'
    $rustupCommand = Get-RustRustupCommand -HomeDirectory $scenarioHome
    Assert-True (Test-Path -LiteralPath $rustupCommand -PathType Leaf) 'the managed rustup.exe was not published'
    Assert-Equal (Get-PlasticineFileHash $script:rustupStubPath) (Get-PlasticineFileHash $rustupCommand) `
        'the published rustup.exe does not carry the candidate bytes'
    foreach ($name in @('rustc', 'cargo', 'rustfmt', 'clippy-driver') + $proxyNames) {
        Assert-True (Test-Path -LiteralPath (Join-Path (Get-RustBinDirectory -HomeDirectory $scenarioHome) ($name + '.exe')) -PathType Leaf) `
            "the reviewed rustup proxy $name.exe was not published"
    }
    $settingsPath = Join-Path (Get-RustRustupHome -HomeDirectory $scenarioHome) 'settings.toml'
    Assert-True (Test-Path -LiteralPath $settingsPath -PathType Leaf) 'the published rustup settings are missing'
    $settings = Get-Content -LiteralPath $settingsPath -Raw
    Assert-True ($settings -match 'default_host_tuple = "x86_64-pc-windows-gnu"') 'the published settings lost the reviewed default host'
    Assert-True ($settings -match 'default_toolchain = "stable-x86_64-pc-windows-gnu"') 'the first installation did not default to stable'
    Assert-RustPathEntry -HomeDirectory $scenarioHome -Present
    Assert-True (Test-Path -LiteralPath (Join-Path $scenarioHome '.plasticine\backups\user-path\user-path.txt') -PathType Leaf) `
        'the user PATH was changed without a backup'
    $localAcl = (Get-Acl -LiteralPath (Join-Path $scenarioHome '.local')).Sddl
    $optAcl = (Get-Acl -LiteralPath (Join-Path $scenarioHome '.local\opt')).Sddl
    Assert-True ($localAcl -match 'D:PAI') "the new .local directory is not owner-only: $localAcl"
    Assert-True ($optAcl -match 'D:PAI') "the new opt directory is not owner-only: $optAcl"
    Assert-RustNoStaging $scenarioHome

    # --- A healthy installation is reused without traffic and without a downgrade. ---
    $managedHash = Get-PlasticineFileHash $rustupCommand
    $settingsHash = Get-PlasticineFileHash $settingsPath
    Reset-Calls
    Reset-Runners
    $plan = Get-PlasticineRustPlan -HomeDirectory $scenarioHome
    Assert-Equal 'native' $plan.Owner 'the installed rustup was not observed as native'
    Assert-True $plan.Healthy 'the installed rustup was not classified as healthy'
    Assert-Equal '1.29.3' $plan.ObservedVersion 'the observed rustup version was lost'
    Assert-Equal 'x86_64-pc-windows-gnu' $plan.ObservedHost 'the observed rustup host was lost'
    Assert-True (-not $plan.PathMissing) 'the published command directory was not observed on the user PATH'
    $preview = Invoke-TestCapture { Write-PlasticineRustPreview -Plan $plan }
    Assert-True ($preview.Output -match 'Observed rustup') 'the preview did not report the observed rustup'
    Assert-True ($preview.Output -match 'will be retained') 'the preview did not report the retention decision'
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'rust' -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the reuse run failed: $($run.Message)"
    Assert-True ($run.Output -match 'pinned baseline is satisfied by rustup 1\.29\.3') 'the reuse was not reported'
    Assert-Equal 0 (@(Get-Calls).Count) 'a satisfied rustup caused rustup-init traffic'
    Assert-Equal 0 (@(Get-Runners).Count) 'a satisfied rustup caused a prepared command'
    Assert-Equal $managedHash (Get-PlasticineFileHash $rustupCommand) 'the healthy rustup binary was replaced'
    Assert-Equal $settingsHash (Get-PlasticineFileHash $settingsPath) 'the healthy rustup settings were changed'
    Assert-Equal 1 @((Get-PlasticineUserPath) -split ';' | Where-Object { $_ -match '\\\.cargo\\bin$' }).Count `
        'the rust command directory was duplicated on the user PATH'

    # --- A newer managed rustup is retained, never downgraded. ---
    $scenarioHome = New-Scenario 'newer'
    Add-ManagedRust -HomeDirectory $scenarioHome -RustupStub $script:rustupNewerStubPath -StableToolchain -Components
    $newerCommand = Get-RustRustupCommand -HomeDirectory $scenarioHome
    $newerHash = Get-PlasticineFileHash $newerCommand
    Set-RustFixture
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'rust' -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the newer rustup run failed: $($run.Message)"
    Assert-True ($run.Output -match 'satisfied by rustup 9\.9\.9') 'the newer rustup was not reported as retained'
    Assert-Equal 0 (@(Get-Calls).Count) 'a newer rustup caused installer traffic'
    Assert-Equal 0 (@(Get-Runners).Count) 'a newer rustup caused a prepared command'
    Assert-Equal $newerHash (Get-PlasticineFileHash $newerCommand) 'the newer rustup was downgraded'
    Assert-RustPathEntry -HomeDirectory $scenarioHome -Present

    # --- Missing stable pieces are maintained forward-only, host and rustup retained. ---
    $scenarioHome = New-Scenario 'maintenance'
    Add-ManagedRust -HomeDirectory $scenarioHome -RustupStub $script:rustupStubPath -DefaultToolchain none
    $retainedCommand = Get-RustRustupCommand -HomeDirectory $scenarioHome
    $retainedHash = Get-PlasticineFileHash $retainedCommand
    Set-RustFixture
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'rust' -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the maintenance run failed: $($run.Message)"
    Assert-True ($run.Output -match 'maintaining the stable toolchain for the retained rustup 1\.29\.3') 'the maintenance action was not reported'
    Assert-True ($run.Output -match 'update completed for rustup 1\.29\.3') 'the maintenance result was not reported'
    $runners = @(Get-Runners)
    Assert-Equal 1 $runners.Count 'maintenance ran more than the stable toolchain command'
    Assert-Equal 'toolchain:stable' $runners[0] 'maintenance executed rustup-init instead of toolchain maintenance'
    Assert-Equal 'toolchain install stable --profile minimal --component rustfmt --component clippy --no-self-update' `
        (@($script:lastToolchainSetup.Argument) -join ' ') 'the maintenance command lost the forward-only contract'
    Assert-True $script:lastToolchainSetup.NoSelfUpdate 'maintenance lost the no-self-update contract'
    Assert-True (-not (@($script:lastToolchainSetup.Argument) -contains '--allow-downgrade')) 'maintenance allowed a downgrade'
    Assert-Equal 0 (@(Get-Calls).Count) 'maintenance downloaded rustup-init instead of keeping the rustup binary'
    Assert-Equal $retainedHash (Get-PlasticineFileHash $retainedCommand) 'maintenance replaced the retained rustup binary'
    Assert-True (Test-Path -LiteralPath (Join-Path (Get-RustRustupHome -HomeDirectory $scenarioHome) 'toolchains\stable-x86_64-pc-windows-gnu') -PathType Container) `
        'maintenance did not install the stable toolchain'
    $maintainedSettings = Get-Content -LiteralPath (Join-Path (Get-RustRustupHome -HomeDirectory $scenarioHome) 'settings.toml') -Raw
    Assert-True ($maintainedSettings -notmatch 'default_toolchain') 'maintenance did not preserve the explicit default none'
    Assert-RustPathEntry -HomeDirectory $scenarioHome -Present
    Assert-RustNoStaging $scenarioHome

    # --- A failing toolchain maintenance preserves the working rustup. ---
    $scenarioHome = New-Scenario 'maintenance-failure'
    Add-ManagedRust -HomeDirectory $scenarioHome -RustupStub $script:rustupStubPath -DefaultToolchain none
    $retainedCommand = Get-RustRustupCommand -HomeDirectory $scenarioHome
    $retainedHash = Get-PlasticineFileHash $retainedCommand
    Set-RustFixture
    $script:toolchainRunnerMode = 'fail'
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'rust' -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'a failed toolchain maintenance reported success'
    Assert-True ($run.Error -match '^plasticine-dotfiles: rust: simulated stable toolchain installation failure') `
        'the toolchain maintenance failure was not reported with the rust prefix'
    Assert-Equal $retainedHash (Get-PlasticineFileHash $retainedCommand) 'the failed maintenance changed the working rustup'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path (Get-RustRustupHome -HomeDirectory $scenarioHome) 'toolchains'))) `
        'the failed maintenance published a toolchain'
    Assert-RustPathEntry -HomeDirectory $scenarioHome

    # --- A failed installer download leaves the home untouched. ---
    $scenarioHome = New-Scenario 'download-failure'
    $sentinel = Join-Path $scenarioHome '.local\opt\neovim\keep.txt'
    New-Item -ItemType Directory -Path (Split-Path -Parent $sentinel) -Force | Out-Null
    Set-Content -LiteralPath $sentinel -Value 'existing distribution' -NoNewline
    $beforePath = Get-PlasticineUserPath
    Set-RustFixture
    $env:PLASTICINE_TEST_DOWNLOAD_FAIL = '1'
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'rust' -HomeDirectory $scenarioHome }
    Remove-Item Env:\PLASTICINE_TEST_DOWNLOAD_FAIL -ErrorAction SilentlyContinue
    Assert-True $run.Threw 'a failed rustup-init.exe download reported success'
    Assert-True ($run.Error -match '^plasticine-dotfiles: rust: official rustup-init\.exe download failed; no installation was attempted and existing files were left untouched\.') `
        'the download failure was not reported with the reviewed wording'
    Assert-Equal 1 (@(Get-Calls).Count) 'the download failure made unexpected requests'
    Assert-Equal 0 (@(Get-Runners).Count) 'the download failure ran a preparation command'
    Assert-RustNoNativeHomes -HomeDirectory $scenarioHome
    Assert-Equal 'existing distribution' (Get-Content -LiteralPath $sentinel -Raw) 'the download failure changed an existing installation'
    Assert-Equal $beforePath (Get-PlasticineUserPath) 'the download failure changed the user PATH'
    Assert-RustNoStaging $scenarioHome

    # --- A checksum mismatch never executes the installer. ---
    $scenarioHome = New-Scenario 'digest-mismatch'
    Set-RustFixture -SidecarContent ('0' * 64)
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'rust' -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'a checksum mismatch reported success'
    Assert-True ($run.Error -match 'rustup-init\.exe SHA-256 mismatch against the official sidecar') 'the checksum mismatch was not reported'
    Assert-Equal 2 (@(Get-Calls).Count) 'the checksum mismatch did not download the reviewed tuple'
    Assert-Equal 0 (@(Get-Runners).Count) 'the checksum mismatch executed the installer'
    Assert-RustNoNativeHomes -HomeDirectory $scenarioHome
    Assert-RustNoStaging $scenarioHome

    # --- A malformed sidecar never executes the installer. ---
    $scenarioHome = New-Scenario 'sidecar-malformed'
    Set-RustFixture -SidecarContent 'not-a-sha256-digest'
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'rust' -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'a malformed checksum sidecar reported success'
    Assert-True ($run.Error -match 'checksum sidecar is malformed') 'the malformed sidecar was not reported'
    Assert-Equal 0 (@(Get-Runners).Count) 'the malformed sidecar executed the installer'
    Assert-RustNoNativeHomes -HomeDirectory $scenarioHome

    # --- A failing installer publishes nothing. ---
    $scenarioHome = New-Scenario 'init-failure'
    Set-RustFixture
    $script:initRunnerMode = 'fail'
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'rust' -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'a failing rustup-init reported success'
    Assert-True ($run.Error -match 'simulated rustup-init failure') 'the rustup-init failure was not reported'
    Assert-True ($run.Error -match '^plasticine-dotfiles: rust: ') 'the rustup-init failure lost the rust prefix'
    $runners = @(Get-Runners)
    Assert-Equal 1 $runners.Count 'the failing installer was not the only prepared command'
    Assert-RustNoNativeHomes -HomeDirectory $scenarioHome
    Assert-RustPathEntry -HomeDirectory $scenarioHome
    Assert-RustNoStaging $scenarioHome

    # --- An installer candidate without a healthy rustup publishes nothing. ---
    $scenarioHome = New-Scenario 'candidate-broken'
    Set-RustFixture
    $script:initRunnerMode = 'broken'
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'rust' -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'a broken installer candidate reported success'
    Assert-True ($run.Error -match 'rustup-init did not produce a healthy rustup at the candidate homes') `
        'the unhealthy candidate was not reported'
    Assert-Equal 1 (@(Get-Runners).Count) 'the broken candidate continued to the toolchain install'
    Assert-RustNoNativeHomes -HomeDirectory $scenarioHome
    Assert-RustNoStaging $scenarioHome

    # --- A failing toolchain install after a verified candidate publishes nothing. ---
    $scenarioHome = New-Scenario 'toolchain-failure'
    Set-RustFixture
    $script:toolchainRunnerMode = 'fail'
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'rust' -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'a failing toolchain install reported success'
    Assert-True ($run.Error -match 'simulated stable toolchain installation failure') 'the toolchain failure was not reported'
    Assert-Equal 2 (@(Get-Runners).Count) 'the failing toolchain install was not reached through the reviewed order'
    Assert-RustNoNativeHomes -HomeDirectory $scenarioHome
    Assert-RustPathEntry -HomeDirectory $scenarioHome
    Assert-RustNoStaging $scenarioHome

    # --- An external rustup owner is never shadowed. ---
    $scenarioHome = New-Scenario 'external-rustup'
    $foreignBin = New-TestDirectory 'foreign-rustup-bin'
    Copy-Item -LiteralPath $script:rustupStubPath -Destination (Join-Path $foreignBin 'rustup.exe') -Force
    $env:PATH = $foreignBin + ';' + $emptyPath
    $run = Invoke-TestCapture { Get-PlasticineRustPlan -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'an external rustup owner reported success'
    Assert-True ($run.Error -match 'external rustup at') 'the external rustup owner was not reported'
    Assert-True ($run.Error -match 'No shadow installation was created') 'the external owner guidance was lost'
    Assert-Equal 0 (@(Get-Calls).Count) 'the external rustup owner caused installer traffic'
    $env:PATH = $emptyPath
    Assert-RustNoNativeHomes -HomeDirectory $scenarioHome

    # --- Native proxies without rustup belong to another owner. ---
    $scenarioHome = New-Scenario 'proxy-without-rustup'
    $bin = Get-RustBinDirectory -HomeDirectory $scenarioHome
    New-Item -ItemType Directory -Path $bin -Force | Out-Null
    Copy-Item -LiteralPath $script:rustcStubPath -Destination (Join-Path $bin 'rustc.exe') -Force
    $run = Invoke-TestCapture { Get-PlasticineRustPlan -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'native proxies without rustup reported success'
    Assert-True ($run.Error -match 'existing proxy without rustup') 'the unowned proxy was not reported'
    Assert-Equal 0 (@(Get-Calls).Count) 'the unowned proxy caused installer traffic'

    # --- Settings without their native executable require repair. ---
    $scenarioHome = New-Scenario 'settings-without-rustup'
    $rustupHome = Get-RustRustupHome -HomeDirectory $scenarioHome
    New-Item -ItemType Directory -Path $rustupHome -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $rustupHome 'settings.toml') -Value 'version = "12"'
    $run = Invoke-TestCapture { Get-PlasticineRustPlan -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'rustup settings without rustup reported success'
    Assert-True ($run.Error -match 'existing rustup settings without its native executable') 'the orphaned settings were not reported'

    # --- A CARGO_HOME that is not a real directory is refused before any work. ---
    $scenarioHome = New-Scenario 'cargo-home-file'
    New-Item -ItemType Directory -Path (Join-Path $scenarioHome '.local\opt') -Force | Out-Null
    Set-Content -LiteralPath (Get-RustCargoHome -HomeDirectory $scenarioHome) -Value 'not a directory' -NoNewline
    $run = Invoke-TestCapture { Get-PlasticineRustPlan -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'a file CARGO_HOME was accepted'
    Assert-True ($run.Error -match 'native home or bin must be a real directory') 'the irregular native home was not reported'
    Assert-Equal 0 (@(Get-Calls).Count) 'the irregular native home caused installer traffic'

    # --- A rustup.exe that is not a regular file is refused before any work. ---
    $scenarioHome = New-Scenario 'rustup-target-directory'
    New-Item -ItemType Directory -Path (Get-RustRustupCommand -HomeDirectory $scenarioHome) -Force | Out-Null
    $run = Invoke-TestCapture { Get-PlasticineRustPlan -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'a directory rustup.exe target was accepted'
    Assert-True ($run.Error -match 'installation target is not a regular file') 'the irregular rustup target was not reported'
    Assert-Equal 0 (@(Get-Calls).Count) 'the irregular rustup target caused installer traffic'

    # --- An existing msvc host without Build Tools fails with installation guidance. ---
    $scenarioHome = New-Scenario 'msvc-without-build-tools'
    $script:rustHostTuple = 'x86_64-pc-windows-msvc'
    Add-ManagedRust -HomeDirectory $scenarioHome -RustupStub $script:rustupMsvcStubPath `
        -HostTuple 'x86_64-pc-windows-msvc' -StableToolchain -Components
    $script:PlasticineTestMsvc = $false
    $run = Invoke-TestCapture { Get-PlasticineRustPlan -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'an msvc host without Build Tools reported success'
    Assert-True ($run.Error -match 'Visual Studio Build Tools are not installed') 'the missing MSVC toolchain was not reported'
    Assert-True ($run.Error -match 'No host switch and no shadow installation was created') 'the MSVC host guidance was lost'
    Assert-Equal 0 (@(Get-Calls).Count) 'the msvc host caused installer traffic'

    # --- arm64 hosts stop with platform guidance before any observation. ---
    $scenarioHome = New-Scenario 'arm64'
    $env:PROCESSOR_ARCHITECTURE = 'ARM64'
    $env:PROCESSOR_ARCHITEW6432 = ''
    $run = Invoke-TestCapture { Get-PlasticineRustPlan -HomeDirectory $scenarioHome }
    $env:PROCESSOR_ARCHITECTURE = $savedArchitecture
    $env:PROCESSOR_ARCHITEW6432 = $savedArchitecture6432
    Assert-True $run.Threw 'an arm64 host reported success'
    Assert-True ($run.Error -match 'unsupported Windows architecture: ARM64') 'the arm64 refusal was not reported'
    Assert-Equal 0 (@(Get-Calls).Count) 'the arm64 refusal caused installer traffic'

    Complete-Test 'windows rust tests passed'
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
} finally {
    $env:PATH = $savedPath
    $env:PROCESSOR_ARCHITECTURE = $savedArchitecture
    $env:PROCESSOR_ARCHITEW6432 = $savedArchitecture6432
    Remove-Item Env:\PLASTICINE_TEST_DOWNLOAD_FAIL -ErrorAction SilentlyContinue
    $script:PlasticineUserEnvironmentSubKey = $savedUserEnvironmentSubKey
    try {
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($testUserEnvironmentSubKey, $false)
    } catch {
    }
    Remove-Item -LiteralPath $PlasticineTestRoot -Recurse -Force -ErrorAction SilentlyContinue
}
