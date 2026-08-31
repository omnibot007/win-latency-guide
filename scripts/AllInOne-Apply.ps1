<#
.SYNOPSIS
    All-in-one stability + performance apply. Runs at every logon.

.OWNERSHIP  (this is the important part)
    The original crash was caused by two tweak packs writing the SAME values
    with DIFFERENT numbers, fighting each other on every boot. To make that
    impossible, ownership is split and NEVER overlaps:

      LatencyLab-Boot.ps1  owns: timer resolution, Win32PrioritySeparation,
        OverlayTestMode (MPO), GPU/NVIDIA keys, NIC RSS, QoS shaper,
        telemetry, FSE/GameDVR, FTH, NetworkThrottlingIndex, Engine.ini
        overlay, E-core pinning of background apps.

      THIS SCRIPT owns: svchost split threshold, core parking (both
        efficiency classes), C-states, memory management, filesystem/TCP
        cleanup, Ndu, SmartScreen, app kill timeouts.

    Do not add a value here that LatencyLab-Boot.ps1 already writes.

.NOTES
    Idempotent. Safe to run repeatedly. Log: C:\LatencyLab\logs\allinone.log
#>

$ErrorActionPreference = 'Continue'
$log = 'C:\LatencyLab\logs\allinone.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
if ((Test-Path $log) -and (Get-Item $log).Length -gt 1MB) { Set-Content $log '' }
function Log { param($m) "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))  $m" | Add-Content $log }

Log '--- AllInOne start ---'

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
$elevated = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $elevated) { Log 'NOT ELEVATED - HKLM changes will be skipped' }

