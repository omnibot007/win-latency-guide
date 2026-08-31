# Root Cause: `CRITICAL_PROCESS_DIED` from a "performance" tweak

A full post-mortem of a boot loop caused by one registry value, and how it was traced.

---

## Symptoms

Tweak pack applied at 17:02. Reboot. **Instant BSOD, then a boot loop** — repeated crashes before
the desktop loaded.

```
Bugcheck : 0x000000EF (0xffff9a017dee50c0, 0, 0, 0)
Name     : CRITICAL_PROCESS_DIED
Dump     : C:\WINDOWS\MEMORY.DMP  (1.08 GB)
Time     : 18:02:54  (~1 hour after the tweaks were applied)
```

Only **one** bugcheck was recorded in the event log. The boot-loop crashes happened too early in
startup for the event log service to persist them — itself a signal that the failure was in early
service initialization.

---

## Ruling things out

Both of the user's initial theories were wrong, and both were cheap to disprove:

**Vanguard** — not installed at all:
```powershell
foreach($d in @("vgk","vgc","EasyAntiCheat","BEDaisy","BEService")){ Get-Service $d }
# all: not installed
```

**Secure Boot** — never disabled:
```
Confirm-SecureBootUEFI  ->  True
```

Nothing in the pack touched boot configuration. Its own `bcdedit.txt` capture was just an
"Access is denied" error string.

---

## Finding it

The pack's log had one line that mattered:

```
elev2_apply.log:  SvcHostSplit 32GB OK
```

Which corresponds to:

```
HKLM\SYSTEM\CurrentControlSet\Control\SvcHostSplitThresholdInKB = 33554432
```

### Confirming the mechanism

Windows compares this threshold against installed RAM to decide service hosting:

- **RAM below threshold** → services **grouped** into shared `svchost.exe`
- **RAM above threshold** → each service gets **its own** process

Stock Win10 is `3670016` KB (3.5 GB). The machine has 32.5 GB, so it normally runs split.
Setting the threshold to 32 GB forced grouped mode.

Measured live:

```powershell
(Get-Process svchost).Count
# 19        <- expected ~70-110 on a 32GB Win10 box
```

And the fatal grouping:

```powershell
Get-CimInstance Win32_Service | Where-Object State -eq 'Running' |
  Group-Object ProcessId | Sort-Object Count -Descending
```

```
PID 1192 hosts 7 services:
  BrokerInfrastructure, DcomLaunch, DeviceInstall, LSM,
  PlugPlay, Power, SystemEventsBroker
```

### Why that's fatal

`DcomLaunch`, `LSM` and `Power` are **critical processes**. Windows marks any process hosting them
as critical. A critical process terminating *is* bugcheck `0xEF` — that's the definition, not a
side effect.

When services are split, a `PlugPlay` or `DeviceInstall` fault kills only that service. Grouped,
the fault takes `DcomLaunch` + `LSM` + `Power` with it.

`DeviceInstall` and `PlugPlay` being in that group explains the **boot-specific** timing — device
enumeration runs at startup, exactly when the same pack was also rewriting NIC advanced properties,
USB power management, and GPU registry keys.

---

## The fix

```powershell
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' `
  -Name SvcHostSplitThresholdInKB -Value 3670016 -Type DWord -Force
```

Reboot required — grouping is decided at service-manager start.

### Verified after

```
svchost.exe instances : 19 -> 55

PID 1160: DcomLaunch, Power, PlugPlay, BrokerInfrastructure, SystemEventsBroker
PID 1284: RpcSs
PID 1340: LSM             <- broke out
PID 5400: DeviceInstall   <- broke out
```

`DeviceInstall` — the boot-time risk — no longer shares a process with `DcomLaunch`.
Three clean boots, zero new bugchecks.

> The remaining PID 1160 grouping is **stock Windows behavior**. It looks identical on a
> clean install. That group is not the problem; `DeviceInstall` joining it was.

---

## The second failure: a revert that did nothing

The pack shipped `revert.ps1`, which restores state by importing four files:

```powershell
reg import "$backup\Multimedia_SystemProfile.reg"
reg import "$backup\PriorityControl.reg"
reg import "$backup\MemoryManagement.reg"
reg import "$backup\GraphicsDrivers.reg"
```

**None of those files were ever created.** The backup folder contained only `.txt` logs and an
`.ini` backup. The pack logged its pre-change state as human-readable text but never exported a
single `.reg`.

Every import failed silently, because each was wrapped in:

```powershell
try { reg import "..." 2>&1 | Out-Null } catch {}
```

Suppressed output, swallowed exception, no exit-code check.

The revert *appeared* to succeed. It deleted the scheduled tasks and restored a game config, so it
looked like it worked. **Every registry change survived**, including the one causing the BSOD.
The machine sat armed for another crash while the user believed it had been undone.

### Lessons

1. **A backup you never verified is not a backup.** Check the file exists after writing it.
2. **Never suppress errors in a revert path.** Check `$LASTEXITCODE` on `reg import`.
3. **Refuse to run rather than pretend.** `revert-optimize.ps1` in this repo exits with an error if
   no `.reg` files are present, instead of reporting success.

---

## A red herring worth documenting

Both packs also set:

```powershell
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' `
  -Name 'WaitToKillServiceTimeout' -Value 2000 -Type DWord
```

This looks like a contributing factor — a 2-second kill timeout against slow-starting grouped
services is a plausible amplifier. It was initially reported as one.

**It was inert.** Windows reads `WaitToKillServiceTimeout` as `REG_SZ`. Written as `REG_DWORD`,
it is ignored entirely and the default 5000 applies:

```powershell
$k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Control")
$k.GetValueKind('WaitToKillServiceTimeout')   # DWord  -> ignored
```

The svchost grouping caused the crash essentially on its own. Worth checking value **type**, not
just value, before blaming a setting.

---

## Timeline

| Time | Event |
|---|---|
| 17:02 | Tweak pack applied. `SvcHostSplit 32GB OK` logged |
| 17:46 | Persist task re-asserts everything |
| ~18:00 | Reboot |
| 18:02:45 | Kernel-Power 41 — unexpected shutdown |
| 18:02:54 | Bugcheck `0xEF` logged, 1.08 GB dump written |
| 19:02 | `revert.ps1` run — **silently did nothing** to the registry |
| next day | Root cause found, fixed, verified across 3 clean boots |
