#Requires -Version 5.1
# Windows entry point for plasticine-dotfiles. Mirrors install.sh: same Feature
# names, same environment contract, same preview, confirmation and apply flow.
#
# Run with: powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
# A source checkout dot-sources lib/windows; a Release build inlines the same
# files into the marker block below, so the asset stays self-contained.

$PlasticineReleaseVersion = ''
$PlasticineRepoRevision = ''
$PlasticineSourceSha256 = ''
$PlasticinePluginsSha256 = ''
$PlasticineRepoUrlDefault = 'https://github.com/Plasticine-Yang/plasticine-dotfiles.git'
$PlasticineReleaseBaseUrlDefault = 'https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/download'

$PlasticineLibraryDirectory = Join-Path $PSScriptRoot 'lib\windows'
if (Test-Path -LiteralPath $PlasticineLibraryDirectory -PathType Container) {
    $PlasticineLibraryModules = @(
        'common.ps1',
        'publish.ps1',
        'acl.ps1',
        'user-path.ps1',
        'chezmoi-bootstrap.ps1',
        'release-payload.ps1',
        'features.ps1'
    )
    foreach ($module in $PlasticineLibraryModules) {
        . (Join-Path $PlasticineLibraryDirectory $module)
    }
    Get-ChildItem -LiteralPath $PlasticineLibraryDirectory -Filter 'feature-*.ps1' |
        Sort-Object Name | ForEach-Object { . $_.FullName }
}
# >>> plasticine-inline-library >>>
# <<< plasticine-inline-library <<<

function Write-PlasticineEntryUsage {
    param([switch]$ToStandardError)
    $text = @'
Usage: install.ps1 [options]

Interactive mode:
  install.ps1

Non-interactive mode:
  install.ps1 -Yes [-GitConfig] [-GithubSsh -GithubSshKey <path>] [-Fnm] [-Rust] [-Uv] [-Herdr] [-Lazygit] [-Neovim] [-Powershell] [-Npmrc]

Options:
  -Yes, -y, --yes                 Skip selection/confirmation; native credentials may still be required
      -GitConfig, --git-config    Configure shared Git preferences and local override inclusion
      -Npmrc, --npmrc             Allow all npm dependency install scripts in ~/.npmrc
      -GithubSsh, --github-ssh    Configure GitHub SSH
      -GithubSshKey <path>        Private key to copy to ~/.ssh/id_github
      -GithubSshTest              Test GitHub SSH after applying
      -ReplaceGithubSshKey        Allow replacement of a different existing key
      -Herdr, --herdr             Install or update Herdr from its stable channel
      -Lazygit, --lazygit         Prepare Lazygit if missing
      -Fnm, --fnm                 Install or update fnm through the permitted route
      -Rust, --rust               Install/update rustup and stable with Cargo, rustfmt and Clippy
      -Uv, --uv                   Install/update uv and uvx through the official installer
      -Neovim, --neovim           Install/update Neovim and configure it
      -Powershell, --powershell   Maintain the PowerShell profile, PATH and fnm activation
  -h, --help                      Show this help

Windows does not provide the shell, login-shell, plasticine CLI or self-update features.
'@
    if ($ToStandardError) { [Console]::Error.WriteLine($text) } else { [Console]::Out.WriteLine($text) }
}

function Stop-PlasticineUsage {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-PlasticineError $Message
    Write-PlasticineEntryUsage -ToStandardError
    exit 2
}

function Get-PlasticineSelectedToolsFromConfig {
    param([Parameter(Mandatory = $true)][string]$ConfigFile)
    $text = [IO.File]::ReadAllText($ConfigFile)
    $match = [regex]::Match($text, '(?m)^\s*tools\s*=\s*\[(?<items>[^\]]*)\]')
    if (-not $match.Success) { return @() }
    $items = @()
    foreach ($item in [regex]::Matches($match.Groups['items'].Value, '"([^"]*)"')) {
        $items += $item.Groups[1].Value
    }
    return $items
}

function Report-PlasticineApplyConflicts {
    param(
        [Parameter(Mandatory = $true)][string]$Chezmoi,
        [Parameter(Mandatory = $true)][string[]]$CommonArgument
    )
    Write-PlasticineError 'apply did not complete; managed paths that still differ are listed below.'
    $status = & $Chezmoi @CommonArgument status 2>$null
    foreach ($line in @($status)) {
        $text = [string]$line
        if (-not $text -or $text.StartsWith('R ')) { continue }
        Write-PlasticineError ('  ' + $text)
    }
    Write-PlasticineError 'paths modified outside chezmoi make the conflict-protected apply refuse; restore them, or overwrite them with a forced apply, then retry.'
    Write-PlasticineError ('inspect with: chezmoi ' + ($CommonArgument -join ' ') + ' status')
}

