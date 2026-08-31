# Disable ShadowPlay on boot (when files are not in use)
$shadowPlayPath = 'C:\Program Files\NVIDIA Corporation\NVIDIA App\ShadowPlay'
$disabled = $shadowPlayPath + '.disabled'
if (Test-Path $shadowPlayPath) {
    if (-not (Test-Path $disabled)) {
        Rename-Item $shadowPlayPath -NewName 'ShadowPlay.disabled' -Force -ErrorAction SilentlyContinue
        if (Test-Path $disabled) {
            Add-Content 'C:\LatencyLab\logs\boot.log' "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))  [boot] Disabled ShadowPlay by renaming directory"
        }
    }
}

# Also ensure NvTelemetry is disabled
$telemetryPath = 'C:\Program Files\NVIDIA Corporation\NvTelemetry'
$telemetryDisabled = $telemetryPath + '.disabled'
if (Test-Path $telemetryPath) {
    if (-not (Test-Path $telemetryDisabled)) {
        Rename-Item $telemetryPath -NewName 'NvTelemetry.disabled' -Force -ErrorAction SilentlyContinue
        if (Test-Path $telemetryDisabled) {
            Add-Content 'C:\LatencyLab\logs\boot.log' "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))  [boot] Disabled NvTelemetry by renaming directory"
        }
    }
}
