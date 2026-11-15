# Coverage for the Windows git-config and npmrc configuration routes: target
# shape validation, first-backup-wins retention, byte-exact npmrc composition,
# owner-only publication, the change-during-apply refusal and the apply-time
# template contract. Offline only: every scenario runs under $PlasticineTestRoot
# and never reads or writes the real home directory.
#
# A file symlink needs SeCreateSymbolicLinkPrivilege (Developer Mode or an
# elevated host); on a plain host this suite falls back to a directory junction,
# which exercises the same reparse-point refusal branch.

$repoDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'harness.ps1')
$PlasticineTestName = 'windows config'
. (Join-Path $repoDir 'lib\windows\common.ps1')
. (Join-Path $repoDir 'lib\windows\publish.ps1')
. (Join-Path $repoDir 'lib\windows\acl.ps1')
. (Join-Path $repoDir 'lib\windows\config-apply.ps1')
. (Join-Path $repoDir 'lib\windows\feature-git-config.ps1')
. (Join-Path $repoDir 'lib\windows\feature-npmrc.ps1')

$lf = "`n"
$crlf = "`r`n"
$quote = [string][char]39

function Read-TestText {
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

function ConvertTo-TestVisible {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    return $Text.Replace([string][char]13, '<CR>').Replace([string][char]10, '<LF>')
}

function Assert-TextEqual {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Expected,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Actual,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not [string]::Equals($Expected, $Actual, [StringComparison]::Ordinal)) {
        Fail ("$Message (expected '" + (ConvertTo-TestVisible $Expected) + "', observed '" +
            (ConvertTo-TestVisible $Actual) + "')")
    }
}

function Assert-FileTextEqual {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Message
    )
    Assert-TextEqual -Expected $Expected -Actual (Read-TestText $Path) -Message $Message
}

function Assert-OwnerOnlyAcl {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Message
    )
    $acl = Get-Acl -LiteralPath $Path
    Assert-True $acl.AreAccessRulesProtected "$Message is not protected: $($acl.Sddl)"
    Assert-Equal 1 @($acl.Access).Count "$Message does not have exactly one access rule"
    $owner = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $ruleOwner = $acl.Access[0].IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
    Assert-Equal $owner $ruleOwner "$Message is not limited to the current user"
    Assert-Equal 'FullControl' $acl.Access[0].FileSystemRights.ToString() "$Message does not grant full control to the owner"
}

function New-ScenarioHome {
    param([Parameter(Mandatory = $true)][string]$Name)
    $scenarioHome = Join-Path (New-TestDirectory $Name) 'home'
    New-Item -ItemType Directory -Path $scenarioHome -ErrorAction Stop | Out-Null
    return $scenarioHome
}

function New-Lines {
    param(
        [Parameter(Mandatory = $true)][string[]]$Line,
        [string]$Separator = "`n",
        [switch]$NoFinalNewline
    )
    $text = [string]::Join($Separator, $Line)
    if (-not $NoFinalNewline -and $Line.Count -gt 0) { $text += $Separator }
    return $text
}

# The portable reparse point: junctions need no privilege, file symlinks do.
function New-TestReparseTarget {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Target,
        [switch]$Directory
    )
    if ($Directory) {
        return (New-Item -ItemType Junction -Path $Path -Target $Target -ErrorAction Stop)
    }
    return (New-Item -ItemType SymbolicLink -Path $Path -Target $Target -ErrorAction Stop)
}

