# PowerShell equivalent of lib/herdr-bootstrap.sh for the Windows route. The
# reviewed official install.ps1 owns the Windows package: it resolves
# https://herdr.dev/latest.json, verifies the manifest SHA-256, unpacks the
# release and creates the ConPTY runtime next to herdr.exe. That installer
# always publishes its visible command directory as a junction, always prepends
# its own release directory to the user PATH, and stores state under
# %USERPROFILE%\.herdr, so this route runs it inside private candidate storage
# (HERDR_HOME and HERDR_INSTALL_DIR both point there), restores the user PATH it
# changed, and only then publishes the whole reviewed tree - herdr.exe plus the
# ConPTY directory - into ~/.local/bin with no-clobber semantics and rollback.

if (-not (Get-Command Write-PlasticineLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'common.ps1')
}
if (-not (Get-Command Publish-PlasticineNewFile -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'publish.ps1')
}
if (-not (Get-Command Set-PlasticineOwnerOnlyAcl -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'acl.ps1')
}
if (-not (Get-Command Get-PlasticineUserPath -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'user-path.ps1')
}
if (Get-Command Get-PlasticineHerdrPlan -ErrorAction SilentlyContinue) { return }

$PlasticineHerdrVersion = '0.9.5'
# Reviewed on 2026-11-15. Upstream publishes no versioned install.ps1 asset, so
# the reviewed 0.9.5-era script is pinned by its SHA-256 and by the identity
# markers below: when herdr.dev serves a different script this route stops
# instead of executing an unreviewed installer. The manifest URL the script
# resolves is https://herdr.dev/latest.json; the script itself verifies the
# manifest SHA-256 of the package it downloads, which is the same upstream
# trust boundary the Unix route uses.
$PlasticineHerdrInstallerUrl = 'https://herdr.dev/install.ps1'
$PlasticineHerdrInstallerDigest = '369e0d2b5a5f976e11b512f3c4b610a2eba6119732b292a2f587ca8f80fe0baf'
$PlasticineHerdrManifestUrl = 'https://herdr.dev/latest.json'
$PlasticineHerdrInstallerMarkers = @(
    'HERDR_INSTALL_DIR',
    'https://herdr.dev/latest.json',
    'herdr-conpty.json',
    'function Test-FileDigest'
)
$PlasticineHerdrCommand = 'herdr.exe'
# Reviewed from the official 0.9.5 herdr-windows-x86_64 package on 2026-11-15
# (package SHA-256 d2c6c9c971c43a0bfdde8c692a9a1a7a45c3e4807cd01ae45662b4734fac1cbf).
$PlasticineHerdrCommandDigest = 'cd877c8744296f4a38a2703bf13cf11728973649ec54959959c4587ffe5368b2'
$PlasticineHerdrConptyDirectory = 'conpty'
$PlasticineHerdrConptyMarker = 'conpty\herdr-conpty.json'
$PlasticineHerdrConptyFiles = @(
    'conpty\conpty.dll',
    'conpty\x64\OpenConsole.exe',
    'conpty\arm64\OpenConsole.exe'
)
# Published in this order: the ConPTY runtime first, the command last, so the
# command only appears once everything it needs is in place.
$PlasticineHerdrEntries = @($PlasticineHerdrConptyDirectory, $PlasticineHerdrCommand)
$PlasticineHerdrInstallerTimeoutSeconds = 1800

function Stop-PlasticineHerdr {
    param([Parameter(Mandatory = $true)][string]$Message)
    Stop-Plasticine "herdr: $Message"
}

# PATH first, then the managed target, so an installation owned elsewhere is
# observed as itself instead of being mistaken for the managed one.
function Resolve-PlasticineHerdrExecutable {
    param([Parameter(Mandatory = $true)][string]$Target)
    $found = Get-PlasticineCommandPath 'herdr'
    if ($found) { return [IO.Path]::GetFullPath($found) }
    $item = Get-PlasticineItem $Target
    if ($item -and -not $item.PSIsContainer -and -not (Test-PlasticineReparsePoint $item)) {
        return [IO.Path]::GetFullPath($Target)
    }
    return $null
}

