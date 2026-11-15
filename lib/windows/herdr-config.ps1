# Apply-time helpers for the Windows herdr route. Windows keeps the herdr
# configuration in %APPDATA%\herdr\config.toml (not ~/.config/herdr), so the file
# is composed and published by this route instead of chezmoi. Only the [terminal]
# policy is managed; every other byte of the Owner's file survives.

if (-not (Get-Command Write-PlasticineLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'common.ps1')
}
if (-not (Get-Command Assert-PlasticineConfigFile -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'config-apply.ps1')
}
if (Get-Command Get-PlasticineHerdrConfigPath -ErrorAction SilentlyContinue) { return }

$PlasticineHerdrAppDataOverride = $null
$PlasticineHerdrShellCommandOverride = $null
$PlasticineHerdrRunner = $null

function Stop-PlasticineHerdrConfig {
    param([Parameter(Mandatory = $true)][string]$Message)
    Stop-Plasticine "herdr: $Message"
}

function Get-PlasticineHerdrAppDataDirectory {
    if ($PlasticineHerdrAppDataOverride) { return [string]$PlasticineHerdrAppDataOverride }
    if ($env:APPDATA) { return [string]$env:APPDATA }
    Stop-PlasticineHerdrConfig 'APPDATA is unavailable; cannot locate the herdr configuration directory.'
}

function Get-PlasticineHerdrConfigDirectory {
    return (Join-Path (Get-PlasticineHerdrAppDataDirectory) 'herdr')
}

function Get-PlasticineHerdrConfigPath {
    return (Join-Path (Get-PlasticineHerdrConfigDirectory) 'config.toml')
}

function Get-PlasticineHerdrBackupDirectory {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    return (Join-Path $HomeDirectory '.plasticine\backups\herdr')
}

# Windows PowerShell is the baseline; pwsh is used when installed. The value is
# resolved to an executable name rather than an absolute path so the file stays
# portable and herdr resolves it the same way its own documentation does.
function Get-PlasticineHerdrDefaultShell {
    if ($PlasticineHerdrShellCommandOverride) { return [string]$PlasticineHerdrShellCommandOverride }
    if (Get-PlasticineCommandPath 'pwsh.exe') { return 'pwsh.exe' }
    if (Get-PlasticineCommandPath 'powershell.exe') { return 'powershell.exe' }
    Stop-PlasticineHerdrConfig 'PowerShell is unavailable; cannot select a default shell for herdr.'
}

function ConvertTo-PlasticineHerdrTomlString {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
    return '"' + ($Value -replace '\\', '\\\\' -replace '"', '\"') + '"'
}

# Ports the Unix compose awk script: replace the managed policy inside every
# [terminal] section, keep the Owner's other lines byte for byte, and append the
# section when the file has none.
function New-PlasticineHerdrConfigCandidate {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$DefaultShell
    )
    $policy = @(
        ('default_shell = ' + (ConvertTo-PlasticineHerdrTomlString $DefaultShell)),
        'shell_mode = "non_login"'
    )
    $parts = [regex]::Split($Text, '(\r\n|\n|\r)')
    $insertedSeparator = "`n"
    if ($parts.Count -gt 1) {
        $firstSeparator = $parts[1]
        if ($firstSeparator -eq "`r`n") { $insertedSeparator = "`r`n" }
        elseif ($firstSeparator -eq "`r") { $insertedSeparator = "`r`n" }
        elseif ($firstSeparator -eq "`n") { $insertedSeparator = "`n" }
    } elseif ($Text -match "`r") {
        $insertedSeparator = "`r`n"
    }
    $output = New-Object Text.StringBuilder
    $inTerminal = $false
    $terminalSections = 0
    $index = 0
    while ($index -lt $parts.Count) {
        $line = $parts[$index]
        $separator = ''
        if ($index + 1 -lt $parts.Count) { $separator = $parts[$index + 1] }
        $bare = $line
        $isTerminalHeader = $bare -match '^[ \t]*\[[ \t]*terminal[ \t]*\][ \t]*(#.*)?$'
        $isOtherSection = (-not $isTerminalHeader) -and ($bare -match '^[ \t]*\[')
        if ($isTerminalHeader) {
            $terminalSections++
            $inTerminal = $true
            [void]$output.Append($bare).Append($separator)
            foreach ($policyLine in $policy) {
                [void]$output.Append($policyLine).Append($insertedSeparator)
            }
        } elseif ($isOtherSection) {
            $inTerminal = $false
            [void]$output.Append($bare).Append($separator)
        } elseif ($inTerminal -and ($bare -match '^[ \t]*(default_shell|"default_shell")[ \t]*=')) {
            # replaced by the composed policy above
        } elseif ($inTerminal -and ($bare -match '^[ \t]*(shell_mode|"shell_mode")[ \t]*=')) {
            # replaced by the composed policy above
        } else {
            [void]$output.Append($bare).Append($separator)
        }
        $index += 2
    }
    if ($terminalSections -eq 0) {
        if ($Text.Length -gt 0 -and -not ($Text -match '(\r\n|\n|\r)$')) {
            [void]$output.Append($insertedSeparator)
        }
        if ($Text.Length -gt 0) { [void]$output.Append($insertedSeparator) }
        [void]$output.Append('[terminal]').Append($insertedSeparator)
        foreach ($policyLine in $policy) {
            [void]$output.Append($policyLine).Append($insertedSeparator)
        }
    }
    return $output.ToString()
}

