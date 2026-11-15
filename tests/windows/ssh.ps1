# Coverage for the Windows github-ssh route: system-OpenSSH resolution, the
# ~/.ssh/config managed-block composition (the Windows replacement for the Unix
# modify_ script), first-backup-wins, private-key installation with owner-only
# ACLs, the opt-in connection probe and the five apply-time templates.
#
# Every ssh and ssh-keygen call goes through fixture scripts: no test connects
# to github.com, and no test writes the real user profile or HKCU. Disposable
# homes live under $PlasticineTestRoot.

$repoDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'harness.ps1')
$PlasticineTestName = 'windows ssh'
. (Join-Path $repoDir 'lib\windows\common.ps1')
. (Join-Path $repoDir 'lib\windows\publish.ps1')
. (Join-Path $repoDir 'lib\windows\acl.ps1')
. (Join-Path $repoDir 'lib\windows\config-apply.ps1')
. (Join-Path $repoDir 'lib\windows\feature-github-ssh.ps1')

$savedSshExecutable = $PlasticineSshExecutable
$savedKeygenExecutable = $PlasticineSshKeygenExecutable
$savedOpenSshDirectoryOverride = $PlasticineOpenSshDirectoryOverride
$savedPath = $env:PATH
$savedUserProfile = $env:USERPROFILE
$savedHome = $env:HOME
$scenarioEnvironmentNames = @(
    'PLASTICINE_GITHUB_SSH_KEY',
    'PLASTICINE_REPLACE_GITHUB_SSH_KEY',
    'PLASTICINE_GITHUB_SSH_TEST',
    'PLASTICINE_TEST_SSH_CALLS',
    'PLASTICINE_TEST_SSH_MESSAGE',
    'PLASTICINE_TEST_SSH_EXIT',
    'PLASTICINE_TEST_SSH_DEFAULT_USER',
    'PLASTICINE_TEST_SSH_CANDIDATE_CONFLICT',
    'PLASTICINE_TEST_SSH_FAIL_CONFIG',
    'PLASTICINE_TEST_SSH_IGNORE_INCLUDE'
)
$savedEnvironment = @{}
foreach ($name in $scenarioEnvironmentNames) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

$fixtures = New-TestDirectory 'fixtures'
$callsFile = Join-Path $PlasticineTestRoot 'calls'
$sshFixture = Join-Path $fixtures 'ssh-fixture.ps1'
$keygenFixture = Join-Path $fixtures 'ssh-keygen-fixture.ps1'

function New-SshFixture {
    param([Parameter(Mandatory = $true)][string]$Path)
    $content = @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Argument)
$ErrorActionPreference = 'Continue'
$calls = $env:PLASTICINE_TEST_SSH_CALLS
if ($calls) { Add-Content -LiteralPath $calls -Value ('ssh ' + ($Argument -join ' ')) }

function Expand-FixtureConfig {
    param([AllowEmptyString()][string]$Text, [int]$Depth = 0)
    $expanded = New-Object System.Collections.ArrayList
    if ($Depth -gt 8) { return $expanded.ToArray() }
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line.Trim() -match '^Include\s+(.+)$') {
            if ($env:PLASTICINE_TEST_SSH_IGNORE_INCLUDE -eq '1') { continue }
            $path = $Matches[1].Trim()
            if ($path.StartsWith('~/') -or $path.StartsWith('~\')) {
                $path = Join-Path $env:USERPROFILE $path.Substring(2)
            }
            if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) {
                foreach ($nested in (Expand-FixtureConfig -Text ([IO.File]::ReadAllText($path)) -Depth ($Depth + 1))) {
                    [void]$expanded.Add($nested)
                }
            }
            continue
        }
        [void]$expanded.Add($line)
    }
    return $expanded.ToArray()
}

if ($Argument.Count -eq 0) { [Console]::Error.WriteLine('fixture ssh: no arguments'); exit 64 }
$mode = $Argument[0]
if ($mode -eq '-G') {
    $configPath = ''
    for ($index = 1; $index -lt $Argument.Count; $index++) {
        if ($Argument[$index] -eq '-F' -and ($index + 1) -lt $Argument.Count) { $configPath = $Argument[$index + 1] }
    }
    $text = ''
    if ($configPath -and $configPath -ne 'NUL') {
        if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
            [Console]::Error.WriteLine('fixture ssh: missing config')
            exit 255
        }
        $text = [IO.File]::ReadAllText($configPath)
    }
    $failMarker = $env:PLASTICINE_TEST_SSH_FAIL_CONFIG
    if ($failMarker -and $text.Contains($failMarker)) {
        [Console]::Error.WriteLine('fixture ssh: bad configuration option')
        exit 255
    }
    $conflict = $env:PLASTICINE_TEST_SSH_CANDIDATE_CONFLICT
    if ($conflict -and $text.Contains('# BEGIN plasticine-dotfiles github-ssh')) {
        $identity = '~/.ssh/id_github'
        $user = 'git'
        $hostname = 'github.com'
        $identitiesOnly = 'yes'
        if ($conflict -eq 'user') { $user = 'someone' }
        if ($conflict -eq 'host') { $hostname = 'github.example.invalid' }
        if ($conflict -eq 'identity') { $identity = '~/.ssh/other' }
        if ($conflict -eq 'identitiesonly') { $identitiesOnly = 'no' }
        Write-Output ('user ' + $user)
        Write-Output ('hostname ' + $hostname)
        Write-Output ('identitiesonly ' + $identitiesOnly)
        Write-Output ('identityfile ' + $identity)
        if ($conflict -eq 'identity-count') { Write-Output 'identityfile ~/.ssh/second' }
        exit 0
    }
    $defaultUser = 'fixture-default-user'
    if ($env:PLASTICINE_TEST_SSH_DEFAULT_USER) { $defaultUser = $env:PLASTICINE_TEST_SSH_DEFAULT_USER }
    $userValue = $defaultUser
    $hostValue = 'github.com'
    $identitiesOnlyValue = 'no'
    $identityFiles = New-Object System.Collections.ArrayList
    foreach ($file in @('~/.ssh/id_rsa', '~/.ssh/id_ecdsa', '~/.ssh/id_ed25519')) { [void]$identityFiles.Add($file) }
    $userSet = $false
    $hostSet = $false
    $identitiesOnlySet = $false
    $identityConfigured = $false
    $inGithub = $false
    foreach ($line in (Expand-FixtureConfig -Text $text)) {
        $trimmed = ([string]$line).Trim()
        if ($trimmed -match '^Host\s+(.+)$') {
            $inGithub = $false
            foreach ($pattern in ($Matches[1] -split '\s+')) {
                if ($pattern -eq '*' -or $pattern -eq 'github.com') { $inGithub = $true }
            }
            continue
        }
        if (-not $inGithub) { continue }
        if ($trimmed -match '^User\s+(\S+)$') { if (-not $userSet) { $userValue = $Matches[1]; $userSet = $true }; continue }
        if ($trimmed -match '^HostName\s+(\S+)$') { if (-not $hostSet) { $hostValue = $Matches[1]; $hostSet = $true }; continue }
        if ($trimmed -match '^IdentitiesOnly\s+(\S+)$') { if (-not $identitiesOnlySet) { $identitiesOnlyValue = $Matches[1]; $identitiesOnlySet = $true }; continue }
        if ($trimmed -match '^IdentityFile\s+(.+)$') {
            if (-not $identityConfigured) { $identityFiles.Clear(); $identityConfigured = $true }
            [void]$identityFiles.Add($Matches[1].Trim())
            continue
        }
    }
    Write-Output ('user ' + $userValue)
    Write-Output ('hostname ' + $hostValue)
    Write-Output 'port 22'
    Write-Output ('identitiesonly ' + $identitiesOnlyValue)
    foreach ($file in $identityFiles) { Write-Output ('identityfile ' + $file) }
    exit 0
}
if ($mode -eq '-T') {
    if ($env:PLASTICINE_TEST_SSH_MESSAGE) { Write-Output $env:PLASTICINE_TEST_SSH_MESSAGE }
    $exitCode = 1
    if ($env:PLASTICINE_TEST_SSH_EXIT) { $exitCode = [int]$env:PLASTICINE_TEST_SSH_EXIT }
    exit $exitCode
}
[Console]::Error.WriteLine('fixture ssh: unexpected arguments')
exit 64
'@
    Set-Content -LiteralPath $Path -Value $content -Encoding Ascii
}