# Upstream reads %APPDATA%\herdr\config.toml on Windows, not ~/.config/herdr.
function Get-PlasticineHerdrConfigDirectory {
    $appData = $env:APPDATA
    if (-not $appData) {
        $appData = [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
    }
    if (-not $appData) { return '' }
    return (Join-Path $appData 'herdr')
}

function Assert-PlasticineHerdrDestination {
    param([Parameter(Mandatory = $true)][string]$ConptyDirectory)
    $item = Get-PlasticineItem $ConptyDirectory
    if ($item -and (-not $item.PSIsContainer -or (Test-PlasticineReparsePoint $item))) {
        Stop-PlasticineHerdr "installation directory is not a real directory: $ConptyDirectory; left untouched."
    }
}

# Runs the reviewed installer in a child Windows PowerShell with an environment
# that keeps its whole native state inside the private work directory.
function Invoke-PlasticineHerdrInstallerProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Installer,
        [Parameter(Mandatory = $true)][hashtable]$Environment,
        [string[]]$RemoveEnvironment = @(),
        [string]$WorkingDirectory
    )
    $null = Assert-PlasticineAbsolutePath -Path $Installer -Name 'reviewed installer path'
    $systemRoot = $env:SystemRoot
    if (-not $systemRoot) { $systemRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows) }
    $powershell = Join-Path $systemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $powershell -PathType Leaf)) {
        Stop-PlasticineHerdr "missing the Windows PowerShell host needed to run the reviewed installer: $powershell"
    }
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $powershell
    $startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $Installer + '"'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    if ($WorkingDirectory) { $startInfo.WorkingDirectory = $WorkingDirectory }
    foreach ($name in @($RemoveEnvironment)) {
        if (-not $name) { continue }
        [void]$startInfo.EnvironmentVariables.Remove([string]$name)
    }
    foreach ($name in @($Environment.Keys)) {
        $startInfo.EnvironmentVariables[[string]$name] = [string]$Environment[$name]
    }
    $process = $null
    try {
        $process = [System.Diagnostics.Process]::Start($startInfo)
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $exited = $process.WaitForExit([int]($PlasticineHerdrInstallerTimeoutSeconds * 1000))
        if (-not $exited) {
            try { $process.Kill() } catch { }
            Stop-PlasticineHerdr "official installer did not finish within $PlasticineHerdrInstallerTimeoutSeconds seconds; nothing was published."
        }
        $process.WaitForExit()
        $process.Refresh()
        $output = ''
        $errorText = ''
        if ($outputTask.Wait(5000)) { $output = [string]$outputTask.Result }
        if ($errorTask.Wait(5000)) { $errorText = [string]$errorTask.Result }
        return [pscustomobject]@{
            ExitCode = [int]$process.ExitCode
            Output   = $output
            Error    = $errorText
        }
    } catch [PlasticineStopException] {
        throw
    } catch {
        Stop-PlasticineHerdr ('official installer could not be executed: ' + $_.Exception.Message)
    } finally {
        if ($process) { try { $process.Dispose() } catch { } }
    }
}

