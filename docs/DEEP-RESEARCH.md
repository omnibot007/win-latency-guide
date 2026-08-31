# Deep Research Round

Findings from a wide survey of primary sources — driver registry enumerations, vendor
documentation, and measurement-driven repos — rather than the usual recycled tweak lists.

**Sources that actually mattered:** [djdallmann/GamingPCSetup](https://github.com/djdallmann/GamingPCSetup)
raw driver enumerations (`mmcss`, `nvlddmkm`, `stornvme`, `dwm`, `ndis`, `mouclass`, `kbdclass`,
display-adapter class) · [valleyofdoom/PC-Tuning](https://github.com/valleyofdoom/PC-Tuning) ·
[BoringBoredom/PC-Optimization-Hub](https://github.com/BoringBoredom/PC-Optimization-Hub) ·
[Epic's Low-Latency Frame Syncing docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/low-latency-frame-syncing-in-unreal-engine) ·
Microsoft audio idle-timer and MMCSS docs · NVIDIA `open-gpu-kernel-modules/nvrm_registry.h`

---

## 1. A bug in this repo's own script — found by an outside AI

`AllInOne-Apply.ps1` had **the entire script duplicated inside itself.** A `-replace` used to
insert a Windows Update block mangled `$($_.Exception.Message)` and pasted the whole file body
inside the `$(...)` subexpression:

```powershell
} catch { Log "WU disable FAILED: $(<#
   ...entire 150-line script pasted here...
.Exception.Message)" }
```

**It passed `Parser::ParseFile` cleanly**, which is what made it dangerous — a silent landmine. If
that catch ever fired, the whole optimisation script would re-execute nested inside a log string.

Fixed: 330 lines → 190. One `.SYNOPSIS`, one start marker, one end marker.

> **Lesson:** a syntax check proves a file *parses*, not that it's *correct*. Add structural
> assertions — marker counts, section counts — not just a parse.

---

## 2. MMCSS `Games` profile was incomplete on the reference machine

Every MMCSS task profile, side by side:

| Profile | Values |
|---|---|
| DisplayPostProcessing | 9 |
| Playback | 8 |
| Audio / Capture / Distribution / Pro Audio / Window Manager | 7 |
| **Games** | **3 usable + 2 misplaced** |

`Games` was missing `Affinity`, `Background Only`, `Clock Rate`, `SFIO Priority`, and
`Latency Sensitive` — while `DisplayPostProcessing` had `Latency Sensitive=True` and
`SFIO Priority=High`. The *video post-processing* task was better configured than the task games
actually run under.

### Two values were in the wrong key entirely

```
Tasks\Games\NetworkThrottlingIndex = 4294967295    <- inert here
Tasks\Games\SystemResponsiveness   = 0             <- inert here
```

Those belong at `...\Multimedia\SystemProfile`, **not** in a task subkey. Note the value:
`0xFFFFFFFF` — the exact `NetworkThrottlingIndex` this repo rejects, sitting inertly in a path
nothing reads. Removed.

**Correct `Games` profile:**
```
Scheduling Category = High     GPU Priority = 8      Priority = 6
Affinity = 0                   Background Only = False
Clock Rate = 10000             SFIO Priority = High  Latency Sensitive = True
```

> `Latency Sensitive` is documented as functional. `SFIO Priority` is questioned even by
> djdallmann — Microsoft's own docs suggest it may do nothing. Applied because it is zero-risk,
> not because it is proven.

---

## 3. Frame cap must be refresh-locked

**Cap at `refresh × N` or `refresh ÷ N`, N a positive integer.** Off-multiple caps mistime frames
against scan-out.

On a 500 Hz panel: `500`, `250`, `1000` are valid. **`800` (1.6×) and `480` (0.96×) are not.**

This repo previously recommended 480, then 800. Both wrong. Corrected to **500**.

---

## 4. `GlobalTimerResolutionRequests` does nothing on Windows 10

Windows 10 2004+ made timer resolution **per-process** — a tool holding 0.5 ms no longer grants it
system-wide. The registry key that restores global behaviour is **Windows 11 / Server 2022+ only.**

On Win10 the correct approach is a resident holder process (`SetTimerResolution.exe`, ISLC), which
is what the reference machine already does. The registry key beside it is inert.

> Blur Busters measurement: **0.5 ms vs 1 ms differs by ~0.0 µs in standard deviation.** The 0.5 ms
> fixation is folklore. What matters is that *something* holds a request.

---

## 5. Epic's own docs contradict the popular Fortnite tweak

Every Fortnite guide says `r.OneFrameThreadLag=0`. **Epic's low-latency configuration says
`r.OneFrameThreadLag = 1`:**

```
r.GTSyncType    = 2      sync to swap-chain present ± offset
rhi.SyncSlackMS = 0      minimise - THIS is the real latency control
r.OneFrameThreadLag = 1
```

`rhi.SyncSlackMS` is the actual input-latency knob in Unreal and appears in almost no tweak guide.
Epic also documents a **deadlock** with `VSync=1` + `GTSyncType=2` + `OneFrameThreadLag=0`.

Measured cost of `OneFrameThreadLag=0` on the reference rig: **480 FPS → 300–400.** Removed.

---

## 6. Undocumented surfaces catalogued (not applied)

Enumerated from driver key dumps. **None applied** — no public documentation exists for their
value semantics, and writing guessed values into a driver's binary settings database is exactly
what this repo forbids.

**Display adapter class** — flip path:
```
VRDirectJITFlipEnable · VRDirectFlipTimingMarginUs · VRDirectFlipDPCDelayUs
enableRS2VSyncToImmediateFlipConversion · enableRS2ImmediateFlipCompletionReporting
enableRS4ContextlessPresent · WaitForFirstFlip · RmDefaultPbTimeslice
RMDeepL1EntryLatencyUsec · PStateTriggerIdleTimeoutMs · PowerMizer* (7 keys)
```

**`stornvme`** — 43 device parameters, typically 3 set:
```
InterruptCoalescingTime · InterruptCoalescingEntry · IoCompletionCapInDPC
IoPollingInterval · IdlePowerMode · MedPowerD3IdleTimeout · IoLatencyCap
```

**DWM:** `DisableIndependentFlip`, `DisableAdvancedDirectFlip`, `ParallelModePolicy`,
`OverlayQualifyInterval/Count` — independent flip is what lets a *windowed* app bypass composition.

**MMCSS internals:** `LazyModeTimeout` (default 1,000,000 = 100 ms), `IdleDetectionCycles`,
`Priority When Yielded`, `SchedulerPeriod`

**NDIS:** `ReceiveWorkerThreadPriority` (left unset — undocumented scale), `DisableNaps` (applied)

**Authoritative source for NVIDIA keys:** `NVIDIA/open-gpu-kernel-modules/src/nvidia/interface/nvrm_registry.h`

---

## 7. Rejected — with reasons

| Tweak | Why rejected |
|---|---|
| `DpcWatchdogPeriod=0`, `DpcTimeout=0` | **Disables crash detection, not latency.** A hung DPC becomes an undiagnosable freeze instead of a bugcheck |
| `TdrLevel=0` | Same class — removes GPU timeout recovery. A driver hang becomes a hard lock |
| `IRQ8Priority` / `IRQ0Priority` | **The string does not exist in the Windows kernel binary.** NT stopped using IRQ8 for timekeeping decades ago |
| Spectre/Meltdown disable | Real on Skylake. On 12th/13th gen, Meltdown/MDS/Downfall are fixed *in silicon* and Spectre v2 uses hardware eIBRS — gains ≈ 0–2%, inside noise |
| Disabling LSO / checksum offload | Gains are *"tiny fractions of 1 ms"* against a 20 ms server ping, and wastes CPU |
| `useplatformclock` | Forces HPET — actively harmful on modern CPUs |

---

## 8. Contested — flagged, not resolved

**`disabledynamictick yes`** — multiple Blur Busters and Overclock.net threads report it *adding*
input lag and desync, with the mouse merely *feeling* more consistent. Widely recommended,
genuinely disputed. Needs a controlled A/B on your own hardware.

**VRR** — BoringBoredom: *"VRR increases input lag compared to properly capped FPS."* With a
correct refresh-locked cap, VRR may be working against you.

**C-states** — this repo disables them. Intel's post-instability guidance for 13th/14th gen says
they should be **enabled**, and AMD X3D parts boost better when cores can idle. Two independent
routes to "leave them on." Unresolved; gated behind a laptop/WHEA check, but worth revisiting on
13th gen desktops too.
