@echo off
setlocal

set "SCRIPT_DIR=%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%start_training_sdxl.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

IF /i "%comspec% /c %~0 " equ "%cmdcmdline:"=%" (
    echo.
    if not "%EXIT_CODE%"=="0" echo start_training_sdxl failed with exit code %EXIT_CODE%.
    pause
)

exit /b %EXIT_CODE%