# Test seam: the suites replace this scriptblock so no network or child process
# is needed. It receives the reviewed script, the isolated environment and the
# private work directory, and returns an object with an ExitCode property.
$PlasticineHerdrInstallerRunner = {
    param(
        [Parameter(Mandatory = $true)][string]$Installer,
        [Parameter(Mandatory = $true)][hashtable]$Environment,
        [string[]]$RemoveEnvironment = @(),
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )
    return (Invoke-PlasticineHerdrInstallerProcess -Installer $Installer -Environment $Environment `
        -RemoveEnvironment $RemoveEnvironment -WorkingDirectory $WorkingDirectory)
}

# The reviewed script is pinned by digest and by the markers that prove it is
# still the manifest-verifying installer this route was reviewed against.
function Assert-PlasticineHerdrInstallerScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Digest
    )
    $null = Assert-PlasticineAbsolutePath -Path $Path -Name 'reviewed installer path'
    if ((Get-PlasticineFileHash $Path) -ne $Digest) {
        Stop-PlasticineHerdr 'the downloaded file is not the reviewed herdr installer (SHA-256 mismatch); nothing changed. Review the upstream installer and update the pinned tuple.'
    }
    $text = [IO.File]::ReadAllText($Path)
    foreach ($marker in $PlasticineHerdrInstallerMarkers) {
        if ($text.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
            Stop-PlasticineHerdr "the downloaded file is not the reviewed herdr installer (missing marker: $marker); nothing changed."
        }
    }
}

# HERDR_HOME keeps the releases, the current junction and the install lock in
# private storage; HERDR_INSTALL_DIR is the visible command directory the
# installer turns into a junction to that release. HERDR_CHANNEL is explicit so
# the installer never inspects an unrelated herdr that happens to be on PATH.
function New-PlasticineHerdrInstallerEnvironment {
    param(
        [Parameter(Mandatory = $true)][string]$CandidateDirectory,
        [Parameter(Mandatory = $true)][string]$HerdrHome
    )
    return @{
        HERDR_HOME         = $HerdrHome
        HERDR_INSTALL_DIR  = $CandidateDirectory
        HERDR_CHANNEL      = 'stable'
    }
}

$PlasticineHerdrInstallerEnvironmentRemovals = @(
    'HERDR_MANIFEST_URL',
    'HERDR_EXPECTED_BUILD_ID'
)

function Invoke-PlasticineHerdrInstaller {
    param(
        [Parameter(Mandatory = $true)][string]$Installer,
        [Parameter(Mandatory = $true)][string]$CandidateDirectory,
        [Parameter(Mandatory = $true)][string]$HerdrHome,
        [Parameter(Mandatory = $true)][string]$WorkDirectory
    )
    $runner = $PlasticineHerdrInstallerRunner
    if (-not $runner) {
        Stop-PlasticineHerdr 'the installer runner seam is not configured; nothing changed.'
    }
    $environment = New-PlasticineHerdrInstallerEnvironment -CandidateDirectory $CandidateDirectory -HerdrHome $HerdrHome
    try {
        $result = & $runner -Installer $Installer -Environment $environment `
            -RemoveEnvironment $PlasticineHerdrInstallerEnvironmentRemovals -WorkingDirectory $WorkDirectory
    } catch [PlasticineStopException] {
        throw
    } catch {
        Stop-PlasticineHerdr ('official installer could not be started: ' + $_.Exception.Message)
    }
    if ($null -eq $result -or $null -eq $result.ExitCode -or [int]$result.ExitCode -ne 0) {
        $detail = ''
        if ($result -and $result.Error) { $detail = ' ' + ([string]$result.Error).Trim() }
        Stop-PlasticineHerdr ("official installer failed (including any upstream download or checksum failure); the existing installation was left untouched.$detail")
    }
    return $result
}

# Marker values are compared to the files they describe, which is the same
# completeness check the installer runs before it activates a release.
function Assert-PlasticineHerdrConptyManifest {
    param([Parameter(Mandatory = $true)][string]$Directory)
    $markerPath = Join-Path $Directory $PlasticineHerdrConptyMarker
    $markerItem = Get-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue
    if (-not $markerItem -or $markerItem.PSIsContainer) {
        Stop-PlasticineHerdr 'the downloaded package is missing the ConPTY manifest; nothing was published.'
    }
    try {
        $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
    } catch {
        Stop-PlasticineHerdr 'the downloaded package has an unreadable ConPTY manifest; nothing was published.'
    }
    $schema = $marker.PSObject.Properties['schema_version']
    $package = $marker.PSObject.Properties['package']
    $architecture = $marker.PSObject.Properties['architecture']
    $version = $marker.PSObject.Properties['version']
    $files = $marker.PSObject.Properties['files']
    if (-not $schema -or [int]$schema.Value -ne 1 -or
        -not $package -or [string]$package.Value -ne 'Microsoft.Windows.Console.ConPTY' -or
        -not $architecture -or [string]$architecture.Value -ne 'x86_64' -or
        -not $version -or [string]::IsNullOrWhiteSpace([string]$version.Value) -or
        -not $files -or -not $files.Value) {
        Stop-PlasticineHerdr 'the downloaded package has an unexpected ConPTY manifest; nothing was published.'
    }
    foreach ($relative in $PlasticineHerdrConptyFiles) {
        $key = $relative -replace '\\', '/'
        $expectedProperty = $files.Value.PSObject.Properties[$key]
        if (-not $expectedProperty -or [string]::IsNullOrWhiteSpace([string]$expectedProperty.Value)) {
            Stop-PlasticineHerdr "the ConPTY manifest does not cover $key; nothing was published."
        }
        $path = Join-Path $Directory $relative
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if (-not $item -or $item.PSIsContainer -or (Test-PlasticineReparsePoint $item)) {
            Stop-PlasticineHerdr "the downloaded package is missing the ConPTY file $relative; nothing was published."
        }
        if ((Get-PlasticineFileHash $path) -ne ([string]$expectedProperty.Value).ToLowerInvariant()) {
            Stop-PlasticineHerdr "the ConPTY file $relative does not match its manifest SHA-256; nothing was published."
        }
    }
}

