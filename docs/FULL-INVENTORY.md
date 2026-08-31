# Full Inventory — every single change

The complete list. Not just the headline fixes — **every** value, service, task, file and app
setting touched, including the ones too small to seem worth documenting. They add up.

Legend: ✅ applied and kept · ❌ removed or reverted · ⚠️ conditional · 🔒 requires elevation

---

## 1. Kernel / timer

| Setting | Path | Value | |
|---|---|---|---|
| `GlobalTimerResolutionRequests` | `HKLM\SYSTEM\CCS\Control\Session Manager\kernel` | `1` | ✅ |
| `DistributeTimers` | `HKLM\SYSTEM\CCS\Control\Session Manager\kernel` | `1` | ✅ |
| `CoalescingTimerInterval` | **7 different keys** (see below) | `0` | ✅ |
| Timer resolution daemon | `SetTimerResolution.exe --resolution 5000` | 0.5 ms resident | ✅ |
| `disabledynamictick` | `bcdedit {current}` | `Yes` | ✅ 🔒 |
| `useplatformclock` | `bcdedit {current}` | *unset* | ❌ forces HPET, harmful |

`CoalescingTimerInterval = 0` is written to **all seven** of these — missing any one leaves
coalescing partly active:

```
HKLM\SYSTEM\CCS\Control\Session Manager\kernel
HKLM\SYSTEM\CCS\Control\Session Manager\Power
HKLM\SYSTEM\CCS\Control\Session Manager\Memory Management
HKLM\SYSTEM\CCS\Control\Session Manager\Executive
HKLM\SYSTEM\CCS\Control\Session Manager
HKLM\SYSTEM\CCS\Control\Power
HKLM\SYSTEM\CCS\Control
```

---

## 2. CPU / scheduler / power

| Setting | Value | |
|---|---|---|
| `SvcHostSplitThresholdInKB` | `3670016` | ✅ 🔒 **the BSOD fix** |
| `Win32PrioritySeparation` | `36` | ✅ |
| Core parking min, **Class 0** (E-cores) | `100` | ✅ |
| Core parking min, **Class 1** (P-cores) | `100` | ✅ **hidden by default** |
| Core parking max, Class 0 and Class 1 | `100` | ✅ |
| `IDLEDISABLE` (C-states) | `1` | ⚠️ desktop only |
| `PROCTHROTTLEMIN` / `PROCTHROTTLEMAX` | `100` / `100` | ✅ |
| `PERFBOOSTMODE` | `2` (Aggressive) | ✅ |
| `PowerThrottlingOff` | `1` | ✅ |
| Power scheme | Ultimate Performance | ✅ |
| `DISKIDLE` | `0` | ✅ NVMe never sleeps |
| Hibernation | off | ⚠️ desktop only |
| PCIe ASPM | `0` (Off) | ✅ already stock here |

**Unhide the hidden power settings** before any of the parking values will apply:

```powershell
Set-ItemProperty "$sub\<setting-guid>" -Name Attributes -Value 2 -Type DWord -Force
```

Applies to: `CPMINCORES`, `CPMAXCORES`, `IDLEDISABLE`, `PERFBOOSTMODE`, and both Class 1 variants.

---

## 3. GPU / display

