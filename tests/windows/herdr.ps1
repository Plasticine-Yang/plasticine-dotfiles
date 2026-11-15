# Coverage for the Windows herdr route. Everything runs offline: the reviewed
# upstream installer is a fixture script, its download is a file copy and the
# child-process run is a recorded scriptblock that publishes a fixture candidate
# tree, so the ConPTY manifest validation, the whole-tree publication with
# rollback and the user-PATH restoration are exercised without network access,
# without %APPDATA%\herdr and without a real user directory.

$repoDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'harness.ps1')
$PlasticineTestName = 'windows herdr'
. (Join-Path $repoDir 'lib\windows\common.ps1')
. (Join-Path $repoDir 'lib\windows\publish.ps1')
. (Join-Path $repoDir 'lib\windows\acl.ps1')
. (Join-Path $repoDir 'lib\windows\user-path.ps1')
. (Join-Path $repoDir 'lib\windows\features.ps1')
. (Join-Path $repoDir 'lib\windows\feature-herdr.ps1')

# The route appends the managed command directory to the user PATH, so every
# registry write goes to a disposable subkey and the broadcast is disabled.
$savedUserEnvironmentSubKey = $PlasticineUserEnvironmentSubKey
$script:PlasticineUserEnvironmentSubKey = 'Software\PlasticineWindowsTests\' + [guid]::NewGuid().ToString('N')
function Send-PlasticineEnvironmentSettingChange {
    param([ValidateRange(0, 60000)][int]$TimeoutMilliseconds = 5000)
    return $true
}

$savedPath = $env:PATH
$savedAppData = $env:APPDATA
$emptyPath = New-TestDirectory 'empty-path'
$fixture = New-TestDirectory 'fixture'
$env:APPDATA = New-TestDirectory 'appdata'
$callsFile = Join-Path $PlasticineTestRoot 'calls'
$script:runnerCalls = New-Object System.Collections.ArrayList

function Reset-Calls {
    Set-Content -LiteralPath $callsFile -Value @()
    $script:runnerCalls.Clear()
}

function Get-Calls {
    if (Test-Path -LiteralPath $callsFile) { return @(Get-Content -LiteralPath $callsFile) }
    return @()
}

# The suite root is disposable, but a recursive delete still has to prove it
# targets that root and nothing above it.
function Remove-TestRootSafely {
    if (-not $PlasticineTestRoot) { return }
    $root = [IO.Path]::GetFullPath($PlasticineTestRoot)
    if (-not $root -or $root.Length -le 3) { return }
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $root.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { return }
    if (-not (Split-Path -Leaf $root).StartsWith('plasticine-windows-test.', [StringComparison]::OrdinalIgnoreCase)) { return }
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

function Invoke-PlasticineDownload {
    param([string]$Url, [string]$Destination, [string]$FailureMessage)
    Add-Content -LiteralPath $callsFile -Value $Url
    if ($env:PLASTICINE_TEST_DOWNLOAD_FAIL) { Stop-Plasticine $FailureMessage }
    Copy-Item -LiteralPath (Join-Path $fixture 'herdr-install.ps1') -Destination $Destination -ErrorAction Stop
}

# The reviewed herdr installer has no versioned URL, so it is pinned by digest
# and by the markers that prove it still resolves the stable manifest and
# verifies the package digest. The fixture supplies both.
function Set-FixtureInstaller {
    param(
        [switch]$DropMarkers,
        [string]$CommandVersion = '0.9.5'
    )
    $lines = @(
        '# reviewed herdr installer fixture',
        'param([string]$InstallDir = $env:HERDR_INSTALL_DIR)',
        'function Test-FileDigest { param([string]$Path, [string]$ExpectedDigest) }',
        '$ManifestUrl = "https://herdr.dev/latest.json"',
        '$marker = "herdr-conpty.json"'
    )
    if ($DropMarkers) {
        $lines = @('# fixture installer with the reviewed markers stripped')
    }
    Set-Content -LiteralPath (Join-Path $fixture 'herdr-install.ps1') -Value $lines -Encoding ASCII
    $digest = Get-PlasticineFileHash (Join-Path $fixture 'herdr-install.ps1')
    $script:PlasticineHerdrInstallerDigest = $digest
    $script:PlasticineHerdrCommandDigest = Get-PlasticineFileHash $script:stubs[$CommandVersion]
    return $digest
}

function New-HerdrStub {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Version,
        [switch]$Unhealthy
    )
    if ($Unhealthy) {
        $body = 'Environment.Exit(9);'
    } else {
        $body = 'Console.WriteLine("herdr ' + $Version + '"); return;'
    }
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

function New-Scenario {
    param([Parameter(Mandatory = $true)][string]$Name)
    $scenarioHome = Join-Path (New-TestDirectory $Name) 'home'
    New-Item -ItemType Directory -Path $scenarioHome -ErrorAction Stop | Out-Null
    $env:PATH = $emptyPath
    Reset-Calls
    return $scenarioHome
}

function Get-BinDirectory {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    return Join-Path $HomeDirectory '.local\bin'
}

function Get-HerdrTarget {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    return Join-Path (Get-BinDirectory $HomeDirectory) 'herdr.exe'
}

function Get-ConptyDirectory {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    return Join-Path (Get-BinDirectory $HomeDirectory) 'conpty'
}

function Assert-NoStaging {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    $bin = Get-BinDirectory $HomeDirectory
    if (Test-Path -LiteralPath $bin) {
        $leftovers = @(Get-ChildItem -LiteralPath $bin -Force | Where-Object { $_.Name -like '.*.plasticine*' })
        Assert-Equal 0 $leftovers.Count ('a run left staging or retained entries behind: ' + (($leftovers | ForEach-Object { $_.Name }) -join ', '))
    }
}

# Writes the ConPTY bundle whose manifest describes the files by digest, exactly
# like the reviewed package does.
function Set-ConptyBundle {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [string]$Marker = '',
        [switch]$WrongConptyDigest,
        [switch]$SkipConpty
    )
    if ($SkipConpty) { return }
    $conpty = Join-Path $Directory 'conpty'
    New-Item -ItemType Directory -Path (Join-Path $conpty 'x64') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $conpty 'arm64') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $conpty 'conpty.dll') -Value 'conpty' -NoNewline -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $conpty 'x64\OpenConsole.exe') -Value 'x64' -NoNewline -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $conpty 'arm64\OpenConsole.exe') -Value 'arm64' -NoNewline -Encoding ASCII
    $files = [ordered]@{
        'conpty/arm64/OpenConsole.exe' = (Get-PlasticineFileHash (Join-Path $conpty 'arm64\OpenConsole.exe'))
        'conpty/conpty.dll'            = (Get-PlasticineFileHash (Join-Path $conpty 'conpty.dll'))
        'conpty/x64/OpenConsole.exe'   = (Get-PlasticineFileHash (Join-Path $conpty 'x64\OpenConsole.exe'))
    }
    if ($WrongConptyDigest) {
        $files['conpty/x64/OpenConsole.exe'] = ('0' * 64)
    }
    $markerBody = [ordered]@{
        architecture   = 'x86_64'
        files          = $files
        package        = 'Microsoft.Windows.Console.ConPTY'
        schema_version = 1
        version        = '1.24.260710001'
    }
    $json = $markerBody | ConvertTo-Json -Depth 5
    if ($Marker) { $json = $Marker }
    Set-Content -LiteralPath (Join-Path $conpty 'herdr-conpty.json') -Value $json -Encoding ASCII
}

