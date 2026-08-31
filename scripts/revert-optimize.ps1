# =====================================================================
#  revert-optimize.ps1
#  Undoes optimize-and-stabilize.ps1 using its REAL .reg backups.
#  Picks the newest stabilize-* folder unless -Backup is given.
#  (Unlike vmp-tweaks' revert.ps1, this verifies the files exist first.)
# =====================================================================
param([string]$Backup)

$ErrorActionPreference = 'Continue'

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: must run elevated (Run as Administrator)." -ForegroundColor Red
    exit 1
}

if (-not $Backup) {
    $cand = Get-ChildItem "C:\Users\Saqcrifice\.backup" -Directory -Filter "stabilize-*" -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
    if (-not $cand) {
        Write-Host "No stabilize-* backup folder found. Nothing to revert from." -ForegroundColor Red
        exit 1
    }
    $Backup = $cand.FullName
}

if (-not (Test-Path $Backup)) {
    Write-Host "Backup folder not found: $Backup" -ForegroundColor Red
    exit 1
}

Write-Host "Reverting from: $Backup" -ForegroundColor Cyan
Write-Host ""

$files = Get-ChildItem $Backup -Filter "*.reg" -ErrorAction SilentlyContinue
if (-not $files) {
    Write-Host "No .reg files in that folder - refusing to pretend this worked." -ForegroundColor Red
    exit 1
}

$ok = 0
$fail = 0
foreach ($f in $files) {
    $out = reg import $f.FullName 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  restored $($f.Name)" -ForegroundColor Green
        $ok++
    } else {
        Write-Host "  FAILED   $($f.Name) :: $out" -ForegroundColor Red
        $fail++
    }
}

Write-Host ""
Write-Host "Restored $ok file(s), $fail failure(s)." -ForegroundColor Cyan

# The QoS policy is not registry-exported, so remove it explicitly.
if (Get-NetQosPolicy -Name "FortniteUDP-EF" -ErrorAction SilentlyContinue) {
    Remove-NetQosPolicy -Name "FortniteUDP-EF" -PolicyStore "localhost" -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Removed QoS policy FortniteUDP-EF" -ForegroundColor Green
}

Write-Host ""
Write-Host "NOTE: this does NOT restore SvcHostSplitThresholdInKB to 32GB." -ForegroundColor Yellow
Write-Host "That value caused the BSOD. If you truly want it back, set it by hand." -ForegroundColor Yellow
Write-Host "Reboot recommended." -ForegroundColor Cyan
