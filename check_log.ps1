# Check event log depth and get hardware power data

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = $PSScriptRoot }

Write-Host "=== EARLIEST SYSTEM LOG EVENT ==="
$oldest = Get-WinEvent -LogName System -MaxEvents 1 -Oldest -ErrorAction SilentlyContinue
if ($oldest) {
    Write-Host "Oldest System Log Entry: $($oldest.TimeCreated)"
} else {
    Write-Host "Could not retrieve oldest event."
}

Write-Host ""
Write-Host "=== SYSTEM EVENT LOG METADATA ==="
$logInfo = Get-WinEvent -ListLog System -ErrorAction SilentlyContinue
if ($logInfo) {
    Write-Host "Record Count : $($logInfo.RecordCount)"
    Write-Host "File Size    : $([math]::Round($logInfo.FileSize / 1MB, 2)) MB"
    Write-Host "Max Size     : $([math]::Round($logInfo.MaximumSizeInBytes / 1MB, 2)) MB"
    Write-Host "Log Path     : $($logInfo.LogFilePath)"
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host ""
Write-Host "=== SYSTEM POWER CAPABILITIES ==="
if ($isAdmin) {
    $sleepstudyPath = Join-Path $scriptDir "sleepstudy.html"
    powercfg /SLEEPSTUDY /output "$sleepstudyPath" 2>&1
} else {
    Write-Host "[Notice] powercfg /SLEEPSTUDY requires Administrator privileges." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== BATTERY REPORT (Laptop) ==="
$batteryReportPath = Join-Path $scriptDir "batteryreport.html"
powercfg /BATTERYREPORT /output "$batteryReportPath" 2>&1

Write-Host ""
Write-Host "=== POWER EFFICIENCY DIAGNOSTICS ==="
if ($isAdmin) {
    $energyReportPath = Join-Path $scriptDir "energyreport.html"
    powercfg /ENERGY /output "$energyReportPath" /duration 10 2>&1
} else {
    Write-Host "[Notice] powercfg /ENERGY requires Administrator privileges." -ForegroundColor Yellow
}
