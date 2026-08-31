<#
.SYNOPSIS
    Rewrites Fortnite's Engine.ini with the LatencyLab performance overlay (v2).

.WHY THIS EXISTS
    Fortnite DELETES Engine.ini when it exits - confirmed live 2026-08-29.
    Restoring only at logon left the overlay missing for the whole session,
    so LatencyLab-Boot.ps1 now calls this the instant Fortnite exits.

.V2 CHANGE - measured, not guessed
    v1 included r.OneFrameThreadLag=0 and r.GTSyncType=1. Those save roughly
    one frame of input lag by stopping the CPU running ahead of the GPU.
    Measured on this rig: FPS fell from 480+ (cap-limited) to 300-400.

    At 500Hz, framerate IS latency:
        480 FPS = 2.08 ms/frame
        300 FPS = 3.33 ms/frame
    The single frame those settings save costs 1.25 ms on EVERY frame.
    Net loss, so both are removed. Everything kept below is free.

    Safe to run any time. Rewrites only if the v2 marker is missing.
#>
$ErrorActionPreference = 'Continue'

$ini = Join-Path $env:LOCALAPPDATA 'FortniteGame\Saved\Config\WindowsClient\Engine.ini'
$dir = Split-Path $ini

$overlay = @'
[Core.System]
Paths=../../../Engine/Content
Paths=%GAMEDIR%Content

; ================= LatencyLab performance overlay v2 =================
; RTX 4070 12GB | 1600x900 | 500Hz | i9-13900KF
; v2: removed r.OneFrameThreadLag=0 and r.GTSyncType=1 - they cost more
; framerate than the frame of latency they saved. See script header.
[/Script/Engine.RendererSettings]
r.FinishCurrentFrame=0
r.Streaming.PoolSize=4096
r.Streaming.LimitPoolSizeToVRAM=1
r.Streaming.UseFixedPoolSize=1
r.Streaming.UseAllMips=0
r.Nanite=0
r.HZBOcclusion=1
r.VRS.Enable=1
r.VSync=0
rhi.SyncInterval=0

[SystemSettings]
r.Streaming.PoolSize=4096
r.Streaming.LimitPoolSizeToVRAM=1
r.Streaming.UseFixedPoolSize=1
; =====================================================================
'@

try {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    $needsWrite = $true
    if (Test-Path $ini) {
        $cur = Get-Content $ini -Raw -ErrorAction SilentlyContinue
        if ($cur -match 'performance overlay v2') { $needsWrite = $false }
    }

    if ($needsWrite) {
        Set-Content -Path $ini -Value $overlay -Encoding UTF8
        Write-Output "Engine.ini overlay v2 written: $ini"
    } else {
        Write-Output "Engine.ini overlay v2 already present - no change"
    }
} catch {
    Write-Output "FAILED: $($_.Exception.Message)"
}