| Setting | Path | Value | |
|---|---|---|---|
| `OverlayTestMode` (MPO off) | `HKLM\SOFTWARE\Microsoft\Windows\Dwm` | `5` | ✅ **correct key** |
| `OverlayTestMode` | `...Control\GraphicsDrivers` | *removed* | ❌ inert, wrong key |
| `RmGpsPsEnablePerCpuCoreDpc` | `...Control\GraphicsDrivers` | `1` | ✅ |
| `HwSchMode` (HAGS) | `...Control\GraphicsDrivers` | `2` | ✅ |
| `VsyncIdleTimeout` | `...GraphicsDrivers\Scheduler` | `0` | ✅ |
| `DisableDynamicPstate` | NVIDIA class key | `1` | ✅ locks max clocks |
| `LOWLATENCY` | NVIDIA class key `\0000` | `1` | ✅ |
| `Node3DLowLatency` | NVIDIA class key `\0000` | `1` | ✅ |
| `D3PCLatency` | NVIDIA class key `\0000` | `1` | ✅ |
| `TransitionLatency` | NVIDIA class key `\0000` | `1` | ✅ |
| `vrrCursorMarginUs` | NVIDIA class key `\0000` | `1` | ✅ |
| `vrrDeflickerMarginUs` | NVIDIA class key `\0000` | `1` | ✅ |
| `vrrDeflickerMaxUs` | NVIDIA class key `\0000` | `1` | ✅ |
| `Display%MonitorAmount%_PipeOptimizationEnable` | `...Services\nvlddmkm` | `1` | ✅ |
| `GpuEnergyDrv` service | `Start` | `4` | ✅ |
| NVIDIA telemetry `EnableRID44231` / `64640` / `66610` | `...NVIDIA Corporation\Global\FTS` | `0` | ✅ |
| GPU interrupt affinity | `DevicePolicy 4`, mask CPU 14 | measured | ✅ |
| `TdrDelay` / `TdrDdiDelay` / `TdrLevel` | — | *left stock* | ❌ no benefit |

**NVIDIA class key** = `HKLM\SYSTEM\CCS\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}`

---

## 4. Memory / filesystem

| Setting | Value | |
|---|---|---|
| `LargeSystemCache` | `0` | ✅ favour apps over file cache |
| `DisablePagingExecutive` | `1` | ✅ kernel stays resident |
| `MemoryCompression` (MMAgent) | `False` | ⚠️ needs 16GB+ |
| `NtfsMemoryUsage` | *removed* | ❌ paged-pool pressure, no gain |
| `NTFSDisable8dot3NameCreation` | `1` | ✅ no short-name generation |
| `NtfsMftZoneReservation` | `1` | ✅ |
| `ContigFileAllocSize` | `100` | ✅ |
| `LongPathsEnabled` | `1` | ✅ QoL, no perf effect |
| `disableLastAccess` | `2` | ✅ fewer SSD writes |
| `SysMain` (Superfetch) | Disabled | ✅ |
| `WSearch` (Indexing) | Disabled | ✅ |

---

## 5. Network

| Setting | Value | |
|---|---|---|
| Interrupt Moderation | Disabled | ✅ |
| Interrupt Moderation Rate | Off | ✅ |
| Flow Control | Disabled | ✅ |
| Receive / Transmit Buffers | `1024` / `1024` | ✅ |
| Speed & Duplex | 2.5 Gbps Full | ✅ |
| `*RSS` | `1` | ✅ |
| `*NumRssQueues` | `4` | ✅ |
| `*RSSProfile` | `4` | ✅ |
| `*RssBaseProcNumber` | `0` | ✅ |
| `*MaxRssProcessors` | `4` | ✅ |
| NIC power management | AllowComputerToTurnOff = **Disabled** | ✅ |
| `NetworkThrottlingIndex` | `10` | ✅ *(not `0xFFFFFFFF`)* |
| `SystemResponsiveness` | `0` | ✅ |
| `TcpAckFrequency` | `1` — **all 7 interfaces** | ✅ |
| `TCPNoDelay` | `1` — **all 7 interfaces** | ✅ |
| `DelayedAckFrequency` | `1` | ✅ |
| `DelayedAckTicks` | `1` | ✅ |
| `Tcp1323Opts` | *removed* | ❌ **disabled window scaling** |
| `InitialRto` | `1000` (from 3000) | ✅ |
| TCP `FastCopyReceiveThreshold` | `16384` | ✅ |
| TCP `FastSendDatagramThreshold` | `16384` | ✅ |
| `Ndu` service | `Start = 4` | ✅ DPC contributor |

### AFD (Winsock) — all seven values

```
DefaultReceiveWindow             16384
DefaultSendWindow                16384
FastCopyReceiveThreshold         16384
FastSendDatagramThreshold        16384
DynamicSendBufferDisable         0
IgnorePushBitOnReceives          1
NonBlockingSendSpecialBuffering  1
```

### TCP/IP ServiceProvider priorities

```
LocalPriority   4        HostsPriority   5
DnsPriority     6        NetbtPriority   7
```

### QoS policies

