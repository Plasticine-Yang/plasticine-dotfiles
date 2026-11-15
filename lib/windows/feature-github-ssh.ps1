# The github-ssh Feature for the Windows route. The Unix route owns the same
# contract through private_dot_ssh/modify_private_config and the
# github-ssh-config-validation template: ~/.ssh/config keeps a managed marker
# block that includes the chezmoi-managed fragment, the private key lives at
# ~/.ssh/id_github with POSIX 600, and the post-apply probe is opt-in.
#
# Windows cannot execute the Unix modify_ script, so this module composes
# ~/.ssh/config itself during apply. ssh and ssh-keygen are resolved from the
# system OpenSSH installation only and invoked through test seams; chmod becomes
# the owner-only DACL from acl.ps1; backups and atomic publication reuse
# config-apply.ps1.
#
# This file is ASCII only: Windows PowerShell 5.1 decodes BOM-less scripts with
# the ANSI code page, so the Chinese diagnostics are stored as \uXXXX escapes
# and decoded at runtime (see Get-PlasticineGithubSshMessage).

if (-not (Get-Command Write-PlasticineLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'common.ps1')
}
if (-not (Get-Command Assert-PlasticineConfigFile -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'config-apply.ps1')
}
if (-not (Get-Command Set-PlasticineOwnerOnlyAcl -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'acl.ps1')
}
if (-not (Get-Command Publish-PlasticineNewFile -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'publish.ps1')
}
if (Get-Command Get-PlasticineGithubSshPlan -ErrorAction SilentlyContinue) { return }

# Test seams: suites replace both executables so no test starts the real
# OpenSSH client, and can point the resolver at an empty directory to observe
# the missing-client branch without depending on the host installation.
if (-not (Test-Path Variable:PlasticineSshExecutable)) { $PlasticineSshExecutable = $null }
if (-not (Test-Path Variable:PlasticineSshKeygenExecutable)) { $PlasticineSshKeygenExecutable = $null }
if (-not (Test-Path Variable:PlasticineOpenSshDirectoryOverride)) { $PlasticineOpenSshDirectoryOverride = $null }

$PlasticineGithubSshBeginMarker = '# BEGIN plasticine-dotfiles github-ssh'
$PlasticineGithubSshEndMarker = '# END plasticine-dotfiles github-ssh'
$PlasticineGithubSshIncludeLine = 'Include ~/.ssh/config.d/00-plasticine-github.conf'
$PlasticineGithubSshFragmentLeaf = '00-plasticine-github.conf'
$PlasticineGithubSshKeyLeaf = 'id_github'
$PlasticineGithubSshBackupLabel = 'github-ssh'
$PlasticineGithubSshExpectedIdentityFile = '~/.ssh/id_github'

