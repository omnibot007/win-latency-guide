<#
.SYNOPSIS
    Samples everything that decides who wins a build race, while you play a real match.

.WHY THIS DESIGN
    It does NOT use PresentMon/ETW. Fortnite runs EAC *and* BattlEye, and BattlEye is
    documented to monitor ETW sessions. Every metric here comes from ordinary Windows
    performance counters and ICMP - nothing touches the game process, reads its memory,
    or starts a trace. Zero anti-cheat surface.

    What actually decides a contested wall grab, in order:
      1. Network latency + jitter to the server  (server is authoritative)
      2. Downlink saturation  (queues upstream -> huge spikes)
      3. Input-to-photon latency on your end     (FPS, Reflex, input path)
    This measures 1 and 2 directly, and 3's system-side inputs.

.USAGE
    Started automatically when Fortnite launches, or run manually:
      powershell -ExecutionPolicy Bypass -File C:\LatencyLab\scripts\Match-Benchmark.ps1
    Ctrl+C to stop early. Summary prints at the end and is written to the log.
#>
[CmdletBinding()]
param(
    [int]$Seconds  = 600,   # how long to sample
    [int]$Interval = 2      # seconds between samples
)

$ErrorActionPreference = 'Continue'
$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$outDir  = 'C:\LatencyLab\results\match'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$csv = Join-Path $outDir "match-$stamp.csv"
$log = Join-Path $outDir "match-$stamp.log"

function Log { param($m) $line = "$((Get-Date).ToString('HH:mm:ss'))  $m"; Add-Content $log $line; Write-Host $line }

Log "=== MATCH BENCHMARK START (${Seconds}s @ ${Interval}s) ==="
Log "csv: $csv"

# Ping target: Epic blocks ICMP, so use a stable low-latency anchor to measure
# YOUR line quality. Absolute value is less important than jitter and spikes.
$pingTarget = '1.1.1.1'

# Detect the active adapter rather than assuming it is called "Ethernet".
# Hardcoding the name meant Get-NetAdapterStatistics returned null on Wi-Fi or
# any renamed NIC, and throughput silently reported 0 Mbps forever - which is
# worse than an error, because the saturation numbers looked fine.
$nic = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
       Where-Object { $_.Status -eq 'Up' } |
       Sort-Object -Property @{ Expression = { $_.LinkSpeed } } -Descending |
       Select-Object -First 1
if (-not $nic) {
    Log 'WARNING: no active physical network adapter found - throughput will read 0'
} else {
    Log "network adapter: $($nic.Name)  ($($nic.InterfaceDescription), $($nic.LinkSpeed))"
}
$nicName = $nic.Name

$samples = @()
$rxLast  = (Get-NetAdapterStatistics -Name $nicName -EA SilentlyContinue).ReceivedBytes
$txLast  = (Get-NetAdapterStatistics -Name $nicName -EA SilentlyContinue).SentBytes
$tLast   = Get-Date
$end     = (Get-Date).AddSeconds($Seconds)
$n       = 0

