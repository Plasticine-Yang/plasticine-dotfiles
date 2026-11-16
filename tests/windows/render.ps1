# Renders every Windows apply template with the pinned chezmoi and parses the
# result. A template that emits invalid PowerShell (for example a trailing comma
# in an array literal) fails here instead of during a real installation.

$repoDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'harness.ps1')
$PlasticineTestName = 'windows render'

function Get-RenderChezmoi {
    $candidates = @()
    if ($env:PLASTICINE_TEST_CHEZMOI_BIN) { $candidates += $env:PLASTICINE_TEST_CHEZMOI_BIN }
    if ($env:USERPROFILE) { $candidates += (Join-Path $env:USERPROFILE '.local\bin\chezmoi.exe') }
    foreach ($name in @('chezmoi', 'chezmoi.exe')) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { $candidates += $command.Source }
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    return $null
}

function New-RenderConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Tool
    )
    $quoted = @($Tool | ForEach-Object { '"' + $_ + '"' }) -join ','
    $text = @"
[data]
    tools = [$quoted]
    plasticineShellTargets = []
    plasticineNeovimTargets = []
    githubSSHKeyPath = ""
    githubSSHKeyFingerprint = ""
    githubSSHReplaceFingerprint = ""
    githubSSHTest = false
[interpreters.ps1]
    command = "powershell"
    args = ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File"]
"@
    [IO.File]::WriteAllText($Path, $text)
}

try {
    $chezmoi = Get-RenderChezmoi
    if (-not $chezmoi) {
        Stop-Test 'windows render tests: chezmoi is unavailable; set PLASTICINE_TEST_CHEZMOI_BIN, install the pinned prerequisite, or add it to PATH.'
    }
    Write-Host "render: using chezmoi at $chezmoi"

    $fixture = New-TestDirectory 'render'
    $caseHome = Join-Path $fixture 'home'
    New-Item -ItemType Directory -Path $caseHome -Force | Out-Null
    $allWindowsTools = @(
        'git-config', 'github-ssh', 'herdr', 'lazygit', 'neovim',
        'fnm', 'rust', 'uv', 'npmrc', 'powershell'
    )
    $samples = [ordered]@{
        'all-tools'    = $allWindowsTools
        'config-only'  = @('git-config', 'npmrc')
        'single-tool'  = @('lazygit')
    }
    $renderCount = 0
    foreach ($sample in $samples.Keys) {
        $configPath = Join-Path $fixture ($sample + '.chezmoi.toml')
        New-RenderConfig -Path $configPath -Tool $samples[$sample]
        foreach ($template in Get-ChildItem -LiteralPath (Join-Path $repoDir '.chezmoiscripts') -Filter '*.ps1.tmpl') {
            $rendered = Join-Path $fixture ($sample + '.' + $template.BaseName + '.ps1')
            $stderrFile = Join-Path $fixture ($sample + '.' + $template.BaseName + '.err')
            Get-Content -LiteralPath $template.FullName -Raw |
                & $chezmoi -S $repoDir -D $caseHome -c $configPath execute-template 2> $stderrFile |
                Set-Content -LiteralPath $rendered
            if ($LASTEXITCODE -ne 0) {
                $details = Get-Content -LiteralPath $stderrFile -Raw -ErrorAction SilentlyContinue
                Fail ("template render failed for $($template.Name) ($sample): " + $details.Trim())
            }
            if (-not (Test-Path -LiteralPath $rendered)) { continue }
            if ((Get-Item -LiteralPath $rendered).Length -eq 0) { continue }
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($rendered, [ref]$null, [ref]$errors)
            if (@($errors).Count -gt 0) {
                $first = @($errors)[0]
                Fail ("template renders invalid PowerShell for $($template.Name) ($sample), line " +
                    $first.Extent.StartLineNumber + ': ' + $first.Message)
            }
            $renderCount++
        }
    }
    Assert-True ($renderCount -gt 0) 'no Windows apply template produced a runnable script'
    Write-Host "render: $renderCount rendered script(s) parsed on this PowerShell version"
    Complete-Test 'windows render tests passed'
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
} finally {
    Remove-Item -LiteralPath $PlasticineTestRoot -Recurse -Force -ErrorAction SilentlyContinue
}