# The candidate has to be the reviewed tuple before anything is published: the
# reviewed herdr.exe bytes, the pinned stable version and the complete ConPTY
# runtime with matching manifest digests. The reviewed installer turns
# HERDR_INSTALL_DIR into a junction to its release directory in private storage;
# Get-Item and Copy-Item follow that junction, so the tree is read as one tree.
function Assert-PlasticineHerdrCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)]$Plan
    )
    $null = Assert-PlasticineAbsolutePath -Path $Directory -Name 'herdr candidate directory'
    $fileName = [IO.Path]::GetFileName([string]$Plan.Command)
    $command = Join-Path $Directory $fileName
    $item = Get-Item -LiteralPath $command -Force -ErrorAction SilentlyContinue
    if (-not $item -or $item.PSIsContainer -or (Test-PlasticineReparsePoint $item)) {
        Stop-PlasticineHerdr "official installer did not produce a regular $fileName in private storage; nothing was published."
    }
    if ((Get-PlasticineFileHash $command) -ne ([string]$Plan.CommandDigest)) {
        Stop-PlasticineHerdr "official installer produced a $fileName that does not match the reviewed SHA-256; nothing was published."
    }
    $version = Get-PlasticineExecutableVersion $command
    if (-not $version) {
        Stop-PlasticineHerdr "official installer produced an unhealthy herdr command that does not report a stable version; nothing was published."
    }
    if ($version -ne $Plan.Version) {
        Stop-PlasticineHerdr "official installer produced herdr $version, not the reviewed baseline $($Plan.Version); nothing was published. Update the reviewed baseline before retrying."
    }
    Assert-PlasticineHerdrConptyManifest -Directory $Directory
}

function Move-PlasticineHerdrPath {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [switch]$Directory
    )
    if ($Directory) {
        Move-PlasticineDirectory -Source $Source -Destination $Destination
    } else {
        [IO.File]::Move($Source, $Destination)
    }
}

function Remove-PlasticineHerdrPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$Directory
    )
    if ($Directory) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    }
}

