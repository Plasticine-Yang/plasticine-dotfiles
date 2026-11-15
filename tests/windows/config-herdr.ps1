# Coverage for the Windows herdr apply side: [terminal] policy composition, the
# candidate check through the installed herdr, backups, and the reload marker.
# No real %APPDATA%, no herdr process, no network.

$repoDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'harness.ps1')
$PlasticineTestName = 'windows herdr config'
. (Join-Path $repoDir 'lib\windows\common.ps1')
. (Join-Path $repoDir 'lib\windows\acl.ps1')
. (Join-Path $repoDir 'lib\windows\config-apply.ps1')
. (Join-Path $repoDir 'lib\windows\herdr-config.ps1')

$appData = New-TestDirectory 'appdata'
$script:PlasticineHerdrAppDataOverride = $appData
$script:PlasticineHerdrShellCommandOverride = 'pwsh.exe'
$script:PlasticineHerdrCalls = New-Object System.Collections.ArrayList
$script:PlasticineHerdrEnvironments = New-Object System.Collections.ArrayList
$script:PlasticineHerdrRunner = {
    param($Executable, $Argument, $Environment)
    [void]$script:PlasticineHerdrCalls.Add(($Argument -join ' '))
    [void]$script:PlasticineHerdrEnvironments.Add($Environment)
    if ($env:PLASTICINE_TEST_CHECK_FAIL -and ($Argument -join ' ') -match 'config check') {
        return [pscustomobject]@{ ExitCode = 1; Output = @('invalid') }
    }
    if ($env:PLASTICINE_TEST_SERVER_STOPPED -and ($Argument -join ' ') -match 'status server') {
        return [pscustomobject]@{ ExitCode = 1; Output = @() }
    }
    if ($env:PLASTICINE_TEST_RELOAD_FAIL -and ($Argument -join ' ') -match 'reload-config') {
        return [pscustomobject]@{ ExitCode = 1; Output = @() }
    }
    return [pscustomobject]@{ ExitCode = 0; Output = @() }
}

function New-HerdrHome {
    param([Parameter(Mandatory = $true)][string]$Name)
    $caseHome = Join-Path (New-TestDirectory $Name) 'home'
    New-Item -ItemType Directory -Path $caseHome -Force | Out-Null
    $bin = Join-Path $caseHome '.local\bin'
    New-Item -ItemType Directory -Path $bin -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $bin 'herdr.exe') -Value 'stub' -NoNewline
    return $caseHome
}

function Get-ConfigPath { return (Join-Path $appData 'herdr\config.toml') }
function Get-BackupPath { param([string]$CaseHome) return (Join-Path $CaseHome '.plasticine\backups\herdr\herdr.plasticine-backup') }
function Get-ReloadMarker { param([string]$CaseHome) return (Join-Path $CaseHome '.plasticine\backups\herdr\reload-pending') }

