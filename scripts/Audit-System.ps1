<#
.SYNOPSIS
    READ-ONLY audit. Detects your hardware, reports current tweak state, and
    tells you which tweaks in this repo apply to YOUR system and which do not.

.WHY THIS EXISTS
    The tweaks in this repo were measured on one specific rig. Some are
    universal (svchost threshold, core parking). Many are hardware-specific
    and will do nothing - or harm - on different hardware.

    Run this FIRST. It changes nothing. It tells you what applies to you.

.USAGE
    powershell -ExecutionPolicy Bypass -File .\scripts\Audit-System.ps1

    Elevated gives a fuller report (boot config, Secure Boot), but it works
    unelevated and will say which checks it had to skip.
#>
[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = 'SilentlyContinue'
$report = [ordered]@{}

function Section($t) { Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Cyan }
function Line($l, $v, $note) {
    if ($note) { Write-Host ("  {0,-32} {1,-22} {2}" -f $l, $v, $note) }
    else       { Write-Host ("  {0,-32} {1}" -f $l, $v) }
}
function Verdict($t, $c) {
    switch ($c) {
        'ok'   { Write-Host "  [OK]    $t" -ForegroundColor Green }
        'warn' { Write-Host "  [CHECK] $t" -ForegroundColor Yellow }
        'bad'  { Write-Host "  [ISSUE] $t" -ForegroundColor Red }
        'na'   { Write-Host "  [N/A]   $t" -ForegroundColor DarkGray }
    }
}
function G($p, $n) {
    $v = $null
    try { $v = (Get-ItemProperty -Path $p -Name $n -ErrorAction Stop).$n } catch {}
    return $v
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
$elevated = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host ""
Write-Host "################################################################" -ForegroundColor White
Write-Host "  SYSTEM AUDIT - read-only, changes nothing" -ForegroundColor White
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm')   Elevated: $elevated" -ForegroundColor Gray
Write-Host "################################################################" -ForegroundColor White

# ---------------------------------------------------------------- HARDWARE
Section 'HARDWARE'
$cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
$cs   = Get-CimInstance Win32_ComputerSystem
$os   = Get-CimInstance Win32_OperatingSystem
$gpus = @(Get-CimInstance Win32_VideoController)
$ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
$chassis = (Get-CimInstance Win32_SystemEnclosure).ChassisTypes -join ','
$isLaptop = ($chassis -match '9|10|14') -or [bool](Get-CimInstance Win32_Battery)

Line 'CPU'        $cpu.Name
Line 'Cores'      "$($cpu.NumberOfCores) physical / $($cpu.NumberOfLogicalProcessors) logical"
Line 'RAM'        "$ramGB GB"
Line 'System'     "$($cs.Manufacturer) $($cs.Model)"
Line 'Form factor' $(if ($isLaptop) { 'LAPTOP' } else { 'DESKTOP' })
Line 'OS'         "$($os.Caption) $($os.BuildNumber)"
foreach ($g in $gpus) { Line 'GPU' "$($g.Name)  driver $($g.DriverVersion)" }

# Hybrid detection: logical > physical*2 means E-cores present (no HT on E-cores)
$hybrid = $cpu.NumberOfLogicalProcessors -lt ($cpu.NumberOfCores * 2)
$report.hybrid = $hybrid
$report.ramGB  = $ramGB
$report.laptop = $isLaptop

Section 'WHAT APPLIES TO YOU'
if ($hybrid) {
    Verdict "Hybrid CPU detected (P-cores + E-cores)" 'ok'
    Write-Host "          -> the per-efficiency-class core parking fix APPLIES to you" -ForegroundColor Gray
    Write-Host "          -> this is the tweak almost every guide gets wrong" -ForegroundColor Gray
} else {
    Verdict "Non-hybrid CPU - only ONE core parking class exists" 'na'
    Write-Host "          -> standard CPMINCORES is enough; the Class 1 fix does not apply" -ForegroundColor Gray
}
if ($isLaptop) {
    Verdict "LAPTOP - several tweaks in this repo are desktop-oriented" 'warn'
    Write-Host "          -> C-states OFF will hurt battery and thermals badly" -ForegroundColor Gray
    Write-Host "          -> do NOT disable hibernation if you use sleep/hibernate" -ForegroundColor Gray
    Write-Host "          -> Ultimate Performance plan may not be exposed" -ForegroundColor Gray
}
if ($ramGB -lt 16) {
    Verdict "Under 16GB RAM - do not disable MemoryCompression" 'warn'
}
$nv = @($gpus | Where-Object { $_.Name -match 'NVIDIA' })
if (-not $nv) { Verdict "No NVIDIA GPU - all NVIDIA registry tweaks are N/A" 'na' }

# ---------------------------------------------------- THE CRITICAL ONE
Section 'CRITICAL: svchost split threshold'
$svcSplit = G 'HKLM:\SYSTEM\CurrentControlSet\Control' 'SvcHostSplitThresholdInKB'
$svcCount = (Get-Process svchost).Count
$ramKB = [int64]($ramGB * 1024 * 1024)
Line 'SvcHostSplitThresholdInKB' $(if ($null -eq $svcSplit) { '<not set - stock>' } else { $svcSplit })
Line 'svchost.exe instances'     $svcCount
if ($null -ne $svcSplit -and $svcSplit -ge $ramKB) {
    Verdict "THRESHOLD EXCEEDS YOUR RAM - services are being FORCED into shared processes" 'bad'
    Write-Host "          This can cause CRITICAL_PROCESS_DIED (0xEF) boot loops." -ForegroundColor Red
    Write-Host "          Fix: set it to 3670016. See docs/BSOD-CRITICAL_PROCESS_DIED.md" -ForegroundColor Red
} elseif ($svcCount -lt 40) {
    Verdict "Only $svcCount svchost processes - unusually low, services may be grouped" 'warn'
} else {
    Verdict "Services are split normally ($svcCount processes)" 'ok'
}

# Are critical services sharing a host with risky ones?
$crit = Get-CimInstance Win32_Service | Where-Object {
    $_.State -eq 'Running' -and $_.Name -in @('DcomLaunch','LSM','Power','PlugPlay','DeviceInstall','RpcSs')
}
$grouped = $crit | Group-Object ProcessId | Sort-Object Count -Descending | Select-Object -First 1
if ($grouped -and $grouped.Count -ge 6) {
    Verdict "$($grouped.Count) critical services share PID $($grouped.Name) - risky grouping" 'bad'
    Write-Host "          $(($grouped.Group.Name) -join ', ')" -ForegroundColor Red
} else {
    Verdict "Critical services are adequately separated" 'ok'
}

# ---------------------------------------------------------------- PARKING
Section 'CORE PARKING'
$parked = @((Get-Counter '\Processor Information(*)\Parking Status').CounterSamples |
            Where-Object { $_.InstanceName -notmatch '_Total' -and $_.CookedValue -eq 1 })
Line 'Cores parked right now' "$($parked.Count) of $($cpu.NumberOfLogicalProcessors)"
if ($parked.Count -gt 0) {
    Verdict "$($parked.Count) cores parked" 'warn'
    Write-Host "          parked: $(($parked.InstanceName | Sort-Object) -join ', ')" -ForegroundColor Gray
    if ($hybrid) {
        Write-Host "          On hybrid CPUs check BOTH classes - Class 1 (P-cores) is HIDDEN" -ForegroundColor Yellow
    }
} else {
    Verdict "No cores parked" 'ok'
}

$sub = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00'
foreach ($c in @(
    @{ n='Class 0 min cores (E-cores)'; g='0cc5b647-c1df-4637-891a-dec35c318583' },
    @{ n='Class 1 min cores (P-cores)'; g='0cc5b647-c1df-4637-891a-dec35c318584' }
)) {
    $k = Join-Path $sub $c.g
    if (Test-Path $k) {
        $attr = G $k 'Attributes'
        Line $c.n $(if ($attr -eq 2) { 'visible' } else { "HIDDEN (Attributes=$attr)" })
    }
}

# ---------------------------------------------------------------- TIMER
Section 'TIMER RESOLUTION'
try {
    Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public class TQ { [DllImport("ntdll.dll")] public static extern int NtQueryTimerResolution(out uint a, out uint b, out uint c); }
"@ -ErrorAction Stop
    $mn = 0; $mx = 0; $cur = 0
    [void][TQ]::NtQueryTimerResolution([ref]$mn, [ref]$mx, [ref]$cur)
    Line 'Current resolution' "$([math]::Round($cur/10000.0,4)) ms"
    Line 'Finest available'   "$([math]::Round($mx/10000.0,4)) ms"
    if ($cur -le 6000) { Verdict "Timer resolution is fine-grained" 'ok' }
    else { Verdict "Timer at $([math]::Round($cur/10000.0,2))ms - consider SetTimerResolution" 'warn' }
} catch { Line 'Timer query' 'unavailable' }

# ---------------------------------------------------------------- LATENCY
Section 'DPC / INTERRUPT LATENCY (5s sample)'
$dpc = @{}
$s = Get-Counter '\Processor(*)\% DPC Time' -SampleInterval 1 -MaxSamples 5
foreach ($smp in $s) { foreach ($c in $smp.CounterSamples) {
    if ($c.InstanceName -ne '_total') {
        if (-not $dpc.ContainsKey($c.InstanceName)) { $dpc[$c.InstanceName] = @() }
        $dpc[$c.InstanceName] += $c.CookedValue
    }
}}
$hot = $dpc.GetEnumerator() | ForEach-Object {
    [PSCustomObject]@{ CPU = $_.Key; Avg = [math]::Round(($_.Value | Measure-Object -Average).Average, 3) }
} | Sort-Object Avg -Descending | Select-Object -First 3
foreach ($h in $hot) { Line "CPU $($h.CPU) avg DPC" "$($h.Avg)%" }
$worst = ($hot | Select-Object -First 1).Avg
if ($worst -lt 1)      { Verdict "DPC latency is low - no interrupt contention" 'ok' }
elseif ($worst -lt 3)  { Verdict "DPC moderate - acceptable" 'warn' }
else { Verdict "DPC HIGH ($worst%) - check drivers with LatencyMon" 'bad' }

# ---------------------------------------------------------------- NETWORK
Section 'NETWORK'
$nic = Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | Select-Object -First 1
if ($nic) {
    Line 'Adapter' "$($nic.InterfaceDescription)"
    Line 'Link speed' $nic.LinkSpeed
    $props = Get-NetAdapterAdvancedProperty -Name $nic.Name |
             Where-Object { $_.DisplayName -match 'Interrupt Moderation$|Flow Control|Energy|Green' }
    foreach ($p in $props) { Line "  $($p.DisplayName)" $p.DisplayValue }
    $im = $props | Where-Object { $_.DisplayName -eq 'Interrupt Moderation' }
    if ($im -and $im.DisplayValue -match 'Disabled') { Verdict "Interrupt moderation off - lower DPC" 'ok' }
    elseif ($im) { Verdict "Interrupt moderation ON - disabling can reduce latency" 'warn' }
    $t1323 = G 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'Tcp1323Opts'
    if ($t1323 -eq 0) { Verdict "Tcp1323Opts=0 DISABLES TCP window scaling - remove it" 'bad' }
}

# ---------------------------------------------------------------- STABILITY
Section 'STABILITY HISTORY'
$bc = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WER-SystemErrorReporting'} -MaxEvents 3
if ($bc) {
    foreach ($b in $bc) {
        $code = if ($b.Message -match '(0x[0-9a-f]{8})') { $matches[1] } else { '?' }
        Line $b.TimeCreated.ToString('yyyy-MM-dd HH:mm') "bugcheck $code"
    }
    if ($bc[0].Message -match '0x000000ef') {
        Verdict "Most recent crash was CRITICAL_PROCESS_DIED - read docs/BSOD-*.md" 'bad'
    }
} else { Verdict "No bugchecks recorded" 'ok' }

$whea = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'} -MaxEvents 3
if ($whea) { Verdict "WHEA hardware errors present - do NOT disable C-states" 'bad' }
else       { Verdict "No WHEA errors - CPU is stable" 'ok' }

# ---------------------------------------------------------------- ELEVATED
Section 'ELEVATED-ONLY CHECKS'
if ($elevated) {
    try { Line 'Secure Boot' "$(Confirm-SecureBootUEFI)" } catch { Line 'Secure Boot' 'unreadable' }
    $bcd = bcdedit /enum "{current}" | Out-String
    foreach ($k in @('disabledynamictick','useplatformclock','useplatformtick')) {
        $l = ($bcd -split "`n") | Where-Object { $_ -match $k }
        Line $k $(if ($l) { ($l -replace '\s+',' ').Trim() } else { '<not set>' })
    }
    if ($bcd -match 'useplatformclock\s+Yes') {
        Verdict "useplatformclock=Yes forces HPET - usually HARMFUL on modern CPUs" 'bad'
    }
} else {
    Verdict "Not elevated - skipped Secure Boot and boot config checks" 'na'
    Write-Host "          Re-run from an admin PowerShell for the full report." -ForegroundColor Gray
}

Write-Host ""
Write-Host "################################################################" -ForegroundColor White
Write-Host "  Audit complete. Nothing was changed." -ForegroundColor White
Write-Host "  Read docs/TWEAK-REFERENCE.md before applying anything." -ForegroundColor White
Write-Host "################################################################" -ForegroundColor White
Write-Host ""

if ($Json) { $report | ConvertTo-Json -Depth 4 }
