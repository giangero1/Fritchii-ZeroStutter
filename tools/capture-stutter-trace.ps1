param([ValidateRange(10,120)][int]$Seconds=90, [switch]$WithCpuTrace)
$ErrorActionPreference = 'Stop'
$processes = @(Get-Process -Name lichii,eden-cli,eglantine -ErrorAction SilentlyContinue)
if ($processes.Count -ne 1) { throw 'Run exactly one emulator first. This tool does not launch or stop games.' }
$targetProcess = $processes[0]
$games = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$folder = Join-Path $games ('Stutter-Tests/trace-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$instance = 'HybridStutter-' + [guid]::NewGuid().ToString('N')
$recording = $false
$stopExitCode = $null
@{ instance=$instance; process_id=$targetProcess.Id; started_utc=[DateTime]::UtcNow.ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder 'session.json') -Encoding UTF8
$wpr = Get-Command wpr.exe -ErrorAction SilentlyContinue
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($WithCpuTrace -and $wpr -and $admin) {
    & $wpr.Source -start GeneralProfile -filemode -instancename $instance
    $recording = $LASTEXITCODE -eq 0
    if (!$recording) { Write-Warning 'CPU trace did not start; no existing trace will be stopped.' }
} elseif ($WithCpuTrace) {
    Write-Warning 'CPU stacks require running this capture command as administrator. Usage counters will still be recorded.'
}
$nvidia = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
$rows = New-Object System.Collections.Generic.List[object]
$timer = [Diagnostics.Stopwatch]::StartNew()
Write-Host "Recording up to $Seconds seconds. Switch to the game and cross the problem area now."
try {
    while ($timer.Elapsed.TotalSeconds -lt $Seconds) {
        $targetProcess.Refresh()
        if ($targetProcess.HasExited) { break }
        $io = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -Filter "IDProcess=$($targetProcess.Id)" -ErrorAction SilentlyContinue
        $memory = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction SilentlyContinue
        $gpu = $null
        if ($nvidia) { $gpu = (& $nvidia.Source --query-gpu=memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits 2>$null | Select-Object -First 1) }
        $parts = @($gpu -split ',' | ForEach-Object { $_.Trim() })
        $rows.Add([pscustomobject]@{
            utc=[DateTime]::UtcNow.ToString('o'); elapsed_s=[Math]::Round($timer.Elapsed.TotalSeconds,3)
            cpu_total_s=$targetProcess.TotalProcessorTime.TotalSeconds
            working_set_bytes=$targetProcess.WorkingSet64; private_bytes=$targetProcess.PrivateMemorySize64
            process_io_read_bytes_s=$io.IOReadBytesPersec; process_page_faults_s=$io.PageFaultsPersec
            system_page_reads_s=$memory.PageReadsPersec
            gpu_total_used_mib=$(if ($parts.Count -ge 3) {$parts[0]} else {$null})
            gpu_capacity_mib=$(if ($parts.Count -ge 3) {$parts[1]} else {$null})
            gpu_utilization_percent=$(if ($parts.Count -ge 3) {$parts[2]} else {$null})
        })
        Start-Sleep -Milliseconds 1000
    }
} finally {
    $rows | Export-Csv -LiteralPath (Join-Path $folder 'usage.csv') -NoTypeInformation
    $trace = Join-Path $folder 'cpu-disk-memory.etl'
    if ($recording) {
        & $wpr.Source -stop $trace -instancename $instance
        $stopExitCode = $LASTEXITCODE
        if ($stopExitCode -ne 0) { Write-Warning 'WPR did not save a complete trace. Usage counters remain available; do not infer CPU stacks from them.' }
    }
    @{
        utc_end=[DateTime]::UtcNow.ToString('o'); samples=$rows.Count; cpu_trace_started=$recording
        cpu_trace_saved=($recording -and $stopExitCode -eq 0 -and (Test-Path -LiteralPath $trace)); wpr_stop_exit_code=$stopExitCode; instance=$instance
        limitations='One-second usage samples, not frame times. Process page faults include soft faults. System page reads are not attributed to this process. NVIDIA memory is whole-GPU usage/capacity, not per-process allocation or DXGI budget. ETL stays local.'
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder 'capture.json') -Encoding UTF8
    Write-Host ('Local capture saved: ' + $folder)
}
