# Windows Gaming Latency Guide

A **measured** guide to Windows 10 latency tuning for competitive FPS — built by debugging a real
`CRITICAL_PROCESS_DIED` boot loop caused by a popular tweak pack, then rebuilding the whole stack
from evidence instead of copy-paste.

Every tweak here has a verdict: **applied**, **removed**, or **rejected** — with the reason.
Several widely-recommended tweaks are in the *rejected* list because they measurably made things
worse on this hardware.

**Reference rig:** i9-13900KF (8P/16E, 32 threads) · RTX 4070 12GB · 32GB DDR5 · Intel I225-V 2.5GbE ·
500Hz panel @ 1600x900 · Windows 10 Home 19045 · Ultimate Performance

---

## ⚠️ Read this before you run anything

**This is not a copy-paste pack.** These values were measured on the rig above. Some findings are
universal; many are hardware-specific and will do nothing — or harm — elsewhere.

**Step 1 is always the audit.** It changes nothing and tells you what applies to *your* machine:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Audit-System.ps1
```

It detects your CPU topology (hybrid or not), RAM, GPU, NIC, whether you're on a laptop, your
current tweak state, live DPC latency, and crash history — then tells you which tweaks apply and
which to skip.

> ### 🤖 Using an AI assistant to apply this?
> Point it at **[`AGENTS.md`](AGENTS.md)** first.
>
> It instructs the assistant to audit your hardware before recommending anything, adapt values
> instead of copying them, refuse tweaks with no measured problem to solve, verify backups, and
> present a numbered list for your approval before deleting or disabling anything.
>
> Blindly applying another machine's tweaks is precisely what caused the boot loop this repo
> documents. The goal is **best performance that is still stable** — not maximum tweaks.

---

## Start here: the bug that started all this

A tweak pack set this:

```
HKLM\SYSTEM\CurrentControlSet\Control\SvcHostSplitThresholdInKB = 33554432   (32 GB)
```

Result: **instant BSOD on boot, then a boot loop.** Bugcheck `0x000000EF` — `CRITICAL_PROCESS_DIED`.

### Why it kills the machine

Windows compares that threshold to installed RAM. Below it, services are **grouped** into shared
`svchost.exe` processes. Above it, each service gets **its own** process. Stock Win10 is `3670016`
(3.5 GB), so any modern machine runs services split.

Setting it to 32 GB on a 32 GB machine forces everything into grouped mode:

| | svchost.exe instances |
|---|---|
| Stock (split) | **~70–110** |
| Threshold at 32 GB (grouped) | **19** |

And this is the part that kills you — one process ended up hosting all of:

```
DcomLaunch, LSM, Power, PlugPlay, BrokerInfrastructure, SystemEventsBroker, DeviceInstall
```

`DcomLaunch`, `LSM` and `Power` are **critical processes**. Windows marks any process hosting them
as critical. So when `PlugPlay` or `DeviceInstall` faults during boot device enumeration, it takes
`DcomLaunch` down with it — and the death of a critical process *is*, by definition, bugcheck `0xEF`.
No error dialog, no recovery. Straight to a boot loop.

### The fix

```powershell
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' `
  -Name SvcHostSplitThresholdInKB -Value 3670016 -Type DWord -Force
```

After reboot: **19 → 55 svchost instances**, with `LSM` and `DeviceInstall` broken out into their
own processes. Zero bugchecks since.

> **This tweak has no performance benefit whatsoever.** It is a RAM-*saving* measure for
> low-memory machines. On 16GB+ it saves nothing and creates a single point of failure.
> If you see it in a "gaming optimization" pack, that pack has not been tested.

---

## The second real find: core parking on hybrid CPUs

On a 12th-gen-or-newer Intel chip, Windows tracks P-cores and E-cores as separate
**efficiency classes**, and core parking has a **separate setting for each**:

```
0cc5b647-c1df-4637-891a-dec35c318583   core parking min cores            (Class 0 = E-cores)
0cc5b647-c1df-4637-891a-dec35c318584   core parking min cores, Class 1   (P-cores)  <- HIDDEN
```

Class 1 is hidden from `powercfg` by default (`Attributes = 1`). Every guide that says
"set `CPMINCORES` to 100 to disable core parking" only sets **Class 0**.

Measured result on this rig — all 8 P-cores parked, only E-cores awake:

```
PARKED   (16): 0,0 ... 0,15    <- every P-core thread
UNPARKED (16): 0,16 ... 0,31   <- every E-core
```

Worse, the background-app pinning strategy sends Discord/Steam/browsers to E-cores — the *only*
guaranteed-awake cores — while the game's P-cores sat parked waiting to wake.

### The fix

```powershell
$scheme = '0eeb3a79-fd9e-49e8-8266-b682359b75ce'   # Ultimate Performance
$sub    = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00'