function Test-FileSymlinkSupport {
    $probeRoot = New-TestDirectory ('symlink-probe.' + [guid]::NewGuid().ToString('N'))
    $probeTarget = Join-Path $probeRoot 'target.txt'
    Set-Content -LiteralPath $probeTarget -Value 'probe' -NoNewline -ErrorAction Stop
    try {
        $null = New-Item -ItemType SymbolicLink -Path (Join-Path $probeRoot 'link.txt') -Target $probeTarget -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# A single-quoted ini key spelling, kept in a variable: an expression inside a
# command argument array is parsed in argument mode and would be split apart.
$quotedKeyFalseLine = $quote + 'dangerously-allow-all-scripts' + $quote + '=false'

$ownerFixtureLines = @(
    '# Owner preferences',
    'registry=https://registry.npmjs.org/',
    '//registry.npmjs.org/:_authToken=npmrc-private-marker',
    'ignore-scripts=true',
    '  dangerously-allow-all-scripts = false',
    '; keep this comment',
    'dangerously-allow-all-scripts[]=false',
    '"dangerously-allow-all-scripts"=false',
    $quotedKeyFalseLine,
    '@company:registry=https://registry.example.com/'
)
$ownerFixture = New-Lines $ownerFixtureLines
$ownerFixtureExpected = New-Lines @(
    '# Owner preferences',
    'registry=https://registry.npmjs.org/',
    '//registry.npmjs.org/:_authToken=npmrc-private-marker',
    'ignore-scripts=true',
    'dangerously-allow-all-scripts=true',
    '; keep this comment',
    '@company:registry=https://registry.example.com/'
)

try {
    # --- npmrc compose: the awk program from lib/npmrc-configuration.sh. ---
    $composeCases = @(
        @{ Name = 'empty input'; Input = ''; Expected = 'dangerously-allow-all-scripts=true' + $lf },
        @{ Name = 'already canonical'; Input = New-Lines @('dangerously-allow-all-scripts=true');
            Expected = New-Lines @('dangerously-allow-all-scripts=true') },
        @{ Name = 'existing scalar false'; Input = New-Lines @('registry=https://r.example/', 'dangerously-allow-all-scripts=false');
            Expected = New-Lines @('registry=https://r.example/', 'dangerously-allow-all-scripts=true') },
        @{ Name = 'existing scalar false without final newline';
            Input = New-Lines @('registry=https://r.example/', 'dangerously-allow-all-scripts=false') -NoFinalNewline;
            Expected = New-Lines @('registry=https://r.example/', 'dangerously-allow-all-scripts=true') -NoFinalNewline },
        @{ Name = 'double quoted key'; Input = New-Lines @('"dangerously-allow-all-scripts"=false');
            Expected = New-Lines @('dangerously-allow-all-scripts=true') },
        @{ Name = 'single quoted key'; Input = New-Lines @($quotedKeyFalseLine);
            Expected = New-Lines @('dangerously-allow-all-scripts=true') },
        @{ Name = 'array spelling'; Input = New-Lines @('dangerously-allow-all-scripts[]=false');
            Expected = New-Lines @('dangerously-allow-all-scripts=true') },
        @{ Name = 'spaced assignment with indentation'; Input = New-Lines @('  dangerously-allow-all-scripts = false');
            Expected = New-Lines @('dangerously-allow-all-scripts=true') },
        @{ Name = 'section only'; Input = New-Lines @('[owner]', 'registry=https://r.example/');
            Expected = New-Lines @('dangerously-allow-all-scripts=true', '[owner]', 'registry=https://r.example/') },
        @{ Name = 'section keeps the owner key'; Input = New-Lines @('[owner]', 'dangerously-allow-all-scripts=false', 'registry=x');
            Expected = New-Lines @('dangerously-allow-all-scripts=true', '[owner]', 'dangerously-allow-all-scripts=false', 'registry=x') },
        @{ Name = 'section key without a value'; Input = New-Lines @('[owner]', 'dangerously-allow-all-scripts');
            Expected = New-Lines @('dangerously-allow-all-scripts=true', '[owner]', 'dangerously-allow-all-scripts') },
        @{ Name = 'section with a trailing comment'; Input = New-Lines @('[owner] # comment', 'dangerously-allow-all-scripts=false');
            Expected = New-Lines @('dangerously-allow-all-scripts=true', '[owner] # comment', 'dangerously-allow-all-scripts=false') },
        @{ Name = 'duplicates outside a section are dropped'; Input = New-Lines @(
                'dangerously-allow-all-scripts[]=false',
                '"dangerously-allow-all-scripts"=false',
                $quotedKeyFalseLine,
                'registry=x');
            Expected = New-Lines @('dangerously-allow-all-scripts=true', 'registry=x') },
        @{ Name = 'owner fixture'; Input = $ownerFixture; Expected = $ownerFixtureExpected },
        @{ Name = 'CRLF preserved without a final newline'; Input = New-Lines @(
                'registry=https://registry.example.com/',
                'dangerously-allow-all-scripts=false',
                '# final comment') -Separator $crlf -NoFinalNewline;
            Expected = New-Lines @(
                'registry=https://registry.example.com/',
                'dangerously-allow-all-scripts=true',
                '# final comment') -Separator $crlf -NoFinalNewline },
        @{ Name = 'CRLF preserved with a final newline'; Input = New-Lines @(
                'registry=https://registry.example.com/',
                'dangerously-allow-all-scripts=false') -Separator $crlf;
            Expected = New-Lines @(
                'registry=https://registry.example.com/',
                'dangerously-allow-all-scripts=true') -Separator $crlf },
        @{ Name = 'missing final newline gains a line'; Input = '# no trailing newline';
            Expected = '# no trailing newline' + $lf + 'dangerously-allow-all-scripts=true' + $lf },
        @{ Name = 'blank line only'; Input = $lf;
            Expected = $lf + 'dangerously-allow-all-scripts=true' + $lf },
        @{ Name = 'comments mentioning the key are preserved'; Input = New-Lines @(
                ';dangerously-allow-all-scripts=false',
                '# dangerously-allow-all-scripts=false');
            Expected = New-Lines @(
                ';dangerously-allow-all-scripts=false',
                '# dangerously-allow-all-scripts=false',
                'dangerously-allow-all-scripts=true') },
        @{ Name = 'unrelated prefixes do not match'; Input = New-Lines @(
                'my-dangerously-allow-all-scripts=false',
                'dangerously-allow-all-scripts-extra=false');
            Expected = New-Lines @(
                'my-dangerously-allow-all-scripts=false',
                'dangerously-allow-all-scripts-extra=false',
                'dangerously-allow-all-scripts=true') }
    )
    foreach ($case in $composeCases) {
        $observed = New-PlasticineNpmrcContent -Text $case.Input
        Assert-TextEqual -Expected $case.Expected -Actual $observed `
            -Message ("the npmrc compose case '" + $case.Name + "' drifted from the sh/awk contract")
    }
    # The composition must be idempotent for every case: a second pass is a no-op.
    foreach ($case in $composeCases) {
        $once = New-PlasticineNpmrcContent -Text $case.Input
        $twice = New-PlasticineNpmrcContent -Text $once
        Assert-TextEqual -Expected $once -Actual $twice `
            -Message ("the npmrc compose case '" + $case.Name + "' is not idempotent")
    }

    # --- npmrc: plan and preview observe, and never print the content. ---
    $scenarioHome = New-ScenarioHome 'npmrc-plan'
    $target = Join-Path $scenarioHome '.npmrc'
    Write-TestText -Path $target -Text $ownerFixture
    $plan = Get-PlasticineNpmrcPlan -HomeDirectory $scenarioHome
    Assert-Equal $target $plan.Target 'the npmrc plan did not target ~/.npmrc'
    Assert-Equal (Join-Path $scenarioHome '.plasticine\backups\npmrc') $plan.BackupDirectory `
        'the npmrc plan did not name the backup directory'
    Assert-True $plan.Exists 'the npmrc plan missed an existing file'
    Assert-True $plan.IsRegularFile 'the npmrc plan rejected a regular file'
    Assert-True (-not $plan.Satisfied) 'the npmrc plan reported an outdated preference as satisfied'
    Assert-True $plan.BackupPending 'the npmrc plan did not report the pending backup'
    Assert-True (-not $plan.BackupExists) 'the npmrc plan invented a backup'
    $preview = Invoke-TestCapture { Write-PlasticineNpmrcPreview -Plan $plan }
    Assert-True (-not $preview.Threw) "the npmrc preview failed: $($preview.Message)"
    Assert-True ($preview.Output -match 'set dangerously-allow-all-scripts=true') 'the npmrc preview lost the planned setting'
    Assert-True ($preview.Output -match 'never printed') 'the npmrc preview lost the credential warning'
    Assert-True ($preview.Output -notmatch 'npmrc-private-marker') 'the npmrc preview leaked the file content'
    Assert-FileTextEqual -Path $target -Expected $ownerFixture 'the npmrc preview changed the file'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $scenarioHome '.plasticine'))) 'the npmrc preview created backup state'

    # --- npmrc: a missing file is created with the owner-only DACL. ---
    $scenarioHome = New-ScenarioHome 'npmrc-fresh'
    $target = Join-Path $scenarioHome '.npmrc'
    $fresh = Invoke-TestCapture { Invoke-PlasticineNpmrcApply -HomeDirectory $scenarioHome }
    Assert-True (-not $fresh.Threw) "the fresh npmrc apply failed: $($fresh.Message)"
    Assert-True ($fresh.Output -match 'created') 'the fresh npmrc apply did not report the creation'
    Assert-FileTextEqual -Path $target -Expected ('dangerously-allow-all-scripts=true' + $lf) `
        'the created ~/.npmrc does not contain exactly the managed preference'
    Assert-OwnerOnlyAcl -Path $target -Message 'the created ~/.npmrc'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $scenarioHome '.plasticine'))) `
        'the fresh npmrc apply created backup state'
    $converged = Invoke-TestCapture { Invoke-PlasticineNpmrcApply -HomeDirectory $scenarioHome }
    Assert-True (-not $converged.Threw) "the converged npmrc apply failed: $($converged.Message)"
    Assert-True ($converged.Output -match 'already has dangerously-allow-all-scripts=true') `
        'the converged npmrc apply did not report the satisfied preference'
    Assert-FileTextEqual -Path $target -Expected ('dangerously-allow-all-scripts=true' + $lf) `
        'the converged npmrc apply rewrote the file'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $scenarioHome '.plasticine'))) `
        'the converged npmrc apply created backup state'

    # --- npmrc: the owner fixture is rewritten in place, backed up once, and
    # the first backup survives later changes. ---
    $scenarioHome = New-ScenarioHome 'npmrc-update'
    $target = Join-Path $scenarioHome '.npmrc'
    $backupDirectory = Join-Path $scenarioHome '.plasticine\backups\npmrc'
    $backupPath = Join-Path $backupDirectory '.npmrc.plasticine-backup'
    Write-TestText -Path $target -Text $ownerFixture
    $update = Invoke-TestCapture { Invoke-PlasticineNpmrcApply -HomeDirectory $scenarioHome }
    Assert-True (-not $update.Threw) "the npmrc update failed: $($update.Message)"
    Assert-True ($update.Output -match 'backed up the previous ~/.npmrc') 'the npmrc update did not report the backup'
    Assert-True ($update.Output -notmatch 'npmrc-private-marker') 'the npmrc update leaked the file content'
    Assert-FileTextEqual -Path $target -Expected $ownerFixtureExpected `
        'the npmrc update did not compose the expected bytes'
    Assert-FileTextEqual -Path $backupPath -Expected $ownerFixture 'the npmrc backup is not the original file'
    Assert-OwnerOnlyAcl -Path $target -Message 'the updated ~/.npmrc'
    Assert-OwnerOnlyAcl -Path $backupPath -Message 'the npmrc backup'
    Assert-OwnerOnlyAcl -Path $backupDirectory -Message 'the npmrc backup directory'
    $updatedPlan = Get-PlasticineNpmrcPlan -HomeDirectory $scenarioHome
    Assert-True $updatedPlan.Satisfied 'the updated ~/.npmrc is not reported as satisfied'
    Assert-True $updatedPlan.BackupExists 'the updated ~/.npmrc is not reported as backed up'
    Assert-True (-not $updatedPlan.BackupPending) 'the updated ~/.npmrc still reports a pending backup'
    # A later change must not overwrite the pristine first backup.
    $laterInput = New-Lines @('registry=https://later.example/', 'dangerously-allow-all-scripts=false')
    $laterExpected = New-Lines @('registry=https://later.example/', 'dangerously-allow-all-scripts=true')
    Write-TestText -Path $target -Text $laterInput
    $later = Invoke-TestCapture { Invoke-PlasticineNpmrcApply -HomeDirectory $scenarioHome }
    Assert-True (-not $later.Threw) "the second npmrc update failed: $($later.Message)"
    Assert-True ($later.Output -match 'kept the earlier backup') 'the second npmrc update did not retain the first backup'
    Assert-FileTextEqual -Path $backupPath -Expected $ownerFixture 'the second npmrc update replaced the first backup'
    Assert-FileTextEqual -Path $target -Expected $laterExpected 'the second npmrc update did not compose the expected bytes'
    Assert-Equal 1 @(Get-ChildItem -LiteralPath $backupDirectory -Filter '*.plasticine-backup' -File).Count `
        'the second npmrc update added a second backup'
    # A converged rerun must neither rewrite the bytes nor add a backup.
    $converged = Invoke-TestCapture { Invoke-PlasticineNpmrcApply -HomeDirectory $scenarioHome }
    Assert-True (-not $converged.Threw) "the converged npmrc rerun failed: $($converged.Message)"
    Assert-True ($converged.Output -match 'already has dangerously-allow-all-scripts=true') `
        'the converged npmrc rerun did not report the satisfied preference'
    Assert-FileTextEqual -Path $target -Expected $laterExpected 'the converged npmrc rerun rewrote the file'
    Assert-Equal 1 @(Get-ChildItem -LiteralPath $backupDirectory -Filter '*.plasticine-backup' -File).Count `
        'the converged npmrc rerun added a backup'

    # --- npmrc: a file changed while the candidate is composed is refused
    # before any backup or replacement. ---
    $scenarioHome = New-ScenarioHome 'npmrc-race'
    $target = Join-Path $scenarioHome '.npmrc'
    $raceOriginal = New-Lines @('registry=https://race.example/', 'dangerously-allow-all-scripts=false')
    $raceCompeting = New-Lines @(
        'registry=https://race.example/',
        'ignore-scripts=true',
        'dangerously-allow-all-scripts=false')
    Write-TestText -Path $target -Text $raceOriginal
    $originalCompose = ${function:New-PlasticineNpmrcContent}
    function New-PlasticineNpmrcContent {
        param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
        [IO.File]::WriteAllText($target, $raceCompeting, (Get-PlasticineLatin1Encoding))
        return (& $originalCompose -Text $Text)
    }
    try {
        $race = Invoke-TestCapture { Invoke-PlasticineNpmrcApply -HomeDirectory $scenarioHome }
    } finally {
        ${function:New-PlasticineNpmrcContent} = $originalCompose
    }
    Assert-True $race.Threw 'a ~/.npmrc changed during apply reported success'
    Assert-True ($race.Error -match 'changed during apply; retry') 'the change-during-apply refusal was not reported'
    Assert-FileTextEqual -Path $target -Expected $raceCompeting 'the refused npmrc apply changed the competing file'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $scenarioHome '.plasticine'))) `
        'the refused npmrc apply created backup state'

    # --- npmrc: a directory target is refused by validate, preview and apply. ---
    $scenarioHome = New-ScenarioHome 'npmrc-directory-target'
    $target = Join-Path $scenarioHome '.npmrc'
    New-Item -ItemType Directory -Path $target -ErrorAction Stop | Out-Null
    $directoryValidate = Invoke-TestCapture { Invoke-PlasticineNpmrcValidate -HomeDirectory $scenarioHome }
    Assert-True $directoryValidate.Threw 'a directory ~/.npmrc passed validation'
    Assert-True ($directoryValidate.Error -match 'must be a regular file') 'the directory target failure was not reported'
    $directoryPlan = Get-PlasticineNpmrcPlan -HomeDirectory $scenarioHome
    Assert-True (-not $directoryPlan.IsRegularFile) 'the npmrc plan accepted a directory target'
    Assert-True (@($directoryPlan.InvalidPaths).Count -gt 0) 'the npmrc plan did not report the invalid path'
    $directoryPreview = Invoke-TestCapture { Write-PlasticineNpmrcPreview -Plan $directoryPlan }
    Assert-True $directoryPreview.Threw 'the npmrc preview accepted a directory target'
    $directoryApply = Invoke-TestCapture { Invoke-PlasticineNpmrcApply -HomeDirectory $scenarioHome }
    Assert-True $directoryApply.Threw 'the npmrc apply accepted a directory target'
    Assert-True ($directoryApply.Error -match 'must be a regular file') 'the directory apply failure was not reported'
    Assert-True (Test-Path -LiteralPath $target -PathType Container) 'the refused directory target was changed'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $scenarioHome '.plasticine'))) `
        'the refused directory target created backup state'

    # --- npmrc: a reparse-point target is refused the same way. ---
    $scenarioHome = New-ScenarioHome 'npmrc-reparse-target'
    $target = Join-Path $scenarioHome '.npmrc'
    $linkTargetRoot = New-TestDirectory 'npmrc-link-target'
    if (Test-FileSymlinkSupport) {
        $linkTarget = Join-Path $linkTargetRoot 'owner.npmrc'
        Write-TestText -Path $linkTarget -Text 'registry=https://linked.example/'
        $link = New-TestReparseTarget -Path $target -Target $linkTarget
    } else {
        $link = New-TestReparseTarget -Path $target -Target $linkTargetRoot -Directory
    }
    Assert-True (Test-PlasticineReparsePoint (Get-PlasticineItem $target)) 'the npmrc reparse target was not created'
    $reparseValidate = Invoke-TestCapture { Invoke-PlasticineNpmrcValidate -HomeDirectory $scenarioHome }
    Assert-True $reparseValidate.Threw 'a reparse-point ~/.npmrc passed validation'
    Assert-True ($reparseValidate.Error -match 'must be a regular file') 'the reparse target failure was not reported'
    $reparsePlan = Get-PlasticineNpmrcPlan -HomeDirectory $scenarioHome
    Assert-True (-not $reparsePlan.IsRegularFile) 'the npmrc plan accepted a reparse-point target'
    $reparseApply = Invoke-TestCapture { Invoke-PlasticineNpmrcApply -HomeDirectory $scenarioHome }
    Assert-True $reparseApply.Threw 'the npmrc apply accepted a reparse-point target'
    Assert-True (Test-PlasticineReparsePoint (Get-PlasticineItem $target)) 'the refused reparse-point target was changed'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $scenarioHome '.plasticine'))) `
        'the refused reparse-point target created backup state'

    # --- npmrc: an invalid backup parent is refused without touching the file. ---
    $scenarioHome = New-ScenarioHome 'npmrc-invalid-backup-parent'
    $target = Join-Path $scenarioHome '.npmrc'
    Write-TestText -Path $target -Text $ownerFixture
    New-Item -ItemType Directory -Path (Join-Path $scenarioHome '.plasticine') -ErrorAction Stop | Out-Null
    Set-Content -LiteralPath (Join-Path $scenarioHome '.plasticine\backups') -Value 'blocker' -NoNewline
    $invalidParent = Invoke-TestCapture { Invoke-PlasticineNpmrcApply -HomeDirectory $scenarioHome }
    Assert-True $invalidParent.Threw 'an invalid npmrc backup parent was accepted'
    Assert-True ($invalidParent.Error -match 'must be a regular directory') 'the invalid backup parent failure was not reported'
    Assert-FileTextEqual -Path $target -Expected $ownerFixture 'the invalid backup parent changed ~/.npmrc'

    # --- git-config: plan and preview observe the target and the backup state. ---
    $scenarioHome = New-ScenarioHome 'gitconfig-plan'
    $target = Join-Path $scenarioHome '.gitconfig'
    $ownerGitConfig = New-Lines @('[user]', "`tname = owner", '[init]', "`tdefaultBranch = main")
    Write-TestText -Path $target -Text $ownerGitConfig
    $plan = Get-PlasticineGitConfigPlan -HomeDirectory $scenarioHome
    Assert-Equal $target $plan.Target 'the git-config plan did not target ~/.gitconfig'
    Assert-Equal (Join-Path $scenarioHome '.plasticine\backups\git-config') $plan.BackupDirectory `
        'the git-config plan did not name the backup directory'
    Assert-True $plan.Exists 'the git-config plan missed an existing file'
    Assert-True $plan.IsRegularFile 'the git-config plan rejected a regular file'
    Assert-True $plan.BackupPending 'the git-config plan did not report the pending backup'
    Assert-True (-not $plan.BackupExists) 'the git-config plan invented a backup'
    $preview = Invoke-TestCapture { Write-PlasticineGitConfigPreview -Plan $plan }
    Assert-True (-not $preview.Threw) "the git-config preview failed: $($preview.Message)"
    Assert-True ($preview.Output -match 'will back up the current') 'the git-config preview lost the planned backup'
    Assert-True ($preview.Output -match [regex]::Escape($plan.BackupDirectory)) 'the git-config preview lost the backup directory'
    Assert-True ($preview.Output -match 'no file mode') 'the git-config preview lost the Windows mode note'
    Assert-FileTextEqual -Path $target -Expected $ownerGitConfig 'the git-config preview changed the file'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $scenarioHome '.plasticine'))) `
        'the git-config preview created backup state'

    # --- git-config: a missing target needs no backup and is left to chezmoi. ---
    $scenarioHome = New-ScenarioHome 'gitconfig-fresh'
    $sourceDirectory = New-TestDirectory 'gitconfig-fresh-source'
    $managedGitConfig = New-Lines @('[user]', "`tname = plasticine", '[init]', "`tdefaultBranch = main")
    Write-TestText -Path (Join-Path $sourceDirectory 'dot_gitconfig') -Text $managedGitConfig
    $fresh = Invoke-TestCapture {
        Invoke-PlasticineGitConfigApply -HomeDirectory $scenarioHome -SourceDirectory $sourceDirectory
    }
    Assert-True (-not $fresh.Threw) "the fresh git-config apply failed: $($fresh.Message)"
    Assert-True ($fresh.Output -match 'does not exist') 'the fresh git-config apply did not report the missing target'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $scenarioHome '.gitconfig'))) `
        'the git-config apply published the managed file instead of leaving it to chezmoi'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $scenarioHome '.plasticine'))) `
        'the fresh git-config apply created backup state'

    # --- git-config: the first backup wins and a converged rerun is inert. ---
    $scenarioHome = New-ScenarioHome 'gitconfig-backup'
    $sourceDirectory = New-TestDirectory 'gitconfig-backup-source'
    Write-TestText -Path (Join-Path $sourceDirectory 'dot_gitconfig') -Text $managedGitConfig
    $target = Join-Path $scenarioHome '.gitconfig'
    $backupPath = Join-Path $scenarioHome '.plasticine\backups\git-config\.gitconfig.plasticine-backup'
    $oldOwner = New-Lines @('[user]', "`tname = old-shared-owner")
    Write-TestText -Path $target -Text $oldOwner
    $apply = Invoke-TestCapture {
        Invoke-PlasticineGitConfigApply -HomeDirectory $scenarioHome -SourceDirectory $sourceDirectory
    }
    Assert-True (-not $apply.Threw) "the git-config backup failed: $($apply.Message)"
    Assert-True ($apply.Output -match 'backed up the previous configuration') 'the git-config backup was not reported'
    Assert-FileTextEqual -Path $backupPath -Expected $oldOwner 'the git-config backup is not the previous file'
    Assert-FileTextEqual -Path $target -Expected $oldOwner 'the git-config apply replaced the file instead of only backing it up'
    Assert-OwnerOnlyAcl -Path $backupPath -Message 'the git-config backup'
    Assert-OwnerOnlyAcl -Path (Split-Path -Parent $backupPath) -Message 'the git-config backup directory'
    $backedUpPlan = Get-PlasticineGitConfigPlan -HomeDirectory $scenarioHome
    Assert-True $backedUpPlan.BackupExists 'the git-config plan missed the retained backup'
    Assert-True (-not $backedUpPlan.BackupPending) 'the git-config plan still reports a pending backup'
    # A later change must not overwrite the pristine first backup.
    $laterOwner = New-Lines @('[user]', "`tname = later-owner")
    Write-TestText -Path $target -Text $laterOwner
    $second = Invoke-TestCapture {
        Invoke-PlasticineGitConfigApply -HomeDirectory $scenarioHome -SourceDirectory $sourceDirectory
    }
    Assert-True (-not $second.Threw) "the second git-config apply failed: $($second.Message)"
    Assert-True ($second.Output -match 'kept the earlier backup') 'the second git-config apply did not retain the first backup'
    Assert-FileTextEqual -Path $backupPath -Expected $oldOwner 'the second git-config apply replaced the first backup'
    Assert-Equal 1 @(Get-ChildItem -LiteralPath (Split-Path -Parent $backupPath) -Filter '*.plasticine-backup' -File).Count `
        'the second git-config apply added a second backup'
    # Converged content (equal to the managed source) needs no backup.
    Write-TestText -Path $target -Text $managedGitConfig
    $converged = Invoke-TestCapture {
        Invoke-PlasticineGitConfigApply -HomeDirectory $scenarioHome -SourceDirectory $sourceDirectory
    }
    Assert-True (-not $converged.Threw) "the converged git-config apply failed: $($converged.Message)"
    Assert-True ($converged.Output -match 'already matches the managed content') `
        'the converged git-config apply did not report the matching content'
    Assert-FileTextEqual -Path $target -Expected $managedGitConfig 'the converged git-config apply rewrote the file'
    Assert-FileTextEqual -Path $backupPath -Expected $oldOwner 'the converged git-config apply replaced the first backup'

    # --- git-config: validate accepts a regular target and creates nothing. ---
    $scenarioHome = New-ScenarioHome 'gitconfig-valid'
    Write-TestText -Path (Join-Path $scenarioHome '.gitconfig') -Text $ownerGitConfig
    $valid = Invoke-TestCapture { Invoke-PlasticineGitConfigValidate -HomeDirectory $scenarioHome }
    Assert-True (-not $valid.Threw) "the git-config validation failed on a regular file: $($valid.Message)"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $scenarioHome '.plasticine'))) `
        'the git-config validation created backup state'

    # --- git-config: a directory target is refused by validate, preview and apply. ---
    $scenarioHome = New-ScenarioHome 'gitconfig-directory-target'
    $target = Join-Path $scenarioHome '.gitconfig'
    New-Item -ItemType Directory -Path $target -ErrorAction Stop | Out-Null
    $directoryValidate = Invoke-TestCapture { Invoke-PlasticineGitConfigValidate -HomeDirectory $scenarioHome }
    Assert-True $directoryValidate.Threw 'a directory ~/.gitconfig passed validation'
    Assert-True ($directoryValidate.Error -match 'must be a regular file') 'the git-config directory failure was not reported'
    $directoryPlan = Get-PlasticineGitConfigPlan -HomeDirectory $scenarioHome
    Assert-True (-not $directoryPlan.IsRegularFile) 'the git-config plan accepted a directory target'
    $directoryPreview = Invoke-TestCapture { Write-PlasticineGitConfigPreview -Plan $directoryPlan }
    Assert-True $directoryPreview.Threw 'the git-config preview accepted a directory target'
    $directoryApply = Invoke-TestCapture {
        Invoke-PlasticineGitConfigApply -HomeDirectory $scenarioHome -SourceDirectory $sourceDirectory
    }
    Assert-True $directoryApply.Threw 'the git-config apply accepted a directory target'
    Assert-True (Test-Path -LiteralPath $target -PathType Container) 'the refused directory target was changed'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $scenarioHome '.plasticine'))) `
        'the refused directory target created backup state'

    # --- git-config: a reparse-point target is refused the same way. ---
    $scenarioHome = New-ScenarioHome 'gitconfig-reparse-target'
    $target = Join-Path $scenarioHome '.gitconfig'
    $linkTargetRoot = New-TestDirectory 'gitconfig-link-target'
    if (Test-FileSymlinkSupport) {
        $linkTarget = Join-Path $linkTargetRoot 'owner.gitconfig'
        Write-TestText -Path $linkTarget -Text $ownerGitConfig
        $null = New-TestReparseTarget -Path $target -Target $linkTarget
    } else {
        $null = New-TestReparseTarget -Path $target -Target $linkTargetRoot -Directory
    }
    Assert-True (Test-PlasticineReparsePoint (Get-PlasticineItem $target)) 'the git-config reparse target was not created'
    $reparseValidate = Invoke-TestCapture { Invoke-PlasticineGitConfigValidate -HomeDirectory $scenarioHome }
    Assert-True $reparseValidate.Threw 'a reparse-point ~/.gitconfig passed validation'
    Assert-True ($reparseValidate.Error -match 'must be a regular file') 'the git-config reparse failure was not reported'
    $reparseApply = Invoke-TestCapture {
        Invoke-PlasticineGitConfigApply -HomeDirectory $scenarioHome -SourceDirectory $sourceDirectory
    }
    Assert-True $reparseApply.Threw 'the git-config apply accepted a reparse-point target'
    Assert-True (Test-PlasticineReparsePoint (Get-PlasticineItem $target)) 'the refused reparse-point target was changed'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $scenarioHome '.plasticine'))) `
        'the refused reparse-point target created backup state'

    # --- git-config: an invalid backup parent is refused without touching the file. ---
    $scenarioHome = New-ScenarioHome 'gitconfig-invalid-backup-parent'
    $target = Join-Path $scenarioHome '.gitconfig'
    Write-TestText -Path $target -Text $ownerGitConfig
    New-Item -ItemType Directory -Path (Join-Path $scenarioHome '.plasticine') -ErrorAction Stop | Out-Null
    Set-Content -LiteralPath (Join-Path $scenarioHome '.plasticine\backups') -Value 'blocker' -NoNewline
    $invalidParent = Invoke-TestCapture {
        Invoke-PlasticineGitConfigApply -HomeDirectory $scenarioHome -SourceDirectory $sourceDirectory
    }
    Assert-True $invalidParent.Threw 'an invalid git-config backup parent was accepted'
    Assert-True ($invalidParent.Error -match 'must be a regular directory') 'the invalid backup parent failure was not reported'
    Assert-FileTextEqual -Path $target -Expected $ownerGitConfig 'the invalid backup parent changed ~/.gitconfig'

    # --- git-config: a missing managed source is refused. ---
    $scenarioHome = New-ScenarioHome 'gitconfig-missing-source'
    Write-TestText -Path (Join-Path $scenarioHome '.gitconfig') -Text $ownerGitConfig
    $emptySource = New-TestDirectory 'gitconfig-empty-source'
    $missingSource = Invoke-TestCapture {
        Invoke-PlasticineGitConfigApply -HomeDirectory $scenarioHome -SourceDirectory $emptySource
    }
    Assert-True $missingSource.Threw 'a missing managed gitconfig source was accepted'
    Assert-True ($missingSource.Error -match 'managed source is not a regular file') 'the missing source failure was not reported'

    # --- Provider registration: both Features follow the Windows registry
    # contract and have no prepare step (the apply scripts own the writes). ---
    . (Join-Path $repoDir 'lib\windows\features.ps1')
    Assert-Equal 'Get-PlasticineGitConfigPlan' (Get-PlasticineFeaturePlanFunction 'git-config') `
        'the git-config plan name drifted from the Feature registry convention'
    Assert-Equal 'Write-PlasticineGitConfigPreview' (Get-PlasticineFeaturePreviewFunction 'git-config') `
        'the git-config preview name drifted from the Feature registry convention'
    Assert-Equal 'Get-PlasticineNpmrcPlan' (Get-PlasticineFeaturePlanFunction 'npmrc') `
        'the npmrc plan name drifted from the Feature registry convention'
    Assert-Equal 'Write-PlasticineNpmrcPreview' (Get-PlasticineFeaturePreviewFunction 'npmrc') `
        'the npmrc preview name drifted from the Feature registry convention'
    Assert-True (Test-PlasticineFunction (Get-PlasticineFeaturePlanFunction 'git-config')) `
        'the git-config plan provider is missing'
    Assert-True (Test-PlasticineFunction (Get-PlasticineFeaturePreviewFunction 'git-config')) `
        'the git-config preview provider is missing'
    Assert-True (Test-PlasticineFunction (Get-PlasticineFeaturePlanFunction 'npmrc')) `
        'the npmrc plan provider is missing'
    Assert-True (Test-PlasticineFunction (Get-PlasticineFeaturePreviewFunction 'npmrc')) `
        'the npmrc preview provider is missing'
    Assert-True ($PlasticineFeatureOrder -contains 'git-config') 'git-config is missing from the Feature order'
    Assert-True ($PlasticineFeatureOrder -contains 'npmrc') 'npmrc is missing from the Feature order'
    Assert-True ($PlasticineFeaturePreviewRequired -contains 'npmrc') `
        'npmrc is not registered as a preview-required Feature'
    $scenarioHome = New-ScenarioHome 'provider-prepare'
    $target = Join-Path $scenarioHome '.gitconfig'
    Write-TestText -Path $target -Text $ownerGitConfig
    $prepare = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'git-config' -HomeDirectory $scenarioHome }
    Assert-True (-not $prepare.Threw) "the git-config Feature unexpectedly has a prepare step: $($prepare.Message)"
    Assert-FileTextEqual -Path $target -Expected $ownerGitConfig 'the git-config prepare step changed the file'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $scenarioHome '.plasticine'))) `
        'the git-config prepare step created backup state'
    $prepare = Invoke-TestCapture { Invoke-PlasticineFeaturePrepare -Feature 'npmrc' -HomeDirectory $scenarioHome }
    Assert-True (-not $prepare.Threw) "the npmrc Feature unexpectedly has a prepare step: $($prepare.Message)"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $scenarioHome '.npmrc'))) `
        'the npmrc prepare step created the target'

    # --- Template contract: platform guard, feature guard and parseable body. ---
    $templateExpectations = @(
        @{ File = 'run_before_00_validate_git_config.ps1.tmpl'; Feature = 'git-config'; Function = 'Invoke-PlasticineGitConfigValidate' },
        @{ File = 'run_before_20_git_configuration.ps1.tmpl'; Feature = 'git-config'; Function = 'Invoke-PlasticineGitConfigApply' },
        @{ File = 'run_before_00_validate_npmrc.ps1.tmpl'; Feature = 'npmrc'; Function = 'Invoke-PlasticineNpmrcValidate' },
        @{ File = 'run_before_23_npmrc_configuration.ps1.tmpl'; Feature = 'npmrc'; Function = 'Invoke-PlasticineNpmrcApply' }
    )
    foreach ($expectation in $templateExpectations) {
        $templatePath = Join-Path $repoDir ('.chezmoiscripts\' + $expectation.File)
        Assert-True (Test-Path -LiteralPath $templatePath -PathType Leaf) "the apply template is missing: $templatePath"
        $raw = Get-Content -LiteralPath $templatePath -Raw
        Assert-True ($raw.StartsWith('{{- if eq .chezmoi.os "windows" -}}')) `
            ("the template '" + $expectation.File + "' lost its Windows platform guard")
        Assert-True ($raw.Contains('{{- if has "' + $expectation.Feature + '" .tools -}}')) `
            ("the template '" + $expectation.File + "' lost its feature guard")
        Assert-True ($raw.TrimEnd().EndsWith('{{- end -}}')) `
            ("the template '" + $expectation.File + "' does not end with the closing guards")
        Assert-True ($raw.Contains($expectation.Function)) `
            ("the template '" + $expectation.File + "' does not call " + $expectation.Function)
        $body = [regex]::Replace($raw, '\{\{\s*template "powershell-quote"\s+\.chezmoi\.(sourceDir|destDir)\s*\}\}', "'C:\fixture'")
        $body = [regex]::Replace($body, '\{\{[^}]*\}\}', '')
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseInput($body, [ref]$tokens, [ref]$errors)
        Assert-Equal 0 @($errors).Count ("the rendered " + $expectation.File + " body does not parse")
    }
    foreach ($modulePath in @(
            (Join-Path $repoDir 'lib\windows\feature-git-config.ps1'),
            (Join-Path $repoDir 'lib\windows\feature-npmrc.ps1'),
            (Join-Path $repoDir 'tests\windows\config.ps1'))) {
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($modulePath, [ref]$tokens, [ref]$errors)
        Assert-Equal 0 @($errors).Count ("the Windows configuration source does not parse: " + $modulePath)
    }

    Complete-Test 'windows config tests passed'
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
} finally {
    # Deletion is limited to the disposable root the harness created under TEMP.
    if ($PlasticineTestRoot -and (Test-Path -LiteralPath $PlasticineTestRoot -PathType Container)) {
        $resolvedRoot = [IO.Path]::GetFullPath($PlasticineTestRoot)
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($resolvedRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
            (Split-Path -Leaf $resolvedRoot).StartsWith('plasticine-windows-test.', [StringComparison]::Ordinal)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
