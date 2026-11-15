# Base environment for every PowerShell host. Use no subprocesses, no output and
# no fnm session creation. Owner code after the startup block can override it.
# The powershell Feature sources this fragment from $PROFILE.CurrentUserAllHosts;
# sourcing it more than once is harmless because entries are de-duplicated.

$plasticineEnvironmentDirectories = @((Join-Path $HOME '.local\bin'))
$plasticineCargoHome = [string]$env:CARGO_HOME
if (-not $plasticineCargoHome) { $plasticineCargoHome = Join-Path $HOME '.cargo' }
if ([IO.Path]::IsPathRooted($plasticineCargoHome)) {
    $plasticineCargoBin = Join-Path $plasticineCargoHome 'bin'
    if (Test-Path -LiteralPath $plasticineCargoBin -PathType Container) {
        $plasticineEnvironmentDirectories += $plasticineCargoBin
    }
}

$plasticineEnvironmentPath = @(([string]$env:PATH) -split ';')
$plasticineEnvironmentMissing = @()
foreach ($plasticineEnvironmentDirectory in $plasticineEnvironmentDirectories) {
    $plasticineEnvironmentWanted = $plasticineEnvironmentDirectory.TrimEnd('\')
    $plasticineEnvironmentPresent = $false
    foreach ($plasticineEnvironmentEntry in $plasticineEnvironmentPath) {
        if ($plasticineEnvironmentEntry.Trim().Trim('"').TrimEnd('\') -eq $plasticineEnvironmentWanted) {
            $plasticineEnvironmentPresent = $true
            break
        }
    }
    if (-not $plasticineEnvironmentPresent) {
        $plasticineEnvironmentMissing += $plasticineEnvironmentDirectory
    }
}
if ($plasticineEnvironmentMissing.Count -gt 0) {
    $env:PATH = (@($plasticineEnvironmentMissing) + $plasticineEnvironmentPath) -join ';'
}

# Marked through a global variable (not $env:) so child processes see no trace.
$global:_plasticine_powershell_environment_loaded = $true
Remove-Variable -Name plasticineEnvironmentDirectories, plasticineCargoHome, plasticineCargoBin,
    plasticineEnvironmentPath, plasticineEnvironmentMissing, plasticineEnvironmentDirectory,
    plasticineEnvironmentWanted, plasticineEnvironmentPresent, plasticineEnvironmentEntry `
    -ErrorAction SilentlyContinue