# The user-facing diagnostics mirror the Unix route's Chinese text. They are
# stored as \uXXXX escapes so this file stays ASCII; the escapes are decoded by
# Get-PlasticineGithubSshMessage below. {0} is filled in by the caller.
function Get-PlasticineGithubSshMessage {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Key)
    $messages = @{
        ManagedBlockDamaged = 'GitHub SSH \u6258\u7BA1\u533A\u5757\u635F\u574F\u6216\u91CD\u590D\uFF0C\u8BF7\u5148\u624B\u52A8\u4FEE\u590D ~/.ssh/config\u3002'
        ConfigUnparseable = '\u73B0\u6709 ~/.ssh/config \u65E0\u6CD5\u88AB OpenSSH \u89E3\u6790\uFF0C\u672A\u8FDB\u884C\u4FEE\u6539\u3002'
        Conflict = '\u5DF2\u6709 SSH \u89C4\u5219\u4F1A\u6539\u53D8 github.com \u7684\u7528\u6237\u3001\u4E3B\u673A\u6216\u79C1\u94A5\uFF0C\u672A\u8FDB\u884C\u4FEE\u6539\u3002'
        IdentityConflict = '\u5DF2\u6709 SSH \u89C4\u5219\u4E3A github.com \u914D\u7F6E\u4E86\u5176\u4ED6 IdentityFile\uFF0C\u672A\u8FDB\u884C\u4FEE\u6539\u3002'
        CandidateConflict = '\u5DF2\u6709 SSH \u89C4\u5219\u4E0E GitHub \u914D\u7F6E\u51B2\u7A81\uFF0C\u672A\u8FDB\u884C\u4FEE\u6539\u3002'
        KeyShape = '\u76EE\u6807\u79C1\u94A5\u4E0D\u662F\u666E\u901A\u6587\u4EF6\uFF1A{0}'
        SourceKeyShape = '\u79C1\u94A5\u5FC5\u987B\u662F\u666E\u901A\u6587\u4EF6\u4E14\u4E0D\u80FD\u662F\u7B26\u53F7\u94FE\u63A5\uFF1A{0}'
        SourceKeyEmpty = '\u79C1\u94A5\u6587\u4EF6\u4E0D\u80FD\u4E3A\u7A7A\uFF1A{0}'
        SourceKeyUnsupported = '\u6307\u5B9A\u6587\u4EF6\u4E0D\u662F\u53D7\u652F\u6301\u7684 SSH \u79C1\u94A5\uFF1A{0}'
        SourceKeyChanged = '\u79C1\u94A5\u5728\u786E\u8BA4\u540E\u53D1\u751F\u53D8\u5316\uFF0C\u8BF7\u91CD\u65B0\u8FD0\u884C chezmoi init\uFF1A{0}'
        TargetKeyUnapproved = '\u76EE\u6807\u79C1\u94A5\u672A\u7ECF\u786E\u8BA4\u6216\u786E\u8BA4\u540E\u53D1\u751F\u53D8\u5316\uFF0C\u8BF7\u91CD\u65B0\u8FD0\u884C chezmoi init\uFF1A{0}'
        CopiedKeyChanged = '\u590D\u5236\u79C1\u94A5\u65F6\u6E90\u6587\u4EF6\u53D1\u751F\u53D8\u5316\uFF0C\u672A\u66FF\u6362\u76EE\u6807\u79C1\u94A5\u3002'
        FingerprintMissing = 'GitHub SSH \u79C1\u94A5\u6307\u7EB9\u7F3A\u5931\uFF0C\u8BF7\u91CD\u65B0\u8FD0\u884C chezmoi init \u4EE5\u786E\u8BA4\u79C1\u94A5\u3002'
        InstalledKeyUnreadable = '\u5B89\u88C5\u540E\u7684 GitHub SSH \u79C1\u94A5\u65E0\u6CD5\u901A\u8FC7 ssh-keygen \u6821\u9A8C\uFF0C\u8BF7\u68C0\u67E5\u6587\u4EF6\u5B8C\u6574\u6027\uFF1A{0}'
        KeySourceMissing = '\u672A\u63D0\u4F9B GitHub SSH \u79C1\u94A5\u8DEF\u5F84\uFF1B\u8BF7\u4F7F\u7528 -GithubSshKey \u6216 PLASTICINE_GITHUB_SSH_KEY \u6307\u5B9A\u79C1\u94A5\u3002'
        OpenSshMissing = '\u7CFB\u7EDF\u7F3A\u5C11 OpenSSH \u5BA2\u6237\u7AEF\uFF08ssh.exe \u4E0E ssh-keygen.exe\uFF09\uFF1A\u8BF7\u901A\u8FC7\u201C\u8BBE\u7F6E > \u5E94\u7528 > \u53EF\u9009\u529F\u80FD\u201D\u5B89\u88C5 OpenSSH \u5BA2\u6237\u7AEF\u540E\u91CD\u8BD5\uFF1B\u5B89\u88C5\u5668\u4E0D\u4F1A\u4EE3\u4E3A\u5B89\u88C5\uFF0C\u4E5F\u4E0D\u63A5\u53D7 Git \u6216 MSYS \u7684\u540C\u540D\u7A0B\u5E8F\u3002'
        SshNotSystem = '\u68C0\u6D4B\u5230\u975E\u7CFB\u7EDF OpenSSH \u7684 ssh \u7A0B\u5E8F\uFF08{0}\uFF09\uFF1B\u672C\u8DEF\u7EBF\u53EA\u4F7F\u7528 Windows \u7CFB\u7EDF\u81EA\u5E26\u7684 OpenSSH \u5BA2\u6237\u7AEF\u3002'
        PreviewBlocked = 'GitHub SSH \u8DEF\u7EBF\u5B58\u5728\u5FC5\u987B\u5148\u89E3\u51B3\u7684\u51B2\u7A81\uFF0C\u672A\u8FDB\u884C\u4FEE\u6539\uFF1B\u8BF7\u6309\u4E0A\u9762\u7684\u63D0\u793A\u4FEE\u590D\u540E\u91CD\u8BD5\u3002'
        AuthRejected = 'GitHub \u62D2\u7EDD\u4E86 SSH \u8BA4\u8BC1\uFF08authentication rejected\uFF09\uFF1A\u79C1\u94A5\u5DF2\u5B89\u88C5\uFF0C\u4F46\u53EF\u80FD\u5C1A\u672A\u6DFB\u52A0\u5230 GitHub \u8D26\u6237\uFF0C\u8BF7\u68C0\u67E5\u516C\u94A5\u4E0E\u8D26\u6237\u8BBE\u7F6E\u3002'
        NetworkFailure = '\u65E0\u6CD5\u8FDE\u63A5 github.com\uFF08network failure, not authentication\uFF09\uFF1A\u8FD9\u662F\u7F51\u7EDC\u95EE\u9898\u800C\u975E\u8BA4\u8BC1\u5931\u8D25\uFF1B\u8BF7\u68C0\u67E5\u7F51\u7EDC\u3001\u4EE3\u7406\u6216\u9632\u706B\u5899\u540E\u91CD\u8BD5\u3002'
        UnknownTestFailure = 'GitHub SSH \u8FDE\u63A5\u6D4B\u8BD5\u672A\u901A\u8FC7\u4E14\u65E0\u6CD5\u5F52\u7C7B\uFF08unclassified failure\uFF09\uFF1B\u8BF7\u67E5\u770B\u4E0A\u9762\u7684 OpenSSH \u539F\u59CB\u8F93\u51FA\uFF0C\u7F51\u7EDC\u95EE\u9898\u4E0D\u7B49\u4E8E\u8BA4\u8BC1\u5931\u8D25\u3002'
        TestUnexpected = 'GitHub SSH \u8FDE\u63A5\u6D4B\u8BD5\u8FD4\u56DE\u6210\u529F\u9000\u51FA\u7801\u4F46\u6CA1\u6709\u8BA4\u8BC1\u6210\u529F\u6807\u8BB0\uFF08unexpected result\uFF09\uFF1B\u8BF7\u67E5\u770B\u4E0A\u9762\u7684 OpenSSH \u539F\u59CB\u8F93\u51FA\u3002'
    }
    if (-not $messages.ContainsKey($Key)) {
        Stop-Plasticine "github-ssh: unknown diagnostic key: $Key"
    }
    return [regex]::Unescape([string]$messages[$Key])
}

function Stop-PlasticineGithubSsh {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Key,
        [object[]]$Argument = @()
    )
    $message = Get-PlasticineGithubSshMessage -Key $Key
    if (@($Argument).Count -gt 0) {
        $message = $message -f $Argument
    }
    Stop-Plasticine ('github-ssh: ' + $message)
}

function Get-PlasticineOpenSshDirectory {
    if ($null -ne $PlasticineOpenSshDirectoryOverride) {
        return [string]$PlasticineOpenSshDirectoryOverride
    }
    $systemRoot = $env:SystemRoot
    if (-not $systemRoot) {
        $systemRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    }
    if (-not $systemRoot) { return $null }
    return (Join-Path $systemRoot 'System32\OpenSSH')
}

# Only the system OpenSSH client is authorized. The PATH lookup runs first so a
# healthy Machine PATH is honored, but a Git/MSYS ssh.exe is never accepted: the
# system absolute path is the only fallback, and its absence stops the route.
function Resolve-PlasticineGithubSshExecutable {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('ssh', 'ssh-keygen')][string]$Name,
        [switch]$Optional
    )
    $override = $null
    if ($Name -eq 'ssh') { $override = $PlasticineSshExecutable }
    else { $override = $PlasticineSshKeygenExecutable }
    if ($null -ne $override) {
        $text = [string]$override
        $usable = $false
        if ($text -and [IO.Path]::IsPathRooted($text)) {
            if (Test-Path -LiteralPath $text -PathType Leaf) { $usable = $true }
        }
        if (-not $usable) {
            if ($Optional) { return $null }
            Stop-PlasticineGithubSsh 'OpenSshMissing'
        }
        return [IO.Path]::GetFullPath($text)
    }

    $directory = Get-PlasticineOpenSshDirectory
    $executableName = $Name + '.exe'
    $absolute = $null
    if ($directory) { $absolute = Join-Path $directory $executableName }

    # The resolver is isolated from the host installation while a suite points
    # it at a disposable directory.
    if (-not $PlasticineOpenSshDirectoryOverride) {
        $resolved = Get-PlasticineCommandPath $executableName
        if ($resolved -and $directory) {
            $resolvedDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($resolved))
            $expectedDirectory = [IO.Path]::GetFullPath($directory)
            if ($resolvedDirectory -and $expectedDirectory -and
                ($resolvedDirectory.TrimEnd('\') -ieq $expectedDirectory.TrimEnd('\')) -and
                (Test-Path -LiteralPath $resolved -PathType Leaf)) {
                return [IO.Path]::GetFullPath($resolved)
            }
        }
        if ($absolute -and (Test-Path -LiteralPath $absolute -PathType Leaf)) {
            return [IO.Path]::GetFullPath($absolute)
        }
        if ($resolved) {
            if ($Optional) { return $null }
            Stop-PlasticineGithubSsh 'SshNotSystem' @($resolved)
        }
        if ($Optional) { return $null }
        Stop-PlasticineGithubSsh 'OpenSshMissing'
    }

    if ($absolute -and (Test-Path -LiteralPath $absolute -PathType Leaf)) {
        return [IO.Path]::GetFullPath($absolute)
    }
    if ($Optional) { return $null }
    Stop-PlasticineGithubSsh 'OpenSshMissing'
}