function Set-Candidate {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$Stub,
        [switch]$SkipCommand,
        [switch]$SkipConpty,
        [switch]$WrongConptyDigest
    )
    New-Item -ItemType Directory -Path $Directory -Force -ErrorAction Stop | Out-Null
    if (-not $SkipCommand) {
        Copy-Item -LiteralPath $Stub -Destination (Join-Path $Directory 'herdr.exe') -Force -ErrorAction Stop
    }
    Set-ConptyBundle -Directory $Directory -WrongConptyDigest:$WrongConptyDigest -SkipConpty:$SkipConpty
}

function Set-ManagedInstall {
    param(
        [Parameter(Mandatory = $true)][string]$HomeDirectory,
        [Parameter(Mandatory = $true)][string]$Stub,
        [string]$Generation = 'old'
    )
    $bin = Get-BinDirectory $HomeDirectory
    New-Item -ItemType Directory -Path $bin -Force -ErrorAction Stop | Out-Null
    Copy-Item -LiteralPath $Stub -Destination (Join-Path $bin 'herdr.exe') -Force -ErrorAction Stop
    $conpty = Join-Path $bin 'conpty'
    New-Item -ItemType Directory -Path (Join-Path $conpty 'x64') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $conpty 'arm64') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $conpty 'conpty.dll') -Value ($Generation + ' conpty') -NoNewline -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $conpty 'x64\OpenConsole.exe') -Value ($Generation + ' x64') -NoNewline -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $conpty 'arm64\OpenConsole.exe') -Value ($Generation + ' arm64') -NoNewline -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $conpty 'herdr-conpty.json') -Value ($Generation + ' marker') -NoNewline -Encoding ASCII
}

function Get-UserPathEntries {
    $entries = @()
    foreach ($entry in ((Get-PlasticineUserPath) -split ';')) {
        if ($entry) { $entries += $entry }
    }
    return $entries
}

