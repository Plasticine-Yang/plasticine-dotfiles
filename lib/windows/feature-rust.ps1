# PowerShell equivalent of lib/rust-bootstrap.sh for the Windows route. The same
# rustup-managed stable baseline is maintained (minimal profile plus rustfmt and
# clippy) and an existing healthy rustup keeps its version and host, but the
# native homes are private under ~/.local/opt, a first installation is reviewed
# against the official rustup-init.exe checksum sidecar, and a machine without
# MSVC Build Tools installs the gnu host instead of failing to link.
#
# Trust boundary: rustup publishes rustup-init.exe at an unversioned URL and
# offers no version-pinned reviewed digest to embed. This route therefore
# downloads the matching official SHA-256 sidecar over the same HTTPS host and
# refuses to execute the installer on any mismatch. TLS to static.rust-lang.org
# is the only trust anchor; a pinned digest cannot be embedded while the URL is
# unversioned. Reviewed 2026-11-15 against
# https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-gnu/rustup-init.exe
# (sidecar f6289656ce42e1099f3cbc6f10ef6321dfde54773faf599dd36fd3b1f07d9103).

if (-not (Get-Command Write-PlasticineLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'common.ps1')
}
if (-not (Get-Command Publish-PlasticineNewDirectory -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'publish.ps1')
}
if (-not (Get-Command Set-PlasticineOwnerOnlyAcl -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'acl.ps1')
}
if (-not (Get-Command Add-PlasticineUserPathEntry -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'user-path.ps1')
}
if (Get-Command Get-PlasticineRustPlan -ErrorAction SilentlyContinue) { return }

# Settled by the Windows contract: the reviewed route installs the gnu host
# because the target baseline may carry no Visual Studio Build Tools, and an
# existing healthy rustup never has its host switched.
$PlasticineRustDefaultHost = 'x86_64-pc-windows-gnu'
$PlasticineRustToolchain = 'stable'
$PlasticineRustProfile = 'minimal'
$PlasticineRustComponent = @('rustfmt', 'clippy')
$PlasticineRustAsset = 'rustup-init.exe'
$PlasticineRustAssetBase = 'https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-gnu'
$PlasticineRustAssetUrl = $PlasticineRustAssetBase + '/' + $PlasticineRustAsset
$PlasticineRustSidecarUrl = $PlasticineRustAssetUrl + '.sha256'
# The reviewed proxy set covers the commands this route publishes and verifies;
# rustup creates every one of them, so a missing proxy means a damaged install.
$PlasticineRustProxy = @(
    'rustup',
    'cargo',
    'rustc',
    'rustdoc',
    'rustfmt',
    'cargo-fmt',
    'clippy-driver',
    'cargo-clippy',
    'rust-analyzer',
    'rust-gdb',
    'rust-gdbgui',
    'rust-lldb'
)
$PlasticineRustVerifiedCommand = @('rustc', 'cargo', 'rustfmt', 'clippy-driver')
# The reviewed installers vswhere is the only accepted MSVC Build Tools
# evidence; a link.exe on PATH may be Git coreutils and is deliberately never
# consulted, and Build Tools are never installed by this route.
$PlasticineRustBuildToolsComponent = 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'

# Test seams: the two network-mutating command groups only. A null value runs
# the real command against the supplied native homes; tests replace these with
# offline fixtures. They are intentionally module variables (not functions) so a
# suite can swap one seam without redefining the whole provider.
$PlasticineRustInitRunner = $null
$PlasticineRustToolchainRunner = $null

function Stop-PlasticineRust {
    param([Parameter(Mandatory = $true)][string]$Message)
    Stop-Plasticine "rust: $Message"
}

# Every native rustup invocation goes through one process helper: the private
# homes are set for the child only, RUSTUP_AUTO_INSTALL is disabled so no command
# can silently install a toolchain, and an inherited project override is removed.
function Invoke-PlasticineRustCommand {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path,
        [string[]]$Argument = @(),
        [string]$CargoHome = '',
        [string]$RustupHome = ''
    )
    $null = Assert-PlasticineAbsolutePath -Path $Path -Name 'rust command'
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Stop-PlasticineRust "native rust command is missing: $Path"
    }
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Path
    $startInfo.Arguments = (@($Argument) -join ' ')
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    if ($CargoHome) {
        $null = Assert-PlasticineAbsolutePath -Path $CargoHome -Name 'CARGO_HOME'
        $startInfo.EnvironmentVariables['CARGO_HOME'] = $CargoHome
    }
    if ($RustupHome) {
        $null = Assert-PlasticineAbsolutePath -Path $RustupHome -Name 'RUSTUP_HOME'
        $startInfo.EnvironmentVariables['RUSTUP_HOME'] = $RustupHome
    }
    $startInfo.EnvironmentVariables['RUSTUP_AUTO_INSTALL'] = '0'
    $startInfo.EnvironmentVariables.Remove('RUSTUP_TOOLCHAIN')
    $process = $null
    try {
        $process = [System.Diagnostics.Process]::Start($startInfo)
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $null = $outputTask.Wait(30000)
        $null = $errorTask.Wait(30000)
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output   = [string]$outputTask.Result
            Error    = [string]$errorTask.Result
        }
    } finally {
        if ($process) { $process.Dispose() }
    }
}

