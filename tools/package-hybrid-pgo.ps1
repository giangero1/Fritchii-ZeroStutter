$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$source = Join-Path $repo 'build\hybrid-pgo-use\bin'
$destination = Join-Path $repo 'portable-hybrid-pgo'

if (-not (Test-Path -LiteralPath (Join-Path $source 'lichii.exe'))) {
    throw "The locally built PGO lichii.exe is missing at $source; build first."
}

if (Test-Path -LiteralPath $destination) {
    Remove-Item -LiteralPath $destination -Recurse -Force
}
New-Item -ItemType Directory -Path $destination | Out-Null

Get-ChildItem -LiteralPath $source | Where-Object {
    $_.Name -notin @('user', 'tests.exe', 'update_checker_tests.exe', 'event_wait_probe.exe')
} | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $destination -Recurse
}

New-Item -ItemType Directory -Path (Join-Path $destination 'user') | Out-Null

$qtRoot = Join-Path $repo '.tools\Qt\6.8.3\msvc2022_64'
$svgFiles = @{
    'bin\Qt6Svg.dll' = 'Qt6Svg.dll'
    'plugins\iconengines\qsvgicon.dll' = 'plugins\iconengines\qsvgicon.dll'
    'plugins\imageformats\qsvg.dll' = 'plugins\imageformats\qsvg.dll'
}
foreach ($relative in $svgFiles.Keys) {
    $svgSource = Join-Path $qtRoot $relative
    if (-not (Test-Path -LiteralPath $svgSource)) { throw "Missing Qt SVG support: $relative" }
    $svgDestination = Join-Path $destination $svgFiles[$relative]
    New-Item -ItemType Directory -Path (Split-Path $svgDestination -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $svgSource -Destination $svgDestination -Force
}

@'
[Paths]
Prefix=.
Plugins=plugins
'@ | Set-Content -LiteralPath (Join-Path $destination 'qt.conf') -Encoding ascii

Copy-Item -LiteralPath (Join-Path $repo 'LICENSE.txt') -Destination $destination
Copy-Item -LiteralPath (Join-Path $repo 'LICENSES') -Destination $destination -Recurse
Copy-Item -LiteralPath (Join-Path $repo 'docs\hybrid') -Destination (Join-Path $destination 'audit') -Recurse
Copy-Item -LiteralPath (Join-Path $repo 'cpmfile.json') -Destination $destination

$notices = Join-Path $destination 'dependency-notices'
New-Item -ItemType Directory -Path $notices | Out-Null
Get-ChildItem -LiteralPath (Join-Path $repo '.cache\cpm') -Directory | ForEach-Object {
    $dependency = $_.Name
    Get-ChildItem -LiteralPath $_.FullName -Directory | ForEach-Object {
        $version = $_
        $files = Get-ChildItem -LiteralPath $version.FullName -File | Where-Object { $_.Name -match '^(LICENSE|LICENCE|COPYING|NOTICE|COPYRIGHT)' }
        if ($files) {
            $noticePath = Join-Path $notices "$dependency\$($version.Name)"
            New-Item -ItemType Directory -Path $noticePath -Force | Out-Null
            $files | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $noticePath }
        }
    }
}

$qtSbom = Join-Path $repo '.tools\Qt\6.8.3\msvc2022_64\sbom'
if (Test-Path -LiteralPath $qtSbom) {
    Copy-Item -LiteralPath $qtSbom -Destination (Join-Path $notices 'qt-6.8.3-sbom') -Recurse
}

@'
@echo off
setlocal
cd /d "%~dp0"
:: Block third-party Vulkan overlay crashers (such as FPS Monitor fpsmonvk64.dll and Medal)
set "DISABLE_LAYER=1"
set "DISABLE_VULKAN_MEDAL_OBS_CAPTURE=1"
set "VK_LOADER_LAYERS_DISABLE=*fpsmon*,VK_LAYER_RENDERDOC_Capture,~implicit~"
if not defined EDEN_NX2_ASYNC_DISCARD set "EDEN_NX2_ASYNC_DISCARD=1"
if not defined EDEN_NX2_SEM_FAST set "EDEN_NX2_SEM_FAST=1"
lichii.exe
'@ | Set-Content -LiteralPath (Join-Path $destination 'Launch-Hybrid-PGO.cmd') -Encoding ascii

@'
Local Fritchii + Lichii PGO-Optimized candidate. Read audit/README.md and audit/VERIFICATION.md.
Built with Clang 19.1.7 + ThinLTO + Profile-Guided Optimization (PGO) using representative gameplay profiles.
This package uses its adjacent user directory. Do not accept migration/import prompts.
'@ | Set-Content -LiteralPath (Join-Path $destination 'READ-ME-FIRST.txt') -Encoding utf8

$binary = Join-Path $destination 'lichii.exe'
$gitRev = (& git -C $repo rev-parse HEAD)
[ordered]@{
    source_commit = $gitRev;
    executable_sha256 = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash;
    pgo = $true;
    profile_source = 'Representative local gameplay';
    toolchain = 'clang-cl 19.1.7 / ThinLTO / PGO';
    linker_flags = '/OPT:REF,NOICF /opt:lldltojobs=12'
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destination 'build-manifest.json') -Encoding utf8

Write-Output "Successfully packaged PGO build to: $destination"
