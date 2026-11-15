# Coverage for the Windows tool routes. The first provider is Lazygit: the
# pinned baseline, the reuse and authorized-replacement rules, the reviewed
# artifact tuple and both publication paths run against offline fixtures only.

$repoDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'harness.ps1')
$PlasticineTestName = 'windows tools'
. (Join-Path $repoDir 'lib\windows\common.ps1')
. (Join-Path $repoDir 'lib\windows\publish.ps1')
. (Join-Path $repoDir 'lib\windows\acl.ps1')
. (Join-Path $repoDir 'lib\windows\features.ps1')
. (Join-Path $repoDir 'lib\windows\feature-lazygit.ps1')

$callsFile = Join-Path $PlasticineTestRoot 'calls'
$fixture = New-TestDirectory 'fixture'
$payload = New-TestDirectory 'payload'
$assetName = 'lazygit_0.65.1_windows_x86_64.zip'
$savedPath = $env:PATH
# Every scenario gets a PATH that cannot resolve a tool the operator happens to
# have installed, so "missing" and "found" are decisions of the fixture.
$emptyPath = New-TestDirectory 'empty-path'

function Reset-Calls { Set-Content -LiteralPath $callsFile -Value @() }
function Get-Calls {
    if (Test-Path -LiteralPath $callsFile) { return @(Get-Content -LiteralPath $callsFile) }
    return @()
}

function Invoke-PlasticineDownload {
    param([string]$Url, [string]$Destination, [string]$FailureMessage)
    Add-Content -LiteralPath $callsFile -Value $Url
    if ($env:PLASTICINE_TEST_DOWNLOAD_FAIL) { Stop-Plasticine $FailureMessage }
    Copy-Item -LiteralPath (Join-Path $fixture (Split-Path -Leaf $Url)) -Destination $Destination -ErrorAction Stop
}