while ((Get-Date) -lt $end) {
    $now = Get-Date

    # --- network throughput ---
    $st   = Get-NetAdapterStatistics -Name $nicName -EA SilentlyContinue
    $secs = ($now - $tLast).TotalSeconds
    $down = 0; $up = 0
    if ($secs -gt 0 -and $st) {
        $down = [math]::Round((($st.ReceivedBytes - $rxLast) * 8 / $secs / 1MB), 1)
        $up   = [math]::Round((($st.SentBytes    - $txLast) * 8 / $secs / 1MB), 1)
    }
    if ($st) { $rxLast = $st.ReceivedBytes; $txLast = $st.SentBytes }
    $tLast = $now

    # --- latency ---
    $ping = $null
    try {
        $r = Test-Connection -ComputerName $pingTarget -Count 1 -EA Stop
        $ping = $r.ResponseTime
    } catch { $ping = -1 }

    # --- cpu / dpc ---
    $cpu = 0; $dpc = 0
    try { $cpu = [math]::Round((Get-Counter '\Processor(_Total)\% Processor Time' -EA Stop).CounterSamples[0].CookedValue,1) } catch {}
    try { $dpc = [math]::Round((Get-Counter '\Processor(_Total)\% DPC Time'       -EA Stop).CounterSamples[0].CookedValue,3) } catch {}

    # --- game process ---
    $fn = Get-Process FortniteClient-Win64-Shipping -EA SilentlyContinue
    $prio = ''; $wsGB = 0; $inGame = 0
    if ($fn) {
        $inGame = 1
        $prio = "$($fn.PriorityClass)"
        $wsGB = [math]::Round($fn.WorkingSet64/1GB,2)
    }

    # --- parked cores (should stay 0) ---
    $parked = 0
    try {
        $parked = @((Get-Counter '\Processor Information(*)\Parking Status' -EA Stop).CounterSamples |
                    Where-Object { $_.InstanceName -notmatch '_Total' -and $_.CookedValue -eq 1 }).Count
    } catch {}

    $samples += [PSCustomObject]@{
        Time=$now.ToString('HH:mm:ss'); PingMs=$ping; DownMbps=$down; UpMbps=$up
        CpuPct=$cpu; DpcPct=$dpc; ParkedCores=$parked; FortniteRunning=$inGame
        Priority=$prio; WorkingSetGB=$wsGB
    }

    $n++
    if ($n % 15 -eq 0) { Log "  t+$([int]((Get-Date)-$tLast.AddSeconds(-$secs)).TotalSeconds)s  ping=${ping}ms down=${down}Mbps cpu=${cpu}% dpc=${dpc}% parked=$parked" }

    Start-Sleep -Seconds $Interval
}

$samples | Export-Csv -Path $csv -NoTypeInformation

# ---------------- SUMMARY ----------------
$valid = @($samples | Where-Object { $_.PingMs -ge 0 })
$pings = @($valid | Select-Object -ExpandProperty PingMs)
Log ''
Log '=== SUMMARY ==='
if ($pings.Count -gt 0) {
    $avg = [math]::Round(($pings | Measure-Object -Average).Average,1)
    $mn  = ($pings | Measure-Object -Minimum).Minimum
    $mx  = ($pings | Measure-Object -Maximum).Maximum
    $sorted = $pings | Sort-Object
    $p95 = $sorted[[math]::Floor($sorted.Count * 0.95)]
    Log "  PING   avg=${avg}ms  min=${mn}ms  max=${mx}ms  p95=${p95}ms  JITTER=$($mx-$mn)ms"
    $spikes = @($pings | Where-Object { $_ -gt ($avg * 3) }).Count
    Log "  SPIKES >3x average: $spikes of $($pings.Count) samples"
}
$dn = @($samples | Select-Object -ExpandProperty DownMbps)
if ($dn.Count) {
    Log "  DOWNLINK avg=$([math]::Round(($dn|Measure-Object -Average).Average,1))Mbps  peak=$(($dn|Measure-Object -Maximum).Maximum)Mbps"
    $sat = @($dn | Where-Object { $_ -gt 100 }).Count
    Log "  SATURATED (>100Mbps) in $sat of $($dn.Count) samples  <- each one risks a ping spike"
}
$cp = @($samples | Select-Object -ExpandProperty CpuPct)
if ($cp.Count) { Log "  CPU    avg=$([math]::Round(($cp|Measure-Object -Average).Average,1))%  peak=$(($cp|Measure-Object -Maximum).Maximum)%" }
$dp = @($samples | Select-Object -ExpandProperty DpcPct)
if ($dp.Count) { Log "  DPC    avg=$([math]::Round(($dp|Measure-Object -Average).Average,3))%  peak=$(($dp|Measure-Object -Maximum).Maximum)%" }
$pk = @($samples | Select-Object -ExpandProperty ParkedCores)
if ($pk.Count) { Log "  PARKED CORES peak=$(($pk|Measure-Object -Maximum).Maximum)  (must stay 0)" }
$pr = @($samples | Where-Object { $_.Priority } | Select-Object -ExpandProperty Priority -Unique)
if ($pr) { Log "  FORTNITE PRIORITY seen: $($pr -join ', ')  (want High)" }

Log ''
Log "Send Claude this file: $log"
