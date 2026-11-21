@echo off
setlocal
cd /d "%~dp0.."

set "TEMP=%CD%\.tmp"
set "TMP=%CD%\.tmp"
if not exist "%CD%\.tmp" mkdir "%CD%\.tmp"

set "EXE=%CD%\build\hybrid-pgo-gen\bin\lichii.exe"
if not exist "%EXE%" (
    echo Error: Instrumented binary not found at %EXE%.
    echo Run tools\build-pgo-instrumented.cmd first.
    exit /b 1
)

set "PGO_DATA=%CD%\build\pgo-data"
if not exist "%PGO_DATA%" mkdir "%PGO_DATA%"

set "LLVM_PROFILE_FILE=%PGO_DATA%\lichii-%%m-%%p.profraw"
set "DISABLE_LAYER=1"
set "DISABLE_VULKAN_MEDAL_OBS_CAPTURE=1"
set "VK_LOADER_LAYERS_DISABLE=*fpsmon*,VK_LAYER_RENDERDOC_Capture,~implicit~"
set "EDEN_NX2_ASYNC_DISCARD=1"
set "EDEN_NX2_SEM_FAST=1"

echo ========================================================
echo Launching instrumented Lichii for PGO profile collection.
echo Profiles will be written to: %PGO_DATA%
echo.
echo Instructions:
echo  1. Load your Switch 2 Ocarina of Time (or other test title).
echo  2. Play representative scenes (Kokiri Forest, Hyrule Field)
echo     for 5-10 minutes under steady gameplay.
echo  3. Exit the emulator normally (File ^> Exit) so profiles flush.
echo ========================================================

cd /d "%CD%\build\hybrid-pgo-gen\bin"
"%EXE%"

cd /d "%~dp0.."
echo.
echo Checking captured profiles in %PGO_DATA%...
dir /b "%PGO_DATA%\*.profraw" 2>nul
if errorlevel 1 (
    echo Warning: No .profraw files were generated. Ensure the emulator exited gracefully.
) else (
    echo Profile capture successful.
    echo Next step: Run tools\build-pgo-optimized.cmd to merge profiles and produce the PGO binary.
)
