# Interactive defaults; later Owner code in the PowerShell profile can override
# them. Runtime only: fnm owns its native per-shell session data, and this
# fragment never edits PATH persistently and never enables directory switching.
# Optional tools stay silent when absent, and a failing fnm is never evaluated.

if (-not (Get-Variable -Name _plasticine_powershell_environment_loaded -Scope Global -ErrorAction SilentlyContinue)) {
    $plasticineEnvironmentFragment = Join-Path $HOME '.plasticine\powershell\environment.ps1'
    if (Test-Path -LiteralPath $plasticineEnvironmentFragment -PathType Leaf) {
        . $plasticineEnvironmentFragment
    } else {
        # Match the base fragment without requiring it: keep ~/.local/bin first.
        $plasticineLocalBin = (Join-Path $HOME '.local\bin').TrimEnd('\')
        $plasticineEnvironmentPath = @(([string]$env:PATH) -split ';')
        $plasticineLocalBinPresent = $false
        foreach ($plasticineEnvironmentEntry in $plasticineEnvironmentPath) {
            if ($plasticineEnvironmentEntry.Trim().Trim('"').TrimEnd('\') -eq $plasticineLocalBin) {
                $plasticineLocalBinPresent = $true
                break
            }
        }
        if (-not $plasticineLocalBinPresent) {
            $env:PATH = (Join-Path $HOME '.local\bin') + ';' + [string]$env:PATH
        }
    }
    Remove-Variable -Name plasticineEnvironmentFragment, plasticineLocalBin,
        plasticineEnvironmentPath, plasticineLocalBinPresent, plasticineEnvironmentEntry `
        -ErrorAction SilentlyContinue
}

# The profile also runs for -Command/-File/-NonInteractive invocations. Skip the
# native prompt defaults there so scripted hosts stay fast and quiet.
$plasticineInteractive = $true
$plasticineCommandLine = @([Environment]::GetCommandLineArgs())
for ($plasticineIndex = 1; $plasticineIndex -lt $plasticineCommandLine.Length; $plasticineIndex++) {
    $plasticineArgument = [string]$plasticineCommandLine[$plasticineIndex]
    if ($plasticineArgument -match '^-(command|c|file|f|encodedcommand|e|ec|noninteractive)$') {
        $plasticineInteractive = $false
    }
}

if ($plasticineInteractive) {
    # fnm is an optional Feature: stay silent when absent, never evaluate output
    # from a failing command, and keep fnm's own directory-change switching off.
    $plasticineFnm = Get-Command -Name fnm -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($plasticineFnm) {
        $plasticineFnmEnvironment = & $plasticineFnm.Source env --shell powershell 2>$null
        if ($LASTEXITCODE -eq 0 -and $plasticineFnmEnvironment) {
            Invoke-Expression (@($plasticineFnmEnvironment) -join [Environment]::NewLine)
        } else {
            [Console]::Error.WriteLine('plasticine: fnm activation unavailable; continuing shell startup')
        }
    }
    Set-Alias -Name lg -Value lazygit -Scope Global -ErrorAction SilentlyContinue
}

Remove-Variable -Name plasticineInteractive, plasticineCommandLine, plasticineIndex,
    plasticineArgument, plasticineFnm, plasticineFnmEnvironment -ErrorAction SilentlyContinue
