# Lessons

Things that cost real time, and the traps behind them. Most of these are not tweak knowledge —
they're debugging knowledge.

---

## 1. Two persistence mechanisms will always fight

Two tweak packs both installed logon tasks. Both wrote `NetworkThrottlingIndex`, one to `10` and
one to `0xFFFFFFFF`. Whichever ran last won, so system state was **never deterministic** — it
flipped every boot depending on task scheduling order.

**Rule:** exactly one script owns any given value. Write the ownership split into the script
headers so the next person can't accidentally violate it.

---

## 2. Check the value *type*, not just the value

```powershell
Set-ItemProperty ... -Name 'WaitToKillServiceTimeout' -Value 2000 -Type DWord
```

Reads back as `2000`. Looks applied. **Windows ignores it** — that value is only read as `REG_SZ`.
Both packs got this wrong, and it was initially blamed as a crash contributor.

```powershell
$k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Control")
$k.GetValueKind('WaitToKillServiceTimeout')
```

---

## 3. The same setting name can live in two places, and only one works

`OverlayTestMode` (MPO disable):

- `HKLM\SOFTWARE\Microsoft\Windows\Dwm\OverlayTestMode` — **correct, works**
- `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\OverlayTestMode` — inert

One pack wrote the wrong one and reported success for weeks.

---

## 4. Hidden power settings mean guides are silently incomplete

Windows hides settings with `Attributes = 1`. `powercfg /query` won't show them, so a guide author
who only reads visible settings never learns Class 1 exists.

On hybrid CPUs this meant **every P-core parked** while the guide's author believed parking was off.

```powershell
Set-ItemProperty $settingKey -Name Attributes -Value 2 -Type DWord -Force
```

---

## 5. Games rewrite their own config — read-only is the only defence

Fortnite **deletes** `Engine.ini` on exit and **regenerates** it on launch. Three approaches failed
before the right one:

| Attempt | Result |
|---|---|
| Write at logon | Game overwrote it at next launch |
| Restore on game exit | Game regenerated it on next launch |
| Write + **set read-only** | Survives |

```powershell
Set-ItemProperty $ini -Name IsReadOnly -Value $true
```

---

## 6. Higher FPS *is* lower latency past a point

`r.OneFrameThreadLag=0` and `r.GTSyncType=1` are widely recommended — they save roughly one frame
of input lag by preventing CPU run-ahead. Measured cost on this rig: **480 FPS → 300–400.**

| FPS | frame time |
|---|---|
| 480 | 2.08 ms |
| 300 | 3.33 ms |

They save one frame and charge 1.25 ms on **every** frame. At high refresh, that's a net loss.
Both removed.

**Generalisation:** a latency tweak that costs framerate needs the math done, not assumed.

---

## 7. MSIX/Store apps have a virtualized filesystem

This cost six failed attempts at one launcher.

The Claude desktop app is MSIX-packaged. A process **inside** the package sees:

```
C:\Users\<u>\AppData\Roaming\Claude\claude-code\<ver>\claude.exe    Test-Path -> True
```

A process **outside** it (an elevated shell) sees only the real location:

```
C:\Users\<u>\AppData\Local\Packages\Claude_<hash>\LocalCache\Roaming\Claude\...
```

The debugging trap: a hardcoded absolute path returned `True` when tested from inside the
container and "not found" when run elevated. **Two processes disagreeing about whether an absolute
path exists means they're looking at different filesystems** — that's nearly the only explanation,
and it should be the first hypothesis, not the last.

Store-packaged apps also **cannot be elevated at all**. "Run as administrator" is silently ignored.

AntiMicro turned out to be MSIX too — its config was in the same kind of container path.

---

## 8. Verify from the same context you'll run in

Related to the above, and the root error behind it. Checking `Test-Path` from a non-elevated shell
and concluding an elevated script will find the file is not verification. Test from the context
that matters.

---

## 9. A tool reporting post-fix state can "disprove" a fix that worked

A background agent inspected core parking **after** the fix, saw both classes at `100`, and
reported the original finding was a false alarm from a transient sample.

It was wrong twice: it inverted the class mapping (called Class 0 the P-cores), and it observed the
repaired state and concluded nothing had been broken.

The evidence that settled it: the pre-fix parked set was *exactly* `0,0`–`0,15` — a clean block on
the P-core boundary. Random idle parking doesn't land precisely on all 16 P-core threads and
nothing else.

**Rule:** don't overwrite your own measured before/after on someone else's after-only reading.

---

## 10. Not every problem is a PC problem

The single biggest remaining latency source was **downlink saturation** — 330 Mbps peaks mid-match
spiking ping to ~500–800ms.

Windows **cannot** rate-limit inbound traffic. The queue that fills lives upstream at the ISP, past
the NIC. No registry value touches it. The honest answer was router-level SQM, not another tweak.

Recognising when to stop tuning the machine matters as much as knowing what to tune.

---

## 11. Arbitrary pass/fail thresholds create false alarms

A verification script hardcoded `svchost >= 60` as the pass condition. The real result was **55** —
a 175% improvement over the broken state, unambiguously fixed. The script reported
`STILL GROUPED` and alarmed the user for no reason.

Compare against the **before** value, not a number you invented.

---

## 12. Don't fix what the measurement says is fine

NIC interrupt affinity was about to be pinned to a dedicated core — a plausible, commonly
recommended tweak. Then: DPC measured **0.243% average, 1.212% peak.**

There was no contention to fix, and forcing an affinity mask would have overridden a working RSS
4-queue setup. Skipped.

The urge to keep applying tweaks is strong. Measurement is what stops you making things worse.
