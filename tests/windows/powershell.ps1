# Unit coverage for the powershell Feature: profile marker composition, byte
# preservation outside the block, managed fragment delivery, execution-policy
# refusal and user PATH integration. No network and no real HKCU writes.

$repoDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'harness.ps1')
$PlasticineTestName = 'windows powershell'
. (Join-Path $repoDir 'lib\windows\common.ps1')
. (Join-Path $repoDir 'lib\windows\user-path.ps1')
. (Join-Path $repoDir 'lib\windows\acl.ps1')
. (Join-Path $repoDir 'lib\windows\powershell-config.ps1')

# Observation helpers are exercised deterministically; the suite never changes
# the machine execution policy or the real user PATH.
$PlasticinePowershellExecutionPolicyOverride = 'RemoteSigned'
$registryTestKey = $null
$previousUserProfile = $env:USERPROFILE
$previousDocumentsRedirect = $env:PLASTICINE_POWERSHELL_DOCUMENTS_DIR
try {
    # --- Template contract: the rendered block matches the library markers. ---
    $templatePath = Join-Path $repoDir '.chezmoitemplates\powershell-profile-blocks'
    $templateText = Get-Content -LiteralPath $templatePath -Raw
    $templateProbe = & {
        . ([scriptblock]::Create($templateText))
        [pscustomobject]@{
            Start = $PlasticinePowershellProfileBlockStart
            End   = $PlasticinePowershellProfileBlockEnd
            Block = Get-PlasticinePowershellProfileBlock
        }
    }
    Assert-Equal '# >>> Plasticine powershell >>>' $templateProbe.Start 'the template start marker drifted'
    Assert-Equal '# <<< Plasticine powershell <<<' $templateProbe.End 'the template end marker drifted'
    $block = [string]$templateProbe.Block
    Assert-True ($block.EndsWith("`r`n")) 'the profile block is not newline terminated'
    Assert-True ($block.Contains('environment.ps1') -and $block.Contains('shared.ps1')) `
        'the profile block lost a managed fragment'
    $blockBytes = (Get-PlasticinePowershellLatin1).GetBytes($block)
    $blockState = Get-PlasticinePowershellProfileBlockState -Bytes $blockBytes
    Assert-True $blockState.Present 'the rendered profile block does not match the library marker contract'
    Assert-True (-not $blockState.Damaged) 'the rendered profile block is reported as damaged'
    Assert-Equal 0 $blockState.Start 'the profile block does not start at offset zero'
    Assert-Equal $blockBytes.Length $blockState.End 'the marker pair does not wrap the whole block'

    # --- Managed fragments parse under this host (5.1 baseline, no 7+ syntax). ---
    foreach ($fragmentName in @('environment.ps1', 'shared.ps1')) {
        $fragmentPath = Join-Path $repoDir ('dot_plasticine\powershell\' + $fragmentName)
        $fragmentTokens = $null
        $fragmentErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            $fragmentPath, [ref]$fragmentTokens, [ref]$fragmentErrors)
        Assert-Equal 0 @($fragmentErrors).Count "$fragmentName does not parse on this PowerShell version"
    }

    # --- Base fragment: prepend ~/.local/bin, add ~/.cargo/bin when present,
    # keep the inherited order, stay silent and stay idempotent. ---
    $fragmentHome = New-TestDirectory 'fragment-home'
    New-Item -ItemType Directory -Path (Join-Path $fragmentHome '.cargo\bin') | Out-Null
    $environmentSource = Join-Path $repoDir 'dot_plasticine\powershell\environment.ps1'
    $fragmentProbeScript = Join-Path $fragmentHome 'probe.ps1'
    $fragmentProbeBody = @"
`$env:PATH = 'C:\Windows;C:\Existing'
. '$environmentSource'
[Console]::Out.WriteLine(`$env:PATH)
`$env:PATH = (Join-Path `$HOME '.local\bin') + ';C:\Windows'
. '$environmentSource'
[Console]::Out.WriteLine(`$env:PATH)
"@
    Set-Content -LiteralPath $fragmentProbeScript -Value $fragmentProbeBody
    $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf) {
        try {
            $env:USERPROFILE = $fragmentHome
            $fragmentOutput = @(& $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $fragmentProbeScript 2>$null)
        } finally {
            $env:USERPROFILE = $previousUserProfile
        }
        $localBin = Join-Path $fragmentHome '.local\bin'
        $cargoBin = Join-Path $fragmentHome '.cargo\bin'
        Assert-Equal 2 $fragmentOutput.Count 'environment.ps1 wrote unexpected output'
        Assert-Equal ($localBin + ';' + $cargoBin + ';C:\Windows;C:\Existing') $fragmentOutput[0] `
            'environment.ps1 prepended the wrong PATH entries'
        Assert-Equal ($cargoBin + ';' + $localBin + ';C:\Windows') $fragmentOutput[1] `
            'environment.ps1 duplicated an existing PATH entry'
    }

    # --- The current host is always part of the target list, never hard-coded. ---
    $realTargets = @(Get-PlasticinePowershellProfileTargets)
    Assert-True ($realTargets.Count -ge 1) 'no PowerShell profile target was discovered'
    $currentProfile = [string]$PROFILE.CurrentUserAllHosts
    $currentFound = $false
    foreach ($realTarget in $realTargets) {
        if ($realTarget.Path -eq $currentProfile) { $currentFound = $true }
    }
    Assert-True $currentFound 'the current host $PROFILE.CurrentUserAllHosts is missing from the target list'

    # --- Insertion: a missing profile is created with exactly the block. ---
    $insertHome = New-TestDirectory 'insert-home'
    $insertProfile = Join-Path $insertHome 'Documents\WindowsPowerShell\profile.ps1'
    $insertBackup = Join-Path $insertHome '.plasticine\backups\powershell'
    $insertResult = Update-PlasticinePowershellProfile -Path $insertProfile -Block $block `
        -BackupDirectory $insertBackup -Label 'WindowsPowerShell-profile.ps1'
    Assert-True $insertResult.Changed 'creating a missing profile reported no change'
    Assert-True (Test-PlasticinePowershellBytesEqual -Left $blockBytes `
        -Right ([IO.File]::ReadAllBytes($insertProfile))) 'the created profile is not exactly the managed block'
    $secondResult = Update-PlasticinePowershellProfile -Path $insertProfile -Block $block `
        -BackupDirectory $insertBackup -Label 'WindowsPowerShell-profile.ps1'
    Assert-True (-not $secondResult.Changed) 'the second profile update was not idempotent'
    Assert-True (-not (Test-Path -LiteralPath $insertBackup)) 'an idempotent update created a backup'

    # --- Bytes outside the block survive byte for byte (CRLF, non-ASCII and a
    # missing final newline included). A prepended block stays first. ---
    $ownerBytes = [byte[]]([Text.Encoding]::UTF8.GetBytes("# Owner profile`r`nWrite-Host 'owner'`r`n") + [byte[]](0xE6, 0x97, 0xA7, 0xE7, 0x8E, 0xAF, 0xE5, 0xA2, 0x83, 255))
    [IO.File]::WriteAllBytes($insertProfile, $ownerBytes)
    $prependResult = Update-PlasticinePowershellProfile -Path $insertProfile -Block $block `
        -BackupDirectory $insertBackup -Label 'WindowsPowerShell-profile.ps1'
    Assert-True $prependResult.Changed 'prepending the block over Owner bytes reported no change'
    Assert-True (Test-PlasticinePowershellBytesEqual -Left ([byte[]]($blockBytes + $ownerBytes)) `
        -Right ([IO.File]::ReadAllBytes($insertProfile))) 'bytes outside the block were not preserved'
    $insertText = (Get-PlasticinePowershellLatin1).GetString([IO.File]::ReadAllBytes($insertProfile))
    Assert-Equal 1 ([regex]::Matches($insertText, [regex]::Escape('# >>> Plasticine powershell >>>')).Count) `
        'the profile carries more than one Plasticine block'
    Assert-True (Test-Path -LiteralPath $insertBackup) 'the changed profile was not backed up'
    Assert-Equal 1 @(Get-ChildItem -LiteralPath $insertBackup -Filter '*.plasticine-backup-*' -File).Count `
        'the changed profile backup was not recorded'

    # --- Replacement: an existing block is rewritten in place and the previous
    # whole file is retained as the backup. ---
    $replaceHome = New-TestDirectory 'replace-home'
    $replaceProfile = Join-Path $replaceHome 'Documents\PowerShell\profile.ps1'
    $replaceBackup = Join-Path $replaceHome '.plasticine\backups\powershell'
    New-Item -ItemType Directory -Path (Split-Path -Parent $replaceProfile) -Force | Out-Null
    $oldBlock = $block.Replace('environment.ps1', 'environment-old.ps1')
    $prefixBytes = [Text.Encoding]::UTF8.GetBytes("# Owner prefix`r`n")
    $suffixBytes = [Text.Encoding]::UTF8.GetBytes("# Owner suffix`r`n")
    $originalBytes = [byte[]]($prefixBytes + (Get-PlasticinePowershellLatin1).GetBytes($oldBlock) + $suffixBytes)
    [IO.File]::WriteAllBytes($replaceProfile, $originalBytes)
    $replaceResult = Update-PlasticinePowershellProfile -Path $replaceProfile -Block $block `
        -BackupDirectory $replaceBackup -Label 'PowerShell-profile.ps1'
    Assert-True $replaceResult.Changed 'replacing the stale block reported no change'
    Assert-True (Test-PlasticinePowershellBytesEqual `
        -Left ([byte[]]($prefixBytes + $blockBytes + $suffixBytes)) `
        -Right ([IO.File]::ReadAllBytes($replaceProfile))) 'owned bytes around the replaced block were not preserved'
    Assert-True ([bool]$replaceResult.BackupPath) 'the replaced profile has no backup'
    Assert-True (Test-PlasticinePowershellBytesEqual -Left $originalBytes `
        -Right ([IO.File]::ReadAllBytes($replaceResult.BackupPath))) 'the backup is not the whole previous profile'
    Assert-True ((Split-Path -Leaf $replaceResult.BackupPath) -match '^PowerShell-profile\.ps1\.plasticine-backup-[0-9a-f]{8}$') `
        'the backup name lost its host label'
    $replaceAgain = Update-PlasticinePowershellProfile -Path $replaceProfile -Block $block `
        -BackupDirectory $replaceBackup -Label 'PowerShell-profile.ps1'
    Assert-True (-not $replaceAgain.Changed) 'the replacement was not idempotent'
    Assert-Equal 1 @(Get-ChildItem -LiteralPath $replaceBackup -Filter '*.plasticine-backup-*' -File).Count `
        'an idempotent replacement added a backup'

    # --- Damaged marker blocks are refused without touching the file. ---
    $damagedHome = New-TestDirectory 'damaged-home'
    $damagedProfile = Join-Path $damagedHome 'Documents\WindowsPowerShell\profile.ps1'
    New-Item -ItemType Directory -Path (Split-Path -Parent $damagedProfile) -Force | Out-Null
    $damagedBackup = Join-Path $damagedHome '.plasticine\backups\powershell'
    $unterminatedBytes = [Text.Encoding]::UTF8.GetBytes("# Owner`r`n# >>> Plasticine powershell >>>`r`nWrite-Host 'half'`r`n")
    [IO.File]::WriteAllBytes($damagedProfile, $unterminatedBytes)
    $null = Assert-Throws {
        Update-PlasticinePowershellProfile -Path $damagedProfile -Block $block `
            -BackupDirectory $damagedBackup -Label 'damaged'
    } 'an unterminated marker block was accepted'
    Assert-True (Test-PlasticinePowershellBytesEqual -Left $unterminatedBytes `
        -Right ([IO.File]::ReadAllBytes($damagedProfile))) 'the refused update changed the damaged profile'
    $duplicateBytes = [Text.Encoding]::UTF8.GetBytes($block + $block)
    [IO.File]::WriteAllBytes($damagedProfile, $duplicateBytes)
    $null = Assert-Throws {
        Update-PlasticinePowershellProfile -Path $damagedProfile -Block $block `
            -BackupDirectory $damagedBackup -Label 'damaged'
    } 'a duplicated marker block was accepted'
    Assert-True (Test-PlasticinePowershellBytesEqual -Left $duplicateBytes `
        -Right ([IO.File]::ReadAllBytes($damagedProfile))) 'the refused update changed the duplicated profile'

    # --- Non-regular targets are refused instead of replaced. ---
    $directoryTarget = Join-Path (New-TestDirectory 'directory-home') 'Documents\WindowsPowerShell\profile.ps1'
    New-Item -ItemType Directory -Path $directoryTarget -Force | Out-Null
    $directoryBackup = Join-Path (Split-Path -Parent (Split-Path -Parent $directoryTarget)) '.plasticine\backups\powershell'
    $null = Assert-Throws {
        Update-PlasticinePowershellProfile -Path $directoryTarget -Block $block `
            -BackupDirectory $directoryBackup -Label 'directory'
    } 'a directory profile target was accepted'
    $fileParentHome = New-TestDirectory 'file-parent-home'
    $fileParentDocuments = Join-Path $fileParentHome 'Documents'
    New-Item -ItemType Directory -Path $fileParentDocuments -Force | Out-Null
    $fileParent = Join-Path $fileParentDocuments 'WindowsPowerShell'
    Set-Content -LiteralPath $fileParent -Value 'not a directory'
    $null = Assert-Throws {
        Update-PlasticinePowershellProfile -Path (Join-Path $fileParent 'profile.ps1') -Block $block `
            -BackupDirectory (Join-Path $fileParentHome '.plasticine\backups\powershell') -Label 'file-parent'
    } 'a file profile parent was accepted'

    # --- Personal PATH: append once, keep order and the registry value kind. ---
    $registryTestKey = 'Software\PlasticineDotfilesTest.' + [IO.Path]::GetRandomFileName()
    $PlasticineUserEnvironmentSubKey = $registryTestKey + '\Environment'
    $registryKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($PlasticineUserEnvironmentSubKey)
    $rawPath = 'C:\Existing;%USERPROFILE%\tools'
    $registryKey.SetValue('Path', $rawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
    $registryKey.Dispose()

    $planHome = New-TestDirectory 'plan-home'
    $planProfile = Join-Path $planHome 'Documents\WindowsPowerShell\profile.ps1'
    New-Item -ItemType Directory -Path (Split-Path -Parent $planProfile) -Force | Out-Null
    $PlasticinePowershellProfileTargetsOverride = @([pscustomobject]@{
            Label = 'Windows PowerShell'; Path = $planProfile; BackupLabel = 'WindowsPowerShell-profile.ps1'
        })
    $plan = Get-PlasticinePowershellPlan -HomeDirectory $planHome
    Assert-Equal (Join-Path $planHome '.local\bin') $plan.PathDirectory 'the plan PATH target drifted'
    Assert-True $plan.PathMissing 'the plan missed the missing user PATH entry'
    Assert-True (-not $plan.ExecutionPolicyBlocked) 'RemoteSigned was reported as blocking profiles'
    Assert-Equal 1 @($plan.ProfileTargets).Count 'the target override was not honoured'
    Assert-True (-not $plan.ProfileTargets[0].Exists) 'the plan invented an existing profile'
    $preview = Invoke-TestCapture { Write-PlasticinePowershellPreview -Plan $plan }
    Assert-True (-not $preview.Threw) ("preview failed: " + $preview.Message)
    Assert-True ($preview.Output -match 'will create') 'the preview omitted the planned profile creation'
    Assert-True ($preview.Output -match [regex]::Escape($plan.PathDirectory)) 'the preview omitted the PATH target'

    # --- Execution policy: Restricted/AllSigned stop with an exact command;
    # the refusal happens before any PATH write. ---
    $PlasticinePowershellExecutionPolicyOverride = 'Restricted'
    $blockedPlan = Get-PlasticinePowershellPlan -HomeDirectory $planHome
    Assert-True $blockedPlan.ExecutionPolicyBlocked 'a Restricted policy was not reported as blocking'
    $blockedPreview = Invoke-TestCapture { Write-PlasticinePowershellPreview -Plan $blockedPlan }
    Assert-True $blockedPreview.Threw 'a Restricted execution policy passed preview'
    Assert-True ($blockedPreview.Error -match 'Set-ExecutionPolicy -Scope CurrentUser RemoteSigned') `
        'the policy failure dropped the exact remediation command'
    $pathBeforeRefusal = Get-PlasticineUserPath
    $null = Assert-Throws { Invoke-PlasticinePowershellPrepare -Plan $blockedPlan } `
        'prepare ran under a Restricted execution policy'
    Assert-Equal $pathBeforeRefusal (Get-PlasticineUserPath) 'the refused prepare still changed the user PATH'
    $PlasticinePowershellExecutionPolicyOverride = 'AllSigned'
    $null = Assert-Throws { Assert-PlasticinePowershellExecutionPolicy } 'AllSigned was accepted'
    $PlasticinePowershellExecutionPolicyOverride = 'RemoteSigned'
    $null = Assert-PlasticinePowershellExecutionPolicy

    # --- Prepare: the user PATH gains ~/.local/bin exactly once. ---
    $prepare = Invoke-TestCapture { Invoke-PlasticinePowershellPrepare -Plan $plan }
    Assert-True (-not $prepare.Threw) ("prepare failed: " + $prepare.Message)
    Assert-True ($prepare.Output -match 'reopen the terminal') 'prepare did not ask for a new terminal'
    $expectedPath = $rawPath + ';' + (Join-Path $planHome '.local\bin')
    Assert-Equal $expectedPath (Get-PlasticineUserPath) 'the user PATH addition lost entries or order'
    $registryKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($PlasticineUserEnvironmentSubKey)
    Assert-Equal ([Microsoft.Win32.RegistryValueKind]::ExpandString) $registryKey.GetValueKind('Path') `
        'the PATH value kind was downgraded'
    $registryKey.Dispose()
    $secondPrepare = Invoke-TestCapture { Invoke-PlasticinePowershellPrepare -Plan $plan }
    Assert-True (-not $secondPrepare.Threw) ("the repeated prepare failed: " + $secondPrepare.Message)
    Assert-True ($secondPrepare.Output -match 'nothing to change') 'the repeated prepare claimed a change'
    Assert-Equal $expectedPath (Get-PlasticineUserPath) 'the repeated prepare duplicated the entry'
    $freshPlan = Get-PlasticinePowershellPlan -HomeDirectory $planHome
    Assert-True (-not $freshPlan.PathMissing) 'the plan still reports the written PATH entry missing'

    # --- A trailing-backslash duplicate is recognised before writing. ---
    $registryKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($PlasticineUserEnvironmentSubKey, $true)
    $duplicatePath = 'C:\Existing;' + (Join-Path $planHome '.local\bin') + '\'
    $registryKey.SetValue('Path', $duplicatePath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
    $registryKey.Dispose()
    $dedupePlan = Get-PlasticinePowershellPlan -HomeDirectory $planHome
    Assert-True (-not $dedupePlan.PathMissing) 'a trailing-backslash PATH duplicate was not recognised'
    $dedupePrepare = Invoke-TestCapture { Invoke-PlasticinePowershellPrepare -Plan $dedupePlan }
    Assert-True (-not $dedupePrepare.Threw) ("the deduplicated prepare failed: " + $dedupePrepare.Message)
    Assert-Equal $duplicatePath (Get-PlasticineUserPath) 'a present PATH entry was duplicated'

    # --- Preview refuses a non-regular profile target. ---
    $invalidPlan = Get-PlasticinePowershellPlan -HomeDirectory $planHome
    $invalidPlan.ProfileTargets = @([pscustomobject]@{
            Label = 'Windows PowerShell'; Path = $directoryTarget; BackupLabel = 'directory'
            Exists = $true; IsRegularFile = $false; HasBlock = $false; Damaged = $false
        })
    $invalidPreview = Invoke-TestCapture { Write-PlasticinePowershellPreview -Plan $invalidPlan }
    Assert-True $invalidPreview.Threw 'preview accepted a non-regular profile target'

    # --- The apply scripts only touch the Owner profile from the Owner home. ---
    $PlasticinePowershellProfileTargetsOverride = $null
    $ownerProfile = [Environment]::GetFolderPath('UserProfile')
    Assert-True (Test-PlasticinePowershellProfileMaintenance -DestDirectory $ownerProfile) `
        'the Owner home was rejected as a profile maintenance destination'
    Assert-True (-not (Test-PlasticinePowershellProfileMaintenance -DestDirectory $PlasticineTestRoot)) `
        'an isolated destination was treated as the Owner home'
    $redirectedDocuments = New-TestDirectory 'documents-redirect'
    $env:PLASTICINE_POWERSHELL_DOCUMENTS_DIR = $redirectedDocuments
    Assert-Equal $redirectedDocuments (Get-PlasticinePowershellDocumentsDirectory) `
        'the Documents redirect seam was ignored'
    $redirectedTargets = @(Get-PlasticinePowershellProfileTargets)
    $redirectedExpected = Join-Path $redirectedDocuments 'WindowsPowerShell\profile.ps1'
    $redirectedFound = $false
    foreach ($redirectedTarget in $redirectedTargets) {
        if ($redirectedTarget.Path -eq $redirectedExpected) { $redirectedFound = $true }
    }
    Assert-True $redirectedFound 'a redirected Documents root did not replace the real $PROFILE path'
    Assert-True (Test-PlasticinePowershellProfileMaintenance -DestDirectory $PlasticineTestRoot) `
        'the Documents redirect seam did not lift the Owner-home guard'

    Complete-Test 'windows powershell tests passed'
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
} finally {
    $env:USERPROFILE = $previousUserProfile
    $env:PLASTICINE_POWERSHELL_DOCUMENTS_DIR = $previousDocumentsRedirect
    if ($registryTestKey) {
        try { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($registryTestKey) } catch { }
    }
    Remove-Item -LiteralPath $PlasticineTestRoot -Recurse -Force -ErrorAction SilentlyContinue
}
