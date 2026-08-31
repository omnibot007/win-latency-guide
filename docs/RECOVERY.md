# Recovery: your PC won't boot after tweaking

**Read this before you tweak, not after.** Bookmark it on your phone.

Most tweak repos never cover this, which is absurd — they hand you registry edits that touch
boot-critical services and no plan for when it goes wrong. This one boot-looped a machine, so:

---

## First: don't reinstall Windows

Almost every tweak-induced boot failure is recoverable in under ten minutes. A registry value that
breaks boot can be undone from Safe Mode or the recovery console. You have not lost anything.

---

## Getting into recovery

Windows auto-enters recovery after **three failed boots**. To force it: power on, and as soon as
you see the Windows logo, **hold the power button** until it powers off. Repeat twice. On the third
boot you land in **Automatic Repair**.

Then: **Advanced options** → and pick from below.

---

## Fix 1 — System Restore (try this first)

**Advanced options → System Restore**

Pick the restore point from before your changes. Every script in this repo creates one first.
This reverts registry and system state, leaves your personal files alone, takes ~5 minutes, and
fixes the overwhelming majority of tweak-induced failures.

---

## Fix 2 — Safe Mode, then undo

**Advanced options → Startup Settings → Restart → press `4`** (Safe Mode)

Safe Mode loads a minimal driver and service set, so most bad tweaks don't apply. Open an admin
PowerShell and undo the change.

**The single most likely culprit** — this one causes `CRITICAL_PROCESS_DIED` boot loops:

```powershell
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' `
  -Name SvcHostSplitThresholdInKB -Value 3670016 -Type DWord -Force
```

If you ran a script from this repo, its revert is right there:

```powershell
powershell -ExecutionPolicy Bypass -File C:\path\to\repo\scripts\revert-optimize.ps1
```

Or import your backups directly:

```powershell
Get-ChildItem "$env:USERPROFILE\.backup" -Recurse -Filter *.reg |
  Sort-Object LastWriteTime -Descending | Select-Object -First 10 FullName
reg import "C:\Users\<you>\.backup\<folder>\Control_root.reg"
```

Reboot normally.

---

## Fix 3 — Last Known Good Configuration

**Advanced options → Startup Settings → Restart → press `F8`** where offered.

Boots from the last control set that reached a successful logon, discarding
`HKLM\SYSTEM\CurrentControlSet` changes since. Works well for `CurrentControlSet` edits (which is
where most of these live). Won't help with `HKLM\SOFTWARE` or scheduled tasks.

---

## Fix 4 — Offline registry edit (Safe Mode won't boot either)

**Advanced options → Command Prompt**

```cmd
reg load HKLM\OFFLINE C:\Windows\System32\config\SYSTEM
reg add "HKLM\OFFLINE\ControlSet001\Control" /v SvcHostSplitThresholdInKB /t REG_DWORD /d 3670016 /f
reg unload HKLM\OFFLINE
```

> Your Windows drive may not be `C:` in recovery. Check with `diskpart` → `list volume` first, and
> substitute the right letter. `ControlSet001` is usually the active set; if it fails, try
> `ControlSet002`.

Then:

```cmd
exit
```
and boot normally.

---

## Fix 5 — Disable a service offline

If a disabled (or enabled) service is blocking boot:

```cmd
reg load HKLM\OFFLINE C:\Windows\System32\config\SYSTEM
reg add "HKLM\OFFLINE\ControlSet001\Services\<ServiceName>" /v Start /t REG_DWORD /d 3 /f
reg unload HKLM\OFFLINE
```

`Start` values: `0` = boot · `1` = system · `2` = automatic · `3` = manual · `4` = disabled

**Never set a boot-critical service to `4`.** If you did, put it back to its original value —
`RpcSs`, `DcomLaunch`, `PlugPlay`, `Power`, `LSM` and `BrokerInfrastructure` must never be disabled.

---

## Reading the crash before you fix it

If you got a BSOD with a stop code, it narrows things fast:

| Stop code | Meaning | Usual tweak cause |
|---|---|---|
| `0x000000EF` `CRITICAL_PROCESS_DIED` | A critical process terminated | **`SvcHostSplitThresholdInKB`**, or a boot-critical service disabled |
| `0x0000007B` `INACCESSIBLE_BOOT_DEVICE` | Can't reach the boot disk | Storage driver/AHCI service disabled |
| `0x0000000A` `IRQL_NOT_LESS_OR_EQUAL` | Bad kernel memory access | Driver conflict, bad interrupt affinity, unstable overclock |
| `0x00000124` `WHEA_UNCORRECTABLE_ERROR` | Hardware fault | Unstable OC, or C-states disabled on a marginal CPU |
| `0x0000009F` `DRIVER_POWER_STATE_FAILURE` | Driver hung on power transition | Power/USB selective-suspend tweaks |

Once booted, read the history:

```powershell
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WER-SystemErrorReporting'} -MaxEvents 5 |
  Select-Object TimeCreated, Message | Format-List
```

---

## Black screen, but it *is* booting

Different problem — usually GPU/display, not boot.

- **Ctrl+Shift+Win+B** restarts the graphics driver without rebooting
- If MPO tweaks did it, remove: `HKLM\SOFTWARE\Microsoft\Windows\Dwm\OverlayTestMode`
- Boot into Safe Mode and roll back or reinstall the GPU driver
- Try a different output (HDMI vs DisplayPort) — some tweaks affect one path only

---

## No login / desktop never appears

Usually a broken shell or a disabled user-critical service.

**Ctrl+Shift+Esc** → Task Manager → **File → Run new task** → `explorer.exe`

If that works, the shell registration broke. Check:

```
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\Shell   should be: explorer.exe
```

An IFEO `Debugger` value on a system binary can also do this. Scan for hijacks:

```powershell
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options' |
  ForEach-Object {
    $d = (Get-ItemProperty $_.PSPath -Name Debugger -EA SilentlyContinue).Debugger
    if ($d) { "$($_.PSChildName) -> $d" }
  }
```

Anything listed there is redirecting a program to something else. On this machine, a debloat script
had pointed `mpcmdrun.exe` (Defender's scanner) at `systray.exe` to silently neuter it.

---

## Before you tweak — the five-minute insurance

1. **Create a restore point manually**
   ```powershell
   Enable-ComputerRestore -Drive "C:\"
   Checkpoint-Computer -Description "Before tweaking" -RestorePointType MODIFY_SETTINGS
   ```
2. **Export the keys you're about to change** — and `Test-Path` the file afterward to confirm it
   actually wrote. An unverified backup is not a backup.
3. **Know your recovery route** — practise getting into Safe Mode *once*, before you need it.
4. **Change things in small batches** and reboot between them. If you apply thirty tweaks and it
   breaks, you're bisecting thirty things in Safe Mode.
5. **Write down what you changed.** The scripts here log to `C:\LatencyLab\logs\`.

---

## The honest summary

The failure documented in this repo happened because a pack applied ~60 changes at once, made
backups that didn't exist, and shipped a revert that silently failed. The user believed they had
undone it. They hadn't — the machine sat armed for another crash.

**Small batches. Verified backups. A revert you've actually tested.** That's the whole discipline.
