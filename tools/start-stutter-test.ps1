param(
    [ValidateSet('Baseline','Workers','Stock117')][string]$Mode = 'Workers',
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path $PSScriptRoot -Parent
$games = Split-Path $workspace -Parent
$package = if ($Mode -ne 'Stock117') { Join-Path $workspace 'portable-hybrid' } else { Join-Path $games 'Lichii-117-PGO' }
$exe = Join-Path $package 'lichii.exe'
if (!(Test-Path -LiteralPath $exe) -or !(Test-Path -LiteralPath (Join-Path $package 'user/config/qt-config.ini'))) {
    throw 'Test package/profile is not ready. Use Play-Hybrid.cmd as fallback.'
}
if ($Mode -eq 'Stock117') {
    $manifest = Get-Content -LiteralPath (Join-Path $package 'READY.json') -Raw | ConvertFrom-Json
    if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne $manifest.executable_sha256) {
        throw 'Stock comparison executable changed since preparation. Do not compare it as the pinned build 117.'
    }
    $userRoot = (Join-Path $package 'user').Replace('\','/') + '/'
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $package 'user/config') -Filter '*.ini' -File -Recurse) {
        foreach ($line in [IO.File]::ReadAllLines($file.FullName)) {
            if ($line -match '^(nand_directory|sdmc_directory|save_directory|load_directory|dump_directory|tas_directory)=(.+)$') {
                if (!$Matches[2].Replace('\','/').StartsWith($userRoot,[StringComparison]::OrdinalIgnoreCase)) {
                    throw 'A copied profile storage path points outside the test profile. Refusing to launch.'
                }
            }
        }
    }
}
# Match the existing launcher's process-local overlay and timing policy.
$env:DISABLE_LAYER = '1'
$env:DISABLE_VULKAN_MEDAL_OBS_CAPTURE = '1'
$env:VK_LOADER_LAYERS_DISABLE = '*fpsmon*,VK_LAYER_RENDERDOC_Capture,~implicit~'
if (!$env:EDEN_NX2_ASYNC_DISCARD) { $env:EDEN_NX2_ASYNC_DISCARD = '1' }
if (!$env:EDEN_NX2_SEM_FAST) { $env:EDEN_NX2_SEM_FAST = '1' }
if ($Mode -eq 'Workers') {
    # OFF takes precedence in this implementation. Preserve every unrelated opt-in/out.
    $on = @($env:EDEN_NX2_PERF_ON -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne 'async_pipelines' })
    $off = @($env:EDEN_NX2_PERF_OFF -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne 'async_pipelines' })
    if ($env:EDEN_NX2_PERF_OPT -and $env:EDEN_NX2_PERF_OPT.StartsWith('0')) {
        throw 'Inherited EDEN_NX2_PERF_OPT=0 disables all performance paths. Use a normal terminal for this comparison.'
    }
    $env:EDEN_NX2_PERF_ON = (@($on) + 'async_pipelines') -join ','
    $env:EDEN_NX2_PERF_OFF = $off -join ','
    if ($env:EDEN_NX2_PERF_VERIFY -eq '1') {
        throw 'Verification mode duplicates shader work. Unset EDEN_NX2_PERF_VERIFY before timing this test.'
    }
}
if ($DryRun) {
    [pscustomobject]@{ Mode=$Mode; Executable=$exe; PortableProfile=(Join-Path $package 'user'); PerfOn=$env:EDEN_NX2_PERF_ON; PerfOff=$env:EDEN_NX2_PERF_OFF; Started=$false }
    return
}
if (Get-Process -Name lichii,eden-cli,eglantine -ErrorAction SilentlyContinue) {
    throw 'An emulator is already running. Close it normally before opening a test; no process was stopped.'
}
if ($Mode -eq 'Stock117') {
    & (Join-Path $PSScriptRoot 'repair-stock117-settings.ps1')
}
$reportRoot = Join-Path $games 'Stutter-Tests'
$run = Join-Path $reportRoot ($Mode + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $run -Force | Out-Null
@{ mode=$Mode; started_utc=[DateTime]::UtcNow.ToString('o'); executable_sha256=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash; perf_on=$env:EDEN_NX2_PERF_ON; perf_off=$env:EDEN_NX2_PERF_OFF; async_discard=$env:EDEN_NX2_ASYNC_DISCARD; sem_fast=$env:EDEN_NX2_SEM_FAST } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'run.json') -Encoding UTF8
Write-Host 'Let startup shader compilation finish. Load your save and test the same area, then revisit it.'
Write-Host 'The current Play-Hybrid.cmd remains your fallback.'
$process = Start-Process -FilePath $exe -WorkingDirectory $package -PassThru
try { $process.PriorityClass = 'High' } catch { Write-Warning 'Could not match High process priority.' }
$process.WaitForExit()
foreach ($name in @('eden_log.txt','eden_log.txt.old.txt')) {
    $log = Join-Path $package ('user/log/' + $name)
    if (Test-Path -LiteralPath $log) { Copy-Item -LiteralPath $log -Destination (Join-Path $run $name) }
}
$python = Get-Command python.exe -ErrorAction SilentlyContinue
$savedLog = Join-Path $run 'eden_log.txt'
if ($python -and (Test-Path -LiteralPath $savedLog)) {
    & $python.Source (Join-Path $PSScriptRoot 'stutter_report.py') $savedLog --format json --output (Join-Path $run 'summary.json')
    & $python.Source (Join-Path $PSScriptRoot 'stutter_report.py') $savedLog --output (Join-Path $run 'summary.txt')
}
Write-Host ('Test logs saved locally: ' + $run)
Write-Host 'Test-build saves are independent. Continue your main playthrough with the original hybrid unless the comparison wins.'
