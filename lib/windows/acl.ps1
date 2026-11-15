# Windows has no 644/755 equivalent. Secrets get an owner-only DACL, and every
# restriction is reversible through one of the two verified restore branches.

if (-not (Get-Command Write-PlasticineLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'common.ps1')
}
if (Get-Command Get-PlasticineAclBackup -ErrorAction SilentlyContinue) { return }

# .NET Core removed the static [IO.File]/[IO.Directory] helpers and exposes
# FileSystemInfo extension methods instead; Windows PowerShell 5.1 keeps the
# static helpers. The branch is selected from the running host, never guessed.
function Get-PlasticineAclWriterKind {
    if ($PSVersionTable.PSEdition -eq 'Core') { return 'extension' }
    return 'static'
}

function Set-PlasticineAccessControl {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path,
        [Parameter(Mandatory = $true)]$Security
    )
    $null = Assert-PlasticineAbsolutePath -Path $Path -Name 'access control path'
    if ((Get-PlasticineAclWriterKind) -eq 'extension') {
        try { Add-Type -AssemblyName System.IO.FileSystem.AccessControl -ErrorAction SilentlyContinue } catch { }
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ('System.IO.FileSystemAclExtensions' -as [type]) {
            [System.IO.FileSystemAclExtensions]::SetAccessControl($item, $Security)
            return
        }
        # PowerShell 7 surfaces the extension class only after its assembly loads;
        # the provider cmdlet is the documented fallback for that host.
        Set-Acl -LiteralPath $Path -AclObject $Security -ErrorAction Stop
        return
    }
    if ($Security -is [Security.AccessControl.DirectorySecurity]) {
        [IO.Directory]::SetAccessControl($Path, $Security)
    } else {
        [IO.File]::SetAccessControl($Path, $Security)
    }
}

# AddAccessRule silently corrupts the DACL when an identity cannot be mapped, so
# every identity is translated to a SecurityIdentifier before anything is built.
function Resolve-PlasticineAclIdentity {
    param($Identity)
    if ($null -eq $Identity) { return $null }
    if ($Identity -is [Security.Principal.SecurityIdentifier]) { return $Identity }
    if ($Identity -is [Security.Principal.NTAccount]) {
        try { return $Identity.Translate([Security.Principal.SecurityIdentifier]) } catch { return $null }
    }
    $text = [string]$Identity
    if (-not $text) { return $null }
    try { return (New-Object Security.Principal.SecurityIdentifier($text)) } catch { }
    try { return ((New-Object Security.Principal.NTAccount($text)).Translate([Security.Principal.SecurityIdentifier])) } catch { }
    return $null
}

function ConvertTo-PlasticineAclRule {
    param($Rule)
    if (-not $Rule) { return $null }
    $identity = Resolve-PlasticineAclIdentity -Identity $Rule.IdentityReference
    if (-not $identity) { return $null }
    return (New-Object Security.AccessControl.FileSystemAccessRule(
            $identity, $Rule.FileSystemRights, $Rule.InheritanceFlags, $Rule.PropagationFlags, $Rule.AccessControlType))
}

# Snapshot the tree without following reparse points: tightening must never
# rewrite the ACL of whatever a junction or symlink points at.
function Get-PlasticineAclTree {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path)
    $null = Assert-PlasticineAbsolutePath -Path $Path -Name 'access control tree'
    $root = Get-PlasticineItem $Path
    if (-not $root) { Stop-Plasticine "cannot change the access rules of a missing path: $Path" }
    $items = New-Object System.Collections.ArrayList
    $pending = New-Object System.Collections.Stack
    $pending.Push($root)
    while ($pending.Count -gt 0) {
        $item = $pending.Pop()
        [void]$items.Add($item)
        if (-not $item.PSIsContainer -or (Test-PlasticineReparsePoint $item)) { continue }
        foreach ($child in @(Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction Stop)) {
            if (Test-PlasticineReparsePoint $child) { continue }
            $pending.Push($child)
        }
    }
    return $items.ToArray()
}

function New-PlasticineAclBackupEntry {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path)
    $item = Get-PlasticineItem $Path
    if (-not $item) { Stop-Plasticine "cannot back up the access rules of a missing path: $Path" }
    if (Test-PlasticineReparsePoint $item) {
        Stop-Plasticine "refusing to back up the access rules of a reparse point: $Path"
    }
    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    return [pscustomobject]@{
        Path        = $Path
        IsDirectory = $item.PSIsContainer
        Protected   = $acl.AreAccessRulesProtected
        Rules       = @($acl.GetAccessRules($true, $false, [Security.Principal.SecurityIdentifier]))
        Sddl        = $acl.Sddl
    }
}

