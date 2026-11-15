# The powershell Feature owns the PowerShell startup integration: the managed
# fragments under ~/.plasticine/powershell, the Plasticine marker block in each
# installed host's $PROFILE.CurrentUserAllHosts, and the user-level PATH entry
# that exposes ~/.local/bin to native Windows terminals.
#
# Observation (plan/preview) never changes native state; only the prepare step
# writes the user PATH, and only chezmoi apply writes profiles. The profile
# composition lives here instead of in a chezmoi template because the release
# installer inlines lib/windows/*.ps1 and cannot render templates.
#
# Marker literals are repeated inside the functions below on purpose: caller
# scopes (including an included template) can shadow variables, so the byte
# contract must not depend on dynamic variable lookup.
#
# This file is ASCII only: Windows PowerShell 5.1 reads BOM-less scripts with
# the ANSI code page, so non-ASCII literals would break on some machines.

if (-not (Get-Command Write-PlasticineLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'common.ps1')
}
if (-not (Get-Command Get-PlasticineUserPath -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'user-path.ps1')
}
if (-not (Get-Command Set-PlasticineOwnerOnlyAcl -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'acl.ps1')
}

# Test seams: suites override these defaults instead of touching the machine.
if (-not (Test-Path Variable:PlasticinePowershellExecutionPolicyOverride)) {
    $PlasticinePowershellExecutionPolicyOverride = $null
}
if (-not (Test-Path Variable:PlasticinePowershellDocumentsDirectoryOverride)) {
    $PlasticinePowershellDocumentsDirectoryOverride = $null
}
if (-not (Test-Path Variable:PlasticinePowershellProfileTargetsOverride)) {
    $PlasticinePowershellProfileTargetsOverride = $null
}

# HKCU\Environment cannot be redirected by the process that runs the suite, so
# $PlasticineUserEnvironmentSubKey from user-path.ps1 stays the PATH test seam.

function Get-PlasticinePowershellProfileMarkers {
    return [pscustomobject]@{
        Name  = 'powershell'
        Start = '# >>> Plasticine powershell >>>'
        End   = '# <<< Plasticine powershell <<<'
    }
}

function Get-PlasticinePowershellBlockedExecutionPolicies {
    # Profiles are unsigned local scripts, so both policies prevent them from
    # loading. RemoteSigned/Unrestricted/Bypass/Undefined resolve elsewhere.
    return @('Restricted', 'AllSigned')
}

function Assert-PlasticinePowershellAbsolutePath {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path)) {
        Stop-Plasticine "powershell: path must be absolute: $Path"
    }
}

function Test-PlasticinePowershellBytesEqual {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Left,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Right
    )
    if ($Left.Length -ne $Right.Length) { return $false }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) { return $false }
    }
    return $true
}

# Latin-1 maps every byte to exactly one character, so string offsets equal
# byte offsets and content outside the block can be preserved byte for byte.
function Get-PlasticinePowershellLatin1 {
    return [Text.Encoding]::GetEncoding(28591)
}

function Get-PlasticinePowershellProfileBlockState {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes)
    $markers = Get-PlasticinePowershellProfileMarkers
    $text = (Get-PlasticinePowershellLatin1).GetString($Bytes)
    $damaged = $false
    $present = $false
    $startOffset = -1
    $endOffset = -1
    $open = $false
    $position = 0
    while ($position -lt $text.Length) {
        $newline = $text.IndexOf([char]10, $position)
        if ($newline -lt 0) {
            $lineEnd = $text.Length
            $next = $text.Length
        } else {
            $lineEnd = $newline
            $next = $newline + 1
        }
        $line = $text.Substring($position, $lineEnd - $position)
        if ($line.EndsWith("`r")) { $line = $line.Substring(0, $line.Length - 1) }
        if ($line -ceq $markers.Start) {
            if ($open -or $present -or $startOffset -ge 0) { $damaged = $true }
            else {
                $open = $true
                $startOffset = $position
            }
        } elseif ($line -ceq $markers.End) {
            if (-not $open -or $present) {
                $damaged = $true
                $open = $false
            } else {
                $open = $false
                $present = $true
                $endOffset = $next
            }
        } else {
            $damagedLine = $line
            $damagedLine = $damagedLine -creplace '^[ \t]*#[ \t]*[<>]*[ \t]*Plasticine[ \t]+', ''
            if ($damagedLine -cne $line) {
                $token = ($damagedLine -split '[ \t\r<>]')[0]
                if ($token -ceq $markers.Name) { $damaged = $true }
            }
        }
        $position = $next
    }
    if ($open) { $damaged = $true }
    if ($damaged) { $present = $false }
    return [pscustomobject]@{
        Damaged = $damaged
        Present = $present
        Start   = $startOffset
        End     = $endOffset
    }
}