function New-KeygenFixture {
    param([Parameter(Mandatory = $true)][string]$Path)
    $content = @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Argument)
$ErrorActionPreference = 'Continue'
$calls = $env:PLASTICINE_TEST_SSH_CALLS
if ($calls) { Add-Content -LiteralPath $calls -Value ('keygen ' + ($Argument -join ' ')) }
if ($Argument.Count -ge 2 -and $Argument[0] -eq '-lf') {
    $path = $Argument[1]
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        [Console]::Error.WriteLine('fixture ssh-keygen: missing file')
        exit 255
    }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    Write-Output ('256 SHA256:' + $hash + ' fixture (ED25519)')
    exit 0
}
[Console]::Error.WriteLine('fixture ssh-keygen: unexpected arguments')
exit 64
'@
    Set-Content -LiteralPath $Path -Value $content -Encoding Ascii
}

New-SshFixture -Path $sshFixture
New-KeygenFixture -Path $keygenFixture

function Reset-Calls {
    if (Test-Path -LiteralPath $callsFile) { Remove-Item -LiteralPath $callsFile -Force }
}

function Get-Calls {
    if (Test-Path -LiteralPath $callsFile) { return @(Get-Content -LiteralPath $callsFile) }
    return @()
}

function Clear-ScenarioEnvironment {
    foreach ($name in $scenarioEnvironmentNames) {
        Remove-Item -LiteralPath ('Env:\' + $name) -ErrorAction SilentlyContinue
    }
}

function New-Scenario {
    param([Parameter(Mandatory = $true)][string]$Name)
    $scenarioHome = Join-Path (New-TestDirectory $Name) 'home'
    New-Item -ItemType Directory -Path $scenarioHome -ErrorAction Stop | Out-Null
    Clear-ScenarioEnvironment
    Reset-Calls
    $env:PLASTICINE_TEST_SSH_CALLS = $callsFile
    return $scenarioHome
}

function Get-TestText {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [IO.File]::ReadAllText($Path, (Get-PlasticineLatin1Encoding))
}

function Write-TestText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )
    [IO.File]::WriteAllText($Path, $Text, (Get-PlasticineLatin1Encoding))
}

function Assert-BytesEqual {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Expected,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Actual,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if ($Expected.Length -ne $Actual.Length) {
        Fail "$Message (length expected $($Expected.Length), observed $($Actual.Length))"
    }
    for ($index = 0; $index -lt $Expected.Length; $index++) {
        if ($Expected[$index] -ne $Actual[$index]) {
            Fail "$Message (byte $index expected $($Expected[$index]), observed $($Actual[$index]))"
        }
    }
}

function Write-OwnerConfig {
    param(
        [Parameter(Mandatory = $true)][string]$HomeDirectory,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [string]$LineEnding = "`r`n"
    )
    $sshDirectory = Join-Path $HomeDirectory '.ssh'
    New-Item -ItemType Directory -Path $sshDirectory -Force -ErrorAction Stop | Out-Null
    $configPath = Join-Path $sshDirectory 'config'
    $normalized = $Text -replace "`r?`n", $LineEnding
    Write-TestText -Path $configPath -Text $normalized
    return $configPath
}

function New-TestPrivateKey {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Payload,
        [string]$FirstLine = '-----BEGIN OPENSSH PRIVATE KEY-----',
        [string]$LastLine = '-----END OPENSSH PRIVATE KEY-----'
    )
    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -ItemType Directory -Path $Directory -Force -ErrorAction Stop | Out-Null
    }
    $path = Join-Path $Directory $Name
    Write-TestText -Path $path -Text ($FirstLine + "`n" + $Payload + "`n" + $LastLine + "`n")
    return $path
}

function Get-BackupFiles {
    param([Parameter(Mandatory = $true)][string]$HomeDirectory)
    $directory = Join-Path $HomeDirectory '.plasticine\backups\github-ssh'
    if (-not (Test-Path -LiteralPath $directory)) { return @() }
    return @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)
}

function New-KeyedScenario {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$KeyPath
    )
    $scenarioHome = New-Scenario $Name
    $sshDirectory = Join-Path $scenarioHome '.ssh'
    New-Item -ItemType Directory -Path $sshDirectory -Force -ErrorAction Stop | Out-Null
    Copy-Item -LiteralPath $KeyPath -Destination (Join-Path $sshDirectory 'id_github') -Force
    return $scenarioHome
}

function Get-ExpectedDiagnostic {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [object[]]$Argument = @()
    )
    $message = Get-PlasticineGithubSshMessage -Key $Key
    if (@($Argument).Count -gt 0) { $message = $message -f $Argument }
    return $message
}

