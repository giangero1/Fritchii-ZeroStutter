param([switch]$VerifyOnly)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path $PSScriptRoot -Parent
$games = Split-Path $workspace -Parent
$source = Join-Path $workspace 'portable-hybrid/user'
$target = Join-Path $games 'Lichii-117-PGO'
$snapshot = Join-Path $games 'Stutter-Tests/seed-profile'
$archive = Join-Path $workspace '.tools/stutter/lichii-117-pgo.zip'
$expected = '1d1d2aef20f73d2b426863dc9b203c6a2920e3a6882019afe6b34c74d79929ac'
if ($VerifyOnly) {
    if (!(Test-Path -LiteralPath (Join-Path $target 'READY.json'))) { throw 'Comparison not prepared.' }
    Get-Content -LiteralPath (Join-Path $target 'READY.json')
    return
}
if (Get-Process -Name lichii,eden-cli,eglantine -ErrorAction SilentlyContinue) {
    throw 'Close the emulator normally before taking a consistent save/config/cache snapshot. Nothing was copied.'
}
if ((Test-Path -LiteralPath $target) -or (Test-Path -LiteralPath $snapshot)) {
    throw 'Comparison or seed already exists. Refusing to overwrite test saves or the benchmark seed.'
}
if (!(Test-Path -LiteralPath $archive)) { throw 'Download build-117 lichii-windows-x86_64-pgo.zip into .tools/stutter first.' }
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
    throw 'Release archive SHA256 mismatch.'
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($archive)
try {
    foreach ($entry in $zip.Entries) {
        $dest = [IO.Path]::GetFullPath((Join-Path $target $entry.FullName))
        if (!$dest.StartsWith($target + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe archive entry.' }
        if ($entry.FullName -match '^(user|portable)/') { throw 'Release unexpectedly includes a user profile.' }
    }
} finally { $zip.Dispose() }
$folders = @('config','keys','nand','sdmc','load','cache','tas','post_presets','post_shaders','amiibo')
$before = @{}
foreach ($folder in $folders) {
    $path = Join-Path $source $folder
    if (!(Test-Path -LiteralPath $path)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $path -File -Recurse) {
        if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Source profile contains a linked file; review isolation manually.' }
        $before[$file.FullName.Substring($source.Length + 1)] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    if (Get-ChildItem -LiteralPath $path -Directory -Recurse | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) {
        throw 'Source profile contains a linked directory; review isolation manually.'
    }
}
New-Item -ItemType Directory -Path $target,$snapshot -Force | Out-Null
Expand-Archive -LiteralPath $archive -DestinationPath $target
foreach ($folder in $folders) {
    $path = Join-Path $source $folder
    if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination $snapshot -Recurse }
}
$user = Join-Path $target 'user'
New-Item -ItemType Directory -Path $user -Force | Out-Null
Get-ChildItem -LiteralPath $snapshot | Copy-Item -Destination $user -Recurse
foreach ($relative in $before.Keys) {
    $copy = Join-Path $snapshot $relative
    if ((Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash -ne $before[$relative]) { throw 'Snapshot verification failed.' }
    if ((Get-FileHash -LiteralPath (Join-Path $source $relative) -Algorithm SHA256).Hash -ne $before[$relative]) { throw 'Source changed while copying; do not use this snapshot.' }
}
# Rewrite copied INIs only. QSettings stores slash-separated absolute paths.
$oldRoot = $source.Replace('\','/')
$newRoot = $user.Replace('\','/')
$utf8 = New-Object System.Text.UTF8Encoding($false)
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $user 'config') -Filter '*.ini' -File -Recurse) {
    $text = [IO.File]::ReadAllText($file.FullName)
    $text = $text.Replace($oldRoot,$newRoot).Replace($source,$user)
    # Explicitly pin mutable storage even if the source used a custom external location.
    $paths = @{nand_directory='nand';sdmc_directory='sdmc';load_directory='load';dump_directory='dump';tas_directory='tas';save_directory='nand'}
    foreach ($key in $paths.Keys) {
        $value = ($user + '/' + $paths[$key]).Replace('\','/')
        $text = [regex]::Replace($text, '(?m)^' + $key + '=.*$', ($key + '=' + $value))
        $text = [regex]::Replace($text, '(?m)^' + $key + '\\default=.*$', ($key + '\default=false'))
    }
    $text = [regex]::Replace($text, '(?m)^(Screenshots\\)?screenshot_path=.*$', ('$1screenshot_path=' + $newRoot + '/screenshots'))
    $text = [regex]::Replace($text, '(?m)^nvidia_dlss=.*$', 'nvidia_dlss=false')
    $text = [regex]::Replace($text, '(?m)^nvidia_dlss\\default=.*$', 'nvidia_dlss\default=false')
    $text = [regex]::Replace($text, '(?m)^check_for_updates=.*$', 'check_for_updates=false')
    $text = [regex]::Replace($text, '(?m)^check_for_updates\\default=.*$', 'check_for_updates\default=false')
    [IO.File]::WriteAllText($file.FullName,$text,$utf8)
}
# Source namespaces stay intact; do not rename/cross-load Fritchii pipeline binaries.
@{ release='build-117'; source_commit='89440b29a90708c0fefc126b2bd8c7a64a996bdd'; archive_sha256=$expected; executable_sha256=(Get-FileHash -LiteralPath (Join-Path $target 'lichii.exe') -Algorithm SHA256).Hash; prepared_utc=[DateTime]::UtcNow.ToString('o'); snapshot_files=$before.Count; source_unchanged=$true; dlss_enabled=$false; cache_note='Copied seed includes Fritchii cache namespaces. Stock may need its own warm-up; no cache filenames were converted.' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $target 'READY.json') -Encoding UTF8
$before | ConvertTo-Json | Set-Content -LiteralPath (Join-Path (Split-Path $snapshot -Parent) 'seed-hashes-private.json') -Encoding UTF8
& (Join-Path $PSScriptRoot 'repair-stock117-settings.ps1')
Write-Host 'Build 117 PGO is prepared. No emulator was launched; original settings, saves and caches are unchanged.'
