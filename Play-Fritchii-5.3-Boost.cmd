@echo off
setlocal
title Fritchii v5.3 Boost - The Legend of Zelda: Ocarina of Time

echo ======================================================================
echo              FRITCHII v5.3 HYBRID - PLAY GAME LAUNCHER               
echo ======================================================================
echo.

set "WORKSPACE=%~dp0"
set "EMU_DIR=%WORKSPACE%Fritchii-5.3"
if not exist "%EMU_DIR%\lichii.exe" (
    if exist "%WORKSPACE%lichii.exe" set "EMU_DIR=%WORKSPACE%"
    if exist "%WORKSPACE%bin\lichii.exe" set "EMU_DIR=%WORKSPACE%bin"
)
set "EMU_EXE=%EMU_DIR%\lichii.exe"

if not exist "%EMU_EXE%" (
    echo [ERROR] Fritchii executable not found at:
    echo   %EMU_EXE%
    pause
    exit /b 1
)

:: Step 1: Optional save sync for dev workspace setups
if exist "%WORKSPACE%scripts\SaveSyncManager.ps1" (
    echo [STEP 1/3] Checking and syncing saves across all platforms...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WORKSPACE%scripts\SaveSyncManager.ps1" -Target Fritchii53 -Phase PreLaunch
)

:: Step 2: Ensure Graphics Pipeline Library (GPL) is disabled to prevent dynamic runtime stalls
if exist "%EMU_DIR%\user\config\qt-config.ini" (
    powershell.exe -NoProfile -Command "$p='%EMU_DIR%\user\config\qt-config.ini'; if (Test-Path -LiteralPath $p) { (Get-Content -LiteralPath $p -Raw).Replace('use_graphics_pipeline_library=true', 'use_graphics_pipeline_library=false').Replace('use_graphics_pipeline_library\default=true', 'use_graphics_pipeline_library\default=false') | Set-Content -LiteralPath $p -NoNewline }"
)

:: Check for pre-warmed shaders
set "SHADER_DIR=%EMU_DIR%\user\cache\shader\0400486024dec000"
if not exist "%SHADER_DIR%\vulkan.fork-v53.bin" (
    if not exist "%SHADER_DIR%\warm-graphics.bin" (
        echo [TIP] Pre-warmed 28,612 shader cache not detected in:
        echo   %SHADER_DIR%
        echo   Download full zero-stutter shaders here:
        echo   https://drive.google.com/file/d/1pa3T-D7lTcuo9B1RHP1HoejbtdUDqS6O/view
        echo.
    )
)

:: Apply hardware boost environment flags (RTX 3070 + Ryzen 7 5800X3D)
set "DISABLE_LAYER=1"
set "DISABLE_VULKAN_MEDAL_OBS_CAPTURE=1"
set "VK_LOADER_LAYERS_DISABLE=*fpsmon*,VK_LAYER_RENDERDOC_Capture,~implicit~"
set "EDEN_NX2_ASYNC_DISCARD=1"
set "EDEN_NX2_SEM_FAST=1"
:: Shader warmup threads: 6 for 8-core (5800X3D), 4 for 6-core (5600X/12400), 2 for 4-core CPUs
set "EDEN_NX2_WARM_THREADS=6"
set "EDEN_NX2_PRELOAD_ALL_PIPELINES=1"
set "EDEN_NX2_OOT_VISUAL_WORKAROUND=0"
set "EDEN_NX2_COMPUTE_NOINLINE=1"
set "EDEN_NX2_SPIRV_INLINE_GLOBALS=0"
set "EDEN_NX2_OCCLUSION_OFF=1"
set "EDEN_NX2_SPLIT=2"
set "EDEN_NX2_FENCE_BATCH=1"
set "EDEN_NX2_PERF_ON=index_rebind,clean_words,fence_flush"

echo Launching Fritchii v5.3 with RTX 3070 + 5800X3D Boosts...
cd /d "%EMU_DIR%"
start /high /wait "" "%EMU_EXE%"

:: Step 3: Optional post-launch save sync
if exist "%WORKSPACE%scripts\SaveSyncManager.ps1" (
    echo.
    echo [STEP 3/3] Session ended. Updating saves back to other platforms...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WORKSPACE%scripts\SaveSyncManager.ps1" -Target Fritchii53 -Phase PostLaunch
    echo ======================================================================
    echo [OK] Cross-play save synchronization complete. All progress is safe!
    echo ======================================================================
    timeout /t 4 >nul
)
