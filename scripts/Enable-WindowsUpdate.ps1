<#
.SYNOPSIS
    Turns Windows Update back ON. Undoes Disable-WindowsUpdate changes.

.WHY YOU MIGHT NEED THIS
    Windows Update is currently fully disabled - it was pulling 169-330 Mbps
    mid-match and spiking ping to ~500-800ms. With it off you get no security
    patches and no feature updates until you run this.

    Run this if you want to patch, then disable again afterwards, or leave it
    on if you decide the bandwidth hit is worth it.

.USAGE
    Run elevated:
      powershell -ExecutionPolicy Bypass -File C:\LatencyLab\scripts\Enable-WindowsUpdate.ps1
#>
$ErrorActionPreference = 'Continue'

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: must run elevated." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== RE-ENABLING WINDOWS UPDATE ===" -ForegroundColor Cyan

# Original StartType values captured before they were disabled on 2026-08-29.
$restore = @{
    'wuauserv'     = 3   # Manual
    'UsoSvc'       = 2   # Automatic
    'WaaSMedicSvc' = 3   # Manual
    'DoSvc'        = 3   # Manual
}

foreach ($s in $restore.Keys) {
    try {
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$s" -Name Start -Value $restore[$s] -Type DWord -Force -ErrorAction Stop
        Write-Host "  $s -> Start=$($restore[$s])" -ForegroundColor Green
    } catch {
        Write-Host "  $s FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Clear the no-update / no-reboot policy.
$au = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
if (Test-Path $au) {
    foreach ($v in @('NoAutoUpdate','AUOptions','NoAutoRebootWithLoggedOnUsers')) {
        Remove-ItemProperty -Path $au -Name $v -Force -ErrorAction SilentlyContinue
    }
    Write-Host "  cleared NoAutoUpdate / AUOptions / NoAutoRebootWithLoggedOnUsers" -ForegroundColor Green
}

# Re-enable the scheduled tasks that were turned off.
foreach ($t in @(
    @{ p='\Microsoft\Windows\UpdateOrchestrator\'; n='Schedule Scan' },
    @{ p='\Microsoft\Windows\WindowsUpdate\';      n='Scheduled Start' }
)) {
    try {
        Enable-ScheduledTask -TaskName $t.n -TaskPath $t.p -ErrorAction Stop | Out-Null
        Write-Host "  re-enabled task: $($t.p)$($t.n)" -ForegroundColor Green
    } catch {
        Write-Host "  task $($t.n): $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Stop AllInOne from disabling them again on next logon.
$flag = 'C:\LatencyLab\WINDOWS_UPDATE_ENABLED'
Set-Content -Path $flag -Value "Windows Update re-enabled $(Get-Date). Delete this file to let AllInOne disable it again." -Encoding UTF8
Write-Host ""
Write-Host "  created flag: $flag" -ForegroundColor Cyan
Write-Host "  (AllInOne-Apply.ps1 checks for this and will leave Windows Update alone)" -ForegroundColor Gray

Write-Host ""
Write-Host "DONE - reboot, then check for updates normally." -ForegroundColor Green
Write-Host "To disable again: delete the flag file and run AllInOne-Apply.ps1" -ForegroundColor Gray
Write-Host ""
