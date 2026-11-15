# Coverage for the Windows Release payload seam: asset caching, digest review,
# local asset overrides and source bundle restoration. No real release traffic.

$repoDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'harness.ps1')
$PlasticineTestName = 'windows release payload'
. (Join-Path $repoDir 'lib\windows\release-payload.ps1')
# The suite replaces the network seam with a fixture copy; keep the real helper
# so the shared timeout and size bounds can be exercised directly.
$realDownload = ${function:Invoke-PlasticineDownload}

$callsFile = Join-Path $PlasticineTestRoot 'calls'
$fixture = New-TestDirectory 'fixture'
$releaseBase = 'https://release.invalid/download/v0.0.0'
$releaseVersion = '0.0.0'
$origin = 'https://github.com/Plasticine-Yang/plasticine-dotfiles.git'
$savedAssetDir = $env:PLASTICINE_RELEASE_ASSET_DIR

function Reset-Calls { Set-Content -LiteralPath $callsFile -Value @() }
function Get-Calls {
    if (Test-Path -LiteralPath $callsFile) { return @(Get-Content -LiteralPath $callsFile) }
    return @()
}

function Invoke-PlasticineDownload {
    param([string]$Url, [string]$Destination, [string]$FailureMessage)
    Add-Content -LiteralPath $callsFile -Value $Url
    Copy-Item -LiteralPath (Join-Path $fixture (Split-Path -Leaf $Url)) -Destination $Destination -ErrorAction Stop
}

function Invoke-FixtureGit {
    param([Parameter(Mandatory = $true)][string[]]$Argument, [string]$Directory)
    $result = Invoke-PlasticineGitCommand -Argument $Argument -Directory $Directory
    Assert-Equal 0 $result.ExitCode "fixture git command failed: $($Argument -join ' ')"
    return ($result.Output -join "`n").Trim()
}

# Offline stand-in for the system curl: records the argument vector, then writes
# a file of the requested size or exits with the curl timeout code.
function New-CurlStub {
    param([Parameter(Mandatory = $true)][string]$Path)
    $source = @'
$arguments = @($args)
if ($env:PLASTICINE_TEST_CURL_LOG) {
    Set-Content -LiteralPath $env:PLASTICINE_TEST_CURL_LOG -Value ($arguments -join "`n")
}
if ($env:PLASTICINE_TEST_CURL_MODE -eq 'timeout') { exit 28 }
$destination = $null
for ($index = 0; $index -lt $arguments.Count; $index++) {
    if ($arguments[$index] -eq '-o') { $destination = $arguments[$index + 1] }
}
if ($destination) {
    $size = 0
    if ($env:PLASTICINE_TEST_CURL_SIZE) { $size = [int]$env:PLASTICINE_TEST_CURL_SIZE }
    [IO.File]::WriteAllBytes($destination, (New-Object byte[] $size))
}
exit 0
'@
    Set-Content -LiteralPath $Path -Value $source -Encoding ASCII
}

function New-SourceScenario {
    param([Parameter(Mandatory = $true)][string]$Name)
    $root = New-TestDirectory $Name
    Reset-Calls
    return [pscustomobject]@{
        Home      = (Join-Path $root 'home')
        SourceDir = (Join-Path $root 'home\.local\share\chezmoi')
    }
}

