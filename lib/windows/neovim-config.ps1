# Apply-time helpers for the Windows Neovim route. The Unix scripts own the
# chmod journal; Windows has no execute bits, so the equivalent work is: validate
# the managed configuration shape, snapshot changed files before chezmoi writes
# them, bridge the %LOCALAPPDATA% paths Neovim actually reads, and drive the
# plugin sync/readiness checks through the managed distribution.

if (-not (Get-Command Write-PlasticineLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'common.ps1')
}
if (-not (Get-Command Assert-PlasticineConfigFile -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'config-apply.ps1')
}
if (Get-Command Assert-PlasticineNeovimConfiguration -ErrorAction SilentlyContinue) { return }

# Kept identical to the Unix inventory; the count is part of the contract.
$PlasticineNeovimConfigFile = @(
    'init.lua',
    'lua/basic.lua',
    'lua/keybindings.lua',
    'lua/colorschema.lua',
    'lua/plugins.lua',
    'lua/plugins-config/neoscroll.lua',
    'lua/plugins-config/nvim-tree.lua',
    'lua/plugins-config/surround.lua',
    'lua/plugins-config/toggleterm.lua',
    'lua/plugins-config/lsp.lua',
    'lua/plugins-config/conform.lua',
    'lua/plugins-config/mason.lua'
)

$PlasticineNeovimLocalAppDataOverride = $null
$PlasticineNeovimRunner = $null

function Stop-PlasticineNeovimConfig {
    param([Parameter(Mandatory = $true)][string]$Message)
    Stop-Plasticine "neovim: $Message"
}

function Get-PlasticineNeovimConfigDirectory {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    return (Join-Path $HomeDirectory '.config\nvim')
}

function Get-PlasticineNeovimLocalAppDataDirectory {
    if ($PlasticineNeovimLocalAppDataOverride) { return [string]$PlasticineNeovimLocalAppDataOverride }
    if ($env:LOCALAPPDATA) { return [string]$env:LOCALAPPDATA }
    Stop-PlasticineNeovimConfig 'LOCALAPPDATA is unavailable; cannot bridge the editor configuration and data directories.'
}

function Test-PlasticineNeovimConfigUnsupportedEnvironment {
    if ($env:NVIM_APPNAME) {
        Stop-PlasticineNeovimConfig 'NVIM_APPNAME and XDG_CONFIG_HOME are unsupported; managed configuration must be ~/.config/nvim.'
    }
    if ($env:XDG_CONFIG_HOME) {
        Stop-PlasticineNeovimConfig 'NVIM_APPNAME and XDG_CONFIG_HOME are unsupported; managed configuration must be ~/.config/nvim.'
    }
}