# One reviewed tree, several published entries. The entries are staged inside
# the destination directory first (so every commit is a same-directory rename),
# an existing entry is retained aside, and any failure - including the rollback
# path - restores the previous installation and removes what this run created.
function Publish-PlasticineHerdrDistribution {
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][string]$Candidate
    )
    $null = Assert-PlasticineAbsolutePath -Path $Candidate -Name 'herdr candidate directory'
    $installDirectory = [string]$Plan.InstallDirectory
    $null = Assert-PlasticineAbsolutePath -Path $installDirectory -Name 'herdr installation directory'
    $entries = @($Plan.Entries)
    # The rollback path removes published entries recursively, so every reviewed
    # entry must be a plain name directly below the managed command directory.
    foreach ($entry in $entries) {
        if (-not $entry -or [IO.Path]::GetFileName($entry) -ne $entry -or $entry.IndexOfAny([char[]]@('\', '/')) -ge 0) {
            Stop-PlasticineHerdr "the reviewed publication entry is not a plain pathname: $entry; nothing was published."
        }
    }
    $records = New-Object System.Collections.ArrayList
    try {
        foreach ($entry in $entries) {
            $source = Join-Path $Candidate $entry
            $sourceItem = Get-Item -LiteralPath $source -Force -ErrorAction SilentlyContinue
            if (-not $sourceItem) {
                Stop-PlasticineHerdr "the downloaded package is missing $entry; nothing was published."
            }
            $isDirectory = [bool]$sourceItem.PSIsContainer
            $target = Join-Path $installDirectory $entry
            $stagedPath = Join-Path $installDirectory ('.' + $entry + '.plasticine.' + [IO.Path]::GetRandomFileName())
            if (Get-PlasticineItem $stagedPath) {
                Stop-PlasticineHerdr 'private staging pathname unexpectedly exists; nothing was published.'
            }
            if ($isDirectory) {
                Copy-Item -LiteralPath $source -Destination $stagedPath -Recurse -ErrorAction Stop
            } else {
                Copy-Item -LiteralPath $source -Destination $stagedPath -ErrorAction Stop
            }
            $record = [pscustomobject]@{
                Name        = $entry
                Target      = $target
                Staged      = $stagedPath
                Retained    = ''
                Directory   = $isDirectory
                RetainedOld = $false
                Published   = $false
            }
            [void]$records.Add($record)

            if (Get-PlasticineItem $target) {
                $retainedPath = Join-Path $installDirectory ('.' + $entry + '.plasticine-old.' + [IO.Path]::GetRandomFileName())
                Move-PlasticineHerdrPath -Source $target -Destination $retainedPath -Directory:$isDirectory
                $record.Retained = $retainedPath
                $record.RetainedOld = $true
            }
            Move-PlasticineHerdrPath -Source $stagedPath -Destination $target -Directory:$isDirectory
            $record.Staged = ''
            $record.Published = $true
        }
    } catch {
        $failure = $_.Exception.Message
        $rollbackFailure = ''
        for ($index = $records.Count - 1; $index -ge 0; $index--) {
            $record = $records[$index]
            try {
                if ($record.Published -and (Get-PlasticineItem $record.Target)) {
                    Remove-PlasticineHerdrPath -Path $record.Target -Directory:$record.Directory
                }
                if ($record.RetainedOld -and $record.Retained -and (Get-PlasticineItem $record.Retained)) {
                    Move-PlasticineHerdrPath -Source $record.Retained -Destination $record.Target -Directory:$record.Directory
                }
            } catch {
                $rollbackFailure = $record.Target
            }
        }
        foreach ($record in $records) {
            if ($record.Staged -and (Get-PlasticineItem $record.Staged)) {
                Remove-PlasticineHerdrPath -Path $record.Staged -Directory:$record.Directory
            }
        }
        if ($rollbackFailure) {
            Stop-PlasticineHerdr "whole-directory publication failed and rollback failed; the previous installation is retained next to $rollbackFailure. Underlying error: $failure"
        }
        Stop-PlasticineHerdr "whole-directory publication failed; the previous installation was restored: $installDirectory. Underlying error: $failure"
    }
    foreach ($record in $records) {
        if ($record.RetainedOld -and $record.Retained -and (Get-PlasticineItem $record.Retained)) {
            Remove-PlasticineHerdrPath -Path $record.Retained -Directory:$record.Directory
        }
    }
}

# The upstream installer always prepends the release directory it just created to
# the user-level PATH. That directory lives in the private work tree, so the
# previous raw value is written back before this route appends its own entry.
function Set-PlasticineHerdrUserPathRaw {
    param([AllowEmptyString()][string]$Value = '')
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($PlasticineUserEnvironmentSubKey, $true)
    if (-not $key) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($PlasticineUserEnvironmentSubKey)
    }
    try {
        if ($Value -eq '') {
            $key.DeleteValue('Path', $false)
            return
        }
        $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
        try { $kind = $key.GetValueKind('Path') } catch { }
        $key.SetValue('Path', $Value, $kind)
    } finally {
        $key.Dispose()
    }
}