function Assert-PlasticineHerdrConfiguration {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    $null = Assert-PlasticineAbsolutePath -Path $HomeDirectory -Name 'home directory'
    $configDirectory = Get-PlasticineHerdrConfigDirectory
    $null = Assert-PlasticineConfigDirectory -Path $configDirectory -Label 'herdr'
    $null = Assert-PlasticineConfigFile -Path (Get-PlasticineHerdrConfigPath) -Label 'herdr'
    foreach ($directory in @(
            (Join-Path $HomeDirectory '.plasticine'),
            (Join-Path $HomeDirectory '.plasticine\backups'),
            (Get-PlasticineHerdrBackupDirectory -HomeDirectory $HomeDirectory))) {
        $null = Assert-PlasticineConfigDirectory -Path $directory -Label 'herdr'
    }
}

function Resolve-PlasticineHerdrCommand {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    $found = Get-PlasticineCommandPath 'herdr'
    if ($found) { return $found }
    $managed = Join-Path $HomeDirectory '.local\bin\herdr.exe'
    if (Test-Path -LiteralPath $managed -PathType Leaf) { return $managed }
    Stop-PlasticineHerdrConfig 'installed command unavailable while validating configuration.'
}

function Invoke-PlasticineHerdrCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Argument,
        [hashtable]$Environment = @{}
    )
    if ($PlasticineHerdrRunner) {
        return (& $PlasticineHerdrRunner -Executable $Executable -Argument $Argument -Environment $Environment)
    }
    $previous = @{}
    foreach ($name in $Environment.Keys) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, [string]$Environment[$name], 'Process')
    }
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $Executable @Argument 2>&1
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($output | ForEach-Object { [string]$_ }) }
    } finally {
        $ErrorActionPreference = $previousPreference
        foreach ($name in $previous.Keys) {
            [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
        }
    }
}

function Invoke-PlasticineHerdrConfigApply {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    Assert-PlasticineHerdrConfiguration -HomeDirectory $HomeDirectory
    $configPath = Get-PlasticineHerdrConfigPath
    $current = Read-PlasticineConfigText $configPath
    $shell = Get-PlasticineHerdrDefaultShell
    $candidate = New-PlasticineHerdrConfigCandidate -Text $current -DefaultShell $shell
    if (Test-PlasticineConfigTextEqual $candidate $current) { return }
    $command = Resolve-PlasticineHerdrCommand -HomeDirectory $HomeDirectory
    $work = New-PlasticineTempDirectory 'plasticine-herdr-config'
    try {
        $candidatePath = Join-Path $work 'config.toml'
        [IO.File]::WriteAllText($candidatePath, $candidate, (Get-PlasticineLatin1Encoding))
        $check = Invoke-PlasticineHerdrCommand -Executable $command -Argument @('config', 'check') `
            -Environment @{ HERDR_CONFIG_PATH = $candidatePath }
        if ($check.ExitCode -ne 0) {
            Stop-PlasticineHerdrConfig 'candidate config is invalid; existing config left untouched.'
        }
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
    $backupDirectory = Get-PlasticineHerdrBackupDirectory -HomeDirectory $HomeDirectory
    if (-not (Get-PlasticineItem $backupDirectory)) {
        # The reload marker lives here too, so the directory exists even for a
        # first-time configuration where there is nothing to back up.
        New-Item -ItemType Directory -Path $backupDirectory -Force -ErrorAction Stop | Out-Null
        Set-PlasticineOwnerOnlyAcl -Path $backupDirectory
    }
    $null = Publish-PlasticineConfigFile -Path $configPath -Text $candidate -Label 'herdr' `
        -BackupDirectory $backupDirectory -OriginalText $current
    $marker = Join-Path $backupDirectory 'reload-pending'
    Set-Content -LiteralPath $marker -Value '' -NoNewline
    Write-PlasticineLog "herdr: composed the [terminal] policy in $configPath (default_shell = $shell, shell_mode = non_login)."
}

function Invoke-PlasticineHerdrConfigReload {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    $marker = Join-Path (Get-PlasticineHerdrBackupDirectory -HomeDirectory $HomeDirectory) 'reload-pending'
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) { return }
    $command = Resolve-PlasticineHerdrCommand -HomeDirectory $HomeDirectory
    $status = Invoke-PlasticineHerdrCommand -Executable $command -Argument @('status', 'server')
    if ($status.ExitCode -eq 0) {
        $reload = Invoke-PlasticineHerdrCommand -Executable $command -Argument @('server', 'reload-config')
        if ($reload.ExitCode -ne 0) {
            Stop-PlasticineHerdrConfig 'running server could not reload configuration; retry chezmoi apply.'
        }
    }
    Remove-Item -LiteralPath $marker -Force
    Write-PlasticineLog 'herdr: configuration reload step finished.'
}
