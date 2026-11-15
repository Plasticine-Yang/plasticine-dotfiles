# Coverage for the Windows Neovim apply side: configuration shape validation,
# pre-apply backups, the %LOCALAPPDATA% junctions Neovim needs, and the plugin
# sync/readiness flow. No editor process, no real LOCALAPPDATA, no network.

$repoDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'harness.ps1')
$PlasticineTestName = 'windows neovim config'
. (Join-Path $repoDir 'lib\windows\common.ps1')
. (Join-Path $repoDir 'lib\windows\acl.ps1')
. (Join-Path $repoDir 'lib\windows\config-apply.ps1')
. (Join-Path $repoDir 'lib\windows\neovim-config.ps1')

$savedPath = $env:PATH
$savedAppName = $env:NVIM_APPNAME
$savedXdg = $env:XDG_CONFIG_HOME
$savedSnapshot = $env:PLASTICINE_MANAGED_PLUGINS_ARCHIVE
$localAppData = New-TestDirectory 'local-appdata'
$emptyPath = New-TestDirectory 'empty-path'

function New-ConfigHome {
    param([Parameter(Mandatory = $true)][string]$Name)
    $caseHome = Join-Path (New-TestDirectory $Name) 'home'
    foreach ($relative in @('.config', '.config\nvim', '.config\nvim\lua', '.config\nvim\lua\plugins-config')) {
        New-Item -ItemType Directory -Path (Join-Path $caseHome $relative) -Force | Out-Null
    }
    return $caseHome
}

