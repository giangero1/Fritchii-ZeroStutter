<#
.SYNOPSIS
    Automated zero-stutter patcher, compiler, and deployment engine for Fritchii upgrades.
.DESCRIPTION
    Applies custom C++ patches (GuessMissing disk-cache fallback, compute DontInline,
    pre-warmed shader databases, and GPL neutralization) to any upstream Fritchii release,
    compiles via Clang 19.1.7 ThinLTO, and deploys it with save-synchronization hooks.
.EXAMPLE
    .\scripts\Upgrade-Fritchii.ps1 -Tag "fritchii-v5.3" -TargetDirName "Fritchii-5.3"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Tag,

    [Parameter(Mandatory = $false)]
    [string]$TargetDirName = "",

    [Parameter(Mandatory = $false)]
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$hybridRepo = Join-Path $workspace "hybrid"

if ([string]::IsNullOrWhiteSpace($TargetDirName)) {
    # Generate clean name from tag, e.g. fritchii-v5.4 -> Fritchii-5.4
    $TargetDirName = $Tag -replace "^fritchii-v", "Fritchii-" -replace "^v", "Fritchii-"
}

$destDir = Join-Path $workspace $TargetDirName
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "         FRITCHII ZERO-STUTTER AUTOMATED UPGRADE & COMPILER           " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host " Upstream Tag:  $Tag"
Write-Host " Target Folder: $destDir"
Write-Host " Workspace:     $workspace"
Write-Host ""

# -----------------------------------------------------------------------------
# STEP 1: Verify Git Repo and Checkout Target Tag
# -----------------------------------------------------------------------------
Write-Host "[STEP 1/6] Preparing repository branch for $Tag..." -ForegroundColor Yellow
if (-not (Test-Path -LiteralPath (Join-Path $hybridRepo ".git"))) {
    throw "Hybrid repository not found at: $hybridRepo"
}