try {
    Remove-Item Env:\PLASTICINE_RELEASE_ASSET_DIR -ErrorAction SilentlyContinue

    # --- A real bundle carries the released revision. ---
    $upstream = New-TestDirectory 'upstream'
    Invoke-FixtureGit -Argument @('init', '-q', $upstream) | Out-Null
    Set-Content -LiteralPath (Join-Path $upstream 'dotfile') -Value 'v1' -NoNewline
    Invoke-FixtureGit -Directory $upstream -Argument @('add', '-A') | Out-Null
    Invoke-FixtureGit -Directory $upstream -Argument @('-c', 'user.name=test', '-c', 'user.email=test@example.com', 'commit', '-qm', 'init') | Out-Null
    $revision = Invoke-FixtureGit -Directory $upstream -Argument @('rev-parse', 'HEAD')
    $bundleName = 'plasticine-source.bundle'
    Invoke-FixtureGit -Directory $upstream -Argument @('bundle', 'create', (Join-Path $fixture $bundleName), 'HEAD') | Out-Null
    $bundleDigest = Get-PlasticineFileHash (Join-Path $fixture $bundleName)

    $pluginsName = 'plasticine-managed-plugins.tar.gz'
    Set-Content -LiteralPath (Join-Path $fixture $pluginsName) -Value 'plugins' -NoNewline
    $pluginsDigest = Get-PlasticineFileHash (Join-Path $fixture $pluginsName)

    # --- A fresh home restores the released revision and nothing else. ---
    $scenario = New-SourceScenario 'fresh'
    New-Item -ItemType Directory -Path $scenario.Home -ErrorAction Stop | Out-Null
    $run = Invoke-TestCapture {
        Invoke-PlasticineReleaseSourceAcquisition -HomeDirectory $scenario.Home -Base $releaseBase `
            -Version $releaseVersion -SourceDigest $bundleDigest -Revision $revision -Origin $origin `
            -SourceDir $scenario.SourceDir
    }
    Assert-True (-not $run.Threw) "the fresh restore failed: $($run.Message)"
    Assert-Equal $scenario.SourceDir $run.Value 'the acquisition did not return the source directory'
    Assert-Equal 1 (@(Get-Calls).Count) 'the fresh restore made more than one request'
    Assert-Equal $revision (Invoke-FixtureGit -Directory $scenario.SourceDir -Argument @('rev-parse', 'HEAD')) 'the restored checkout is not at the released revision'
    Assert-Equal $origin (Invoke-FixtureGit -Directory $scenario.SourceDir -Argument @('remote', 'get-url', 'origin')) 'the restored origin was not set'
    Assert-Equal 0 (@(Get-ChildItem -LiteralPath (Split-Path -Parent $scenario.SourceDir) -Force -Filter '.plasticine-source.*').Count) 'the restore left a staged checkout behind'
    Assert-True (Test-Path -LiteralPath (Join-Path $scenario.SourceDir 'dotfile')) 'the restored checkout has no working tree'

    # --- A second run reuses the cached asset and the existing checkout. ---
    Reset-Calls
    $run = Invoke-TestCapture {
        Invoke-PlasticineReleaseSourceAcquisition -HomeDirectory $scenario.Home -Base $releaseBase `
            -Version $releaseVersion -SourceDigest $bundleDigest -Revision $revision -Origin $origin `
            -SourceDir $scenario.SourceDir
    }
    Assert-True (-not $run.Threw) "the cached restore failed: $($run.Message)"
    Assert-Equal 0 (@(Get-Calls).Count) 'a cached asset was downloaded again'
    Assert-Equal $revision (Invoke-FixtureGit -Directory $scenario.SourceDir -Argument @('rev-parse', 'HEAD')) 'the cached restore moved the checkout'

    # --- A digest mismatch stops before any source is written. ---
    $scenario = New-SourceScenario 'digest'
    New-Item -ItemType Directory -Path $scenario.Home -ErrorAction Stop | Out-Null
    $run = Invoke-TestCapture {
        Invoke-PlasticineReleaseSourceAcquisition -HomeDirectory $scenario.Home -Base $releaseBase `
            -Version $releaseVersion -SourceDigest ('0' * 64) -Revision $revision -Origin $origin `
            -SourceDir $scenario.SourceDir
    }
    Assert-True $run.Threw 'a digest mismatch reported success'
    Assert-True ($run.Error -match 'release payload: SHA-256 mismatch') 'the digest mismatch was not reported'
    Assert-True (-not (Test-Path -LiteralPath $scenario.SourceDir)) 'the digest mismatch wrote a source directory'

    # --- A bundle without the released revision is refused. ---
    $scenario = New-SourceScenario 'wrong-revision'
    New-Item -ItemType Directory -Path $scenario.Home -ErrorAction Stop | Out-Null
    $run = Invoke-TestCapture {
        Invoke-PlasticineReleaseSourceAcquisition -HomeDirectory $scenario.Home -Base $releaseBase `
            -Version $releaseVersion -SourceDigest $bundleDigest -Revision ('0' * 40) -Origin $origin `
            -SourceDir $scenario.SourceDir
    }
    Assert-True $run.Threw 'an absent revision reported success'
    Assert-True ($run.Error -match 'restored source does not match the released revision') 'the revision failure was not reported'
    Assert-True (-not (Test-Path -LiteralPath $scenario.SourceDir)) 'the revision failure published a checkout'

    # --- An existing checkout with local changes or another origin is refused. ---
    foreach ($state in @('dirty', 'foreign-origin')) {
        $scenario = New-SourceScenario $state
        New-Item -ItemType Directory -Path $scenario.SourceDir -Force -ErrorAction Stop | Out-Null
        Invoke-FixtureGit -Argument @('init', '-q', $scenario.SourceDir) | Out-Null
        if ($state -eq 'dirty') {
            Invoke-FixtureGit -Directory $scenario.SourceDir -Argument @('remote', 'add', 'origin', $origin) | Out-Null
            Set-Content -LiteralPath (Join-Path $scenario.SourceDir 'local') -Value 'change' -NoNewline
        } else {
            Invoke-FixtureGit -Directory $scenario.SourceDir -Argument @('remote', 'add', 'origin', 'https://github.com/other/repo.git') | Out-Null
        }
        $run = Invoke-TestCapture {
            Invoke-PlasticineReleaseSourceAcquisition -HomeDirectory $scenario.Home -Base $releaseBase `
                -Version $releaseVersion -SourceDigest $bundleDigest -Revision $revision -Origin $origin `
                -SourceDir $scenario.SourceDir
        }
        Assert-True $run.Threw "a $state checkout was accepted"
        if ($state -eq 'dirty') {
            Assert-True ($run.Error -match 'existing chezmoi source has local changes') 'the dirty checkout was not reported'
        } else {
            Assert-True ($run.Error -match 'existing chezmoi source belongs to another repository') 'the foreign origin was not reported'
        }
    }

    # --- A local asset directory is reviewed and never downloaded. ---
    $scenario = New-SourceScenario 'local-asset'
    New-Item -ItemType Directory -Path $scenario.Home -ErrorAction Stop | Out-Null
    $localAssets = New-TestDirectory 'local-assets'
    Copy-Item -LiteralPath (Join-Path $fixture $bundleName) -Destination (Join-Path $localAssets $bundleName)
    $env:PLASTICINE_RELEASE_ASSET_DIR = $localAssets
    $run = Invoke-TestCapture {
        Invoke-PlasticineReleaseSourceAcquisition -HomeDirectory $scenario.Home -Base $releaseBase `
            -Version $releaseVersion -SourceDigest $bundleDigest -Revision $revision -Origin $origin `
            -SourceDir $scenario.SourceDir
    }
    Remove-Item Env:\PLASTICINE_RELEASE_ASSET_DIR -ErrorAction SilentlyContinue
    Assert-True (-not $run.Threw) "the local asset restore failed: $($run.Message)"
    Assert-Equal 0 (@(Get-Calls).Count) 'a local asset was downloaded'
    Assert-Equal $revision (Invoke-FixtureGit -Directory $scenario.SourceDir -Argument @('rev-parse', 'HEAD')) 'the local asset restore missed the revision'

    $scenario = New-SourceScenario 'local-asset-relative'
    $env:PLASTICINE_RELEASE_ASSET_DIR = 'relative\assets'
    $run = Invoke-TestCapture {
        Get-PlasticineReleaseAsset -HomeDirectory $scenario.Home -Base $releaseBase -Version $releaseVersion `
            -Name $bundleName -Digest $bundleDigest
    }
    Remove-Item Env:\PLASTICINE_RELEASE_ASSET_DIR -ErrorAction SilentlyContinue
    Assert-True $run.Threw 'a relative asset directory was accepted'
    Assert-True ($run.Error -match 'PLASTICINE_RELEASE_ASSET_DIR must be absolute') 'the relative asset directory was not reported'

    # --- Managed plugins use the same reviewed asset seam. ---
    $scenario = New-SourceScenario 'plugins'
    New-Item -ItemType Directory -Path $scenario.Home -ErrorAction Stop | Out-Null
    $run = Invoke-TestCapture {
        Invoke-PlasticineReleasePluginAcquisition -HomeDirectory $scenario.Home -Base $releaseBase `
            -Version $releaseVersion -Digest $pluginsDigest
    }
    Assert-True (-not $run.Threw) "the plugin acquisition failed: $($run.Message)"
    Assert-Equal 1 (@(Get-Calls).Count) 'the plugin acquisition made more than one request'
    Assert-Equal $pluginsDigest (Get-PlasticineFileHash $run.Value) 'the published plugin asset does not match its digest'
    Reset-Calls
    $again = Invoke-TestCapture {
        Invoke-PlasticineReleasePluginAcquisition -HomeDirectory $scenario.Home -Base $releaseBase `
            -Version $releaseVersion -Digest $pluginsDigest
    }
    Assert-Equal $run.Value $again.Value 'the cached plugin asset path changed'
    Assert-Equal 0 (@(Get-Calls).Count) 'a cached plugin asset was downloaded again'

    # --- Release downloads inherit the shared timeout and size bounds. ---
    $scenario = New-SourceScenario 'bounded-download'
    New-Item -ItemType Directory -Path $scenario.Home -ErrorAction Stop | Out-Null
    $stubCurl = Join-Path $PlasticineTestRoot 'curl-stub.ps1'
    New-CurlStub -Path $stubCurl
    $savedCurlCommand = $PlasticineCurlCommand
    $savedMaxBytes = $PlasticineDownloadMaxBytes
    $curlLog = Join-Path $PlasticineTestRoot 'curl.log'
    $mockDownload = ${function:Invoke-PlasticineDownload}
    $env:PLASTICINE_TEST_CURL_LOG = $curlLog
    try {
        ${function:Invoke-PlasticineDownload} = $realDownload
        $PlasticineCurlCommand = $stubCurl
        $PlasticineDownloadMaxBytes = 4
        $env:PLASTICINE_TEST_CURL_SIZE = '8'
        $boundedRun = Invoke-TestCapture {
            Get-PlasticineReleaseAsset -HomeDirectory $scenario.Home -Base $releaseBase -Version $releaseVersion `
                -Name 'plasticine-source.bundle' -Digest $bundleDigest
        }
        Assert-True $boundedRun.Threw 'an oversized release download reported success'
        Assert-True ($boundedRun.Error -match 'release payload: download failed') 'the release download failure was not reported'
        Assert-True ($boundedRun.Error -match 'size limit') 'the release download did not report the size limit'
        $curlCall = Get-Content -LiteralPath $curlLog -Raw
        Assert-True ($curlCall -match '--max-time\s+600') 'the release download did not carry the total timeout'
        Assert-True ($curlCall -match '--connect-timeout\s+30') 'the release download did not carry the connect timeout'
        $assetDir = Join-Path $scenario.Home '.cache\plasticine\releases\0.0.0'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $assetDir 'plasticine-source.bundle'))) 'the failed release download published an asset'
        Assert-Equal 0 (@(Get-ChildItem -LiteralPath $assetDir -Force -Filter '.plasticine-release.*').Count) `
            'the failed release download left a staging file behind'

        $env:PLASTICINE_TEST_CURL_MODE = 'timeout'
        $timeoutRun = Invoke-TestCapture {
            Get-PlasticineReleaseAsset -HomeDirectory $scenario.Home -Base $releaseBase -Version $releaseVersion `
                -Name 'plasticine-source.bundle' -Digest $bundleDigest
        }
        Assert-True $timeoutRun.Threw 'a timed-out release download reported success'
        Assert-True ($timeoutRun.Error -match 'release payload: download failed') 'the timeout download failure was not reported'
    } finally {
        ${function:Invoke-PlasticineDownload} = $mockDownload
        $PlasticineCurlCommand = $savedCurlCommand
        $PlasticineDownloadMaxBytes = $savedMaxBytes
        Remove-Item Env:\PLASTICINE_TEST_CURL_LOG -ErrorAction SilentlyContinue
        Remove-Item Env:\PLASTICINE_TEST_CURL_MODE -ErrorAction SilentlyContinue
        Remove-Item Env:\PLASTICINE_TEST_CURL_SIZE -ErrorAction SilentlyContinue
    }

    Complete-Test 'windows release payload tests passed'
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
} finally {
    if ($savedAssetDir) { $env:PLASTICINE_RELEASE_ASSET_DIR = $savedAssetDir }
    else { Remove-Item Env:\PLASTICINE_RELEASE_ASSET_DIR -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $PlasticineTestRoot -Recurse -Force -ErrorAction SilentlyContinue
}