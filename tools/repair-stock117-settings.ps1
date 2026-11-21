param([switch]$DryRun, [switch]$SelfTest)
$ErrorActionPreference = 'Stop'
# QSettings default=true ignores the serialized value and selects this build's default.
# Explicit values are required when comparing builds whose defaults differ.
$pins = [ordered]@{
    gpu_accuracy='0'; use_asynchronous_shaders='true'; async_presentation='true'
    use_asynchronous_gpu_emulation='true'; use_multi_core='true'; memory_layout_mode='2'
    resolution_setup='3'; anti_aliasing='1'; scaling_filter='5'
    use_disk_shader_cache='true'; use_vulkan_driver_pipeline_cache='true'
    nvidia_dlss='false'; game_dlss_network='false'; oot_30fps='false'
}
function Convert-TestSettings([string]$Text) {
    foreach ($key in $pins.Keys) {
        $pattern = '(?m)^' + [regex]::Escape($key) + '=.*$'
        $defaultPattern = '(?m)^' + [regex]::Escape($key + '\default') + '=.*$'
        if (![regex]::IsMatch($Text,$pattern) -or ![regex]::IsMatch($Text,$defaultPattern)) {
            throw ('Expected comparison setting missing: ' + $key)
        }
        $Text = [regex]::Replace($Text,$pattern,($key + '=' + $pins[$key]))
        $Text = [regex]::Replace($Text,$defaultPattern,($key + '\default=false'))
    }
    return $Text
}
if ($SelfTest) {
    $sample = "[Renderer]`r`n"
    foreach ($key in $pins.Keys) { $sample += "$key=old`r`n$key\default=true`r`n" }
    $sample += "unrelated=value`r`nunrelated\default=true`r`n"
    $fixed = Convert-TestSettings $sample
    foreach ($key in $pins.Keys) {
        if (!$fixed.Contains($key + '=' + $pins[$key]) -or !$fixed.Contains($key + '\default=false')) { throw 'Pin test failed.' }
    }
    if (!$fixed.Contains("unrelated=value`r`nunrelated\default=true")) { throw 'Unrelated settings changed.' }
    if ((Convert-TestSettings $fixed) -ne $fixed) { throw 'Repair is not idempotent.' }
    try { $null = Convert-TestSettings 'missing=keys'; throw 'Missing-setting test failed.' } catch { if ($_.Exception.Message -eq 'Missing-setting test failed.') { throw } }
    Write-Host 'Comparison setting repair: pins, unrelated preservation, idempotence and missing-key checks PASS.'
    return
}
$games = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$package = Join-Path $games 'Lichii-117-PGO'
$marker = Join-Path $package 'stutter-settings-v2.json'
if (Test-Path -LiteralPath $marker) { Write-Host 'Explicit comparison settings already applied.'; return }
$config = Join-Path $package 'user/config/qt-config.ini'
$original = [IO.File]::ReadAllText($config)
$fixed = Convert-TestSettings $original
if ($DryRun) { Write-Host 'Pending: explicit Low GPU accuracy, async shaders/presentation, 1x FXAA, cache on, 60 FPS, saved 8GB memory selector. No file changed.'; return }
if (Get-Process -Name lichii,eden-cli,eglantine -ErrorAction SilentlyContinue) {
    throw 'Close the emulator normally first. Active configuration was not changed.'
}
$backup = $config + '.before-stutter-settings-v2-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.bak'
Copy-Item -LiteralPath $config -Destination $backup
[IO.File]::WriteAllText($config,$fixed,(New-Object Text.UTF8Encoding($false)))
@{ applied_utc=[DateTime]::UtcNow.ToString('o'); reason='Copied default=true flags selected different defaults in stock build 117'; explicit_settings=$pins } | ConvertTo-Json | Set-Content -LiteralPath $marker -Encoding UTF8
Write-Host 'Corrected isolated comparison settings. Original hybrid profile and all saves/caches are untouched.'
