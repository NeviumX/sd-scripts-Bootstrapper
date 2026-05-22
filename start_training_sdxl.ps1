[CmdletBinding()]
param(
    [string]$ConfigPath = "",
    [string]$SdScriptsUrl = "https://github.com/kohya-ss/sd-scripts.git",
    [switch]$SkipUpdate,
    [switch]$NoSync,
    [switch]$ForceOverwrite,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs = @()
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "scripts\bootstrapper_common.ps1")

$ProjectRoot = Get-BootstrapperRoot -CallerRoot $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = "training_settings\sdxl\training_setting.toml"
}

Start-SdScriptsTraining `
    -ProjectRoot $ProjectRoot `
    -ConfigPath $ConfigPath `
    -TrainScriptNames @("sdxl_train_network.py") `
    -DisplayName "SDXL" `
    -SdScriptsUrl $SdScriptsUrl `
    -SkipUpdate:$SkipUpdate `
    -NoSync:$NoSync `
    -ForceOverwrite:$ForceOverwrite `
    -ExtraArgs $ExtraArgs