function Restore-PlasticineHerdrUserPath {
    param([AllowEmptyString()][string]$Expected = '')
    $current = Get-PlasticineUserPath
    if ($current -eq $Expected) { return $false }
    Set-PlasticineHerdrUserPathRaw -Value $Expected
    if ((Get-PlasticineUserPath) -ne $Expected) {
        Stop-PlasticineHerdr 'the upstream installer changed the user-level PATH and it could not be restored; the existing installation was left untouched. Repair HKCU\Environment\Path manually, then retry.'
    }
    $null = Send-PlasticineEnvironmentSettingChange
    Write-PlasticineLog 'herdr: restored the user-level PATH that the upstream installer changed during the private installation.'
    return $true
}

function Assert-PlasticineHerdrPathEntry {
    param([Parameter(Mandatory = $true)]$Plan)
    if ($null -eq (Resolve-PlasticineUserPathAddition -Directory $Plan.InstallDirectory)) { return }
    $backupDirectory = Join-Path $Plan.HomeDirectory '.plasticine\backups\user-path'
    $added = Add-PlasticineUserPathEntry -Directory $Plan.InstallDirectory -BackupDirectory $backupDirectory
    if ($added) {
        Write-PlasticineLog "herdr: added $($Plan.InstallDirectory) to the user-level PATH; reopen the terminal to pick it up."
    } else {
        Write-PlasticineLog "herdr: the user-level PATH already contains $($Plan.InstallDirectory); nothing to change."
    }
}

# A managed installation is only reusable while the ConPTY runtime that
# herdr.exe loads from its own directory is still complete.
function Test-PlasticineHerdrRuntime {
    param([Parameter(Mandatory = $true)]$Plan)
    foreach ($relative in @($Plan.ConptyFiles)) {
        $path = Join-Path $Plan.InstallDirectory $relative
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if (-not $item -or $item.PSIsContainer -or (Test-PlasticineReparsePoint $item)) { return $false }
    }
    return $true
}

function Assert-PlasticineHerdrPublishedTree {
    param([Parameter(Mandatory = $true)]$Plan)
    $command = [string]$Plan.Command
    $version = Get-PlasticineExecutableVersion $command
    if (-not $version) {
        Stop-PlasticineHerdr "published $([IO.Path]::GetFileName($command)) failed its final health check at ${command}; repair the installation and retry."
    }
    if ($version -ne $Plan.Version) {
        Stop-PlasticineHerdr "post-publication version $version does not match the resolved target $($Plan.Version); configuration was not applied."
    }
    if ((Get-PlasticineFileHash $command) -ne ([string]$Plan.CommandDigest)) {
        Stop-PlasticineHerdr "published $([IO.Path]::GetFileName($command)) does not match the reviewed SHA-256; configuration was not applied."
    }
    foreach ($relative in $PlasticineHerdrConptyFiles) {
        $path = Join-Path $Plan.InstallDirectory $relative
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if (-not $item -or $item.PSIsContainer -or (Test-PlasticineReparsePoint $item)) {
            Stop-PlasticineHerdr "the published ConPTY runtime is incomplete ($relative); configuration was not applied."
        }
    }
}

function Get-PlasticineHerdrPlan {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    $null = Assert-PlasticineAbsolutePath -Path $HomeDirectory -Name 'home directory'
    Assert-PlasticineWindowsPlatform
    $localDirectory = Join-Path $HomeDirectory '.local'
    $installDirectory = Join-Path $localDirectory 'bin'
    $command = Join-Path $installDirectory $PlasticineHerdrCommand
    $conptyDirectory = Join-Path $installDirectory $PlasticineHerdrConptyDirectory
    Assert-PlasticineInstallDestination -Parent @($HomeDirectory, $localDirectory, $installDirectory) -Target $command
    Assert-PlasticineHerdrDestination -ConptyDirectory $conptyDirectory
    $observed = Resolve-PlasticineHerdrExecutable -Target $command
    $owner = 'missing'
    if ($observed) {
        if ($observed -eq [IO.Path]::GetFullPath($command)) { $owner = 'managed' } else { $owner = 'external' }
    }
    $configDirectory = Get-PlasticineHerdrConfigDirectory
    $configFile = ''
    if ($configDirectory) { $configFile = Join-Path $configDirectory 'config.toml' }
    return [pscustomobject]@{
        Version          = $PlasticineHerdrVersion
        InstallerUrl     = $PlasticineHerdrInstallerUrl
        InstallerDigest  = $PlasticineHerdrInstallerDigest
        ManifestUrl      = $PlasticineHerdrManifestUrl
        HomeDirectory    = $HomeDirectory
        LocalDirectory   = $localDirectory
        InstallDirectory = $installDirectory
        Command          = $command
        CommandDigest    = $PlasticineHerdrCommandDigest
        ConptyDirectory  = $conptyDirectory
        ConptyMarker     = $PlasticineHerdrConptyMarker
        ConptyFiles      = @($PlasticineHerdrConptyFiles)
        Entries          = @($PlasticineHerdrEntries)
        ConfigDirectory  = $configDirectory
        ConfigFile       = $configFile
        PathMissing      = ($null -ne (Resolve-PlasticineUserPathAddition -Directory $installDirectory))
        Observed         = $observed
        Owner            = $owner
    }
}

