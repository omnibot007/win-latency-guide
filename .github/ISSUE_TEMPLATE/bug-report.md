---
name: Bug in a script or doc
about: Something here is wrong, broken, or unsafe
title: "[bug] "
labels: bug
---

## What's wrong

## Which file

## What happened

Paste the error, or what the script did versus what it should have done.

```
```

## Your hardware

Output of `Audit-System.ps1` if the bug is hardware-dependent.

## Did it break anything?

- [ ] No — script errored but system is fine
- [ ] Yes — system instability (**please include the stop code**)
- [ ] Yes — machine wouldn't boot (see `docs/RECOVERY.md`)

> A tweak marked `keep` that caused instability is high priority — it means an `applies_when`
> condition is wrong and other people will hit it too.
