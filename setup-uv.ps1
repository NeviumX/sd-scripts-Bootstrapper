[CmdletBinding()]
param(
    [string]$SdScriptsUrl = "https://github.com/kohya-ss/sd-scripts.git",
    [switch]$SkipSync
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "scripts\bootstrapper_common.ps1")

$ProjectRoot = Get-BootstrapperRoot -CallerRoot $PSScriptRoot

Write-Host "sd-scripts bootstrapper setup"
Write-Host "Project: $ProjectRoot"

Ensure-Git
$sdScriptsDir = Ensure-SdScriptsRepo -ProjectRoot $ProjectRoot -RepoUrl $SdScriptsUrl
$customOptimizerDir = Ensure-CustomOptimizerRepo -ProjectRoot $ProjectRoot

if (-not $SkipSync) {
    $forceReinstall = $false
    if (Test-PythonEnvironmentInstalled -ProjectRoot $ProjectRoot) {
        Write-Host ""
        Write-Host "Python environment is already installed."
        $answer = Read-Host "Reinstall the Python environment? (Y/N)"
        $forceReinstall = ($answer -match "^(Y|y|YES|yes)$")

        if (-not $forceReinstall) {
            Write-Host "Skipping Python environment installation."
        }
    }

    if ($forceReinstall -or -not (Test-PythonEnvironmentInstalled -ProjectRoot $ProjectRoot)) {
        Invoke-PythonProjectInstall -ProjectRoot $ProjectRoot -SdScriptsDir $sdScriptsDir -ForceReinstall:$forceReinstall
    }
}

Write-Host ""
Write-Host "Setup complete."
Write-Host "sd-scripts: $sdScriptsDir"
Write-Host "optimizer:  $customOptimizerDir"
Write-Host "venv:       $(Join-Path $ProjectRoot '.venv')"