function Get-PlasticineRustDestinations {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory)
    $null = Assert-PlasticineAbsolutePath -Path $HomeDirectory -Name 'home directory'
    $localDirectory = Join-Path $HomeDirectory '.local'
    $optDirectory = Join-Path $localDirectory 'opt'
    $cargoHome = Join-Path $optDirectory '.cargo'
    $rustupHome = Join-Path $optDirectory '.rustup'
    $binDirectory = Join-Path $cargoHome 'bin'
    return [pscustomobject]@{
        HomeDirectory  = $HomeDirectory
        LocalDirectory = $localDirectory
        OptDirectory   = $optDirectory
        CargoHome      = $cargoHome
        RustupHome     = $rustupHome
        BinDirectory   = $binDirectory
        RustupCommand  = (Join-Path $binDirectory 'rustup.exe')
        SettingsFile   = (Join-Path $rustupHome 'settings.toml')
    }
}

# Resolve one rustup line. `--version` prints the rustup version followed by
# informational stderr, so only the first stable line is accepted.
function Get-PlasticineRustupVersion {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RustupCommand,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$CargoHome,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RustupHome
    )
    if (-not (Test-Path -LiteralPath $RustupCommand -PathType Leaf)) { return $null }
    $result = Invoke-PlasticineRustCommand -Path $RustupCommand -Argument @('--version') `
        -CargoHome $CargoHome -RustupHome $RustupHome
    if ($result.ExitCode -ne 0) { return $null }
    foreach ($line in ($result.Output -split "`r?`n")) {
        if (([string]$line).Trim() -match '^rustup ([0-9]+\.[0-9]+\.[0-9]+)(\s|$)') { return $Matches[1] }
    }
    return $null
}

# `rustup show` reports the configured default host even when no toolchain is
# installed, which is exactly the state a first installation starts from.
function Get-PlasticineRustupHost {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RustupCommand,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$CargoHome,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RustupHome
    )
    if (-not (Test-Path -LiteralPath $RustupCommand -PathType Leaf)) { return $null }
    $result = Invoke-PlasticineRustCommand -Path $RustupCommand -Argument @('show') `
        -CargoHome $CargoHome -RustupHome $RustupHome
    if ($result.ExitCode -ne 0) { return $null }
    foreach ($line in ($result.Output -split "`r?`n")) {
        if (([string]$line).Trim() -match '^Default host:\s*(\S+)$') { return $Matches[1] }
    }
    return $null
}

# The default toolchain is `none` when rustup reports no configured default; any
# other unreadable output is a damaged settings state and returns null.
function Get-PlasticineRustDefault {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RustupCommand,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$CargoHome,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RustupHome
    )
    $result = Invoke-PlasticineRustCommand -Path $RustupCommand -Argument @('default') `
        -CargoHome $CargoHome -RustupHome $RustupHome
    if ($result.ExitCode -ne 0) {
        $text = [string]$result.Output + "`n" + [string]$result.Error
        if ($text -match 'no default toolchain is configured') { return 'none' }
        return $null
    }
    foreach ($line in ($result.Output -split "`r?`n")) {
        if (([string]$line).Trim() -match '^(.*?)\s+\(default\)$') { return $Matches[1].Trim() }
    }
    return $null
}

function Set-PlasticineRustDefault {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RustupCommand,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$CargoHome,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RustupHome,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Name
    )
    $result = Invoke-PlasticineRustCommand -Path $RustupCommand -Argument @('default', $Name) `
        -CargoHome $CargoHome -RustupHome $RustupHome
    if ($result.ExitCode -ne 0) {
        Stop-PlasticineRust "could not set the default toolchain to $Name; repair rustup settings before retrying."
    }
}

function Get-PlasticineRustMissingProxy {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$CargoHome
    )
    $binDirectory = Join-Path $CargoHome 'bin'
    $missing = @()
    foreach ($name in $PlasticineRustProxy) {
        if (-not (Test-Path -LiteralPath (Join-Path $binDirectory ($name + '.exe')) -PathType Leaf)) {
            $missing += ($name + '.exe')
        }
    }
    return $missing
}

# rustup publishes one proxy executable per known command, so the presence of
# every reviewed proxy is the local evidence that the installation is complete.
function Test-PlasticineRustStableToolchain {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RustupCommand,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$CargoHome,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RustupHome,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HostTuple
    )
    $result = Invoke-PlasticineRustCommand -Path $RustupCommand -Argument @('toolchain', 'list') `
        -CargoHome $CargoHome -RustupHome $RustupHome
    if ($result.ExitCode -ne 0) { return $false }
    $expected = '^stable-' + [regex]::Escape($HostTuple) + '(\s|$)'
    foreach ($line in ($result.Output -split "`r?`n")) {
        if (([string]$line).Trim() -match $expected) { return $true }
    }
    return $false
}

function Test-PlasticineRustComponents {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RustupCommand,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$CargoHome,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RustupHome
    )
    $result = Invoke-PlasticineRustCommand -Path $RustupCommand `
        -Argument @('component', 'list', '--installed', '--toolchain', 'stable', '-q') `
        -CargoHome $CargoHome -RustupHome $RustupHome
    if ($result.ExitCode -ne 0) { return $false }
    $names = @()
    foreach ($line in ($result.Output -split "`r?`n")) {
        $name = ([string]$line).Trim()
        if ($name) { $names += $name }
    }
    foreach ($component in $PlasticineRustComponent) {
        $found = $false
        foreach ($name in $names) {
            if ($name -match ('^' + [regex]::Escape($component) + '(-|$)')) { $found = $true; break }
        }
        if (-not $found) { return $false }
    }
    return $true
}

