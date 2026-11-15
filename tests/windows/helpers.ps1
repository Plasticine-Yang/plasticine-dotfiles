# Unit coverage for the shared Windows helpers: ACL, publication, user PATH,
# archive validation and version parsing. No network and no real user PATH.

$repoDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'harness.ps1')
$PlasticineTestName = 'windows helpers'
. (Join-Path $repoDir 'lib\windows\common.ps1')
. (Join-Path $repoDir 'lib\windows\publish.ps1')
. (Join-Path $repoDir 'lib\windows\acl.ps1')
. (Join-Path $repoDir 'lib\windows\user-path.ps1')

# The stop diagnostic is written to stderr before the exception is thrown, so a
# probe has to capture both the stream and the exception object.
function Invoke-StopProbe {
    param([Parameter(Mandatory = $true)][scriptblock]$Body)
    $captured = New-Object IO.StringWriter
    $previous = [Console]::Error
    [Console]::SetError($captured)
    $exception = $null
    try {
        & $Body
    } catch {
        $exception = $_.Exception
    } finally {
        [Console]::SetError($previous)
    }
    return [pscustomobject]@{ Exception = $exception; Error = $captured.ToString() }
}

# Offline stand-in for the system curl: records the argument vector, then writes
# a file of the requested size or exits with the curl timeout code.
function New-CurlStub {
    param([Parameter(Mandatory = $true)][string]$Path)
    $source = @'
$arguments = @($args)
if ($env:PLASTICINE_TEST_CURL_LOG) {
    Set-Content -LiteralPath $env:PLASTICINE_TEST_CURL_LOG -Value ($arguments -join "`n")
}
if ($env:PLASTICINE_TEST_CURL_MODE -eq 'timeout') { exit 28 }
$destination = $null
for ($index = 0; $index -lt $arguments.Count; $index++) {
    if ($arguments[$index] -eq '-o') { $destination = $arguments[$index + 1] }
}
if ($destination) {
    $size = 0
    if ($env:PLASTICINE_TEST_CURL_SIZE) { $size = [int]$env:PLASTICINE_TEST_CURL_SIZE }
    [IO.File]::WriteAllBytes($destination, (New-Object byte[] $size))
}
exit 0
'@
    Set-Content -LiteralPath $Path -Value $source -Encoding ASCII
}

# The PowerShell 7 ACL writer cannot run in this host, so a child process covers
# the Core branch; the case is skipped when pwsh is not installed.
function New-Ps7AclChildScript {
    param([Parameter(Mandatory = $true)][string]$Path)
    $source = @'
param([string]$AclPath, [string]$RepoDir)
$ErrorActionPreference = 'Stop'
. (Join-Path $RepoDir 'lib\windows\acl.ps1')
if (-not ($PSVersionTable.PSEdition -eq 'Core')) { throw 'the child is not running PowerShell 7' }
if ((Get-PlasticineAclWriterKind) -ne 'extension') { throw 'the Core branch did not select the extension ACL writer' }
$backup = Get-PlasticineAclBackup -Path $AclPath
Set-PlasticineOwnerOnlyAcl -Path $AclPath
$tightened = (Get-Acl -LiteralPath $AclPath).Sddl
if ($tightened -notmatch 'D:PAI\(A;;FA;;;') { throw "the Core branch did not tighten the DACL: $tightened" }
Restore-PlasticineAcl -Path $AclPath -Backup $backup
$restored = Get-Acl -LiteralPath $AclPath
if ($restored.AreAccessRulesProtected) { throw 'the Core branch restore kept the DACL protected' }
if (@($restored.GetAccessRules($true, $false, [Security.Principal.SecurityIdentifier])).Count -ne 0) {
    throw 'the Core branch restore introduced explicit ACEs'
}
[Console]::Out.WriteLine('pwsh acl branch passed')
'@
    Set-Content -LiteralPath $Path -Value $source -Encoding ASCII
}

