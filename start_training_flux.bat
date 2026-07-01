@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "PAUSE_AFTER_RUN="

if "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%start_training_flux.ps1"
) else if /i "%~x1"==".toml" (
    set "PAUSE_AFTER_RUN=1"
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%start_training_flux.ps1" -ConfigPath "%~1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%start_training_flux.ps1" %*
)
set "EXIT_CODE=%ERRORLEVEL%"

if defined PAUSE_AFTER_RUN (
    echo.
    if not "%EXIT_CODE%"=="0" echo start_training_flux failed with exit code %EXIT_CODE%.
    pause
)

IF not defined PAUSE_AFTER_RUN IF /i "%comspec% /c %~0 " equ "%cmdcmdline:"=%" (
    echo.
    if not "%EXIT_CODE%"=="0" echo start_training_flux failed with exit code %EXIT_CODE%.
    pause
)

exit /b %EXIT_CODE%