# Validates the shape only; contents are owned by chezmoi and by the Owner.
function Assert-PlasticineNeovimConfiguration {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    $null = Assert-PlasticineAbsolutePath -Path $HomeDirectory -Name 'home directory'
    Test-PlasticineNeovimConfigUnsupportedEnvironment
    $root = Get-PlasticineNeovimConfigDirectory -HomeDirectory $HomeDirectory
    foreach ($directory in @(
            (Join-Path $HomeDirectory '.config'),
            $root,
            (Join-Path $root 'lua'),
            (Join-Path $root 'lua\plugins-config'))) {
        $null = Assert-PlasticineConfigDirectory -Path $directory -Label 'neovim'
    }
    $competing = Join-Path $root 'init.vim'
    $competingItem = Get-PlasticineItem $competing
    if ($competingItem) {
        Stop-PlasticineNeovimConfig 'competing ~/.config/nvim/init.vim entrypoint must be migrated or removed by the Owner.'
    }
    foreach ($relative in $PlasticineNeovimConfigFile) {
        $null = Assert-PlasticineConfigFile -Path (Join-Path $root ($relative -replace '/', '\')) -Label 'neovim'
    }
}

# Snapshot every changed managed file before chezmoi replaces it. The first
# backup per file wins, so a rerun never overwrites the pristine copy.
function Save-PlasticineNeovimConfigurationBackup {
    param(
        [Parameter(Mandatory = $true)][string]$HomeDirectory,
        [Parameter(Mandatory = $true)][string]$SourceDirectory
    )
    $backupDirectory = Join-Path $HomeDirectory '.plasticine\backups\neovim'
    foreach ($relative in $PlasticineNeovimConfigFile) {
        $target = Join-Path $HomeDirectory ('.config\nvim\' + ($relative -replace '/', '\'))
        $candidate = Join-Path $SourceDirectory ('dot_config\nvim\' + ($relative -replace '/', '\'))
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { continue }
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $current = Read-PlasticineConfigText $target
        $desired = Read-PlasticineConfigText $candidate
        if (Test-PlasticineConfigTextEqual $current $desired) { continue }
        $leaf = Split-Path -Leaf $target
        $null = Save-PlasticineConfigBackup -Path $target -BackupDirectory $backupDirectory -Label ('neovim-' + $leaf)
    }
}

function Invoke-PlasticineNeovimConfigurationApply {
    param(
        [Parameter(Mandatory = $true)][string]$HomeDirectory,
        [Parameter(Mandatory = $true)][string]$SourceDirectory
    )
    Assert-PlasticineNeovimConfiguration -HomeDirectory $HomeDirectory
    Save-PlasticineNeovimConfigurationBackup -HomeDirectory $HomeDirectory -SourceDirectory $SourceDirectory
}

function Test-PlasticineNeovimJunction {
    param([Parameter(Mandatory = $true)][string]$Path)
    $item = Get-PlasticineItem $Path
    if (-not $item) { return $false }
    if (-not (Test-PlasticineReparsePoint $item)) {
        Stop-PlasticineNeovimConfig "existing path is not the managed junction: $Path; left untouched."
    }
    return $true
}

function Assert-PlasticineNeovimJunctionTarget {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Target
    )
    $item = Get-PlasticineItem $Path
    if (-not $item) { return }
    if (-not (Test-PlasticineReparsePoint $item)) {
        Stop-PlasticineNeovimConfig "existing path is not the managed junction: $Path; left untouched."
    }
    $current = @($item.Target)[0]
    if (-not $current) {
        Stop-PlasticineNeovimConfig "existing junction is unreadable: $Path; left untouched."
    }
    $normalizedCurrent = ([IO.Path]::GetFullPath([string]$current)).TrimEnd('\')
    $normalizedTarget = ([IO.Path]::GetFullPath($Target)).TrimEnd('\')
    if ($normalizedCurrent -ine $normalizedTarget) {
        Stop-PlasticineNeovimConfig "existing junction points elsewhere: $Path -> $current; left untouched."
    }
}

# Neovim on Windows reads %LOCALAPPDATA%\nvim and %LOCALAPPDATA%\nvim-data. The
# managed configuration and data live under the home directory, so both paths
# are junctions owned by this route.
function Invoke-PlasticineNeovimRuntimeBridge {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    $localAppData = Get-PlasticineNeovimLocalAppDataDirectory
    $configTarget = Get-PlasticineNeovimConfigDirectory -HomeDirectory $HomeDirectory
    if (-not (Get-PlasticineItem $configTarget)) {
        Stop-PlasticineNeovimConfig "managed configuration is missing: $configTarget; apply the managed files first."
    }
    Assert-PlasticineRealDirectory $configTarget
    $dataTarget = Join-Path $HomeDirectory '.local\share\nvim'
    if (-not (Get-PlasticineItem $dataTarget)) {
        New-Item -ItemType Directory -Path $dataTarget -Force -ErrorAction Stop | Out-Null
        Set-PlasticineOwnerOnlyAcl -Path $dataTarget
    }
    Assert-PlasticineRealDirectory $dataTarget
    $bridges = @(
        [pscustomobject]@{ Link = (Join-Path $localAppData 'nvim'); Target = $configTarget },
        [pscustomobject]@{ Link = (Join-Path $localAppData 'nvim-data'); Target = $dataTarget }
    )
    foreach ($bridge in $bridges) {
        if (Test-PlasticineNeovimJunction -Path $bridge.Link) {
            Assert-PlasticineNeovimJunctionTarget -Path $bridge.Link -Target $bridge.Target
            continue
        }
        New-Item -ItemType Junction -Path $bridge.Link -Target $bridge.Target -ErrorAction Stop | Out-Null
        Write-PlasticineLog "neovim: bridged $($bridge.Link) to $($bridge.Target)."
    }
}

function Get-PlasticineNeovimCommandPath {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    $managed = Join-Path $HomeDirectory '.local\opt\neovim\bin\nvim.exe'
    if (Test-Path -LiteralPath $managed -PathType Leaf) { return $managed }
    $found = Get-PlasticineCommandPath 'nvim'
    if ($found) { return $found }
    Stop-PlasticineNeovimConfig 'installed command unavailable while preparing the editor configuration.'
}

# Both the lazy.nvim synchronization and the readiness probe run through the
# distribution binary; tests replace the runner instead of starting an editor.
function Invoke-PlasticineNeovimCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Argument
    )
    if ($PlasticineNeovimRunner) {
        return (& $PlasticineNeovimRunner -Executable $Executable -Argument $Argument)
    }
    $previousHome = $env:HOME
    $previousPrompt = $env:GIT_TERMINAL_PROMPT
    $previousPreference = $ErrorActionPreference
    $env:GIT_TERMINAL_PROMPT = '0'
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $Executable @Argument 2>&1
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($output | ForEach-Object { [string]$_ }) }
    } finally {
        $ErrorActionPreference = $previousPreference
        $env:HOME = $previousHome
        $env:GIT_TERMINAL_PROMPT = $previousPrompt
    }
}

function Invoke-PlasticineNeovimPluginSync {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    $executable = Get-PlasticineNeovimCommandPath -HomeDirectory $HomeDirectory
    $releaseSnapshot = [bool]$env:PLASTICINE_MANAGED_PLUGINS_ARCHIVE
    if ($releaseSnapshot) {
        Write-PlasticineLog 'neovim: using the verified Release plugin snapshot; no Git update during installation.'
    } else {
        Write-PlasticineLog 'neovim: updating plugins through lazy.nvim...'
        $sync = Invoke-PlasticineNeovimCommand -Executable $executable -Argument @(
            '--headless', '+Lazy! sync', '+qa'
        )
        if ($sync.ExitCode -ne 0) {
            Stop-PlasticineNeovimConfig 'native plugin synchronization or startup failed after configuration application; configuration/backups, editor publication, and completed native effects remain. Fix the reported error and retry.'
        }
    }
    $readiness = Invoke-PlasticineNeovimCommand -Executable $executable -Argument @(
        '--headless',
        '+lua local ok, err = pcall(function() assert(vim.fn.maparg("<C-n>", "n") ~= ""); assert(type(_FLOAT_TERM) == "function") end); if not ok then io.stderr:write(tostring(err) .. "\n"); vim.cmd("cquit") end',
        '+qa'
    )
    if ($readiness.ExitCode -ne 0) {
        Stop-PlasticineNeovimConfig 'runtime readiness check failed after plugin synchronization; retry after correcting the reported configuration/plugin error.'
    }
    Write-PlasticineLog 'neovim: complete distribution, managed configuration, and current plugins passed runtime readiness.'
}

function Invoke-PlasticineNeovimRuntimePreparation {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    Invoke-PlasticineNeovimRuntimeBridge -HomeDirectory $HomeDirectory
    Invoke-PlasticineNeovimPluginSync -HomeDirectory $HomeDirectory
}