function Assert-PlasticinePowershellProfileBlock {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Block)
    foreach ($character in $Block.ToCharArray()) {
        if ([int]$character -gt 255) {
            Stop-Plasticine 'powershell: the profile block text must stay ASCII so bytes outside the block are preserved.'
        }
    }
    $encoding = Get-PlasticinePowershellLatin1
    $bytes = $encoding.GetBytes($Block)
    $state = Get-PlasticinePowershellProfileBlockState -Bytes $bytes
    if ($state.Damaged -or -not $state.Present -or $state.Start -ne 0 -or $state.End -ne $bytes.Length) {
        Stop-Plasticine 'powershell: the profile block text must contain exactly one Plasticine powershell marker pair and end with the closing marker.'
    }
}

function New-PlasticinePowershellProfileContent {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Block,
        [ValidateSet('prepend', 'append')][string]$Position = 'prepend'
    )
    Assert-PlasticinePowershellProfileBlock -Block $Block
    $blockBytes = (Get-PlasticinePowershellLatin1).GetBytes($Block)
    $state = Get-PlasticinePowershellProfileBlockState -Bytes $Bytes
    if ($state.Damaged) {
        Stop-Plasticine 'powershell: the Plasticine powershell block is damaged, nested, or duplicated; left unchanged. Repair it manually first.'
    }
    if ($state.Present) {
        $head = New-Object byte[] $state.Start
        if ($head.Length -gt 0) { [Array]::Copy($Bytes, 0, $head, 0, $head.Length) }
        $tailLength = $Bytes.Length - $state.End
        $tail = New-Object byte[] $tailLength
        if ($tail.Length -gt 0) { [Array]::Copy($Bytes, $state.End, $tail, 0, $tail.Length) }
        return [byte[]]($head + $blockBytes + $tail)
    }
    if ($Bytes.Length -eq 0) { return [byte[]]$blockBytes }
    if ($Position -eq 'append') {
        # Keep an Owner file without a final newline intact as a line of its own.
        if ($Bytes[$Bytes.Length - 1] -eq 10) {
            return [byte[]]($Bytes + $blockBytes)
        }
        return [byte[]]($Bytes + [byte[]](13, 10) + $blockBytes)
    }
    return [byte[]]($blockBytes + $Bytes)
}

function Get-PlasticinePowershellProfileState {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path)
    $item = Get-PlasticineItem $Path
    $exists = $false
    $regular = $false
    $hasBlock = $false
    $damaged = $false
    if ($item) {
        $exists = $true
        if (-not $item.PSIsContainer -and -not (Test-PlasticineReparsePoint $item)) {
            $regular = $true
            $bytes = [IO.File]::ReadAllBytes($Path)
            $state = Get-PlasticinePowershellProfileBlockState -Bytes $bytes
            $hasBlock = $state.Present
            $damaged = $state.Damaged
        }
    }
    return [pscustomobject]@{
        Path          = $Path
        Exists        = $exists
        IsRegularFile = $regular
        HasBlock      = $hasBlock
        Damaged       = $damaged
    }
}

function Assert-PlasticinePowershellRegularFile {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path)
    $item = Get-PlasticineItem $Path
    if (-not $item) { return }
    if ($item.PSIsContainer -or (Test-PlasticineReparsePoint $item)) {
        Stop-Plasticine "powershell: configuration target must be a regular file: $Path"
    }
}