function Expand-TestTemplate {
    param([Parameter(Mandatory = $true)][string]$Path)
    $raw = Get-Content -LiteralPath $Path -Raw
    $rendered = New-Object System.Collections.ArrayList
    foreach ($line in ($raw -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\{\{-?\s*(if|else|end)\b') { continue }
        $substituted = [regex]::Replace($line, '\{\{-?\s*template\s+"powershell-quote"\s+[^}]+\}\}', "''")
        [void]$rendered.Add($substituted)
    }
    return ($rendered -join "`n")
}

try {
    $script:PlasticineSshExecutable = $sshFixture
    $script:PlasticineSshKeygenExecutable = $keygenFixture
    $env:PLASTICINE_TEST_SSH_CALLS = $callsFile

    # --- Template contract and rendered-body parse -------------------------
    $templateExpectations = [ordered]@{
        'run_before_00_validate_github_ssh_config.ps1.tmpl' = 'Assert-PlasticineGithubSshConfiguration'
        'run_before_05_backup_github_ssh_config.ps1.tmpl'   = 'Save-PlasticineGithubSshConfigBackup'
        'run_before_10_install_github_ssh_key.ps1.tmpl'     = 'Install-PlasticineGithubSshKey'
        'run_before_15_compose_github_ssh_config.ps1.tmpl'  = 'Invoke-PlasticineGithubSshConfigApply'
        'run_after_90_test_github_ssh.ps1.tmpl'             = 'Invoke-PlasticineGithubSshConnectionTest'
    }
    $requiredModules = @('common', 'acl', 'config-apply', 'feature-github-ssh')
    foreach ($templateName in $templateExpectations.Keys) {
        $templatePath = Join-Path $repoDir ('.chezmoiscripts\' + $templateName)
        Assert-True (Test-Path -LiteralPath $templatePath -PathType Leaf) "the $templateName template is missing"
        $raw = Get-Content -LiteralPath $templatePath -Raw
        $templateLines = @($raw -split "`r?`n")
        Assert-Equal '{{- if eq .chezmoi.os "windows" -}}' $templateLines[0] "$templateName lost the Windows guard"
        Assert-True ($raw -match 'has "github-ssh" \.tools') "$templateName lost the github-ssh guard"
        Assert-True ($raw -match '\{\{- end -\}\}\s*\{\{- end -\}\}\s*$') "$templateName lost the closing guards"
        foreach ($requiredLine in @(
                '{{ template "powershell-quote" .chezmoi.sourceDir }}',
                '{{ template "powershell-quote" .chezmoi.destDir }}',
                'Write-PlasticineError',
                'exit 1',
                $templateExpectations[$templateName])) {
            Assert-True ($raw.Contains($requiredLine)) "$templateName is missing $requiredLine"
        }
        foreach ($moduleName in $requiredModules) {
            $moduleLine = ". (Join-Path `$source_dir 'lib/windows/$moduleName.ps1')"
            Assert-True ($raw.Contains($moduleLine)) "$templateName is missing the $moduleName dot-source"
        }
        if ($templateName -like 'run_after_90*') {
            Assert-True ($raw.Contains('.githubSSHTest')) "$templateName lost the opt-in connection-test guard"
        }
        $renderedBody = Expand-TestTemplate -Path $templatePath
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseInput($renderedBody, [ref]$tokens, [ref]$errors)
        Assert-Equal 0 @($errors).Count "$templateName does not parse as PowerShell after rendering"
    }

    # --- The module itself parses and stays ASCII for Windows PowerShell 5.1 ---
    $modulePath = Join-Path $repoDir 'lib\windows\feature-github-ssh.ps1'
    $moduleTokens = $null
    $moduleErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($modulePath, [ref]$moduleTokens, [ref]$moduleErrors)
    Assert-Equal 0 @($moduleErrors).Count 'feature-github-ssh.ps1 does not parse on this PowerShell version'
    $nonAsciiBytes = @([IO.File]::ReadAllBytes($modulePath) | Where-Object { $_ -gt 127 })
    Assert-Equal 0 $nonAsciiBytes.Count 'feature-github-ssh.ps1 must stay ASCII so PowerShell 5.1 decodes it correctly'
    Assert-True ((Get-PlasticineGithubSshMessage -Key 'Conflict').Contains('github.com')) `
        'the escaped Chinese diagnostics do not decode'

    # --- ssh -G output parsing ---------------------------------------------
    $effective = ConvertFrom-PlasticineGithubSshGOutput -Line @(
        'user git',
        'hostname github.com',
        'port 22',
        'identityfile ~/.ssh/id_github',
        'identitiesonly yes'
    )
    Assert-Equal 'git' $effective.User 'the parser lost the user field'
    Assert-Equal 'github.com' $effective.HostName 'the parser lost the hostname field'
    Assert-Equal 'yes' $effective.IdentitiesOnly 'the parser lost the identitiesonly field'
    Assert-Equal 1 @($effective.IdentityFile).Count 'the parser lost the identityfile field'
    Assert-Equal '~/.ssh/id_github' @($effective.IdentityFile)[0] 'the parser lost the identityfile value'
    $multiple = ConvertFrom-PlasticineGithubSshGOutput -Line @(
        'user fixture-default-user',
        'hostname github.com',
        'identityfile ~/.ssh/id_rsa',
        'identityfile ~/.ssh/id_ed25519',
        'identitiesonly no',
        'hostkeyalgorithms ssh-ed25519'
    )
    Assert-Equal 2 @($multiple.IdentityFile).Count 'the parser dropped a repeated identityfile'
    Assert-Equal '~/.ssh/id_ed25519' @($multiple.IdentityFile)[1] 'the parser reordered identity files'
    Assert-Equal 'fixture-default-user' $multiple.User 'the parser kept the wrong user value'
    $empty = ConvertFrom-PlasticineGithubSshGOutput -Line @()
    Assert-Equal '' $empty.User 'the parser invented a user field'
    Assert-Equal 0 @($empty.IdentityFile).Count 'the parser invented identity files'
    $carriage = ConvertFrom-PlasticineGithubSshGOutput -Line @("user git`r", "identityfile ~/.ssh/id_github`r")
    Assert-Equal 'git' $carriage.User 'the parser did not strip a CR line ending'

    # --- Managed marker block state ----------------------------------------
    $beginMarker = $PlasticineGithubSshBeginMarker
    $endMarker = $PlasticineGithubSshEndMarker
    $block = Get-PlasticineGithubSshManagedBlock
    $paired = Get-PlasticineGithubSshManagedBlockState -Text ($block + "Host example.com`r`n")
    Assert-True (-not $paired.Damaged) 'a paired managed block was reported as damaged'
    Assert-True $paired.HasMarker 'a paired managed block was not observed'
    Assert-True $paired.HasBlock 'a paired managed block was not reported as intact'
    Assert-Equal "Host example.com`r`n" $paired.Stripped 'a paired block did not strip to the Owner bytes'
    $unmarked = Get-PlasticineGithubSshManagedBlockState -Text 'Host example.com'
    Assert-True (-not $unmarked.HasMarker) 'an Owner-only config was reported as managed'
    Assert-Equal 'Host example.com' $unmarked.Stripped 'an Owner-only config was rewritten during slicing'
    $unterminated = Get-PlasticineGithubSshManagedBlockState -Text ($beginMarker + "`r`nHost x`r`n")
    Assert-True $unterminated.Damaged 'an unterminated managed block was accepted'
    $duplicated = Get-PlasticineGithubSshManagedBlockState -Text ($block + $beginMarker + "`r`n")
    Assert-True $duplicated.Damaged 'a duplicated managed block was accepted'
    $orphanEnd = Get-PlasticineGithubSshManagedBlockState -Text ($endMarker + "`r`nHost x`r`n")
    Assert-True $orphanEnd.Damaged 'an orphaned end marker was accepted'
    $lfBlock = Get-PlasticineGithubSshManagedBlock -LineEnding "`n"
    $lfState = Get-PlasticineGithubSshManagedBlockState -Text ($lfBlock + "Host x`n")
    Assert-True (-not $lfState.Damaged) 'LF marker lines were not recognized'

    # --- Candidate composition is byte-exact and idempotent ----------------
    $owner = "# owner`r`nHost example.com`r`n    User someone`r`n"
    $candidate = New-PlasticineGithubSshConfigCandidate -Text $owner
    Assert-Equal ($block + $owner) $candidate 'the candidate did not preserve the Owner bytes exactly'
    Assert-True $candidate.EndsWith($owner) 'the candidate did not append the Owner bytes unchanged'
    $ownerLf = "Host example.com`n    User someone`n"
    $candidateLf = New-PlasticineGithubSshConfigCandidate -Text $ownerLf
    Assert-Equal ((Get-PlasticineGithubSshManagedBlock -LineEnding "`n") + $ownerLf) $candidateLf `
        'the candidate did not follow an LF Owner config'
    $ownerNoNewline = 'Host example.com'
    $candidateNoNewline = New-PlasticineGithubSshConfigCandidate -Text $ownerNoNewline
    Assert-Equal ($block + $ownerNoNewline) $candidateNoNewline 'the candidate invented a final newline'
    Assert-Equal $candidate (New-PlasticineGithubSshConfigCandidate -Text $candidate) `
        'composing an already managed config was not idempotent'
    $fragmentTemplate = Get-Content -LiteralPath (Join-Path $repoDir '.chezmoitemplates\github-ssh-fragment') -Raw
    Assert-Equal (($fragmentTemplate -replace "`r`n", "`n")) ((Get-PlasticineGithubSshFragmentText) -replace "`r`n", "`n") `
        'the Windows fragment drifted from .chezmoitemplates/github-ssh-fragment'

    # --- validate: a fresh home is accepted without touching it ------------
    $scenarioHome = New-Scenario 'validate-fresh'
    $run = Invoke-TestCapture { Assert-PlasticineGithubSshConfiguration -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "validation failed on a fresh home: $($run.Message)"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $scenarioHome '.ssh'))) 'validation created ~/.ssh'

    # --- validate: an allowed existing rule passes -------------------------
    $scenarioHome = New-Scenario 'validate-allowed'
    $allowedConfig = Write-OwnerConfig -HomeDirectory $scenarioHome -Text "Host github.com`n    User git`n"
    $allowedBytes = [IO.File]::ReadAllBytes($allowedConfig)
    $run = Invoke-TestCapture { Assert-PlasticineGithubSshConfiguration -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "validation rejected the allowed git user rule: $($run.Message)"
    Assert-BytesEqual $allowedBytes ([IO.File]::ReadAllBytes($allowedConfig)) 'validation rewrote the Owner config'

    # --- validate: conflicting user, hostname and identity rules stop ------
    $conflictCases = [ordered]@{
        'hostname' = "Host github.com`n    HostName internal.example.invalid`n"
        'user'     = "Host github.com`n    User owner-name`n"
        'identity' = "Host github.com`n    IdentityFile ~/.ssh/other`n"
    }
    foreach ($caseName in $conflictCases.Keys) {
        $scenarioHome = New-Scenario ('validate-conflict-' + $caseName)
        $configPath = Write-OwnerConfig -HomeDirectory $scenarioHome -Text $conflictCases[$caseName]
        $before = [IO.File]::ReadAllBytes($configPath)
        $run = Invoke-TestCapture { Assert-PlasticineGithubSshConfiguration -HomeDirectory $scenarioHome }
        Assert-True $run.Threw "the $caseName conflict was accepted"
        Assert-True ($run.Error.Contains((Get-PlasticineGithubSshMessage -Key 'Conflict'))) `
            "the $caseName conflict did not use the Chinese diagnostic"
        Assert-BytesEqual $before ([IO.File]::ReadAllBytes($configPath)) "the $caseName conflict modified the config"
    }

    # --- validate: damaged and duplicated marker blocks stop --------------
    foreach ($case in @('unterminated', 'duplicated')) {
        $scenarioHome = New-Scenario ('validate-damaged-' + $case)
        if ($case -eq 'unterminated') {
            $configPath = Write-OwnerConfig -HomeDirectory $scenarioHome -Text ($beginMarker + "`nHost x`n")
        } else {
            $configPath = Write-OwnerConfig -HomeDirectory $scenarioHome -Text ($block + $block)
        }
        $before = [IO.File]::ReadAllBytes($configPath)
        $run = Invoke-TestCapture { Assert-PlasticineGithubSshConfiguration -HomeDirectory $scenarioHome }
        Assert-True $run.Threw "a $case marker block was accepted"
        Assert-True ($run.Error.Contains((Get-PlasticineGithubSshMessage -Key 'ManagedBlockDamaged'))) `
            "the $case marker block did not use the Chinese diagnostic"
        Assert-BytesEqual $before ([IO.File]::ReadAllBytes($configPath)) "the $case marker block destroyed the config"
    }

    # --- validate: an unparseable config stops -----------------------------
    $scenarioHome = New-Scenario 'validate-unparseable'
    $configPath = Write-OwnerConfig -HomeDirectory $scenarioHome -Text "Host broken-host`n    User x`n"
    $before = [IO.File]::ReadAllBytes($configPath)
    $env:PLASTICINE_TEST_SSH_FAIL_CONFIG = 'Host broken-host'
    $run = Invoke-TestCapture { Assert-PlasticineGithubSshConfiguration -HomeDirectory $scenarioHome }
    Clear-ScenarioEnvironment
    $env:PLASTICINE_TEST_SSH_CALLS = $callsFile
    Assert-True $run.Threw 'an unparseable config was accepted'
    Assert-True ($run.Error.Contains((Get-PlasticineGithubSshMessage -Key 'ConfigUnparseable'))) `
        'the unparseable config did not use the Chinese diagnostic'
    Assert-BytesEqual $before ([IO.File]::ReadAllBytes($configPath)) 'the unparseable config was modified'

    # --- shapes: file/junction conflicts are refused ----------------------
    $scenarioHome = New-Scenario 'shape-ssh-file'
    Write-TestText -Path (Join-Path $scenarioHome '.ssh') -Text 'not a directory'
    $run = Invoke-TestCapture { Assert-PlasticineGithubSshConfiguration -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'a file at ~/.ssh was accepted'
    Assert-True ($run.Error -match 'must be a regular directory') 'the file at ~/.ssh was not reported as an irregular directory'

    $scenarioHome = New-Scenario 'shape-config-directory'
    $sshDirectory = Join-Path $scenarioHome '.ssh'
    New-Item -ItemType Directory -Path $sshDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $sshDirectory 'config') -Force | Out-Null
    $run = Invoke-TestCapture { Assert-PlasticineGithubSshConfiguration -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'a directory at ~/.ssh/config was accepted'
    Assert-True ($run.Error -match 'must be a regular file') 'the directory at ~/.ssh/config was not reported as an irregular file'

    $scenarioHome = New-Scenario 'shape-ssh-junction'
    $junctionTarget = New-TestDirectory 'ssh-junction-target'
    New-Item -ItemType Junction -Path (Join-Path $scenarioHome '.ssh') -Target $junctionTarget -ErrorAction Stop | Out-Null
    $run = Invoke-TestCapture { Assert-PlasticineGithubSshConfiguration -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'a junction at ~/.ssh was accepted'
    Assert-True ($run.Error -match 'must be a regular directory') 'the junction at ~/.ssh was not reported as an irregular directory'

    # --- backup: first pre-managed copy wins ------------------------------
    $scenarioHome = New-Scenario 'backup-first-wins'
    $configPath = Write-OwnerConfig -HomeDirectory $scenarioHome -Text "# pristine`nHost example.com`n    User someone`n"
    $pristineBytes = [IO.File]::ReadAllBytes($configPath)
    $run = Invoke-TestCapture { Save-PlasticineGithubSshConfigBackup -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the first pre-managed backup failed: $($run.Message)"
    $firstBackup = $run.Value
    Assert-True ([bool]$firstBackup) 'the first pre-managed backup was not created'
    Assert-True (Test-Path -LiteralPath $firstBackup -PathType Leaf) 'the first pre-managed backup is missing'
    Assert-BytesEqual $pristineBytes ([IO.File]::ReadAllBytes($firstBackup)) 'the backup did not preserve the pre-managed bytes'
    $backupAcl = Get-Acl -LiteralPath $firstBackup
    Assert-True $backupAcl.AreAccessRulesProtected 'the pre-managed backup is not owner-only'
    Write-OwnerConfig -HomeDirectory $scenarioHome -Text "# rewritten`nHost example.com`n" | Out-Null
    $run = Invoke-TestCapture { Save-PlasticineGithubSshConfigBackup -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the second pre-managed backup failed: $($run.Message)"
    $secondBackup = $run.Value
    Assert-Equal $firstBackup $secondBackup 'a rerun returned a different first backup path'
    Assert-BytesEqual $pristineBytes ([IO.File]::ReadAllBytes($firstBackup)) 'a rerun overwrote the first backup'
    $managedHome = New-Scenario 'backup-managed'
    Write-OwnerConfig -HomeDirectory $managedHome -Text ($block + "Host example.com`n") | Out-Null
    $run = Invoke-TestCapture { Save-PlasticineGithubSshConfigBackup -HomeDirectory $managedHome }
    Assert-True (-not $run.Threw) "the managed-config backup check failed: $($run.Message)"
    Assert-True ($null -eq $run.Value) 'a managed config was backed up as if it were pre-managed'

    # --- key install: fresh copy, ACL and no key material on the streams ---
    $keyDirectory = New-TestDirectory 'keys'
    $keyBody = 'ZmFrZS1wcml2YXRlLWtleS1ib2R5LW11c3Qtbm90LWxlYWs='
    $sourceKey = New-TestPrivateKey -Directory $keyDirectory -Name 'id_ed25519' -Payload $keyBody
    $otherKeyBody = 'b3RoZXItcHJpdmF0ZS1rZXktYm9keQ=='
    $otherKey = New-TestPrivateKey -Directory $keyDirectory -Name 'id_other' -Payload $otherKeyBody
    $sourceFingerprint = Get-PlasticineGithubSshKeyFingerprint -KeygenExecutable $keygenFixture -Path $sourceKey
    Assert-True ([bool]$sourceFingerprint) 'the key fingerprint helper returned nothing'
    Assert-True ($sourceFingerprint.StartsWith('SHA256:')) 'the key fingerprint helper did not parse the second field'

    $scenarioHome = New-Scenario 'key-install'
    $run = Invoke-TestCapture {
        Install-PlasticineGithubSshKey -HomeDirectory $scenarioHome -SourceKey $sourceKey `
            -ExpectedFingerprint $sourceFingerprint
    }
    Assert-True (-not $run.Threw) "the key installation failed: $($run.Message)"
    $installedKey = Join-Path $scenarioHome '.ssh\id_github'
    Assert-True (Test-Path -LiteralPath $installedKey -PathType Leaf) 'the private key was not installed'
    Assert-Equal (Get-TestText $sourceKey) (Get-TestText $installedKey) 'the installed key bytes differ from the source'
    Assert-True (-not $run.Output.Contains($keyBody)) 'the private key contents reached stdout'
    Assert-True (-not $run.Error.Contains($keyBody)) 'the private key contents reached stderr'
    Assert-True ((Get-Acl -LiteralPath $installedKey).AreAccessRulesProtected) 'the installed key is not owner-only'
    $sshAcl = Get-Acl -LiteralPath (Join-Path $scenarioHome '.ssh')
    Assert-True $sshAcl.AreAccessRulesProtected 'the created ~/.ssh directory is not owner-only'
    $configDirectoryAcl = Get-Acl -LiteralPath (Join-Path $scenarioHome '.ssh\config.d')
    Assert-True $configDirectoryAcl.AreAccessRulesProtected 'the created ~/.ssh/config.d directory is not owner-only'
    Assert-Equal 0 @(Get-ChildItem -LiteralPath (Join-Path $scenarioHome '.ssh') -Filter '.id_github.*' -Force).Count `
        'the key installation left a staged key behind'

    # --- key install: an existing matching key is kept ---------------------
    $installedHash = (Get-FileHash -LiteralPath $installedKey -Algorithm SHA256).Hash
    $run = Invoke-TestCapture {
        Install-PlasticineGithubSshKey -HomeDirectory $scenarioHome -SourceKey $sourceKey `
            -ExpectedFingerprint $sourceFingerprint
    }
    Assert-True (-not $run.Threw) "the key reuse failed: $($run.Message)"
    Assert-True ($run.Output -match 'kept the existing private key') 'key reuse was not reported'
    Assert-Equal $installedHash (Get-FileHash -LiteralPath $installedKey -Algorithm SHA256).Hash 'key reuse replaced the key'
    Assert-Equal 0 @(Get-ChildItem -LiteralPath (Join-Path $scenarioHome '.ssh') -Filter 'id_github.plasticine-backup-*').Count `
        'key reuse created a replacement backup'

    # --- key install: an approved replacement backs up first ---------------
    $scenarioHome = New-Scenario 'key-replace'
    $sshDirectory = Join-Path $scenarioHome '.ssh'
    New-Item -ItemType Directory -Path $sshDirectory -Force | Out-Null
    Copy-Item -LiteralPath $otherKey -Destination (Join-Path $sshDirectory 'id_github') -Force
    $targetFingerprint = Get-PlasticineGithubSshKeyFingerprint -KeygenExecutable $keygenFixture -Path (Join-Path $sshDirectory 'id_github')
    $run = Invoke-TestCapture {
        Install-PlasticineGithubSshKey -HomeDirectory $scenarioHome -SourceKey $sourceKey `
            -ExpectedFingerprint $sourceFingerprint -ApprovedReplaceFingerprint $targetFingerprint
    }
    Assert-True (-not $run.Threw) "the approved replacement failed: $($run.Message)"
    Assert-Equal (Get-TestText $sourceKey) (Get-TestText (Join-Path $sshDirectory 'id_github')) `
        'the approved replacement did not install the supplied key'
    $keyBackups = @(Get-ChildItem -LiteralPath $sshDirectory -Filter 'id_github.plasticine-backup-*' -Force)
    Assert-Equal 1 $keyBackups.Count 'the replacement did not create exactly one key backup'
    Assert-Equal (Get-TestText $otherKey) (Get-TestText $keyBackups[0].FullName) 'the key backup does not hold the replaced key'
    Assert-True ((Get-Acl -LiteralPath $keyBackups[0].FullName).AreAccessRulesProtected) 'the key backup is not owner-only'
    Assert-True (-not $run.Output.Contains($keyBody)) 'the replacement printed the private key contents'

    # --- key install: an unapproved replacement stops ---------------------
    $scenarioHome = New-Scenario 'key-unapproved'
    $sshDirectory = Join-Path $scenarioHome '.ssh'
    New-Item -ItemType Directory -Path $sshDirectory -Force | Out-Null
    Copy-Item -LiteralPath $otherKey -Destination (Join-Path $sshDirectory 'id_github') -Force
    $otherBytes = [IO.File]::ReadAllBytes((Join-Path $sshDirectory 'id_github'))
    $run = Invoke-TestCapture {
        Install-PlasticineGithubSshKey -HomeDirectory $scenarioHome -SourceKey $sourceKey `
            -ExpectedFingerprint $sourceFingerprint
    }
    Assert-True $run.Threw 'an unapproved replacement reported success'
    Assert-True ($run.Error.Contains((Get-ExpectedDiagnostic -Key 'TargetKeyUnapproved' -Argument @((Join-Path $scenarioHome '.ssh\id_github'))))) `
        'the unapproved replacement did not use the Chinese diagnostic'
    Assert-BytesEqual $otherBytes ([IO.File]::ReadAllBytes((Join-Path $sshDirectory 'id_github'))) `
        'the unapproved replacement changed the target key'

    # --- key install: source and target shape failures --------------------
    $scenarioHome = New-Scenario 'key-source-changed'
    $run = Invoke-TestCapture {
        Install-PlasticineGithubSshKey -HomeDirectory $scenarioHome -SourceKey $sourceKey `
            -ExpectedFingerprint 'SHA256:0000000000000000000000000000000000000000000000000000000000000000'
    }
    Assert-True $run.Threw 'a key changed after confirmation was accepted'
    Assert-True ($run.Error.Contains((Get-ExpectedDiagnostic -Key 'SourceKeyChanged' -Argument @($sourceKey)))) `
        'the changed key did not use the Chinese diagnostic'

    $scenarioHome = New-Scenario 'key-unsupported'
    $badKey = Join-Path $keyDirectory 'not-a-key'
    Write-TestText -Path $badKey -Text "not a private key`n"
    $run = Invoke-TestCapture {
        Install-PlasticineGithubSshKey -HomeDirectory $scenarioHome -SourceKey $badKey `
            -ExpectedFingerprint $sourceFingerprint
    }
    Assert-True $run.Threw 'an unsupported private key was accepted'
    Assert-True ($run.Error.Contains((Get-ExpectedDiagnostic -Key 'SourceKeyUnsupported' -Argument @($badKey)))) `
        'the unsupported key did not use the Chinese diagnostic'

    $scenarioHome = New-Scenario 'key-empty'
    $emptyKey = Join-Path $keyDirectory 'empty-key'
    Write-TestText -Path $emptyKey -Text ''
    $run = Invoke-TestCapture {
        Install-PlasticineGithubSshKey -HomeDirectory $scenarioHome -SourceKey $emptyKey `
            -ExpectedFingerprint $sourceFingerprint
    }
    Assert-True $run.Threw 'an empty private key was accepted'
    Assert-True ($run.Error.Contains((Get-ExpectedDiagnostic -Key 'SourceKeyEmpty' -Argument @($emptyKey)))) `
        'the empty key did not use the Chinese diagnostic'

    $scenarioHome = New-Scenario 'key-target-directory'
    $sshDirectory = Join-Path $scenarioHome '.ssh'
    New-Item -ItemType Directory -Path (Join-Path $sshDirectory 'id_github') -Force | Out-Null
    $run = Invoke-TestCapture {
        Install-PlasticineGithubSshKey -HomeDirectory $scenarioHome -SourceKey $sourceKey `
            -ExpectedFingerprint $sourceFingerprint
    }
    Assert-True $run.Threw 'a directory at the private-key target was accepted'
    Assert-True ($run.Error.Contains((Get-ExpectedDiagnostic -Key 'KeyShape' -Argument @((Join-Path $scenarioHome '.ssh\id_github'))))) `
        'the irregular key target did not use the Chinese diagnostic'

    $scenarioHome = New-Scenario 'key-missing-fingerprint'
    $run = Invoke-TestCapture { Install-PlasticineGithubSshKey -HomeDirectory $scenarioHome -SourceKey $sourceKey }
    Assert-True $run.Threw 'a missing expected fingerprint was accepted'
    Assert-True ($run.Error.Contains((Get-PlasticineGithubSshMessage -Key 'FingerprintMissing'))) `
        'the missing fingerprint did not use the Chinese diagnostic'

    $scenarioHome = New-Scenario 'key-missing-source'
    $run = Invoke-TestCapture {
        Install-PlasticineGithubSshKey -HomeDirectory $scenarioHome -SourceKey '' -ExpectedFingerprint $sourceFingerprint
    }
    Assert-True $run.Threw 'a missing source key was accepted'
    Assert-True ($run.Error.Contains((Get-PlasticineGithubSshMessage -Key 'KeySourceMissing'))) `
        'the missing source key did not use the Chinese diagnostic'

    # --- compose: a fresh home produces exactly the managed block ----------
    $scenarioHome = New-Scenario 'compose-fresh'
    $run = Invoke-TestCapture { Invoke-PlasticineGithubSshConfigApply -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the fresh compose failed: $($run.Message)"
    $configPath = Join-Path $scenarioHome '.ssh\config'
    Assert-Equal $block (Get-TestText $configPath) 'a fresh compose did not write exactly the managed block'
    Assert-True ($run.Output -match 'composed') 'the fresh compose was not reported'
    Assert-True ((Get-Acl -LiteralPath $configPath).AreAccessRulesProtected) 'the composed config is not owner-only'
    Assert-True ((Get-Acl -LiteralPath (Join-Path $scenarioHome '.ssh')).AreAccessRulesProtected) 'the composed ~/.ssh is not owner-only'
    Assert-Equal 0 (Get-BackupFiles -HomeDirectory $scenarioHome).Count 'a fresh compose created a pre-managed backup'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $scenarioHome '.ssh\config.d\00-plasticine-github.conf'))) `
        'the compose step wrote the chezmoi-managed fragment'

    # --- compose: Owner bytes outside the block are preserved byte for byte ---
    $scenarioHome = New-Scenario 'compose-bytes'
    $sshDirectory = Join-Path $scenarioHome '.ssh'
    New-Item -ItemType Directory -Path $sshDirectory -Force | Out-Null
    $ownerText = "# owner rules`r`nHost example.com`r`n    User someone`r`n"
    $ownerBytes = [byte[]](@([Text.Encoding]::ASCII.GetBytes($ownerText)) + @(0xE4, 0xB8, 0xAD, 0xFF) + @([Text.Encoding]::ASCII.GetBytes("`r`n")))
    [IO.File]::WriteAllBytes((Join-Path $sshDirectory 'config'), $ownerBytes)
    $run = Invoke-TestCapture { Invoke-PlasticineGithubSshConfigApply -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the compose over Owner bytes failed: $($run.Message)"
    $blockBytes = (Get-PlasticineLatin1Encoding).GetBytes($block)
    $expectedBytes = [byte[]]($blockBytes + $ownerBytes)
    Assert-BytesEqual $expectedBytes ([IO.File]::ReadAllBytes((Join-Path $sshDirectory 'config'))) `
        'the compose did not preserve the Owner bytes exactly'
    $backupFiles = @(Get-BackupFiles -HomeDirectory $scenarioHome)
    Assert-Equal 1 $backupFiles.Count 'the first managed write did not back up the pre-managed config'
    Assert-BytesEqual $ownerBytes ([IO.File]::ReadAllBytes($backupFiles[0].FullName)) `
        'the pre-managed backup lost bytes'
    Assert-True ((Get-Acl -LiteralPath $backupFiles[0].FullName).AreAccessRulesProtected) `
        'the pre-managed backup is not owner-only'

    # --- compose: idempotent, and the first backup still wins --------------
    $composedHash = (Get-FileHash -LiteralPath (Join-Path $sshDirectory 'config') -Algorithm SHA256).Hash
    $run = Invoke-TestCapture { Invoke-PlasticineGithubSshConfigApply -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the second compose failed: $($run.Message)"
    Assert-True ($run.Output -match 'already up to date') 'the second compose was not reported as up to date'
    Assert-Equal $composedHash (Get-FileHash -LiteralPath (Join-Path $sshDirectory 'config') -Algorithm SHA256).Hash `
        'the second compose rewrote an up-to-date config'
    Assert-Equal 1 @(Get-BackupFiles -HomeDirectory $scenarioHome).Count 'the second compose added a backup'
    $rewrittenBytes = [Text.Encoding]::ASCII.GetBytes("# rewritten`r`nHost example.com`r`n")
    [IO.File]::WriteAllBytes((Join-Path $sshDirectory 'config'), $rewrittenBytes)
    $run = Invoke-TestCapture { Invoke-PlasticineGithubSshConfigApply -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the compose after an Owner rewrite failed: $($run.Message)"
    $backupFiles = @(Get-BackupFiles -HomeDirectory $scenarioHome)
    Assert-Equal 1 $backupFiles.Count 'the rewrite created a second backup'
    Assert-BytesEqual $ownerBytes ([IO.File]::ReadAllBytes($backupFiles[0].FullName)) `
        'the first backup was overwritten after an Owner rewrite'
    Assert-BytesEqual ([byte[]]($blockBytes + $rewrittenBytes)) ([IO.File]::ReadAllBytes((Join-Path $sshDirectory 'config'))) `
        'the composed config after a rewrite is not the block plus the new Owner bytes'

    # --- compose: damaged marker, conflicting rules and candidate checks stop ---
    $scenarioHome = New-Scenario 'compose-damaged'
    $configPath = Write-OwnerConfig -HomeDirectory $scenarioHome -Text ($beginMarker + "`nHost x`n")
    $before = [IO.File]::ReadAllBytes($configPath)
    $run = Invoke-TestCapture { Invoke-PlasticineGithubSshConfigApply -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'compose accepted a damaged marker block'
    Assert-True ($run.Error.Contains((Get-PlasticineGithubSshMessage -Key 'ManagedBlockDamaged'))) `
        'the damaged block did not use the Chinese diagnostic'
    Assert-BytesEqual $before ([IO.File]::ReadAllBytes($configPath)) 'the damaged block was modified'
    Assert-Equal 0 (Get-BackupFiles -HomeDirectory $scenarioHome).Count 'a damaged block created a backup'

    $scenarioHome = New-Scenario 'compose-conflict'
    $configPath = Write-OwnerConfig -HomeDirectory $scenarioHome -Text "Host github.com`n    HostName internal.example.invalid`n"
    $before = [IO.File]::ReadAllBytes($configPath)
    $run = Invoke-TestCapture { Invoke-PlasticineGithubSshConfigApply -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'compose accepted a conflicting existing rule'
    Assert-True ($run.Error.Contains((Get-PlasticineGithubSshMessage -Key 'Conflict'))) `
        'the conflicting rule did not use the Chinese diagnostic'
    Assert-BytesEqual $before ([IO.File]::ReadAllBytes($configPath)) 'the conflicting config was modified'

    $candidateCases = [ordered]@{
        'identity'       = 'IdentityConflict'
        'identity-count' = 'IdentityConflict'
        'user'           = 'CandidateConflict'
        'host'           = 'CandidateConflict'
        'identitiesonly' = 'CandidateConflict'
    }
    foreach ($caseName in $candidateCases.Keys) {
        $scenarioHome = New-Scenario ('compose-candidate-' + $caseName)
        $configPath = Write-OwnerConfig -HomeDirectory $scenarioHome -Text "# owner`nHost example.com`n"
        $before = [IO.File]::ReadAllBytes($configPath)
        $env:PLASTICINE_TEST_SSH_CANDIDATE_CONFLICT = $caseName
        $run = Invoke-TestCapture { Invoke-PlasticineGithubSshConfigApply -HomeDirectory $scenarioHome }
        Clear-ScenarioEnvironment
        $env:PLASTICINE_TEST_SSH_CALLS = $callsFile
        $expectedKey = $candidateCases[$caseName]
        Assert-True $run.Threw "a candidate conflict ($caseName) was accepted"
        Assert-True ($run.Error.Contains((Get-PlasticineGithubSshMessage -Key $expectedKey))) `
            "the candidate conflict ($caseName) did not use the Chinese diagnostic"
        Assert-BytesEqual $before ([IO.File]::ReadAllBytes($configPath)) "the candidate conflict ($caseName) modified the config"
    }

    $scenarioHome = New-Scenario 'compose-unparseable'
    $configPath = Write-OwnerConfig -HomeDirectory $scenarioHome -Text "Host broken-host`n"
    $before = [IO.File]::ReadAllBytes($configPath)
    $env:PLASTICINE_TEST_SSH_FAIL_CONFIG = 'Host broken-host'
    $run = Invoke-TestCapture { Invoke-PlasticineGithubSshConfigApply -HomeDirectory $scenarioHome }
    Clear-ScenarioEnvironment
    $env:PLASTICINE_TEST_SSH_CALLS = $callsFile
    Assert-True $run.Threw 'compose accepted an unparseable config'
    Assert-True ($run.Error.Contains((Get-PlasticineGithubSshMessage -Key 'ConfigUnparseable'))) `
        'the unparseable config did not use the Chinese diagnostic'
    Assert-BytesEqual $before ([IO.File]::ReadAllBytes($configPath)) 'the unparseable config was modified'

    $scenarioHome = New-Scenario 'compose-shape-junction'
    $junctionTarget = New-TestDirectory 'compose-junction-target'
    New-Item -ItemType Junction -Path (Join-Path $scenarioHome '.ssh') -Target $junctionTarget -ErrorAction Stop | Out-Null
    $run = Invoke-TestCapture { Invoke-PlasticineGithubSshConfigApply -HomeDirectory $scenarioHome }
    Assert-True $run.Threw 'compose accepted a junction at ~/.ssh'
    Assert-True ($run.Error -match 'must be a regular directory') 'the junction was not reported as an irregular directory'

    # --- connection test: authentication and network results stay separate ---
    $scenarioHome = New-KeyedScenario -Name 'connect-success' -KeyPath $sourceKey
    $env:PLASTICINE_TEST_SSH_MESSAGE = "Hi there! You've successfully authenticated, but GitHub does not provide shell access."
    $env:PLASTICINE_TEST_SSH_EXIT = '0'
    $run = Invoke-TestCapture { Invoke-PlasticineGithubSshConnectionTest -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the successful connection test threw: $($run.Message)"
    Assert-Equal 'authenticated' $run.Value.Status 'the successful connection test was not classified as authenticated'
    Assert-Equal 0 $run.Value.ExitCode 'the successful connection test returned a failure exit code'
    Assert-True ($run.Output -match 'authentication succeeded') 'the successful connection test was not reported'
    $allCalls = @(Get-Calls)
    Assert-True ($allCalls.Count -ge 1) 'the successful connection test did not start ssh'
    $lastCall = [string]$allCalls[$allCalls.Count - 1]
    foreach ($expectedArgument in @('-T', 'BatchMode=yes', 'ConnectTimeout=10', 'StrictHostKeyChecking=accept-new', 'git@github.com')) {
        Assert-True ($lastCall.Contains($expectedArgument)) "the connection test did not pass $expectedArgument"
    }
    Clear-ScenarioEnvironment
    $env:PLASTICINE_TEST_SSH_CALLS = $callsFile

    $scenarioHome = New-KeyedScenario -Name 'connect-authentication' -KeyPath $sourceKey
    $env:PLASTICINE_TEST_SSH_MESSAGE = 'git@github.com: Permission denied (publickey).'
    $env:PLASTICINE_TEST_SSH_EXIT = '255'
    $run = Invoke-TestCapture { Invoke-PlasticineGithubSshConnectionTest -HomeDirectory $scenarioHome }
    Assert-Equal 'authentication-rejected' $run.Value.Status 'an authentication rejection was misclassified'
    Assert-Equal 1 $run.Value.ExitCode 'the authentication rejection did not fail the probe'
    Assert-True ($run.Error.Contains((Get-PlasticineGithubSshMessage -Key 'AuthRejected'))) `
        'the authentication rejection did not use the Chinese diagnostic'
    Assert-True (-not $run.Error.Contains((Get-PlasticineGithubSshMessage -Key 'NetworkFailure'))) `
        'the authentication rejection was reported as a network failure'
    Clear-ScenarioEnvironment
    $env:PLASTICINE_TEST_SSH_CALLS = $callsFile

    $scenarioHome = New-KeyedScenario -Name 'connect-network' -KeyPath $sourceKey
    $env:PLASTICINE_TEST_SSH_MESSAGE = 'ssh: connect to host github.com port 22: Connection timed out'
    $env:PLASTICINE_TEST_SSH_EXIT = '255'
    $run = Invoke-TestCapture { Invoke-PlasticineGithubSshConnectionTest -HomeDirectory $scenarioHome }
    Assert-Equal 'network-failure' $run.Value.Status 'a network failure was misclassified'
    Assert-Equal 1 $run.Value.ExitCode 'the network failure did not fail the probe'
    Assert-True ($run.Error.Contains((Get-PlasticineGithubSshMessage -Key 'NetworkFailure'))) `
        'the network failure did not use the Chinese diagnostic'
    Assert-True (-not $run.Error.Contains((Get-PlasticineGithubSshMessage -Key 'AuthRejected'))) `
        'the network failure was reported as an authentication failure'
    Clear-ScenarioEnvironment
    $env:PLASTICINE_TEST_SSH_CALLS = $callsFile

    $scenarioHome = New-KeyedScenario -Name 'connect-unclassified' -KeyPath $sourceKey
    $env:PLASTICINE_TEST_SSH_MESSAGE = 'something completely unexpected happened'
    $env:PLASTICINE_TEST_SSH_EXIT = '255'
    $run = Invoke-TestCapture { Invoke-PlasticineGithubSshConnectionTest -HomeDirectory $scenarioHome }
    Assert-Equal 'unclassified' $run.Value.Status 'an unclassifiable failure was misclassified'
    Assert-True ($run.Error.Contains((Get-PlasticineGithubSshMessage -Key 'UnknownTestFailure'))) `
        'the unclassifiable failure did not use the Chinese diagnostic'
    Clear-ScenarioEnvironment
    $env:PLASTICINE_TEST_SSH_CALLS = $callsFile

    $scenarioHome = New-KeyedScenario -Name 'connect-unexpected' -KeyPath $sourceKey
    $env:PLASTICINE_TEST_SSH_MESSAGE = 'Welcome to the fixture'
    $env:PLASTICINE_TEST_SSH_EXIT = '0'
    $run = Invoke-TestCapture { Invoke-PlasticineGithubSshConnectionTest -HomeDirectory $scenarioHome }
    Assert-Equal 'unexpected' $run.Value.Status 'a zero exit without the success marker was misclassified'
    Assert-Equal 1 $run.Value.ExitCode 'the unexpected result was reported as success'
    Assert-True ($run.Error.Contains((Get-PlasticineGithubSshMessage -Key 'TestUnexpected'))) `
        'the unexpected result did not use the Chinese diagnostic'
    Clear-ScenarioEnvironment
    $env:PLASTICINE_TEST_SSH_CALLS = $callsFile

    $scenarioHome = New-Scenario 'connect-skipped'
    $run = Invoke-TestCapture { Invoke-PlasticineGithubSshConnectionTest -HomeDirectory $scenarioHome }
    Assert-True (-not $run.Threw) "the skipped connection test threw: $($run.Message)"
    Assert-Equal 'skipped' $run.Value.Status 'a keyless home did not skip the connection test'
    Assert-Equal 0 $run.Value.ExitCode 'a skipped connection test returned a failure exit code'
    Assert-True ($run.Output -match 'skipped') 'the skipped connection test was not reported'
    Assert-Equal 0 @(Get-Calls).Count 'a skipped connection test started ssh'

    # --- plan and preview: observation only, actions explained ------------
    $scenarioHome = New-Scenario 'plan-fresh'
    $env:PLASTICINE_GITHUB_SSH_KEY = $sourceKey
    $plan = Get-PlasticineGithubSshPlan -HomeDirectory $scenarioHome
    Assert-Equal (Join-Path $scenarioHome '.ssh\config') $plan.ConfigPath 'the plan did not target ~/.ssh/config'
    Assert-Equal (Join-Path $scenarioHome '.ssh\id_github') $plan.KeyPath 'the plan did not target ~/.ssh/id_github'
    Assert-Equal $sshFixture $plan.SshExecutable 'the plan did not expose the system OpenSSH seam'
    Assert-True $plan.OpenSshAvailable 'a resolvable OpenSSH client was reported as missing'
    Assert-True $plan.ConfigChanged 'a fresh config was not reported as changed'
    Assert-Equal 'install' $plan.KeyAction 'a missing key was not planned as an installation'
    Assert-True (-not $plan.TestRequested) 'the connection test was requested without opt-in'
    $preview = Invoke-TestCapture { Write-PlasticineGithubSshPreview -Plan $plan }
    Assert-True (-not $preview.Threw) "the preview failed: $($preview.Message)"
    foreach ($expectedPreviewText in @(
            'never printed',
            'network',
            'DACL',
            'connection test',
            'managed fragment',
            'compose',
            $plan.ConfigPath,
            $plan.KeyPath)) {
        Assert-True ($preview.Output.Contains($expectedPreviewText)) "the preview is missing: $expectedPreviewText"
    }
    Assert-True (-not $preview.Error) 'the preview wrote to stderr for a valid plan'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $scenarioHome '.ssh'))) 'the preview created ~/.ssh'
    Clear-ScenarioEnvironment
    $env:PLASTICINE_TEST_SSH_CALLS = $callsFile

    $scenarioHome = New-KeyedScenario -Name 'plan-retain' -KeyPath $sourceKey
    $env:PLASTICINE_GITHUB_SSH_KEY = $sourceKey
    $plan = Get-PlasticineGithubSshPlan -HomeDirectory $scenarioHome
    Assert-Equal 'retain' $plan.KeyAction 'a matching existing key was not planned as retained'
    $preview = Invoke-TestCapture { Write-PlasticineGithubSshPreview -Plan $plan }
    Assert-True (-not $preview.Threw) "the retain preview failed: $($preview.Message)"
    Assert-True ($preview.Output -match 'matches the supplied key') 'the retain preview lost the reuse explanation'
    Clear-ScenarioEnvironment
    $env:PLASTICINE_TEST_SSH_CALLS = $callsFile

    $scenarioHome = New-KeyedScenario -Name 'plan-conflict' -KeyPath $otherKey
    $env:PLASTICINE_GITHUB_SSH_KEY = $sourceKey
    $plan = Get-PlasticineGithubSshPlan -HomeDirectory $scenarioHome
    Assert-Equal 'conflict' $plan.KeyAction 'an unapproved different key was not planned as a conflict'
    $preview = Invoke-TestCapture { Write-PlasticineGithubSshPreview -Plan $plan }
    Assert-True $preview.Threw 'the conflicting key preview reported success'
    Assert-True ($preview.Error.Contains((Get-ExpectedDiagnostic -Key 'TargetKeyUnapproved' -Argument @($plan.KeyPath)))) `
        'the conflicting key preview did not use the Chinese diagnostic'
    Clear-ScenarioEnvironment
    $env:PLASTICINE_TEST_SSH_CALLS = $callsFile

    $scenarioHome = New-KeyedScenario -Name 'plan-replace' -KeyPath $otherKey
    $env:PLASTICINE_GITHUB_SSH_KEY = $sourceKey
    $env:PLASTICINE_REPLACE_GITHUB_SSH_KEY = '1'
    $env:PLASTICINE_GITHUB_SSH_TEST = '1'
    $plan = Get-PlasticineGithubSshPlan -HomeDirectory $scenarioHome
    Assert-Equal 'replace' $plan.KeyAction 'an approved replacement was not planned as replacement'
    Assert-True $plan.ReplaceApproved 'the approved replacement flag was lost'
    Assert-True $plan.TestRequested 'the requested connection test was not observed'
    $preview = Invoke-TestCapture { Write-PlasticineGithubSshPreview -Plan $plan }
    Assert-True (-not $preview.Threw) "the replace preview failed: $($preview.Message)"
    Assert-True ($preview.Output -match 'approved replacement') 'the replace preview lost the backup explanation'
    Assert-True ($preview.Output -match 'requested') 'the preview lost the connection-test request'
    Clear-ScenarioEnvironment
    $env:PLASTICINE_TEST_SSH_CALLS = $callsFile

    $scenarioHome = New-Scenario 'plan-damaged'
    Write-OwnerConfig -HomeDirectory $scenarioHome -Text ($beginMarker + "`nHost x`n") | Out-Null
    $env:PLASTICINE_GITHUB_SSH_KEY = $sourceKey
    $plan = Get-PlasticineGithubSshPlan -HomeDirectory $scenarioHome
    Assert-True $plan.Config.Damaged 'a damaged marker block was not observed by the plan'
    $preview = Invoke-TestCapture { Write-PlasticineGithubSshPreview -Plan $plan }
    Assert-True $preview.Threw 'the damaged-block preview reported success'
    Assert-True ($preview.Error.Contains((Get-PlasticineGithubSshMessage -Key 'ManagedBlockDamaged'))) `
        'the damaged-block preview did not use the Chinese diagnostic'
    Clear-ScenarioEnvironment
    $env:PLASTICINE_TEST_SSH_CALLS = $callsFile

    $scenarioHome = New-Scenario 'plan-missing-openssh'
    $script:PlasticineSshExecutable = $null
    $script:PlasticineSshKeygenExecutable = $null
    $script:PlasticineOpenSshDirectoryOverride = New-TestDirectory 'empty-openssh'
    try {
        $plan = Get-PlasticineGithubSshPlan -HomeDirectory $scenarioHome
        Assert-True (-not $plan.OpenSshAvailable) 'a missing system OpenSSH client was reported as available'
        Assert-True ($null -eq $plan.SshExecutable) 'a missing ssh resolved to a path'
        $preview = Invoke-TestCapture { Write-PlasticineGithubSshPreview -Plan $plan }
        Assert-True $preview.Threw 'the missing-OpenSSH preview reported success'
        Assert-True ($preview.Error.Contains((Get-PlasticineGithubSshMessage -Key 'OpenSshMissing'))) `
            'the missing OpenSSH client did not produce the Chinese guidance'
        $resolution = Invoke-TestCapture { Resolve-PlasticineGithubSshExecutable 'ssh' }
        Assert-True $resolution.Threw 'resolving a missing system ssh reported success'
        Assert-True ($resolution.Error.Contains((Get-PlasticineGithubSshMessage -Key 'OpenSshMissing'))) `
            'the resolver did not stop with the Chinese guidance'
        $optional = Resolve-PlasticineGithubSshExecutable 'ssh' -Optional
        Assert-True ($null -eq $optional) 'the optional resolver returned a path for a missing client'
    } finally {
        $script:PlasticineSshExecutable = $sshFixture
        $script:PlasticineSshKeygenExecutable = $keygenFixture
        $script:PlasticineOpenSshDirectoryOverride = $null
    }

    # --- resolver: a non-system ssh.exe on PATH is never accepted ---------
    $systemSsh = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe'
    if (Test-Path -LiteralPath $systemSsh -PathType Leaf) {
        $fakeBin = New-TestDirectory 'fake-ssh-bin'
        Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') `
            -Destination (Join-Path $fakeBin 'ssh.exe') -Force -ErrorAction Stop
        $env:PATH = $fakeBin + ';' + $savedPath
        # The seam shortcuts resolution, so it is cleared to exercise the real
        # resolver against PATH.
        $script:PlasticineSshExecutable = $null
        try {
            $resolved = Resolve-PlasticineGithubSshExecutable 'ssh'
            Assert-Equal ([IO.Path]::GetFullPath($systemSsh)) $resolved `
                'the resolver accepted a non-system ssh.exe from PATH'
        } finally {
            $env:PATH = $savedPath
            $script:PlasticineSshExecutable = $sshFixture
        }
    }

    Complete-Test 'windows ssh tests passed'
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
} finally {
    $script:PlasticineSshExecutable = $savedSshExecutable
    $script:PlasticineSshKeygenExecutable = $savedKeygenExecutable
    $script:PlasticineOpenSshDirectoryOverride = $savedOpenSshDirectoryOverride
    $env:PATH = $savedPath
    $env:USERPROFILE = $savedUserProfile
    $env:HOME = $savedHome
    foreach ($name in $scenarioEnvironmentNames) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
    Remove-Item -LiteralPath $PlasticineTestRoot -Recurse -Force -ErrorAction SilentlyContinue
}
