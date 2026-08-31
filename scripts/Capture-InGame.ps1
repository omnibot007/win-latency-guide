<#
.SYNOPSIS
    Automatically captures PresentMon frame + latency data while Fortnite is running.
    Called by the LatencyLab-Boot task - you never run this manually.

.DESCRIPTION
    Waits for you to actually be in a match (lobby frames are meaningless), captures,
    then writes a summary line to the log so you can read results without opening a CSV.

    ANTI-CHEAT NOTE - READ THIS ONCE
    PresentMon is Intel's official tool. It does NOT inject into the game and does not
    read game memory; it consumes ETW (Event Tracing for Windows). However, Fortnite
    runs BOTH Easy Anti-Cheat and BattlEye, and BattlEye is documented to monitor ETW
    sessions. The risk is low but it is not zero.

    KILL SWITCH: create this file and capture is skipped permanently:
        C:\LatencyLab\NO_INGAME_CAPTURE

    If you would rather not run ETW tracing alongside anti-cheat at all, create that
    file now. Fortnite's own in-game "Latency Debug Stats" overlay gives you Game /
    Render / Total System Latency with zero tracing and zero risk - it is less precise
    but completely safe.

.PARAMETER DelaySeconds
    How long after Fortnite launch before capturing (time to get into a match).

.PARAMETER Seconds
    Capture duration.
#>
[CmdletBinding()]
param(
    [int]$DelaySeconds = 120,
    [int]$Seconds = 60,
    [string]$Stage = ''
)

$ErrorActionPreference = 'Continue'
$log = 'C:\LatencyLab\logs\boot.log'
function Log { param($m) "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))  [capture] $m" | Add-Content $log }

if (Test-Path 'C:\LatencyLab\NO_INGAME_CAPTURE') { Log 'skipped (kill switch present)'; return }

$GAME = 'FortniteClient-Win64-Shipping'
if (-not (Get-Process -Name $GAME -ErrorAction SilentlyContinue)) { Log 'game not running, aborting'; return }

Log "waiting ${DelaySeconds}s for you to get into a match..."
$waited = 0
while ($waited -lt $DelaySeconds) {
    Start-Sleep -Seconds 5; $waited += 5
    if (-not (Get-Process -Name $GAME -ErrorAction SilentlyContinue)) { Log 'game exited during wait, aborting'; return }
}

if (-not $Stage) { $Stage = 'ingame-' + (Get-Date -Format 'yyyyMMdd_HHmmss') }
$out = "C:\LatencyLab\results\$Stage"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$csv = Join-Path $out 'frames_raw.csv'

Log "capturing ${Seconds}s -> $Stage"
$pmArgs = @(
    '--process_name', "$GAME.exe",
    '--output_file',  $csv,
    '--timed',        $Seconds,
    '--terminate_after_timed',
    '--track_pc_latency',
    '--stop_existing_session',
    '--no_console_stats',
    '--qpc_time_ms'
)
$console = Join-Path $out 'frames_console.txt'
& 'C:\LatencyLab\tools\PresentMon.exe' @pmArgs 2>&1 | Out-String | Set-Content $console

if (-not (Test-Path $csv)) {
    Log 'NO CSV PRODUCED - EAC/BattlEye is very likely blocking ETW. See frames_console.txt'
    Log 'this is harmless; use Fortnite in-game Latency Debug Stats instead'
    return
}

# ---- summarise so results are readable from the log alone ----
try {
    Import-Module 'C:\LatencyLab\scripts\LatencyLab.psm1' -Force -ErrorAction Stop
    $stats = Get-LLFrameStats -CsvPath $csv -Stage $Stage
    $fps = $stats | Where-Object Metric -eq 'FPS'
    $ft  = $stats | Where-Object Metric -eq 'FrameTime'
    $pcl = $stats | Where-Object Metric -eq 'PCLatency'
    $c2p = $stats | Where-Object Metric -eq 'ClickToPhoton'
    $gpu = $stats | Where-Object Metric -eq 'GPUBusy'

    if ($fps) { Log ("FPS  avg {0}  1%low {1}  0.1%low {2}" -f $fps.Avg, $fps.P99, $fps.P999) }
    if ($ft)  { Log ("frametime avg {0}ms  p99 {1}ms  max {2}ms" -f $ft.Avg, $ft.P99, $ft.Max) }
    if ($pcl) { Log ("PC LATENCY avg {0}ms  p99 {1}ms  max {2}ms" -f $pcl.Avg, $pcl.P99, $pcl.Max) }
    if ($c2p) { Log ("click-to-photon avg {0}ms  p99 {1}ms" -f $c2p.Avg, $c2p.P99) }
    if ($gpu) { Log ("GPU busy avg {0}ms (GPU-bound if close to frametime)" -f $gpu.Avg) }
    if (-not $pcl) { Log 'no PC Latency column - Reflex markers may be off in-game (Video > Advanced > Latency Markers)' }
    Log "done -> $out"
} catch { Log "summary failed: $($_.Exception.Message)" }