# ---------------------------------------------------------------
# 1. THE CRASH FIX. 32GB threshold crammed DcomLaunch+LSM+Power into
#    one svchost; any fault there = bugcheck 0xEF CRITICAL_PROCESS_DIED.
#    3670016 KB is the Windows 10 stock value.
# ---------------------------------------------------------------
if ($elevated) {
    try {
        $cur = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SvcHostSplitThresholdInKB -EA SilentlyContinue).SvcHostSplitThresholdInKB
        if ($cur -ne 3670016) {
            Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SvcHostSplitThresholdInKB -Value 3670016 -Type DWord -Force
            Log "SvcHostSplitThresholdInKB $cur -> 3670016 (CRASH FIX re-asserted)"
        }
    } catch { Log "svchost threshold FAILED: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------
# 2. Core parking OFF for BOTH efficiency classes.
#    Class 0 = E-cores, Class 1 = P-cores. Only class 0 had ever been
#    set, so all 8 P-cores were parking while E-cores stayed awake.
# ---------------------------------------------------------------
if ($elevated) {
    try {
        $scheme = '0eeb3a79-fd9e-49e8-8266-b682359b75ce'   # Ultimate Performance
        $sub    = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00'
        $c0min = '0cc5b647-c1df-4637-891a-dec35c318583'
        $c1min = '0cc5b647-c1df-4637-891a-dec35c318584'
        $c0max = 'ea062031-0e34-4ff1-9b6d-eb1059334028'
        $c1max = 'ea062031-0e34-4ff1-9b6d-eb1059334029'
        $idle  = '5d76a2ca-e8c0-402f-a133-2158492d58ad'
        foreach ($g in @($c0min, $c1min, $c0max, $c1max, $idle)) {
            $k = Join-Path $sub $g
            if (Test-Path $k) { Set-ItemProperty $k -Name Attributes -Value 2 -Type DWord -Force }
        }
        foreach ($g in @($c0min, $c1min, $c0max, $c1max)) {
            powercfg /setacvalueindex $scheme SUB_PROCESSOR $g 100 2>&1 | Out-Null
            powercfg /setdcvalueindex $scheme SUB_PROCESSOR $g 100 2>&1 | Out-Null
        }
        # C-states off: cores never enter sleep states, no wake latency.
        powercfg /setacvalueindex $scheme SUB_PROCESSOR $idle 1 2>&1 | Out-Null
        powercfg /setdcvalueindex $scheme SUB_PROCESSOR $idle 1 2>&1 | Out-Null
        powercfg /setactive $scheme 2>&1 | Out-Null
        Log 'core parking off (both classes) + C-states disabled'
    } catch { Log "power settings FAILED: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------
# 3. Memory / filesystem / network cleanup
# ---------------------------------------------------------------
if ($elevated) {
    try {
        Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name LargeSystemCache -Value 0 -Type DWord -Force
        Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name DisablePagingExecutive -Value 1 -Type DWord -Force
        # Tcp1323Opts=0 disabled TCP window scaling - hurts a 2.5Gbps link.
        Remove-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name Tcp1323Opts -Force -EA SilentlyContinue
        # NtfsMemoryUsage=2 raises paged-pool pressure for no measurable gain.
        Remove-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name NtfsMemoryUsage -Force -EA SilentlyContinue
        # Ndu is a documented DPC latency contributor; only powers Settings > Data usage.
        Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Ndu' -Name Start -Value 4 -Type DWord -Force
        Log 'memory/filesystem/network cleanup applied'
    } catch { Log "cleanup FAILED: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------
# 4. Things that must NOT come back
# ---------------------------------------------------------------
if ($elevated) {
    try {
        # Defender IFEO hijack: mpcmdrun.exe -> systray.exe stub.
        $mp = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\mpcmdrun.exe'
        if (Test-Path $mp) {
            if ((Get-ItemProperty $mp -Name Debugger -EA SilentlyContinue).Debugger) {
                Remove-ItemProperty $mp -Name Debugger -Force
                Log 'removed mpcmdrun.exe Debugger hijack (had returned)'
            }
        }
        # csrss IFEO: no measurable gain, csrss already runs high priority.
        $csr = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\csrss.exe'
        if (Test-Path $csr) { Remove-Item $csr -Recurse -Force -EA SilentlyContinue; Log 'removed csrss.exe IFEO (had returned)' }
        # SmartScreen stays OFF - deliberate user choice.
        Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -Name SmartScreenEnabled -Value 'Off' -Type String -Force
    } catch { Log "cleanup2 FAILED: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------
# 5. App kill timeouts (HKCU - runs as the user).
#    Aggressive values here can force-kill the game on a brief hang
#    (shader compile). LowLevelHooksTimeout stays low on purpose - that
#    one drops a hung mouse/keyboard hook faster and IS an input tweak.
# ---------------------------------------------------------------
try {
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name AutoEndTasks         -Value '0'    -Type String -Force
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name HungAppTimeout       -Value '5000' -Type String -Force
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name WaitToKillAppTimeout -Value '5000' -Type String -Force
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name LowLevelHooksTimeout -Value '1000' -Type String -Force
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name MenuShowDelay        -Value '0'    -Type String -Force
    # 1:1 mouse - pointer precision (acceleration) off.
    Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name MouseSpeed       -Value '0'  -Type String -Force
    Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name MouseThreshold1  -Value '0'  -Type String -Force
    Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name MouseThreshold2  -Value '0'  -Type String -Force
    Log 'HKCU timeouts + 1:1 mouse applied'
} catch { Log "HKCU FAILED: $($_.Exception.Message)" }

# ---------------------------------------------------------------
# 6. Report
# ---------------------------------------------------------------
try {
    $parked = @((Get-Counter '\Processor Information(*)\Parking Status' -EA SilentlyContinue).CounterSamples |
                Where-Object { $_.InstanceName -notmatch '_Total' -and $_.CookedValue -eq 1 })
    $sv = (Get-Process svchost -EA SilentlyContinue).Count
    Log "state: svchost=$sv parkedCores=$($parked.Count)/32"
} catch { }

# ---------------------------------------------------------------
# 7. Keep Windows Update OFF.
#    It was pulling 169-330 Mbps mid-match and spiking ping to
#    ~500-800ms. WaaSMedicSvc is Windows' self-heal service and will
#    silently turn updates back on, so it goes too.
#    ESCAPE HATCH: create C:\LatencyLab\WINDOWS_UPDATE_ENABLED (or run
#    Enable-WindowsUpdate.ps1) and this block is skipped entirely.
# ---------------------------------------------------------------
if ($elevated -and -not (Test-Path 'C:\LatencyLab\WINDOWS_UPDATE_ENABLED')) {
    try {
        $changed = 0
        foreach ($s in @('wuauserv','UsoSvc','WaaSMedicSvc','DoSvc')) {
            $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$s"
            if (Test-Path $k) {
                $cur = (Get-ItemProperty $k -Name Start -EA SilentlyContinue).Start
                if ($cur -ne 4) {
                    Set-ItemProperty $k -Name Start -Value 4 -Type DWord -Force
                    $changed++
                }
            }
        }
        $au = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
        if (-not (Test-Path $au)) { New-Item -Path $au -Force | Out-Null }
        Set-ItemProperty $au -Name 'NoAutoUpdate' -Value 1 -Type DWord -Force
        Set-ItemProperty $au -Name 'NoAutoRebootWithLoggedOnUsers' -Value 1 -Type DWord -Force
        Set-ItemProperty $au -Name 'AUOptions' -Value 1 -Type DWord -Force
        if ($changed -gt 0) { Log "Windows Update re-disabled ($changed service(s) had come back)" }
    } catch { Log "WU disable FAILED: $(<#
.SYNOPSIS
    All-in-one stability + performance apply. Runs at every logon.

.OWNERSHIP  (this is the important part)
    The original crash was caused by two tweak packs writing the SAME values
    with DIFFERENT numbers, fighting each other on every boot. To make that
    impossible, ownership is split and NEVER overlaps:

      LatencyLab-Boot.ps1  owns: timer resolution, Win32PrioritySeparation,
        OverlayTestMode (MPO), GPU/NVIDIA keys, NIC RSS, QoS shaper,
        telemetry, FSE/GameDVR, FTH, NetworkThrottlingIndex, Engine.ini
        overlay, E-core pinning of background apps.

      THIS SCRIPT owns: svchost split threshold, core parking (both
        efficiency classes), C-states, memory management, filesystem/TCP
        cleanup, Ndu, SmartScreen, app kill timeouts.

    Do not add a value here that LatencyLab-Boot.ps1 already writes.

.NOTES
    Idempotent. Safe to run repeatedly. Log: C:\LatencyLab\logs\allinone.log
#>

$ErrorActionPreference = 'Continue'
$log = 'C:\LatencyLab\logs\allinone.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
if ((Test-Path $log) -and (Get-Item $log).Length -gt 1MB) { Set-Content $log '' }
function Log { param($m) "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))  $m" | Add-Content $log }

Log '--- AllInOne start ---'

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
$elevated = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $elevated) { Log 'NOT ELEVATED - HKLM changes will be skipped' }

# ---------------------------------------------------------------
# 1. THE CRASH FIX. 32GB threshold crammed DcomLaunch+LSM+Power into
#    one svchost; any fault there = bugcheck 0xEF CRITICAL_PROCESS_DIED.
#    3670016 KB is the Windows 10 stock value.
# ---------------------------------------------------------------
if ($elevated) {
    try {
        $cur = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SvcHostSplitThresholdInKB -EA SilentlyContinue).SvcHostSplitThresholdInKB
        if ($cur -ne 3670016) {
            Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SvcHostSplitThresholdInKB -Value 3670016 -Type DWord -Force
            Log "SvcHostSplitThresholdInKB $cur -> 3670016 (CRASH FIX re-asserted)"
        }
    } catch { Log "svchost threshold FAILED: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------
# 2. Core parking OFF for BOTH efficiency classes.
#    Class 0 = E-cores, Class 1 = P-cores. Only class 0 had ever been
#    set, so all 8 P-cores were parking while E-cores stayed awake.
# ---------------------------------------------------------------
if ($elevated) {
    try {
        $scheme = '0eeb3a79-fd9e-49e8-8266-b682359b75ce'   # Ultimate Performance
        $sub    = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00'
        $c0min = '0cc5b647-c1df-4637-891a-dec35c318583'
        $c1min = '0cc5b647-c1df-4637-891a-dec35c318584'
        $c0max = 'ea062031-0e34-4ff1-9b6d-eb1059334028'
        $c1max = 'ea062031-0e34-4ff1-9b6d-eb1059334029'
        $idle  = '5d76a2ca-e8c0-402f-a133-2158492d58ad'
        foreach ($g in @($c0min, $c1min, $c0max, $c1max, $idle)) {
            $k = Join-Path $sub $g
            if (Test-Path $k) { Set-ItemProperty $k -Name Attributes -Value 2 -Type DWord -Force }
        }
        foreach ($g in @($c0min, $c1min, $c0max, $c1max)) {
            powercfg /setacvalueindex $scheme SUB_PROCESSOR $g 100 2>&1 | Out-Null
            powercfg /setdcvalueindex $scheme SUB_PROCESSOR $g 100 2>&1 | Out-Null
        }
        # C-states off: cores never enter sleep states, no wake latency.
        powercfg /setacvalueindex $scheme SUB_PROCESSOR $idle 1 2>&1 | Out-Null
        powercfg /setdcvalueindex $scheme SUB_PROCESSOR $idle 1 2>&1 | Out-Null
        powercfg /setactive $scheme 2>&1 | Out-Null
        Log 'core parking off (both classes) + C-states disabled'
    } catch { Log "power settings FAILED: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------
# 3. Memory / filesystem / network cleanup
# ---------------------------------------------------------------
if ($elevated) {
    try {
        Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name LargeSystemCache -Value 0 -Type DWord -Force
        Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name DisablePagingExecutive -Value 1 -Type DWord -Force
        # Tcp1323Opts=0 disabled TCP window scaling - hurts a 2.5Gbps link.
        Remove-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name Tcp1323Opts -Force -EA SilentlyContinue
        # NtfsMemoryUsage=2 raises paged-pool pressure for no measurable gain.
        Remove-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name NtfsMemoryUsage -Force -EA SilentlyContinue
        # Ndu is a documented DPC latency contributor; only powers Settings > Data usage.
        Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Ndu' -Name Start -Value 4 -Type DWord -Force
        Log 'memory/filesystem/network cleanup applied'
    } catch { Log "cleanup FAILED: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------
# 4. Things that must NOT come back
# ---------------------------------------------------------------
if ($elevated) {
    try {
        # Defender IFEO hijack: mpcmdrun.exe -> systray.exe stub.
        $mp = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\mpcmdrun.exe'
        if (Test-Path $mp) {
            if ((Get-ItemProperty $mp -Name Debugger -EA SilentlyContinue).Debugger) {
                Remove-ItemProperty $mp -Name Debugger -Force
                Log 'removed mpcmdrun.exe Debugger hijack (had returned)'
            }
        }
        # csrss IFEO: no measurable gain, csrss already runs high priority.
        $csr = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\csrss.exe'
        if (Test-Path $csr) { Remove-Item $csr -Recurse -Force -EA SilentlyContinue; Log 'removed csrss.exe IFEO (had returned)' }
        # SmartScreen stays OFF - deliberate user choice.
        Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -Name SmartScreenEnabled -Value 'Off' -Type String -Force
    } catch { Log "cleanup2 FAILED: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------
# 5. App kill timeouts (HKCU - runs as the user).
#    Aggressive values here can force-kill the game on a brief hang
#    (shader compile). LowLevelHooksTimeout stays low on purpose - that
#    one drops a hung mouse/keyboard hook faster and IS an input tweak.
# ---------------------------------------------------------------
try {
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name AutoEndTasks         -Value '0'    -Type String -Force
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name HungAppTimeout       -Value '5000' -Type String -Force
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name WaitToKillAppTimeout -Value '5000' -Type String -Force
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name LowLevelHooksTimeout -Value '1000' -Type String -Force
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name MenuShowDelay        -Value '0'    -Type String -Force
    # 1:1 mouse - pointer precision (acceleration) off.
    Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name MouseSpeed       -Value '0'  -Type String -Force
    Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name MouseThreshold1  -Value '0'  -Type String -Force
    Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name MouseThreshold2  -Value '0'  -Type String -Force
    Log 'HKCU timeouts + 1:1 mouse applied'
} catch { Log "HKCU FAILED: $($_.Exception.Message)" }

# ---------------------------------------------------------------
# 6. Report
# ---------------------------------------------------------------
try {
    $parked = @((Get-Counter '\Processor Information(*)\Parking Status' -EA SilentlyContinue).CounterSamples |
                Where-Object { $_.InstanceName -notmatch '_Total' -and $_.CookedValue -eq 1 })
    $sv = (Get-Process svchost -EA SilentlyContinue).Count
    Log "state: svchost=$sv parkedCores=$($parked.Count)/32"
} catch { }

Log '--- AllInOne end ---'
.Exception.Message)" }
}
Log '--- AllInOne end ---'

