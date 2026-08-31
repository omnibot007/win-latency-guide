---
name: Hardware result
about: Report what worked (or didn't) on your hardware
title: "[result] <CPU> - <what you tested>"
labels: measured-result
---

## Hardware

Paste the top of `Audit-System.ps1` output, or fill this in:

- **CPU:**  (and: hybrid P+E cores? yes/no)
- **RAM:**
- **GPU:**
- **NIC:**
- **Display refresh:**
- **Laptop or desktop:**
- **Windows build:**

## What you changed

Exact registry path / value, or the command you ran.

```
```

## How you measured

Tool and method. Frame counter, DPC sample, ping under load, etc.

## Numbers

| | Before | After |
|---|---|---|
| metric | | |

## Survived a reboot?

- [ ] Yes, verified after restart
- [ ] No, reverted on reboot
- [ ] Not tested yet

## Verdict

- [ ] `keep` — measurable benefit
- [ ] `remove` — no benefit or harmful
- [ ] `reject` — commonly recommended, doesn't hold up

## Anything else

Especially: did it behave differently from what `docs/TWEAK-REFERENCE.md` says?