# ssh and ssh-keygen inherit the caller's environment, so a suite can replace
# them with fixture scripts; the seams are never exercised in production.
function Invoke-PlasticineGithubSshProcess {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Executable,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Argument = @(),
        [switch]$MergeError
    )
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $exitCode = 0
    $output = @()
    try {
        if ($MergeError) {
            $output = @(& $Executable @Argument 2>&1)
        } else {
            $output = @(& $Executable @Argument 2>$null)
        }
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($null -eq $exitCode) { $exitCode = 0 }
    $lines = @()
    foreach ($line in $output) {
        if ($null -eq $line) { continue }
        $lines += [string]$line
    }
    return [pscustomobject]@{
        ExitCode = [int]$exitCode
        Output   = $lines
    }
}

# ~/.ssh/config is not a chezmoi target on Windows: the apply scripts compose
# it. These paths are the complete Windows inventory of the route.
function Get-PlasticineGithubSshPaths {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory)
    $null = Assert-PlasticineAbsolutePath -Path $HomeDirectory -Name 'home directory'
    $homePath = [IO.Path]::GetFullPath($HomeDirectory)
    if ($homePath.Length -gt 3) { $homePath = $homePath.TrimEnd('\') }
    $sshDirectory = Join-Path $homePath '.ssh'
    return [pscustomobject]@{
        HomeDirectory   = $homePath
        SshDirectory    = $sshDirectory
        ConfigDirectory = Join-Path $sshDirectory 'config.d'
        ConfigPath      = Join-Path $sshDirectory 'config'
        FragmentPath    = Join-Path $sshDirectory ('config.d\' + $PlasticineGithubSshFragmentLeaf)
        KeyPath         = Join-Path $sshDirectory $PlasticineGithubSshKeyLeaf
        BackupDirectory = Join-Path $homePath '.plasticine\backups\github-ssh'
    }
}

# The managed fragment is the same seven lines the Unix route installs through
# the github-ssh-fragment template. Windows checkouts carry CRLF, so the
# constant uses CRLF; the byte comparison lives in tests/windows/ssh.ps1.
function Get-PlasticineGithubSshFragmentText {
    return ("Host github.com`r`n    HostName github.com`r`n    User git`r`n    IdentityFile ~/.ssh/id_github`r`n    IdentitiesOnly yes`r`n`r`nHost *`r`n")
}

function Get-PlasticineGithubSshLineEnding {
    param([AllowEmptyString()][string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $index = $Text.IndexOf([char]10)
    if ($index -lt 1) { return "`r`n" }
    if ($Text[$index - 1] -eq [char]13) { return "`r`n" }
    return "`n"
}

function Get-PlasticineGithubSshManagedBlock {
    param([string]$LineEnding = '')
    if (-not $LineEnding) { $LineEnding = "`r`n" }
    return ($PlasticineGithubSshBeginMarker + $LineEnding +
        $PlasticineGithubSshIncludeLine + $LineEnding +
        $PlasticineGithubSshEndMarker + $LineEnding)
}

# Mirrors the awk program in github-ssh-config-validation: the marker pair must
# appear exactly once, nested or repeated markers are damage, and the Owner's
# bytes outside the block are preserved exactly.
function Get-PlasticineGithubSshManagedBlockState {
    param([AllowEmptyString()][string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $stripped = New-Object System.Text.StringBuilder
    $damaged = $false
    $hasMarker = $false
    $hasBlock = $false
    $inside = $false
    $seenBegin = $false
    $position = 0
    while ($position -lt $Text.Length) {
        $newline = $Text.IndexOf([char]10, $position)
        if ($newline -lt 0) {
            $lineEnd = $Text.Length
            $next = $Text.Length
        } else {
            $lineEnd = $newline
            $next = $newline + 1
        }
        $line = $Text.Substring($position, $lineEnd - $position)
        $lineValue = $line
        if ($lineValue.EndsWith("`r")) {
            $lineValue = $lineValue.Substring(0, $lineValue.Length - 1)
        }
        if ($lineValue -ceq $PlasticineGithubSshBeginMarker) {
            if ($inside -or $seenBegin) { $damaged = $true }
            $seenBegin = $true
            $hasMarker = $true
            $inside = $true
        } elseif ($lineValue -ceq $PlasticineGithubSshEndMarker) {
            $hasMarker = $true
            if (-not $inside) {
                $damaged = $true
            } else {
                $inside = $false
                $hasBlock = $true
            }
        } elseif (-not $inside) {
            [void]$stripped.Append($Text.Substring($position, $next - $position))
        }
        $position = $next
    }
    if ($inside) { $damaged = $true }
    if ($damaged) { $hasBlock = $false }
    return [pscustomobject]@{
        Damaged   = $damaged
        HasMarker = $hasMarker
        HasBlock  = $hasBlock
        Stripped  = $stripped.ToString()
    }
}

function Get-PlasticineGithubSshConfigState {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path)
    $null = Assert-PlasticineAbsolutePath -Path $Path -Name 'configuration path'
    $state = [pscustomobject]@{
        Path          = $Path
        Exists        = $false
        IsRegularFile = $false
        Damaged       = $false
        HasMarker     = $false
        HasBlock      = $false
        Text          = ''
        Stripped      = ''
    }
    $item = Get-PlasticineItem $Path
    if (-not $item) { return $state }
    $state.Exists = $true
    if ($item.PSIsContainer -or (Test-PlasticineReparsePoint $item)) { return $state }
    $state.IsRegularFile = $true
    $state.Text = Read-PlasticineConfigText -Path $Path
    $blockState = Get-PlasticineGithubSshManagedBlockState -Text $state.Text
    $state.Damaged = $blockState.Damaged
    $state.HasMarker = $blockState.HasMarker
    $state.HasBlock = $blockState.HasBlock
    $state.Stripped = $blockState.Stripped
    return $state
}

# The shape contract of the Unix run_before scripts: ~/.ssh and ~/.ssh/config.d
# are regular directories, the managed entries are regular files. An existing
# reparse point is a conflict, never something this route replaces.
function Assert-PlasticineGithubSshShapes {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory)
    $paths = Get-PlasticineGithubSshPaths -HomeDirectory $HomeDirectory
    $null = Assert-PlasticineConfigDirectory -Path $paths.SshDirectory -Label 'github-ssh'
    $null = Assert-PlasticineConfigDirectory -Path $paths.ConfigDirectory -Label 'github-ssh'
    $null = Assert-PlasticineConfigFile -Path $paths.ConfigPath -Label 'github-ssh'
    $null = Assert-PlasticineConfigFile -Path $paths.FragmentPath -Label 'github-ssh'
    $null = Assert-PlasticineConfigFile -Path $paths.KeyPath -Label 'github-ssh'
    return $paths
}

# ssh -G output is "keyword value" lines. The Unix route reads user, hostname,
# identityfile and identitiesonly with awk; the Windows route parses the same
# fields in PowerShell so the comparison stays byte-for-byte equivalent.
function ConvertFrom-PlasticineGithubSshGOutput {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Line = @())
    $values = @{}
    foreach ($entry in $Line) {
        $text = [string]$entry
        if (-not $text) { continue }
        $text = $text.TrimEnd([char]13)
        $text = $text.TrimStart()
        $space = $text.IndexOf([char]32)
        if ($space -lt 1) { continue }
        $keyword = $text.Substring(0, $space).ToLowerInvariant()
        $value = $text.Substring($space + 1).Trim()
        if (-not $values.ContainsKey($keyword)) {
            $values[$keyword] = New-Object System.Collections.ArrayList
        }
        [void]$values[$keyword].Add($value)
    }
    $user = ''
    if ($values.ContainsKey('user') -and $values['user'].Count -gt 0) { $user = [string]$values['user'][0] }
    $hostName = ''
    if ($values.ContainsKey('hostname') -and $values['hostname'].Count -gt 0) { $hostName = [string]$values['hostname'][0] }
    $identitiesOnly = ''
    if ($values.ContainsKey('identitiesonly') -and $values['identitiesonly'].Count -gt 0) {
        $identitiesOnly = [string]$values['identitiesonly'][0]
    }
    $identityFile = @()
    if ($values.ContainsKey('identityfile')) {
        foreach ($value in $values['identityfile']) { $identityFile += [string]$value }
    }
    return [pscustomobject]@{
        User           = $user
        HostName       = $hostName
        IdentitiesOnly = $identitiesOnly
        IdentityFile   = @($identityFile)
    }
}

function Invoke-PlasticineGithubSshG {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$SshExecutable,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ConfigPath
    )
    $result = Invoke-PlasticineGithubSshProcess -Executable $SshExecutable `
        -Argument @('-G', '-F', $ConfigPath, 'github.com')
    if ($result.ExitCode -ne 0) { return $null }
    return (ConvertFrom-PlasticineGithubSshGOutput -Line $result.Output)
}

function Get-PlasticineGithubSshDefaultEffectiveConfig {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$SshExecutable)
    # NUL is the Windows equivalent of /dev/null for -F.
    return (Invoke-PlasticineGithubSshG -SshExecutable $SshExecutable -ConfigPath 'NUL')
}

function Get-PlasticineGithubSshEffectiveConfigFromText {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$SshExecutable,
        [AllowEmptyString()][string]$Text
    )
    if ($null -eq $Text) { $Text = '' }
    $work = New-PlasticineTempDirectory 'plasticine-github-ssh'
    try {
        $configPath = Join-Path $work 'config'
        [IO.File]::WriteAllText($configPath, $Text, (Get-PlasticineLatin1Encoding))
        return (Invoke-PlasticineGithubSshG -SshExecutable $SshExecutable -ConfigPath $configPath)
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# The github-ssh-config-validation contract: strip the managed block first, then
# compare the remaining rules against the defaults from NUL. A rule that would
# change github.com's user (other than git), hostname or identity files is a
# conflict and nothing is modified.
function Assert-PlasticineGithubSshExistingConfigCompatible {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$SshExecutable,
        [AllowEmptyString()][string]$StrippedText
    )
    $default = Get-PlasticineGithubSshDefaultEffectiveConfig -SshExecutable $SshExecutable
    if (-not $default) { Stop-PlasticineGithubSsh 'ConfigUnparseable' }
    $existing = Get-PlasticineGithubSshEffectiveConfigFromText -SshExecutable $SshExecutable -Text $StrippedText
    if (-not $existing) { Stop-PlasticineGithubSsh 'ConfigUnparseable' }
    $userCompatible = ($existing.User -ceq $default.User) -or ($existing.User -ceq 'git')
    $hostCompatible = ($existing.HostName -ceq $default.HostName)
    $identityCompatible = ((@($existing.IdentityFile) -join "`n") -ceq (@($default.IdentityFile) -join "`n"))
    if (-not ($userCompatible -and $hostCompatible -and $identityCompatible)) {
        Stop-PlasticineGithubSsh 'Conflict'
    }
}

# Compose a candidate exactly like modify_private_config: the managed marker
# block (whose body is the Include line) followed by the Owner's bytes with the
# previous block removed.
function New-PlasticineGithubSshConfigCandidate {
    param([AllowEmptyString()][string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $blockState = Get-PlasticineGithubSshManagedBlockState -Text $Text
    if ($blockState.Damaged) { Stop-PlasticineGithubSsh 'ManagedBlockDamaged' }
    $lineEnding = Get-PlasticineGithubSshLineEnding -Text $Text
    return ((Get-PlasticineGithubSshManagedBlock -LineEnding $lineEnding) + $blockState.Stripped)
}

# The candidate is checked with ssh -G exactly like the Unix modify script. On a
# first apply chezmoi has not written ~/.ssh/config.d/00-plasticine-github.conf
# yet, so the expected fragment is staged in a disposable home for the duration
# of the check; USERPROFILE is what OpenSSH expands ~ against.
function Assert-PlasticineGithubSshCandidateEffective {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$SshExecutable,
        [AllowEmptyString()][string]$CandidateText
    )
    if ($null -eq $CandidateText) { $CandidateText = '' }
    $stagingHome = New-PlasticineTempDirectory 'plasticine-github-ssh-home'
    try {
        $stagingConfigDirectory = Join-Path $stagingHome '.ssh\config.d'
        New-Item -ItemType Directory -Path $stagingConfigDirectory -Force -ErrorAction Stop | Out-Null
        $stagingFragment = Join-Path $stagingConfigDirectory $PlasticineGithubSshFragmentLeaf
        [IO.File]::WriteAllText($stagingFragment, (Get-PlasticineGithubSshFragmentText), (Get-PlasticineLatin1Encoding))
        $candidatePath = Join-Path $stagingHome 'config'
        [IO.File]::WriteAllText($candidatePath, $CandidateText, (Get-PlasticineLatin1Encoding))
        $savedUserProfile = $env:USERPROFILE
        $savedHome = $env:HOME
        try {
            $env:USERPROFILE = $stagingHome
            $env:HOME = $stagingHome
            $effective = Invoke-PlasticineGithubSshG -SshExecutable $SshExecutable -ConfigPath $candidatePath
        } finally {
            $env:USERPROFILE = $savedUserProfile
            $env:HOME = $savedHome
        }
    } finally {
        Remove-Item -LiteralPath $stagingHome -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (-not $effective) { Stop-PlasticineGithubSsh 'ConfigUnparseable' }
    $identityFile = @($effective.IdentityFile)
    $singleIdentity = ''
    if ($identityFile.Count -eq 1) { $singleIdentity = [string]$identityFile[0] }
    if ($identityFile.Count -ne 1 -or $singleIdentity -cne $PlasticineGithubSshExpectedIdentityFile) {
        Stop-PlasticineGithubSsh 'IdentityConflict'
    }
    if ($effective.User -cne 'git' -or $effective.HostName -cne 'github.com' -or
        $effective.IdentitiesOnly -cne 'yes') {
        Stop-PlasticineGithubSsh 'CandidateConflict'
    }
}

# Pre-flight validation for run_before_00: shape, marker pairing and the
# effective-config comparison. Observation only.
function Assert-PlasticineGithubSshConfiguration {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory)
    Assert-PlasticineWindowsPlatform
    $paths = Assert-PlasticineGithubSshShapes -HomeDirectory $HomeDirectory
    $state = Get-PlasticineGithubSshConfigState -Path $paths.ConfigPath
    if ($state.Damaged) { Stop-PlasticineGithubSsh 'ManagedBlockDamaged' }
    $ssh = Resolve-PlasticineGithubSshExecutable 'ssh'
    Assert-PlasticineGithubSshExistingConfigCompatible -SshExecutable $ssh -StrippedText $state.Stripped
}

# First backup wins, exactly like the Unix journal: a rerun never overwrites the
# pristine pre-managed copy with an already-managed file.
function Save-PlasticineGithubSshConfigBackup {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory)
    $paths = Get-PlasticineGithubSshPaths -HomeDirectory $HomeDirectory
    $state = Get-PlasticineGithubSshConfigState -Path $paths.ConfigPath
    if (-not $state.Exists) { return $null }
    if ($state.HasMarker) { return $null }
    $backup = Save-PlasticineConfigBackup -Path $paths.ConfigPath `
        -BackupDirectory $paths.BackupDirectory -Label $PlasticineGithubSshBackupLabel
    if ($backup) {
        Write-PlasticineLog "github-ssh: backed up the pre-managed ~/.ssh/config before the first managed write: $backup"
    }
    return $backup
}

# The Windows replacement for private_dot_ssh/modify_private_config. Runs after
# the key installation: validate, re-check the candidate with ssh -G, back up on
# the first managed write, then publish atomically with an owner-only DACL while
# preserving every byte outside the managed block.
function Invoke-PlasticineGithubSshConfigApply {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory)
    Assert-PlasticineWindowsPlatform
    $paths = Get-PlasticineGithubSshPaths -HomeDirectory $HomeDirectory
    $null = Assert-PlasticineGithubSshShapes -HomeDirectory $HomeDirectory
    $state = Get-PlasticineGithubSshConfigState -Path $paths.ConfigPath
    if ($state.Damaged) { Stop-PlasticineGithubSsh 'ManagedBlockDamaged' }
    if ($state.Exists -and -not $state.IsRegularFile) {
        Stop-PlasticineConfig -Label 'github-ssh' -Message "$($paths.ConfigPath) must be a regular file."
    }
    $ssh = Resolve-PlasticineGithubSshExecutable 'ssh'
    Assert-PlasticineGithubSshExistingConfigCompatible -SshExecutable $ssh -StrippedText $state.Stripped
    $candidate = New-PlasticineGithubSshConfigCandidate -Text $state.Text
    Assert-PlasticineGithubSshCandidateEffective -SshExecutable $ssh -CandidateText $candidate

    if ($state.Exists -and (Test-PlasticineConfigTextEqual $state.Text $candidate)) {
        Set-PlasticineOwnerOnlyAcl -Path $paths.SshDirectory
        Set-PlasticineOwnerOnlyAcl -Path $paths.ConfigPath
        if (Get-PlasticineItem $paths.ConfigDirectory) {
            Set-PlasticineOwnerOnlyAcl -Path $paths.ConfigDirectory
        }
        Write-PlasticineLog "github-ssh: the managed ~/.ssh/config block is already up to date: $($paths.ConfigPath)"
        return
    }

    if ($state.Exists -and -not $state.HasMarker) {
        $null = Save-PlasticineGithubSshConfigBackup -HomeDirectory $HomeDirectory
    }
    $changed = Publish-PlasticineConfigFile -Path $paths.ConfigPath -Text $candidate `
        -Label $PlasticineGithubSshBackupLabel -OwnerOnly -OriginalText $state.Text
    Set-PlasticineOwnerOnlyAcl -Path $paths.SshDirectory
    Set-PlasticineOwnerOnlyAcl -Path $paths.ConfigPath
    if (Get-PlasticineItem $paths.ConfigDirectory) {
        Set-PlasticineOwnerOnlyAcl -Path $paths.ConfigDirectory
    }
    if (-not $changed) {
        Write-PlasticineLog "github-ssh: the managed ~/.ssh/config block is already up to date: $($paths.ConfigPath)"
        return
    }
    if ($state.HasBlock) {
        Write-PlasticineLog "github-ssh: updated the managed ~/.ssh/config block and preserved the Owner's rules: $($paths.ConfigPath)"
    } else {
        Write-PlasticineLog "github-ssh: composed ~/.ssh/config with the managed GitHub SSH block: $($paths.ConfigPath)"
    }
}

function Get-PlasticineGithubSshKeyFingerprint {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$KeygenExecutable,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path
    )
    $result = Invoke-PlasticineGithubSshProcess -Executable $KeygenExecutable -Argument @('-lf', $Path)
    if ($result.ExitCode -ne 0) { return $null }
    foreach ($line in @($result.Output)) {
        $text = ([string]$line).Trim()
        if (-not $text) { continue }
        $tokens = @($text -split '\s+')
        if ($tokens.Count -ge 2 -and $tokens[1]) { return [string]$tokens[1] }
        return $null
    }
    return $null
}

function Get-PlasticineGithubSshSourceKeyFirstLine {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path)
    $firstLine = ''
    $reader = $null
    $stream = [IO.File]::OpenRead($Path)
    try {
        $reader = New-Object System.IO.StreamReader($stream, (Get-PlasticineLatin1Encoding))
        $firstLine = [string]$reader.ReadLine()
    } finally {
        if ($reader) { $reader.Dispose() } else { $stream.Dispose() }
    }
    return $firstLine
}

# Installs the supplied private key at ~/.ssh/id_github. Existing keys are kept;
# a replacement needs the fingerprint approved during chezmoi init and backs up
# the current key first. The key bytes are never written to any stream.
function Install-PlasticineGithubSshKey {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$SourceKey,
        [AllowEmptyString()][string]$ExpectedFingerprint = '',
        [AllowEmptyString()][string]$ApprovedReplaceFingerprint = ''
    )
    Assert-PlasticineWindowsPlatform
    $paths = Get-PlasticineGithubSshPaths -HomeDirectory $HomeDirectory
    $keygen = Resolve-PlasticineGithubSshExecutable 'ssh-keygen'
    if (-not $ExpectedFingerprint) { Stop-PlasticineGithubSsh 'FingerprintMissing' }
    if (-not $SourceKey) { Stop-PlasticineGithubSsh 'KeySourceMissing' }

    $targetItem = Get-PlasticineItem $paths.KeyPath
    if ($targetItem -and ($targetItem.PSIsContainer -or (Test-PlasticineReparsePoint $targetItem))) {
        Stop-PlasticineGithubSsh 'KeyShape' @($paths.KeyPath)
    }
    $targetExists = [bool]$targetItem
    $targetFingerprint = ''
    if ($targetExists) {
        $observed = Get-PlasticineGithubSshKeyFingerprint -KeygenExecutable $keygen -Path $paths.KeyPath
        if ($observed) { $targetFingerprint = [string]$observed }
        if ($targetFingerprint -and $targetFingerprint -ceq $ExpectedFingerprint) {
            Set-PlasticineOwnerOnlyAcl -Path $paths.KeyPath
            Write-PlasticineLog "github-ssh: kept the existing private key at $($paths.KeyPath); its fingerprint already matches the supplied key."
            return
        }
    }

    $null = Assert-PlasticineAbsolutePath -Path $SourceKey -Name 'source private key'
    $sourceItem = Get-PlasticineItem $SourceKey
    if (-not $sourceItem -or $sourceItem.PSIsContainer -or (Test-PlasticineReparsePoint $sourceItem)) {
        Stop-PlasticineGithubSsh 'SourceKeyShape' @($SourceKey)
    }
    if ($sourceItem.Length -le 0) {
        Stop-PlasticineGithubSsh 'SourceKeyEmpty' @($SourceKey)
    }
    $firstLine = Get-PlasticineGithubSshSourceKeyFirstLine -Path $SourceKey
    if ($firstLine -cnotmatch '^-----BEGIN .+PRIVATE KEY-----$') {
        Stop-PlasticineGithubSsh 'SourceKeyUnsupported' @($SourceKey)
    }
    $sourceFingerprint = Get-PlasticineGithubSshKeyFingerprint -KeygenExecutable $keygen -Path $SourceKey
    if (-not $sourceFingerprint -or $sourceFingerprint -cne $ExpectedFingerprint) {
        Stop-PlasticineGithubSsh 'SourceKeyChanged' @($SourceKey)
    }

    if ($targetExists) {
        if (Test-PlasticineConfigTextEqual (Read-PlasticineConfigText -Path $SourceKey) (Read-PlasticineConfigText -Path $paths.KeyPath)) {
            Set-PlasticineOwnerOnlyAcl -Path $paths.KeyPath
            Write-PlasticineLog "github-ssh: the existing private key already matches the supplied key; kept at $($paths.KeyPath)."
            return
        }
        if (-not $ApprovedReplaceFingerprint -or $targetFingerprint -cne $ApprovedReplaceFingerprint) {
            Stop-PlasticineGithubSsh 'TargetKeyUnapproved' @($paths.KeyPath)
        }
    }

    foreach ($directory in @($paths.SshDirectory, $paths.ConfigDirectory)) {
        $item = Get-PlasticineItem $directory
        if (-not $item) {
            New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
        } elseif (-not $item.PSIsContainer -or (Test-PlasticineReparsePoint $item)) {
            Stop-PlasticineConfig -Label 'github-ssh' -Message "$directory must be a regular directory."
        }
        Set-PlasticineOwnerOnlyAcl -Path $directory
    }

    $temporaryKey = Join-Path $paths.SshDirectory ('.id_github.' + [IO.Path]::GetRandomFileName())
    try {
        Copy-Item -LiteralPath $SourceKey -Destination $temporaryKey -ErrorAction Stop
        Set-PlasticineOwnerOnlyAcl -Path $temporaryKey
        $copiedFingerprint = Get-PlasticineGithubSshKeyFingerprint -KeygenExecutable $keygen -Path $temporaryKey
        if (-not $copiedFingerprint -or $copiedFingerprint -cne $ExpectedFingerprint) {
            Stop-PlasticineGithubSsh 'CopiedKeyChanged'
        }
        if ($targetExists) {
            $timestamp = (Get-Date).ToString('yyyyMMddHHmmss')
            $backupKey = $paths.KeyPath + '.plasticine-backup-' + $timestamp
            $suffix = 0
            while (Test-Path -LiteralPath $backupKey) {
                $suffix++
                $backupKey = $paths.KeyPath + '.plasticine-backup-' + $timestamp + '-' + $suffix
            }
            Copy-Item -LiteralPath $paths.KeyPath -Destination $backupKey -ErrorAction Stop
            Set-PlasticineOwnerOnlyAcl -Path $backupKey
            Write-PlasticineLog "github-ssh: backed up the replaced private key at $backupKey."
            [IO.File]::Replace($temporaryKey, $paths.KeyPath, [NullString]::Value)
        } else {
            Publish-PlasticineNewFile -Candidate $temporaryKey -Target $paths.KeyPath
        }
    } finally {
        if (Get-PlasticineItem $temporaryKey) {
            Remove-Item -LiteralPath $temporaryKey -Force -ErrorAction SilentlyContinue
        }
    }

    Set-PlasticineOwnerOnlyAcl -Path $paths.KeyPath
    $installedFingerprint = Get-PlasticineGithubSshKeyFingerprint -KeygenExecutable $keygen -Path $paths.KeyPath
    if (-not $installedFingerprint -or $installedFingerprint -cne $ExpectedFingerprint) {
        Stop-PlasticineGithubSsh 'InstalledKeyUnreadable' @($paths.KeyPath)
    }
    Write-PlasticineLog "github-ssh: installed the private key at $($paths.KeyPath); fingerprint $installedFingerprint (contents never printed)."
}

# The post-apply probe is opt-in. Authentication results and connectivity
# results are reported separately: a network failure is never reported as an
# authentication failure.
function Invoke-PlasticineGithubSshConnectionTest {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory)
    Assert-PlasticineWindowsPlatform
    $paths = Get-PlasticineGithubSshPaths -HomeDirectory $HomeDirectory
    $ssh = Resolve-PlasticineGithubSshExecutable 'ssh'
    $keyItem = Get-PlasticineItem $paths.KeyPath
    if (-not $keyItem -or $keyItem.PSIsContainer -or (Test-PlasticineReparsePoint $keyItem)) {
        Write-PlasticineLog ("github-ssh: skipped the requested GitHub SSH test because no installed private key exists at " +
            "$($paths.KeyPath); the installation itself completed.")
        return [pscustomobject]@{
            Status   = 'skipped'
            ExitCode = 0
            Output   = @()
            Message  = ''
        }
    }
    $result = Invoke-PlasticineGithubSshProcess -Executable $ssh -MergeError -Argument @(
        '-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10',
        '-o', 'StrictHostKeyChecking=accept-new', 'git@github.com')
    $lines = @($result.Output)
    $text = ($lines -join "`n")
    if ($result.ExitCode -eq 0 -and $text -match 'successfully authenticated') {
        foreach ($line in $lines) { Write-PlasticineLog ('github-ssh: ' + [string]$line) }
        Write-PlasticineLog 'github-ssh: GitHub SSH authentication succeeded.'
        return [pscustomobject]@{
            Status   = 'authenticated'
            ExitCode = 0
            Output   = $lines
            Message  = ''
        }
    }

    foreach ($line in $lines) {
        if ([string]$line) { [Console]::Error.WriteLine([string]$line) }
    }
    $lower = $text.ToLowerInvariant()
    $authenticationFailure = ($lower -match 'permission denied') -or
        ($lower -match 'authentication failed') -or
        ($lower -match 'no supported authentication methods') -or
        ($lower -match 'no more authentication methods')
    $networkFailure = ($lower -match 'connection timed out') -or
        ($lower -match 'operation timed out') -or
        ($lower -match 'connection refused') -or
        ($lower -match 'could not resolve hostname') -or
        ($lower -match 'network is unreachable') -or
        ($lower -match 'no route to host') -or
        ($lower -match 'connection reset') -or
        ($lower -match 'temporarily unavailable') -or
        ($lower -match 'kex_exchange_identification') -or
        ($lower -match 'broken pipe')
    if ($authenticationFailure -and -not $networkFailure) {
        $message = Get-PlasticineGithubSshMessage -Key 'AuthRejected'
        Write-PlasticineError ('github-ssh: ' + $message)
        return [pscustomobject]@{
            Status   = 'authentication-rejected'
            ExitCode = 1
            Output   = $lines
            Message  = $message
        }
    }
    if ($networkFailure -and -not $authenticationFailure) {
        $message = Get-PlasticineGithubSshMessage -Key 'NetworkFailure'
        Write-PlasticineError ('github-ssh: ' + $message)
        return [pscustomobject]@{
            Status   = 'network-failure'
            ExitCode = 1
            Output   = $lines
            Message  = $message
        }
    }
    if ($result.ExitCode -eq 0) {
        $message = Get-PlasticineGithubSshMessage -Key 'TestUnexpected'
        Write-PlasticineError ('github-ssh: ' + $message)
        return [pscustomobject]@{
            Status   = 'unexpected'
            ExitCode = 1
            Output   = $lines
            Message  = $message
        }
    }
    $message = Get-PlasticineGithubSshMessage -Key 'UnknownTestFailure'
    Write-PlasticineError ('github-ssh: ' + $message)
    return [pscustomobject]@{
        Status   = 'unclassified'
        ExitCode = 1
        Output   = $lines
        Message  = $message
    }
}

function Get-PlasticineGithubSshItemState {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path)
    $item = Get-PlasticineItem $Path
    $exists = [bool]$item
    $isContainer = $false
    $isReparsePoint = $false
    if ($item) {
        $isContainer = [bool]$item.PSIsContainer
        $isReparsePoint = Test-PlasticineReparsePoint $item
    }
    return [pscustomobject]@{
        Path           = $Path
        Exists         = $exists
        IsContainer    = $isContainer
        IsReparsePoint = $isReparsePoint
        IsRegularFile  = ($exists -and -not $isContainer -and -not $isReparsePoint)
        IsRealDirectory = ($exists -and $isContainer -and -not $isReparsePoint)
    }
}

