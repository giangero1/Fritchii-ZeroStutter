@echo off
setlocal EnableDelayedExpansion
title Fritchii Zero-Stutter Automated Upgrade Engine
cd /d "%~dp0"

echo ======================================================================
echo           FRITCHII ZERO-STUTTER AUTOMATED UPGRADE ENGINE             
echo ======================================================================
echo.
echo This tool automatically ports all custom zero-stutter patches to any
echo Fritchii / Fritz version tag, compiles via Clang ThinLTO, and deploys
echo the pre-warmed shaders, Reflex DLLs, and save-syncing launcher.
echo.

set "TAG=%~1"
if "%TAG%"=="" (
    set /p "TAG=Enter target Git Tag or Release [default: fritchii-v5.3]: "
)
if "%TAG%"=="" set "TAG=fritchii-v5.3"

echo.
echo [START] Upgrading to %TAG%...
echo.

if exist "%~dp0tools\Upgrade-Fritchii.ps1" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Upgrade-Fritchii.ps1" -Tag "%TAG%"
) else if exist "%~dp0Upgrade-Fritchii.ps1" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Upgrade-Fritchii.ps1" -Tag "%TAG%"
) else (
    echo [ERROR] Upgrade-Fritchii.ps1 not found!
    pause
    exit /b 1
)

if errorlevel 1 (
    echo.
    echo ======================================================================
    echo [ERROR] Upgrade encountered an error. Check logs above.
    echo ======================================================================
    pause
    exit /b 1
)

echo.
echo ======================================================================
echo [SUCCESS] Upgrade complete! You can now launch your new build.
echo ======================================================================
pause
