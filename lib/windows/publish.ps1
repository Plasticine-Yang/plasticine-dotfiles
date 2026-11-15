# Publication primitives. Single files use the same no-clobber and atomic-replace
# semantics as the Unix hardlink plus mv -f; directories use a rename swap.

if (-not (Get-Command Write-PlasticineLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'common.ps1')
}
if (Get-Command Publish-PlasticineNewFile -ErrorAction SilentlyContinue) { return }

# Isolated so the failure branch can be exercised without a second volume.
function New-PlasticineHardLink {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Value
    )
    New-Item -ItemType HardLink -Path $Path -Value $Value -ErrorAction Stop | Out-Null
}

# Hard links require both names on the same NTFS volume. Without this the raw
# "could not create hard link" error gives the user no actionable root cause.
function Get-PlasticineHardLinkFailureReason {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Candidate,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Target
    )
    $candidateRoot = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Candidate))
    $targetRoot = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Target))
    if (-not $candidateRoot -or -not $targetRoot -or $candidateRoot -eq $targetRoot) { return '' }
    return "candidate on $candidateRoot and target on $targetRoot are on different volumes; hard links cannot cross volumes"
}

# Isolated so the rollback branch can be exercised deterministically.
function Move-PlasticineDirectory {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Source,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Destination
    )
    [IO.Directory]::Move($Source, $Destination)
}

function Publish-PlasticineNewFile {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Candidate,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Target
    )
    $null = Assert-PlasticineAbsolutePath -Path $Candidate -Name 'publication candidate'
    $null = Assert-PlasticineAbsolutePath -Path $Target -Name 'publication target'
    if (Get-PlasticineItem $Target) {
        Stop-Plasticine "installation target appeared during preparation; left untouched: $Target"
    }
    try {
        New-PlasticineHardLink -Path $Target -Value $Candidate
    } catch {
        $reason = Get-PlasticineHardLinkFailureReason -Candidate $Candidate -Target $Target
        if ($reason) {
            Stop-Plasticine "atomic no-clobber publication failed: $Target ($reason)"
        }
        Stop-Plasticine "atomic no-clobber publication failed: $Target"
    }
    Remove-Item -LiteralPath $Candidate -Force -ErrorAction SilentlyContinue
}

function Update-PlasticineFile {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Candidate,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Target,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ExpectedHash
    )
    $null = Assert-PlasticineAbsolutePath -Path $Candidate -Name 'replacement candidate'
    $null = Assert-PlasticineAbsolutePath -Path $Target -Name 'replacement target'
    if ((Get-PlasticineFileHash $Target) -ne $ExpectedHash) {
        Stop-Plasticine "installation target changed during preparation; update aborted: $Target"
    }
    try {
        [IO.File]::Replace($Candidate, $Target, [NullString]::Value)
    } catch {
        Stop-Plasticine "atomic replacement failed; inspect the retained destination: $Target"
    }
}

function Publish-PlasticineNewDirectory {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Candidate,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Target
    )
    $null = Assert-PlasticineAbsolutePath -Path $Candidate -Name 'publication candidate'
    $null = Assert-PlasticineAbsolutePath -Path $Target -Name 'publication target'
    try {
        Move-PlasticineDirectory -Source $Candidate -Destination $Target
    } catch {
        Stop-Plasticine "could not publish the candidate directory: $Target"
    }
}

function Update-PlasticineDirectory {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Candidate,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Target
    )
    $null = Assert-PlasticineAbsolutePath -Path $Candidate -Name 'replacement candidate'
    $null = Assert-PlasticineAbsolutePath -Path $Target -Name 'replacement target'
    $parent = Split-Path -Parent $Target
    $leaf = Split-Path -Leaf $Target
    $retained = Join-Path $parent ('.' + $leaf + '.plasticine-old.' + [IO.Path]::GetRandomFileName())
    try {
        Move-PlasticineDirectory -Source $Target -Destination $retained
    } catch {
        Stop-Plasticine "could not retain the existing directory for replacement: $Target"
    }
    try {
        Move-PlasticineDirectory -Source $Candidate -Destination $Target
    } catch {
        # The previous installation only lives at $retained until the rollback
        # move succeeds; if that move fails the retained copy is the recovery
        # path and must survive, so the message names it explicitly.
        try {
            Move-PlasticineDirectory -Source $retained -Destination $Target
        } catch {
            Stop-Plasticine "directory publication failed and rollback failed; the previous installation is retained at $retained"
        }
        Stop-Plasticine "directory publication failed; the previous installation was restored: $Target"
    }
    Remove-Item -LiteralPath $retained -Recurse -Force -ErrorAction SilentlyContinue
}
