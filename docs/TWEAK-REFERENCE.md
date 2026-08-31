# Tweak Reference

Every setting evaluated, with a verdict. Measured on i9-13900KF / RTX 4070 / 500Hz / Win10 19045.

Legend: **KEEP** = real, measurable benefit · **REMOVE** = no benefit or actively harmful ·
**REJECT** = commonly recommended, does not survive scrutiny

---

## Critical — fixes a crash

| Setting | Value | Verdict | Why |
|---|---|---|---|
| `SvcHostSplitThresholdInKB` | `3670016` | **KEEP** | 32GB value caused `CRITICAL_PROCESS_DIED` boot loop. Stock value. Zero perf cost |

---

## CPU / scheduler

| Setting | Value | Verdict | Why |
|---|---|---|---|
| Core parking Class 0 (E-cores) | `100` | **KEEP** | Keeps E-cores unparked |
| Core parking Class 1 (P-cores) | `100` | **KEEP** | **The one everyone misses.** Hidden by default; without it all 8 P-cores park |
| `IDLEDISABLE` (C-states) | `1` | **KEEP** | No core sleep = no wake latency. Costs idle power/heat. Verify no WHEA errors after |
| `Win32PrioritySeparation` | `36` | **KEEP** | Short quantum, foreground boost. Standard competitive value |
| `PROCTHROTTLEMIN` | `100` | **KEEP** | CPU never downclocks. Watch thermals on a 200W+ chip |
| `PERFBOOSTMODE` | `2` (Aggressive) | **KEEP** | Longer turbo residency |
| Fortnite IFEO `CpuPriorityClass` | `3` (High) | **KEEP** | Verified live: priority held `High` through a full match |
| `csrss.exe` IFEO `PerfOptions` | *removed* | **REMOVE** | csrss already runs high priority. No measurable gain |
| Affinity `0x555` (pin to 6 cores) | *never applied* | **REJECT** | Catastrophic on a 32-thread CPU. Correctly skipped by the original pack |
| Disabling E-cores in BIOS | *not done* | **REJECT** | [TechPowerUp 53-game test](https://www.techpowerup.com/review/rtx-4090-53-games-core-i9-13900k-e-cores-enabled-vs-disabled/): mostly a wash. Pinning background apps to them is strictly better |

---

## Timer

| Setting | Value | Verdict | Why |
|---|---|---|---|
| `SetTimerResolution` 0.5ms | resident | **KEEP** | Verified active: `NtQueryTimerResolution` reports **0.4999 ms** |
| `GlobalTimerResolutionRequests` | `1` | **KEEP** | Lets the request apply process-wide |
| `DistributeTimers` | `1` | **KEEP** | Spreads timer interrupts |
| `CoalescingTimerInterval` | `0` | **KEEP** | No timer coalescing |
| `disabledynamictick` | `Yes` | **KEEP** | Constant tick rate |
| `useplatformclock` | *unset* | **REJECT** | Forces HPET. **Actively harmful** on modern Intel. Leaving unset is correct |

---

## GPU / display

| Setting | Value | Verdict | Why |
|---|---|---|---|
| `OverlayTestMode` (MPO off) | `5` in `HKLM\SOFTWARE\Microsoft\Windows\Dwm` | **KEEP** | Fixes DWM stutter/flicker. **Location matters** |
| `OverlayTestMode` in `GraphicsDrivers` | *removed* | **REMOVE** | Wrong key. Inert. A pack wrote it here and it did nothing |
| `DisableDynamicPstate` | `1` | **KEEP** | GPU locked at max clocks |
| `LOWLATENCY` | `1` | **KEEP** | NVIDIA low-latency path |
| HAGS (`HwSchMode`) | `2` (On) | **KEEP** | Prerequisite for full Reflex benefit — *but see FPS cap below* |
| `RmGpsPsEnablePerCpuCoreDpc` | `1` | **KEEP** | Per-core GPU DPC |
| TDR `4/4/3` | *left stock* | **REJECT** | No FPS benefit. The source pack's own logs contradicted themselves (`4/4/3` vs `8/8/3`) |
| GPU interrupt affinity → CPU 14 | `DevicePolicy 4` | **KEEP** | Measured: CPU 14 at 0.94% DPC vs CPU 8 at 1.56%. Deliberate, leave it |

---

## Memory / filesystem

| Setting | Value | Verdict | Why |
|---|---|---|---|
| `LargeSystemCache` | `0` | **KEEP** | Favors app working set over file cache |
| `DisablePagingExecutive` | `1` | **KEEP** | Kernel stays resident. Negligible but harmless on 32GB |
| `MemoryCompression` | `False` | **KEEP** | Saves CPU on a machine with RAM to spare |
| `NtfsMemoryUsage` | *removed* | **REMOVE** | Raises paged-pool pressure for no measurable gain |

---

## Network

| Setting | Value | Verdict | Why |
|---|---|---|---|
| Interrupt Moderation | `Disabled` | **KEEP** | Lower DPC latency for small UDP packets |
| Flow Control | `Disabled` | **KEEP** | No pause frames |
| RSS, 4 queues | enabled | **KEEP** | Spreads receive processing |
| `TcpAckFrequency` / `TCPNoDelay` | `1` / `1` | **KEEP** | Nagle off |
| `NetworkThrottlingIndex` | `10` | **KEEP** | Windows default. With `SystemResponsiveness=0` the throttle window is already minimal |
| `NetworkThrottlingIndex = 0xFFFFFFFF` | *rejected* | **REJECT** | Removes DPC pacing for no measured gain. Was one half of a two-pack conflict |
| `Tcp1323Opts` | *removed* | **REMOVE** | `0` **disables TCP window scaling** — actively hurts a 2.5 Gbps link |
| `Ndu` service | `Start = 4` | **KEEP** | Documented DPC latency contributor. Only powers Settings › Data usage |
| AFD buffers `16384` | kept | **NEUTRAL** | Harmless. Placebo for a UDP game — these are TCP socket buffers |
| QoS DSCP 46 for Fortnite | policy | **KEEP** | Also exempts the game from the default upload shaper |

---

## Input

| Setting | Value | Verdict | Why |
|---|---|---|---|
| USB selective suspend | disabled, 61 devices | **KEEP** | No wake latency on input |
| `MouseSpeed` / `Threshold1` / `Threshold2` | `0/0/0` | **KEEP** | 1:1, pointer acceleration off |
| `LowLevelHooksTimeout` | `1000` | **KEEP** | Drops a hung mouse/kbd hook faster. Genuine input-path tweak |
| `HungAppTimeout` `1000`, `AutoEndTasks` `1` | *reverted to stock* | **REMOVE** | Can force-kill the game on a brief shader-compile hang. Zero FPS benefit |
| `WaitToKillServiceTimeout` `2000` | *removed* | **REMOVE** | Both packs wrote it as `REG_DWORD`. **Windows only reads it as `REG_SZ`** — it was silently inert the whole time |
| AntiMicro `HistorySize` | `10 → 1` | **KEEP** | It averaged input across 10 samples before output. Real added lag |
| AntiMicro `WeightModifier` | `0.2 → 0` | **KEEP** | Weighted smoothing off, raw passthrough |
| AntiMicro `GamepadPollRate` | `1` | **already optimal** | 1ms is the floor |

---

## Fortnite

| Setting | Value | Verdict | Why |
|---|---|---|---|
| `r.Streaming.PoolSize` | `4096` | **KEEP** | Prevents texture eviction on a 12GB card |
| `r.Nanite` | `0` | **KEEP** | Performance mode disables it anyway |
| `r.HZBOcclusion` | `1` | **KEEP** | Cheaper occlusion culling |
| `r.VRS.Enable` | `1` | **KEEP** | Variable rate shading |
| `r.OneFrameThreadLag` | `0` → **removed** | **REMOVE** | **Measured: 480 FPS → 300–400.** Saves ~1 frame of lag but costs 1.25ms on *every* frame at 500Hz. Net loss |
| `r.GTSyncType` | `1` → **removed** | **REMOVE** | Same reason — throttles CPU run-ahead |
| `Engine.ini` **read-only** | required | **KEEP** | Fortnite deletes/rewrites this file on every launch. Read-only is the only thing that makes an overlay survive |
| `FrameRateLimit` | `800` | **KEEP** | Above 500Hz refresh, extra frames don't display but the displayed frame is fresher |
| Deadzone (Hall-effect pad) | `3–5%` | **KEEP** | Hall sticks don't drift. Stock pads need 10–15%, wasting the low end of stick travel where tracking lives |

---

## Not a PC problem

| Issue | Finding |
|---|---|
| Downlink saturation | Measured **330 Mbps peaks** mid-match, ping spiking to ~500–800ms. Windows **cannot** rate-limit inbound traffic — the queue fills upstream at the ISP. Needs router-level SQM. No registry tweak touches this |
| Windows Update | `MoUsoCoreWorker` downloading at full line speed during matches. Disabling `wuauserv` + `UsoSvc` + `DoSvc` + **`WaaSMedicSvc`** stops it. `WaaSMedicSvc` is the self-heal service that silently re-enables the rest |