# Lazygit prints a comma-separated field list, so the shared chezmoi stub shape
# cannot stand in for it; this stub reproduces the reviewed version field only.
function New-LazygitStub {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Version = '0.65.1',
        [switch]$Unhealthy,
        [switch]$Prerelease
    )
    if ($Unhealthy) {
        $body = 'Environment.Exit(9);'
    } elseif ($Prerelease) {
        $body = 'Console.WriteLine("version=v0.66.0-beta"); return;'
    } else {
        $body = 'Console.WriteLine("version=' + $Version + '"); return;'
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

function Get-Target {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    return Join-Path $HomeDirectory '.local\bin\lazygit.exe'
}

function Assert-NoStaging {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    $bin = Join-Path $HomeDirectory '.local\bin'
    if (Test-Path -LiteralPath $bin) {
        Assert-Equal 0 (@(Get-ChildItem -LiteralPath $bin -Force -Filter '.lazygit.plasticine.*').Count) `
            'a run left a staged file behind'
    }
}

# Rebuilds the single reviewed archive name from the given payload stub, pins the
# module to the resulting digest, and returns it, so each scenario reviews
# exactly the artifact it exercises without network traffic.
function Set-FixtureArchive {
    param(
        [Parameter(Mandatory = $true)][string]$Stub,
        [string[]]$ExtraEntry
    )
    Copy-Item -LiteralPath $Stub -Destination (Join-Path $payload 'lazygit.exe') -Force
    $files = @(
        (Join-Path $payload 'LICENSE'),
        (Join-Path $payload 'README.md'),
        (Join-Path $payload 'lazygit.exe')
    )
    New-TestZip -Path (Join-Path $fixture $assetName) -File $files -ExtraEntry $ExtraEntry
    $digest = Get-PlasticineFileHash (Join-Path $fixture $assetName)
    $script:PlasticineLazygitDigest = $digest
    return $digest
}

function Get-LazygitPlan {
    param(
        [Parameter(Mandatory = $true)][string]$HomeDirectory,
        [string]$Digest
    )
    $plan = Get-PlasticineLazygitPlan -HomeDirectory $HomeDirectory
    if ($Digest) { $plan.Digest = $Digest }
    return $plan
}

function Assert-DirectInstall {
    param(
        [Parameter(Mandatory = $true)][string]$HomeDirectory,
        [Parameter(Mandatory = $true)][string]$Stub
    )
    $bin = Join-Path $HomeDirectory '.local\bin'
    New-Item -ItemType Directory -Path $bin -Force -ErrorAction Stop | Out-Null
    Copy-Item -LiteralPath $Stub -Destination (Join-Path $bin 'lazygit.exe') -Force -ErrorAction Stop
}

try {
    $stubDirectory = New-TestDirectory 'stubs'
    $stubs = @{}
    foreach ($version in @('0.65.1', '0.64.0', '0.66.0', '0.60.0')) {
        $path = Join-Path $stubDirectory ("lazygit-$version.exe")
        New-LazygitStub -Path $path -Version $version
        $stubs[$version] = $path
    }
    $unhealthyStub = Join-Path $stubDirectory 'lazygit-unhealthy.exe'
    New-LazygitStub -Path $unhealthyStub -Unhealthy
    $prereleaseStub = Join-Path $stubDirectory 'lazygit-prerelease.exe'
    New-LazygitStub -Path $prereleaseStub -Prerelease
    Set-Content -LiteralPath (Join-Path $payload 'LICENSE') -Value 'license' -NoNewline
    Set-Content -LiteralPath (Join-Path $payload 'README.md') -Value 'readme' -NoNewline

    # --- Plan and preview name the reviewed tuple without touching anything. ---
    $scenarioHome = New-Scenario 'plan'
    $reviewedDigest = Set-FixtureArchive -Stub $stubs['0.65.1']
    $plan = Get-LazygitPlan -HomeDirectory $scenarioHome -Digest $reviewedDigest
    Assert-Equal (Get-Target $scenarioHome) $plan.Target 'the plan did not target ~/.local/bin/lazygit.exe'
    Assert-Equal '0.65.1' $plan.Version 'the plan lost the pinned baseline'
    Assert-Equal $reviewedDigest $plan.Digest 'the plan lost the reviewed digest'
    Assert-True ($plan.ReleaseUrl -match '/v0\.65\.1/lazygit_0\.65\.1_windows_x86_64\.zip$') `
        'the plan did not pin the official versioned release asset'
    Assert-Equal 'LICENSE README.md lazygit.exe' (@($plan.Member) -join ' ') 'the plan lost the reviewed member set'
    Assert-True ($null -eq $plan.Observed) 'a missing tool was reported as observed'
    $preview = Invoke-TestCapture { Write-PlasticineLazygitPreview -Plan $plan }
    Assert-True (-not $preview.Threw) "the preview failed: $($preview.Message)"
    Assert-True ($preview.Output -match 'pinned baseline 0\.65\.1') 'the preview lost the pinned baseline'
    Assert-True ($preview.Output -match [regex]::Escape($plan.Target)) 'the preview did not name the destination'
    Assert-True ($preview.Output -notmatch 'Observed executable') 'the preview invented an observed executable'
    Assert-True (-not (Test-Path -LiteralPath (Get-Target $scenarioHome))) 'the preview published a target'
    Assert-Equal 0 @(Get-Calls).Count 'the preview made a release request'

    # --- Preview reports an executable that PATH resolves. ---
    $scenarioHome = New-Scenario 'observed'
    $ownerBin = New-TestDirectory 'owner-bin'
    Copy-Item -LiteralPath $stubs['0.66.0'] -Destination (Join-Path $ownerBin 'lazygit.exe') -Force
    $env:PATH = $ownerBin + ';' + $emptyPath
    $plan = Get-LazygitPlan -HomeDirectory $scenarioHome -Digest (Set-FixtureArchive -Stub $stubs['0.65.1'])
    Assert-Equal (Join-Path $ownerBin 'lazygit.exe') $plan.Observed 'the plan did not resolve the PATH executable'
    $preview = Invoke-TestCapture { Write-PlasticineLazygitPreview -Plan $plan }
    Assert-True ($preview.Output -match 'Observed executable') 'the preview did not name the observed executable'

    # --- A missing tool installs the pinned release through the registry. ---
    $scenarioHome = New-Scenario 'fresh'
    $reviewedDigest = Set-FixtureArchive -Stub $stubs['0.65.1']
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'lazygit' -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the fresh install failed: $($run.Message)"
    Assert-True ($run.Output -match 'fresh completed at stable target 0\.65\.1') 'the fresh install was not reported'
    Assert-Equal 1 @(Get-Calls).Count 'the fresh install made more than one request'
    Assert-True (@(Get-Calls)[0] -match '/v0\.65\.1/lazygit_0\.65\.1_windows_x86_64\.zip$') `
        'the reviewed pinned asset was not selected'
    Assert-Equal '0.65.1' (Get-PlasticineLazygitVersion (Get-Target $scenarioHome)) 'the pinned release was not installed'
    Assert-NoStaging $scenarioHome
    $localAcl = (Get-Acl -LiteralPath (Join-Path $scenarioHome '.local')).Sddl
    $binAcl = (Get-Acl -LiteralPath (Join-Path $scenarioHome '.local\bin')).Sddl
    Assert-True ($localAcl -match 'D:PAI') "the new .local directory is not owner-only: $localAcl"
    Assert-True ($binAcl -match 'D:PAI') "the new bin directory is not owner-only: $binAcl"

    # --- The satisfied baseline is reused without release traffic. ---
    $installedHash = Get-PlasticineFileHash (Get-Target $scenarioHome)
    Reset-Calls
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'lazygit' -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the reuse run failed: $($run.Message)"
    Assert-True ($run.Output -match 'is satisfied by stable 0\.65\.1') 'reuse was not reported'
    Assert-Equal 0 @(Get-Calls).Count 'a satisfied check made a release request'
    Assert-Equal $installedHash (Get-PlasticineFileHash (Get-Target $scenarioHome)) 'the current executable was replaced'

    # --- A newer direct installation is retained. ---
    $scenarioHome = New-Scenario 'newer-direct'
    Assert-DirectInstall -HomeDirectory $scenarioHome -Stub $stubs['0.66.0']
    $newerHash = Get-PlasticineFileHash (Get-Target $scenarioHome)
    $null = Set-FixtureArchive -Stub $stubs['0.65.1']
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'lazygit' -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the newer direct run failed: $($run.Message)"
    Assert-Equal 0 @(Get-Calls).Count 'a newer installation caused release traffic'
    Assert-Equal $newerHash (Get-PlasticineFileHash (Get-Target $scenarioHome)) 'a newer installation was downgraded'

    # --- An outdated direct installation at the managed target is replaced. ---
    $scenarioHome = New-Scenario 'upgrade'
    Assert-DirectInstall -HomeDirectory $scenarioHome -Stub $stubs['0.64.0']
    $outdatedHash = Get-PlasticineFileHash (Get-Target $scenarioHome)
    $null = Set-FixtureArchive -Stub $stubs['0.65.1']
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'lazygit' -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the upgrade run failed: $($run.Message)"
    Assert-True ($run.Output -match 'upgrade completed at stable target 0\.65\.1') 'the upgrade was not reported'
    Assert-Equal 1 @(Get-Calls).Count 'the upgrade did not request the reviewed asset'
    Assert-Equal '0.65.1' (Get-PlasticineLazygitVersion (Get-Target $scenarioHome)) 'the outdated executable was not replaced'
    Assert-True ($outdatedHash -ne (Get-PlasticineFileHash (Get-Target $scenarioHome))) 'the outdated executable was retained'
    Assert-NoStaging $scenarioHome

    # --- An outdated installation owned elsewhere is never shadowed. ---
    $scenarioHome = New-Scenario 'foreign-owner'
    $foreignBin = New-TestDirectory 'foreign-bin'
    Copy-Item -LiteralPath $stubs['0.64.0'] -Destination (Join-Path $foreignBin 'lazygit.exe') -Force
    $env:PATH = $foreignBin + ';' + $emptyPath
    $foreignHash = Get-PlasticineFileHash (Join-Path $foreignBin 'lazygit.exe')
    $null = Set-FixtureArchive -Stub $stubs['0.65.1']
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'lazygit' -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'an unsupported owner reported success'
    Assert-True ($run.Error -match 'unsupported owner path') 'the unsupported owner was not reported'
    Assert-Equal 0 @(Get-Calls).Count 'the unsupported owner caused release traffic'
    Assert-Equal $foreignHash (Get-PlasticineFileHash (Join-Path $foreignBin 'lazygit.exe')) 'the foreign owner was modified'
    Assert-True (-not (Test-Path -LiteralPath (Get-Target $scenarioHome))) 'a shadow installation was created'

    # --- An unhealthy installation is left for its owner. ---
    $scenarioHome = New-Scenario 'unhealthy'
    Assert-DirectInstall -HomeDirectory $scenarioHome -Stub $unhealthyStub
    $null = Set-FixtureArchive -Stub $stubs['0.65.1']
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'lazygit' -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'an unhealthy installation reported success'
    Assert-True ($run.Error -match 'existing executable is unhealthy') 'the unhealthy installation was not reported'
    Assert-Equal 0 @(Get-Calls).Count 'the unhealthy installation caused release traffic'

    # --- A custom or prerelease version is left for its owner. ---
    $scenarioHome = New-Scenario 'prerelease'
    Assert-DirectInstall -HomeDirectory $scenarioHome -Stub $prereleaseStub
    $null = Set-FixtureArchive -Stub $stubs['0.65.1']
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'lazygit' -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'a prerelease installation reported success'
    Assert-True ($run.Error -match 'custom, prerelease, or unparseable version') 'the prerelease installation was not reported'
    Assert-Equal 0 @(Get-Calls).Count 'the prerelease installation caused release traffic'

    # --- A download failure preserves the working executable. ---
    $scenarioHome = New-Scenario 'download-failure'
    Assert-DirectInstall -HomeDirectory $scenarioHome -Stub $stubs['0.64.0']
    $before = Get-PlasticineFileHash (Get-Target $scenarioHome)
    $null = Set-FixtureArchive -Stub $stubs['0.65.1']
    $env:PLASTICINE_TEST_DOWNLOAD_FAIL = '1'
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'lazygit' -HomeDirectory $scenarioHome }
    Remove-Item Env:\PLASTICINE_TEST_DOWNLOAD_FAIL -ErrorAction SilentlyContinue
    Assert-True $run.Threw 'a download failure reported success'
    Assert-True ($run.Error -match 'release archive download failed; active installation was left untouched') `
        'the download failure was not reported'
    Assert-Equal $before (Get-PlasticineFileHash (Get-Target $scenarioHome)) 'the download failure changed the working executable'
    Assert-NoStaging $scenarioHome

    # --- A digest mismatch never publishes a target. ---
    $scenarioHome = New-Scenario 'digest-mismatch'
    $null = Set-FixtureArchive -Stub $stubs['0.65.1']
    $plan = Get-LazygitPlan -HomeDirectory $scenarioHome -Digest ('0' * 64)
    $run = Invoke-TestCapture { Invoke-PlasticineLazygitPrepare -Plan $plan }
    Assert-True $run.Threw 'a digest mismatch reported success'
    Assert-True ($run.Error -match 'release archive SHA-256 mismatch') 'the digest mismatch was not reported'
    Assert-True (-not (Test-Path -LiteralPath (Get-Target $scenarioHome))) 'the digest mismatch published a target'
    Assert-NoStaging $scenarioHome

    # --- An archive with an unexpected member set is refused. ---
    $scenarioHome = New-Scenario 'archive-members'
    $unexpectedDigest = Set-FixtureArchive -Stub $stubs['0.65.1'] -ExtraEntry @('extra.txt')
    $plan = Get-LazygitPlan -HomeDirectory $scenarioHome -Digest $unexpectedDigest
    $run = Invoke-TestCapture { Invoke-PlasticineLazygitPrepare -Plan $plan }
    Assert-True $run.Threw 'an unexpected archive member reported success'
    Assert-True ($run.Error -match 'archive members do not match the reviewed layout') 'the member failure was not reported'
    Assert-True (-not (Test-Path -LiteralPath (Get-Target $scenarioHome))) 'the member failure published a target'

    # --- A candidate that is not the pinned version is refused. ---
    $scenarioHome = New-Scenario 'candidate-version'
    $candidateDigest = Set-FixtureArchive -Stub $stubs['0.60.0']
    $plan = Get-LazygitPlan -HomeDirectory $scenarioHome -Digest $candidateDigest
    $run = Invoke-TestCapture { Invoke-PlasticineLazygitPrepare -Plan $plan }
    Assert-True $run.Threw 'a wrong candidate version reported success'
    Assert-True ($run.Error -match 'does not match resolved target 0\.65\.1') 'the candidate failure was not reported'
    Assert-True (-not (Test-Path -LiteralPath (Get-Target $scenarioHome))) 'the candidate failure published a target'

    # --- A target that is not a regular file is refused before any work. ---
    $scenarioHome = New-Scenario 'target-directory'
    New-Item -ItemType Directory -Path (Get-Target $scenarioHome) -Force | Out-Null
    $run = Invoke-TestCapture { Get-PlasticineLazygitPlan -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'a directory installation target was accepted'
    Assert-True ($run.Error -match 'installation target is not a regular file') 'the irregular target was not reported'

    # --- A conflicting target that appears mid-preparation aborts the update. ---
    $scenarioHome = New-Scenario 'upgrade-race'
    Assert-DirectInstall -HomeDirectory $scenarioHome -Stub $stubs['0.64.0']
    $null = Set-FixtureArchive -Stub $stubs['0.65.1']
    $originalExpand = ${function:Expand-PlasticineArchive}
    function Expand-PlasticineArchive {
        param($Archive, $Destination, $Member)
        Set-Content -LiteralPath (Get-Target $scenarioHome) -Value 'competing owner' -NoNewline
        & $originalExpand -Archive $Archive -Destination $Destination -Member $Member
    }
    $run = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'lazygit' -HomeDirectory $scenarioHome }
    ${function:Expand-PlasticineArchive} = $originalExpand
    Assert-True $run.Threw 'a target changed during preparation reported success'
    Assert-True ($run.Error -match 'installation target changed during preparation') 'the preparation race was not reported'
    Remove-Item -LiteralPath (Get-Target $scenarioHome) -Force -ErrorAction SilentlyContinue
    Assert-NoStaging $scenarioHome

    Complete-Test 'windows tools tests passed'
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
} finally {
    $env:PATH = $savedPath
    Remove-Item Env:\PLASTICINE_TEST_DOWNLOAD_FAIL -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $PlasticineTestRoot -Recurse -Force -ErrorAction SilentlyContinue
}
