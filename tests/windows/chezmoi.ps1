# Integration coverage for the Windows chezmoi prerequisite, using controlled
# assets and a download fixture. No release traffic and no real installation.

$repoDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'harness.ps1')
$PlasticineTestName = 'windows chezmoi'
. (Join-Path $repoDir 'lib\windows\chezmoi-bootstrap.ps1')

$callsFile = Join-Path $PlasticineTestRoot 'calls'
$fixture = New-TestDirectory 'fixture'
$assetName = 'chezmoi_2.72.1_windows_amd64.zip'
$savedPath = $env:PATH
$savedArchitecture = $env:PROCESSOR_ARCHITECTURE

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

function New-Scenario {
    param([Parameter(Mandatory = $true)][string]$Name)
    $scenarioHome = Join-Path (New-TestDirectory $Name) 'home'
    New-Item -ItemType Directory -Path $scenarioHome -ErrorAction Stop | Out-Null
    Reset-Calls
    return $scenarioHome
}

function Set-DirectChezmoi {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory, [Parameter(Mandatory = $true)][string]$Stub)
    $bin = Join-Path $HomeDirectory '.local\bin'
    New-Item -ItemType Directory -Path $bin -Force -ErrorAction Stop | Out-Null
    Copy-Item -LiteralPath $Stub -Destination (Join-Path $bin 'chezmoi.exe') -Force -ErrorAction Stop
}

function Get-Target {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    return Join-Path $HomeDirectory '.local\bin\chezmoi.exe'
}

