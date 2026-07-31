# Parse battery report and calculate electricity cost
# Then build a detailed power consumption report

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = $PSScriptRoot }

$reportPath = Join-Path $scriptDir "batteryreport.html"

if (-not (Test-Path $reportPath)) {
    Write-Host "Battery report file not found at: $reportPath" -ForegroundColor Red
    Write-Host "Run check_log.ps1 or 'powercfg /BATTERYREPORT' first." -ForegroundColor Yellow
    exit
}

$content = Get-Content $reportPath -Raw -ErrorAction SilentlyContinue

# Strip <script> and <style> blocks so JavaScript doesn't match
$cleanContent = $content -replace '(?s)<script.*?>.*?</script>', '' -replace '(?s)<style.*?>.*?</style>', ''

Write-Host "=== BATTERY REPORT KEY DATA ==="
# Extract useful bits from the HTML - look for capacity and usage data
$lines = $cleanContent -split "`n"
foreach ($line in $lines) {
    $stripped = $line -replace '<[^>]+>', '' -replace '&nbsp;', ' ' -replace '&#160;', ' '
    $stripped = $stripped.Trim()
    if ($stripped.Length -gt 3) {
        if ($stripped -match 'Design Capacity|Full Charge|Charge Cycle|Connected Standby|Active|Drain|Battery Life|mWh|Duration|Timestamp|Installed|Report') {
            # Skip noise lines that don't contain real report values
            if ($stripped -notmatch 'function|var |durationFormat|\{|\}') {
                Write-Host $stripped
            }
        }
    }
}
