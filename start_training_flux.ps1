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
    $ConfigPath = "training_settings\flux\training_setting.toml"
}

Start-SdScriptsTraining `
    -ProjectRoot $ProjectRoot `
    -ConfigPath $ConfigPath `
    -TrainScriptNames @("flux_train_network.py") `
    -DisplayName "FLUX" `
    -SdScriptsUrl $SdScriptsUrl `
    -SkipUpdate:$SkipUpdate `
    -NoSync:$NoSync `
    -ForceOverwrite:$ForceOverwrite `
    -ExtraArgs $ExtraArgs