# Verifies that the installed stable toolchain actually runs the reviewed
# commands. `rustup run` is used instead of the bare proxies so an existing
# `default none` configuration is preserved while the toolchain is proven usable.
function Get-PlasticineRustCommandFailure {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RustupCommand,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$CargoHome,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RustupHome
    )
    foreach ($command in $PlasticineRustVerifiedCommand) {
        $result = Invoke-PlasticineRustCommand -Path $RustupCommand `
            -Argument @('run', 'stable', $command, '--version') `
            -CargoHome $CargoHome -RustupHome $RustupHome
        if ($result.ExitCode -ne 0 -or -not ([string]$result.Output).Trim()) { return $command }
    }
    return ''
}

# MSVC Build Tools are detected only through the Visual Studio installer's
# vswhere. A link.exe on PATH is not evidence: Git for Windows ships a coreutils
# link.exe, which is exactly the wrong conclusion this route must avoid. The
# route never installs Build Tools; it only refuses an existing msvc host that
# cannot link and points at the Visual Studio installer workload.
function Test-PlasticineRustMsvcBuildTools {
    $vswhere = @()
    foreach ($rootVariable in @('ProgramFiles(x86)', 'ProgramFiles', 'ProgramW6432')) {
        $root = [Environment]::GetEnvironmentVariable($rootVariable)
        if (-not $root) { continue }
        $candidate = Join-Path $root 'Microsoft Visual Studio\Installer\vswhere.exe'
        if (($vswhere -notcontains $candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            $vswhere += $candidate
        }
    }
    foreach ($path in $vswhere) {
        $output = & $path -latest -products '*' -requires $PlasticineRustBuildToolsComponent -property installationPath 2>$null
        if ($LASTEXITCODE -eq 0 -and (($output -join '').Trim())) { return $true }
    }
    return $false
}

function Get-PlasticineRustObservation {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory)
    $destination = Get-PlasticineRustDestinations -HomeDirectory $HomeDirectory
    $parents = @($destination.HomeDirectory, $destination.LocalDirectory, $destination.OptDirectory)
    Assert-PlasticineInstallDestination -Parent $parents -Target $destination.RustupCommand
    foreach ($directory in @($destination.CargoHome, $destination.RustupHome, $destination.BinDirectory)) {
        $item = Get-PlasticineItem $directory
        if ($item -and (-not $item.PSIsContainer -or (Test-PlasticineReparsePoint $item))) {
            Stop-PlasticineRust "native home or bin must be a real directory: $directory; left untouched."
        }
    }

    # Only the managed direct pathname is an authorized rust installation. A
    # rustup resolved from PATH anywhere else belongs to another owner and is
    # never shadowed by a second copy.
    $external = Get-PlasticineCommandPath 'rustup'
    if ($external) {
        $external = [IO.Path]::GetFullPath($external)
        if ($external -ne [IO.Path]::GetFullPath($destination.RustupCommand)) {
            Stop-PlasticineRust "external rustup at $external; maintain it through its owner. No shadow installation was created."
        }
    }

    $observation = [pscustomobject]@{
        HomeDirectory    = $destination.HomeDirectory
        LocalDirectory   = $destination.LocalDirectory
        OptDirectory     = $destination.OptDirectory
        CargoHome        = $destination.CargoHome
        RustupHome       = $destination.RustupHome
        BinDirectory     = $destination.BinDirectory
        RustupCommand    = $destination.RustupCommand
        SettingsFile     = $destination.SettingsFile
        Owner            = 'missing'
        ObservedVersion  = ''
        ObservedHost     = ''
        DefaultToolchain = ''
        StableReady      = $false
        ComponentsReady  = $false
        Healthy          = $false
        MsvcDetected     = (Test-PlasticineRustMsvcBuildTools)
    }

    if (Test-Path -LiteralPath $destination.RustupCommand -PathType Leaf) {
        $observation.Owner = 'native'
        if (-not (Test-Path -LiteralPath $destination.SettingsFile -PathType Leaf)) {
            Stop-PlasticineRust "native rustup settings are missing: $($destination.SettingsFile); repair rustup before retrying."
        }
        $version = Get-PlasticineRustupVersion -RustupCommand $destination.RustupCommand `
            -CargoHome $destination.CargoHome -RustupHome $destination.RustupHome
        if (-not $version) {
            Stop-PlasticineRust "native rustup is unhealthy or not stable: $($destination.RustupCommand); repair it before retrying."
        }
        $hostTuple = Get-PlasticineRustupHost -RustupCommand $destination.RustupCommand `
            -CargoHome $destination.CargoHome -RustupHome $destination.RustupHome
        if (-not $hostTuple) {
            Stop-PlasticineRust 'could not identify the existing rustup host; repair rustup settings before retrying.'
        }
        $missingProxy = @(Get-PlasticineRustMissingProxy -CargoHome $destination.CargoHome)
        if ($missingProxy.Count -gt 0) {
            Stop-PlasticineRust ("native rustup installation is incomplete (missing " +
                ($missingProxy -join ', ') + '); repair it before retrying.')
        }
        $defaultToolchain = Get-PlasticineRustDefault -RustupCommand $destination.RustupCommand `
            -CargoHome $destination.CargoHome -RustupHome $destination.RustupHome
        if ($null -eq $defaultToolchain) {
            Stop-PlasticineRust 'could not read the existing default toolchain; repair rustup settings before retrying.'
        }
        $stableReady = Test-PlasticineRustStableToolchain -RustupCommand $destination.RustupCommand `
            -CargoHome $destination.CargoHome -RustupHome $destination.RustupHome -HostTuple $hostTuple
        $componentsReady = $false
        if ($stableReady) {
            $componentsReady = Test-PlasticineRustComponents -RustupCommand $destination.RustupCommand `
                -CargoHome $destination.CargoHome -RustupHome $destination.RustupHome
        }
        # The msvc host depends on the Visual Studio linker; a missing Build
        # Tools installation is a hard stop with guidance, never a silent host
        # switch and never an automatic Build Tools installation.
        if ($hostTuple -match 'windows-msvc$' -and -not $observation.MsvcDetected) {
            Stop-PlasticineRust ("the existing rustup uses the msvc host $hostTuple but Visual Studio Build Tools are not installed; " +
                'install the "Desktop development with C++" workload with the MSVC x64 linker, or let the owner of that rustup switch it. ' +
                'No host switch and no shadow installation was created.')
        }
        $observation.ObservedVersion = $version
        $observation.ObservedHost = $hostTuple
        $observation.DefaultToolchain = $defaultToolchain
        $observation.StableReady = $stableReady
        $observation.ComponentsReady = $componentsReady
        $observation.Healthy = ($stableReady -and $componentsReady)
        return $observation
    }

    if (Test-Path -LiteralPath $destination.SettingsFile) {
        Stop-PlasticineRust "existing rustup settings without its native executable: $($destination.SettingsFile); repair rustup before retrying."
    }
    foreach ($name in $PlasticineRustProxy) {
        if ($name -eq 'rustup') { continue }
        $proxy = Join-Path $destination.BinDirectory ($name + '.exe')
        if (Test-Path -LiteralPath $proxy) {
            Stop-PlasticineRust "existing proxy without rustup: $proxy; repair its owner. No shadow installation was created."
        }
    }
    foreach ($name in @('cargo', 'rustc')) {
        $found = Get-PlasticineCommandPath $name
        if ($found) {
            Stop-PlasticineRust "existing $name at $found without native rustup; repair its owner. No shadow installation was created."
        }
    }
    return $observation
}

function Get-PlasticineRustPlan {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory)
    $null = Assert-PlasticineAbsolutePath -Path $HomeDirectory -Name 'home directory'
    Assert-PlasticineWindowsPlatform
    $observation = Get-PlasticineRustObservation -HomeDirectory $HomeDirectory
    return [pscustomobject]@{
        DefaultHost      = $PlasticineRustDefaultHost
        Asset            = $PlasticineRustAsset
        AssetUrl         = $PlasticineRustAssetUrl
        SidecarUrl       = $PlasticineRustSidecarUrl
        Toolchain        = $PlasticineRustToolchain
        Profile          = $PlasticineRustProfile
        Component        = $PlasticineRustComponent
        HomeDirectory    = $observation.HomeDirectory
        LocalDirectory   = $observation.LocalDirectory
        OptDirectory     = $observation.OptDirectory
        CargoHome        = $observation.CargoHome
        RustupHome       = $observation.RustupHome
        BinDirectory     = $observation.BinDirectory
        RustupCommand    = $observation.RustupCommand
        Owner            = $observation.Owner
        Observed         = $(if ($observation.Owner -eq 'native') { $observation.RustupCommand } else { $null })
        ObservedVersion  = $observation.ObservedVersion
        ObservedHost     = $observation.ObservedHost
        DefaultToolchain = $observation.DefaultToolchain
        StableReady      = $observation.StableReady
        ComponentsReady  = $observation.ComponentsReady
        Healthy          = $observation.Healthy
        MsvcDetected     = $observation.MsvcDetected
        PathMissing      = ($null -ne (Resolve-PlasticineUserPathAddition -Directory $observation.BinDirectory))
    }
}

function Write-PlasticineRustPreview {
    param([Parameter(Mandatory = $true)]$Plan)
    if ($Plan.Owner -eq 'native') {
        Write-PlasticineLog ("rust: observed windows/amd64; rustup=$($Plan.ObservedVersion); owner=$($Plan.Owner); host=$($Plan.ObservedHost); default=$($Plan.DefaultToolchain).")
    } else {
        Write-PlasticineLog 'rust: observed windows/amd64; rustup=missing; owner=missing; no native homes at the managed destination.'
    }
    Write-PlasticineLog '  Fixed supported baseline: the rustup-managed stable toolchain with the minimal profile plus rustfmt and clippy; a first installation uses the reviewed official rustup-init.exe for x86_64-pc-windows-gnu.'
    Write-PlasticineLog '  An existing healthy rustup keeps its current version and host: this route never switches hosts and never downgrades.'
    Write-PlasticineLog '  network during apply: HTTPS static.rust-lang.org for rustup-init.exe and its .sha256 sidecar only when rustup is missing; the toolchain and component distribution only when stable, rustfmt or clippy need forward-only maintenance.'
    Write-PlasticineLog '  commands during apply: curl.exe download; Get-FileHash SHA-256 against the official rustup-init.exe sidecar; rustup-init.exe -y --no-modify-path --default-toolchain none --profile minimal --default-host x86_64-pc-windows-gnu; rustup toolchain install stable --profile minimal --component rustfmt --component clippy --no-self-update; rustup default maintenance; rustup run stable verification.'
    Write-PlasticineLog '  trust boundary: the unversioned upstream URL has no embeddable pinned digest, so rustup-init.exe is verified only against the official .sha256 sidecar served over the same HTTPS host; a mismatch is fatal and TLS to static.rust-lang.org is the only trust anchor.'
    Write-PlasticineLog "  native homes: CARGO_HOME=$($Plan.CargoHome); RUSTUP_HOME=$($Plan.RustupHome); targets: $($Plan.CargoHome), $($Plan.RustupHome)."
    if ($Plan.PathMissing) {
        Write-PlasticineLog "  command path: $($Plan.BinDirectory) (will be appended to the user-level PATH; the previous user PATH is backed up under $($Plan.HomeDirectory)\.plasticine\backups\user-path)."
    } else {
        Write-PlasticineLog "  command path: $($Plan.BinDirectory) (already on the user-level PATH)."
    }
    Write-PlasticineLog '  verification: rustup --version; rustup show default host; stable toolchain plus rustfmt and clippy components; rustup run stable for rustc, cargo, rustfmt and clippy-driver.'
    Write-PlasticineLog '  reuse: a managed rustup whose version, host, proxies, stable toolchain and components verify is retained without rustup-init traffic; only missing stable pieces trigger toolchain maintenance with --no-self-update.'
    Write-PlasticineLog '  refusal: external rustup/cargo/rustc owners, proxies or settings without rustup, unreadable versions/hosts/defaults, irregular targets, and an msvc host without Visual Studio Build Tools stop with guidance and no mutation.'
    if ($Plan.MsvcDetected) {
        Write-PlasticineLog '  MSVC Build Tools: detected. The PATH link.exe is never used as evidence; this route never installs Build Tools.'
    } else {
        Write-PlasticineLog '  MSVC Build Tools: not detected. A missing MSVC toolchain fails with Visual Studio guidance for an existing msvc host; the fresh-install baseline uses the gnu host. The PATH link.exe is never used as evidence and Build Tools are never installed by this route.'
    }
    if ($Plan.Owner -eq 'native') {
        if ($Plan.Healthy) {
            Write-PlasticineLog "  Observed rustup: $($Plan.RustupCommand) (rustup $($Plan.ObservedVersion), host $($Plan.ObservedHost), default $($Plan.DefaultToolchain)); the stable toolchain and components verify and will be retained."
        } else {
            Write-PlasticineLog "  Observed rustup: $($Plan.RustupCommand) (rustup $($Plan.ObservedVersion), host $($Plan.ObservedHost), default $($Plan.DefaultToolchain)); stable or its rustfmt/clippy components need forward-only maintenance. The rustup binary and host are retained."
        }
    }
    Write-PlasticineLog '  package manager: none; privilege: none; credentials: none; release API: none.'
    Write-PlasticineLog '  Standalone selection does not edit shell startup; reopen the terminal after the user-level PATH is updated.'
}

# Fresh installations are staged inside the home directory so the no-clobber
# directory publication always stays on one volume; %TEMP% may live on another.
function Remove-PlasticineRustWorkDirectory {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$WorkDirectory,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory
    )
    $parent = Split-Path -Parent $WorkDirectory
    $leaf = Split-Path -Leaf $WorkDirectory
    if (-not $parent -or -not $leaf) { return }
    if (-not $leaf.StartsWith('.plasticine-rust.')) { return }
    if ([IO.Path]::GetFullPath($parent) -ne [IO.Path]::GetFullPath($HomeDirectory)) { return }
    if (Get-PlasticineItem $WorkDirectory) {
        Remove-Item -LiteralPath $WorkDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-PlasticineRustWorkDirectory {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory)
    $work = Join-Path $HomeDirectory ('.plasticine-rust.' + [IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $work -ErrorAction Stop | Out-Null
    return $work
}

# Executes the reviewed rustup-init command against the candidate homes. The
# default implementation is the real process; tests replace the seam when the
# official installer cannot be run offline.
function Invoke-PlasticineRustInit {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RustupInit,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$CargoHome,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RustupHome
    )
    $setup = [pscustomobject]@{
        RustupInit = $RustupInit
        CargoHome  = $CargoHome
        RustupHome = $RustupHome
        Argument   = @(
            '-y',
            '--no-modify-path',
            '--default-toolchain', 'none',
            '--profile', $PlasticineRustProfile,
            '--default-host', $PlasticineRustDefaultHost
        )
    }
    if ($PlasticineRustInitRunner) {
        & $PlasticineRustInitRunner $setup
        return
    }
    $result = Invoke-PlasticineRustCommand -Path $setup.RustupInit -Argument $setup.Argument `
        -CargoHome $setup.CargoHome -RustupHome $setup.RustupHome
    if ($result.ExitCode -ne 0) {
        Stop-PlasticineRust 'rustup-init failed; the candidate directory was discarded and nothing was published.'
    }
}

# Executes the stable toolchain maintenance. `--no-self-update` keeps the
# existing rustup binary untouched and no downgrade flag is ever passed, so a
# maintenance run can only move the stable channel forward.
function Invoke-PlasticineRustToolchain {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$CargoHome,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RustupHome
    )
    $setup = [pscustomobject]@{
        RustupCommand = (Join-Path $CargoHome 'bin\rustup.exe')
        CargoHome     = $CargoHome
        RustupHome    = $RustupHome
        Toolchain     = $PlasticineRustToolchain
        Profile       = $PlasticineRustProfile
        Component     = $PlasticineRustComponent
        NoSelfUpdate  = $true
        Argument      = @(
            'toolchain', 'install', 'stable',
            '--profile', $PlasticineRustProfile,
            '--component', 'rustfmt',
            '--component', 'clippy',
            '--no-self-update'
        )
    }
    if ($PlasticineRustToolchainRunner) {
        & $PlasticineRustToolchainRunner $setup
        return
    }
    $result = Invoke-PlasticineRustCommand -Path $setup.RustupCommand -Argument $setup.Argument `
        -CargoHome $setup.CargoHome -RustupHome $setup.RustupHome
    if ($result.ExitCode -ne 0) {
        # A fresh candidate is discarded by the caller; a retained installation
        # keeps whatever the interrupted command wrote next to its existing
        # toolchains. Neither case publishes or applies configuration.
        Stop-PlasticineRust 'stable toolchain installation failed; no configuration was applied.'
    }
}

# A first installation keeps rustup's own default behaviour: stable becomes the
# default toolchain. An existing installation keeps whatever default it had,
# including an explicit `none`; rustup toolchain install may silently set a
# default, so it is restored before verification.
function Assert-PlasticineRustDefault {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RustupCommand,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$CargoHome,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RustupHome,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$SavedDefault,
        [switch]$FirstInstallation
    )
    $current = Get-PlasticineRustDefault -RustupCommand $RustupCommand -CargoHome $CargoHome -RustupHome $RustupHome
    if ($null -eq $current) {
        Stop-PlasticineRust 'could not read the default toolchain after toolchain maintenance; repair rustup settings before retrying.'
    }
    if ($FirstInstallation) {
        if ($current -eq 'none') {
            Set-PlasticineRustDefault -RustupCommand $RustupCommand -CargoHome $CargoHome -RustupHome $RustupHome -Name 'stable'
            $current = Get-PlasticineRustDefault -RustupCommand $RustupCommand -CargoHome $CargoHome -RustupHome $RustupHome
        }
        if ($null -eq $current -or $current -notmatch '^stable-') {
            Stop-PlasticineRust "the first installation did not retain stable as the default toolchain (observed $current); nothing was published."
        }
        return
    }
    if ($SavedDefault -eq 'none') {
        if ($current -ne 'none') {
            Set-PlasticineRustDefault -RustupCommand $RustupCommand -CargoHome $CargoHome -RustupHome $RustupHome -Name 'none'
            $current = Get-PlasticineRustDefault -RustupCommand $RustupCommand -CargoHome $CargoHome -RustupHome $RustupHome
        }
        if ($current -ne 'none') {
            Stop-PlasticineRust 'the existing default toolchain none could not be preserved after maintenance; repair rustup settings before retrying.'
        }
        return
    }
    if ($current -ne $SavedDefault) {
        Stop-PlasticineRust "the default toolchain changed unexpectedly from $SavedDefault to $current; inspect rustup settings before retrying."
    }
}

function Assert-PlasticineRustStableReady {
    param(
        [Parameter(Mandatory = $true)]$Observation,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ExpectedHost,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Context,
        [string]$ExpectedVersion = ''
    )
    $version = Get-PlasticineRustupVersion -RustupCommand $Observation.RustupCommand `
        -CargoHome $Observation.CargoHome -RustupHome $Observation.RustupHome
    if (-not $version) {
        Stop-PlasticineRust "$Context rustup failed verification at $($Observation.CargoHome); repair the native homes before retrying."
    }
    if ($ExpectedVersion -and $version -ne $ExpectedVersion) {
        Stop-PlasticineRust "$Context rustup version $version does not match the retained version $ExpectedVersion; configuration was not applied."
    }
    $hostTuple = Get-PlasticineRustupHost -RustupCommand $Observation.RustupCommand `
        -CargoHome $Observation.CargoHome -RustupHome $Observation.RustupHome
    if (-not $hostTuple) {
        Stop-PlasticineRust "$Context rustup host could not be verified; repair rustup settings before retrying."
    }
    if ($hostTuple -ne $ExpectedHost) {
        Stop-PlasticineRust "$Context rustup host $hostTuple does not match the expected host $ExpectedHost; configuration was not applied."
    }
    if (-not (Test-PlasticineRustStableToolchain -RustupCommand $Observation.RustupCommand `
            -CargoHome $Observation.CargoHome -RustupHome $Observation.RustupHome -HostTuple $hostTuple)) {
        Stop-PlasticineRust "$Context stable toolchain is not installed for host $hostTuple; configuration was not applied."
    }
    if (-not (Test-PlasticineRustComponents -RustupCommand $Observation.RustupCommand `
            -CargoHome $Observation.CargoHome -RustupHome $Observation.RustupHome)) {
        Stop-PlasticineRust "$Context stable toolchain is missing the reviewed rustfmt/clippy components; configuration was not applied."
    }
    $failure = Get-PlasticineRustCommandFailure -RustupCommand $Observation.RustupCommand `
        -CargoHome $Observation.CargoHome -RustupHome $Observation.RustupHome
    if ($failure) {
        Stop-PlasticineRust "$Context stable toolchain is unhealthy: 'rustup run stable $failure --version' failed; repair it before retrying."
    }
}

# The managed homes live under ~/.local/opt, so the published proxies only find
# their toolchain when CARGO_HOME/RUSTUP_HOME are user-scope variables as well.
function Assert-PlasticineRustEnvironment {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$BinDirectory,
        [string]$CargoHome,
        [string]$RustupHome
    )
    $backupDirectory = Join-Path $HomeDirectory '.plasticine\backups\user-path'
    $variables = @()
    if ($CargoHome) { $variables += @{ Name = 'CARGO_HOME'; Value = $CargoHome } }
    if ($RustupHome) { $variables += @{ Name = 'RUSTUP_HOME'; Value = $RustupHome } }
    foreach ($variable in $variables) {
        try {
            $changed = Set-PlasticineUserEnvironmentValue -Name $variable.Name -Value $variable.Value -BackupDirectory $backupDirectory
        } catch {
            Stop-PlasticineRust "the user-level $($variable.Name) could not be set; set it to $($variable.Value) manually and retry."
        }
        if ($changed) {
            Write-PlasticineLog "rust: set $($variable.Name) to $($variable.Value) for new processes."
        }
    }
    if ($null -eq (Resolve-PlasticineUserPathAddition -Directory $BinDirectory)) { return }
    try {
        $added = Add-PlasticineUserPathEntry -Directory $BinDirectory -BackupDirectory $backupDirectory
    } catch {
        Stop-PlasticineRust "the user-level PATH could not be updated; add $BinDirectory manually and retry."
    }
    if ($added) {
        Write-PlasticineLog "rust: added $BinDirectory to the user-level PATH; reopen the terminal to pick it up."
    }
}

