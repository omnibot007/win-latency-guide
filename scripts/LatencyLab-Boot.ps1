<#
.SYNOPSIS
    Runs automatically at every logon via the 'LatencyLab-Boot' scheduled task.
    Fully unattended - there is no manual step to remember.

.DESCRIPTION
    Handles the state Windows does NOT persist, plus automatic game-mode switching.

    ALWAYS:
      * GPU power limit -> 216W  (nvidia-smi resets to 200W on every driver reload)
      * Timer task resident      (SetTimerResolution must stay running to hold 0.5ms)
      * Background apps pinned to E-cores, held in a loop because affinity is
        per-process and every newly spawned process starts on all 32 threads again.

    ON FORTNITE LAUNCH (detected automatically):
      * Spotify closed
      * Affinity loop tightens to 5s so newly spawned helpers get pinned fast
      * Re-asserts GPU power limit (driver may have reloaded)

    ON FORTNITE EXIT:
      * Loop relaxes back to 15s. Spotify is NOT reopened - relaunch it yourself.

    NOT repeated here because the registry already persists them:
      USB power management, USB selective suspend, Fortnite IFEO priority,
      GPU/XHCI interrupt affinity + priority, NIC settings, DistributeTimers,
      NoLazyMode, FTH, NTFS memoryusage.

    Log: C:\LatencyLab\logs\boot.log
#>
$ErrorActionPreference = 'Continue'
$log = 'C:\LatencyLab\logs\boot.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
if ((Test-Path $log) -and (Get-Item $log).Length -gt 2MB) { Set-Content $log '' }
function Log { param($m) "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))  $m" | Add-Content $log }

Log '--- boot task start ---'

try {
    if (-not (Get-Process SetTimerResolution -ErrorAction SilentlyContinue)) {
        Start-ScheduledTask -TaskName 'LatencyLab-TimerResolution' -ErrorAction Stop
        Log 'started timer task'
    } else { Log 'timer already resident' }
} catch { Log "timer FAILED: $($_.Exception.Message)" }