function Get-PlasticineAclBackup {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path,
        [switch]$Recurse
    )
    $null = Assert-PlasticineAbsolutePath -Path $Path -Name 'ACL backup path'
    if (-not $Recurse) {
        return (New-PlasticineAclBackupEntry -Path $Path)
    }
    $entries = @()
    foreach ($item in @(Get-PlasticineAclTree -Path $Path)) {
        $entries += New-PlasticineAclBackupEntry -Path $item.FullName
    }
    return $entries
}

function New-PlasticineOwnerOnlySecurity {
    param(
        [Parameter(Mandatory = $true)][bool]$IsDirectory,
        [Parameter(Mandatory = $true)][string]$Right
    )
    $identity = Resolve-PlasticineAclIdentity -Identity ([Security.Principal.WindowsIdentity]::GetCurrent().User)
    if (-not $identity) {
        Stop-Plasticine 'cannot resolve the current user identity required for an owner-only access rule'
    }
    if ($IsDirectory) {
        $security = New-Object Security.AccessControl.DirectorySecurity
        $rule = New-Object Security.AccessControl.FileSystemAccessRule(
            $identity, $Right, 'ContainerInherit, ObjectInherit', 'None', 'Allow')
    } else {
        $security = New-Object Security.AccessControl.FileSecurity
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity, $Right, 'Allow')
    }
    $security.SetAccessRuleProtection($true, $false)
    $security.AddAccessRule($rule)
    return $security
}

function Set-PlasticineOwnerOnlyAcl {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path,
        [ValidateSet('FullControl', 'ReadAndExecute')][string]$Right = 'FullControl',
        [switch]$Recurse
    )
    $null = Assert-PlasticineAbsolutePath -Path $Path -Name 'access control path'
    if ($Recurse) {
        $targets = @(Get-PlasticineAclTree -Path $Path)
    } else {
        $item = Get-PlasticineItem $Path
        if (-not $item) { Stop-Plasticine "cannot restrict a missing path: $Path" }
        $targets = @($item)
    }
    foreach ($target in $targets) {
        $security = New-PlasticineOwnerOnlySecurity -IsDirectory ([bool]$target.PSIsContainer) -Right $Right
        Set-PlasticineAccessControl -Path $target.FullName -Security $security
    }
}

function Set-PlasticineOwnerOnlyAclRecursive {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path,
        [ValidateSet('FullControl', 'ReadAndExecute')][string]$Right = 'FullControl'
    )
    Set-PlasticineOwnerOnlyAcl -Path $Path -Right $Right -Recurse
}

function Restore-PlasticineAcl {
    param(
        [string]$Path,
        [Parameter(Mandatory = $true)]$Backup
    )
    # A recursive backup is an ordered list of entries; restore each entry itself.
    if ($Backup -is [array]) {
        foreach ($entry in $Backup) {
            Restore-PlasticineAcl -Path $entry.Path -Backup $entry
        }
        return
    }
    if (-not $Path) { $Path = $Backup.Path }
    $null = Assert-PlasticineAbsolutePath -Path $Path -Name 'ACL restore path'
    if (-not (Get-PlasticineItem $Path)) {
        Stop-Plasticine "cannot restore the access rules of a missing path: $Path"
    }
    $rules = @()
    foreach ($rule in @($Backup.Rules)) {
        $converted = ConvertTo-PlasticineAclRule -Rule $rule
        if (-not $converted) {
            $identity = $rule.IdentityReference
            Stop-Plasticine "refusing to restore an access rule whose identity cannot be resolved: $identity; no access rules were changed: $Path"
        }
        $rules += $converted
    }
    if ($Backup.Protected -and $rules.Count -eq 0) {
        # An empty rule set would publish an empty DACL and lock everyone out.
        Stop-Plasticine "refusing to restore an empty access rule set: $Path"
    }
    if ($Backup.IsDirectory) {
        $security = New-Object Security.AccessControl.DirectorySecurity
    } else {
        $security = New-Object Security.AccessControl.FileSecurity
    }
    if ($Backup.Protected) {
        $security.SetAccessRuleProtection($true, $false)
    } else {
        # Re-inherit, but keep the explicit ACEs captured from a mixed DACL.
        $security.SetAccessRuleProtection($false, $true)
    }
    foreach ($rule in $rules) { $security.AddAccessRule($rule) }
    Set-PlasticineAccessControl -Path $Path -Security $security
}