$registryTestKey = $null
try {
    $everyone = New-Object Security.Principal.SecurityIdentifier('S-1-1-0')
    $owner = [Security.Principal.WindowsIdentity]::GetCurrent().User

    # --- Stop-Plasticine: one prefixed stderr line and a catchable stop type. ---
    $stopProbe = Invoke-StopProbe { Stop-Plasticine 'helper stop diagnostic' }
    Assert-True ($stopProbe.Exception -is [PlasticineStopException]) 'Stop-Plasticine did not throw the typed stop exception'
    Assert-Equal 'helper stop diagnostic' $stopProbe.Exception.Message 'the typed stop exception lost its message'
    Assert-Equal 1 ([regex]::Matches($stopProbe.Error, 'plasticine-dotfiles: helper stop diagnostic')).Count `
        'the stop diagnostic was not printed exactly once'

    # --- Modules reload idempotently: seams and overrides survive a second load. ---
    $savedCurlCommand = $PlasticineCurlCommand
    $savedCurlTimeout = $PlasticineDownloadTimeoutSeconds
    $PlasticineCurlCommand = 'C:\sentinel\curl.exe'
    $PlasticineDownloadTimeoutSeconds = 123
    . (Join-Path $repoDir 'lib\windows\common.ps1')
    . (Join-Path $repoDir 'lib\windows\publish.ps1')
    . (Join-Path $repoDir 'lib\windows\acl.ps1')
    . (Join-Path $repoDir 'lib\windows\user-path.ps1')
    Assert-Equal 'C:\sentinel\curl.exe' $PlasticineCurlCommand 'reloading common.ps1 reset the curl seam'
    Assert-Equal 123 $PlasticineDownloadTimeoutSeconds 'reloading common.ps1 reset the download timeout seam'
    $PlasticineCurlCommand = $savedCurlCommand
    $PlasticineDownloadTimeoutSeconds = $savedCurlTimeout

    $savedSubKey = $PlasticineUserEnvironmentSubKey
    $PlasticineUserEnvironmentSubKey = 'Software\PlasticineSentinel'
    . (Join-Path $repoDir 'lib\windows\user-path.ps1')
    Assert-Equal 'Software\PlasticineSentinel' $PlasticineUserEnvironmentSubKey 'reloading user-path.ps1 reset the registry seam'
    $PlasticineUserEnvironmentSubKey = $savedSubKey

    $originalPublish = ${function:Publish-PlasticineNewFile}
    ${function:Publish-PlasticineNewFile} = { param($Candidate, $Target) throw 'seam override survived' }
    . (Join-Path $repoDir 'lib\windows\publish.ps1')
    $publishReload = Invoke-TestCapture { Publish-PlasticineNewFile -Candidate 'C:\candidate.exe' -Target 'C:\target.exe' }
    Assert-True ($publishReload.Message -match 'seam override survived') 'reloading publish.ps1 replaced an active function override'
    ${function:Publish-PlasticineNewFile} = $originalPublish

    # --- Path and name parameters are validated before any filesystem work. ---
    $relativeHashError = Assert-Throws { Get-PlasticineFileHash 'relative\file.bin' } 'a relative hash path was accepted'
    Assert-True ($relativeHashError -match 'must be absolute') 'the relative hash path failure was not reported'
    $relativeArchiveError = Assert-Throws {
        Expand-PlasticineArchive -Archive 'relative.zip' -Destination (Join-Path $PlasticineTestRoot 'relative-archive') -Member @('payload')
    } 'a relative archive path was accepted'
    Assert-True ($relativeArchiveError -match 'must be absolute') 'the relative archive path failure was not reported'
    $null = Assert-Throws { Get-PlasticineItem '' } 'an empty item path was accepted'
    $null = Assert-Throws { Get-PlasticineCommandPath '' } 'an empty command name was accepted'

    # --- Downloads carry a hard timeout and a size cap. ---
    $downloadDir = New-TestDirectory 'download'
    $curlStub = Join-Path $downloadDir 'curl-stub.ps1'
    New-CurlStub -Path $curlStub
    $savedCurl = $PlasticineCurlCommand
    $savedTimeout = $PlasticineDownloadTimeoutSeconds
    $savedConnectTimeout = $PlasticineDownloadConnectTimeoutSeconds
    $savedMaxBytes = $PlasticineDownloadMaxBytes
    $curlLog = Join-Path $downloadDir 'curl.log'
    $env:PLASTICINE_TEST_CURL_LOG = $curlLog
    try {
        $PlasticineCurlCommand = $curlStub
        $env:PLASTICINE_TEST_CURL_SIZE = '4'
        $bounded = Join-Path $downloadDir 'bounded.bin'
        Invoke-PlasticineDownload -Url 'https://example.invalid/bounded.bin' -Destination $bounded -FailureMessage 'bounded download failed'
        Assert-True (Test-Path -LiteralPath $bounded -PathType Leaf) 'the bounded download did not write its destination'
        $curlCall = Get-Content -LiteralPath $curlLog -Raw
        Assert-True ($curlCall -match '--max-time\s+600') 'the download did not carry the default total timeout'
        Assert-True ($curlCall -match '--connect-timeout\s+30') 'the download did not carry the default connect timeout'

        Invoke-PlasticineDownload -Url 'https://example.invalid/custom.bin' -Destination (Join-Path $downloadDir 'custom.bin') `
            -FailureMessage 'custom download failed' -TimeoutSeconds 7 -ConnectTimeoutSeconds 5
        $curlCall = Get-Content -LiteralPath $curlLog -Raw
        Assert-True ($curlCall -match '--max-time\s+7') 'the download ignored its total timeout override'
        Assert-True ($curlCall -match '--connect-timeout\s+5') 'the download ignored its connect timeout override'

        $PlasticineDownloadMaxBytes = 4
        $env:PLASTICINE_TEST_CURL_SIZE = '8'
        $oversized = Join-Path $downloadDir 'oversized.bin'
        $oversizedError = Assert-Throws {
            Invoke-PlasticineDownload -Url 'https://example.invalid/oversized.bin' -Destination $oversized -FailureMessage 'oversized download failed'
        } 'an oversized download was accepted'
        Assert-True ($oversizedError -match 'size limit') 'the size limit failure was not reported'
        Assert-Equal 4 $PlasticineDownloadMaxBytes 'the download helper corrupted the size limit seam'
        Assert-True (-not (Test-Path -LiteralPath $oversized)) 'the oversized download was left on disk'

        $env:PLASTICINE_TEST_CURL_MODE = 'timeout'
        $timedOut = Join-Path $downloadDir 'timed-out.bin'
        $timeoutError = Assert-Throws {
            Invoke-PlasticineDownload -Url 'https://example.invalid/slow.bin' -Destination $timedOut -FailureMessage 'slow download failed'
        } 'a timed-out download was accepted'
        Assert-True ($timeoutError -match 'slow download failed') 'the timeout failure lost its diagnostic'
        Assert-True (-not (Test-Path -LiteralPath $timedOut)) 'the timed-out download was left on disk'
    } finally {
        $PlasticineCurlCommand = $savedCurl
        $PlasticineDownloadTimeoutSeconds = $savedTimeout
        $PlasticineDownloadConnectTimeoutSeconds = $savedConnectTimeout
        $PlasticineDownloadMaxBytes = $savedMaxBytes
        Remove-Item Env:\PLASTICINE_TEST_CURL_LOG -ErrorAction SilentlyContinue
        Remove-Item Env:\PLASTICINE_TEST_CURL_MODE -ErrorAction SilentlyContinue
        Remove-Item Env:\PLASTICINE_TEST_CURL_SIZE -ErrorAction SilentlyContinue
    }

    # --- ACL: an inherited DACL is restored by re-inheriting. ---
    $aclDir = New-TestDirectory 'acl'
    $inherited = Join-Path $aclDir 'inherited-key'
    Set-Content -LiteralPath $inherited -Value 'secret' -NoNewline
    $backup = Get-PlasticineAclBackup $inherited
    Assert-True (-not $backup.Protected) 'a fresh file should have an inherited DACL'
    Set-PlasticineOwnerOnlyAcl -Path $inherited
    $restricted = (Get-Acl -LiteralPath $inherited).Sddl
    Assert-True ($restricted -match 'D:PAI\(A;;FA;;;') "owner-only DACL was not applied: $restricted"
    Assert-True ($restricted -notmatch ';;;WD') 'owner-only DACL kept an Everyone rule'
    Restore-PlasticineAcl -Path $inherited -Backup $backup
    $restored = (Get-Acl -LiteralPath $inherited).Sddl
    # Re-inheriting marks the DACL auto-inherited (AI); the ACE list is what must match.
    Assert-Equal $backup.Sddl.Substring($backup.Sddl.IndexOf('(')) `
        $restored.Substring($restored.IndexOf('(')) 'inherited DACL was not restored'

    # --- ACL: an explicit DACL is restored rule by rule. ---
    $explicit = Join-Path $aclDir 'explicit-key'
    Set-Content -LiteralPath $explicit -Value 'secret' -NoNewline
    $custom = New-Object Security.AccessControl.FileSecurity
    $custom.SetAccessRuleProtection($true, $false)
    $custom.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($everyone, 'Read', 'Allow')))
    [IO.File]::SetAccessControl($explicit, $custom)
    $explicitBackup = Get-PlasticineAclBackup $explicit
    Assert-True $explicitBackup.Protected 'the custom DACL should be protected'
    Assert-Equal 1 (@($explicitBackup.Rules).Count) 'the custom DACL should hold one rule'
    Set-PlasticineOwnerOnlyAcl -Path $explicit
    Restore-PlasticineAcl -Path $explicit -Backup $explicitBackup
    $explicitNow = (Get-Acl -LiteralPath $explicit).Sddl
    Assert-Equal $explicitBackup.Sddl $explicitNow 'explicit DACL was not restored byte for byte'
    Set-PlasticineOwnerOnlyAcl -Path $explicit

    # --- ACL: an empty rule set must never be published. ---
    $empty = [pscustomobject]@{
        Path = $explicit; IsDirectory = $false; Protected = $true; Rules = @(); Sddl = ''
    }
    $before = (Get-Acl -LiteralPath $explicit).Sddl
    $null = Assert-Throws { Restore-PlasticineAcl -Path $explicit -Backup $empty } 'an empty rule set was accepted'
    Assert-Equal $before (Get-Acl -LiteralPath $explicit).Sddl 'the refused restore still changed the DACL'

    # --- ACL: directories restrict with inheritance, and read-only denies writes. ---
    $secretDir = Join-Path $aclDir 'dir700'
    New-Item -ItemType Directory -Path $secretDir | Out-Null
    $dirBackup = Get-PlasticineAclBackup $secretDir
    Set-PlasticineOwnerOnlyAcl -Path $secretDir
    $child = Join-Path $secretDir 'child'
    Set-Content -LiteralPath $child -Value 'c' -NoNewline
    $childAcl = (Get-Acl -LiteralPath $child).Sddl
    Assert-True ($childAcl -match ';ID;FA;;;') "a new child did not inherit the owner-only rule: $childAcl"
    Restore-PlasticineAcl -Path $secretDir -Backup $dirBackup

    $readOnly = Join-Path $aclDir 'readonly-key'
    Set-Content -LiteralPath $readOnly -Value 'secret' -NoNewline
    $readBackup = Get-PlasticineAclBackup $readOnly
    Set-PlasticineOwnerOnlyAcl -Path $readOnly -Right ReadAndExecute
    $null = Assert-Throws { Set-Content -LiteralPath $readOnly -Value 'changed' -NoNewline -ErrorAction Stop } `
        'a ReadAndExecute DACL allowed a write'
    Restore-PlasticineAcl -Path $readOnly -Backup $readBackup
    Set-Content -LiteralPath $readOnly -Value 'secret' -NoNewline

    # --- ACL: a mixed DACL keeps its explicit ACE through tighten and restore. ---
    $aclExtra = New-TestDirectory 'acl-extra'
    $mixedFile = Join-Path $aclExtra 'mixed.txt'
    Set-Content -LiteralPath $mixedFile -Value 'secret' -NoNewline
    $mixedAcl = Get-Acl -LiteralPath $mixedFile
    $mixedAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($everyone, 'Read', 'Allow')))
    [IO.File]::SetAccessControl($mixedFile, $mixedAcl)
    $mixedBackup = Get-PlasticineAclBackup $mixedFile
    Assert-True (-not $mixedBackup.Protected) 'the mixed DACL backup should stay unprotected'
    Assert-Equal 1 (@($mixedBackup.Rules).Count) 'the mixed DACL backup lost its explicit ACE'
    Set-PlasticineOwnerOnlyAcl -Path $mixedFile
    $mixedTightened = (Get-Acl -LiteralPath $mixedFile).Sddl
    Assert-True ($mixedTightened -notmatch ';;;WD') 'the mixed DACL explicit Everyone ACE survived tightening'
    Restore-PlasticineAcl -Path $mixedFile -Backup $mixedBackup
    $mixedRestored = Get-Acl -LiteralPath $mixedFile
    Assert-True (-not $mixedRestored.AreAccessRulesProtected) 'the mixed DACL was restored as protected'
    $mixedExplicitRules = @($mixedRestored.GetAccessRules($true, $false, [Security.Principal.SecurityIdentifier]))
    Assert-Equal 1 $mixedExplicitRules.Count 'the mixed DACL lost its explicit ACE during restore'
    Assert-Equal $everyone $mixedExplicitRules[0].IdentityReference 'the mixed DACL explicit ACE identity changed'
    Assert-True ($mixedRestored.Sddl -match 'D:AI') 'the mixed DACL inherited ACEs were not restored'

    # --- ACL: recursive tightening and recursive backup cover the whole tree. ---
    $treeRoot = Join-Path $aclExtra 'tree'
    New-Item -ItemType Directory -Path $treeRoot | Out-Null
    $treeChild = Join-Path $treeRoot 'child'
    New-Item -ItemType Directory -Path $treeChild | Out-Null
    $treeRootFile = Join-Path $treeRoot 'root.txt'
    $treeChildFile = Join-Path $treeChild 'child.txt'
    Set-Content -LiteralPath $treeRootFile -Value 'r' -NoNewline
    Set-Content -LiteralPath $treeChildFile -Value 'c' -NoNewline
    $permissive = Get-Acl -LiteralPath $treeChildFile
    $permissive.SetAccessRuleProtection($true, $false)
    $permissive.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($everyone, 'FullControl', 'Allow')))
    [IO.File]::SetAccessControl($treeChildFile, $permissive)
    $treeBackups = @(Get-PlasticineAclBackup -Path $treeRoot -Recurse)
    Assert-Equal 4 $treeBackups.Count 'the recursive ACL backup missed part of the tree'
    Set-PlasticineOwnerOnlyAclRecursive -Path $treeRoot
    foreach ($treePath in @($treeRoot, $treeChild, $treeRootFile, $treeChildFile)) {
        $treeSddl = (Get-Acl -LiteralPath $treePath).Sddl
        Assert-True ($treeSddl -match 'D:PAI\(') "recursive tightening missed $treePath"
        Assert-True ($treeSddl -notmatch ';;;WD') "recursive tightening kept Everyone on $treePath"
    }
    Restore-PlasticineAcl -Backup $treeBackups
    $childBackup = @($treeBackups | Where-Object { $_.Path -eq $treeChildFile })[0]
    Assert-Equal $childBackup.Sddl ((Get-Acl -LiteralPath $treeChildFile).Sddl) 'the recursive restore did not bring back the permissive file DACL'
    Assert-True (-not (Get-Acl -LiteralPath $treeRoot).AreAccessRulesProtected) 'the recursive restore kept the root DACL protected'

    # --- ACL: identities are resolved before any DACL is written. ---
    Assert-Equal $everyone (Resolve-PlasticineAclIdentity -Identity 'S-1-1-0') 'a string SID was not resolved'
    Assert-Equal $null (Resolve-PlasticineAclIdentity -Identity 'Plasticine-no-such-identity') 'an unresolvable identity was accepted'
    $bogusBackup = [pscustomobject]@{
        Path = $mixedFile; IsDirectory = $false; Protected = $true; Sddl = ''
        Rules = @([pscustomobject]@{
                IdentityReference = 'Plasticine-no-such-identity'; FileSystemRights = 'Read'
                InheritanceFlags = 'None'; PropagationFlags = 'None'; AccessControlType = 'Allow'
            })
    }
    $bogusBefore = (Get-Acl -LiteralPath $mixedFile).Sddl
    $bogusError = Assert-Throws { Restore-PlasticineAcl -Path $mixedFile -Backup $bogusBackup } 'an unresolvable identity was accepted by the restore'
    Assert-True ($bogusError -match 'identity cannot be resolved') 'the unresolvable identity failure was not reported'
    Assert-Equal $bogusBefore (Get-Acl -LiteralPath $mixedFile).Sddl 'the refused identity restore still changed the DACL'

    # --- ACL: the PowerShell 7 writer branch runs when pwsh is installed. ---
    $pwshCommand = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pwshCommand) {
        $ps7Target = Join-Path $aclExtra 'ps7.txt'
        Set-Content -LiteralPath $ps7Target -Value 'secret' -NoNewline
        $ps7Script = Join-Path $PlasticineTestRoot 'ps7-acl.ps1'
        New-Ps7AclChildScript -Path $ps7Script
        try {
            $ps7Output = & $pwshCommand.Source -NoProfile -ExecutionPolicy Bypass -File $ps7Script -AclPath $ps7Target -RepoDir $repoDir 2>&1
            $ps7Exit = $LASTEXITCODE
            Assert-Equal 0 $ps7Exit "the PowerShell 7 ACL branch failed: $(@($ps7Output) -join ' | ')"
            Assert-True ((@($ps7Output) -join "`n") -match 'pwsh acl branch passed') 'the PowerShell 7 child did not confirm the ACL round trip'
        } finally {
            Remove-Item -LiteralPath $ps7Script -Force -ErrorAction SilentlyContinue
        }
    } else {
        [Console]::Out.WriteLine('windows helpers tests: skipped the PowerShell 7 ACL branch (pwsh is not installed)')
    }

    # --- Publication: single files keep the Unix no-clobber and replace semantics. ---
    $pubDir = New-TestDirectory 'publish'
    $candidate = Join-Path $pubDir 'candidate.exe'
    Set-Content -LiteralPath $candidate -Value 'v1' -NoNewline
    $live = Join-Path $pubDir 'live.exe'
    Publish-PlasticineNewFile -Candidate $candidate -Target $live
    Assert-Equal 'v1' (Get-Content -LiteralPath $live -Raw) 'the new file was not published'
    Assert-True (-not (Test-Path -LiteralPath $candidate)) 'publication left the staged file behind'

    $second = Join-Path $pubDir 'second.exe'
    Set-Content -LiteralPath $second -Value 'v2' -NoNewline
    $null = Assert-Throws { Publish-PlasticineNewFile -Candidate $second -Target $live } 'no-clobber publication overwrote a live file'
    Assert-Equal 'v1' (Get-Content -LiteralPath $live -Raw) 'the refused publication changed the live file'
    Assert-True (Test-Path -LiteralPath $second) 'the refused publication lost its candidate'

    $liveHash = Get-PlasticineFileHash $live
    $third = Join-Path $pubDir 'third.exe'
    Set-Content -LiteralPath $third -Value 'v3' -NoNewline
    Update-PlasticineFile -Candidate $third -Target $live -ExpectedHash $liveHash
    Assert-Equal 'v3' (Get-Content -LiteralPath $live -Raw) 'the atomic replacement did not land'
    Assert-True (-not (Test-Path -LiteralPath $third)) 'the replacement left the staged file behind'

    $fourth = Join-Path $pubDir 'fourth.exe'
    Set-Content -LiteralPath $fourth -Value 'v4' -NoNewline
    $null = Assert-Throws { Update-PlasticineFile -Candidate $fourth -Target $live -ExpectedHash $liveHash } `
        'a stale observation hash was accepted'
    Assert-Equal 'v3' (Get-Content -LiteralPath $live -Raw) 'the aborted update changed the live file'
    Remove-Item -LiteralPath $fourth -Force

    # --- Publication: directories use Move plus a rename swap with rollback. ---
    $liveDir = Join-Path $pubDir 'tool'
    New-Item -ItemType Directory -Path $liveDir | Out-Null
    Set-Content -LiteralPath (Join-Path $liveDir 'tool.exe') -Value 'v1' -NoNewline
    $candidateDir = Join-Path $pubDir 'tool-candidate'
    New-Item -ItemType Directory -Path $candidateDir | Out-Null
    Set-Content -LiteralPath (Join-Path $candidateDir 'tool.exe') -Value 'v2' -NoNewline
    $null = Assert-Throws { Publish-PlasticineNewDirectory -Candidate $candidateDir -Target $liveDir } `
        'directory publication overwrote a live directory'
    Assert-Equal 'v1' (Get-Content -LiteralPath (Join-Path $liveDir 'tool.exe') -Raw) 'the refused move changed the live directory'
    Assert-True (Test-Path -LiteralPath $candidateDir) 'the refused move lost its candidate'

    Update-PlasticineDirectory -Candidate $candidateDir -Target $liveDir
    Assert-Equal 'v2' (Get-Content -LiteralPath (Join-Path $liveDir 'tool.exe') -Raw) 'the directory swap did not land'
    Assert-Equal 0 (@(Get-ChildItem -LiteralPath $pubDir -Force -Filter '.tool.plasticine-old.*').Count) `
        'the directory swap left a retained copy behind'

    $missingCandidate = Join-Path $pubDir 'absent-candidate'
    $null = Assert-Throws { Update-PlasticineDirectory -Candidate $missingCandidate -Target $liveDir } `
        'a failed directory swap reported success'
    Assert-Equal 'v2' (Get-Content -LiteralPath (Join-Path $liveDir 'tool.exe') -Raw) 'the failed swap did not roll back'
    Assert-Equal 0 (@(Get-ChildItem -LiteralPath $pubDir -Force -Filter '.tool.plasticine-old.*').Count) `
        'the rollback left a retained copy behind'

    # --- Publication: a cross-volume hard link reports the volume root cause. ---
    $originalHardLink = ${function:New-PlasticineHardLink}
    ${function:New-PlasticineHardLink} = { param($Path, $Value) throw 'simulated hard link failure' }
    try {
        $crossError = Assert-Throws {
            Publish-PlasticineNewFile -Candidate 'C:\plasticine-candidate.exe' -Target 'D:\plasticine-target.exe'
        } 'a cross-volume hard link failure was not reported'
        Assert-True ($crossError -match 'different volumes') 'the cross-volume root cause was not reported'
        Assert-True ($crossError -match 'hard links cannot cross volumes') 'the hard link volume constraint was not explained'
        $sameVolumeError = Assert-Throws {
            Publish-PlasticineNewFile -Candidate 'C:\plasticine-candidate.exe' -Target 'C:\plasticine-target.exe'
        } 'a same-volume hard link failure was not reported'
        Assert-True ($sameVolumeError -notmatch 'different volumes') 'a same-volume failure was blamed on volumes'
    } finally {
        ${function:New-PlasticineHardLink} = $originalHardLink
    }

    # --- Publication: a failed rollback keeps and names the previous directory. ---
    $rollbackLive = Join-Path $pubDir 'rollback-tool'
    New-Item -ItemType Directory -Path $rollbackLive | Out-Null
    Set-Content -LiteralPath (Join-Path $rollbackLive 'tool.exe') -Value 'v1' -NoNewline
    $rollbackCandidate = Join-Path $pubDir 'rollback-candidate'
    New-Item -ItemType Directory -Path $rollbackCandidate | Out-Null
    Set-Content -LiteralPath (Join-Path $rollbackCandidate 'tool.exe') -Value 'v2' -NoNewline
    $originalMove = ${function:Move-PlasticineDirectory}
    $moveState = [pscustomobject]@{ Calls = 0 }
    ${function:Move-PlasticineDirectory} = {
        param($Source, $Destination)
        $moveState.Calls = $moveState.Calls + 1
        if ($moveState.Calls -gt 1) { throw 'simulated directory move failure' }
        [IO.Directory]::Move($Source, $Destination)
    }
    try {
        $rollbackError = Assert-Throws { Update-PlasticineDirectory -Candidate $rollbackCandidate -Target $rollbackLive } `
            'a failed directory swap with a failed rollback reported success'
        Assert-True ($rollbackError -match 'rollback failed') 'the rollback failure was not reported'
        Assert-True ($rollbackError -match [regex]::Escape($pubDir)) 'the retained rollback copy path was not reported'
        $retainedCopies = @(Get-ChildItem -LiteralPath $pubDir -Force -Filter '.rollback-tool.plasticine-old.*')
        Assert-Equal 1 $retainedCopies.Count 'the failed rollback did not retain the previous installation'
        Assert-Equal 'v1' (Get-Content -LiteralPath (Join-Path $retainedCopies[0].FullName 'tool.exe') -Raw) 'the retained copy lost the previous installation'
    } finally {
        ${function:Move-PlasticineDirectory} = $originalMove
    }

    # --- Archive: members are validated before anything is extracted. ---
    $archiveDir = New-TestDirectory 'archive'
    $payload = Join-Path $archiveDir 'chezmoi.exe'
    Set-Content -LiteralPath $payload -Value 'payload' -NoNewline
    $goodZip = Join-Path $archiveDir 'good.zip'
    New-TestZip -Path $goodZip -File @($payload)
    $goodDest = Join-Path $archiveDir 'good'
    Expand-PlasticineArchive -Archive $goodZip -Destination $goodDest -Member @('chezmoi.exe')
    Assert-True (Test-Path -LiteralPath (Join-Path $goodDest 'chezmoi.exe')) 'the reviewed archive did not expand'

    $extraZip = Join-Path $archiveDir 'extra.zip'
    New-TestZip -Path $extraZip -File @($payload) -ExtraEntry @('extra.txt')
    $null = Assert-Throws { Expand-PlasticineArchive -Archive $extraZip -Destination (Join-Path $archiveDir 'extra') -Member @('chezmoi.exe') } `
        'an unexpected archive member was accepted'

    $escapeZip = Join-Path $archiveDir 'escape.zip'
    New-TestZip -Path $escapeZip -File @($payload) -ExtraEntry @('../evil.txt')
    $null = Assert-Throws { Expand-PlasticineArchive -Archive $escapeZip -Destination (Join-Path $archiveDir 'escape') -Member @('chezmoi.exe') } `
        'a path-traversal archive member was accepted'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $archiveDir 'evil.txt'))) 'the traversal member was written'

    # --- Version parsing keeps the exactly-one-semver-token contract. ---
    $versionDir = New-TestDirectory 'version'
    $healthy = Join-Path $versionDir 'healthy.exe'
    New-TestStub -Path $healthy -Version '2.72.1'
    Assert-Equal '2.72.1' (Get-PlasticineExecutableVersion $healthy) 'a healthy version was not parsed'
    $prerelease = Join-Path $versionDir 'prerelease.exe'
    New-TestStub -Path $prerelease -Version '2.73.0-rc1'
    Assert-Equal $null (Get-PlasticineExecutableVersion $prerelease) 'a prerelease was accepted as stable'
    $unhealthy = Join-Path $versionDir 'unhealthy.exe'
    New-TestStub -Path $unhealthy -Version '2.72.1' -Unhealthy
    Assert-Equal $null (Get-PlasticineExecutableVersion $unhealthy) 'an unhealthy executable was accepted'
    $ambiguous = Join-Path $versionDir 'ambiguous.exe'
    New-TestStub -Path $ambiguous -Version '2.72.1 build 2.72.1'
    Assert-Equal $null (Get-PlasticineExecutableVersion $ambiguous) 'an ambiguous version was accepted'
    Assert-Equal $null (Get-PlasticineExecutableVersion (Join-Path $versionDir 'absent.exe')) 'a missing executable reported a version'

    Assert-Equal (-1) (Compare-PlasticineVersion '2.72.0' '2.72.1') 'version comparison lost the lower case'
    Assert-Equal 0 (Compare-PlasticineVersion '2.72.1' '2.72.1') 'version comparison lost the equal case'
    Assert-Equal 1 (Compare-PlasticineVersion '2.73.0' '2.72.1') 'version comparison lost the higher case'

    # --- User PATH: dedupe, order and value kind, against a disposable registry key. ---
    $registryTestKey = 'Software\PlasticineDotfilesTest.' + [IO.Path]::GetRandomFileName()
    $PlasticineUserEnvironmentSubKey = $registryTestKey + '\Environment'
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($PlasticineUserEnvironmentSubKey)
    $rawPath = 'C:\Existing;%USERPROFILE%\tools;C:\Trailing\;"C:\Quoted Dir"'
    $key.SetValue('Path', $rawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
    $key.Dispose()

    Assert-Equal $rawPath (Get-PlasticineUserPath) 'the raw user PATH was expanded on read'
    Assert-Equal $null (Resolve-PlasticineUserPathAddition 'C:\existing') 'a case-insensitive duplicate was not detected'
    Assert-Equal $null (Resolve-PlasticineUserPathAddition 'C:\Trailing') 'a trailing-backslash duplicate was not detected'
    Assert-Equal $null (Resolve-PlasticineUserPathAddition 'C:\Quoted Dir') 'a quoted existing entry was not detected'
    Assert-Equal $null (Resolve-PlasticineUserPathAddition ([Environment]::ExpandEnvironmentVariables('%USERPROFILE%\tools'))) `
        'an expanded %VAR% duplicate was not detected'
    Assert-Equal $null (Resolve-PlasticineUserPathAddition '%USERPROFILE%\tools') 'an unexpanded %VAR% duplicate was not detected'
    Assert-Equal $null (Resolve-PlasticineUserPathAddition ('"' + [Environment]::ExpandEnvironmentVariables('%USERPROFILE%\tools') + '"')) `
        'a quoted expanded %VAR% duplicate was not detected'
    Assert-Equal ($rawPath + ';%TEMP%\PlasticineVar') (Resolve-PlasticineUserPathAddition '%TEMP%\PlasticineVar') `
        'an environment-variable addition was not preserved verbatim'
    Assert-Equal ($rawPath + ';C:\New') (Resolve-PlasticineUserPathAddition 'C:\New') 'the appended PATH lost existing entries'

    Assert-True (Add-PlasticineUserPathEntry 'C:\New') 'the first PATH addition did not write'
    Assert-True (-not (Add-PlasticineUserPathEntry 'C:\New')) 'the second PATH addition wrote again'
    Assert-Equal ($rawPath + ';C:\New') (Get-PlasticineUserPath) 'the written PATH lost existing entries'
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($PlasticineUserEnvironmentSubKey)
    Assert-Equal ([Microsoft.Win32.RegistryValueKind]::ExpandString) $key.GetValueKind('Path') 'the PATH value kind was downgraded'
    $key.Dispose()

    # --- User PATH: the original value is backed up before the first write. ---
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($PlasticineUserEnvironmentSubKey, $true)
    $key.SetValue('Path', $rawPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
    $key.Dispose()
    $backupDir = New-TestDirectory 'path-backup'
    $savedBroadcast = ${function:Send-PlasticineEnvironmentSettingChange}
    $broadcastState = [pscustomobject]@{ Calls = 0 }
    ${function:Send-PlasticineEnvironmentSettingChange} = {
        param([int]$TimeoutMilliseconds = 5000)
        $broadcastState.Calls = $broadcastState.Calls + 1
        return $true
    }
    try {
        Assert-True (Add-PlasticineUserPathEntry -Directory 'C:\Backed-New' -BackupDirectory $backupDir) 'the backed-up PATH addition did not write'
        Assert-Equal 1 $broadcastState.Calls 'the PATH addition did not broadcast the environment change exactly once'
        $backupFile = Join-Path $backupDir 'user-path.txt'
        Assert-True (Test-Path -LiteralPath $backupFile -PathType Leaf) 'the PATH addition wrote no original-value backup'
        Assert-Equal $rawPath (Get-Content -LiteralPath $backupFile -Raw) 'the PATH backup lost the original value'
        Assert-Equal 'ExpandString' (Get-Content -LiteralPath (Join-Path $backupDir 'user-path.kind') -Raw) 'the PATH backup lost the registry value kind'
        Assert-True (-not (Add-PlasticineUserPathEntry -Directory 'C:\Backed-New' -BackupDirectory $backupDir)) 'the duplicate PATH addition wrote again'
        Assert-Equal 1 $broadcastState.Calls 'a duplicate PATH addition broadcast again'
        Assert-True (Add-PlasticineUserPathEntry -Directory 'C:\Silent-New' -NoBroadcast) 'the quiet PATH addition did not write'
        Assert-Equal 1 $broadcastState.Calls 'the quiet PATH addition broadcast anyway'
        $passThru = Add-PlasticineUserPathEntry -Directory 'C:\Thru-New' -NoBroadcast -PassThru
        Assert-True $passThru.Changed 'the PassThru result did not report a change'
        Assert-Equal ($rawPath + ';C:\Backed-New;C:\Silent-New') $passThru.PreviousPath 'the PassThru result lost the previous value'
        Assert-Equal ($rawPath + ';C:\Backed-New;C:\Silent-New;C:\Thru-New') $passThru.Path 'the PassThru result lost the written value'
    } finally {
        ${function:Send-PlasticineEnvironmentSettingChange} = $savedBroadcast
    }

    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($PlasticineUserEnvironmentSubKey, $true)
    $key.SetValue('Path', '', [Microsoft.Win32.RegistryValueKind]::ExpandString)
    $key.Dispose()
    Assert-Equal 'C:\First' (Resolve-PlasticineUserPathAddition 'C:\First') 'an empty PATH gained a leading separator'

    # --- User PATH: a value over the Windows limit is reported as a hint. ---
    $padEntry = 'C:\PlasticineLongPathPad-' + ('x' * 180)
    $longRaw = ((1..10 | ForEach-Object { $padEntry + $_ }) -join ';')
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($PlasticineUserEnvironmentSubKey, $true)
    $key.SetValue('Path', $longRaw, [Microsoft.Win32.RegistryValueKind]::ExpandString)
    $key.Dispose()
    $longRun = Invoke-TestCapture { Add-PlasticineUserPathEntry -Directory 'C:\Long-New' -NoBroadcast }
    Assert-True (-not $longRun.Threw) "the long PATH addition failed: $($longRun.Message)"
    Assert-True ($longRun.Output -match '2047') 'a PATH over the Windows length limit was not reported'

    Complete-Test 'windows helpers tests passed'
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
} finally {
    if ($registryTestKey) {
        try { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($registryTestKey) } catch { }
    }
    Remove-Item -LiteralPath $PlasticineTestRoot -Recurse -Force -ErrorAction SilentlyContinue
}