function Assert-UserPathHasNoEntry {
    param([Parameter(Mandatory = $true)][string]$Directory)
    $normalized = $Directory.TrimEnd('\')
    foreach ($entry in (Get-UserPathEntries)) {
        Assert-True ($entry.TrimEnd('\') -ine $normalized) "the user PATH still contains $Directory"
    }
}

$script:PlasticineHerdrInstallerRunner = {
    param($Installer, $Environment, $RemoveEnvironment, $WorkingDirectory)
    throw 'the herdr suite must configure the installer runner seam before preparation'
}

# Replaces the child-process seam: it records the environment the reviewed
# installer would have received, publishes the fixture candidate tree and can
# reproduce the unconditional user-PATH write of the upstream installer.
function Set-CandidateRunner {
    param(
        [Parameter(Mandatory = $true)][string]$Stub,
        [switch]$SkipCommand,
        [switch]$SkipConpty,
        [switch]$WrongConptyDigest,
        [switch]$JunctionCandidate,
        [int]$ExitCode = 0,
        [string]$PathEntryToAdd = ''
    )
    $script:candidateStub = $Stub
    $script:candidateSkipCommand = [bool]$SkipCommand
    $script:candidateSkipConpty = [bool]$SkipConpty
    $script:candidateWrongConptyDigest = [bool]$WrongConptyDigest
    $script:candidateJunction = [bool]$JunctionCandidate
    $script:candidateExitCode = $ExitCode
    $script:candidatePathEntry = $PathEntryToAdd
    $script:PlasticineHerdrInstallerRunner = {
        param($Installer, $Environment, $RemoveEnvironment, $WorkingDirectory)
        $candidate = [string]$Environment['HERDR_INSTALL_DIR']
        [void]$script:runnerCalls.Add([pscustomobject]@{
            Installer         = $Installer
            Environment       = $Environment
            RemoveEnvironment = @($RemoveEnvironment)
            WorkingDirectory  = $WorkingDirectory
            Candidate         = $candidate
            HerdrHome         = [string]$Environment['HERDR_HOME']
        })
        $rerun = $script:candidateExitCode
        if ($rerun -ne 0) {
            return [pscustomobject]@{ ExitCode = $rerun; Output = ''; Error = 'simulated installer failure' }
        }
        if ($script:candidateJunction) {
            # The reviewed installer publishes HERDR_INSTALL_DIR as a junction to
            # its versioned release directory inside HERDR_HOME.
            $release = Join-Path $WorkingDirectory 'release-tree'
            Set-Candidate -Directory $release -Stub $script:candidateStub
            New-Item -ItemType Junction -Path $candidate -Target $release -ErrorAction Stop | Out-Null
        } else {
            Set-Candidate -Directory $candidate -Stub $script:candidateStub `
                -SkipCommand:$script:candidateSkipCommand -SkipConpty:$script:candidateSkipConpty `
                -WrongConptyDigest:$script:candidateWrongConptyDigest
        }
        if ($script:candidatePathEntry) {
            # The upstream installer always prepends its own release directory;
            # reproduce that write against the disposable registry subkey.
            $null = Add-PlasticineUserPathEntry -Directory $script:candidatePathEntry
        }
        return [pscustomobject]@{ ExitCode = 0; Output = 'fixture installer output'; Error = '' }
    }
}

try {
    $stubDirectory = New-TestDirectory 'stubs'
    $script:stubs = @{}
    foreach ($version in @('0.9.5', '0.8.0', '0.10.0')) {
        $path = Join-Path $stubDirectory ('herdr-' + $version + '.exe')
        New-HerdrStub -Path $path -Version $version
        $script:stubs[$version] = $path
    }
    $unhealthyStub = Join-Path $stubDirectory 'herdr-unhealthy.exe'
    New-HerdrStub -Path $unhealthyStub -Version '0.9.5' -Unhealthy

    # --- Plan and preview name the reviewed tuple without touching anything. ---
    $scenarioHome = New-Scenario 'plan'
    $reviewedDigest = Set-FixtureInstaller
    $userPathBefore = Get-PlasticineUserPath
    $plan = Get-PlasticineHerdrPlan -HomeDirectory $scenarioHome
    Assert-Equal (Get-BinDirectory $scenarioHome) $plan.InstallDirectory 'the plan did not target ~/.local/bin'
    Assert-Equal (Get-HerdrTarget $scenarioHome) $plan.Command 'the plan did not target ~/.local/bin/herdr.exe'
    Assert-Equal (Get-ConptyDirectory $scenarioHome) $plan.ConptyDirectory 'the plan did not target the ConPTY directory'
    Assert-Equal 'conpty herdr.exe' (@($plan.Entries) -join ' ') 'the plan lost the whole-tree publication order'
    Assert-Equal '0.9.5' $plan.Version 'the plan lost the pinned baseline'
    Assert-Equal $reviewedDigest $plan.InstallerDigest 'the plan lost the reviewed installer digest'
    Assert-True ($plan.InstallerUrl -match 'herdr\.dev/install\.ps1$') 'the plan did not pin the reviewed installer URL'
    Assert-True ($plan.ManifestUrl -match 'herdr\.dev/latest\.json$') 'the plan lost the reviewed manifest URL'
    Assert-Equal (Join-Path $env:APPDATA 'herdr\config.toml') $plan.ConfigFile 'the plan did not use the Windows configuration path'
    Assert-True $plan.PathMissing 'a fresh user PATH was not reported as missing the command directory'
    Assert-True ($null -eq $plan.Observed) 'a missing herdr was reported as observed'
    Assert-Equal 'missing' $plan.Owner 'a missing herdr was classified as an owner'
    $preview = Invoke-TestCapture { Write-PlasticineHerdrPreview -Plan $plan }
    Assert-True (-not $preview.Threw) "the preview failed: $($preview.Message)"
    Assert-True ($preview.Output -match 'pinned baseline 0\.9\.5') 'the preview lost the pinned baseline'
    Assert-True ($preview.Output -match [regex]::Escape($plan.InstallDirectory)) 'the preview did not name the destination'
    Assert-True ($preview.Output -match [regex]::Escape($plan.ConfigFile)) 'the preview lost the Windows configuration path'
    Assert-True ($preview.Output -match 'ConPTY') 'the preview lost the ConPTY runtime note'
    Assert-True ($preview.Output -match 'HERDR_INSTALL_DIR') 'the preview lost the installer environment contract'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $scenarioHome '.local'))) 'the plan or preview created the managed directory'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $env:APPDATA 'herdr'))) 'the plan or preview created the herdr configuration directory'
    Assert-Equal $userPathBefore (Get-PlasticineUserPath) 'the plan or preview changed the user PATH'
    Assert-Equal 0 @(Get-Calls).Count 'the plan or preview made a request'

    # --- Preview reports an executable that PATH resolves, with its owner. ---
    $scenarioHome = New-Scenario 'observed'
    $ownerBin = New-TestDirectory 'owner-bin'
    Copy-Item -LiteralPath $script:stubs['0.9.5'] -Destination (Join-Path $ownerBin 'herdr.exe') -Force
    $env:PATH = $ownerBin + ';' + $emptyPath
    $plan = Get-PlasticineHerdrPlan -HomeDirectory $scenarioHome
    Assert-Equal (Join-Path $ownerBin 'herdr.exe') $plan.Observed 'the plan did not resolve the PATH executable'
    Assert-Equal 'external' $plan.Owner 'the plan did not classify the PATH executable as external'
    $preview = Invoke-TestCapture { Write-PlasticineHerdrPreview -Plan $plan }
    Assert-True ($preview.Output -match 'Observed executable') 'the preview did not name the observed executable'

    # --- A missing installation publishes the whole reviewed tree. ---
    $scenarioHome = New-Scenario 'fresh'
    $null = Set-FixtureInstaller
    Set-CandidateRunner -Stub $script:stubs['0.9.5']
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'herdr' -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the fresh install failed: $($run.Message)"
    Assert-True ($run.Output -match 'fresh completed at stable target 0\.9\.5') 'the fresh install was not reported'
    Assert-Equal 1 @(Get-Calls).Count 'the fresh install made more than one request'
    Assert-True (@(Get-Calls)[0] -match 'herdr\.dev/install\.ps1$') 'the reviewed installer was not requested'
    Assert-Equal 1 @($script:runnerCalls).Count 'the reviewed installer did not run exactly once'
    $record = @($script:runnerCalls)[0]
    Assert-Equal 'herdr-install.ps1' (Split-Path -Leaf $record.Installer) 'the reviewed script was not handed to the runner'
    Assert-Equal 'stable' $record.Environment['HERDR_CHANNEL'] 'the installer channel was not pinned to stable'
    Assert-Equal $record.Candidate $record.Environment['HERDR_INSTALL_DIR'] 'HERDR_INSTALL_DIR did not name the private candidate'
    Assert-True (-not $record.Environment.ContainsKey('HERDR_MANIFEST_URL')) 'a manifest override reached the installer'
    Assert-True (-not $record.Candidate.StartsWith($scenarioHome, [StringComparison]::OrdinalIgnoreCase)) `
        'the reviewed installer was pointed at the managed destination'
    Assert-True (-not $record.HerdrHome.StartsWith($scenarioHome, [StringComparison]::OrdinalIgnoreCase)) `
        'the reviewed installer was pointed at a durable herdr home'
    Assert-True (-not (Test-Path -LiteralPath $record.Candidate)) 'the private candidate directory was not discarded'
    Assert-True (-not (Test-Path -LiteralPath $record.HerdrHome)) 'the private herdr home directory was not discarded'
    Assert-Equal '0.9.5' (Get-PlasticineExecutableVersion (Get-HerdrTarget $scenarioHome)) 'the pinned herdr was not published'
    Assert-True (Test-Path -LiteralPath (Join-Path (Get-ConptyDirectory $scenarioHome) 'x64\OpenConsole.exe') -PathType Leaf) `
        'the reviewed ConPTY runtime was not published'
    Assert-True (Test-Path -LiteralPath (Join-Path (Get-ConptyDirectory $scenarioHome) 'arm64\OpenConsole.exe') -PathType Leaf) `
        'the reviewed arm64 ConPTY runtime was not published'
    Assert-NoStaging $scenarioHome
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $env:APPDATA 'herdr'))) 'the route created the herdr configuration directory'
    $entries = @(Get-UserPathEntries)
    Assert-Equal 1 @($entries | Where-Object { $_.TrimEnd('\') -ieq (Get-BinDirectory $scenarioHome).TrimEnd('\') }).Count `
        'the managed command directory was not appended to the user PATH exactly once'
    $localAcl = (Get-Acl -LiteralPath (Join-Path $scenarioHome '.local')).Sddl
    $binAcl = (Get-Acl -LiteralPath (Join-Path $scenarioHome '.local\bin')).Sddl
    Assert-True ($localAcl -match 'D:PAI') "the new .local directory is not owner-only: $localAcl"
    Assert-True ($binAcl -match 'D:PAI') "the new bin directory is not owner-only: $binAcl"

    # --- A candidate published as a junction, like the reviewed installer does,
    # is read through and published as a plain tree. ---
    $scenarioHome = New-Scenario 'junction-candidate'
    $null = Set-FixtureInstaller
    Set-CandidateRunner -Stub $script:stubs['0.9.5'] -JunctionCandidate
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'herdr' -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the junction candidate install failed: $($run.Message)"
    Assert-Equal '0.9.5' (Get-PlasticineExecutableVersion (Get-HerdrTarget $scenarioHome)) 'the junction candidate was not published'
    Assert-True (Test-Path -LiteralPath (Join-Path (Get-ConptyDirectory $scenarioHome) 'x64\OpenConsole.exe') -PathType Leaf) `
        'the junction candidate ConPTY runtime was not published'
    $publishedItem = Get-Item -LiteralPath (Get-HerdrTarget $scenarioHome) -Force
    Assert-True (-not ($publishedItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) 'the published command is a reparse point'
    Assert-NoStaging $scenarioHome

    # --- The satisfied baseline is reused without installer traffic. ---
    $scenarioHome = New-Scenario 'reuse'
    $null = Set-FixtureInstaller
    Set-CandidateRunner -Stub $script:stubs['0.9.5']
    $seed = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'herdr' -HomeDirectory $scenarioHome }
    Assert-True (-not $seed.Threw) "the reuse seed install failed: $($seed.Message)"
    $installedHash = Get-PlasticineFileHash (Get-HerdrTarget $scenarioHome)
    Reset-Calls
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'herdr' -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the reuse run failed: $($run.Message)"
    Assert-True ($run.Output -match 'is satisfied by stable 0\.9\.5') 'reuse was not reported'
    Assert-Equal 0 @(Get-Calls).Count 'a satisfied installation caused installer traffic'
    Assert-Equal 0 @($script:runnerCalls).Count 'a satisfied installation ran the installer'
    Assert-Equal $installedHash (Get-PlasticineFileHash (Get-HerdrTarget $scenarioHome)) 'the current executable was replaced'
    Assert-Equal 1 @(Get-UserPathEntries | Where-Object { $_.TrimEnd('\') -ieq (Get-BinDirectory $scenarioHome).TrimEnd('\') }).Count `
        'the managed PATH entry was duplicated'

    # --- A newer managed installation is retained, never downgraded. ---
    $scenarioHome = New-Scenario 'newer'
    Set-ManagedInstall -HomeDirectory $scenarioHome -Stub $script:stubs['0.10.0']
    $newerHash = Get-PlasticineFileHash (Get-HerdrTarget $scenarioHome)
    $null = Set-FixtureInstaller
    Set-CandidateRunner -Stub $script:stubs['0.9.5']
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'herdr' -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the newer managed run failed: $($run.Message)"
    Assert-True ($run.Output -match 'is satisfied by stable 0\.10\.0') 'the newer installation was not reused'
    Assert-Equal 0 @(Get-Calls).Count 'a newer installation caused installer traffic'
    Assert-Equal $newerHash (Get-PlasticineFileHash (Get-HerdrTarget $scenarioHome)) 'a newer installation was downgraded'

    # --- An older managed installation is replaced as a whole tree. ---
    $scenarioHome = New-Scenario 'upgrade'
    Set-ManagedInstall -HomeDirectory $scenarioHome -Stub $script:stubs['0.8.0']
    $outdatedHash = Get-PlasticineFileHash (Get-HerdrTarget $scenarioHome)
    $null = Set-FixtureInstaller
    Set-CandidateRunner -Stub $script:stubs['0.9.5']
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'herdr' -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the upgrade failed: $($run.Message)"
    Assert-True ($run.Output -match 'upgrade completed at stable target 0\.9\.5') 'the upgrade was not reported'
    Assert-Equal 1 @(Get-Calls).Count 'the upgrade did not request the reviewed installer'
    Assert-Equal '0.9.5' (Get-PlasticineExecutableVersion (Get-HerdrTarget $scenarioHome)) 'the outdated executable was not replaced'
    Assert-True ($outdatedHash -ne (Get-PlasticineFileHash (Get-HerdrTarget $scenarioHome))) 'the outdated executable was retained'
    Assert-Equal 'conpty' (Get-Content -LiteralPath (Join-Path (Get-ConptyDirectory $scenarioHome) 'conpty.dll') -Raw) `
        'the outdated ConPTY runtime was retained'
    Assert-NoStaging $scenarioHome

    # --- A current command with a damaged ConPTY runtime is repaired. ---
    $scenarioHome = New-Scenario 'repair-runtime'
    Set-ManagedInstall -HomeDirectory $scenarioHome -Stub $script:stubs['0.9.5']
    Remove-Item -LiteralPath (Join-Path (Get-ConptyDirectory $scenarioHome) 'x64\OpenConsole.exe') -Force
    $null = Set-FixtureInstaller
    Set-CandidateRunner -Stub $script:stubs['0.9.5']
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'herdr' -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the runtime repair failed: $($run.Message)"
    Assert-True ($run.Output -match 'ConPTY runtime is incomplete') 'the incomplete runtime was not reported'
    Assert-True ($run.Output -match 'repair completed at stable target 0\.9\.5') 'the runtime repair was not reported'
    Assert-Equal 1 @(Get-Calls).Count 'the runtime repair did not request the reviewed installer'
    Assert-True (Test-Path -LiteralPath (Join-Path (Get-ConptyDirectory $scenarioHome) 'x64\OpenConsole.exe') -PathType Leaf) `
        'the runtime repair did not restore the ConPTY runtime'
    Assert-NoStaging $scenarioHome

    # --- The user PATH is restored after the upstream installer rewrites it. ---
    $scenarioHome = New-Scenario 'path-restore'
    $upstreamRelease = New-TestDirectory 'upstream-release-bin'
    $null = Set-FixtureInstaller
    Set-CandidateRunner -Stub $script:stubs['0.9.5'] -PathEntryToAdd $upstreamRelease
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'herdr' -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the PATH restore run failed: $($run.Message)"
    Assert-True ($run.Output -match 'restored the user-level PATH') 'the PATH restoration was not reported'
    Assert-UserPathHasNoEntry -Directory $upstreamRelease
    Assert-Equal 1 @(Get-UserPathEntries | Where-Object { $_.TrimEnd('\') -ieq (Get-BinDirectory $scenarioHome).TrimEnd('\') }).Count `
        'the managed command directory was not appended exactly once after the PATH restore'

    # --- An installation owned elsewhere below the baseline is never shadowed. ---
    $scenarioHome = New-Scenario 'foreign'
    $foreignBin = New-TestDirectory 'foreign-bin'
    Copy-Item -LiteralPath $script:stubs['0.8.0'] -Destination (Join-Path $foreignBin 'herdr.exe') -Force
    $env:PATH = $foreignBin + ';' + $emptyPath
    $foreignHash = Get-PlasticineFileHash (Join-Path $foreignBin 'herdr.exe')
    $null = Set-FixtureInstaller
    Set-CandidateRunner -Stub $script:stubs['0.9.5']
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'herdr' -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'an external herdr reported success'
    Assert-True ($run.Error -match 'unsupported owner path .*No shadow installation') 'the external owner was not reported'
    Assert-Equal 0 @(Get-Calls).Count 'the external owner caused installer traffic'
    Assert-Equal 0 @($script:runnerCalls).Count 'the external owner ran the installer'
    Assert-Equal $foreignHash (Get-PlasticineFileHash (Join-Path $foreignBin 'herdr.exe')) 'the external owner was modified'
    Assert-True (-not (Test-Path -LiteralPath (Get-HerdrTarget $scenarioHome))) 'a shadow installation was created'

    # --- An unhealthy managed installation is left for its owner. ---
    $scenarioHome = New-Scenario 'unhealthy'
    Set-ManagedInstall -HomeDirectory $scenarioHome -Stub $unhealthyStub
    $null = Set-FixtureInstaller
    Set-CandidateRunner -Stub $script:stubs['0.9.5']
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'herdr' -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'an unhealthy managed installation reported success'
    Assert-True ($run.Error -match 'existing executable is unhealthy') 'the unhealthy installation was not reported'
    Assert-Equal 0 @(Get-Calls).Count 'an unhealthy installation caused installer traffic'

    # --- An unowned ConPTY directory at the managed destination is refused. ---
    $scenarioHome = New-Scenario 'unowned-conpty'
    New-Item -ItemType Directory -Path (Get-ConptyDirectory $scenarioHome) -Force | Out-Null
    $null = Set-FixtureInstaller
    Set-CandidateRunner -Stub $script:stubs['0.9.5']
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'herdr' -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'an unowned ConPTY directory reported success'
    Assert-True ($run.Error -match 'unowned ConPTY directory') 'the unowned ConPTY directory was not reported'
    Assert-Equal 0 @(Get-Calls).Count 'an unowned ConPTY directory caused installer traffic'

    # --- A candidate below the reviewed baseline keeps the old installation. ---
    $scenarioHome = New-Scenario 'candidate-version'
    Set-ManagedInstall -HomeDirectory $scenarioHome -Stub $script:stubs['0.8.0']
    $beforeHash = Get-PlasticineFileHash (Get-HerdrTarget $scenarioHome)
    $null = Set-FixtureInstaller -CommandVersion '0.8.0'
    Set-CandidateRunner -Stub $script:stubs['0.8.0']
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'herdr' -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'an unreviewed candidate version reported success'
    Assert-True ($run.Error -match 'produced herdr 0\.8\.0, not the reviewed baseline 0\.9\.5') 'the candidate version failure was not reported'
    Assert-Equal $beforeHash (Get-PlasticineFileHash (Get-HerdrTarget $scenarioHome)) 'the candidate failure replaced the working executable'
    Assert-Equal 'old conpty' (Get-Content -LiteralPath (Join-Path (Get-ConptyDirectory $scenarioHome) 'conpty.dll') -Raw) `
        'the candidate failure replaced the working ConPTY runtime'
    Assert-NoStaging $scenarioHome

    # --- A candidate whose ConPTY manifest digest does not match is refused. ---
    $scenarioHome = New-Scenario 'candidate-conpty-digest'
    $null = Set-FixtureInstaller -CommandVersion '0.9.5'
    Set-CandidateRunner -Stub $script:stubs['0.9.5'] -WrongConptyDigest
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'herdr' -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'a candidate with a mismatched ConPTY digest reported success'
    Assert-True ($run.Error -match 'does not match its manifest SHA-256') 'the ConPTY digest failure was not reported'
    Assert-True (-not (Test-Path -LiteralPath (Get-HerdrTarget $scenarioHome))) 'the unverified candidate was published'
    Assert-NoStaging $scenarioHome

    # --- A candidate without the ConPTY runtime is refused. ---
    $scenarioHome = New-Scenario 'candidate-no-conpty'
    $null = Set-FixtureInstaller -CommandVersion '0.9.5'
    Set-CandidateRunner -Stub $script:stubs['0.9.5'] -SkipConpty
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'herdr' -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'a candidate without the ConPTY runtime reported success'
    Assert-True ($run.Error -match 'missing the ConPTY manifest') 'the missing ConPTY runtime was not reported'
    Assert-True (-not (Test-Path -LiteralPath (Get-HerdrTarget $scenarioHome))) 'an incomplete package was published'
    Assert-NoStaging $scenarioHome

    # --- The reviewed installer digest is enforced before execution. ---
    $scenarioHome = New-Scenario 'installer-digest'
    $null = Set-FixtureInstaller
    $savedDigest = $script:PlasticineHerdrInstallerDigest
    $script:PlasticineHerdrInstallerDigest = ('0' * 64)
    Set-CandidateRunner -Stub $script:stubs['0.9.5']
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'herdr' -HomeDirectory $scenarioHome }
    $script:PlasticineHerdrInstallerDigest = $savedDigest
    Assert-True $run.Threw 'an installer digest mismatch reported success'
    Assert-True ($run.Error -match 'SHA-256 mismatch') 'the installer digest mismatch was not reported'
    Assert-Equal 0 @($script:runnerCalls).Count 'an unreviewed installer was executed'
    Assert-True (-not (Test-Path -LiteralPath (Get-HerdrTarget $scenarioHome))) 'an unreviewed installer published a target'

    # --- A changed upstream installer is refused instead of executed. ---
    $scenarioHome = New-Scenario 'installer-markers'
    $null = Set-FixtureInstaller -DropMarkers
    Set-CandidateRunner -Stub $script:stubs['0.9.5']
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'herdr' -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'an installer without the reviewed markers reported success'
    Assert-True ($run.Error -match 'missing marker') 'the installer marker failure was not reported'
    Assert-Equal 0 @($script:runnerCalls).Count 'an unreviewed installer was executed'

    # --- An installer failure preserves the working installation. ---
    $scenarioHome = New-Scenario 'installer-failure'
    Set-ManagedInstall -HomeDirectory $scenarioHome -Stub $script:stubs['0.8.0']
    $beforeHash = Get-PlasticineFileHash (Get-HerdrTarget $scenarioHome)
    $null = Set-FixtureInstaller
    Set-CandidateRunner -Stub $script:stubs['0.9.5'] -ExitCode 1
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'herdr' -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'a failed installer reported success'
    Assert-True ($run.Error -match 'official installer failed') 'the installer failure was not reported'
    Assert-True ($run.Error -match 'simulated installer failure') 'the installer diagnostics were dropped'
    Assert-Equal $beforeHash (Get-PlasticineFileHash (Get-HerdrTarget $scenarioHome)) 'the failed install replaced the working executable'
    Assert-NoStaging $scenarioHome

    # --- A download failure preserves the working installation. ---
    $scenarioHome = New-Scenario 'download-failure'
    Set-ManagedInstall -HomeDirectory $scenarioHome -Stub $script:stubs['0.8.0']
    $beforeHash = Get-PlasticineFileHash (Get-HerdrTarget $scenarioHome)
    $null = Set-FixtureInstaller
    Set-CandidateRunner -Stub $script:stubs['0.9.5']
    $env:PLASTICINE_TEST_DOWNLOAD_FAIL = '1'
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'herdr' -HomeDirectory $scenarioHome }
    Remove-Item Env:\PLASTICINE_TEST_DOWNLOAD_FAIL -ErrorAction SilentlyContinue
    Assert-True $run.Threw 'a download failure reported success'
    Assert-True ($run.Error -match 'official installer download failed') 'the download failure was not reported'
    Assert-Equal $beforeHash (Get-PlasticineFileHash (Get-HerdrTarget $scenarioHome)) 'the download failure replaced the working executable'
    Assert-NoStaging $scenarioHome

    # --- A failed whole-tree publication restores the previous installation. ---
    $scenarioHome = New-Scenario 'publication-rollback'
    Set-ManagedInstall -HomeDirectory $scenarioHome -Stub $script:stubs['0.8.0']
    $beforeHash = Get-PlasticineFileHash (Get-HerdrTarget $scenarioHome)
    $beforeConpty = Get-PlasticineFileHash (Join-Path (Get-ConptyDirectory $scenarioHome) 'conpty.dll')
    $null = Set-FixtureInstaller
    Set-CandidateRunner -Stub $script:stubs['0.9.5']
    $originalMove = ${function:Move-PlasticineHerdrPath}
    ${function:Move-PlasticineHerdrPath} = {
        param($Source, $Destination, [switch]$Directory)
        # Fail only when the staged command is being committed, so the retained
        # previous entries still exist for the rollback that follows.
        if ($Source -like '*.herdr.exe.plasticine.*' -and $Destination -like '*\herdr.exe') {
            throw 'simulated whole-directory publication failure'
        }
        if ($Directory) { Move-PlasticineDirectory -Source $Source -Destination $Destination }
        else { [IO.File]::Move($Source, $Destination) }
    }
    try {
        $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'herdr' -HomeDirectory $scenarioHome }
    } finally {
        ${function:Move-PlasticineHerdrPath} = $originalMove
    }
    Assert-True $run.Threw 'a failed whole-tree publication reported success'
    Assert-True ($run.Error -match 'whole-directory publication failed; the previous installation was restored') `
        'the publication rollback was not reported'
    Assert-True ($run.Error -match 'simulated whole-directory publication failure') 'the underlying publication failure was dropped'
    Assert-Equal $beforeHash (Get-PlasticineFileHash (Get-HerdrTarget $scenarioHome)) 'the rollback did not restore the previous executable'
    Assert-Equal '0.8.0' (Get-PlasticineExecutableVersion (Get-HerdrTarget $scenarioHome)) 'the rollback left an upgraded executable behind'
    Assert-Equal $beforeConpty (Get-PlasticineFileHash (Join-Path (Get-ConptyDirectory $scenarioHome) 'conpty.dll')) `
        'the rollback did not restore the previous ConPTY runtime'
    Assert-Equal 'old marker' (Get-Content -LiteralPath (Join-Path (Get-ConptyDirectory $scenarioHome) 'herdr-conpty.json') -Raw) `
        'the rollback did not restore the previous ConPTY manifest'
    Assert-NoStaging $scenarioHome

    # --- A target that is not a regular file is refused before any work. ---
    $scenarioHome = New-Scenario 'target-directory'
    New-Item -ItemType Directory -Path (Get-HerdrTarget $scenarioHome) -Force | Out-Null
    $run = Invoke-TestCapture { Get-PlasticineHerdrPlan -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'a directory herdr target was accepted'
    Assert-True ($run.Error -match 'installation target is not a regular file') 'the irregular target was not reported'

    # --- A ConPTY path that is not a real directory is refused. ---
    $scenarioHome = New-Scenario 'conpty-file'
    $bin = Get-BinDirectory $scenarioHome
    New-Item -ItemType Directory -Path $bin -Force | Out-Null
    Set-Content -LiteralPath (Get-ConptyDirectory $scenarioHome) -Value 'not a directory' -NoNewline
    $run = Invoke-TestCapture { Get-PlasticineHerdrPlan -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'a file ConPTY path was accepted'
    Assert-True ($run.Error -match 'installation directory is not a real directory') 'the irregular ConPTY path was not reported'

    Complete-Test 'windows herdr tests passed'
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
} finally {
    $env:PATH = $savedPath
    $env:APPDATA = $savedAppData
    Remove-Item Env:\PLASTICINE_TEST_DOWNLOAD_FAIL -ErrorAction SilentlyContinue
    $script:PlasticineUserEnvironmentSubKey = $savedUserEnvironmentSubKey
    try {
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree('Software\PlasticineWindowsTests', $false)
    } catch {
    }
    Remove-TestRootSafely
}
