# Power and Uptime Analysis Script
$startDate = Get-Date "2026-01-01T00:00:00"
$endDate = Get-Date

Write-Host "=== HARDWARE INFO ==="
$cpu = Get-CimInstance Win32_Processor | Select-Object Name, MaxClockSpeed, NumberOfCores, NumberOfLogicalProcessors
$gpu = Get-CimInstance Win32_VideoController | Select-Object Name, AdapterRAM

$cpu | Format-List
$gpu | Format-List

Write-Host "=== EVENT LOG SYSTEM UPTIME ESTIMATION (Since Jan 1 2026) ==="
try {
    # 6005: Event log service started (System boot)
    # 6006: Event log service stopped (System shutdown)
    # 1: System resumed from sleep/hibernate (Kernel-General)
    # 42: System entering sleep (Kernel-Power)
    # 1074: System shutdown/restart initiated
    $events = Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$startDate; Id=@(6005,6006,1,42,1074)} -ErrorAction SilentlyContinue | Sort-Object TimeCreated

    if ($null -eq $events -or $events.Count -eq 0) {
        Write-Host "No lifecycle events found in Event Log since Jan 1, 2026."
        Write-Host "Checking earliest available event..."
        $earliest = Get-WinEvent -ListLog System -ErrorAction SilentlyContinue | Select-Object OldestRecordNumber, RecordCount
        $earliest | Format-List
    } else {
        Write-Host "Found $($events.Count) relevant system lifecycle events since Jan 1, 2026."
        Write-Host "First record timestamp: $($events[0].TimeCreated)"
        Write-Host "Last record timestamp: $($events[-1].TimeCreated)"

        $totalActiveSeconds = 0
        $isPoweredOn = $false
        $lastStateChangeTime = $events[0].TimeCreated

        # Iterate through events to calculate running windows
        foreach ($e in $events) {
            $eTime = $e.TimeCreated
            $eId = $e.Id

            if ($eId -eq 6005 -or $eId -eq 1) {
                # Power on / Resume event
                if (-not $isPoweredOn) {
                    $isPoweredOn = $true
                    $lastStateChangeTime = $eTime
                }
            }
            elseif ($eId -eq 6006 -or $eId -eq 42 -or $eId -eq 1074) {
                # Shutdown / Sleep event
                if ($isPoweredOn) {
                    $span = ($eTime - $lastStateChangeTime).TotalSeconds
                    if ($span -gt 0) {
                        $totalActiveSeconds += $span
                    }
                    $isPoweredOn = $false
                }
            }
        }

        # If currently powered on, add time from last state change until now
        if ($isPoweredOn) {
            $span = ($endDate - $lastStateChangeTime).TotalSeconds
            if ($span -gt 0) {
                $totalActiveSeconds += $span
            }
        }

        $activeHours = [math]::Round($totalActiveSeconds / 3600, 2)
        $activeDays = [math]::Round($activeHours / 24, 2)

        # Calculate uptime percentage based on actual log coverage date span
        $logStart = $events[0].TimeCreated
        $logSpanDays = [math]::Round([math]::Max(0.1, ($endDate - $logStart).TotalDays), 2)
        $uptimePercentLogPeriod = [math]::Round(($activeHours / ($logSpanDays * 24)) * 100, 2)

        $totalDaysPeriod = [math]::Round(($endDate - $startDate).TotalDays, 2)
        $extrapolatedActiveHours = [math]::Round(($activeHours / $logSpanDays) * $totalDaysPeriod, 2)

        Write-Host ""
        Write-Host "=== UPTIME SUMMARY ==="
        Write-Host "Log Data Period    : $($logStart.ToString('yyyy-MM-dd HH:mm')) to $($endDate.ToString('yyyy-MM-dd HH:mm')) ($logSpanDays days)"
        Write-Host "Total Active Uptime: $activeHours hours ($activeDays days)"
        Write-Host "Active Percentage  : $uptimePercentLogPeriod % (during recorded period)"
        Write-Host "Projected Full Year: $extrapolatedActiveHours active hours (since Jan 1, 2026)"
    }
} catch {
    Write-Host "Error querying system event logs: $_"
}

# Check SRUM (System Resource Usage Monitor) or PowerCfg if available
Write-Host ""
Write-Host "=== BATTERY / POWER ENERGY REPORT CHECK ==="
try {
    $srumExists = Test-Path "C:\Windows\System32\SRU\SRUDB.dat" -ErrorAction SilentlyContinue
    Write-Host "SRUM Data Store Present: $srumExists"
} catch {
    Write-Host "SRUM check skipped."
}
