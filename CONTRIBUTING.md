# Contributing

The point of this repo is that **every claim is measured**. That's the only thing separating it
from the hundreds of unsourced tweak lists already out there, so it's the one rule that matters.

---

## What gets merged

**Measured results.** A before/after number, the hardware it came from, and how you measured it.

**Corrections.** If something here is wrong on your hardware, that's valuable — especially if a
tweak marked `keep` did nothing or hurt on your setup. Negative results are as useful as positive
ones and there are already several in [`docs/TWEAK-REFERENCE.md`](docs/TWEAK-REFERENCE.md).

**Portability fixes.** Anything hardcoded to the reference rig that could adapt instead. Several
such bugs have already been found and fixed; assume more exist.

**New hardware coverage.** AMD, non-hybrid Intel, laptops, different NICs. The core parking finding
only applies to hybrid CPUs — nobody has verified the equivalent on Ryzen CCX parking.

## What doesn't

**Unsourced tweaks.** "This helped me" without a number isn't evidence. If it can't be measured,
it can't be verified, and it doesn't belong here.

**Anything that touches anti-cheat.** No injection, no memory editing, no bypasses. This repo stays
on the right side of that line — registry values, power settings, process priority, and config
files games ship themselves.

**Bulk tweak packs.** Adding fifty registry values in one PR is exactly the pattern that caused the
boot loop this repo documents. One change, one justification.

---

## Submitting a measured result

Run the audit first — it's read-only and gives the hardware context needed to interpret anything
else:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Audit-System.ps1
```

Then include:

1. **Hardware** — CPU (and whether hybrid), RAM, GPU, NIC, display refresh, laptop or desktop
2. **What you changed** — the exact registry path/value or command
3. **How you measured** — the tool and method
4. **Before / after numbers** — actual figures, not impressions
5. **Whether it survived a reboot**

Use the [hardware result template](.github/ISSUE_TEMPLATE/hardware-result.md) — it prompts for all
of this.

## Adding a tweak to the database

New entries go in [`data/tweaks.json`](data/tweaks.json) and need every field:

```json
{
  "id": "kebab-case-id",
  "name": "Human readable name",
  "path": "HKLM\\...",
  "value": 1,
  "verdict": "keep | remove | reject | neutral",
  "risk": "none | low | medium | high | critical",
  "applies_when": "always | cpu_hybrid == true | never | ...",
  "reason": "Why, in terms of what was measured.",
  "evidence": "The actual before/after numbers."
}
```

`applies_when` is the important one. `"always"` means genuinely universal — if it depends on
hardware, say what it depends on. That field is what lets tools and agents reason about whether a
tweak is relevant instead of applying everything blindly.

## Script standards

If you touch a `.ps1`:

- **No hardcoded usernames or drive letters.** Use `$env:USERPROFILE`, `$env:LOCALAPPDATA`.
- **No hardcoded device names.** Detect the adapter, detect the power scheme. Assuming the NIC is
  called `Ethernet` was a real bug here that made the benchmark silently report 0 Mbps.
- **Back up before writing, and verify the backup exists.** `Test-Path` the file after `reg export`.
- **Never swallow errors in a revert path.** Check `$LASTEXITCODE`. A revert that can't verify its
  backups must refuse to run, not report success — see
  [`docs/BSOD-CRITICAL_PROCESS_DIED.md`](docs/BSOD-CRITICAL_PROCESS_DIED.md).
- **Gate `HKLM` writes behind an elevation check** and degrade gracefully unelevated.
- **Must parse clean:**
  ```powershell
  $e=$null; [System.Management.Automation.Language.Parser]::ParseFile('script.ps1',[ref]$null,[ref]$e); $e
  ```

## Documentation standards

- State the **mechanism**, not just the setting. "Sets X to Y" is useless; "Y forces services into
  shared hosts, and a fault in any of them kills a critical process" is the actual finding.
- Include the **numbers**. `19 → 55 svchost instances` beats "improves stability".
- **Document failures.** [`docs/LESSONS.md`](docs/LESSONS.md) exists because the mistakes were more
  instructive than the wins.

---

## Reporting a problem

Something here broke your machine? Open an issue with the stop code and what you'd applied.
[`docs/RECOVERY.md`](docs/RECOVERY.md) should get you booting again first.

If a tweak marked `keep` caused instability on your hardware, that's a **high priority** issue —
it means an `applies_when` condition is wrong, and someone else will hit it too.
