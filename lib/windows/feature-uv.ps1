# PowerShell equivalent of lib/uv-bootstrap.sh for the Windows route. The Unix
# route runs the shell installer in place; the Windows installer force-overwrites
# its destination and writes its own updater receipt, so this route runs the
# reviewed official uv-installer.ps1 inside private candidate storage and only
# then publishes the reviewed command pair into ~/.local/bin. Ownership, reuse
# and refusal rules match the other Windows tool routes: a healthy managed pair
# at or above the pinned baseline is reused without release traffic, an older
# managed pair is replaced, and an external uv/uvx is never shadowed.

if (-not (Get-Command Write-PlasticineLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'common.ps1')
}
if (-not (Get-Command Publish-PlasticineNewFile -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'publish.ps1')
}
if (-not (Get-Command Set-PlasticineOwnerOnlyAcl -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'acl.ps1')
}
if (Get-Command Get-PlasticineUvPlan -ErrorAction SilentlyContinue) { return }

$PlasticineUvVersion = '0.13.8'
# Reviewed from the official uv 0.13.8 GitHub Release asset on 2026-11-15; the
# versioned Astral copy (https://astral.sh/uv/0.13.8/install.ps1) is the same
# bytes. The installer itself pins every archive URL it downloads to 0.13.8, so
# this URL is a versioned reviewed artifact and never a dynamic "latest".
$PlasticineUvInstallerUrl = 'https://github.com/astral-sh/uv/releases/download/0.13.8/uv-installer.ps1'
$PlasticineUvInstallerDigest = '200a377ed0f8e719b1c9cbe849c736e7712ee684212f61dc9565d747ac163db0'
$PlasticineUvInstallerAppName = 'uv'
$PlasticineUvCommands = @('uv.exe', 'uvx.exe')
# The installer copies both commands out of uv-x86_64-pc-windows-msvc.zip without
# publishing a digest for that archive, so the reviewed command SHA-256 values
# below are the anchor for what may be published. They were taken from the
# official 0.13.8 Windows archive on 2026-11-15.
$PlasticineUvCommandDigests = [ordered]@{
    'uv.exe'  = '03fa174894b9d0cbe08762d40d1c2c64d10e875bd56f1a1e334ee1e00d60cdbe'
    'uvx.exe' = '848dac6b5a5d0e03c5b3fcf7fc9e697c1be59d40b1989e428c95806f44443d6b'
}
$PlasticineUvInstallerTimeoutSeconds = 1800

function Stop-PlasticineUv {
    param([Parameter(Mandatory = $true)][string]$Message)
    Stop-Plasticine "uv: $Message"
}

# PATH first, then the managed target, so a foreign installation is observed as
# itself instead of being mistaken for the managed pair.
function Resolve-PlasticineUvExecutable {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string]$Target
    )
    $found = Get-PlasticineCommandPath $Command
    if ($found) { return [IO.Path]::GetFullPath($found) }
    $item = Get-PlasticineItem $Target
    if ($item -and -not $item.PSIsContainer -and -not (Test-PlasticineReparsePoint $item)) {
        return [IO.Path]::GetFullPath($Target)
    }
    return $null
}

# Runs the reviewed installer in a child Windows PowerShell with an environment
# that isolates the whole installation. StartInfo is used instead of the ambient
# environment so nothing the parent shell exported can redirect the install.
function Invoke-PlasticineUvInstallerProcess {
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
        Stop-PlasticineUv "missing the Windows PowerShell host needed to run the reviewed installer: $powershell"
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
        $exited = $process.WaitForExit([int]($PlasticineUvInstallerTimeoutSeconds * 1000))
        if (-not $exited) {
            try { $process.Kill() } catch { }
            Stop-PlasticineUv "official installer did not finish within $PlasticineUvInstallerTimeoutSeconds seconds; nothing was published."
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
        Stop-PlasticineUv ('official installer could not be executed: ' + $_.Exception.Message)
    } finally {
        if ($process) { try { $process.Dispose() } catch { } }
    }
}