| Policy | Effect | |
|---|---|---|
| `FN-UploadShaper` | Default policy, throttle **18 Mbps** outbound | ✅ anti-bufferbloat |
| `FortniteUDP-EF` | App-match `FortniteClient-Win64-Shipping.exe`, UDP, **DSCP 46** | ✅ |

These are complementary, not conflicting — the app-specific policy exempts the game from the
default shaper *and* marks it Expedited Forwarding.

---

## 6. Input

| Setting | Value | |
|---|---|---|
| USB selective suspend | Disabled — **61 devices** | ✅ |
| USB `EnhancedPowerManagementEnabled` | `0` | ✅ |
| Power-scheme USB selective suspend | `0` | ✅ |
| `MouseSpeed` / `MouseThreshold1` / `MouseThreshold2` | `0` / `0` / `0` | ✅ 1:1, no accel |
| `MouseSensitivity` | `10` | ✅ 1:1 |
| `LowLevelHooksTimeout` | `1000` | ✅ **genuine input tweak** |
| `MenuShowDelay` | `0` | ✅ |
| `HungAppTimeout` | `1000` → **`5000`** | ❌ reverted to stock |
| `WaitToKillAppTimeout` | `2000` → **`5000`** | ❌ reverted to stock |
| `AutoEndTasks` | `1` → **`0`** | ❌ reverted to stock |
| `WaitToKillServiceTimeout` | *removed* | ❌ was inert `REG_DWORD` anyway |
| StickyKeys `Flags` | `506` | ✅ shortcut disabled |
| `UserDuckingPreference` | `3` | ✅ no audio ducking on Discord voice |

---

## 7. Services disabled

| Service | Why |
|---|---|
| `DiagTrack` | Telemetry |
| `dmwappushservice` | Telemetry |
| `WerSvc` | Error reporting |
| `PcaSvc` | Program Compatibility Assistant |
| `TrkWks` | Distributed Link Tracking |
| `GpuEnergyDrv` | GPU energy driver |
| `Ndu` | Network Data Usage — DPC contributor |
| `SysMain` | Superfetch |
| `WSearch` | Search indexing |
| `Spooler` | Print spooler (no printer) |
| `WMPNetworkSvc` | WMP sharing |
| `SensrSvc` | Sensors (desktop) |
| `wisvc` | Insider service |
| `XblAuthManager`, `XblGameSave`, `XboxGipSvc`, `XboxNetApiSvc` | Xbox stack |
| **`wuauserv`** | Windows Update |
| **`UsoSvc`** | Update Orchestrator |
| **`DoSvc`** | Delivery Optimization — the actual downloader |
| **`WaaSMedicSvc`** | **Self-heal — silently re-enables the other three** |

`WaaSMedicSvc` is the one everyone misses. Without disabling it, the other three quietly come back.

---

## 8. Scheduled tasks disabled

**Telemetry (15, re-checked every logon because Windows re-enables them):**
```
Application Experience\Microsoft Compatibility Appraiser
Application Experience\ProgramDataUpdater
Application Experience\StartupAppTask
Customer Experience Improvement Program\Consolidator
Customer Experience Improvement Program\UsbCeip
Customer Experience Improvement Program\KernelCeipTask
Feedback\Siuf\DmClient
Feedback\Siuf\DmClientOnScenarioDownload
Windows Error Reporting\QueueReporting
Autochk\Proxy
DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector
DiskFootprint\Diagnostics
Power Efficiency Diagnostics\AnalyzeSystem
Shell\FamilySafetyMonitor
Shell\FamilySafetyRefreshTask
```

**Maintenance:** `Maintenance\WinSAT`, `Defrag\ScheduledDefrag`, `Maps\MapsUpdateTask`

**Update / reboot:** `UpdateOrchestrator\Reboot_AC`, `UpdateOrchestrator\Reboot_Battery`,
`UpdateOrchestrator\Schedule Scan`, `WindowsUpdate\Scheduled Start`

> Several `UpdateOrchestrator` tasks are owned by TrustedInstaller and refuse to disable even
> elevated. That's fine — with the services disabled they can't do anything.

---

## 9. Telemetry / privacy / noise

