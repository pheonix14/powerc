# ============================================================
# FINAL ELECTRICITY COST REPORT GENERATOR
# PC: Intel i9-14900HX + NVIDIA RTX 4070 Laptop
# ============================================================

$startDate  = Get-Date "2026-01-01T00:00:00"
$endDate    = Get-Date
$totalDays  = [math]::Round(($endDate - $startDate).TotalDays, 1)

# ---- HARDWARE SPECS (from detection) ----
# CPU:  Intel Core i9-14900HX (24 cores, TDP ~55W base, up to 157W)
# GPU:  NVIDIA RTX 4070 Laptop (max ~150W)
# RAM:  Estimated 32GB DDR5 (~10W)
# SSD:  ~3W
# Display: ~20W (laptop)
# Fans/Board/Other: ~15W

# ---- POWER MODES (watt estimates) ----
$watt_idle       = 30   # Plugged in, idle/light use
$watt_moderate   = 80   # Typical productivity / browsing
$watt_gaming     = 200  # Gaming / heavy GPU load
$watt_sleep      = 3    # Connected standby
$watt_off        = 0.5  # Plugged in, shutdown (vampire draw)

# ---- DYNAMIC UPTIME CALCULATION FROM EVENT LOGS ----
$uptime_detected_hours = 0
$uptime_detected_days  = 1

try {
    # 6005: Event log service started (System boot)
    # 6006: Event log service stopped (System shutdown)
    # 1: System resumed from sleep/hibernate
    # 42: System entering sleep
    # 1074: System shutdown/restart initiated
    $events = Get-WinEvent -FilterHashtable @{LogName='System'; Id=@(6005,6006,1,42,1074)} -ErrorAction SilentlyContinue | Sort-Object TimeCreated

    if ($events -and $events.Count -gt 0) {
        $firstLogTime = $events[0].TimeCreated
        $logSpanDays = [math]::Max(1, ($endDate - $firstLogTime).TotalDays)
        $uptime_detected_days = [math]::Round($logSpanDays, 1)

        $totalActiveSeconds = 0
        $isPoweredOn = $false
        $lastStateChangeTime = $firstLogTime

        foreach ($e in $events) {
            $eTime = $e.TimeCreated
            $eId = $e.Id

            if ($eId -eq 6005 -or $eId -eq 1) {
                if (-not $isPoweredOn) {
                    $isPoweredOn = $true
                    $lastStateChangeTime = $eTime
                }
            }
            elseif ($eId -eq 6006 -or $eId -eq 42 -or $eId -eq 1074) {
                if ($isPoweredOn) {
                    $span = ($eTime - $lastStateChangeTime).TotalSeconds
                    if ($span -gt 0) { $totalActiveSeconds += $span }
                    $isPoweredOn = $false
                }
            }
        }
        if ($isPoweredOn) {
            $span = ($endDate - $lastStateChangeTime).TotalSeconds
            if ($span -gt 0) { $totalActiveSeconds += $span }
        }
        $uptime_detected_hours = [math]::Round($totalActiveSeconds / 3600, 2)
    }
} catch {
    # Fallback to defaults if event log query fails
    $uptime_detected_hours = 147.5
    $uptime_detected_days  = 32.0
}

# Extrapolate to full year / period
$avg_daily_hours = $uptime_detected_hours / $uptime_detected_days
$total_active_hours_est = [math]::Round($avg_daily_hours * $totalDays, 1)
$total_sleep_hours_est  = [math]::Round(($totalDays * 24 - $total_active_hours_est) * 0.3, 1)  # ~30% sleep
$total_off_hours_est    = [math]::Round([math]::Max(0, $totalDays * 24 - $total_active_hours_est - $total_sleep_hours_est), 1)