# Test seam: the suites replace this scriptblock so no network or child process
# is needed. It receives the reviewed script, the isolated environment and the
# private work directory, and returns an object with an ExitCode property.
$PlasticineUvInstallerRunner = {
    param(
        [Parameter(Mandatory = $true)][string]$Installer,
        [Parameter(Mandatory = $true)][hashtable]$Environment,
        [string[]]$RemoveEnvironment = @(),
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )
    return (Invoke-PlasticineUvInstallerProcess -Installer $Installer -Environment $Environment `
        -RemoveEnvironment $RemoveEnvironment -WorkingDirectory $WorkingDirectory)
}

# The reviewed script carries its own identity the same way the Unix installer
# does; a file that passes the digest but not this check is not the reviewed
# installer and must never be executed.
function Assert-PlasticineUvInstallerIdentity {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Version
    )
    $null = Assert-PlasticineAbsolutePath -Path $Path -Name 'reviewed installer path'
    $text = [IO.File]::ReadAllText($Path)
    $namePattern = '(?m)^\$app_name\s*=\s*' + [regex]::Escape("'" + $PlasticineUvInstallerAppName + "'") + '\s*$'
    $versionPattern = '(?m)^\$app_version\s*=\s*' + [regex]::Escape("'" + $Version + "'") + '\s*$'
    if (-not [regex]::IsMatch($text, $namePattern) -or -not [regex]::IsMatch($text, $versionPattern)) {
        Stop-PlasticineUv 'the downloaded file is not the reviewed uv installer (identity check failed); nothing changed.'
    }
}

# Everything the reviewed installer is allowed to see is redirected into the
# private work directory. UV_NO_MODIFY_PATH keeps the user PATH untouched,
# UV_DISABLE_UPDATE suppresses the updater receipt (this route never claims
# `uv self update`), and XDG_CONFIG_HOME keeps any future receipt private too.
function New-PlasticineUvInstallerEnvironment {
    param(
        [Parameter(Mandatory = $true)][string]$CandidateDirectory,
        [Parameter(Mandatory = $true)][string]$WorkDirectory
    )
    return @{
        UV_INSTALL_DIR     = $CandidateDirectory
        UV_NO_MODIFY_PATH  = '1'
        UV_DISABLE_UPDATE  = '1'
        XDG_CONFIG_HOME    = (Join-Path $WorkDirectory 'config')
    }
}

# Exporting these would redirect the installer away from its reviewed 0.13.8
# archives or make it edit an unrelated CI PATH file.
$PlasticineUvInstallerEnvironmentRemovals = @(
    'UV_UNMANAGED_INSTALL',
    'UV_DOWNLOAD_URL',
    'INSTALLER_DOWNLOAD_URL',
    'UV_INSTALLER_GHE_BASE_URL',
    'UV_INSTALLER_GITHUB_BASE_URL',
    'CARGO_DIST_FORCE_INSTALL_DIR',
    'INSTALLER_NO_MODIFY_PATH',
    'GITHUB_PATH'
)

function Invoke-PlasticineUvInstaller {
    param(
        [Parameter(Mandatory = $true)][string]$Installer,
        [Parameter(Mandatory = $true)][string]$CandidateDirectory,
        [Parameter(Mandatory = $true)][string]$WorkDirectory
    )
    $runner = $PlasticineUvInstallerRunner
    if (-not $runner) {
        Stop-PlasticineUv 'the installer runner seam is not configured; nothing changed.'
    }
    $environment = New-PlasticineUvInstallerEnvironment -CandidateDirectory $CandidateDirectory -WorkDirectory $WorkDirectory
    try {
        $result = & $runner -Installer $Installer -Environment $environment `
            -RemoveEnvironment $PlasticineUvInstallerEnvironmentRemovals -WorkingDirectory $WorkDirectory
    } catch [PlasticineStopException] {
        throw
    } catch {
        Stop-PlasticineUv ('official installer could not be started: ' + $_.Exception.Message)
    }
    if ($null -eq $result -or $null -eq $result.ExitCode -or [int]$result.ExitCode -ne 0) {
        $detail = ''
        if ($result -and $result.Error) { $detail = ' ' + ([string]$result.Error).Trim() }
        Stop-PlasticineUv ("official installer failed; the active installation was left untouched.$detail")
    }
    return $result
}