| Setting | Value |
|---|---|
| `AllowTelemetry` | `0` |
| `AdvertisingInfo\Enabled` | `0` |
| `DisableWindowsConsumerFeatures` | `1` |
| `BingSearchEnabled` | `0` |
| `ToastEnabled` / `LockScreenToastEnabled` | `0` |
| `Maps\AutoUpdateEnabled` | `0` |
| Remote Assistance `fAllowFullControl` / `fAllowToGetHelp` | `0` |
| `DisableAutomaticRestartSignOn` | `1` |
| `DelayedDesktopSwitchTimeout` | `0` |
| `NoAutoUpdate` / `AUOptions` / `NoAutoRebootWithLoggedOnUsers` | `1` / `1` / `1` |
| Active hours | 08:00–02:00 |
| SmartScreen | `Off` — deliberate user choice |
| **`mpcmdrun.exe` IFEO `Debugger`** | **removed** — pointed Defender's scanner at `systray.exe` |

---

## 10. MMCSS

| Task profile | Setting | Value |
|---|---|---|
| `SystemProfile` | `SystemResponsiveness` | `0` |
| `SystemProfile` | `NetworkThrottlingIndex` | `10` |
| `SystemProfile` | `NoLazyMode` | `1` |
| `Tasks\Games` | `GPU Priority` | `8` |
| `Tasks\Games` | `Priority` | `6` |
| `Tasks\Games` | `Scheduling Category` | `High` |
| `Tasks\DisplayPostProcessing` | `Priority` | `8` |
| `Tasks\DisplayPostProcessing` | `GPU Priority` | `18` |
| `Tasks\DisplayPostProcessing` | `Scheduling Category` | `High` |
| `Tasks\DisplayPostProcessing` | `SFIO Priority` | `High` |
| `Tasks\DisplayPostProcessing` | `Latency Sensitive` | `True` |

Also: **Fault Tolerant Heap** (`FTH\Enabled = 0`) — stops Windows silently applying compatibility
shims to a repeatedly-crashing game.

---

## 11. Game (Fortnite)

**IFEO priority** — `FortniteClient-Win64-Shipping.exe\PerfOptions`: `CpuPriorityClass=3` (High),
`IoPriority=3`. Verified holding `High` through a full match.

**`GameUserSettings.ini`:**
```
FrameRateLimit          = 800.000000     was 0 (which behaved as capped)
FrontendFrameRateLimit  = 480            was 60  <- this was the real "60 FPS cap"
bUseVSync               = False
LowInputLatencyModeIsEnabled = True
PreferredFullscreenMode = 1              windowed fullscreen, user preference
```

> The `FrontendFrameRateLimit = 60` was the actual cause of a reported "0 caps me at 60 FPS".
> Easy to miss because it's a *separate* key from the main frame limit.

**`Engine.ini` overlay — file set READ-ONLY:**
```ini
[/Script/Engine.RendererSettings]
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
```
Removed in v2: `r.OneFrameThreadLag=0`, `r.GTSyncType=1` — cost 480 → 300-400 FPS.

**GameDVR / fullscreen optimizations (six keys):**
```
GameDVR_Enabled=0                        GameDVR_FSEBehaviorMode=2
GameDVR_FSEBehavior=2                    GameDVR_DSEBehavior=2
GameDVR_HonorUserFSEBehaviorMode=1       GameDVR_DXGIHonorFSEWindowsCompatible=1
GameDVR_EFSEFeatureFlags=0
AllowGameDVR=0 (policy)                  AppCaptureEnabled=0
```

**Game Bar:** `AllowAutoGameMode=1`, `AutoGameModeEnabled=1`, `UseNexusForGameBarEnabled=0`,
`ShowStartupPanel=0`

---

## 12. Application-level tweaks

### Discord
```
audioSubsystem      "experimental" -> "standard"     classic cause of voice crackle/dropouts
offloadAdmControls  true -> false
```
Config lives at `%APPDATA%\discord\settings.json`. Discord must be closed — it rewrites on exit.

### AntiMicro (controller remapper)
```
HistorySize                10 -> 1     smoothing BUFFER - averaged input over 10 samples
WeightModifier            0.2 -> 0     weighted averaging off, raw passthrough
DisableWinEnhancedPointer   0 -> 1
Smoothing                   0          already correct
GamepadPollRate             1          already optimal - 1ms is the floor
KeyRepeatDelay/Rate    250 / 20        left alone - changes behaviour, not latency
```

