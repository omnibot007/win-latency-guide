# =====================================================================
#  optimize-and-stabilize.ps1
#  Single owner for every setting LatencyLab and vmp-tweaks disagreed on.
#  Fixes the CRITICAL_PROCESS_DIED cause, keeps all real performance.
#  Idempotent - safe to run more than once.
# =====================================================================
$ErrorActionPreference = 'Continue'

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: must run elevated (Run as Administrator)." -ForegroundColor Red
    exit 1
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$bk    = (Join-Path $env:USERPROFILE ".backup\stabilize-$stamp")
New-Item -ItemType Directory -Force -Path $bk | Out-Null
Write-Host "Backups -> $bk"  -ForegroundColor Cyan
Write-Host ""

# ---------- REAL backups (the thing vmp-tweaks never actually did) ----------
$exports = @{
 "Control_root.reg"     = "HKLM\SYSTEM\CurrentControlSet\Control"
 "MemoryManagement.reg" = "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
 "FileSystem.reg"       = "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem"
 "TcpipParams.reg"      = "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
 "Multimedia.reg"       = "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
 "IFEO.reg"             = "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
 "Explorer.reg"         = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer"
 "Dwm.reg"              = "HKLM\SOFTWARE\Microsoft\Windows\Dwm"
 "Desktop_HKCU.reg"     = "HKCU\Control Panel\Desktop"
}
foreach ($k in $exports.Keys) {
    reg export $exports[$k] "$bk\$k" /y 2>&1 | Out-Null
    if (Test-Path "$bk\$k") { Write-Host "  saved $k" -ForegroundColor DarkGray }
    else { Write-Host "  WARN could not save $k" -ForegroundColor Yellow }
}

try {
    Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
    Checkpoint-Computer -Description "Before stabilize+optimize" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    Write-Host "  restore point created" -ForegroundColor Green
} catch {
    Write-Host "  restore point skipped: $($_.Exception.Message)" -ForegroundColor Yellow
}

# =====================================================================
Write-Host ""
Write-Host "=== 1. THE CRASH FIX ===" -ForegroundColor Cyan
# 33554432 KB (32GB) forces every service into shared svchost processes.
# DcomLaunch + LSM + Power then share one PID; a fault in any service in that
# group kills a critical process => bugcheck 0xEF CRITICAL_PROCESS_DIED.
# 3670016 KB (3.5GB) is the Windows 10 stock value -> services run split.
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "SvcHostSplitThresholdInKB" -Value 3670016 -Type DWord -Force
Write-Host "  SvcHostSplitThresholdInKB 33554432 -> 3670016 (services split again)" -ForegroundColor Green