# The candidate must match the reviewed tuple exactly before anything is
# published: both commands, their reviewed bytes and the pinned stable version.
function Assert-PlasticineUvCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)]$Plan
    )
    $null = Assert-PlasticineAbsolutePath -Path $Directory -Name 'uv candidate directory'
    $commands = @($Plan.Commands)
    foreach ($command in $commands) {
        $path = Join-Path $Directory $command
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if (-not $item -or $item.PSIsContainer -or (Test-PlasticineReparsePoint $item)) {
            Stop-PlasticineUv "official installer did not produce a regular $command in private storage; nothing was published."
        }
        $expected = $Plan.CommandDigests[$command]
        if ($expected -and (Get-PlasticineFileHash $path) -ne ([string]$expected)) {
            Stop-PlasticineUv "official installer produced a $command that does not match the reviewed SHA-256; nothing was published."
        }
        $version = Get-PlasticineExecutableVersion $path
        if (-not $version) {
            Stop-PlasticineUv "official installer produced an unhealthy $command that does not report a stable version; nothing was published."
        }
        if ($version -ne $Plan.Version) {
            Stop-PlasticineUv "official installer produced $command version $version, not the reviewed target $($Plan.Version); nothing was published."
        }
    }
}

# uvx is published first and uv last, so the primary command only appears once
# its pair is in place. A failed uv publication removes the uvx this run created
# (an updated uvx is kept: the previous uv is still reachable and the next run
# repairs the pair).
function Publish-PlasticineUvCommands {
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$UvAction,
        [Parameter(Mandatory = $true)][string]$UvxAction,
        [AllowEmptyString()][string]$UvHash = '',
        [AllowEmptyString()][string]$UvxHash = ''
    )
    $parents = @($Plan.HomeDirectory, $Plan.LocalDirectory, $Plan.InstallDirectory)
    Assert-PlasticineInstallDestination -Parent $parents -Target $Plan.UvTarget
    Assert-PlasticineInstallDestination -Parent $parents -Target $Plan.UvxTarget
    foreach ($directory in @($Plan.LocalDirectory, $Plan.InstallDirectory)) {
        if (-not (Get-PlasticineItem $directory)) {
            New-Item -ItemType Directory -Path $directory -ErrorAction Stop | Out-Null
            Set-PlasticineOwnerOnlyAcl -Path $directory
        }
    }
    Assert-PlasticineInstallDestination -Parent $parents -Target $Plan.UvTarget
    Assert-PlasticineInstallDestination -Parent $parents -Target $Plan.UvxTarget

    $stagedUvx = Join-Path $Plan.InstallDirectory ('.uvx.plasticine.' + [IO.Path]::GetRandomFileName())
    $stagedUv = Join-Path $Plan.InstallDirectory ('.uv.plasticine.' + [IO.Path]::GetRandomFileName())
    try {
        Copy-Item -LiteralPath (Join-Path $Candidate 'uvx.exe') -Destination $stagedUvx -ErrorAction Stop
        Copy-Item -LiteralPath (Join-Path $Candidate 'uv.exe') -Destination $stagedUv -ErrorAction Stop
        if ($UvxAction -eq 'fresh') {
            Publish-PlasticineNewFile -Candidate $stagedUvx -Target $Plan.UvxTarget
        } else {
            Update-PlasticineFile -Candidate $stagedUvx -Target $Plan.UvxTarget -ExpectedHash $UvxHash
        }
        try {
            if ($UvAction -eq 'fresh') {
                Publish-PlasticineNewFile -Candidate $stagedUv -Target $Plan.UvTarget
            } else {
                Update-PlasticineFile -Candidate $stagedUv -Target $Plan.UvTarget -ExpectedHash $UvHash
            }
        } catch {
            if ($UvxAction -eq 'fresh' -and (Test-Path -LiteralPath $Plan.UvxTarget -PathType Leaf)) {
                Remove-Item -LiteralPath $Plan.UvxTarget -Force -ErrorAction SilentlyContinue
            }
            throw
        }
    } finally {
        foreach ($stage in @($stagedUv, $stagedUvx)) {
            if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Get-PlasticineUvPlan {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    $null = Assert-PlasticineAbsolutePath -Path $HomeDirectory -Name 'home directory'
    Assert-PlasticineWindowsPlatform
    $localDirectory = Join-Path $HomeDirectory '.local'
    $installDirectory = Join-Path $localDirectory 'bin'
    $uvTarget = Join-Path $installDirectory 'uv.exe'
    $uvxTarget = Join-Path $installDirectory 'uvx.exe'
    $parents = @($HomeDirectory, $localDirectory, $installDirectory)
    Assert-PlasticineInstallDestination -Parent $parents -Target $uvTarget
    Assert-PlasticineInstallDestination -Parent $parents -Target $uvxTarget
    return [pscustomobject]@{
        Version          = $PlasticineUvVersion
        InstallerUrl     = $PlasticineUvInstallerUrl
        InstallerDigest  = $PlasticineUvInstallerDigest
        Commands         = @($PlasticineUvCommands)
        CommandDigests   = $PlasticineUvCommandDigests
        HomeDirectory    = $HomeDirectory
        LocalDirectory   = $localDirectory
        InstallDirectory = $installDirectory
        UvTarget         = $uvTarget
        UvxTarget        = $uvxTarget
        Observed         = Resolve-PlasticineUvExecutable -Command 'uv' -Target $uvTarget
        UvxObserved      = Resolve-PlasticineUvExecutable -Command 'uvx' -Target $uvxTarget
    }
}

function Write-PlasticineUvPreview {
    param([Parameter(Mandatory = $true)]$Plan)
    Write-PlasticineLog ("uv: observed windows/amd64; pinned baseline $($Plan.Version) from the reviewed official installer.")
    Write-PlasticineLog "  Fixed supported baseline: uv $($Plan.Version) through its exact versioned uv-installer.ps1; the installer downloads only $($Plan.Version) archives."
    Write-PlasticineLog '  A missing pair is installed; an older managed pair at the managed paths is safely replaced; a current pair is retained without release traffic.'
    Write-PlasticineLog '  An external uv/uvx, and any unhealthy, prerelease, or custom managed installation, is refused and left for its owner. No shadow installation.'
    Write-PlasticineLog "  network during apply (only when installation or repair is needed): $($Plan.InstallerUrl)"
    Write-PlasticineLog '    the reviewed installer then fetches uv-x86_64-pc-windows-msvc.zip from the HTTPS URLs pinned inside it; upstream publishes no digest for that archive, so this route trusts that HTTPS boundary and verifies the reviewed command SHA-256 afterwards.'
    Write-PlasticineLog "  commands during apply: System32 curl.exe download; Get-FileHash of the installer and of both candidate commands against the reviewed SHA-256; the reviewed script runs in a private candidate directory."
    Write-PlasticineLog "  destination: $($Plan.InstallDirectory)\uv.exe and uvx.exe (fresh atomic no-clobber publication; an authorized upgrade uses checked atomic replacement)."
    Write-PlasticineLog '  installer environment: UV_INSTALL_DIR points at private storage, UV_NO_MODIFY_PATH=1, UV_DISABLE_UPDATE=1; the user PATH and shell startup are not edited by this route.'
    Write-PlasticineLog '  no updater receipt is published, so uv reports a package-manager-style installation and `uv self update` stays outside this pinned route; re-run Plasticine to update.'
    Write-PlasticineLog '  only the reviewed command pair is published; the optional uvw.exe console-less alias is not installed by this route.'
    Write-PlasticineLog '  Python versions, uv tools, cache, credentials, and project environments are not inspected, installed, or changed.'
    if ($Plan.Observed) {
        Write-PlasticineLog "  Observed uv: $($Plan.Observed); its version and owner will be classified during apply."
    }
    if ($Plan.UvxObserved) {
        Write-PlasticineLog "  Observed uvx: $($Plan.UvxObserved); its version and owner will be classified during apply."
    }
}

function Write-PlasticineUvRouteSummary {
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][string]$Route,
        [Parameter(Mandatory = $true)][string]$Reason,
        [AllowEmptyString()][string]$Version = ''
    )
    $observed = 'missing'
    if ($Version) { $observed = $Version }
    Write-PlasticineLog "uv: observed=$observed; target=$($Plan.Version); route=$Route; reason=$Reason."
}
function Invoke-PlasticineUvPrepare {
    param([Parameter(Mandatory = $true)]$Plan)
    Assert-PlasticineWindowsPlatform

    # Re-observe at confirmed apply. Only the two managed pathnames are
    # authorized owners; anything else on PATH keeps its own installation.
    $uvTarget = [IO.Path]::GetFullPath([string]$Plan.UvTarget)
    $uvxTarget = [IO.Path]::GetFullPath([string]$Plan.UvxTarget)
    $uvBin = Resolve-PlasticineUvExecutable -Command 'uv' -Target $uvTarget
    $uvxBin = Resolve-PlasticineUvExecutable -Command 'uvx' -Target $uvxTarget
    if ($uvBin -and $uvBin -ne $uvTarget) {
        Stop-PlasticineUv "external uv at $uvBin; maintain it through its owner. No shadow installation."
    }
    if ($uvxBin -and $uvxBin -ne $uvxTarget) {
        Stop-PlasticineUv "external uvx at $uvxBin; maintain it through its owner. No shadow installation."
    }

    $uvVersion = ''
    $uvxVersion = ''
    $uvAction = 'fresh'
    $uvxAction = 'fresh'
    $uvHash = ''
    $uvxHash = ''
    if ($uvBin) {
        $uvVersion = Get-PlasticineExecutableVersion $uvTarget
        if (-not $uvVersion) {
            Stop-PlasticineUv "managed uv is unhealthy or has an unverifiable/prerelease/custom version: $uvBin; repair it before retrying."
        }
        $uvHash = Get-PlasticineFileHash $uvTarget
        $uvAction = 'replace'
    }
    if ($uvxBin) {
        $uvxVersion = Get-PlasticineExecutableVersion $uvxTarget
        if (-not $uvxVersion) {
            Stop-PlasticineUv "managed uvx is unhealthy or has an unverifiable/prerelease/custom version: $uvxBin; repair it before retrying."
        }
        $uvxHash = Get-PlasticineFileHash $uvxTarget
        $uvxAction = 'replace'
    }

    $route = 'install'
    $reason = 'no managed installation'
    if ($uvBin -and $uvxBin) {
        if ($uvxVersion -ne $uvVersion) {
            $route = 'repair'
            $reason = 'uv and uvx versions differ'
        } elseif ((Compare-PlasticineVersion $uvVersion $Plan.Version) -ge 0) {
            Write-PlasticineLog "uv: pinned baseline $($Plan.Version) is satisfied by stable $uvVersion at $uvBin; no installer download or replacement."
            return
        } else {
            $route = 'update'
            $reason = 'the managed pair is older than the pinned baseline'
        }
    } elseif ($uvBin) {
        $route = 'repair'
        $reason = 'uvx is missing'
    } elseif ($uvxBin) {
        $route = 'repair'
        $reason = 'uvx exists without uv'
    }

    $work = New-PlasticineTempDirectory 'plasticine-uv'
    try {
        $installer = Join-Path $work 'uv-installer.ps1'
        Invoke-PlasticineDownload -Url $Plan.InstallerUrl -Destination $installer `
            -FailureMessage 'uv: official installer download failed; the active installation was left untouched.'
        if ((Get-PlasticineFileHash $installer) -ne ([string]$Plan.InstallerDigest)) {
            Stop-PlasticineUv 'the downloaded file is not the reviewed uv installer (SHA-256 mismatch); nothing changed.'
        }
        Assert-PlasticineUvInstallerIdentity -Path $installer -Version ([string]$Plan.Version)

        # A destination can appear while the installer is being prepared, so the
        # published paths are re-checked immediately before the private run.
        Assert-PlasticineInstallDestination -Parent @($Plan.HomeDirectory, $Plan.LocalDirectory, $Plan.InstallDirectory) `
            -Target $Plan.UvTarget
        Assert-PlasticineInstallDestination -Parent @($Plan.HomeDirectory, $Plan.LocalDirectory, $Plan.InstallDirectory) `
            -Target $Plan.UvxTarget

        $candidate = Join-Path $work 'candidate'
        New-Item -ItemType Directory -Path $candidate -ErrorAction Stop | Out-Null
        Write-PlasticineUvRouteSummary -Plan $Plan -Route $route -Reason $reason -Version $uvVersion
        $null = Invoke-PlasticineUvInstaller -Installer $installer -CandidateDirectory $candidate -WorkDirectory $work
        Assert-PlasticineUvCandidate -Directory $candidate -Plan $Plan
        Publish-PlasticineUvCommands -Plan $Plan -Candidate $candidate -UvAction $uvAction -UvxAction $uvxAction `
            -UvHash $uvHash -UvxHash $uvxHash
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }

    foreach ($command in @($Plan.Commands)) {
        $path = Join-Path $Plan.InstallDirectory $command
        $resultVersion = Get-PlasticineExecutableVersion $path
        if (-not $resultVersion) {
            Stop-PlasticineUv "published $command failed its final health check at ${path}; repair the installation and retry."
        }
        if ($resultVersion -ne $Plan.Version) {
            Stop-PlasticineUv "post-publication $command version $resultVersion does not match the resolved target $($Plan.Version); configuration was not applied."
        }
    }
    Write-PlasticineLog "uv: $route completed at stable target $($Plan.Version): $($Plan.InstallDirectory)"
}