**Gotcha:** AntiMicro from the Microsoft Store is MSIX-packaged, so its config is **not** at
`%APPDATA%\antimicrox`. The real path is:
```
%LOCALAPPDATA%\Packages\<pkg>\LocalCache\Local\antimicro\antimicro_settings.ini
```

### Desktop shortcuts — `.url` → `.lnk`
`.url` internet shortcuts replaced with real `.lnk` files that launch the game directly:
```
Steam:  "C:\Program Files (x86)\Steam\steam.exe"  -applaunch <appid>
Epic:   "...\EpicGamesLauncher.exe"  com.epicgames.launcher://apps/<id>?action=launch&silent=true
```
Original game icons preserved via `IconLocation`.

---

## 13. Background process affinity

Pinned to **E-cores** (CPU 16–31) so they never compete with the game's P-cores:

```
Discord, discord_clips, DiscordSystemHelper, DiscordCanary, DiscordPTB
Spotify, Notion, steam, steamwebhelper, steamservice
EpicWebHelper, Voicemod, VoicemodDesktop, antimicrox
msedge, chrome, firefox, RtkAudUService64, SearchIndexer, OneDrive, RustDesk
```

**Added later** — these were running uncontested on P-cores and are easy to miss:
```
EOSOverlayRenderer-Win64-Shipping   (5 separate processes!)
EpicOnlineServicesUserHelper
gamingservices, gamingservicesnet
MoUsoCoreWorker
SearchApp
```

**Never pinned** — pinning these caused real regressions:
```
nvcontainer, NVDisplay.Container, nvsphelper64, NVIDIA Share, NVIDIA Web Helper,
nvcplui, nvtelemetrycontainer, dwm, audiodg, csrss, winlogon, explorer,
GameInputSvc, GameInputRedistService, EpicGamesLauncher
```

> Pinning `nvcontainer` / `NVDisplay.Container` to E-cores starved the display pipeline and
> produced stutter plus fullscreen focus loss. `dwm` is the compositor, `audiodg` the audio graph.
> Don't pin any of them.

Affinity is per-process and resets on spawn, so a watcher re-applies it every 15s (5s in-game).

**Affinity mask gotcha:** PowerShell parses `0xFFFF0000` as a *negative* Int32 and the setter
rejects it. Use:
```powershell
$E_CORES = [IntPtr][int64]4294901760
```

---

## 14. Persistence

Two scheduled tasks, both **at logon, RunLevel Highest**, with **non-overlapping ownership**:

| Task | Owns |
|---|---|
| `LatencyLab-Boot` | timer, priority separation, MPO, GPU/NVIDIA, NIC RSS, QoS, telemetry, FSE, FTH, `Engine.ini`, E-core pinning |
| `LatencyLab-AllInOne` | svchost threshold, core parking, C-states, memory, filesystem/TCP, `Ndu`, SmartScreen, kill timeouts, Windows Update |
| `LatencyLab-TimerResolution` | keeps `SetTimerResolution.exe` resident |

Plus an in-game watcher that detects Fortnite launch/exit, tightens the affinity loop to 5s,
closes Spotify, monitors downlink saturation, and restores `Engine.ini` on exit.

**Escape hatch:** `C:\LatencyLab\WINDOWS_UPDATE_ENABLED` — if that file exists, the Windows Update
block is skipped entirely.

---

## 15. Things deliberately NOT done

| Not done | Why |
|---|---|
| NIC interrupt affinity pinning | Measured DPC 0.243% avg — no contention to fix, and it would override working RSS |
| Clearing the 6.4 GB NVIDIA shader cache | Large cache = fewer recompiles. Clearing causes stutter for no lasting gain |
| Disabling E-cores in BIOS | Pinning background apps to them is strictly better |
| CPU affinity restriction on the game | Thread Director handles hybrid scheduling better than a static mask |
| PresentMon / ETW capture | BattlEye monitors ETW sessions. Not worth the risk for a frametime graph |
| Killing Voicemod | 340 MB in the audio path, but it's pinned to E-cores and killing it drops the mic mid-session |
| Metered connection flag | `DefaultMediaCost` is owned by TrustedInstaller; unnecessary once the services are disabled |