# --- Re-assert registry tweaks that Windows or driver updates may reset ---
try {
    # Win32PrioritySeparation = 36 (FrameSync best 1% lows)
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name Win32PrioritySeparation -Value 36 -Type DWord -Force
    # GlobalTimerResolutionRequests = 1 (frame pacing at 500Hz)
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' -Name 'GlobalTimerResolutionRequests' -Value 1 -Type DWord -Force
    # MPO disabled (prevents stutter/flicker)
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' -Name 'OverlayTestMode' -Value 5 -Type DWord -Force
    # GpuEnergyDrv disabled
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\GpuEnergyDrv' -Name 'Start' -Value 4 -Type DWord -Force
    # RmGpsPsEnablePerCpuCoreDpc = 1 (per-CPU core DPC for GPU)
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'RmGpsPsEnablePerCpuCoreDpc' -Value 1 -Type DWord -Force
    # NVIDIA telemetry registry keys
    $fts = 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS'
    if (Test-Path $fts) {
        Set-ItemProperty $fts -Name 'EnableRID44231' -Value 0 -Type DWord -Force
        Set-ItemProperty $fts -Name 'EnableRID64640' -Value 0 -Type DWord -Force
        Set-ItemProperty $fts -Name 'EnableRID66610' -Value 0 -Type DWord -Force
    }
    # Windows telemetry
    $dc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
    if (-not (Test-Path $dc)) { New-Item -Path $dc -Force | Out-Null }
    Set-ItemProperty $dc -Name 'AllowTelemetry' -Value 0 -Type DWord -Force
    # DisableDynamicPstate = 1 (lock GPU max clocks)
    $nvClass = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    Get-ChildItem $nvClass -ErrorAction SilentlyContinue | ForEach-Object {
        $desc = (Get-ItemProperty $_.PSPath -Name 'DriverDesc' -ErrorAction SilentlyContinue).DriverDesc
        if ($desc -like '*NVIDIA GeForce RTX 4070*') {
            Set-ItemProperty $_.PSPath -Name 'DisableDynamicPstate' -Value 1 -Type DWord -Force
        }
    }
    # QoS upload shaper (18 Mbps = 90% of 20 Mbps upload)
    Remove-NetQosPolicy -Name 'FN-UploadShaper' -PolicyStore 'localhost' -Confirm:$false -ErrorAction SilentlyContinue
    New-NetQosPolicy -Name 'FN-UploadShaper' -Default -ThrottleRateActionBitsPerSecond 18000000 -PolicyStore 'localhost' -ErrorAction SilentlyContinue | Out-Null
    # RSS for I225-V (driver fails to set these on reinstall)
    $netClass = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
    Get-ChildItem $netClass -ErrorAction SilentlyContinue | ForEach-Object {
        $desc = (Get-ItemProperty $_.PSPath -Name 'DriverDesc' -ErrorAction SilentlyContinue).DriverDesc
        if ($desc -like '*I225*') {
            Set-ItemProperty $_.PSPath -Name '*RSS' -Value '1' -Type String -Force
            Set-ItemProperty $_.PSPath -Name '*NumRssQueues' -Value '4' -Type String -Force
            Set-ItemProperty $_.PSPath -Name '*RSSProfile' -Value '4' -Type String -Force
            Set-ItemProperty $_.PSPath -Name '*RssBaseProcNumber' -Value '0' -Type String -Force
            Set-ItemProperty $_.PSPath -Name '*MaxRssProcessors' -Value '4' -Type String -Force
        }
    }
    # Consumer features / bloatware auto-install
    $cc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
    if (-not (Test-Path $cc)) { New-Item -Path $cc -Force | Out-Null }
    Set-ItemProperty $cc -Name 'DisableWindowsConsumerFeatures' -Value 1 -Type DWord -Force
    # Bing search in Start Menu
    Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'BingSearchEnabled' -Value 0 -Type DWord -Force
    # Fullscreen Optimizations disabled
    Set-ItemProperty 'HKCU:\System\GameConfigStore' -Name 'GameDVR_FSEBehaviorMode' -Value 2 -Type DWord -Force
    Set-ItemProperty 'HKCU:\System\GameConfigStore' -Name 'GameDVR_HonorUserFSEBehaviorMode' -Value 1 -Type DWord -Force
    Set-ItemProperty 'HKCU:\System\GameConfigStore' -Name 'GameDVR_FSEBehavior' -Value 2 -Type DWord -Force
    Set-ItemProperty 'HKCU:\System\GameConfigStore' -Name 'GameDVR_DXGIHonorFSEWindowsCompatible' -Value 1 -Type DWord -Force
    Set-ItemProperty 'HKCU:\System\GameConfigStore' -Name 'GameDVR_EFSEFeatureFlags' -Value 0 -Type DWord -Force
    # Sticky Key shortcut disabled
    Set-ItemProperty 'HKCU:\Control Panel\Accessibility\StickyKeys' -Name 'Flags' -Value '506' -Type String -Force
    # NetworkThrottlingIndex = 10 (default - lower DPC latency than disabled per djdallmann xperf)
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'NetworkThrottlingIndex' -Value 10 -Type DWord -Force
    # Fault Tolerant Heap disabled
    $fth = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FTH'
    if (-not (Test-Path $fth)) { New-Item -Path $fth -Force | Out-Null }
    Set-ItemProperty $fth -Name 'Enabled' -Value 0 -Type DWord -Force
    # --- Tweaks from fortnite-tweak-packs repo (legitimate ones only) ---
    # Audio ducking off (Peterbot Delay8.reg) - stops Windows lowering game audio 20% on Discord voice
    $duckPath = 'HKCU:\SOFTWARE\Microsoft\Multimedia\Audio'
    if (-not (Test-Path $duckPath)) { New-Item -Path $duckPath -Force | Out-Null }
    Set-ItemProperty $duckPath -Name 'UserDuckingPreference' -Value 3 -Type DWord -Force
    # Timer coalescing off (Peterbot Delay3.reg)
    @('HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel',
      'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power',
      'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management',
      'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Executive',
      'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager',
      'HKLM:\SYSTEM\CurrentControlSet\Control\Power',
      'HKLM:\SYSTEM\CurrentControlSet\Control') | ForEach-Object {
        Set-ItemProperty $_ -Name 'CoalescingTimerInterval' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    # NTFS tweaks (Peterbot Delay20.reg)
    $fsKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
    Set-ItemProperty $fsKey -Name 'NTFSDisable8dot3NameCreation' -Value 1 -Type DWord -Force
    Set-ItemProperty $fsKey -Name 'NtfsMftZoneReservation' -Value 1 -Type DWord -Force
    Set-ItemProperty $fsKey -Name 'ContigFileAllocSize' -Value 100 -Type DWord -Force
    # VsyncIdleTimeout=0 (Peterbot Delay22.reg)
    $schedK = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Scheduler'
    if (-not (Test-Path $schedK)) { New-Item -Path $schedK -Force | Out-Null }
    Set-ItemProperty $schedK -Name 'VsyncIdleTimeout' -Value 0 -Type DWord -Force
    # MenuShowDelay=0 (ReduceInputDelay delay.reg)
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value '0' -Type String -Force
    # Kill timeouts (ReduceInputDelay delay.reg)
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name 'AutoEndTasks' -Value '0' -Type String -Force
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name 'HungAppTimeout' -Value '5000' -Type String -Force
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name 'WaitToKillAppTimeout' -Value '5000' -Type String -Force
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name 'LowLevelHooksTimeout' -Value '1000' -Type String -Force
    # [PATCHED] removed: was written as REG_DWORD (Windows ignores it) and 2000ms is unsafe. Default 5000 applies.
    # GPU VRR latency (Peterbot Delay16.reg)
    $nvGpu = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000'
    if ((Get-ItemProperty $nvGpu -Name 'DriverDesc' -EA SilentlyContinue).DriverDesc -like '*NVIDIA*') {
        Set-ItemProperty $nvGpu -Name 'LOWLATENCY' -Value 1 -Type DWord -Force -EA SilentlyContinue
        Set-ItemProperty $nvGpu -Name 'Node3DLowLatency' -Value 1 -Type DWord -Force -EA SilentlyContinue
        Set-ItemProperty $nvGpu -Name 'D3PCLatency' -Value 1 -Type DWord -Force -EA SilentlyContinue
        Set-ItemProperty $nvGpu -Name 'TransitionLatency' -Value 1 -Type DWord -Force -EA SilentlyContinue
        Set-ItemProperty $nvGpu -Name 'vrrCursorMarginUs' -Value 1 -Type DWord -Force -EA SilentlyContinue
        Set-ItemProperty $nvGpu -Name 'vrrDeflickerMarginUs' -Value 1 -Type DWord -Force -EA SilentlyContinue
        Set-ItemProperty $nvGpu -Name 'vrrDeflickerMaxUs' -Value 1 -Type DWord -Force -EA SilentlyContinue
    }
    # nvlddmkm pipe optimization (Peterbot Delay17.reg)
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm' -Name 'Display%MonitorAmount%_PipeOptimizationEnable' -Value 1 -Type DWord -Force -EA SilentlyContinue
    # DelayedDesktopSwitchTimeout=0 (Peterbot Delay7.reg)
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'DelayedDesktopSwitchTimeout' -Value 0 -Type DWord -Force
    # TCP ServiceProvider priorities (ReduceInputDelay fcshotgun.reg)
    $spKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\ServiceProvider'
    Set-ItemProperty $spKey -Name 'LocalPriority' -Value 4 -Type DWord -Force
    Set-ItemProperty $spKey -Name 'HostsPriority' -Value 5 -Type DWord -Force
    Set-ItemProperty $spKey -Name 'DnsPriority' -Value 6 -Type DWord -Force
    Set-ItemProperty $spKey -Name 'NetbtPriority' -Value 7 -Type DWord -Force
    # DisplayPostProcessing MMCSS task (ReduceInputDelay FPS.reg)
    $dppKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\DisplayPostProcessing'
    if (-not (Test-Path $dppKey)) { New-Item -Path $dppKey -Force | Out-Null }
    Set-ItemProperty $dppKey -Name 'Priority' -Value 8 -Type DWord -Force
    Set-ItemProperty $dppKey -Name 'GPU Priority' -Value 18 -Type DWord -Force
    Set-ItemProperty $dppKey -Name 'Scheduling Category' -Value 'High' -Type String -Force
    Set-ItemProperty $dppKey -Name 'SFIO Priority' -Value 'High' -Type String -Force
    Set-ItemProperty $dppKey -Name 'Latency Sensitive' -Value 'True' -Type String -Force
    # --- Tweaks extracted from Aphrodite .bat files (legitimate ones only) ---
    # csrss.exe IFEO priority (GUI thread manager)
    # [PATCHED] removed - csrss already runs high priority; conflicted with optimize-and-stabilize.ps1 every logon
    # $csrssPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\csrss.exe\PerfOptions'
    # [PATCHED] removed - csrss already runs high priority; conflicted with optimize-and-stabilize.ps1 every logon
    # if (-not (Test-Path $csrssPath)) { New-Item -Path $csrssPath -Force | Out-Null }
    # [PATCHED] removed - csrss already runs high priority; conflicted with optimize-and-stabilize.ps1 every logon
    # Set-ItemProperty $csrssPath -Name 'CpuPriorityClass' -Value 3 -Type DWord -Force
    # [PATCHED] removed - csrss already runs high priority; conflicted with optimize-and-stabilize.ps1 every logon
    # Set-ItemProperty $csrssPath -Name 'IoPriority' -Value 3 -Type DWord -Force
    # AFD Winsock buffer optimization (affects UDP game traffic)
    $afdPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters'
    if (-not (Test-Path $afdPath)) { New-Item -Path $afdPath -Force | Out-Null }
    Set-ItemProperty $afdPath -Name 'DefaultReceiveWindow' -Value 16384 -Type DWord -Force
    Set-ItemProperty $afdPath -Name 'DefaultSendWindow' -Value 16384 -Type DWord -Force
    Set-ItemProperty $afdPath -Name 'FastCopyReceiveThreshold' -Value 16384 -Type DWord -Force
    Set-ItemProperty $afdPath -Name 'FastSendDatagramThreshold' -Value 16384 -Type DWord -Force
    Set-ItemProperty $afdPath -Name 'DynamicSendBufferDisable' -Value 0 -Type DWord -Force
    Set-ItemProperty $afdPath -Name 'IgnorePushBitOnReceives' -Value 1 -Type DWord -Force
    Set-ItemProperty $afdPath -Name 'NonBlockingSendSpecialBuffering' -Value 1 -Type DWord -Force
    # TCP/IP fast path thresholds
    $tcpPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
    Set-ItemProperty $tcpPath -Name 'FastCopyReceiveThreshold' -Value 16384 -Type DWord -Force
    Set-ItemProperty $tcpPath -Name 'FastSendDatagramThreshold' -Value 16384 -Type DWord -Force
    Set-ItemProperty $tcpPath -Name 'DelayedAckFrequency' -Value 1 -Type DWord -Force
    Set-ItemProperty $tcpPath -Name 'DelayedAckTicks' -Value 1 -Type DWord -Force
    # DisablePagingExecutive=1 (keep kernel drivers in RAM, reduces DPC latency)
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'DisablePagingExecutive' -Value 1 -Type DWord -Force
    # GameDVR_DSEBehavior=2
    Set-ItemProperty 'HKCU:\System\GameConfigStore' -Name 'GameDVR_DSEBehavior' -Value 2 -Type DWord -Force
    # GameBar / Game Mode
    $gameBarPath = 'HKCU:\Software\Microsoft\GameBar'
    Set-ItemProperty $gameBarPath -Name 'AllowAutoGameMode' -Value 1 -Type DWord -Force
    Set-ItemProperty $gameBarPath -Name 'AutoGameModeEnabled' -Value 1 -Type DWord -Force
    Set-ItemProperty $gameBarPath -Name 'UseNexusForGameBarEnabled' -Value 0 -Type DWord -Force
    Set-ItemProperty $gameBarPath -Name 'ShowStartupPanel' -Value 0 -Type DWord -Force
    # DisableAutomaticRestartSignOn
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'DisableAutomaticRestartSignOn' -Value 1 -Type DWord -Force
    # Remote Assistance disabled (does NOT affect RustDesk)
    $raPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance'
    Set-ItemProperty $raPath -Name 'fAllowFullControl' -Value 0 -Type DWord -Force
    Set-ItemProperty $raPath -Name 'fAllowToGetHelp' -Value 0 -Type DWord -Force
    # Maps auto-update off
    $mapsPath = 'HKLM:\SYSTEM\Maps'
    if (-not (Test-Path $mapsPath)) { New-Item -Path $mapsPath -Force | Out-Null }
    Set-ItemProperty $mapsPath -Name 'AutoUpdateEnabled' -Value 0 -Type DWord -Force
    # Push notification toasts off
    $pushPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications'
    Set-ItemProperty $pushPath -Name 'ToastEnabled' -Value 0 -Type DWord -Force
    Set-ItemProperty $pushPath -Name 'LockScreenToastEnabled' -Value 0 -Type DWord -Force
    # --- Engine.ini overlay (Fortnite regenerates this file and wipes the tweaks) ---
    $fnCfg = "$env:LOCALAPPDATA\FortniteGame\Saved\Config\WindowsClient\Engine.ini"
    try {
        $needOverlay = $true
        if (Test-Path $fnCfg) {
            if ((Get-Content $fnCfg -Raw -ErrorAction SilentlyContinue) -match 'LatencyLab performance overlay') { $needOverlay = $false }
        } else {
            New-Item -ItemType Directory -Force -Path (Split-Path $fnCfg) | Out-Null
        }
        if ($needOverlay) {
            $ov = @"

; ================= LatencyLab performance overlay =================
[/Script/Engine.RendererSettings]
r.OneFrameThreadLag=0
r.GTSyncType=1
r.FinishCurrentFrame=0
r.Streaming.PoolSize=4096
r.Streaming.LimitPoolSizeToVRAM=1
r.Streaming.UseFixedPoolSize=1
r.Streaming.UseAllMips=0
r.Nanite=0
r.HZBOcclusion=1
r.VRS.Enable=1
r.VSync=0
rhi.SyncInterval=0

[SystemSettings]
r.OneFrameThreadLag=0
r.GTSyncType=1
r.Streaming.PoolSize=4096
r.Streaming.LimitPoolSizeToVRAM=1
r.Streaming.UseFixedPoolSize=1
; ==================================================================
"@
            Add-Content -Path $fnCfg -Value $ov -Encoding UTF8
            Log 'Engine.ini overlay re-applied (Fortnite had wiped it)'
        }
    } catch { Log "Engine.ini overlay FAILED: $($_.Exception.Message)" }
    Log 're-asserted all registry tweaks (priority sep, timer, MPO, GPU, NIC RSS, QoS, telemetry, FSE, FTH, NTI, pack tweaks, Aphrodite legit)'
} catch { Log "registry re-assert FAILED: $($_.Exception.Message)" }

# --- Disable telemetry scheduled tasks (Windows re-enables some after updates) ---
try {
    $telTasks = @(
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
        '\Microsoft\Windows\Application Experience\StartupAppTask',
        '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
        '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
        '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask',
        '\Microsoft\Windows\Feedback\Siuf\DmClient',
        '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
        '\Microsoft\Windows\Windows Error Reporting\QueueReporting',
        '\Microsoft\Windows\Autochk\Proxy',
        '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
        '\Microsoft\Windows\DiskFootprint\Diagnostics',
        '\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem',
        '\Microsoft\Windows\Shell\FamilySafetyMonitor',
        '\Microsoft\Windows\Shell\FamilySafetyRefreshTask'
    )
    $td = 0
    foreach ($t in $telTasks) {
        $tn = $t.Split('\')[-1]
        $tp = $t.Substring(0, $t.LastIndexOf('\')) + '\'
        $task = Get-ScheduledTask -TaskName $tn -TaskPath $tp -ErrorAction SilentlyContinue
        if ($task -and $task.State -ne 'Disabled') {
            Disable-ScheduledTask -TaskName $tn -TaskPath $tp -ErrorAction SilentlyContinue | Out-Null
            $td++
        }
    }
    if ($td -gt 0) { Log "disabled $td telemetry task(s) re-enabled by Windows" }
} catch { Log "telemetry task disable FAILED: $($_.Exception.Message)" }

# --- Disable NVIDIA bloat directories on boot (files not in use yet) ---
try {
    & 'C:\LatencyLab\scripts\Boot-DisableNvidiaBloat.ps1'
} catch { Log "NVIDIA bloat disable FAILED: $($_.Exception.Message)" }

# Decimal literal: PowerShell parses 0xFFFF0000 as a NEGATIVE Int32 and the affinity
# setter rejects the sign-extended value. See Set-BackgroundAffinity.ps1.
$E_CORES = [IntPtr][int64]4294901760   # 0xFFFF0000 -> logical 16-31

$targets = @(
    'Discord','discord_clips','DiscordSystemHelper','DiscordCanary','DiscordPTB',
    'Spotify','Notion','steam','steamwebhelper','steamservice',
    'EpicWebHelper','Voicemod','VoicemodDesktop','antimicrox',
    'msedge','chrome','firefox','RtkAudUService64','SearchIndexer','OneDrive',
    'EOSOverlayRenderer-Win64-Shipping','EpicOnlineServicesUserHelper','gamingservices','gamingservicesnet','MoUsoCoreWorker','SearchApp',
    'RustDesk'
)

# HARD EXCLUSION LIST - never pin these, regardless of what is in $targets.
# Pinning nvcontainer/NVDisplay.Container to E-cores starved the display pipeline
# and produced stutter plus fullscreen focus loss. That was a real regression.
# dwm is the 500Hz compositor, audiodg is the audio graph, GameInput* is the
# controller path, EpicGamesLauncher owns a visible window and can steal focus.
$NEVER_PIN = @(
    'nvcontainer','NVDisplay.Container','nvsphelper64','NVIDIA Share','NVIDIA Web Helper',
    'nvcplui','nvtelemetrycontainer','dwm','audiodg','csrss','winlogon','explorer',
    'GameInputSvc','GameInputRedistService','EpicGamesLauncher'
)
$targets = $targets | Where-Object { $NEVER_PIN -notcontains $_ }

$GAME = 'FortniteClient-Win64-Shipping'

Log "watcher start (targets=$($targets.Count))"
$inGame   = $false
$interval = 15

# Downlink saturation monitor.
# Windows CANNOT rate-limit INBOUND traffic - the buffer that fills lives upstream at
# the CMTS, past your NIC. So we cannot fix bufferbloat from here. What we CAN do is
# make it visible: sample the adapter's receive counter while in a match and log when
# the line is loaded, so a bad game can be correlated with an actual cause instead of
# being blamed on the game.
# Measured on this line: idle 26ms -> +144ms under download load (p95 503ms, max 694ms).
$SAT_MBPS = 150          # sustained downlink above this is enough to start queueing
$rxLast   = (Get-NetAdapterStatistics -Name Ethernet -EA SilentlyContinue).ReceivedBytes
$rxTime   = Get-Date
$satWarned = $false

# GPU power limit decays back to the 200W default after logon, and GeForce cards do
# NOT support nvidia-smi persistence mode ("not supported for GPU on this platform").
# Setting it once at startup was a bug - it must be re-asserted periodically.

while ($true) {
    # ---- detect game state transitions ----
    $running = [bool](Get-Process -Name $GAME -ErrorAction SilentlyContinue)

    if ($running -and -not $inGame) {
        $inGame = $true; $interval = 5; $satWarned = $false
        Log 'FORTNITE DETECTED -> game mode on'
        $sp = Get-Process Spotify -ErrorAction SilentlyContinue
        if ($sp) { $sp | Stop-Process -Force -ErrorAction SilentlyContinue; Log "closed $($sp.Count) Spotify process(es)" }

        # GPU power logger DISABLED - it spawned nvidia-smi every 500ms which
        # flashed a console window. Every run confirmed peak ~100-120W, never
        # close to the 200W limit. The question is settled: 216W is pointless.
        Log 'GPU power logger skipped (settled: peak never exceeds 120W)'

        if (-not (Test-Path 'C:\LatencyLab\NO_INGAME_CAPTURE')) {
            $psi2 = New-Object System.Diagnostics.ProcessStartInfo
            $psi2.FileName = 'powershell.exe'
            $psi2.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\LatencyLab\scripts\Capture-InGame.ps1'
            $psi2.WindowStyle = 'Hidden'
            $psi2.CreateNoWindow = $true
            $psi2.UseShellExecute = $false
            [System.Diagnostics.Process]::Start($psi2) | Out-Null
            Log 'launched in-game capture (waits 120s for you to be in a match)'
        } else { Log 'in-game capture skipped (kill switch)' }
    }
    elseif (-not $running -and $inGame) {
        $inGame = $false; $interval = 15
        Log 'Fortnite exited -> game mode off'
        # Fortnite DELETES Engine.ini on exit - restore it now so it is
        # in place before the next launch, not just at next logon.
        try {
            $fnIni = "$env:LOCALAPPDATA\FortniteGame\Saved\Config\WindowsClient\Engine.ini"
            $has = $false
            if (Test-Path $fnIni) { if ((Get-Content $fnIni -Raw -EA SilentlyContinue) -match 'LatencyLab performance overlay') { $has = $true } }
            if (-not $has) { & 'C:\LatencyLab\scripts\Restore-EngineIni.ps1'; Log 'Engine.ini overlay restored after Fortnite exit' }
        } catch { Log "Engine.ini restore failed: $($_.Exception.Message)" }
    }

    # ---- downlink saturation check (only meaningful while playing) ----
    $rxNow  = (Get-NetAdapterStatistics -Name Ethernet -EA SilentlyContinue).ReceivedBytes
    $tNow   = Get-Date
    $secs   = ($tNow - $rxTime).TotalSeconds
    if ($secs -gt 0 -and $rxNow -ge $rxLast) {
        $mbps = (($rxNow - $rxLast) * 8) / $secs / 1MB
        if ($inGame -and $mbps -gt $SAT_MBPS) {
            if (-not $satWarned) {
                Log ("!! DOWNLINK LOADED {0:F0} Mbps WHILE IN MATCH - expect ping spikes up to ~500ms" -f $mbps)
                $satWarned = $true
            }
        } elseif ($inGame -and $satWarned -and $mbps -lt ($SAT_MBPS / 3)) {
            Log ("downlink back to normal ({0:F0} Mbps)" -f $mbps)
            $satWarned = $false
        }
    }
    $rxLast = $rxNow; $rxTime = $tNow

    # ---- hold background affinity ----
    $n = 0
    foreach ($p in (Get-Process -ErrorAction SilentlyContinue | Where-Object { $targets -contains $_.Name -and $NEVER_PIN -notcontains $_.Name })) {
        if ($p.ProcessorAffinity -ne $E_CORES) {
            try { $p.ProcessorAffinity = $E_CORES; $n++ } catch { }
        }
    }
    if ($n -gt 0) { Log "pinned $n new process(es) to E-cores$(if($inGame){' [in-game]'})" }

    Start-Sleep -Seconds $interval
}

