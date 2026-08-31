# Baseline: what "good" actually looks like

Real numbers from the reference machine, so you have something to compare your own audit against.
Every figure here was measured, not estimated.

**Rig:** i9-13900KF (8P/16E) · RTX 4070 12GB · 32GB DDR5 · Intel I225-V 2.5GbE · 500Hz @ 1600x900 ·
Win10 19045

---

## Before / after on the fixes that mattered

| Metric | Broken | Fixed |
|---|---|---|
| `svchost.exe` instances | **19** | **55** |
| Critical services sharing one PID | **7** (`DcomLaunch`, `LSM`, `Power`, `PlugPlay`, `BrokerInfrastructure`, `SystemEventsBroker`, `DeviceInstall`) | spread over **4 PIDs** |
| Cores parked (idle) | **16 of 32** — every P-core | **0 of 32** |
| Bugchecks | `0x000000EF` boot loop | none across 3+ clean boots |
| Timer resolution | — | **0.4999 ms** |

If your audit shows fewer than ~40 `svchost` processes, or any cores parked at idle on a desktop,
you have the same problems this repo fixes.

---

## A full match, sampled every 2s (295 samples)

```
PING     avg=22.4ms  min=16ms  max=37ms  p95=27ms
SPIKES >3x average:  0 of 295
DOWNLINK avg=10.4 Mbps   peak=330.4 Mbps
SATURATED (>100Mbps) in 13 of 295 samples
CPU      avg=19%    peak=31.4%
DPC      avg=0.243% peak=1.212%
PARKED CORES peak=0
GAME PRIORITY: High (held for the entire match)
```

### Reading it

**CPU at 19% average** — the machine is nowhere near CPU-bound. If yours is pegged at 80%+ during a
match, your bottleneck is CPU, and latency micro-tweaks won't help until that's addressed.

**DPC at 0.243% average** — excellent. This is the number that tells you whether interrupt tuning is
worth doing at all.

| DPC average | What it means |
|---|---|
| **< 1%** | No contention. **Do not** pin interrupt affinity — nothing to fix |
| 1–3% | Moderate. Worth investigating which driver |
| **> 3%** | Real problem. Use LatencyMon to find the driver |

**0 parked cores throughout** — parking stayed off under real load, not just at idle.

**Priority held `High`** — the IFEO priority setting actually persisted through a full match rather
than being reset.

**13 of 295 samples saturated** — this is the one bad number, and it isn't the PC's fault. See below.

---

## The bottleneck that isn't the PC

```
DOWNLINK peak: 330.4 Mbps    saturated in 13 of 295 samples
```

Ping held at ~22ms during this particular run, but the machine's logs caught spikes to ~500ms
whenever saturation coincided with a fight:

```
!! DOWNLINK LOADED 169 Mbps WHILE IN MATCH - expect ping spikes up to ~500ms
!! DOWNLINK LOADED 252 Mbps WHILE IN MATCH
```

The culprit was **Windows Update** (`MoUsoCoreWorker`) downloading at full line speed.

**Windows cannot rate-limit inbound traffic.** The queue that fills lives upstream at the ISP, past
your NIC. No registry tweak reaches it. The real fixes are router-level SQM, or removing the source
of the traffic.

In a server-authoritative game, whoever's packet arrives first wins the contested action. Half a
second of bufferbloat beats any amount of local tuning — a player on a laptop with a clean line
will take the wall off you every time.

**If you are chasing latency and haven't measured your line under load, start there.**

---

## Verified end state — measured in-game

After the refresh-locked cap and the Engine.ini v2 change, captured live with Fortnite running:

```
Reported FPS   : 500, consistent        <- pinned at cap, NOT GPU-limited
Frame time     : 2.00 ms exactly
Ratio          : 1.00x refresh          <- one frame per scan-out
CPU total      : 9.5%                   <- enormous headroom
Cores parked   : 0 of 32
Game priority  : High (IFEO holding)
Affinity       : 0xFFFFFFFF (all 32 threads)
Ping           : 20.8 ms, 7 ms jitter
```

**Pinned at the cap with the GPU not maxed is the target state.** Frame times stay flat, the card
runs cooler, and every frame lands on a scan-out boundary. Capped-with-headroom beats uncapped.

### A note on DPC under load

```
idle:      CPU 14 = 0.94%
at 500fps: CPU 14 = 6.24%    CPU 8 = 1.95%    everything else = 0%
```

CPU 14 is the core the GPU's interrupts are deliberately pinned to. Higher frame rate means more
GPU interrupts, so elevated DPC *on that core specifically* is the affinity policy working — the
load is **contained on one core** instead of scattered across the scheduler. Judge DPC by whether
it is isolated, not only by its peak value.

---

## The tweak that measured worse

Applying `r.OneFrameThreadLag=0` and `r.GTSyncType=1` — both widely recommended:

| | FPS | frame time |
|---|---|---|
| Before | **480+** (cap-limited) | 2.08 ms |
| After | **300–400** | 3.33 ms |

They save roughly one frame of input lag and charge **1.25 ms on every frame** to do it. Removed.

This is why the repo insists on before/after measurement. Both settings appear in most Fortnite
optimization guides as unambiguous wins. On a 500Hz display they are a net loss.

---

## Verify your own machine

```powershell
# Read-only audit - hardware detection + current state
powershell -ExecutionPolicy Bypass -File .\scripts\Audit-System.ps1

# Real match sampling - run before you queue
powershell -ExecutionPolicy Bypass -File .\scripts\Match-Benchmark.ps1
```

For in-game frame data use the game's own overlay (Fortnite: Settings → Game → **Latency Debug
Stats**). Do **not** run PresentMon or any ETW tracer alongside EAC/BattlEye — BattlEye is
documented to monitor ETW sessions. The benchmark here deliberately avoids ETW entirely.