function New-SourceDirectory {
    param([Parameter(Mandatory = $true)][string]$Name)
    $source = Join-Path (New-TestDirectory $Name) 'source'
    foreach ($relative in @('dot_config\nvim', 'dot_config\nvim\lua', 'dot_config\nvim\lua\plugins-config')) {
        New-Item -ItemType Directory -Path (Join-Path $source $relative) -Force | Out-Null
    }
    foreach ($relative in $PlasticineNeovimConfigFile) {
        $path = Join-Path $source ('dot_config\nvim\' + ($relative -replace '/', '\'))
        Set-Content -LiteralPath $path -Value ('-- ' + $relative) -NoNewline
    }
    return $source
}

function Set-ManagedConfiguration {
    param(
        [Parameter(Mandatory = $true)][string]$HomeDirectory,
        [Parameter(Mandatory = $true)][string]$SourceDirectory
    )
    foreach ($relative in $PlasticineNeovimConfigFile) {
        $target = Join-Path $HomeDirectory ('.config\nvim\' + ($relative -replace '/', '\'))
        $candidate = Join-Path $SourceDirectory ('dot_config\nvim\' + ($relative -replace '/', '\'))
        Copy-Item -LiteralPath $candidate -Destination $target -Force
    }
}

function Get-BackupPath {
    param([string]$HomeDirectory, [string]$Leaf)
    return (Join-Path $HomeDirectory ('.plasticine\backups\neovim\neovim-' + $Leaf + '.plasticine-backup'))
}

try {
    $env:PATH = $emptyPath

    # --- A well-formed home validates without touching anything. ---
    $caseHome = New-ConfigHome 'validate'
    $source = New-SourceDirectory 'validate-source'
    Set-ManagedConfiguration -HomeDirectory $caseHome -SourceDirectory $source
    $run = Invoke-TestCapture { Assert-PlasticineNeovimConfiguration -HomeDirectory $caseHome }
    Assert-True (-not $run.Threw) "the well-formed configuration was rejected: $($run.Message)"

    # --- Shape violations stop with the documented messages. ---
    $caseHome = New-ConfigHome 'competing'
    Set-Content -LiteralPath (Join-Path $caseHome '.config\nvim\init.vim') -Value 'set number' -NoNewline
    $run = Invoke-TestCapture { Assert-PlasticineNeovimConfiguration -HomeDirectory $caseHome }
    Assert-True $run.Threw 'a competing init.vim was accepted'
    Assert-True ($run.Error -match 'competing ~/.config/nvim/init.vim') 'the competing entrypoint was not reported'

    $caseHome = New-ConfigHome 'irregular'
    Remove-Item -LiteralPath (Join-Path $caseHome '.config\nvim') -Recurse -Force
    Set-Content -LiteralPath (Join-Path $caseHome '.config\nvim') -Value 'not a directory' -NoNewline
    $run = Invoke-TestCapture { Assert-PlasticineNeovimConfiguration -HomeDirectory $caseHome }
    Assert-True $run.Threw 'a file configuration directory was accepted'
    Assert-True ($run.Error -match 'must be a regular directory') 'the irregular directory was not reported'

    $caseHome = New-ConfigHome 'unsupported-env'
    $env:NVIM_APPNAME = 'other'
    $run = Invoke-TestCapture { Assert-PlasticineNeovimConfiguration -HomeDirectory $caseHome }
    Remove-Item Env:\NVIM_APPNAME -ErrorAction SilentlyContinue
    Assert-True $run.Threw 'NVIM_APPNAME was accepted'
    Assert-True ($run.Error -match 'NVIM_APPNAME and XDG_CONFIG_HOME are unsupported') 'the unsupported environment was not reported'

    # --- Backups snapshot changed files and keep the first copy. ---
    $caseHome = New-ConfigHome 'backup'
    $source = New-SourceDirectory 'backup-source'
    New-Item -ItemType Directory -Path (Join-Path $caseHome '.plasticine') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $caseHome '.config\nvim\init.lua') -Value '-- owner copy' -NoNewline
    Set-ManagedConfiguration -HomeDirectory $caseHome -SourceDirectory $source
    Set-Content -LiteralPath (Join-Path $caseHome '.config\nvim\init.lua') -Value '-- owner copy' -NoNewline
    $run = Invoke-TestCapture { Invoke-PlasticineNeovimConfigurationApply -HomeDirectory $caseHome -SourceDirectory $source }
    Assert-True (-not $run.Threw) "the configuration apply failed: $($run.Message)"
    $backup = Get-BackupPath -HomeDirectory $caseHome -Leaf 'init.lua'
    Assert-True (Test-Path -LiteralPath $backup -PathType Leaf) 'the changed managed file was not backed up'
    Assert-Equal '-- owner copy' (Get-Content -LiteralPath $backup -Raw) 'the backup does not hold the previous bytes'
    Assert-Equal 0 (@(Get-ChildItem -LiteralPath (Join-Path $caseHome '.plasticine\backups\neovim') -Force -Filter 'neovim-basic.lua*').Count) `
        'an unchanged managed file was backed up'
    $acl = (Get-Acl -LiteralPath (Join-Path $caseHome '.plasticine\backups\neovim')).Sddl
    Assert-True ($acl -match 'D:PAI') "the backup directory is not owner-only: $acl"
    Set-Content -LiteralPath (Join-Path $caseHome '.config\nvim\init.lua') -Value '-- second owner copy' -NoNewline
    $null = Invoke-TestCapture { Invoke-PlasticineNeovimConfigurationApply -HomeDirectory $caseHome -SourceDirectory $source }
    Assert-Equal '-- owner copy' (Get-Content -LiteralPath $backup -Raw) 'the first backup was overwritten'

    # --- The LOCALAPPDATA bridges point at the managed directories. ---
    $script:PlasticineNeovimLocalAppDataOverride = $localAppData
    $caseHome = New-ConfigHome 'bridge'
    $source = New-SourceDirectory 'bridge-source'
    Set-ManagedConfiguration -HomeDirectory $caseHome -SourceDirectory $source
    $run = Invoke-TestCapture { Invoke-PlasticineNeovimRuntimeBridge -HomeDirectory $caseHome }
    Assert-True (-not $run.Threw) "the runtime bridge failed: $($run.Message)"
    $configLink = Join-Path $localAppData 'nvim'
    $dataLink = Join-Path $localAppData 'nvim-data'
    Assert-True ((Get-Item $configLink).LinkType -eq 'Junction') 'the configuration bridge is not a junction'
    Assert-True ((Get-Item $dataLink).LinkType -eq 'Junction') 'the data bridge is not a junction'
    Assert-Equal (Join-Path $caseHome '.config\nvim') (([string](Get-Item $configLink).Target).TrimEnd('\')) 'the configuration bridge target drifted'
    Assert-Equal (Join-Path $caseHome '.local\share\nvim') (([string](Get-Item $dataLink).Target).TrimEnd('\')) 'the data bridge target drifted'
    $dataAcl = (Get-Acl -LiteralPath (Join-Path $caseHome '.local\share\nvim')).Sddl
    Assert-True ($dataAcl -match 'D:PAI') "the data directory is not owner-only: $dataAcl"
    $run = Invoke-TestCapture { Invoke-PlasticineNeovimRuntimeBridge -HomeDirectory $caseHome }
    Assert-True (-not $run.Threw) "the repeated runtime bridge failed: $($run.Message)"

    $foreignLink = New-TestDirectory 'foreign-local-appdata'
    New-Item -ItemType Directory -Path (Join-Path $foreignLink 'nvim') -Force | Out-Null
    $script:PlasticineNeovimLocalAppDataOverride = $foreignLink
    $run = Invoke-TestCapture { Invoke-PlasticineNeovimRuntimeBridge -HomeDirectory $caseHome }
    Assert-True $run.Threw 'a real directory at the bridge path was accepted'
    Assert-True ($run.Error -match 'existing path is not the managed junction') 'the foreign bridge path was not reported'
    $script:PlasticineNeovimLocalAppDataOverride = $localAppData

    # --- Plugin sync and readiness run through the injected runner. ---
    $caseHome = New-ConfigHome 'sync'
    $command = Join-Path $caseHome '.local\opt\neovim\bin\nvim.exe'
    New-Item -ItemType Directory -Path (Split-Path -Parent $command) -Force | Out-Null
    Set-Content -LiteralPath $command -Value 'stub' -NoNewline
    $script:PlasticineNeovimCalls = New-Object System.Collections.ArrayList
    $script:PlasticineNeovimRunner = {
        param($Executable, $Argument)
        [void]$script:PlasticineNeovimCalls.Add(($Argument -join ' '))
        if ($env:PLASTICINE_TEST_SYNC_FAIL -and ($Argument -join ' ') -match 'Lazy! sync') {
            return [pscustomobject]@{ ExitCode = 1; Output = @() }
        }
        if ($env:PLASTICINE_TEST_READINESS_FAIL -and ($Argument -join ' ') -match 'pcall') {
            return [pscustomobject]@{ ExitCode = 1; Output = @() }
        }
        return [pscustomobject]@{ ExitCode = 0; Output = @() }
    }
    $run = Invoke-TestCapture { Invoke-PlasticineNeovimPluginSync -HomeDirectory $caseHome }
    Assert-True (-not $run.Threw) "the plugin sync failed: $($run.Message)"
    Assert-Equal 2 $script:PlasticineNeovimCalls.Count 'the sync flow did not run both stages'
    Assert-True ($run.Output -match 'updating plugins through lazy.nvim') 'the plugin update was not reported'

    $env:PLASTICINE_TEST_SYNC_FAIL = '1'
    $run = Invoke-TestCapture { Invoke-PlasticineNeovimPluginSync -HomeDirectory $caseHome }
    Remove-Item Env:\PLASTICINE_TEST_SYNC_FAIL -ErrorAction SilentlyContinue
    Assert-True $run.Threw 'a failed plugin sync reported success'
    Assert-True ($run.Error -match 'native plugin synchronization or startup failed') 'the plugin sync failure was not reported'

    $env:PLASTICINE_TEST_READINESS_FAIL = '1'
    $run = Invoke-TestCapture { Invoke-PlasticineNeovimPluginSync -HomeDirectory $caseHome }
    Remove-Item Env:\PLASTICINE_TEST_READINESS_FAIL -ErrorAction SilentlyContinue
    Assert-True $run.Threw 'a failed readiness probe reported success'
    Assert-True ($run.Error -match 'runtime readiness check failed') 'the readiness failure was not reported'

    # --- A release snapshot skips Git synchronization but still probes readiness. ---
    $script:PlasticineNeovimCalls.Clear()
    $env:PLASTICINE_MANAGED_PLUGINS_ARCHIVE = 'release-snapshot'
    $run = Invoke-TestCapture { Invoke-PlasticineNeovimPluginSync -HomeDirectory $caseHome }
    Remove-Item Env:\PLASTICINE_MANAGED_PLUGINS_ARCHIVE -ErrorAction SilentlyContinue
    Assert-True (-not $run.Threw) "the release snapshot flow failed: $($run.Message)"
    Assert-Equal 1 $script:PlasticineNeovimCalls.Count 'the release snapshot still synchronized through Git'
    Assert-True ($run.Output -match 'verified Release plugin snapshot') 'the release snapshot was not reported'

    Complete-Test 'windows neovim config tests passed'
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
} finally {
    $env:PATH = $savedPath
    if ($null -eq $savedAppName) { Remove-Item Env:\NVIM_APPNAME -ErrorAction SilentlyContinue } else { $env:NVIM_APPNAME = $savedAppName }
    if ($null -eq $savedXdg) { Remove-Item Env:\XDG_CONFIG_HOME -ErrorAction SilentlyContinue } else { $env:XDG_CONFIG_HOME = $savedXdg }
    if ($null -eq $savedSnapshot) { Remove-Item Env:\PLASTICINE_MANAGED_PLUGINS_ARCHIVE -ErrorAction SilentlyContinue } else { $env:PLASTICINE_MANAGED_PLUGINS_ARCHIVE = $savedSnapshot }
    $script:PlasticineNeovimRunner = $null
    $script:PlasticineNeovimLocalAppDataOverride = $null
    Remove-Item -LiteralPath $PlasticineTestRoot -Recurse -Force -ErrorAction SilentlyContinue
}