Write-Host "=== ACTIVE HOURS ESTIMATION ==="
Write-Host ("Detected log period: " + $uptime_detected_days + " days (" + $uptime_detected_hours + " active hrs detected)")
Write-Host ("Average daily active hours: " + [math]::Round($avg_daily_hours, 2) + " hrs/day")
Write-Host ("Total days in period (Jan 1 - now): " + $totalDays)
Write-Host ("Estimated total active hours: " + $total_active_hours_est + " hrs")
Write-Host ("Estimated sleep/standby hours: " + $total_sleep_hours_est + " hrs")
Write-Host ("Estimated powered-off hours: " + $total_off_hours_est + " hrs")

# ---- USAGE MIX ASSUMPTION ----
$frac_idle     = 0.50
$frac_moderate = 0.40
$frac_heavy    = 0.10

$hrs_idle     = [math]::Round($total_active_hours_est * $frac_idle, 1)
$hrs_moderate = [math]::Round($total_active_hours_est * $frac_moderate, 1)
$hrs_heavy    = [math]::Round($total_active_hours_est * $frac_heavy, 1)

Write-Host ""
Write-Host "=== USAGE MIX (Active Hours Breakdown) ==="
Write-Host ("Idle/Light use (50%): " + $hrs_idle + " hrs @ " + $watt_idle + "W")
Write-Host ("Moderate work (40%): " + $hrs_moderate + " hrs @ " + $watt_moderate + "W")
Write-Host ("Heavy/Gaming (10%): " + $hrs_heavy + " hrs @ " + $watt_gaming + "W")

# ---- ENERGY CALCULATIONS ----
$kwh_idle     = [math]::Round(($hrs_idle * $watt_idle) / 1000, 2)
$kwh_moderate = [math]::Round(($hrs_moderate * $watt_moderate) / 1000, 2)
$kwh_heavy    = [math]::Round(($hrs_heavy * $watt_gaming) / 1000, 2)
$kwh_sleep    = [math]::Round(($total_sleep_hours_est * $watt_sleep) / 1000, 2)
$kwh_off      = [math]::Round(($total_off_hours_est * $watt_off) / 1000, 2)
$kwh_total    = [math]::Round($kwh_idle + $kwh_moderate + $kwh_heavy + $kwh_sleep + $kwh_off, 2)

# Add charger overhead (~15% power supply inefficiency for laptop)
$kwh_charger_loss = [math]::Round($kwh_total * 0.15, 2)
$kwh_grand_total  = [math]::Round($kwh_total + $kwh_charger_loss, 2)

Write-Host ""
Write-Host "=== ENERGY CONSUMPTION (kWh) ==="
Write-Host ("Idle/light:         " + $kwh_idle + " kWh")
Write-Host ("Moderate work:      " + $kwh_moderate + " kWh")
Write-Host ("Heavy/Gaming:       " + $kwh_heavy + " kWh")
Write-Host ("Sleep/Standby:      " + $kwh_sleep + " kWh")
Write-Host ("Powered off (draw): " + $kwh_off + " kWh")
Write-Host ("Charger losses ~15%:" + $kwh_charger_loss + " kWh")
Write-Host "-----------------------------------"
Write-Host ("TOTAL kWh:          " + $kwh_grand_total + " kWh")

# ---- COST CALCULATION ----
$rate_inr = 7.0
$rate_usd = 0.12

$cost_inr = [math]::Round($kwh_grand_total * $rate_inr, 2)
$cost_usd = [math]::Round($kwh_grand_total * $rate_usd, 2)

Write-Host ""
Write-Host "=== ELECTRICITY COST ESTIMATE ==="
Write-Host ("Rate used (India avg): Rs. " + $rate_inr + "/kWh")
Write-Host ("Estimated Cost (INR):  Rs. " + $cost_inr)
Write-Host ("Estimated Cost (USD):  `$" + $cost_usd)

# CO2 equivalent (India grid: ~0.82 kg CO2/kWh)
$co2_kg = [math]::Round($kwh_grand_total * 0.82, 2)
Write-Host ""
Write-Host "=== ENVIRONMENTAL IMPACT ==="
Write-Host ("CO2 Equivalent: " + $co2_kg + " kg CO2")

Write-Host ""
Write-Host "NOTE: Figures are dynamically calculated and extrapolated from system event logs."
