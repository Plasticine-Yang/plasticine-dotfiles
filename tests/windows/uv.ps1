# Coverage for the Windows uv route. Everything runs offline: the official
# installer is replaced by a fixture script, its download by a file copy and the
# child-process run by a recorded scriptblock, so the reviewed tuple, the private
# candidate installation, the published command pair and every reuse/refusal
# branch are exercised without network access or a real user directory.

$repoDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'harness.ps1')
$PlasticineTestName = 'windows uv'
. (Join-Path $repoDir 'lib\windows\common.ps1')
. (Join-Path $repoDir 'lib\windows\publish.ps1')
. (Join-Path $repoDir 'lib\windows\acl.ps1')
. (Join-Path $repoDir 'lib\windows\user-path.ps1')
. (Join-Path $repoDir 'lib\windows\features.ps1')
. (Join-Path $repoDir 'lib\windows\feature-uv.ps1')

# The route never edits PATH, but a suite must still never write the real HKCU:
# keep the registry seam on a disposable subkey and disable the broadcast.
$savedUserEnvironmentSubKey = $PlasticineUserEnvironmentSubKey
$script:PlasticineUserEnvironmentSubKey = 'Software\PlasticineWindowsTests\' + [guid]::NewGuid().ToString('N')
function Send-PlasticineEnvironmentSettingChange {
    param([ValidateRange(0, 60000)][int]$TimeoutMilliseconds = 5000)
    return $true
}

$savedPath = $env:PATH
$emptyPath = New-TestDirectory 'empty-path'
$fixture = New-TestDirectory 'fixture'
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

# Offline stand-in for Invoke-PlasticineDownload: the fixture install script is
# copied into place and the requested URL is recorded.
function Invoke-PlasticineDownload {
    param([string]$Url, [string]$Destination, [string]$FailureMessage)
    Add-Content -LiteralPath $callsFile -Value $Url
    if ($env:PLASTICINE_TEST_DOWNLOAD_FAIL) { Stop-Plasticine $FailureMessage }
    Copy-Item -LiteralPath (Join-Path $fixture 'uv-installer.ps1') -Destination $Destination -ErrorAction Stop
}

# The reviewed installer is only ever a pinned digest plus its own identity
# lines, so the fixture supplies both and the module is pinned to its digest.
# The reviewed command hashes are pinned to the fixture candidates in the same
# step, so each scenario reviews exactly the commands it exercises.
function Set-FixtureInstaller {
    param(
        [switch]$NoIdentity,
        [string]$CandidateVersion = '0.13.8'
    )
    $lines = @(
        '# reviewed uv installer fixture',
        "`$app_name = 'uv'",
        "`$app_version = '0.13.8'"
    )
    if ($NoIdentity) {
        $lines = @('# fixture installer with the reviewed identity lines removed')
    }
    Set-Content -LiteralPath (Join-Path $fixture 'uv-installer.ps1') -Value $lines -Encoding ASCII
    $digest = Get-PlasticineFileHash (Join-Path $fixture 'uv-installer.ps1')
    $script:PlasticineUvInstallerDigest = $digest
    $script:PlasticineUvCommandDigests = @{
        'uv.exe'  = (Get-PlasticineFileHash $script:stubs[$CandidateVersion])
        'uvx.exe' = (Get-PlasticineFileHash $script:stubs[$CandidateVersion])
    }
    return $digest
}