function Write-PlasticineHerdrPreview {
    param([Parameter(Mandatory = $true)]$Plan)
    Write-PlasticineLog ("herdr: observed windows/amd64; pinned baseline $($Plan.Version) from the reviewed official install.ps1.")
    Write-PlasticineLog '  Fixed supported baseline: herdr 0.9.5 for x86_64-pc-windows-msvc through the reviewed upstream installer; the package carries the ConPTY runtime.'
    Write-PlasticineLog '  A missing installation is published; an older managed installation is safely replaced; a current installation is retained without release traffic.'
    Write-PlasticineLog '  An external installation below the baseline, and any unhealthy, prerelease, or custom installation, is refused and left for its owner. No shadow installation.'
    Write-PlasticineLog "  network during apply (only when installation or replacement is needed): $($Plan.InstallerUrl)"
    Write-PlasticineLog "    the reviewed installer then resolves $($Plan.ManifestUrl) and verifies the manifest SHA-256 of the package over HTTPS; Plasticine adds no independent signature."
    Write-PlasticineLog '  commands during apply: System32 curl.exe download; Get-FileHash of the installer against the reviewed SHA-256; the reviewed script runs in a private candidate directory; herdr.exe --version and the ConPTY manifest are checked before publication.'
    Write-PlasticineLog "  destination: $($Plan.Command) and the $($Plan.ConptyDirectory) runtime directory in $($Plan.InstallDirectory) (whole-tree fresh no-clobber publication; an authorized upgrade uses a checked rename swap with rollback)."
    Write-PlasticineLog '  installer environment: HERDR_HOME and HERDR_INSTALL_DIR point at private storage and HERDR_CHANNEL=stable; the release directory the installer prepends to the user-level PATH is removed again afterwards.'
    Write-PlasticineLog "  configuration: herdr reads $($Plan.ConfigFile) on Windows, not ~/.config/herdr; the herdr configuration Feature maintains that file and no session, server, or integration state is touched here."
    Write-PlasticineLog '  a native `herdr update` installs its own layout and user PATH entry; Plasticine then reports that owner as external instead of shadowing it.'
    if ($Plan.PathMissing) {
        Write-PlasticineLog "  command path: $($Plan.InstallDirectory) (will be appended to the user-level PATH; nothing else is added)."
    } else {
        Write-PlasticineLog "  command path: $($Plan.InstallDirectory) (already on the user-level PATH)."
    }
    if ($Plan.Observed) {
        Write-PlasticineLog "  Observed executable: $($Plan.Observed) (owner=$($Plan.Owner)); its version and owner will be classified during apply."
    }
}