function Assert-NoStaging {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    $bin = Join-Path $HomeDirectory '.local\bin'
    if (Test-Path -LiteralPath $bin) {
        Assert-Equal 0 (@(Get-ChildItem -LiteralPath $bin -Force -Filter '.chezmoi.plasticine.*').Count) `
            'a failed run left a staged file behind'
    }
}

# Stops print to stderr before throwing, so the probe captures both the stream
# and the exception object the installer uses for its exit-code decision.
function Invoke-StopProbe {
    param([Parameter(Mandatory = $true)][scriptblock]$Body)
    $captured = New-Object IO.StringWriter
    $previous = [Console]::Error
    [Console]::SetError($captured)
    $exception = $null
    try {
        & $Body
    } catch {
        $exception = $_.Exception
    } finally {
        [Console]::SetError($previous)
    }
    return [pscustomobject]@{ Exception = $exception; Error = $captured.ToString() }
}

try {
    Assert-True (-not (Get-PlasticineCommandPath 'chezmoi')) `
        'the suite needs a PATH without chezmoi; remove it or run in a clean environment'

    # --- Controlled assets: one reviewed zip per candidate behaviour. ---
    $stubDir = New-TestDirectory 'stubs'
    $stubs = @{}
    foreach ($version in @('2.72.1', '2.72.0', '2.73.0')) {
        $path = Join-Path $stubDir "chezmoi-$version.exe"
        New-TestStub -Path $path -Version $version
        $stubs[$version] = $path
    }
    $unhealthyStub = Join-Path $stubDir 'unhealthy.exe'
    New-TestStub -Path $unhealthyStub -Version '2.72.1' -Unhealthy
    $prereleaseStub = Join-Path $stubDir 'prerelease.exe'
    New-TestStub -Path $prereleaseStub -Version '2.73.0-rc1'

    $payloadDir = New-TestDirectory 'payload'
    Copy-Item -LiteralPath $stubs['2.72.1'] -Destination (Join-Path $payloadDir 'chezmoi.exe')
    New-TestZip -Path (Join-Path $fixture $assetName) -File @((Join-Path $payloadDir 'chezmoi.exe'))
    $reviewedDigest = Get-PlasticineFileHash (Join-Path $fixture $assetName)
    $PlasticineChezmoiAssets[$assetName] = $reviewedDigest

    # --- Missing owner installs the pinned release and nothing else. ---
    $scenarioHome = New-Scenario 'install'
    $run = Invoke-TestCapture { Invoke-PlasticineChezmoiBootstrap -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the install run failed: $($run.Message)"
    Assert-Equal (Get-Target $scenarioHome) $run.Value 'the bootstrap did not return the published target'
    Assert-True ($run.Output -match 'observed=missing; target=2\.72\.1; action=install') 'the install action was not reported'
    Assert-True ($run.Output -match 'install completed at') 'the completed install was not reported'
    Assert-Equal 1 @(Get-Calls).Count 'the install made more than one request'
    Assert-True (@(Get-Calls)[0] -match '/v2\.72\.1/chezmoi_2\.72\.1_windows_amd64\.zip$') 'the reviewed pinned asset was not selected'
    Assert-True (-not (@(Get-Calls) -match 'api\.github\.com')) 'the bootstrap queried the GitHub API'
    Assert-Equal '2.72.1' (Get-PlasticineExecutableVersion (Get-Target $scenarioHome)) 'the pinned release was not installed'
    Assert-NoStaging $scenarioHome
    $localAcl = (Get-Acl -LiteralPath (Join-Path $scenarioHome '.local')).Sddl
    $binAcl = (Get-Acl -LiteralPath (Join-Path $scenarioHome '.local\bin')).Sddl
    Assert-True ($localAcl -match 'D:PAI') "the new .local directory is not owner-only: $localAcl"
    Assert-True ($binAcl -match 'D:PAI') "the new bin directory is not owner-only: $binAcl"

    # --- A satisfied pin is reused without any release traffic. ---
    $installedHash = Get-PlasticineFileHash (Get-Target $scenarioHome)
    Reset-Calls
    $run = Invoke-TestCapture { Invoke-PlasticineChezmoiBootstrap -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the reuse run failed: $($run.Message)"
    Assert-Equal 0 @(Get-Calls).Count 'a satisfied check made a release request'
    Assert-True ($run.Output -match 'reusing it without release traffic') 'reuse was not reported'
    Assert-Equal $installedHash (Get-PlasticineFileHash (Get-Target $scenarioHome)) 'the current executable was replaced'

    # --- A newer direct installation is never downgraded. ---
    $scenarioHome = New-Scenario 'newer-direct'
    Set-DirectChezmoi $scenarioHome $stubs['2.73.0']
    $newerHash = Get-PlasticineFileHash (Get-Target $scenarioHome)
    $run = Invoke-TestCapture { Invoke-PlasticineChezmoiBootstrap -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the newer direct run failed: $($run.Message)"
    Assert-Equal 0 @(Get-Calls).Count 'a newer installation caused release traffic'
    Assert-Equal $newerHash (Get-PlasticineFileHash (Get-Target $scenarioHome)) 'a newer installation was downgraded'

    # --- An outdated direct installation is updated in place. ---
    $scenarioHome = New-Scenario 'update'
    Set-DirectChezmoi $scenarioHome $stubs['2.72.0']
    $run = Invoke-TestCapture { Invoke-PlasticineChezmoiBootstrap -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the update run failed: $($run.Message)"
    Assert-True ($run.Output -match 'action=update') 'the update action was not reported'
    Assert-Equal '2.72.1' (Get-PlasticineExecutableVersion (Get-Target $scenarioHome)) 'the outdated executable was not updated'
    Assert-NoStaging $scenarioHome

    # --- A download failure preserves the working executable. ---
    $scenarioHome = New-Scenario 'download-failure'
    Set-DirectChezmoi $scenarioHome $stubs['2.72.0']
    $before = Get-PlasticineFileHash (Get-Target $scenarioHome)
    $env:PLASTICINE_TEST_DOWNLOAD_FAIL = '1'
    $run = Invoke-TestCapture { Invoke-PlasticineChezmoiBootstrap -HomeDirectory $scenarioHome }
    Remove-Item Env:\PLASTICINE_TEST_DOWNLOAD_FAIL -ErrorAction SilentlyContinue
    Assert-True $run.Threw 'a download failure reported success'
    Assert-True ($run.Error -match 'release archive download failed; existing executable preserved') 'the download failure was not reported'
    Assert-Equal $before (Get-PlasticineFileHash (Get-Target $scenarioHome)) 'the download failure changed the working executable'
    Assert-NoStaging $scenarioHome

    # --- A digest mismatch preserves the working executable. ---
    $scenarioHome = New-Scenario 'digest-mismatch'
    Set-DirectChezmoi $scenarioHome $stubs['2.72.0']
    $before = Get-PlasticineFileHash (Get-Target $scenarioHome)
    $PlasticineChezmoiAssets[$assetName] = ('0' * 64)
    $run = Invoke-TestCapture { Invoke-PlasticineChezmoiBootstrap -HomeDirectory $scenarioHome }
    $PlasticineChezmoiAssets[$assetName] = $reviewedDigest
    Assert-True $run.Threw 'a digest mismatch reported success'
    Assert-True ($run.Error -match 'SHA-256 mismatch; existing executable preserved') 'the digest mismatch was not reported'
    Assert-Equal $before (Get-PlasticineFileHash (Get-Target $scenarioHome)) 'the digest mismatch changed the working executable'
    Assert-NoStaging $scenarioHome

    # --- A candidate that is not the pinned version is refused. ---
    $scenarioHome = New-Scenario 'candidate-version'
    Set-DirectChezmoi $scenarioHome $stubs['2.72.0']
    $before = Get-PlasticineFileHash (Get-Target $scenarioHome)
    $wrongPayload = New-TestDirectory 'wrong-payload'
    Copy-Item -LiteralPath $stubs['2.73.0'] -Destination (Join-Path $wrongPayload 'chezmoi.exe')
    New-TestZip -Path (Join-Path $fixture $assetName) -File @((Join-Path $wrongPayload 'chezmoi.exe'))
    $PlasticineChezmoiAssets[$assetName] = Get-PlasticineFileHash (Join-Path $fixture $assetName)
    $run = Invoke-TestCapture { Invoke-PlasticineChezmoiBootstrap -HomeDirectory $scenarioHome }
    $PlasticineChezmoiAssets[$assetName] = $reviewedDigest
    New-TestZip -Path (Join-Path $fixture $assetName) -File @((Join-Path $payloadDir 'chezmoi.exe'))
    Assert-True $run.Threw 'a wrong candidate version reported success'
    Assert-True ($run.Error -match 'release candidate failed version/health validation') 'the candidate failure was not reported'
    Assert-Equal $before (Get-PlasticineFileHash (Get-Target $scenarioHome)) 'the candidate failure changed the working executable'

    # --- An archive with an unexpected member is refused. ---
    $scenarioHome = New-Scenario 'archive-members'
    New-TestZip -Path (Join-Path $fixture $assetName) -File @((Join-Path $payloadDir 'chezmoi.exe')) -ExtraEntry @('extra.txt')
    $PlasticineChezmoiAssets[$assetName] = Get-PlasticineFileHash (Join-Path $fixture $assetName)
    $run = Invoke-TestCapture { Invoke-PlasticineChezmoiBootstrap -HomeDirectory $scenarioHome }
    $PlasticineChezmoiAssets[$assetName] = $reviewedDigest
    New-TestZip -Path (Join-Path $fixture $assetName) -File @((Join-Path $payloadDir 'chezmoi.exe'))
    Assert-True $run.Threw 'an unexpected archive member reported success'
    Assert-True ($run.Error -match 'archive members do not match the reviewed layout') 'the member failure was not reported'
    Assert-True (-not (Test-Path -LiteralPath (Get-Target $scenarioHome))) 'the member failure published a target'

    # --- A failed publication leaves no target and no staging. ---
    $scenarioHome = New-Scenario 'publish-failure'
    $originalPublish = ${function:Publish-PlasticineNewFile}
    function Publish-PlasticineNewFile { param($Candidate, $Target) Stop-Plasticine 'simulated publication failure' }
    $run = Invoke-TestCapture { Invoke-PlasticineChezmoiBootstrap -HomeDirectory $scenarioHome }
    ${function:Publish-PlasticineNewFile} = $originalPublish
    Assert-True $run.Threw 'a failed publication reported success'
    Assert-True (-not (Test-Path -LiteralPath (Get-Target $scenarioHome))) 'the failed publication left a target'
    Assert-NoStaging $scenarioHome

    # --- A failed update keeps the previously observed executable. ---
    $scenarioHome = New-Scenario 'update-failure'
    Set-DirectChezmoi $scenarioHome $stubs['2.72.0']
    $originalUpdate = ${function:Update-PlasticineFile}
    function Update-PlasticineFile { param($Candidate, $Target, $ExpectedHash) Stop-Plasticine 'simulated replacement failure' }
    $run = Invoke-TestCapture { Invoke-PlasticineChezmoiBootstrap -HomeDirectory $scenarioHome }
    ${function:Update-PlasticineFile} = $originalUpdate
    Assert-True $run.Threw 'a failed update reported success'
    Assert-Equal '2.72.0' (Get-PlasticineExecutableVersion (Get-Target $scenarioHome)) 'the failed update lost the old executable'
    Assert-NoStaging $scenarioHome

    # --- A target that changes during preparation aborts the update. ---
    $scenarioHome = New-Scenario 'update-race'
    Set-DirectChezmoi $scenarioHome $stubs['2.72.0']
    $originalExpand = ${function:Expand-PlasticineArchive}
    function Expand-PlasticineArchive {
        param($Archive, $Destination, $Member)
        Set-Content -LiteralPath (Join-Path $scenarioHome '.local\bin\chezmoi.exe') -Value 'competing owner' -NoNewline
        Expand-Archive -LiteralPath $Archive -DestinationPath $Destination -Force
    }
    $run = Invoke-TestCapture { Invoke-PlasticineChezmoiBootstrap -HomeDirectory $scenarioHome }
    ${function:Expand-PlasticineArchive} = $originalExpand
    Assert-True $run.Threw 'a racing target was accepted'
    Assert-True ($run.Error -match 'installation target changed during preparation; update aborted') 'the race was not reported'
    Assert-Equal 'competing owner' (Get-Content -LiteralPath (Get-Target $scenarioHome) -Raw) 'the racing owner was overwritten'
    Assert-NoStaging $scenarioHome

    # --- External ownership satisfies the pin but is never mutated or shadowed. ---
    foreach ($state in @('current', 'outdated', 'unhealthy', 'prerelease')) {
        $scenarioHome = New-Scenario "external-$state"
        $externalBin = New-TestDirectory "external-bin-$state"
        switch ($state) {
            'current' { Copy-Item -LiteralPath $stubs['2.73.0'] -Destination (Join-Path $externalBin 'chezmoi.exe') }
            'outdated' { Copy-Item -LiteralPath $stubs['2.72.0'] -Destination (Join-Path $externalBin 'chezmoi.exe') }
            'unhealthy' { Copy-Item -LiteralPath $unhealthyStub -Destination (Join-Path $externalBin 'chezmoi.exe') }
            'prerelease' { Copy-Item -LiteralPath $prereleaseStub -Destination (Join-Path $externalBin 'chezmoi.exe') }
        }
        $env:PATH = $externalBin + ';' + $savedPath
        $run = Invoke-TestCapture { Invoke-PlasticineChezmoiBootstrap -HomeDirectory $scenarioHome }
        $env:PATH = $savedPath
        if ($state -eq 'current') {
            Assert-True (-not $run.Threw) "a current external owner was rejected: $($run.Message)"
            Assert-Equal (Join-Path $externalBin 'chezmoi.exe') $run.Value 'the external owner was not returned'
            Assert-Equal 0 @(Get-Calls).Count 'a current external owner caused release traffic'
        } else {
            Assert-True $run.Threw "a $state external owner was accepted"
            Assert-Equal 0 @(Get-Calls).Count "a $state external owner caused release traffic"
        }
        Assert-True (-not (Test-Path -LiteralPath (Get-Target $scenarioHome))) "a $state external owner was shadowed"
    }

    # --- Explicit overrides keep their interface contract and never mutate. ---
    $scenarioHome = New-Scenario 'explicit'
    $run = Invoke-TestCapture { Invoke-PlasticineChezmoiBootstrap -HomeDirectory $scenarioHome -Explicit $stubs['2.73.0'] }
    Assert-True (-not $run.Threw) "an explicit override was rejected: $($run.Message)"
    Assert-Equal $stubs['2.73.0'] $run.Value 'the explicit override was not returned'
    Assert-Equal 0 @(Get-Calls).Count 'an explicit override queried upstream'
    Assert-True (-not (Test-Path -LiteralPath (Get-Target $scenarioHome))) 'an explicit override was shadowed'

    $scenarioHome = New-Scenario 'explicit-outdated'
    $run = Invoke-TestCapture { Invoke-PlasticineChezmoiBootstrap -HomeDirectory $scenarioHome -Explicit $stubs['2.72.0'] }
    Assert-True $run.Threw 'an outdated explicit override was accepted'
    Assert-True ($run.Error -match 'lacks the required chezmoi interface') 'the interface failure was not reported'

    $scenarioHome = New-Scenario 'explicit-missing'
    $run = Invoke-TestCapture { Invoke-PlasticineChezmoiBootstrap -HomeDirectory $scenarioHome -Explicit (Join-Path $stubDir 'absent.exe') }
    Assert-True $run.Threw 'a missing explicit override was accepted'
    Assert-True ($run.Error -match 'explicit executable was not found') 'the missing override was not reported'

    $scenarioHome = New-Scenario 'explicit-by-name'
    $externalBin = New-TestDirectory 'explicit-name-bin'
    Copy-Item -LiteralPath $stubs['2.73.0'] -Destination (Join-Path $externalBin 'chezmoi.exe')
    $env:PATH = $externalBin + ';' + $savedPath
    $run = Invoke-TestCapture { Invoke-PlasticineChezmoiBootstrap -HomeDirectory $scenarioHome -Explicit 'chezmoi' }
    $env:PATH = $savedPath
    Assert-True (-not $run.Threw) "an explicit name was rejected: $($run.Message)"
    Assert-Equal 0 @(Get-Calls).Count 'an explicit name queried upstream'

    # --- Platform and destination guards stop before any release traffic. ---
    $scenarioHome = New-Scenario 'arm64'
    $env:PROCESSOR_ARCHITECTURE = 'ARM64'
    $run = Invoke-TestCapture { Invoke-PlasticineChezmoiBootstrap -HomeDirectory $scenarioHome }
    $env:PROCESSOR_ARCHITECTURE = $savedArchitecture
    Assert-True $run.Threw 'an arm64 host was accepted'
    Assert-True ($run.Error -match 'unsupported Windows architecture') 'the architecture failure was not reported'
    Assert-Equal 0 @(Get-Calls).Count 'an unsupported architecture made a release request'

    $run = Invoke-TestCapture { Invoke-PlasticineChezmoiBootstrap -HomeDirectory 'relative\home' }
    Assert-True $run.Threw 'a relative HOME was accepted'
    Assert-True ($run.Error -match 'HOME must be absolute') 'the relative HOME was not reported'

    # --- A reported stop is typed and printed exactly once for the installer. ---
    $stopProbe = Invoke-StopProbe { Invoke-PlasticineChezmoiBootstrap -HomeDirectory 'relative\home' }
    Assert-True ($stopProbe.Exception -is [PlasticineStopException]) 'a chezmoi stop did not raise the typed stop exception'
    Assert-Equal 1 ([regex]::Matches($stopProbe.Error, 'plasticine-dotfiles: chezmoi prerequisite: HOME must be absolute\.')).Count `
        'the chezmoi stop diagnostic was not printed exactly once'

    $scenarioHome = New-Scenario 'parent-is-file'
    Set-Content -LiteralPath (Join-Path $scenarioHome '.local') -Value 'not a directory' -NoNewline
    $run = Invoke-TestCapture { Invoke-PlasticineChezmoiBootstrap -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'a file parent was accepted'
    Assert-True ($run.Error -match 'installation parent is not a real directory') 'the parent failure was not reported'
    Assert-Equal 0 @(Get-Calls).Count 'a rejected destination made a release request'

    $scenarioHome = New-Scenario 'target-is-directory'
    New-Item -ItemType Directory -Path (Get-Target $scenarioHome) -Force | Out-Null
    $run = Invoke-TestCapture { Invoke-PlasticineChezmoiBootstrap -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'a directory target was accepted'
    Assert-True ($run.Error -match 'installation target is not a regular file') 'the target failure was not reported'
    Assert-Equal 0 @(Get-Calls).Count 'a rejected target made a release request'

    # --- Reloading the shared modules keeps the download seam and asset pin. ---
    $savedCurlCommand = $PlasticineCurlCommand
    $PlasticineCurlCommand = 'C:\sentinel\curl.exe'
    $PlasticineChezmoiAssets['sentinel-asset.zip'] = 'sentinel-digest'
    . (Join-Path $repoDir 'lib\windows\common.ps1')
    . (Join-Path $repoDir 'lib\windows\publish.ps1')
    . (Join-Path $repoDir 'lib\windows\acl.ps1')
    Assert-Equal 'C:\sentinel\curl.exe' $PlasticineCurlCommand 'reloading the shared modules reset the curl seam'
    Assert-Equal 'sentinel-digest' $PlasticineChezmoiAssets['sentinel-asset.zip'] 'reloading the shared modules reset the asset pin seam'
    $PlasticineCurlCommand = $savedCurlCommand
    $null = $PlasticineChezmoiAssets.Remove('sentinel-asset.zip')

    Complete-Test 'windows chezmoi tests passed'
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
} finally {
    $env:PATH = $savedPath
    $env:PROCESSOR_ARCHITECTURE = $savedArchitecture
    Remove-Item Env:\PLASTICINE_TEST_DOWNLOAD_FAIL -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $PlasticineTestRoot -Recurse -Force -ErrorAction SilentlyContinue
}