# uv prints "uv 0.13.8 (<hash> <date> <triple>)" and uvx the same shape, so one
# compiled stub per version is enough for both managed commands.
function New-UvStub {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Version,
        [switch]$Unhealthy
    )
    if ($Unhealthy) {
        $body = 'Environment.Exit(9);'
    } else {
        $body = 'Console.WriteLine("uv ' + $Version + ' (3d97a6aad 2026-11-12 x86_64-pc-windows-msvc)"); return;'
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

function Get-UvTarget {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    return Join-Path $HomeDirectory '.local\bin\uv.exe'
}

function Get-UvxTarget {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    return Join-Path $HomeDirectory '.local\bin\uvx.exe'
}

function Assert-NoStaging {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    $bin = Join-Path $HomeDirectory '.local\bin'
    if (Test-Path -LiteralPath $bin) {
        Assert-Equal 0 (@(Get-ChildItem -LiteralPath $bin -Force -Filter '.uv*.plasticine.*').Count) `
            'a run left a staged uv file behind'
    }
}

function Assert-ManagedPair {
    param(
        [Parameter(Mandatory = $true)][string]$HomeDirectory,
        [Parameter(Mandatory = $true)][string]$Version,
        [string]$UvxVersion = ''
    )
    $bin = Join-Path $HomeDirectory '.local\bin'
    New-Item -ItemType Directory -Path $bin -Force -ErrorAction Stop | Out-Null
    Copy-Item -LiteralPath $script:stubs[$Version] -Destination (Join-Path $bin 'uv.exe') -Force -ErrorAction Stop
    if (-not $UvxVersion) { $UvxVersion = $Version }
    Copy-Item -LiteralPath $script:stubs[$UvxVersion] -Destination (Join-Path $bin 'uvx.exe') -Force -ErrorAction Stop
}

# Replaces the child-process seam: it records the environment the reviewed
# installer would have received and publishes the requested candidate commands.
$script:PlasticineUvInstallerRunner = {
    param($Installer, $Environment, $RemoveEnvironment, $WorkingDirectory)
    throw 'the uv suite must configure the installer runner seam before preparation'
}

function Set-CandidateRunner {
    param(
        [Parameter(Mandatory = $true)][string]$Version,
        [string]$UvxVersion = '',
        [switch]$SkipUv,
        [switch]$SkipUvx,
        [int]$ExitCode = 0
    )
    if (-not $UvxVersion) { $UvxVersion = $Version }
    $script:candidateUvStub = $script:stubs[$Version]
    $script:candidateUvxStub = $script:stubs[$UvxVersion]
    $script:candidateSkipUv = [bool]$SkipUv
    $script:candidateSkipUvx = [bool]$SkipUvx
    $script:candidateExitCode = $ExitCode
    $script:PlasticineUvInstallerRunner = {
        param($Installer, $Environment, $RemoveEnvironment, $WorkingDirectory)
        $candidate = [string]$Environment['UV_INSTALL_DIR']
        [void]$script:runnerCalls.Add([pscustomobject]@{
            Installer        = $Installer
            Environment      = $Environment
            RemoveEnvironment = @($RemoveEnvironment)
            WorkingDirectory = $WorkingDirectory
            Candidate        = $candidate
        })
        $rerun = $script:candidateExitCode
        if ($rerun -ne 0) {
            return [pscustomobject]@{ ExitCode = $rerun; Output = ''; Error = 'simulated installer failure' }
        }
        New-Item -ItemType Directory -Path $candidate -Force -ErrorAction Stop | Out-Null
        if (-not $script:candidateSkipUv) {
            Copy-Item -LiteralPath $script:candidateUvStub -Destination (Join-Path $candidate 'uv.exe') -Force -ErrorAction Stop
        }
        if (-not $script:candidateSkipUvx) {
            Copy-Item -LiteralPath $script:candidateUvxStub -Destination (Join-Path $candidate 'uvx.exe') -Force -ErrorAction Stop
        }
        return [pscustomobject]@{ ExitCode = 0; Output = 'fixture installer output'; Error = '' }
    }
}

try {
    $stubDirectory = New-TestDirectory 'stubs'
    $script:stubs = @{}
    foreach ($version in @('0.13.8', '0.13.7', '0.13.0', '0.12.0', '0.14.0')) {
        $path = Join-Path $stubDirectory ('uv-' + $version + '.exe')
        New-UvStub -Path $path -Version $version
        $script:stubs[$version] = $path
    }
    $unhealthyStub = Join-Path $stubDirectory 'uv-unhealthy.exe'
    New-UvStub -Path $unhealthyStub -Version '0.13.0' -Unhealthy

    # --- Plan and preview name the reviewed tuple without touching anything. ---
    $scenarioHome = New-Scenario 'plan'
    $reviewedDigest = Set-FixtureInstaller
    $plan = Get-PlasticineUvPlan -HomeDirectory $scenarioHome
    Assert-Equal (Join-Path $scenarioHome '.local\bin') $plan.InstallDirectory 'the plan did not target ~/.local/bin'
    Assert-Equal (Get-UvTarget $scenarioHome) $plan.UvTarget 'the plan did not target ~/.local/bin/uv.exe'
    Assert-Equal (Get-UvxTarget $scenarioHome) $plan.UvxTarget 'the plan did not target ~/.local/bin/uvx.exe'
    Assert-Equal '0.13.8' $plan.Version 'the plan lost the pinned baseline'
    Assert-Equal $reviewedDigest $plan.InstallerDigest 'the plan lost the reviewed installer digest'
    Assert-True ($plan.InstallerUrl -match '/0\.13\.8/uv-installer\.ps1$') 'the plan did not pin the versioned official installer'
    Assert-Equal 'uv.exe uvx.exe' (@($plan.Commands) -join ' ') 'the plan lost the reviewed command pair'
    Assert-True ($null -eq $plan.Observed) 'a missing uv was reported as observed'
    Assert-True ($null -eq $plan.UvxObserved) 'a missing uvx was reported as observed'
    $userPathBefore = Get-PlasticineUserPath
    $preview = Invoke-TestCapture { Write-PlasticineUvPreview -Plan $plan }
    Assert-True (-not $preview.Threw) "the preview failed: $($preview.Message)"
    Assert-True ($preview.Output -match 'pinned baseline 0\.13\.8') 'the preview lost the pinned baseline'
    Assert-True ($preview.Output -match [regex]::Escape($plan.InstallDirectory)) 'the preview did not name the destination'
    Assert-True ($preview.Output -match 'UV_NO_MODIFY_PATH=1') 'the preview lost the installer environment contract'
    Assert-True ($preview.Output -match 'uvw\.exe') 'the preview lost the unpublished-command note'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $scenarioHome '.local'))) 'the plan or preview created the managed directory'
    Assert-Equal $userPathBefore (Get-PlasticineUserPath) 'the plan or preview changed the user PATH'
    Assert-Equal 0 @(Get-Calls).Count 'the plan or preview made a request'

    # --- Preview reports an executable that PATH resolves. ---
    $scenarioHome = New-Scenario 'observed'
    $ownerBin = New-TestDirectory 'owner-bin'
    Copy-Item -LiteralPath $script:stubs['0.13.0'] -Destination (Join-Path $ownerBin 'uv.exe') -Force
    $env:PATH = $ownerBin + ';' + $emptyPath
    $plan = Get-PlasticineUvPlan -HomeDirectory $scenarioHome
    Assert-Equal (Join-Path $ownerBin 'uv.exe') $plan.Observed 'the plan did not resolve the PATH executable'
    $preview = Invoke-TestCapture { Write-PlasticineUvPreview -Plan $plan }
    Assert-True ($preview.Output -match 'Observed uv') 'the preview did not name the observed executable'

    # --- A missing pair is installed from the reviewed installer. ---
    $scenarioHome = New-Scenario 'fresh'
    $null = Set-FixtureInstaller
    Set-CandidateRunner -Version '0.13.8'
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'uv' -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the fresh install failed: $($run.Message)"
    Assert-True ($run.Output -match 'install completed at stable target 0\.13\.8') 'the fresh install was not reported'
    Assert-Equal 1 @(Get-Calls).Count 'the fresh install made more than one request'
    Assert-True (@(Get-Calls)[0] -match '/0\.13\.8/uv-installer\.ps1$') 'the reviewed installer was not requested'
    Assert-Equal 1 @($script:runnerCalls).Count 'the reviewed installer did not run exactly once'
    $record = @($script:runnerCalls)[0]
    Assert-Equal 'uv-installer.ps1' (Split-Path -Leaf $record.Installer) 'the reviewed script was not handed to the runner'
    Assert-Equal '1' $record.Environment['UV_NO_MODIFY_PATH'] 'the installer was allowed to edit PATH'
    Assert-Equal '1' $record.Environment['UV_DISABLE_UPDATE'] 'the installer was allowed to write an updater receipt'
    Assert-Equal $record.Candidate $record.Environment['UV_INSTALL_DIR'] 'UV_INSTALL_DIR did not name the private candidate'
    Assert-True (-not $record.Environment.ContainsKey('UV_UNMANAGED_INSTALL')) 'an unmanaged-install override reached the installer'
    Assert-True (-not $record.Candidate.StartsWith($scenarioHome, [StringComparison]::OrdinalIgnoreCase)) `
        'the reviewed installer was pointed at the managed destination'
    Assert-True (-not (Test-Path -LiteralPath $record.Candidate)) 'the private candidate directory was not discarded'
    Assert-Equal '0.13.8' (Get-PlasticineExecutableVersion (Get-UvTarget $scenarioHome)) 'the pinned uv was not published'
    Assert-Equal '0.13.8' (Get-PlasticineExecutableVersion (Get-UvxTarget $scenarioHome)) 'the pinned uvx was not published'
    Assert-NoStaging $scenarioHome
    Assert-Equal $userPathBefore (Get-PlasticineUserPath) 'the uv route changed the user PATH'
    $localAcl = (Get-Acl -LiteralPath (Join-Path $scenarioHome '.local')).Sddl
    $binAcl = (Get-Acl -LiteralPath (Join-Path $scenarioHome '.local\bin')).Sddl
    Assert-True ($localAcl -match 'D:PAI') "the new .local directory is not owner-only: $localAcl"
    Assert-True ($binAcl -match 'D:PAI') "the new bin directory is not owner-only: $binAcl"

    # --- The satisfied baseline is reused without installer traffic. ---
    $installedUvHash = Get-PlasticineFileHash (Get-UvTarget $scenarioHome)
    $installedUvxHash = Get-PlasticineFileHash (Get-UvxTarget $scenarioHome)
    Reset-Calls
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'uv' -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the reuse run failed: $($run.Message)"
    Assert-True ($run.Output -match 'is satisfied by stable 0\.13\.8') 'reuse was not reported'
    Assert-Equal 0 @(Get-Calls).Count 'a satisfied pair caused installer traffic'
    Assert-Equal 0 @($script:runnerCalls).Count 'a satisfied pair ran the installer'
    Assert-Equal $installedUvHash (Get-PlasticineFileHash (Get-UvTarget $scenarioHome)) 'the current uv was replaced'
    Assert-Equal $installedUvxHash (Get-PlasticineFileHash (Get-UvxTarget $scenarioHome)) 'the current uvx was replaced'

    # --- A newer managed pair is retained, never downgraded. ---
    $scenarioHome = New-Scenario 'newer'
    Assert-ManagedPair -HomeDirectory $scenarioHome -Version '0.14.0'
    $beforeUv = Get-PlasticineFileHash (Get-UvTarget $scenarioHome)
    $beforeUvx = Get-PlasticineFileHash (Get-UvxTarget $scenarioHome)
    $null = Set-FixtureInstaller
    Set-CandidateRunner -Version '0.13.8'
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'uv' -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the newer managed run failed: $($run.Message)"
    Assert-True ($run.Output -match 'is satisfied by stable 0\.14\.0') 'the newer managed pair was not reused'
    Assert-Equal 0 @(Get-Calls).Count 'a newer managed pair caused installer traffic'
    Assert-Equal $beforeUv (Get-PlasticineFileHash (Get-UvTarget $scenarioHome)) 'a newer uv was downgraded'
    Assert-Equal $beforeUvx (Get-PlasticineFileHash (Get-UvxTarget $scenarioHome)) 'a newer uvx was downgraded'

    # --- An older managed pair is replaced in place. ---
    $scenarioHome = New-Scenario 'update'
    Assert-ManagedPair -HomeDirectory $scenarioHome -Version '0.13.0'
    $outdatedUvHash = Get-PlasticineFileHash (Get-UvTarget $scenarioHome)
    $null = Set-FixtureInstaller
    Set-CandidateRunner -Version '0.13.8'
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'uv' -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the update run failed: $($run.Message)"
    Assert-True ($run.Output -match 'update completed at stable target 0\.13\.8') 'the update was not reported'
    Assert-Equal 1 @(Get-Calls).Count 'the update did not request the reviewed installer'
    Assert-Equal '0.13.8' (Get-PlasticineExecutableVersion (Get-UvTarget $scenarioHome)) 'the outdated uv was not replaced'
    Assert-Equal '0.13.8' (Get-PlasticineExecutableVersion (Get-UvxTarget $scenarioHome)) 'the outdated uvx was not replaced'
    Assert-True ($outdatedUvHash -ne (Get-PlasticineFileHash (Get-UvTarget $scenarioHome))) 'the outdated uv was retained'
    Assert-NoStaging $scenarioHome

    # --- A mismatched managed pair is repaired as a pair. ---
    $scenarioHome = New-Scenario 'repair'
    Assert-ManagedPair -HomeDirectory $scenarioHome -Version '0.13.0' -UvxVersion '0.12.0'
    $null = Set-FixtureInstaller
    Set-CandidateRunner -Version '0.13.8'
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'uv' -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the repair run failed: $($run.Message)"
    Assert-True ($run.Output -match 'reason=uv and uvx versions differ') 'the repair reason was not reported'
    Assert-True ($run.Output -match 'repair completed at stable target 0\.13\.8') 'the repair was not reported'
    Assert-Equal '0.13.8' (Get-PlasticineExecutableVersion (Get-UvxTarget $scenarioHome)) 'the mismatched uvx was not repaired'
    Assert-NoStaging $scenarioHome

    # --- An installation owned elsewhere is never shadowed. ---
    $scenarioHome = New-Scenario 'foreign'
    $foreignBin = New-TestDirectory 'foreign-bin'
    Copy-Item -LiteralPath $script:stubs['0.13.0'] -Destination (Join-Path $foreignBin 'uv.exe') -Force
    $env:PATH = $foreignBin + ';' + $emptyPath
    $foreignHash = Get-PlasticineFileHash (Join-Path $foreignBin 'uv.exe')
    $null = Set-FixtureInstaller
    Set-CandidateRunner -Version '0.13.8'
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'uv' -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'an external uv reported success'
    Assert-True ($run.Error -match 'external uv at .*No shadow installation') 'the external owner was not reported'
    Assert-Equal 0 @(Get-Calls).Count 'the external owner caused installer traffic'
    Assert-Equal 0 @($script:runnerCalls).Count 'the external owner ran the installer'
    Assert-Equal $foreignHash (Get-PlasticineFileHash (Join-Path $foreignBin 'uv.exe')) 'the external owner was modified'
    Assert-True (-not (Test-Path -LiteralPath (Get-UvTarget $scenarioHome))) 'a shadow uv was installed'

    # --- An unhealthy managed installation is left for its owner. ---
    $scenarioHome = New-Scenario 'unhealthy'
    Assert-ManagedPair -HomeDirectory $scenarioHome -Version '0.13.0'
    Copy-Item -LiteralPath $unhealthyStub -Destination (Get-UvTarget $scenarioHome) -Force
    $null = Set-FixtureInstaller
    Set-CandidateRunner -Version '0.13.8'
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'uv' -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'an unhealthy managed uv reported success'
    Assert-True ($run.Error -match 'managed uv is unhealthy') 'the unhealthy managed uv was not reported'
    Assert-Equal 0 @(Get-Calls).Count 'an unhealthy managed uv caused installer traffic'

    # --- A candidate that is not the reviewed version keeps the old pair. ---
    $scenarioHome = New-Scenario 'candidate-version'
    Assert-ManagedPair -HomeDirectory $scenarioHome -Version '0.13.0'
    $beforeUv = Get-PlasticineFileHash (Get-UvTarget $scenarioHome)
    $beforeUvx = Get-PlasticineFileHash (Get-UvxTarget $scenarioHome)
    $null = Set-FixtureInstaller
    # The fixture candidate is a different binary, so its reviewed digest is
    # pinned here and the version check becomes the active refusal.
    $script:PlasticineUvCommandDigests = @{
        'uv.exe'  = (Get-PlasticineFileHash $script:stubs['0.13.7'])
        'uvx.exe' = (Get-PlasticineFileHash $script:stubs['0.13.7'])
    }
    Set-CandidateRunner -Version '0.13.7'
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'uv' -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'an unreviewed candidate version reported success'
    Assert-True ($run.Error -match 'uv\.exe version 0\.13\.7, not the reviewed target 0\.13\.8') 'the candidate version failure was not reported'
    Assert-Equal $beforeUv (Get-PlasticineFileHash (Get-UvTarget $scenarioHome)) 'the candidate failure replaced the working uv'
    Assert-Equal $beforeUvx (Get-PlasticineFileHash (Get-UvxTarget $scenarioHome)) 'the candidate failure replaced the working uvx'
    Assert-NoStaging $scenarioHome

    # --- A candidate that does not match the reviewed SHA-256 is refused. ---
    $scenarioHome = New-Scenario 'candidate-digest'
    $null = Set-FixtureInstaller
    $script:PlasticineUvCommandDigests = @{ 'uv.exe' = ('0' * 64); 'uvx.exe' = ('0' * 64) }
    Set-CandidateRunner -Version '0.13.8'
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'uv' -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'a candidate with the wrong digest reported success'
    Assert-True ($run.Error -match 'does not match the reviewed SHA-256') 'the candidate digest failure was not reported'
    Assert-True (-not (Test-Path -LiteralPath (Get-UvTarget $scenarioHome))) 'the unreviewed candidate was published'
    Assert-NoStaging $scenarioHome

    # --- A missing candidate command is refused. ---
    $scenarioHome = New-Scenario 'candidate-missing'
    $null = Set-FixtureInstaller
    $script:PlasticineUvCommandDigests = @{}
    Set-CandidateRunner -Version '0.13.8' -SkipUvx
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'uv' -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'an incomplete candidate reported success'
    Assert-True ($run.Error -match 'did not produce a regular uvx\.exe') 'the incomplete candidate was not reported'
    Assert-True (-not (Test-Path -LiteralPath (Get-UvxTarget $scenarioHome))) 'the incomplete candidate was published'
    Assert-NoStaging $scenarioHome

    # --- The reviewed installer digest is enforced before execution. ---
    $scenarioHome = New-Scenario 'installer-digest'
    $null = Set-FixtureInstaller
    $savedDigest = $script:PlasticineUvInstallerDigest
    $script:PlasticineUvInstallerDigest = ('0' * 64)
    Set-CandidateRunner -Version '0.13.8'
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'uv' -HomeDirectory $scenarioHome }
    $script:PlasticineUvInstallerDigest = $savedDigest
    Assert-True $run.Threw 'an installer digest mismatch reported success'
    Assert-True ($run.Error -match 'SHA-256 mismatch') 'the installer digest mismatch was not reported'
    Assert-Equal 0 @($script:runnerCalls).Count 'an unreviewed installer was executed'
    Assert-True (-not (Test-Path -LiteralPath (Get-UvTarget $scenarioHome))) 'an unreviewed installer published a target'

    # --- The installer identity lines are enforced before execution. ---
    $scenarioHome = New-Scenario 'installer-identity'
    $null = Set-FixtureInstaller -NoIdentity
    Set-CandidateRunner -Version '0.13.8'
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'uv' -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'an installer without its identity lines reported success'
    Assert-True ($run.Error -match 'identity check failed') 'the installer identity failure was not reported'
    Assert-Equal 0 @($script:runnerCalls).Count 'an unreviewed installer was executed'
    Assert-True (-not (Test-Path -LiteralPath (Get-UvTarget $scenarioHome))) 'an unreviewed installer published a target'

    # --- An installer failure preserves the working pair. ---
    $scenarioHome = New-Scenario 'installer-failure'
    Assert-ManagedPair -HomeDirectory $scenarioHome -Version '0.13.0'
    $beforeUv = Get-PlasticineFileHash (Get-UvTarget $scenarioHome)
    $null = Set-FixtureInstaller
    Set-CandidateRunner -Version '0.13.8' -ExitCode 1
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'uv' -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'a failed installer reported success'
    Assert-True ($run.Error -match 'official installer failed') 'the installer failure was not reported'
    Assert-True ($run.Error -match 'simulated installer failure') 'the installer diagnostics were dropped'
    Assert-Equal $beforeUv (Get-PlasticineFileHash (Get-UvTarget $scenarioHome)) 'the failed install replaced the working uv'
    Assert-NoStaging $scenarioHome

    # --- A download failure preserves the working pair. ---
    $scenarioHome = New-Scenario 'download-failure'
    Assert-ManagedPair -HomeDirectory $scenarioHome -Version '0.13.0'
    $beforeUv = Get-PlasticineFileHash (Get-UvTarget $scenarioHome)
    $null = Set-FixtureInstaller
    Set-CandidateRunner -Version '0.13.8'
    $env:PLASTICINE_TEST_DOWNLOAD_FAIL = '1'
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'uv' -HomeDirectory $scenarioHome }
    Remove-Item Env:\PLASTICINE_TEST_DOWNLOAD_FAIL -ErrorAction SilentlyContinue
    Assert-True $run.Threw 'a download failure reported success'
    Assert-True ($run.Error -match 'official installer download failed') 'the download failure was not reported'
    Assert-Equal $beforeUv (Get-PlasticineFileHash (Get-UvTarget $scenarioHome)) 'the download failure replaced the working uv'
    Assert-NoStaging $scenarioHome

    # --- A target that is not a regular file is refused before any work. ---
    $scenarioHome = New-Scenario 'target-directory'
    New-Item -ItemType Directory -Path (Get-UvTarget $scenarioHome) -Force | Out-Null
    $run = Invoke-TestCapture { Get-PlasticineUvPlan -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'a directory uv target was accepted'
    Assert-True ($run.Error -match 'installation target is not a regular file') 'the irregular target was not reported'

    $scenarioHome = New-Scenario 'target-directory-uvx'
    New-Item -ItemType Directory -Path (Get-UvxTarget $scenarioHome) -Force | Out-Null
    $run = Invoke-TestCapture { Get-PlasticineUvPlan -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'a directory uvx target was accepted'
    Assert-True ($run.Error -match 'installation target is not a regular file') 'the irregular uvx target was not reported'

    Complete-Test 'windows uv tests passed'
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
} finally {
    $env:PATH = $savedPath
    Remove-Item Env:\PLASTICINE_TEST_DOWNLOAD_FAIL -ErrorAction SilentlyContinue
    $script:PlasticineUserEnvironmentSubKey = $savedUserEnvironmentSubKey
    try {
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree('Software\PlasticineWindowsTests', $false)
    } catch {
    }
    Remove-TestRootSafely
}
