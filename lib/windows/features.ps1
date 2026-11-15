# Feature provider registry for the Windows routes.
# Providers follow one convention: Get-Plasticine<Feature>Plan observes,
# Write-Plasticine<Feature>Preview reports, Invoke-Plasticine<Feature>Prepare mutates.

$PlasticineFeatureOrder = @(
    'git-config',
    'github-ssh',
    'lazygit',
    'fnm',
    'rust',
    'uv',
    'neovim',
    'herdr',
    'npmrc',
    'powershell'
)

# Features that must provide a preview before the installer shows the diff.
$PlasticineFeaturePreviewRequired = @(
    'lazygit',
    'fnm',
    'rust',
    'uv',
    'neovim',
    'herdr',
    'npmrc',
    'powershell'
)

function Get-PlasticineFeatureKind {
    param([Parameter(Mandatory = $true)][string]$Feature)
    $parts = $Feature -split '[-_]'
    $kind = ''
    foreach ($part in $parts) {
        if (-not $part) { continue }
        $kind += $part.Substring(0, 1).ToUpperInvariant() + $part.Substring(1)
    }
    return $kind
}

function Get-PlasticineFeaturePlanFunction {
    param([Parameter(Mandatory = $true)][string]$Feature)
    return 'Get-Plasticine' + (Get-PlasticineFeatureKind $Feature) + 'Plan'
}

function Get-PlasticineFeaturePreviewFunction {
    param([Parameter(Mandatory = $true)][string]$Feature)
    return 'Write-Plasticine' + (Get-PlasticineFeatureKind $Feature) + 'Preview'
}

function Get-PlasticineFeaturePrepareFunction {
    param([Parameter(Mandatory = $true)][string]$Feature)
    return 'Invoke-Plasticine' + (Get-PlasticineFeatureKind $Feature) + 'Prepare'
}

function Test-PlasticineFunction {
    param([Parameter(Mandatory = $true)][string]$Name)
    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Invoke-PlasticineFeaturePrepare {
    param(
        [Parameter(Mandatory = $true)][string]$Feature,
        [Parameter(Mandatory = $true)][string]$HomeDirectory
    )
    $prepareFunction = Get-PlasticineFeaturePrepareFunction $Feature
    if (-not (Test-PlasticineFunction $prepareFunction)) {
        return
    }
    $planFunction = Get-PlasticineFeaturePlanFunction $Feature
    if (-not (Test-PlasticineFunction $planFunction)) {
        Stop-Plasticine "selected feature has no Windows plan in this release: $Feature"
    }
    $plan = & $planFunction -HomeDirectory $HomeDirectory
    & $prepareFunction -Plan $plan
}