# Unhide Class 1, then set BOTH classes
foreach ($g in @('0cc5b647-c1df-4637-891a-dec35c318583',
                 '0cc5b647-c1df-4637-891a-dec35c318584')) {
    Set-ItemProperty (Join-Path $sub $g) -Name Attributes -Value 2 -Type DWord -Force
    powercfg /setacvalueindex $scheme SUB_PROCESSOR $g 100
}
powercfg /setactive $scheme
```

**Result: 16 parked → 0 parked.** Verified stable across repeated sampling.

> Higher efficiency class = higher performance. **Class 1 is P-cores, Class 0 is E-cores.**
> Getting this backwards is easy and makes the whole fix a no-op.

---

## The principle: one owner per setting

The original boot loop happened because **two tweak packs both persisted at logon** and wrote the
same values with different numbers. They fought every single boot:

| Setting | Pack A | Pack B |
|---|---|---|
| `NetworkThrottlingIndex` | `10` | `0xFFFFFFFF` |
| Kill timeouts | aggressive | aggressive |
| `OverlayTestMode` | `Dwm` key (correct) | `GraphicsDrivers` key (inert) |

Whichever ran last won. State was never deterministic.

**The rule:** exactly one script owns any given value. Never two. The scripts here declare
ownership in their headers, and the split is enforced by convention:

- `LatencyLab-Boot.ps1` — timer, priority separation, MPO, GPU/NVIDIA, NIC RSS, QoS,
  telemetry, FSE, `Engine.ini`, E-core pinning
- `AllInOne-Apply.ps1` — svchost threshold, core parking, C-states, memory management,
  filesystem/TCP, `Ndu`, SmartScreen, kill timeouts

---

## Documentation

| Doc | What's in it |
|---|---|
| **[Recovery](docs/RECOVERY.md)** | **Your PC won't boot? Start here. Bookmark it before you tweak** |
| [BSOD writeup](docs/BSOD-CRITICAL_PROCESS_DIED.md) | Full root-cause analysis with evidence |
| [Tweak reference](docs/TWEAK-REFERENCE.md) | Every tweak, with verdict and reasoning |
| [Baseline](docs/BASELINE.md) | Real measured numbers — what "good" looks like |
| [Lessons](docs/LESSONS.md) | What didn't work, and traps that cost hours |
| [AGENTS.md](AGENTS.md) | Rules for AI assistants applying this for you |
| [`data/tweaks.json`](data/tweaks.json) | Machine-readable database — verdict, condition, risk per tweak |

## Scripts

| Script | Purpose | Safe to run blind? |
|---|---|---|
| **`Audit-System.ps1`** | **Read-only. Detects your hardware, reports state, says what applies to you** | **Yes — changes nothing** |
| `Match-Benchmark.ps1` | Samples ping/jitter/DPC/saturation during a real match | Yes — read-only |
| `optimize-and-stabilize.ps1` | One-shot fix with verified `.reg` backups + restore point | Read it first |
| `revert-optimize.ps1` | Undo. Refuses to run if backups are missing | Yes |
| `AllInOne-Apply.ps1` | Main apply. Idempotent, runs at logon | Read it first |
| `LatencyLab-Boot.ps1` | Logon persistence + in-game watcher | Rig-specific |
| `Restore-EngineIni.ps1` | Rebuilds Fortnite `Engine.ini` (the game deletes it) | Fortnite only |
| `Enable-WindowsUpdate.ps1` | Restores Windows Update to stock | Yes |

---

## Usage

```powershell
# 1. ALWAYS start here. Read-only. Tells you what applies to your hardware.
powershell -ExecutionPolicy Bypass -File .\scripts\Audit-System.ps1

# 2. Read the reference before changing anything.
#    docs/TWEAK-REFERENCE.md  - every tweak with a verdict
#    AGENTS.md                - if an AI is doing this for you

# 3. Inspect the script yourself.
notepad .\scripts\optimize-and-stabilize.ps1

# 4. Run elevated. Makes verified .reg backups and a restore point FIRST.
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\optimize-and-stabilize.ps1

# 5. Undo at any point.
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\revert-optimize.ps1
```

### Benchmarking your own machine

```powershell
# Run before you queue, then play a real match. 25 min of samples.
powershell -ExecutionPolicy Bypass -File .\scripts\Match-Benchmark.ps1
```

Reports ping, jitter, spike count, downlink saturation, CPU, DPC, parked cores, and whether game
priority held under load. **Uses no ETW or PresentMon** — see the anti-cheat note below.

> **These are tuned for the reference rig.** The svchost threshold and core parking fixes are
> universal. NIC, GPU, `Engine.ini` and FPS-cap values are hardware-specific — run the audit and
> adapt them.

---

## Anti-cheat note

Nothing here injects, hooks, or reads game memory. It's registry values, power settings, process
priority, and a config file the game itself ships.

`Match-Benchmark.ps1` deliberately avoids **PresentMon/ETW**. Fortnite runs EAC *and* BattlEye, and
BattlEye is documented to monitor ETW sessions. Every metric it collects comes from ordinary
performance counters and ICMP. Use the game's own **Latency Debug Stats** overlay for frame data —
zero risk.

## License

MIT. No warranty. You are modifying your own system at your own risk.