function Get-PlasticineGithubSshPlan {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory)
    $null = Assert-PlasticineAbsolutePath -Path $HomeDirectory -Name 'home directory'
    Assert-PlasticineWindowsPlatform
    $paths = Get-PlasticineGithubSshPaths -HomeDirectory $HomeDirectory
    $ssh = Resolve-PlasticineGithubSshExecutable 'ssh' -Optional
    $keygen = Resolve-PlasticineGithubSshExecutable 'ssh-keygen' -Optional
    $sshDirectory = Get-PlasticineGithubSshItemState -Path $paths.SshDirectory
    $configDirectory = Get-PlasticineGithubSshItemState -Path $paths.ConfigDirectory
    $configState = Get-PlasticineGithubSshConfigState -Path $paths.ConfigPath
    $fragment = Get-PlasticineGithubSshItemState -Path $paths.FragmentPath
    $key = Get-PlasticineGithubSshItemState -Path $paths.KeyPath

    $configChanged = $true
    if ($configState.IsRegularFile -and -not $configState.Damaged) {
        try {
            $candidate = New-PlasticineGithubSshConfigCandidate -Text $configState.Text
            $configChanged = -not (Test-PlasticineConfigTextEqual $configState.Text $candidate)
        } catch {
            $configChanged = $true
        }
    }

    $keySource = [string]$env:PLASTICINE_GITHUB_SSH_KEY
    $replaceApproved = ([string]$env:PLASTICINE_REPLACE_GITHUB_SSH_KEY -eq '1')
    $testRequested = ([string]$env:PLASTICINE_GITHUB_SSH_TEST -eq '1')
    $keyAction = 'unknown'
    if (-not $key.IsRegularFile) {
        if ($keySource) { $keyAction = 'install' }
    } elseif ($keygen) {
        $targetFingerprint = Get-PlasticineGithubSshKeyFingerprint -KeygenExecutable $keygen -Path $paths.KeyPath
        $sourceFingerprint = $null
        if ($keySource -and (Test-Path -LiteralPath $keySource -PathType Leaf)) {
            $sourceFingerprint = Get-PlasticineGithubSshKeyFingerprint -KeygenExecutable $keygen -Path $keySource
        }
        if ($targetFingerprint -and $sourceFingerprint) {
            if ($targetFingerprint -ceq $sourceFingerprint) { $keyAction = 'retain' }
            elseif ($replaceApproved) { $keyAction = 'replace' }
            else { $keyAction = 'conflict' }
        }
    }

    return [pscustomobject]@{
        HomeDirectory   = $paths.HomeDirectory
        SshDirectory    = $sshDirectory
        ConfigDirectory = $configDirectory
        ConfigPath      = $paths.ConfigPath
        FragmentPath    = $paths.FragmentPath
        KeyPath         = $paths.KeyPath
        BackupDirectory = $paths.BackupDirectory
        SshExecutable   = $ssh
        KeygenExecutable = $keygen
        OpenSshAvailable = [bool]($ssh -and $keygen)
        Config          = $configState
        Fragment        = $fragment
        Key             = $key
        KeySource       = $keySource
        ReplaceApproved = $replaceApproved
        TestRequested   = $testRequested
        ConfigChanged   = [bool]$configChanged
        KeyAction       = $keyAction
    }
}