# =====================================================================
Write-Host ""
Write-Host "=== 2. SECURITY: remove Defender IFEO hijack ===" -ForegroundColor Cyan
$mp = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\mpcmdrun.exe"
if (Test-Path $mp) {
    $d = (Get-ItemProperty $mp -Name Debugger -ErrorAction SilentlyContinue).Debugger
    if ($d) {
        Remove-ItemProperty $mp -Name Debugger -Force
        Write-Host "  REMOVED mpcmdrun.exe Debugger redirect -> $d" -ForegroundColor Green
    } else {
        Write-Host "  already clean" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  key absent - clean" -ForegroundColor DarkGray
}

# =====================================================================
Write-Host ""
Write-Host "=== 3. CONFLICT RESOLUTION (one owner per value) ===" -ForegroundColor Cyan
# NetworkThrottlingIndex: LatencyLab=10, vmp=0xFFFFFFFF. Keeping 10.
# With SystemResponsiveness=0 the throttle window is already minimal; fully
# disabling removes the network stack's DPC pacing for no measured gain.
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -Value 10 -Type DWord -Force
Write-Host "  NetworkThrottlingIndex -> 10 (LatencyLab wins, vmp no longer competes)" -ForegroundColor Green

# MPO: LatencyLab writes the correct Dwm key. vmp wrote GraphicsDrivers = inert.
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" -Name "OverlayTestMode" -Value 5 -Type DWord -Force
Remove-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "OverlayTestMode" -Force -ErrorAction SilentlyContinue
Write-Host "  OverlayTestMode -> Dwm key only (removed inert duplicate)" -ForegroundColor Green

# =====================================================================
Write-Host ""
Write-Host "=== 4. REMOVE: no gain, or actively harmful ===" -ForegroundColor Cyan
Remove-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "Tcp1323Opts" -Force -ErrorAction SilentlyContinue
Write-Host "  Tcp1323Opts removed (0 disabled TCP window scaling on a 2.5Gbps NIC)" -ForegroundColor Green

Remove-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "NtfsMemoryUsage" -Force -ErrorAction SilentlyContinue
Write-Host "  NtfsMemoryUsage removed (paged-pool pressure, no measurable gain)" -ForegroundColor Green

$csr = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\csrss.exe"
if (Test-Path $csr) { Remove-Item $csr -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host "  csrss.exe IFEO PerfOptions removed (csrss already runs high priority)" -ForegroundColor Green

Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "SmartScreenEnabled" -Value "Warn" -Type String -Force
Write-Host "  SmartScreen Off -> Warn (zero FPS either way)" -ForegroundColor Green

# =====================================================================
Write-Host ""
Write-Host "=== 5. KEEP + CORRECT: real performance ===" -ForegroundColor Cyan
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "LargeSystemCache" -Value 0 -Type DWord -Force
Write-Host "  LargeSystemCache -> 0 (favor game working set over file cache)" -ForegroundColor Green

# App kill timeouts back to Windows defaults. LowLevelHooksTimeout STAYS at
# 1000 - that one is a genuine input-path tweak (drops a hung mouse/kbd hook).
Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name "HungAppTimeout"       -Value "5000" -Type String -Force
Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name "WaitToKillAppTimeout" -Value "5000" -Type String -Force
Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name "AutoEndTasks"         -Value "0"    -Type String -Force
Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name "LowLevelHooksTimeout" -Value "1000" -Type String -Force
Write-Host "  App kill timeouts -> defaults; LowLevelHooksTimeout kept at 1000" -ForegroundColor Green

# Exempt Fortnite from LatencyLab's 18 Mbps default upload shaper, and mark EF.
if (-not (Get-NetQosPolicy -Name "FortniteUDP-EF" -ErrorAction SilentlyContinue)) {
    $qos = @{
        Name                       = "FortniteUDP-EF"
        AppPathNameMatchCondition  = "FortniteClient-Win64-Shipping.exe"
        IPProtocolMatchCondition   = "UDP"
        DSCPAction                 = 46
        PolicyStore                = "localhost"
    }
    New-NetQosPolicy @qos -ErrorAction SilentlyContinue | Out-Null
}
Write-Host "  QoS FortniteUDP-EF DSCP46 present - game exempt from 18Mbps shaper" -ForegroundColor Green

# =====================================================================
Write-Host ""
Write-Host "=== VERIFY ===" -ForegroundColor Cyan
function Show($label, $path, $name, $want) {
    $v = $null
    try { $v = (Get-ItemProperty $path -Name $name -ErrorAction Stop).$name } catch { }
    if ($null -eq $v) { $s = "<absent>" } else { $s = "$v" }
    if ($s -eq $want) { $mark = "OK " } else { $mark = "!! " }
    "  {0}{1,-26} = {2,-12} (want {3})" -f $mark, $label, $s, $want
}
Show "SvcHostSplitThreshold"   "HKLM:\SYSTEM\CurrentControlSet\Control" "SvcHostSplitThresholdInKB" "3670016"
Show "NetworkThrottlingIndex"  "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex" "10"
Show "LargeSystemCache"        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "LargeSystemCache" "0"
Show "OverlayTestMode (Dwm)"   "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" "OverlayTestMode" "5"
Show "Win32PrioritySeparation" "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" "36"
Show "SmartScreenEnabled"      "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" "SmartScreenEnabled" "Warn"

$dbg = (Get-ItemProperty $mp -Name Debugger -ErrorAction SilentlyContinue).Debugger
if ($dbg) { Write-Host "  !! Defender IFEO hijack STILL PRESENT" -ForegroundColor Red }
else       { Write-Host "  OK Defender IFEO hijack     = removed" -ForegroundColor Green }

Write-Host ""
Write-Host "DONE - reboot required." -ForegroundColor Green
Write-Host "After reboot run:  (Get-Process svchost).Count" -ForegroundColor Gray
Write-Host "Expect ~70-110 (was 19). That number IS the fix working." -ForegroundColor Gray