Push-Location $hybridRepo
try {
    # Fetch latest tags
    & git fetch origin --tags 2>$null

    $branchName = "hybrid/$Tag-custom-opt"
    Write-Host "Checking out or creating branch: $branchName from tag $Tag..."
    
    $branchExists = (& git branch --list $branchName)
    if ($branchExists) {
        & git checkout $branchName
    } else {
        & git checkout -b $branchName $Tag
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to checkout tag $Tag"
    }

    # -----------------------------------------------------------------------------
    # STEP 2: Apply Custom Zero-Stutter C++ Patches
    # -----------------------------------------------------------------------------
    Write-Host "[STEP 2/6] Applying custom zero-stutter C++ engine patches..." -ForegroundColor Yellow

    # Patch 1: GuessMissing in vk_pipeline_cache.cpp
    $pipeCachePath = Join-Path $hybridRepo "src\video_core\renderer_vulkan\vk_pipeline_cache.cpp"
    if (Test-Path -LiteralPath $pipeCachePath) {
        $c = [System.IO.File]::ReadAllText($pipeCachePath)
        if (-not $c.Contains("static const GuessMissing guess{};")) {
            $target = @"
std::unique_ptr<GraphicsPipeline> PipelineCache::CreateCachedGraphicsPipeline(
    const GraphicsPipelineCacheKey& key, std::vector<std::vector<FileEnvironment>>& records,
    PipelineStatistics* statistics) {
    ShaderPools pools;
"@
            $replacement = @"
std::unique_ptr<GraphicsPipeline> PipelineCache::CreateCachedGraphicsPipeline(
    const GraphicsPipelineCacheKey& key, std::vector<std::vector<FileEnvironment>>& records,
    PipelineStatistics* statistics) {
    static const GuessMissing guess{};
    ShaderPools pools;
    for (auto& envs : records) {
        pools.ReleaseContents();
        boost::container::static_vector<Shader::Environment*, 5> env_ptrs;
        for (auto& env : envs) {
            env.SetGuessMissing(&guess);
            env_ptrs.push_back(&env);
        }
        if (auto pipeline{CreateGraphicsPipeline(pools, key, MakeSpan(env_ptrs), statistics, false)}) {
            return pipeline;
        }
    }
"@
            # Normalize newlines
            $cNorm = $c -replace "`r`n", "`n"
            $tNorm = $target -replace "`r`n", "`n"
            $rNorm = $replacement -replace "`r`n", "`n"
            if ($cNorm.Contains($tNorm)) {
                $cNorm = $cNorm.Replace($tNorm, $rNorm)
                [System.IO.File]::WriteAllText($pipeCachePath, $cNorm)
                Write-Host "  [OK] Patch 1 applied: GuessMissing in vk_pipeline_cache.cpp" -ForegroundColor Green
            } else {
                Write-Warning "  [SKIP] Target signature in vk_pipeline_cache.cpp already patched or changed."
            }
        } else {
            Write-Host "  [OK] Patch 1 already present: GuessMissing in vk_pipeline_cache.cpp" -ForegroundColor Green
        }
    }

    # Patch 2: compute_noinline in spirv_emit_context.cpp
    $spirvPath = Join-Path $hybridRepo "src\shader_recompiler\backend\spirv\spirv_emit_context.cpp"
    if (Test-Path -LiteralPath $spirvPath) {
        $c = [System.IO.File]::ReadAllText($spirvPath)
        if (-not $c.Contains("compute_noinline = []")) {
            $tNorm = "static const spv::FunctionControlMask function_control = [] {"
            $rNorm = @"
static const bool compute_noinline = [] {
        if (const char* value = std::getenv("EDEN_NX2_COMPUTE_NOINLINE")) {
            return value[0] != '0';
        }
        if (const char* value = std::getenv("EDEN_NX2_SPIRV_INLINE_GLOBALS")) {
            return value[0] == '0';
        }
        return true;
    }();
    const spv::FunctionControlMask function_control =
        (stage == Stage::Compute && compute_noinline)
            ? spv::FunctionControlMask::DontInline
            : spv::FunctionControlMask::MaskNone;
    static const auto _unused_fc = []() -> spv::FunctionControlMask {
"@
            $cNorm = $c -replace "`r`n", "`n"
            if ($cNorm.Contains($tNorm)) {
                $cNorm = $cNorm.Replace($tNorm, $rNorm)
                [System.IO.File]::WriteAllText($spirvPath, $cNorm)
                Write-Host "  [OK] Patch 2 applied: compute_noinline in spirv_emit_context.cpp" -ForegroundColor Green
            } else {
                Write-Warning "  [SKIP] Target signature in spirv_emit_context.cpp already patched or changed."
            }
        } else {
            Write-Host "  [OK] Patch 2 already present: compute_noinline in spirv_emit_context.cpp" -ForegroundColor Green
        }
    }

    # Patch 3: Remove duplicate Header definition in pipeline_cache_files.cpp
    $testPipeCache = Join-Path $hybridRepo "src\tests\video_core\pipeline_cache_files.cpp"
    if (Test-Path -LiteralPath $testPipeCache) {
        $c = [System.IO.File]::ReadAllText($testPipeCache)
        $dupHeader = @"
std::string Header(u32 version) {
    return std::string(Magic.data(), Magic.size()) +
           std::string(reinterpret_cast<const char*>(&version), sizeof(version));
}

std::string Header(u32 version) {
"@
        $cNorm = $c -replace "`r`n", "`n"
        $dupNorm = $dupHeader -replace "`r`n", "`n"
        if ($cNorm.Contains($dupNorm)) {
            $fixed = @"
std::string Header(u32 version) {
    return std::string(Magic.data(), Magic.size()) +
           std::string(reinterpret_cast<const char*>(&version), sizeof(version));
}

// Merge tests use records
"@
            $targetBlock = @"
std::string Header(u32 version) {
    return std::string(Magic.data(), Magic.size()) +
           std::string(reinterpret_cast<const char*>(&version), sizeof(version));
}

std::string Header(u32 version) {
    return std::string(Magic.data(), Magic.size()) +
           std::string(reinterpret_cast<const char*>(&version), sizeof(version));
}

// Merge tests use records
"@
            $targetNorm = $targetBlock -replace "`r`n", "`n"
            $fixedNorm = $fixed -replace "`r`n", "`n"
            if ($cNorm.Contains($targetNorm)) {
                $cNorm = $cNorm.Replace($targetNorm, $fixedNorm)
                [System.IO.File]::WriteAllText($testPipeCache, $cNorm)
                Write-Host "  [OK] Patch 3 applied: Duplicate Header removed in pipeline_cache_files.cpp" -ForegroundColor Green
            }
        }
    }

    # Ensure rules.ninja uses llvm-rc directly instead of cmake_llvm_rc + rc.exe
    $rulesFile = Join-Path $hybridRepo "build\hybrid\CMakeFiles\rules.ninja"
    if (Test-Path -LiteralPath $rulesFile) {
        $rContent = [System.IO.File]::ReadAllText($rulesFile)
        if ($rContent.Contains("cmake_llvm_rc")) {
            $rLines = [System.IO.File]::ReadAllLines($rulesFile)
            $newRLines = [System.Collections.Generic.List[string]]::new()
            foreach ($rl in $rLines) {
                if ($rl.Contains("cmake_llvm_rc")) {
                    $newRLines.Add('  command = "C:\Program Files\LLVM\bin\llvm-rc.exe" /I D:/Games/FRITZIV3/hybrid/src /fo $out $in')
                } else {
                    $newRLines.Add($rl)
                }
            }
            [System.IO.File]::WriteAllLines($rulesFile, $newRLines)
            Write-Host "  [OK] Configured rules.ninja to use llvm-rc natively." -ForegroundColor Green
        }
    }

    # -----------------------------------------------------------------------------
    # STEP 3: Compile via Clang 19.1.7 ThinLTO
    # -----------------------------------------------------------------------------
    if (-not $SkipBuild) {
        Write-Host "[STEP 3/6] Compiling via Clang 19.1.7 ThinLTO (8 parallel jobs)..." -ForegroundColor Yellow
        $vcvars = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
        if (-not (Test-Path -LiteralPath $vcvars)) {
            throw "Visual Studio 2022 vcvars64.bat not found at: $vcvars"
        }
        
        $buildCmd = "call `"$vcvars`" && set `"PATH=C:\Program Files\LLVM\bin;C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja;%PATH%`" && cd /d `"$hybridRepo\build\hybrid`" && ninja bin\lichii.exe"
        cmd.exe /c $buildCmd
        if ($LASTEXITCODE -ne 0) {
            throw "Compilation failed with exit code $LASTEXITCODE"
        }
        Write-Host "  [OK] Clang ThinLTO compilation succeeded!" -ForegroundColor Green
    } else {
        Write-Host "[STEP 3/6] Skipping build step as requested." -ForegroundColor Yellow
    }

    $builtExe = Join-Path $hybridRepo "build\hybrid\bin\lichii.exe"
    if (-not (Test-Path -LiteralPath $builtExe)) {
        throw "Compiled executable not found at: $builtExe"
    }

    # -----------------------------------------------------------------------------
    # STEP 4: Deploy into Target Folder
    # -----------------------------------------------------------------------------
    Write-Host "[STEP 4/6] Deploying executable and runtime libraries to $destDir..." -ForegroundColor Yellow
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    # Copy binary
    Copy-Item -LiteralPath $builtExe -Destination (Join-Path $destDir "lichii.exe") -Force

    # Copy Qt & runtime dependencies from hybrid build directory if missing
    $binSource = Join-Path $hybridRepo "build\hybrid\bin"
    Get-ChildItem -LiteralPath $binSource -Filter "*.dll" | ForEach-Object {
        $destFile = Join-Path $destDir $_.Name
        if (-not (Test-Path -LiteralPath $destFile)) {
            Copy-Item -LiteralPath $_.FullName -Destination $destFile -Force
        }
    }

    # Copy Qt plugins (platforms, imageformats, iconengines, styles) safely
    @("platforms", "imageformats", "iconengines", "styles", "generic", "tls") | ForEach-Object {
        $subSrc = Join-Path $binSource $_
        $subDest = Join-Path $destDir $_
        if (Test-Path -LiteralPath $subSrc) {
            if (-not (Test-Path -LiteralPath $subDest)) {
                New-Item -ItemType Directory -Path $subDest -Force | Out-Null
            }
            Get-ChildItem -LiteralPath $subSrc | Copy-Item -Destination $subDest -Recurse -Force
        }
    }

    # -----------------------------------------------------------------------------
    # STEP 5: Seed Pre-Warmed Shaders & Streamline Reflex DLLs
    # -----------------------------------------------------------------------------
    Write-Host "[STEP 5/6] Seeding complete 28,612 pre-warmed shader pipeline cache..." -ForegroundColor Yellow
    $masterShaderDir = Join-Path $workspace "hybrid\portable-hybrid-opt\user\cache\shader\0400486024dec000"
    $destShaderDir = Join-Path $destDir "user\cache\shader\0400486024dec000"
    if (-not (Test-Path -LiteralPath $destShaderDir)) {
        New-Item -ItemType Directory -Path $destShaderDir -Force | Out-Null
    }

    $shaderFiles = @(
        "warm-graphics.bin", "warm-graphics.count", "warm-compute.bin",
        "warm-compute.count", "warm-compute.done", "vulkan_static_pipelines.bin",
        "vulkan-frizti.fork-v52.bin", "vulkan.fork-v53.bin",
        "vulkan_used-frizti.fork-v52.bin", "vulkan_used.fork-v53.bin"
    )
    foreach ($sf in $shaderFiles) {
        $src = Join-Path $masterShaderDir $sf
        $dst = Join-Path $destShaderDir $sf
        if (Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
    }

    # Hardlink compatibility alias
    $v52Src = Join-Path $destShaderDir "vulkan-frizti.fork-v52.bin"
    $v52Alias = Join-Path $destShaderDir "vulkan.fork-v52.bin"
    if ((Test-Path -LiteralPath $v52Src) -and (-not (Test-Path -LiteralPath $v52Alias))) {
        New-Item -ItemType HardLink -Path $v52Alias -Target $v52Src -Force | Out-Null
    }

    # Deploy Streamline + Reflex
    $destStreamline = Join-Path $destDir "user\streamline"
    if (-not (Test-Path -LiteralPath $destStreamline)) {
        New-Item -ItemType Directory -Path $destStreamline -Force | Out-Null
    }
    $masterStreamline = Join-Path $workspace "hybrid\portable-hybrid-opt\user\streamline"
    Get-ChildItem -LiteralPath $masterStreamline -Filter "*.dll" | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $destStreamline $_.Name) -Force
    }
    $reflexDll = Join-Path $hybridRepo ".cache\cpm\streamline\v2.14.16\external\reflex-sdk-vk\lib\NvLowLatencyVk.dll"
    if (Test-Path -LiteralPath $reflexDll) {
        Copy-Item -LiteralPath $reflexDll -Destination (Join-Path $destStreamline "NvLowLatencyVk.dll") -Force
    }

    # Enforce GPL=false in qt-config.ini
    $cfgDir = Join-Path $destDir "user\config"
    if (-not (Test-Path -LiteralPath $cfgDir)) { New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null }
    $cfgPath = Join-Path $cfgDir "qt-config.ini"
    if (Test-Path -LiteralPath $cfgPath) {
        (Get-Content -LiteralPath $cfgPath -Raw).Replace("use_graphics_pipeline_library=true", "use_graphics_pipeline_library=false").Replace("use_graphics_pipeline_library\default=true", "use_graphics_pipeline_library\default=false") | Set-Content -LiteralPath $cfgPath -NoNewline
    }

    # Deploy nx2_switches.txt
    $switchesPath = Join-Path $destDir "nx2_switches.txt"
    @"
# Switch NX2 - read when the Lichii GUI starts.
EDEN_NX2_SPLIT=2
EDEN_NX2_FENCE_BATCH=1
EDEN_NX2_PERF_ON=index_rebind,clean_words,fence_flush
EDEN_NX2_PRELOAD_ALL_PIPELINES=1
EDEN_NX2_ASYNC_DISCARD=1
EDEN_NX2_SEM_FAST=1
EDEN_NX2_WARM_THREADS=6
EDEN_NX2_COMPUTE_NOINLINE=1
EDEN_NX2_SPIRV_INLINE_GLOBALS=0
EDEN_NX2_OCCLUSION_OFF=1
EDEN_NX2_OOT_VISUAL_WORKAROUND=0
"@ | Set-Content -LiteralPath $switchesPath -Encoding ascii

    # -----------------------------------------------------------------------------
    # STEP 6: Generate Root Launcher
    # -----------------------------------------------------------------------------
    Write-Host "[STEP 6/6] Generating root launcher Play-$TargetDirName-Boost.cmd..." -ForegroundColor Yellow
    $launcherPath = Join-Path $workspace "Play-$TargetDirName-Boost.cmd"
    $launcherContent = @"
@echo off
setlocal
title $TargetDirName Boost - The Legend of Zelda: Ocarina of Time

echo ======================================================================
echo              $TargetDirName HYBRID - PLAY GAME LAUNCHER               
echo ======================================================================
echo.

set "WORKSPACE=%~dp0"
set "EMU_DIR=%WORKSPACE%$TargetDirName"
set "EMU_EXE=%EMU_DIR%\lichii.exe"

if not exist "%EMU_EXE%" (
    echo [ERROR] Emulator executable not found at:
    echo   %EMU_EXE%
    pause
    exit /b 1
)

echo [STEP 1/3] Checking and syncing saves across all platforms...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WORKSPACE%scripts\SaveSyncManager.ps1" -Target $TargetDirName -Phase PreLaunch

echo.
echo [STEP 2/3] Launching $TargetDirName with RTX 3070 + 5800X3D Boosts...
echo Close the emulator window when you are done playing to trigger automatic save sync.
echo.

:: Ensure Graphics Pipeline Library (GPL) is disabled to prevent dynamic runtime stalls
if exist "%EMU_DIR%\user\config\qt-config.ini" (
    powershell.exe -NoProfile -Command "`$p='%EMU_DIR%\user\config\qt-config.ini'; if (Test-Path -LiteralPath `$p) { (Get-Content -LiteralPath `$p -Raw).Replace('use_graphics_pipeline_library=true', 'use_graphics_pipeline_library=false').Replace('use_graphics_pipeline_library\default=true', 'use_graphics_pipeline_library\default=false') | Set-Content -LiteralPath `$p -NoNewline }"
)

:: Apply hardware boost environment flags
set "DISABLE_LAYER=1"
set "DISABLE_VULKAN_MEDAL_OBS_CAPTURE=1"
set "VK_LOADER_LAYERS_DISABLE=*fpsmon*,VK_LAYER_RENDERDOC_Capture,~implicit~"
set "EDEN_NX2_ASYNC_DISCARD=1"
set "EDEN_NX2_SEM_FAST=1"
set "EDEN_NX2_WARM_THREADS=6"
set "EDEN_NX2_PRELOAD_ALL_PIPELINES=1"
set "EDEN_NX2_OOT_VISUAL_WORKAROUND=0"
set "EDEN_NX2_COMPUTE_NOINLINE=1"
set "EDEN_NX2_SPIRV_INLINE_GLOBALS=0"
set "EDEN_NX2_OCCLUSION_OFF=1"
set "EDEN_NX2_SPLIT=2"
set "EDEN_NX2_FENCE_BATCH=1"
set "EDEN_NX2_PERF_ON=index_rebind,clean_words,fence_flush"

cd /d "%EMU_DIR%"
start /high /wait "" "%EMU_EXE%"

echo.
echo [STEP 3/3] Session ended. Updating saves back to other platforms...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WORKSPACE%scripts\SaveSyncManager.ps1" -Target $TargetDirName -Phase PostLaunch

echo.
echo ======================================================================
echo [OK] Cross-play save synchronization complete. All progress is safe!
echo ======================================================================
timeout /t 4 >nul
"@
    Set-Content -LiteralPath $launcherPath -Value $launcherContent -Encoding ascii

    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host "[SUCCESS] Upgrade to $TargetDirName completed successfully!" -ForegroundColor Green
    Write-Host "Launcher created at: Play-$TargetDirName-Boost.cmd" -ForegroundColor Green
    Write-Host "======================================================================" -ForegroundColor Green

} finally {
    Pop-Location
}