function Write-PlasticineGithubSshPreview {
    param([Parameter(Mandatory = $true)]$Plan)
    $issues = 0
    if (-not $Plan.OpenSshAvailable) {
        Write-PlasticineError ('github-ssh: ' + (Get-PlasticineGithubSshMessage -Key 'OpenSshMissing'))
        $issues++
    } else {
        Write-PlasticineLog "github-ssh: observed the system OpenSSH client at $($Plan.SshExecutable) and ssh-keygen at $($Plan.KeygenExecutable); a Git/MSYS ssh is never used."
    }

    if ($Plan.SshDirectory.Exists -and -not $Plan.SshDirectory.IsRealDirectory) {
        Write-PlasticineError "github-ssh: $($Plan.SshDirectory.Path) must be a regular directory."
        $issues++
    }
    if ($Plan.ConfigDirectory.Exists -and -not $Plan.ConfigDirectory.IsRealDirectory) {
        Write-PlasticineError "github-ssh: $($Plan.ConfigDirectory.Path) must be a regular directory."
        $issues++
    }
    if ($Plan.Config.Exists -and -not $Plan.Config.IsRegularFile) {
        Write-PlasticineError "github-ssh: $($Plan.ConfigPath) must be a regular file."
        $issues++
    }
    if ($Plan.Fragment.Exists -and -not $Plan.Fragment.IsRegularFile) {
        Write-PlasticineError "github-ssh: $($Plan.FragmentPath) must be a regular file."
        $issues++
    }
    if ($Plan.Key.Exists -and -not $Plan.Key.IsRegularFile) {
        Write-PlasticineError ('github-ssh: ' + ((Get-PlasticineGithubSshMessage -Key 'KeyShape') -f $Plan.KeyPath))
        $issues++
    }
    if ($Plan.Config.Damaged) {
        Write-PlasticineError ('github-ssh: ' + (Get-PlasticineGithubSshMessage -Key 'ManagedBlockDamaged'))
        $issues++
    }

    Write-PlasticineLog "github-ssh: config target: $($Plan.ConfigPath) (composed by this route; the marker block includes ~/.ssh/config.d/00-plasticine-github.conf)."
    Write-PlasticineLog "github-ssh: managed fragment: $($Plan.FragmentPath) (Host github.com block with IdentityFile ~/.ssh/id_github plus Host *; provided by the github-ssh-fragment template)."
    if (-not $Plan.Config.Exists) {
        Write-PlasticineLog 'github-ssh: will compose ~/.ssh/config with the managed marker block; the pre-managed file is backed up before the first managed write (the first backup wins).'
    } elseif ($Plan.Config.Damaged) {
        Write-PlasticineLog 'github-ssh: the managed marker block is damaged; the file is left untouched until the Owner repairs it.'
    } elseif ($Plan.Config.HasBlock) {
        if ($Plan.ConfigChanged) {
            Write-PlasticineLog 'github-ssh: the managed marker block is present; the composed file will be rewritten with the Owner''s other bytes preserved.'
        } else {
            Write-PlasticineLog 'github-ssh: the managed marker block is already up to date.'
        }
    } else {
        Write-PlasticineLog 'github-ssh: will prepend the managed marker block to the existing ~/.ssh/config and back up the pre-managed file first (the first backup wins); the Owner''s other bytes are preserved.'
    }

    Write-PlasticineLog "github-ssh: private key target: $($Plan.KeyPath); installed with an owner-only DACL and the key contents are never printed or logged."
    switch ($Plan.KeyAction) {
        'install' {
            Write-PlasticineLog 'github-ssh: will install the supplied private key at the target and re-protect it.'
        }
        'retain' {
            Write-PlasticineLog 'github-ssh: the existing private key already matches the supplied key; it is kept and re-protected.'
        }
        'replace' {
            Write-PlasticineLog 'github-ssh: an approved replacement will back up the existing private key to a timestamped copy before installing the supplied key.'
        }
        'conflict' {
            Write-PlasticineError ('github-ssh: ' + ((Get-PlasticineGithubSshMessage -Key 'TargetKeyUnapproved') -f $Plan.KeyPath))
            $issues++
        }
        default {
            if (-not $Plan.KeySource) {
                Write-PlasticineError ('github-ssh: ' + (Get-PlasticineGithubSshMessage -Key 'KeySourceMissing'))
                $issues++
            } else {
                Write-PlasticineLog 'github-ssh: the supplied private key could not be compared during preview; apply re-verifies it before installing.'
            }
        }
    }

    Write-PlasticineLog 'github-ssh: network during apply: none while composing the config or installing the key; only the optional post-apply connection test contacts github.com.'
    Write-PlasticineLog 'github-ssh: commands during apply: system ssh.exe -G for config validation and ssh-keygen.exe -lf for fingerprints; no other binaries are started.'
    Write-PlasticineLog 'github-ssh: permissions: ~/.ssh, the composed config and the private key get an owner-only DACL; chmod has no Windows equivalent.'
    if ($Plan.TestRequested) {
        Write-PlasticineLog 'github-ssh: connection test: requested (-GithubSshTest / PLASTICINE_GITHUB_SSH_TEST=1); it runs ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new git@github.com after apply.'
    } else {
        Write-PlasticineLog 'github-ssh: connection test: not requested; no network request is made after apply.'
    }

    if ($issues -gt 0) {
        Stop-PlasticineGithubSsh 'PreviewBlocked'
    }
}