function Invoke-PlasticineHerdrPrepare {
    param([Parameter(Mandatory = $true)]$Plan)
    Assert-PlasticineWindowsPlatform

    # Re-observe at confirmed apply: only the managed command pathname is an
    # authorized replacement owner.
    $command = [IO.Path]::GetFullPath([string]$Plan.Command)
    $bin = Resolve-PlasticineHerdrExecutable -Target $command
    $publication = 'fresh'
    $observedVersion = ''
    if ($bin) {
        $owner = 'external'
        if ($bin -eq $command) { $owner = 'managed' }
        $observedVersion = Get-PlasticineExecutableVersion $bin
        if (-not $observedVersion) {
            Stop-PlasticineHerdr "existing executable is unhealthy or has an unverifiable/prerelease/custom version: $bin; repair its owner. Left untouched."
        }
        if ((Compare-PlasticineVersion $observedVersion $Plan.Version) -ge 0) {
            if ($owner -eq 'managed') {
                if (Test-PlasticineHerdrRuntime -Plan $Plan) {
                    Assert-PlasticineHerdrPathEntry -Plan $Plan
                    Write-PlasticineLog "herdr: pinned baseline $($Plan.Version) is satisfied by stable $observedVersion at $bin; no installer download or replacement."
                    return
                }
                # The command is current but the runtime it loads is incomplete:
                # the whole tree is repaired instead of being used or shadowed.
                $publication = 'repair'
                Write-PlasticineLog 'herdr: the managed ConPTY runtime is incomplete; repairing the whole published tree.'
            } else {
                Write-PlasticineLog "herdr: pinned baseline $($Plan.Version) is satisfied by stable $observedVersion at $bin; no installer download or replacement."
                return
            }
        } elseif ($owner -ne 'managed') {
            Stop-PlasticineHerdr "outdated Herdr $observedVersion at unsupported owner path $bin; update it with its owner. No shadow installation was created."
        } else {
            $publication = 'upgrade'
        }
    } elseif (Get-PlasticineItem $Plan.ConptyDirectory) {
        Stop-PlasticineHerdr "an unowned ConPTY directory exists at $($Plan.ConptyDirectory); remove or repair it explicitly. Left untouched."
    }

    $userPathBefore = Get-PlasticineUserPath
    $work = New-PlasticineTempDirectory 'plasticine-herdr'
    try {
        $installer = Join-Path $work 'herdr-install.ps1'
        Invoke-PlasticineDownload -Url $Plan.InstallerUrl -Destination $installer `
            -FailureMessage 'herdr: official installer download failed; the existing installation was left untouched.'
        Assert-PlasticineHerdrInstallerScript -Path $installer -Digest ([string]$Plan.InstallerDigest)

        $candidate = Join-Path $work 'candidate'
        $herdrHome = Join-Path $work 'home'
        New-Item -ItemType Directory -Path $herdrHome -ErrorAction Stop | Out-Null
        $observed = 'missing'
        if ($observedVersion) { $observed = $observedVersion }
        Write-PlasticineLog "herdr: observed=$observed; target=$($Plan.Version); route=$publication."
        try {
            $null = Invoke-PlasticineHerdrInstaller -Installer $installer -CandidateDirectory $candidate `
                -HerdrHome $herdrHome -WorkDirectory $work
        } finally {
            # The installer always writes its own release directory into the user
            # PATH; restore the snapshot even when the run itself failed.
            $null = Restore-PlasticineHerdrUserPath -Expected $userPathBefore
        }
        Assert-PlasticineHerdrCandidate -Directory $candidate -Plan $Plan

        $parents = @($Plan.HomeDirectory, $Plan.LocalDirectory, $Plan.InstallDirectory)
        Assert-PlasticineInstallDestination -Parent $parents -Target $Plan.Command
        foreach ($directory in @($Plan.LocalDirectory, $Plan.InstallDirectory)) {
            if (-not (Get-PlasticineItem $directory)) {
                New-Item -ItemType Directory -Path $directory -ErrorAction Stop | Out-Null
                Set-PlasticineOwnerOnlyAcl -Path $directory
            }
        }
        Assert-PlasticineInstallDestination -Parent $parents -Target $Plan.Command
        Assert-PlasticineHerdrDestination -ConptyDirectory $Plan.ConptyDirectory
        Publish-PlasticineHerdrDistribution -Plan $Plan -Candidate $candidate
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }

    Assert-PlasticineHerdrPublishedTree -Plan $Plan
    Assert-PlasticineHerdrPathEntry -Plan $Plan
    Write-PlasticineLog "herdr: $publication completed at stable target $($Plan.Version): $($Plan.Command)"
}