function Assert-PlasticinePowershellRealDirectory {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path)
    $item = Get-PlasticineItem $Path
    if (-not $item) { return }
    if (-not $item.PSIsContainer -or (Test-PlasticineReparsePoint $item)) {
        Stop-Plasticine "powershell: configuration directory must be a regular directory: $Path"
    }
}

function Get-PlasticinePowershellDocumentsDirectory {
    if ($null -ne $PlasticinePowershellDocumentsDirectoryOverride) {
        return [string]$PlasticinePowershellDocumentsDirectoryOverride
    }
    if ($env:PLASTICINE_POWERSHELL_DOCUMENTS_DIR) {
        # Offline suites point this at a disposable Documents root.
        return [string]$env:PLASTICINE_POWERSHELL_DOCUMENTS_DIR
    }
    $documents = [Environment]::GetFolderPath('MyDocuments')
    if (-not $documents) {
        Stop-Plasticine 'powershell: cannot locate the current user Documents folder; check the Windows Known Folders configuration and retry.'
    }
    return $documents
}

function Test-PlasticinePowershellDocumentsRedirect {
    # With a redirected Documents root every host path derives from it; the
    # running host's real $PROFILE must not leak into an isolated run.
    if ($null -ne $PlasticinePowershellDocumentsDirectoryOverride) { return $true }
    if ($env:PLASTICINE_POWERSHELL_DOCUMENTS_DIR) { return $true }
    return $false
}

function Assert-PlasticinePowershellDocumentsDirectory {
    $documents = Get-PlasticinePowershellDocumentsDirectory
    $item = Get-PlasticineItem $documents
    if (-not $item) {
        Stop-Plasticine "powershell: Documents directory is missing: $documents"
    }
    if (-not $item.PSIsContainer) {
        Stop-Plasticine "powershell: configuration directory must be a regular directory: $documents"
    }
    return $documents
}

function New-PlasticinePowershellProfileTarget {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$BackupLabel
    )
    return [pscustomobject]@{
        Label       = $Label
        Path        = $Path
        BackupLabel = $BackupLabel
    }
}