try {
    # --- Empty input gains exactly one [terminal] policy. ---
    $candidate = New-PlasticineHerdrConfigCandidate -Text '' -DefaultShell 'pwsh.exe'
    Assert-Equal "[terminal]`ndefault_shell = `"pwsh.exe`"`nshell_mode = `"non_login`"`n" $candidate `
        'an empty configuration did not gain the managed policy'

    # --- An Owner file without a section keeps every byte and appends one. ---
    $candidate = New-PlasticineHerdrConfigCandidate -Text "font_size = 12`n" -DefaultShell 'pwsh.exe'
    Assert-True ($candidate.StartsWith("font_size = 12`n`n[terminal]`n")) 'the Owner bytes were not preserved'
    Assert-True ($candidate.EndsWith("default_shell = `"pwsh.exe`"`nshell_mode = `"non_login`"`n")) `
        'the appended policy is incomplete'

    # --- Existing keys inside [terminal] are replaced, not duplicated. ---
    $existing = "[terminal]`ndefault_shell = `"/bin/zsh`"`nshell_mode = `"login`"`nscrollback = 1000`n[other]`ndefault_shell = `"keep`"`n"
    $candidate = New-PlasticineHerdrConfigCandidate -Text $existing -DefaultShell 'powershell.exe'
    Assert-True ($candidate -match 'default_shell = "powershell\.exe"') 'the managed default shell was not replaced'
    Assert-Equal 1 ([regex]::Matches($candidate, 'default_shell = "powershell.exe"')).Count 'the managed default shell was duplicated'
    Assert-Equal 1 ([regex]::Matches($candidate, 'shell_mode = "non_login"')).Count 'the managed shell mode was duplicated'
    Assert-True ($candidate -match 'scrollback = 1000') 'an Owner key inside [terminal] was dropped'
    Assert-True ($candidate -match '\[other\]\ndefault_shell = "keep"') 'a policy inside another section was changed'

    # --- CRLF files keep CRLF for inserted lines. ---
    $candidate = New-PlasticineHerdrConfigCandidate -Text "tab_width = 4`r`n" -DefaultShell 'pwsh.exe'
    Assert-True ($candidate.Contains("[terminal]`r`ndefault_shell")) 'the inserted policy did not use CRLF'
    Assert-True (-not ($candidate -match '[^\r]\n')) 'the composed CRLF file mixes line endings'

    # --- A missing configuration is composed, validated and published. ---
    $caseHome = New-HerdrHome 'apply'
    New-Item -ItemType Directory -Path (Join-Path $appData 'herdr') -Force | Out-Null
    $script:PlasticineHerdrCalls.Clear()
    $run = Invoke-TestCapture { Invoke-PlasticineHerdrConfigApply -HomeDirectory $caseHome }
    Assert-True (-not $run.Threw) "the herdr configuration apply failed: $($run.Message)"
    $configPath = Get-ConfigPath
    Assert-True (Test-Path -LiteralPath $configPath -PathType Leaf) 'the composed configuration was not published'
    Assert-Equal 1 $script:PlasticineHerdrCalls.Count 'the candidate was not validated once'
    Assert-True (@($script:PlasticineHerdrCalls)[0] -match 'config check') 'the candidate check did not run'
    $environment = @($script:PlasticineHerdrEnvironments)[0]
    Assert-True ($environment.ContainsKey('HERDR_CONFIG_PATH')) 'the candidate check did not receive HERDR_CONFIG_PATH'
    Assert-True (Test-Path -LiteralPath (Get-ReloadMarker -CaseHome $caseHome) -PathType Leaf) 'the reload marker was not written'
    Assert-True (-not (Test-Path -LiteralPath (Get-BackupPath -CaseHome $caseHome))) 'a first-time configuration created a backup'
    $published = Read-PlasticineConfigText $configPath
    Assert-True ($published -match '\[terminal\]') 'the published configuration has no managed section'
    Assert-True ($published -match 'shell_mode = "non_login"') 'the published configuration lost the shell mode'

    # --- An already-composed configuration causes no work and no reload. ---
    $script:PlasticineHerdrCalls.Clear()
    Remove-Item -LiteralPath (Get-ReloadMarker -CaseHome $caseHome) -Force
    $run = Invoke-TestCapture { Invoke-PlasticineHerdrConfigApply -HomeDirectory $caseHome }
    Assert-True (-not $run.Threw) "the repeated herdr apply failed: $($run.Message)"
    Assert-Equal 0 $script:PlasticineHerdrCalls.Count 'an unchanged configuration still ran the herdr command'
    Assert-True (-not (Test-Path -LiteralPath (Get-ReloadMarker -CaseHome $caseHome))) 'an unchanged configuration marked a reload'

    # --- A changed Owner file is backed up before the replacement. ---
    Set-Content -LiteralPath $configPath -Value "font_size = 14`n" -NoNewline
    $run = Invoke-TestCapture { Invoke-PlasticineHerdrConfigApply -HomeDirectory $caseHome }
    Assert-True (-not $run.Threw) "the changed herdr apply failed: $($run.Message)"
    Assert-Equal "font_size = 14`n" (Get-Content -LiteralPath (Get-BackupPath -CaseHome $caseHome) -Raw) `
        'the previous configuration was not backed up'
    Assert-True ((Read-PlasticineConfigText $configPath) -match '\[terminal\]') 'the configuration was not recomposed'
    $backupAcl = (Get-Acl -LiteralPath (Split-Path -Parent (Get-BackupPath -CaseHome $caseHome))).Sddl
    Assert-True ($backupAcl -match 'D:PAI') "the herdr backup directory is not owner-only: $backupAcl"

    # --- A rejected candidate leaves the existing configuration alone. ---
    Set-Content -LiteralPath $configPath -Value "font_size = 16
" -NoNewline
    $before = Read-PlasticineConfigText $configPath
    $env:PLASTICINE_TEST_CHECK_FAIL = '1'
    $run = Invoke-TestCapture { Invoke-PlasticineHerdrConfigApply -HomeDirectory $caseHome }
    Remove-Item Env:\PLASTICINE_TEST_CHECK_FAIL -ErrorAction SilentlyContinue
    Assert-True $run.Threw 'an invalid candidate reported success'
    Assert-True ($run.Error -match 'candidate config is invalid') 'the invalid candidate was not reported'
    Assert-Equal $before (Read-PlasticineConfigText $configPath) 'the invalid candidate changed the configuration'

    # --- Reload only runs for a pending marker and a running server. ---
    Remove-Item -LiteralPath (Get-ReloadMarker -CaseHome $caseHome) -Force -ErrorAction SilentlyContinue
    $script:PlasticineHerdrCalls.Clear()
    $run = Invoke-TestCapture { Invoke-PlasticineHerdrConfigReload -HomeDirectory $caseHome }
    Assert-True (-not $run.Threw) "the herdr reload without a marker failed: $($run.Message)"
    Assert-Equal 0 $script:PlasticineHerdrCalls.Count 'a reload ran without a pending marker'

    Set-Content -LiteralPath (Get-ReloadMarker -CaseHome $caseHome) -Value '' -NoNewline
    $script:PlasticineHerdrCalls.Clear()
    $run = Invoke-TestCapture { Invoke-PlasticineHerdrConfigReload -HomeDirectory $caseHome }
    Assert-True (-not $run.Threw) "the herdr reload failed: $($run.Message)"
    Assert-Equal 2 $script:PlasticineHerdrCalls.Count 'a running server was not asked to reload'
    Assert-True (-not (Test-Path -LiteralPath (Get-ReloadMarker -CaseHome $caseHome))) 'the reload marker was not cleared'

    Set-Content -LiteralPath (Get-ReloadMarker -CaseHome $caseHome) -Value '' -NoNewline
    $env:PLASTICINE_TEST_SERVER_STOPPED = '1'
    $script:PlasticineHerdrCalls.Clear()
    $run = Invoke-TestCapture { Invoke-PlasticineHerdrConfigReload -HomeDirectory $caseHome }
    Remove-Item Env:\PLASTICINE_TEST_SERVER_STOPPED -ErrorAction SilentlyContinue
    Assert-True (-not $run.Threw) "the stopped-server reload failed: $($run.Message)"
    Assert-Equal 1 $script:PlasticineHerdrCalls.Count 'a stopped server was asked to reload'
    Assert-True (-not (Test-Path -LiteralPath (Get-ReloadMarker -CaseHome $caseHome))) 'the stopped-server marker was not cleared'

    Set-Content -LiteralPath (Get-ReloadMarker -CaseHome $caseHome) -Value '' -NoNewline
    $env:PLASTICINE_TEST_RELOAD_FAIL = '1'
    $run = Invoke-TestCapture { Invoke-PlasticineHerdrConfigReload -HomeDirectory $caseHome }
    Remove-Item Env:\PLASTICINE_TEST_RELOAD_FAIL -ErrorAction SilentlyContinue
    Assert-True $run.Threw 'a failed reload reported success'
    Assert-True ($run.Error -match 'running server could not reload configuration') 'the reload failure was not reported'
    Assert-True (Test-Path -LiteralPath (Get-ReloadMarker -CaseHome $caseHome)) 'the reload failure dropped the pending marker'

    Complete-Test 'windows herdr config tests passed'
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
} finally {
    $script:PlasticineHerdrRunner = $null
    $script:PlasticineHerdrAppDataOverride = $null
    $script:PlasticineHerdrShellCommandOverride = $null
    Remove-Item -LiteralPath $PlasticineTestRoot -Recurse -Force -ErrorAction SilentlyContinue
}