function Invoke-PlasticineEntry {
    $homeDirectory = $env:USERPROFILE
    if (-not $homeDirectory) { Stop-Plasticine 'HOME must be absolute.' }
    if (-not [IO.Path]::IsPathRooted($homeDirectory)) { Stop-Plasticine 'HOME must be absolute.' }

    $toolOptionsSelected = $false
    foreach ($selected in $script:PlasticineFeatures.Values) {
        if ($selected) { $toolOptionsSelected = $true }
    }
    $sshOptionsSelected = $script:PlasticineGitHubSshKey -or $script:PlasticineGitHubSshTest -or
        $script:PlasticineReplaceGitHubSshKey

    if (-not $script:PlasticineYes) {
        if ($toolOptionsSelected -or $sshOptionsSelected) {
            Stop-PlasticineUsage 'Tool options require -Yes; run without options for interactive selection.'
        }
        if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
            Stop-Plasticine 'Interactive mode requires a console; use -Yes for automation.'
        }
    } else {
        if ($sshOptionsSelected -and -not $script:PlasticineFeatures['github-ssh']) {
            Stop-PlasticineUsage 'GitHub SSH options require -GithubSsh.'
        }
        if ($script:PlasticineFeatures['github-ssh'] -and -not $script:PlasticineGitHubSshKey) {
            Stop-PlasticineUsage '-GithubSsh requires -GithubSshKey in non-interactive mode.'
        }
    }

    Assert-PlasticineWindowsPlatform
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Stop-Plasticine 'run as the target user, not an elevated administrator.'
    }

    $gitCommand = Get-PlasticineCommandPath 'git'
    if (-not $gitCommand) { Stop-Plasticine 'Required command not found: git' }
    $openSshDirectory = Join-Path $env:SystemRoot 'System32\OpenSSH'
    foreach ($name in @('ssh', 'ssh-keygen')) {
        $path = Join-Path $openSshDirectory ($name + '.exe')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Stop-Plasticine "Required command not found: $name (enable the OpenSSH Client optional feature)"
        }
    }
    if (-not (Test-Path -LiteralPath $PlasticineCurlCommand -PathType Leaf)) {
        Stop-Plasticine "missing system curl: $PlasticineCurlCommand"
    }

    if ($script:PlasticineYes) {
        $env:PLASTICINE_NONINTERACTIVE = '1'
        $requested = @()
        foreach ($feature in $PlasticineFeatureOrder) {
            if ($script:PlasticineFeatures[$feature]) { $requested += $feature }
        }
        $env:PLASTICINE_TOOLS = ($requested -join ' ')
        $env:PLASTICINE_GITHUB_SSH_KEY = $script:PlasticineGitHubSshKey
        $env:PLASTICINE_GITHUB_SSH_TEST = $(if ($script:PlasticineGitHubSshTest) { '1' } else { '0' })
        $env:PLASTICINE_REPLACE_GITHUB_SSH_KEY = $(if ($script:PlasticineReplaceGitHubSshKey) { '1' } else { '0' })
    } else {
        foreach ($name in @('PLASTICINE_NONINTERACTIVE', 'PLASTICINE_TOOLS', 'PLASTICINE_GITHUB_SSH_KEY',
                'PLASTICINE_GITHUB_SSH_TEST', 'PLASTICINE_REPLACE_GITHUB_SSH_KEY')) {
            Remove-Item ('Env:' + $name) -ErrorAction SilentlyContinue
        }
    }

    $sourceDir = $env:PLASTICINE_CHEZMOI_SOURCE_DIR
    if (-not $sourceDir) { $sourceDir = Join-Path $homeDirectory '.local\share\chezmoi' }
    $configFile = $env:PLASTICINE_CHEZMOI_CONFIG_FILE
    if (-not $configFile) { $configFile = Join-Path $homeDirectory '.config\chezmoi\chezmoi.toml' }
    $stateFile = $env:PLASTICINE_CHEZMOI_STATE_FILE
    if (-not $stateFile) { $stateFile = Join-Path $homeDirectory '.config\chezmoi\chezmoistate.boltdb' }
    $destinationDir = $env:PLASTICINE_CHEZMOI_DEST_DIR
    if (-not $destinationDir) { $destinationDir = $homeDirectory }
    foreach ($path in @($sourceDir, $configFile, $stateFile, $destinationDir)) {
        if (-not [IO.Path]::IsPathRooted($path)) { Stop-Plasticine 'chezmoi paths must be absolute.' }
    }
    $repoUrl = $env:PLASTICINE_DOTFILES_REPO_URL
    if (-not $repoUrl) { $repoUrl = $PlasticineRepoUrlDefault }
    $releaseBaseUrl = $env:PLASTICINE_RELEASE_BASE_URL
    if (-not $releaseBaseUrl) { $releaseBaseUrl = $PlasticineReleaseBaseUrlDefault + '/' + $PlasticineReleaseVersion }

    $chezmoi = Invoke-PlasticineChezmoiBootstrap -HomeDirectory $homeDirectory -Explicit $env:PLASTICINE_CHEZMOI_BIN

    $devRepoUrl = $env:PLASTICINE_DOTFILES_REPO_URL
    if ($PlasticineReleaseVersion -and -not $devRepoUrl) {
        if (-not $PlasticineRepoRevision -or -not $PlasticineSourceSha256 -or -not $PlasticinePluginsSha256) {
            Stop-Plasticine 'Release payload metadata is incomplete.'
        }
        Write-PlasticineLog "Restoring released chezmoi source: $PlasticineRepoRevision"
        Invoke-PlasticineReleaseSourceAcquisition -HomeDirectory $homeDirectory -Base $releaseBaseUrl `
            -Version $PlasticineReleaseVersion -SourceDigest $PlasticineSourceSha256 `
            -Revision $PlasticineRepoRevision -Origin $repoUrl -SourceDir $sourceDir | Out-Null
    } elseif (Get-PlasticineItem $sourceDir) {
        $sourceItem = Get-PlasticineItem $sourceDir
        if ($sourceItem.PSIsContainer -eq $false -or (Test-PlasticineReparsePoint $sourceItem) -or
            -not (Get-PlasticineItem (Join-Path $sourceDir '.git'))) {
            Stop-Plasticine "existing chezmoi source is not a Git checkout: $sourceDir"
        }
        $origin = Invoke-PlasticineGitCommand -Directory $sourceDir -Argument @('remote', 'get-url', 'origin')
        $existingOrigin = ($origin.Output -join '').Trim()
        if ($origin.ExitCode -ne 0 -or $existingOrigin -ne $repoUrl) {
            Stop-Plasticine "existing chezmoi source belongs to another repository: $existingOrigin"
        }
        $status = Invoke-PlasticineGitCommand -Directory $sourceDir -Argument @('status', '--porcelain')
        if ($status.ExitCode -ne 0 -or ($status.Output -join '').Trim() -ne '') {
            Stop-Plasticine "existing chezmoi source has local changes: $sourceDir"
        }
        if ($PlasticineRepoRevision) {
            Write-PlasticineLog "Selecting released chezmoi source: $PlasticineRepoRevision"
            $present = Invoke-PlasticineGitCommand -Directory $sourceDir -Argument @('cat-file', '-e', $PlasticineRepoRevision + '^{commit}')
            if ($present.ExitCode -ne 0) {
                Invoke-PlasticineGitCommand -Directory $sourceDir -Argument @('fetch', '--no-tags', 'origin', $PlasticineRepoRevision) | Out-Null
            }
            $resolved = Invoke-PlasticineGitCommand -Directory $sourceDir -Argument @('rev-parse', $PlasticineRepoRevision + '^{commit}')
            if (($resolved.Output -join '').Trim() -ne $PlasticineRepoRevision) {
                Stop-Plasticine "Release revision did not resolve to the expected commit: $PlasticineRepoRevision"
            }
            Invoke-PlasticineGitCommand -Directory $sourceDir -Argument @('checkout', '--detach', $PlasticineRepoRevision) | Out-Null
        } else {
            Write-PlasticineLog 'Updating chezmoi source...'
            $pull = Invoke-PlasticineGitCommand -Directory $sourceDir -Argument @('pull', '--ff-only')
            if ($pull.ExitCode -ne 0) { Stop-Plasticine "could not update the chezmoi source: $sourceDir" }
        }
    } else {
        $sourceParent = Split-Path -Parent $sourceDir
        if (-not (Get-PlasticineItem $sourceParent)) {
            New-Item -ItemType Directory -Path $sourceParent -Force -ErrorAction Stop | Out-Null
        }
        Write-PlasticineLog 'Cloning chezmoi source...'
        $clone = Invoke-PlasticineGitCommand -Argument @('clone', '--', $repoUrl, $sourceDir)
        if ($clone.ExitCode -ne 0) { Stop-Plasticine "could not clone the chezmoi source: $repoUrl" }
        if ($PlasticineRepoRevision) {
            $resolved = Invoke-PlasticineGitCommand -Directory $sourceDir -Argument @('rev-parse', $PlasticineRepoRevision + '^{commit}')
            if (($resolved.Output -join '').Trim() -ne $PlasticineRepoRevision) {
                Stop-Plasticine "Release revision is unavailable from the repository: $PlasticineRepoRevision"
            }
            Invoke-PlasticineGitCommand -Directory $sourceDir -Argument @('checkout', '--detach', $PlasticineRepoRevision) | Out-Null
        }
    }

    if (-not (Get-PlasticineItem (Join-Path $sourceDir '.chezmoi.toml.tmpl'))) {
        Stop-Plasticine 'The source repository does not contain .chezmoi.toml.tmpl.'
    }
    $configItem = Get-PlasticineItem $configFile
    if ($configItem -and ($configItem.PSIsContainer -or (Test-PlasticineReparsePoint $configItem))) {
        Stop-Plasticine "chezmoi config is not a regular file: $configFile"
    }
    foreach ($parent in @((Split-Path -Parent $configFile), (Split-Path -Parent $stateFile))) {
        if (-not (Get-PlasticineItem $parent)) {
            New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
        }
        Assert-PlasticineRealDirectory $parent
    }

    $commonArgument = @(
        '-S', $sourceDir,
        '-D', $destinationDir,
        '-c', $configFile,
        '--persistent-state', $stateFile
    )
    if ($script:PlasticineYes) { $commonArgument += '--no-tty' }
    Write-PlasticineLog 'Selecting tools...'
    & $chezmoi @commonArgument init
    if ($LASTEXITCODE -ne 0) { Stop-Plasticine 'chezmoi init did not complete.' }
    $configItem = Get-PlasticineItem $configFile
    if (-not $configItem -or $configItem.PSIsContainer -or $configItem.Length -eq 0) {
        Stop-Plasticine 'Generated chezmoi config is empty.'
    }
    Set-PlasticineOwnerOnlyAcl -Path $configFile

    $tools = @(Get-PlasticineSelectedToolsFromConfig $configFile)
    Write-PlasticineLog ('Selected tools: ' + $(if ($tools.Count -gt 0) { $tools -join ' ' } else { '(none)' }))

    if ($PlasticineReleaseVersion -and ($tools -contains 'neovim')) {
        $archive = Invoke-PlasticineReleasePluginAcquisition -HomeDirectory $homeDirectory `
            -Base $releaseBaseUrl -Version $PlasticineReleaseVersion -Digest $PlasticinePluginsSha256
        $env:PLASTICINE_MANAGED_PLUGINS_ARCHIVE = $archive
    } else {
        Remove-Item Env:PLASTICINE_MANAGED_PLUGINS_ARCHIVE -ErrorAction SilentlyContinue
    }

    foreach ($feature in $PlasticineFeatureOrder) {
        if ($tools -notcontains $feature) { continue }
        $previewFunction = Get-PlasticineFeaturePreviewFunction $feature
        if (-not (Test-PlasticineFunction $previewFunction)) {
            if ($PlasticineFeaturePreviewRequired -contains $feature) {
                Stop-Plasticine "selected feature has no Windows route in this release: $feature"
            }
            continue
        }
        $planFunction = Get-PlasticineFeaturePlanFunction $feature
        if (-not (Test-PlasticineFunction $planFunction)) {
            Stop-Plasticine "selected feature has no Windows plan in this release: $feature"
        }
        Write-PlasticineLog "Previewing $feature..."
        $plan = & $planFunction -HomeDirectory $homeDirectory
        & $previewFunction -Plan $plan
    }

    Write-PlasticineLog 'Previewing changes...'
    & $chezmoi @commonArgument --no-pager diff

    if (-not $script:PlasticineYes) {
        [Console]::Out.Write('Apply these changes? [y/N] ')
        $answer = [Console]::In.ReadLine()
        if (-not $answer -or $answer -notmatch '^(y|Y|yes|YES|Yes)$') {
            Write-PlasticineLog 'Cancelled; no changes were applied.'
            exit 0
        }
    }

    Write-PlasticineLog 'Applying changes...'
    & $chezmoi @commonArgument --error-on-conflict apply
    $applyStatus = $LASTEXITCODE
    if ($applyStatus -ne 0) {
        Report-PlasticineApplyConflicts -Chezmoi $chezmoi -CommonArgument $commonArgument
        exit 1
    }

    $binDirectory = Join-Path $homeDirectory '.local\bin'
    if (-not ($script:PlasticineFeatures['powershell']) -and
        -not (Test-PlasticineUserPathContains -Path $binDirectory)) {
        Write-PlasticineLog "Add $binDirectory to PATH, or rerun with -Powershell to maintain the user PATH and profile."
    }
    Write-PlasticineLog 'Done.'
}

function Test-PlasticineUserPathContains {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-PlasticineFunction 'Get-PlasticineUserPath')) { return $false }
    $entries = Get-PlasticineUserPath
    $normalized = $Path.TrimEnd('\')
    foreach ($entry in $entries) {
        if ($entry.TrimEnd('\') -ieq $normalized) { return $true }
    }
    return $false
}

$script:PlasticineYes = $false
$script:PlasticineHelp = $false
$script:PlasticineFeatures = [ordered]@{
    'git-config' = $false
    'github-ssh' = $false
    'lazygit' = $false
    'fnm' = $false
    'rust' = $false
    'uv' = $false
    'neovim' = $false
    'herdr' = $false
    'npmrc' = $false
    'powershell' = $false
}
$script:PlasticineGitHubSshKey = ''
$script:PlasticineGitHubSshTest = $false
$script:PlasticineReplaceGitHubSshKey = $false

$plasticineArguments = @($args)
for ($index = 0; $index -lt $plasticineArguments.Count; $index++) {
    $token = [string]$plasticineArguments[$index]
    if (-not $token.StartsWith('-')) { Stop-PlasticineUsage "Unknown option: $token" }
    $name = $token.TrimStart('-')
    $value = ''
    if ($name.Contains('=')) {
        $split = $name.Split('=', 2)
        $name = $split[0]
        $value = $split[1]
    }
    switch ($name.ToLowerInvariant()) {
        'y' { $script:PlasticineYes = $true }
        'yes' { $script:PlasticineYes = $true }
        'git-config' { $script:PlasticineFeatures['git-config'] = $true }
        'npmrc' { $script:PlasticineFeatures['npmrc'] = $true }
        'github-ssh' { $script:PlasticineFeatures['github-ssh'] = $true }
        'github-ssh-key' {
            if (-not $value) {
                if ($index + 1 -ge $plasticineArguments.Count) { Stop-PlasticineUsage '-GithubSshKey requires a path.' }
                $index++
                $value = [string]$plasticineArguments[$index]
            }
            $script:PlasticineGitHubSshKey = $value
        }
        'github-ssh-test' { $script:PlasticineGitHubSshTest = $true }
        'replace-github-ssh-key' { $script:PlasticineReplaceGitHubSshKey = $true }
        'herdr' { $script:PlasticineFeatures['herdr'] = $true }
        'lazygit' { $script:PlasticineFeatures['lazygit'] = $true }
        'fnm' { $script:PlasticineFeatures['fnm'] = $true }
        'rust' { $script:PlasticineFeatures['rust'] = $true }
        'uv' { $script:PlasticineFeatures['uv'] = $true }
        'neovim' { $script:PlasticineFeatures['neovim'] = $true }
        'powershell' { $script:PlasticineFeatures['powershell'] = $true }
        'help' { $script:PlasticineHelp = $true }
        'h' { $script:PlasticineHelp = $true }
        default { Stop-PlasticineUsage "Unknown option: $token" }
    }
}

if ($script:PlasticineHelp) {
    Write-PlasticineEntryUsage
    exit 0
}

try {
    Invoke-PlasticineEntry
} catch {
    $exception = $_.Exception
    if ($exception.GetType().Name -eq 'PlasticineStopException') { exit 1 }
    if ($exception -is [System.Management.Automation.RuntimeException] -and
        $exception.Message -match '^(chezmoi prerequisite|release payload|source|installation|archive|missing|not a|unsupported|the Windows|selected feature|run as|HOME|Required|chezmoi|could not|atomic|directory|Interactive|Tool options|GitHub SSH options|GithubSsh|Unknown option|apply)') {
        exit 1
    }
    Write-PlasticineError $exception.Message
    exit 1
}

exit 0