function Get-PlasticinePowershellProfileTargets {
    if ($null -ne $PlasticinePowershellProfileTargetsOverride) {
        return @($PlasticinePowershellProfileTargetsOverride)
    }
    $documents = Get-PlasticinePowershellDocumentsDirectory
    $redirected = Test-PlasticinePowershellDocumentsRedirect
    $currentIsCore = $false
    if ($PSVersionTable.PSVersion.Major -ge 6) { $currentIsCore = $true }
    $currentProfile = [string]$PROFILE.CurrentUserAllHosts
    $windowsPowerShell = Get-PlasticineCommandPath 'powershell.exe'
    $powershellCore = Get-PlasticineCommandPath 'pwsh.exe'
    $targets = @()
    if ($windowsPowerShell -or -not $currentIsCore) {
        $path = Join-Path $documents 'WindowsPowerShell\profile.ps1'
        # The running host's $PROFILE is authoritative; the other host's
        # Documents path is derived because it cannot be queried from here.
        if (-not $currentIsCore -and $currentProfile -and -not $redirected) { $path = $currentProfile }
        $targets += New-PlasticinePowershellProfileTarget -Label 'Windows PowerShell' `
            -Path $path -BackupLabel 'WindowsPowerShell-profile.ps1'
    }
    if ($powershellCore -or $currentIsCore) {
        $path = Join-Path $documents 'PowerShell\profile.ps1'
        if ($currentIsCore -and $currentProfile -and -not $redirected) { $path = $currentProfile }
        $targets += New-PlasticinePowershellProfileTarget -Label 'PowerShell 7+' `
            -Path $path -BackupLabel 'PowerShell-profile.ps1'
    }
    $unique = @()
    foreach ($target in $targets) {
        $duplicate = $false
        foreach ($seen in $unique) {
            if ($seen.Path.TrimEnd('\') -eq $target.Path.TrimEnd('\')) { $duplicate = $true }
        }
        if (-not $duplicate) { $unique += $target }
    }
    return @($unique)
}

function Assert-PlasticinePowershellCurrentHostProfile {
    $currentProfile = [string]$PROFILE.CurrentUserAllHosts
    if (-not $currentProfile) {
        Stop-Plasticine 'powershell: the current host profile path is empty; cannot locate $PROFILE.CurrentUserAllHosts.'
    }
    if (-not [IO.Path]::IsPathRooted($currentProfile)) {
        Stop-Plasticine "powershell: the current host profile path must be absolute: $currentProfile"
    }
}

function Assert-PlasticinePowershellProfileTargets {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Targets)
    foreach ($target in $Targets) {
        Assert-PlasticinePowershellAbsolutePath -Path $target.Path
        $parent = Split-Path -Parent $target.Path
        if (-not $parent) {
            Stop-Plasticine "powershell: profile path has no parent directory: $($target.Path)"
        }
        Assert-PlasticinePowershellRealDirectory -Path $parent
        Assert-PlasticinePowershellRegularFile -Path $target.Path
    }
}

function Test-PlasticinePowershellProfileMaintenance {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$DestDirectory)
    # Offline suites redirect the Documents root; explicit seams also opt in.
    if ($env:PLASTICINE_POWERSHELL_DOCUMENTS_DIR) { return $true }
    if ($null -ne $PlasticinePowershellDocumentsDirectoryOverride) { return $true }
    if ($null -ne $PlasticinePowershellProfileTargetsOverride) { return $true }
    $userProfile = [Environment]::GetFolderPath('UserProfile')
    if (-not $userProfile) { $userProfile = $env:USERPROFILE }
    if (-not $userProfile) { return $true }
    try {
        $dest = [IO.Path]::GetFullPath($DestDirectory).TrimEnd('\')
        $owner = [IO.Path]::GetFullPath([string]$userProfile).TrimEnd('\')
    } catch {
        return $false
    }
    return ($dest -eq $owner)
}

function Save-PlasticinePowershellProfileBackup {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$BackupDirectory,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Label
    )
    Assert-PlasticinePowershellAbsolutePath -Path $BackupDirectory
    $directoryItem = Get-PlasticineItem $BackupDirectory
    if ($directoryItem) {
        if (-not $directoryItem.PSIsContainer -or (Test-PlasticineReparsePoint $directoryItem)) {
            Stop-Plasticine "powershell: configuration directory must be a regular directory: $BackupDirectory"
        }
    } else {
        New-Item -ItemType Directory -Path $BackupDirectory -Force -ErrorAction Stop | Out-Null
    }
    # Match the zsh backup contract: the backup root and its feature directory
    # are owner-only, and the copy itself is owner-only.
    $backupRoot = Split-Path -Parent $BackupDirectory
    foreach ($protected in @($backupRoot, $BackupDirectory)) {
        if (Get-PlasticineItem $protected) { Set-PlasticineOwnerOnlyAcl -Path $protected }
    }
    $name = $Label + '.plasticine-backup-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $backup = Join-Path $BackupDirectory $name
    [IO.File]::WriteAllBytes($backup, $Bytes)
    Set-PlasticineOwnerOnlyAcl -Path $backup
    return $backup
}

function Update-PlasticinePowershellProfile {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Block,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$BackupDirectory,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Label,
        [ValidateSet('prepend', 'append')][string]$Position = 'prepend'
    )
    Assert-PlasticinePowershellAbsolutePath -Path $Path
    Assert-PlasticinePowershellAbsolutePath -Path $BackupDirectory
    Assert-PlasticinePowershellProfileBlock -Block $Block

    $targetItem = Get-PlasticineItem $Path
    if ($targetItem) {
        if ($targetItem.PSIsContainer -or (Test-PlasticineReparsePoint $targetItem)) {
            Stop-Plasticine "powershell: configuration target must be a regular file: $Path"
        }
    }
    $parent = Split-Path -Parent $Path
    if (-not $parent) {
        Stop-Plasticine "powershell: profile path has no parent directory: $Path"
    }
    $parentItem = Get-PlasticineItem $parent
    if ($parentItem) {
        if (-not $parentItem.PSIsContainer -or (Test-PlasticineReparsePoint $parentItem)) {
            Stop-Plasticine "powershell: configuration directory must be a regular directory: $parent"
        }
    }

    $current = New-Object byte[] 0
    if ($targetItem) { $current = [IO.File]::ReadAllBytes($Path) }
    $state = Get-PlasticinePowershellProfileBlockState -Bytes $current
    if ($state.Damaged) {
        Stop-Plasticine "powershell: the Plasticine powershell block in $Path is damaged, nested, or duplicated; left unchanged. Repair it manually first."
    }
    $candidate = New-PlasticinePowershellProfileContent -Bytes $current -Block $Block -Position $Position
    $changed = -not (Test-PlasticinePowershellBytesEqual -Left $current -Right $candidate)
    $backup = $null
    if ($changed -and $targetItem) {
        $backup = Save-PlasticinePowershellProfileBackup -Path $Path -Bytes $current `
            -BackupDirectory $BackupDirectory -Label $Label
    }
    if ($changed) {
        if (-not $parentItem) {
            New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
        }
        # Publish beside the target and replace atomically; a profile without a
        # block is new, so a plain move is enough there.
        $temp = Join-Path $parent ('.' + $Label + '.plasticine-' + [guid]::NewGuid().ToString('N') + '.tmp')
        try {
            [IO.File]::WriteAllBytes($temp, $candidate)
            if ($targetItem) {
                [IO.File]::Replace($temp, $Path, [NullString]::Value)
            } else {
                [IO.File]::Move($temp, $Path)
            }
        } catch {
            if (Test-Path -LiteralPath $temp) {
                Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
            }
            throw
        }
    }
    $finalState = Get-PlasticinePowershellProfileBlockState -Bytes ([IO.File]::ReadAllBytes($Path))
    return [pscustomobject]@{
        Path       = $Path
        Changed    = $changed
        BackupPath = $backup
        HasBlock   = $finalState.Present
    }
}

function Get-PlasticinePowershellExecutionPolicy {
    if ($null -ne $PlasticinePowershellExecutionPolicyOverride) {
        return [string]$PlasticinePowershellExecutionPolicyOverride
    }
    # The process scope only covers this installer process (Bypass), while the
    # profile loads from a fresh shell. Resolve as a new shell would.
    $policies = @{}
    foreach ($entry in @(Get-ExecutionPolicy -List)) {
        $policies[[string]$entry.Scope] = [string]$entry.ExecutionPolicy
    }
    foreach ($scope in @('MachinePolicy', 'UserPolicy', 'CurrentUser', 'LocalMachine')) {
        if ($policies.ContainsKey($scope)) {
            $value = $policies[$scope]
            if ($value -and $value -ne 'Undefined') { return $value }
        }
    }
    return 'Restricted'
}

function Assert-PlasticinePowershellExecutionPolicy {
    $policy = Get-PlasticinePowershellExecutionPolicy
    if ((Get-PlasticinePowershellBlockedExecutionPolicies) -contains $policy) {
        Stop-Plasticine ("powershell: the effective execution policy $policy does not allow PowerShell profiles; " +
            'the policy was not changed. Run Set-ExecutionPolicy -Scope CurrentUser RemoteSigned ' +
            '(or another organization-approved policy that allows local scripts) and retry, or re-run ' +
            'the installer without the powershell Feature.')
    }
}

function Get-PlasticinePowershellPlan {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$HomeDirectory
    )
    try {
        $homePath = [IO.Path]::GetFullPath($HomeDirectory)
    } catch {
        Stop-Plasticine "powershell: invalid home directory: $HomeDirectory"
    }
    if ($homePath.Length -gt 3) { $homePath = $homePath.TrimEnd('\') }
    $pathDirectory = Join-Path $homePath '.local\bin'
    $pathMissing = $true
    if ($null -eq (Resolve-PlasticineUserPathAddition -Directory $pathDirectory)) { $pathMissing = $false }
    $targets = @()
    foreach ($target in @(Get-PlasticinePowershellProfileTargets)) {
        $state = Get-PlasticinePowershellProfileState -Path $target.Path
        $targets += [pscustomobject]@{
            Label         = $target.Label
            Path          = $target.Path
            BackupLabel   = $target.BackupLabel
            Exists        = $state.Exists
            IsRegularFile = $state.IsRegularFile
            HasBlock      = $state.HasBlock
            Damaged       = $state.Damaged
        }
    }
    $policy = Get-PlasticinePowershellExecutionPolicy
    $blocked = $false
    if ((Get-PlasticinePowershellBlockedExecutionPolicies) -contains $policy) { $blocked = $true }
    return [pscustomobject]@{
        HomeDirectory          = $homePath
        PathDirectory          = $pathDirectory
        PathMissing            = $pathMissing
        ProfileTargets         = @($targets)
        BackupDirectory        = Join-Path $homePath '.plasticine\backups\powershell'
        ExecutionPolicy        = $policy
        ExecutionPolicyBlocked = $blocked
        DocumentsDirectory     = Get-PlasticinePowershellDocumentsDirectory
    }
}

function Write-PlasticinePowershellPreview {
    param([Parameter(Mandatory = $true)]$Plan)
    if ($Plan.PathMissing) {
        Write-PlasticineLog "powershell: will append $($Plan.PathDirectory) to the user-level PATH; a new terminal picks it up."
    } else {
        Write-PlasticineLog "powershell: the user-level PATH already contains $($Plan.PathDirectory)."
    }
    $invalid = @()
    $damaged = @()
    foreach ($target in @($Plan.ProfileTargets)) {
        if (-not $target.Exists) {
            Write-PlasticineLog "powershell: will create the $($target.Label) profile with the Plasticine block: $($target.Path)"
        } elseif (-not $target.IsRegularFile) {
            Write-PlasticineError "powershell: configuration target must be a regular file: $($target.Path)"
            $invalid += $target.Path
        } elseif ($target.Damaged) {
            Write-PlasticineError "powershell: the Plasticine block in $($target.Path) is damaged, nested, or duplicated; left unchanged. Repair it manually first."
            $damaged += $target.Path
        } elseif ($target.HasBlock) {
            Write-PlasticineLog "powershell: the $($target.Label) profile block is up to date: $($target.Path)"
        } else {
            Write-PlasticineLog "powershell: will prepend the Plasticine block to the $($target.Label) profile: $($target.Path)"
        }
    }
    if ($invalid.Count -gt 0) {
        Stop-Plasticine 'powershell: profile targets must be regular files; nothing was changed. Repair the paths above first.'
    }
    if ($damaged.Count -gt 0) {
        Stop-Plasticine 'powershell: a Plasticine profile block is damaged; nothing was changed. Repair it manually first.'
    }
    Assert-PlasticinePowershellExecutionPolicy
}

function Invoke-PlasticinePowershellPrepare {
    param([Parameter(Mandatory = $true)]$Plan)
    Assert-PlasticinePowershellExecutionPolicy
    Assert-PlasticinePowershellAbsolutePath -Path ([string]$Plan.PathDirectory)
    if ($Plan.PathMissing) {
        $added = Add-PlasticineUserPathEntry -Directory $Plan.PathDirectory
        if ($added) {
            # user-path.ps1 owns the HKCU write and the WM_SETTINGCHANGE broadcast.
            Write-PlasticineLog "powershell: added $($Plan.PathDirectory) to the user-level PATH; reopen the terminal to pick it up."
        } else {
            Write-PlasticineLog "powershell: the user-level PATH already contains $($Plan.PathDirectory); nothing to change."
        }
    } else {
        Write-PlasticineLog "powershell: the user-level PATH already contains $($Plan.PathDirectory); nothing to change."
    }
    Write-PlasticineLog 'powershell: the profile block and managed fragments are maintained during chezmoi apply.'
}