function Assert-PlasticineRustPathEntry {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$BinDirectory,
        [string]$CargoHome,
        [string]$RustupHome
    )
    Assert-PlasticineRustEnvironment -HomeDirectory $HomeDirectory -BinDirectory $BinDirectory `
        -CargoHome $CargoHome -RustupHome $RustupHome
}

function Get-PlasticineRustSidecarDigest {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path)
    $null = Assert-PlasticineAbsolutePath -Path $Path -Name 'checksum sidecar'
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Stop-PlasticineRust 'official rustup-init.exe checksum sidecar is missing; the installer was not executed and nothing was published.'
    }
    $text = ([IO.File]::ReadAllText($Path)).Trim()
    if ($text -notmatch '^[0-9a-fA-F]{64}$') {
        Stop-PlasticineRust 'official rustup-init.exe checksum sidecar is malformed; the installer was not executed and nothing was published.'
    }
    return $text.ToLowerInvariant()
}

function Invoke-PlasticineRustPrepare {
    param([Parameter(Mandatory = $true)]$Plan)
    Assert-PlasticineWindowsPlatform

    # Re-observe at confirmed apply: the plan may be stale by the time a user
    # confirms, and every ownership and destination rule is re-checked here.
    $observation = Get-PlasticineRustObservation -HomeDirectory $Plan.HomeDirectory

    if ($observation.Owner -eq 'native' -and $observation.Healthy) {
        Assert-PlasticineRustStableCommands -Observation $observation
        Assert-PlasticineRustPathEntry -HomeDirectory $observation.HomeDirectory -BinDirectory $observation.BinDirectory -CargoHome $observation.CargoHome -RustupHome $observation.RustupHome
        Write-PlasticineLog "rust: pinned baseline is satisfied by rustup $($observation.ObservedVersion) with stable host $($observation.ObservedHost) at $($observation.RustupCommand); no rustup-init or toolchain traffic."
        return
    }

    if ($observation.Owner -eq 'native') {
        # Maintenance keeps the rustup binary and its host untouched. Only the
        # stable toolchain and its reviewed components move forward.
        $savedDefault = $observation.DefaultToolchain
        Write-PlasticineLog ("rust: maintaining the stable toolchain for the retained rustup " +
            "$($observation.ObservedVersion) (host $($observation.ObservedHost)); no host switch and no rustup reinstall.")
        Invoke-PlasticineRustToolchain -CargoHome $observation.CargoHome -RustupHome $observation.RustupHome
        Assert-PlasticineRustDefault -RustupCommand $observation.RustupCommand `
            -CargoHome $observation.CargoHome -RustupHome $observation.RustupHome -SavedDefault $savedDefault
        $refreshed = Get-PlasticineRustObservationSnapshot -CargoHome $observation.CargoHome `
            -RustupHome $observation.RustupHome -RustupCommand $observation.RustupCommand
        Assert-PlasticineRustStableReady -Observation $refreshed -ExpectedHost $observation.ObservedHost `
            -ExpectedVersion $observation.ObservedVersion -Context 'the maintained'
        Assert-PlasticineRustPathEntry -HomeDirectory $observation.HomeDirectory -BinDirectory $observation.BinDirectory -CargoHome $observation.CargoHome -RustupHome $observation.RustupHome
        Write-PlasticineLog "rust: update completed for rustup $($observation.ObservedVersion) with stable host $($observation.ObservedHost); the rustup binary was retained."
        return
    }

    $work = $null
    $workRoot = New-PlasticineRustWorkDirectory -HomeDirectory $Plan.HomeDirectory
    $work = $workRoot
    try {
        $rustupInit = Join-Path $workRoot 'rustup-init.exe'
        $sidecar = Join-Path $workRoot 'rustup-init.exe.sha256'
        Invoke-PlasticineDownload -Url $Plan.AssetUrl -Destination $rustupInit `
            -FailureMessage 'rust: official rustup-init.exe download failed; no installation was attempted and existing files were left untouched.'
        Invoke-PlasticineDownload -Url $Plan.SidecarUrl -Destination $sidecar -MaxBytes 4096 `
            -FailureMessage 'rust: official rustup-init.exe checksum sidecar download failed; no installation was attempted and existing files were left untouched.'
        $expectedDigest = Get-PlasticineRustSidecarDigest -Path $sidecar
        $observedDigest = Get-PlasticineFileHash $rustupInit
        if ($observedDigest -ne $expectedDigest) {
            Stop-PlasticineRust 'rustup-init.exe SHA-256 mismatch against the official sidecar; the installer was not executed and nothing was published.'
        }

        $candidateRoot = Join-Path $workRoot 'opt'
        $candidateCargo = Join-Path $candidateRoot '.cargo'
        $candidateRustup = Join-Path $candidateRoot '.rustup'
        Invoke-PlasticineRustInit -RustupInit $rustupInit -CargoHome $candidateCargo -RustupHome $candidateRustup

        $candidateCommand = Join-Path $candidateCargo 'bin\rustup.exe'
        $candidateVersion = Get-PlasticineRustupVersion -RustupCommand $candidateCommand `
            -CargoHome $candidateCargo -RustupHome $candidateRustup
        $candidateHost = Get-PlasticineRustupHost -RustupCommand $candidateCommand `
            -CargoHome $candidateCargo -RustupHome $candidateRustup
        $candidateMissing = @(Get-PlasticineRustMissingProxy -CargoHome $candidateCargo)
        if (-not $candidateVersion -or -not $candidateHost -or $candidateMissing.Count -gt 0) {
            Stop-PlasticineRust 'rustup-init did not produce a healthy rustup at the candidate homes; nothing was published.'
        }
        if ($candidateHost -ne $Plan.DefaultHost) {
            Stop-PlasticineRust "rustup-init reported host $candidateHost instead of the reviewed host $($Plan.DefaultHost); nothing was published."
        }
        Write-PlasticineLog "rust: rustup-init installed rustup $candidateVersion for host $candidateHost in the candidate directory; installing the stable toolchain."

        Invoke-PlasticineRustToolchain -CargoHome $candidateCargo -RustupHome $candidateRustup
        Assert-PlasticineRustDefault -RustupCommand $candidateCommand -CargoHome $candidateCargo `
            -RustupHome $candidateRustup -SavedDefault 'none' -FirstInstallation
        $candidateObservation = Get-PlasticineRustObservationSnapshot -CargoHome $candidateCargo `
            -RustupHome $candidateRustup -RustupCommand $candidateCommand
        Assert-PlasticineRustStableReady -Observation $candidateObservation -ExpectedHost $Plan.DefaultHost `
            -ExpectedVersion $candidateVersion -Context 'the candidate'

        foreach ($directory in @($Plan.LocalDirectory, $Plan.OptDirectory)) {
            if (-not (Get-PlasticineItem $directory)) {
                New-Item -ItemType Directory -Path $directory -ErrorAction Stop | Out-Null
                Set-PlasticineOwnerOnlyAcl -Path $directory
            }
        }
        Assert-PlasticineInstallDestination -Parent @($Plan.HomeDirectory, $Plan.LocalDirectory, $Plan.OptDirectory)
        if (Get-PlasticineItem $Plan.CargoHome) {
            Stop-PlasticineRust "installation target appeared during preparation; left untouched: $($Plan.CargoHome)"
        }
        if (Get-PlasticineItem $Plan.RustupHome) {
            Stop-PlasticineRust "installation target appeared during preparation; left untouched: $($Plan.RustupHome)"
        }

        Publish-PlasticineNewDirectory -Candidate $candidateCargo -Target $Plan.CargoHome
        try {
            Publish-PlasticineNewDirectory -Candidate $candidateRustup -Target $Plan.RustupHome
        } catch {
            Stop-PlasticineRust "the command directory was published at $($Plan.CargoHome) but the rustup settings could not be published at $($Plan.RustupHome); repair the retained installation before retrying."
        }

        $published = Get-PlasticineRustObservationSnapshot -CargoHome $Plan.CargoHome `
            -RustupHome $Plan.RustupHome -RustupCommand $Plan.RustupCommand
        Assert-PlasticineRustStableReady -Observation $published -ExpectedHost $Plan.DefaultHost `
            -ExpectedVersion $candidateVersion -Context 'the published'
        Assert-PlasticineRustPathEntry -HomeDirectory $Plan.HomeDirectory -BinDirectory $Plan.BinDirectory -CargoHome $Plan.CargoHome -RustupHome $Plan.RustupHome
        Write-PlasticineLog "rust: install completed with rustup $($published.Version) and stable host $($published.Host) at $($Plan.CargoHome); command path $($Plan.BinDirectory)."
    } finally {
        if ($work) { Remove-PlasticineRustWorkDirectory -WorkDirectory $work -HomeDirectory $Plan.HomeDirectory }
    }
}

# A re-observation snapshot for the verification helpers. It never re-applies
# ownership rules; ownership was decided once at the start of preparation.
function Get-PlasticineRustObservationSnapshot {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$CargoHome,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RustupHome,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RustupCommand
    )
    return [pscustomobject]@{
        CargoHome     = $CargoHome
        RustupHome    = $RustupHome
        RustupCommand = $RustupCommand
        Version       = (Get-PlasticineRustupVersion -RustupCommand $RustupCommand -CargoHome $CargoHome -RustupHome $RustupHome)
        Host          = (Get-PlasticineRustupHost -RustupCommand $RustupCommand -CargoHome $CargoHome -RustupHome $RustupHome)
    }
}

# Verifies the commands of an installation that is otherwise healthy before it
# is declared reusable. This is the only check that runs the installed binaries.
function Assert-PlasticineRustStableCommands {
    param([Parameter(Mandatory = $true)]$Observation)
    $failure = Get-PlasticineRustCommandFailure -RustupCommand $Observation.RustupCommand `
        -CargoHome $Observation.CargoHome -RustupHome $Observation.RustupHome
    if ($failure) {
        Stop-PlasticineRust "existing stable toolchain is unhealthy: 'rustup run stable $failure --version' failed; repair it before retrying."
    }
}
