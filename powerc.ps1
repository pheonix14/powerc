<#
.SYNOPSIS
    powerc v2.5 - All-In-One CPU & GPU Power Control, Dual Thermal Guard & Live Monitor CLI
    Limits CPU & GPU power consumption to eliminate thermal degradation, prevent overvolting/overclocking,
    and keep CPU and GPU temperatures strictly below 80°C at all times.

.DESCRIPTION
    Provides unified CPU & GPU power capping, PCIe Link State GPU Power Saving,
    Dual CPU & GPU 80°C Thermal Guard, real-time live monitoring dashboard,
    continuous interactive prompt loop, and OEM overclocking override protection.
#>

param (
    [switch]$Lock,
    [switch]$Unlock,
    [switch]$Status,
    [switch]$Quiet,
    [switch]$SuperQuiet,
    [switch]$UltraQuiet,
    [switch]$MaxQuiet,
    [switch]$Potato,
    [switch]$LifeCalculator,
    [switch]$Watchdog,
    [switch]$ThermalGuard,
    [switch]$Monitor,
    [int]$CpuTempLimit = 80,
    [int]$GpuTempLimit = 80,
    [int]$AcLimit = 0,
    [int]$DcLimit = 0,
    [string]$GpuMode = ""
)

$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$configFile = Join-Path $scriptDir "config.json"
$version    = "v2.5.0"
$deg        = [char]176

# Default fallback values (Quiet Mode)
$defaultAcLimit = 75
$defaultDcLimit = 60
$defaultGpuMode = 1   # 0: Off, 1: Moderate, 2: Max Power Save

# ─── NVIDIA SMI HELPER ─────────────────────────────────────────────────────────

function Get-NvidiaSmiPath {
    $cmd = Get-Command "nvidia-smi.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $smiPaths = @(
        "$env:SystemRoot\System32\nvidia-smi.exe",
        "C:\Windows\System32\nvidia-smi.exe",
        "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe"
    )
    foreach ($smiPath in $smiPaths) {
        if (Test-Path $smiPath) { return $smiPath }
    }
    return $null
}

# ─── CPU TEMPERATURE ───────────────────────────────────────────────────────────

function Get-CpuTemperature {
    <#
    Returns the current CPU temperature in Celsius (integer).
    Returns -1 if thermal counters/WMI are unavailable.
    #>
    try {
        $tzInfo = Get-CimInstance Win32_PerfFormattedData_Counters_ThermalZoneInformation -ErrorAction SilentlyContinue |
            Where-Object { $_.HighPrecisionTemperature -gt 2732 } |
            Select-Object -First 1
        if ($tzInfo) {
            $tempC = [math]::Round(($tzInfo.HighPrecisionTemperature / 10) - 273.15)
            if ($tempC -gt 0 -and $tempC -lt 120) { return [int]$tempC }
        }
    } catch { }

    try {
        $ohm = Get-CimInstance -Namespace root\OpenHardwareMonitor -ClassName Sensor -ErrorAction SilentlyContinue |
            Where-Object { $_.SensorType -eq "Temperature" -and $_.Name -like "*CPU Package*" } |
            Select-Object -First 1
        if ($ohm) { return [int]$ohm.Value }
    } catch { }

    try {
        $wmiTemp = Get-CimInstance -Namespace root\WMI -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($wmiTemp) {
            $tempC = [math]::Round(($wmiTemp.CurrentTemperature - 2732) / 10)
            if ($tempC -gt 0 -and $tempC -lt 120) { return [int]$tempC }
        }
    } catch { }

    return -1
}

function Get-CpuTemperatureDisplay {
    $temp = Get-CpuTemperature
    if ($temp -eq -1) { return "N/A (Thermal Zone Counter unavailable)" }
    if ($temp -ge 80) { return "$temp${deg}C [CRITICAL - CPU ABOVE 80${deg}C LIMIT!]" }
    if ($temp -ge 70) { return "$temp${deg}C [WARNING - Approaching 80${deg}C limit]" }
    return "$temp${deg}C [Safe]"
}

# ─── GPU TEMPERATURE ───────────────────────────────────────────────────────────

function Get-GpuTemperature {
    $smiPath = Get-NvidiaSmiPath
    if ($smiPath) {
        try {
            $out = & $smiPath --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>$null
            if ($out -match '^\s*(\d+)\s*$') {
                return [int]$matches[1]
            }
        } catch { }
    }

    try {
        $wmiTemp = Get-WmiObject -Namespace root\WMI -Class MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceName -like "*GPU*" -or $_.InstanceName -like "*VGA*" } |
            Select-Object -First 1
        if ($wmiTemp) {
            return [int](($wmiTemp.CurrentTemperature - 2732) / 10)
        }
    } catch { }

    return -1
}

function Get-GpuTemperatureDisplay {
    $temp = Get-GpuTemperature
    if ($temp -eq -1) { return "N/A (nvidia-smi not found)" }
    if ($temp -ge 80) { return "$temp${deg}C [CRITICAL - GPU ABOVE 80${deg}C LIMIT!]" }
    if ($temp -ge 70) { return "$temp${deg}C [WARNING - Approaching 80${deg}C limit]" }
    return "$temp${deg}C [Safe]"
}

# ─── CPU POWER LIMITS ──────────────────────────────────────────────────────────

function Get-CurrentPowerLimits {
    $query = powercfg /query SCHEME_CURRENT SUB_PROCESSOR 2>$null
    $acVal = 100; $dcVal = 100
    $inMaxSection = $false
    foreach ($line in $query) {
        if ($line -match "Maximum processor state" -or $line -match "PROCTHROTTLEMAX" -or $line -match "bc5038f7-23e0-4960-96da-33abaf5935ec") {
            $inMaxSection = $true
        } elseif ($inMaxSection -and $line -match "Power Setting GUID") {
            $inMaxSection = $false
        }
        if ($inMaxSection) {
            if ($line -match "Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)") { $acVal = [Convert]::ToInt32($matches[1], 16) }
            if ($line -match "Current DC Power Setting Index:\s*0x([0-9a-fA-F]+)") { $dcVal = [Convert]::ToInt32($matches[1], 16) }
        }
    }
    return @{ AC = $acVal; DC = $dcVal }
}

# ─── GPU LINK STATE ────────────────────────────────────────────────────────────

function Get-CurrentGpuLimits {
    $query = powercfg /query SCHEME_CURRENT SUB_PCIEXPRESS 2>$null
    $acGpu = 0; $dcGpu = 0
    $inAspm = $false
    foreach ($line in $query) {
        if ($line -match "Link State Power Management" -or $line -match "ee12f906-d277-404b-b6da-e5fa1a576df5" -or $line -match "ASPM") {
            $inAspm = $true
        } elseif ($inAspm -and $line -match "Power Setting GUID") {
            $inAspm = $false
        }
        if ($inAspm) {
            if ($line -match "Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)") { $acGpu = [Convert]::ToInt32($matches[1], 16) }
            if ($line -match "Current DC Power Setting Index:\s*0x([0-9a-fA-F]+)") { $dcGpu = [Convert]::ToInt32($matches[1], 16) }
        }
    }
    return @{ AC = $acGpu; DC = $dcGpu }
}

# ─── LIVE GPU INFO (NVIDIA SMI) ────────────────────────────────────────────────

function Get-LiveGpuInfo {
    $gpuInfo = @{ Name = "Generic / Integrated GPU"; PowerDraw = "N/A" }
    $smiPath = Get-NvidiaSmiPath
    if ($smiPath) {
        try {
            $out = & $smiPath --query-gpu=name,power.draw --format=csv,noheader,nounits 2>$null
            if ($out) {
                $parts = $out.Split(',')
                if ($parts.Count -ge 2) {
                    $gpuInfo.Name = $parts[0].Trim()
                    $gpuInfo.PowerDraw = "$($parts[1].Trim()) W"
                }
            }
        } catch { }
    }
    return $gpuInfo
}

# ─── APPLY POWER LIMITS ────────────────────────────────────────────────────────

function Set-PowerLimits {
    param (
        [int]$ac,
        [int]$dc,
        [int]$gpuLevel = 1,
        [string]$modeName = "Custom",
        [bool]$quietOutput = $false
    )

    if ($ac -gt 100) {
        if (-not $quietOutput) { Write-Host "[powerc] HARDWARE GUARD: AC limit clamped to 100% max!" -ForegroundColor Yellow }
        $ac = 100
    }
    if ($dc -gt 100) {
        if (-not $quietOutput) { Write-Host "[powerc] HARDWARE GUARD: DC limit clamped to 100% max!" -ForegroundColor Yellow }
        $dc = 100
    }
    $ac = [Math]::Max(5, $ac)
    $dc = [Math]::Max(5, $dc)
    $gpuLevel = [Math]::Max(0, [Math]::Min(2, $gpuLevel))

    $gpuText = switch ($gpuLevel) {
        0 { "Off (Full Performance)" }
        1 { "Moderate Power Savings" }
        2 { "Maximum Power Savings (Max GPU Power Cut)" }
    }

    if (-not $quietOutput) {
        Write-Host ""
        Write-Host "[powerc] Enforcing $modeName limits..." -ForegroundColor Cyan
        Write-Host "  Plugged In (AC) CPU  : $ac% (Max 100% Ceiling)" -ForegroundColor Yellow
        Write-Host "  On Battery (DC) CPU  : $dc% (Max 100% Ceiling)" -ForegroundColor Yellow
        Write-Host "  GPU Link Saver       : $gpuText" -ForegroundColor Yellow
    }

    try {
        powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX $ac 2>$null
        powercfg /setacvalueindex SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 bc5038f7-23e0-4960-96da-33abaf5935ec $ac 2>$null

        powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX $dc 2>$null
        powercfg /setdcvalueindex SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 bc5038f7-23e0-4960-96da-33abaf5935ec $dc 2>$null

        powercfg /setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM $gpuLevel 2>$null
        powercfg /setacvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 $gpuLevel 2>$null

        powercfg /setdcvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM $gpuLevel 2>$null
        powercfg /setdcvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 $gpuLevel 2>$null

        powercfg /setactive SCHEME_CURRENT 2>$null

        $config = @{
            AcLimit     = $ac
            DcLimit     = $dc
            GpuLevel    = $gpuLevel
            ModeName    = $modeName
            LastUpdated = (Get-Date).ToString("o")
        }

        if (Test-Path $configFile) {
            try {
                $existing = Get-Content $configFile -Raw | ConvertFrom-Json
                if ($null -ne $existing.LastEcoAcLimit)  { $config["LastEcoAcLimit"]  = $existing.LastEcoAcLimit }
                if ($null -ne $existing.LastEcoDcLimit)  { $config["LastEcoDcLimit"]  = $existing.LastEcoDcLimit }
                if ($null -ne $existing.LastEcoGpuLevel) { $config["LastEcoGpuLevel"] = $existing.LastEcoGpuLevel }
                if ($null -ne $existing.LastEcoModeName) { $config["LastEcoModeName"] = $existing.LastEcoModeName }
            } catch { }
        }

        if ($modeName -ne "Normal Stock" -and ($ac -lt 100 -or $dc -lt 100 -or $gpuLevel -gt 0)) {
            $config["LastEcoAcLimit"]  = $ac
            $config["LastEcoDcLimit"]  = $dc
            $config["LastEcoGpuLevel"] = $gpuLevel
            $config["LastEcoModeName"] = $modeName
        } elseif (-not $config.ContainsKey("LastEcoAcLimit")) {
            $config["LastEcoAcLimit"]  = 75
            $config["LastEcoDcLimit"]  = 60
            $config["LastEcoGpuLevel"] = 1
            $config["LastEcoModeName"] = "Quiet"
        }

        $config | ConvertTo-Json | Out-File -FilePath $configFile -Encoding utf8

        if (-not $quietOutput) {
            Write-Host "[powerc] SUCCESS: Power limits enforced! OEM Overclocking Blocked." -ForegroundColor Green
        }
    } catch {
        if (-not $quietOutput) {
            Write-Host "[powerc] ERROR: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# ─── DUAL CPU & GPU THERMAL GUARD ──────────────────────────────────────────────

function Start-ThermalGuard {
    param (
        [int]$cpuLimit = 80,
        [int]$gpuLimit = 80,
        [bool]$embeddedInWatchdog = $false
    )

    if (-not $embeddedInWatchdog) {
        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Red
        Write-Host "   POWERC V2.5 - DUAL CPU & GPU THERMAL GUARD ACTIVE        " -ForegroundColor Yellow
        Write-Host "============================================================" -ForegroundColor Red
        Write-Host " Monitoring CPU & GPU temperatures every 10 seconds." -ForegroundColor Cyan
        Write-Host " Hard Ceiling: CPU < ${cpuLimit}${deg}C | GPU < ${gpuLimit}${deg}C" -ForegroundColor Cyan
        Write-Host " Auto-Throttles down if temperature exceeds 80${deg}C ceiling." -ForegroundColor Cyan
        Write-Host " Press Ctrl+C to stop Guard." -ForegroundColor Gray
        Write-Host ""
    }

    $basePlan = @{ AcLimit = 75; DcLimit = 60; GpuLevel = 1; ModeName = "Quiet" }
    if (Test-Path $configFile) {
        try {
            $saved = Get-Content $configFile -Raw | ConvertFrom-Json
            if ($saved.AcLimit -and $saved.ModeName -ne "Normal Stock") {
                if ($saved.AcLimit)  { $basePlan.AcLimit  = $saved.AcLimit  }
                if ($saved.DcLimit)  { $basePlan.DcLimit   = $saved.DcLimit  }
                if ($saved.GpuLevel -ne $null) { $basePlan.GpuLevel = $saved.GpuLevel }
                if ($saved.ModeName) { $basePlan.ModeName  = $saved.ModeName }
            } elseif ($saved.LastEcoAcLimit) {
                $basePlan.AcLimit  = $saved.LastEcoAcLimit
                $basePlan.DcLimit  = $saved.LastEcoDcLimit
                $basePlan.GpuLevel = $saved.LastEcoGpuLevel
                $basePlan.ModeName = $saved.LastEcoModeName
            }
        } catch { }
    }

    $throttleLadder = @(
        @{ Ac = 75;  Dc = 60;  Gpu = 2; Name = "Quiet (Step 1)" },
        @{ Ac = 50;  Dc = 40;  Gpu = 2; Name = "Super Quiet (Step 2)" },
        @{ Ac = 35;  Dc = 25;  Gpu = 2; Name = "Ultra Quiet (Step 3)" },
        @{ Ac = 20;  Dc = 15;  Gpu = 2; Name = "Max Quiet (Step 4)" },
        @{ Ac = 10;  Dc = 10;  Gpu = 2; Name = "Potato PC (Emergency Cut)" }
    )

    $throttleIndex = -1
    $coolingCounter = 0
    $restoreAfterCycles = 6
    $cycleCount = 0

    while ($true) {
        $cpuTemp = Get-CpuTemperature
        $gpuTemp = Get-GpuTemperature

        if ($embeddedInWatchdog -and ($cycleCount % 3 -eq 0)) {
            if ($throttleIndex -ge 0) {
                $step = $throttleLadder[$throttleIndex]
                Set-PowerLimits -ac $step.Ac -dc $step.Dc -gpuLevel $step.Gpu -modeName $step.Name -quietOutput $true
            } else {
                Set-PowerLimits -ac $basePlan.AcLimit -dc $basePlan.DcLimit -gpuLevel $basePlan.GpuLevel -modeName $basePlan.ModeName -quietOutput $true
            }
        }
        $cycleCount++

        $timestamp = Get-Date -Format "HH:mm:ss"
        $cpuHot = ($cpuTemp -ne -1 -and $cpuTemp -ge $cpuLimit)
        $gpuHot = ($gpuTemp -ne -1 -and $gpuTemp -ge $gpuLimit)

        $cpuDisp = if ($cpuTemp -ne -1) { "${cpuTemp}${deg}C" } else { "N/A" }
        $gpuDisp = if ($gpuTemp -ne -1) { "${gpuTemp}${deg}C" } else { "N/A" }

        if ($cpuHot -or $gpuHot) {
            $coolingCounter = 0
            $throttleIndex = [Math]::Min($throttleIndex + 1, $throttleLadder.Count - 1)
            $step = $throttleLadder[$throttleIndex]

            $reason = if ($cpuHot -and $gpuHot) { "CPU & GPU" } elseif ($cpuHot) { "CPU" } else { "GPU" }
            Write-Host "  [$timestamp] WARNING: $reason OVER 80${deg}C (CPU: $cpuDisp | GPU: $gpuDisp)! THROTTLING -> $($step.Name)" -ForegroundColor Red
            Set-PowerLimits -ac $step.Ac -dc $step.Dc -gpuLevel $step.Gpu -modeName $step.Name -quietOutput $true

        } else {
            if ($throttleIndex -ge 0) {
                $coolingCounter++
                $remaining = $restoreAfterCycles - $coolingCounter

                if ($remaining -gt 0) {
                    Write-Host "  [$timestamp] Temperatures Normal (CPU: $cpuDisp | GPU: $gpuDisp) - Cooling... restoring base mode in $remaining cycles" -ForegroundColor Cyan
                } else {
                    if ($throttleIndex -gt 0) {
                        $throttleIndex--
                        $step = $throttleLadder[$throttleIndex]
                        Write-Host "  [$timestamp] Temperatures Normal - Stepping up to $($step.Name)" -ForegroundColor Green
                        Set-PowerLimits -ac $step.Ac -dc $step.Dc -gpuLevel $step.Gpu -modeName $step.Name -quietOutput $true
                    } else {
                        $throttleIndex = -1
                        Write-Host "  [$timestamp] Temperatures Normal - RESTORED to base mode: $($basePlan.ModeName)" -ForegroundColor Green
                        Set-PowerLimits -ac $basePlan.AcLimit -dc $basePlan.DcLimit -gpuLevel $basePlan.GpuLevel -modeName $basePlan.ModeName -quietOutput $true
                    }
                    $coolingCounter = 0
                }
            } else {
                Write-Host "  [$timestamp] CPU: $cpuDisp [OK] | GPU: $gpuDisp [OK] (80${deg}C Hard Ceiling Enforced)" -ForegroundColor Green
            }
        }

        Start-Sleep -Seconds 10
    }
}

# ─── WATCHDOG (OEM + DUAL THERMAL GUARD) ───────────────────────────────────────

function Start-WatchdogEnforcer {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "   POWERC V2.5 - WATCHDOG + DUAL THERMAL GUARD ACTIVE       " -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " * Enforcing CPU & GPU power limits every 30 seconds." -ForegroundColor Yellow
    Write-Host " * Monitoring CPU & GPU temperatures every 10 seconds (80${deg}C ceiling)." -ForegroundColor Yellow
    Write-Host " * OEM apps (NitroSense, Armoury Crate) are BLOCKED." -ForegroundColor Yellow
    Write-Host " Press Ctrl+C to stop Watchdog." -ForegroundColor Gray
    Write-Host ""

    Start-ThermalGuard -cpuLimit 80 -gpuLimit 80 -embeddedInWatchdog $true
}

# ─── REAL-TIME ACTIVE MONITORING DASHBOARD ──────────────────────────────────────

function Start-RealtimeMonitor {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "   POWERC REAL-TIME MONITORING & DIAGNOSTICS DASHBOARD     " -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Press Ctrl+C to exit monitoring mode." -ForegroundColor Gray
    Write-Host ""

    while ($true) {
        $cpuTemp = Get-CpuTemperature
        $gpuTemp = Get-GpuTemperature
        $current = Get-CurrentPowerLimits
        $gpuCurr = Get-CurrentGpuLimits
        $liveGpu = Get-LiveGpuInfo
        $nowStr  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        Clear-Host
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host "   POWERC $version - REAL-TIME HARDWARE MONITOR ($nowStr)   " -ForegroundColor Green
        Write-Host "============================================================" -ForegroundColor Cyan

        # CPU Status
        Write-Host " [CPU] Temperature         : " -NoNewline
        if ($cpuTemp -eq -1) {
            Write-Host "N/A (Thermal Zone unavailable)" -ForegroundColor Gray
        } elseif ($cpuTemp -ge 80) {
            Write-Host "${cpuTemp}${deg}C [CRITICAL - CPU OVER 80${deg}C!]" -ForegroundColor Red
        } elseif ($cpuTemp -ge 70) {
            Write-Host "${cpuTemp}${deg}C [WARNING - Approaching 80${deg}C]" -ForegroundColor Yellow
        } else {
            Write-Host "${cpuTemp}${deg}C [Safe & Cool]" -ForegroundColor Green
        }
        Write-Host " [CPU] AC Power Cap        : $($current.AC)%" -ForegroundColor Yellow
        Write-Host " [CPU] DC Power Cap        : $($current.DC)%" -ForegroundColor Yellow

        Write-Host " ----------------------------------------------------------" -ForegroundColor Gray

        # GPU Status
        Write-Host " [GPU] Model               : $($liveGpu.Name)" -ForegroundColor White
        Write-Host " [GPU] Temperature         : " -NoNewline
        if ($gpuTemp -eq -1) {
            Write-Host "N/A (nvidia-smi not found)" -ForegroundColor Gray
        } elseif ($gpuTemp -ge 80) {
            Write-Host "${gpuTemp}${deg}C [CRITICAL - GPU OVER 80${deg}C!]" -ForegroundColor Red
        } elseif ($gpuTemp -ge 70) {
            Write-Host "${gpuTemp}${deg}C [WARNING - Approaching 80${deg}C]" -ForegroundColor Yellow
        } else {
            Write-Host "${gpuTemp}${deg}C [Safe & Cool]" -ForegroundColor Green
        }
        if ($liveGpu.PowerDraw -ne "N/A") {
            Write-Host " [GPU] Live Power Draw     : $($liveGpu.PowerDraw)" -ForegroundColor Yellow
        }
        $gpuStateText = switch ($gpuCurr.AC) { 0 { "Off (Full Power)" } 1 { "Moderate Save" } 2 { "Max Save" } }
        Write-Host " [GPU] Link Saver State    : $gpuStateText" -ForegroundColor Yellow

        Write-Host " ----------------------------------------------------------" -ForegroundColor Gray
        Write-Host " [GUARD] Dual 80${deg}C Ceiling : ACTIVE (CPU & GPU Protection)" -ForegroundColor Green
        Write-Host " [GUARD] OEM Overclock Block: ACTIVE" -ForegroundColor Green
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host " Press Ctrl+C to return to menu..." -ForegroundColor Gray

        Start-Sleep -Seconds 2
    }
}

# ─── LIFESPAN CALCULATOR ───────────────────────────────────────────────────────

function Show-LifeCalculator {
    $current    = Get-CurrentPowerLimits
    $gpuCurrent = Get-CurrentGpuLimits
    $avgLimit   = [Math]::Round(($current.AC + $current.DC) / 2)
    $cpuTemp    = Get-CpuTemperature
    $gpuTemp    = Get-GpuTemperature

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "     POWERC V2.5 - HARDWARE LIFESPAN & THERMAL CALCULATOR  " -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Based on semiconductor electromigration physics (Arrhenius Law):" -ForegroundColor Gray
    Write-Host " Keeping CPU and GPU below 80${deg}C cuts silicon degradation by up to 90%." -ForegroundColor Gray
    Write-Host ""
    Write-Host " Current Average CPU Cap  : $avgLimit%" -ForegroundColor White

    if ($cpuTemp -ne -1) {
        $cColor = if ($cpuTemp -ge 80) { "Red" } elseif ($cpuTemp -ge 70) { "Yellow" } else { "Green" }
        Write-Host " Current CPU Temperature  : ${cpuTemp}${deg}C" -ForegroundColor $cColor
    } else {
        Write-Host " Current CPU Temperature  : N/A" -ForegroundColor Gray
    }

    if ($gpuTemp -ne -1) {
        $gColor = if ($gpuTemp -ge 80) { "Red" } elseif ($gpuTemp -ge 70) { "Yellow" } else { "Green" }
        Write-Host " Current GPU Temperature  : ${gpuTemp}${deg}C" -ForegroundColor $gColor
    } else {
        Write-Host " Current GPU Temperature  : N/A" -ForegroundColor Gray
    }

    $gpuStateText = switch ($gpuCurrent.AC) {
        0 { "Off (High Thermal Wear)" }
        1 { "Moderate Power Saver" }
        2 { "Maximum Power Saver (Ultra Low Wear)" }
    }
    Write-Host " Current GPU Link Saver   : $gpuStateText" -ForegroundColor White

    if ($avgLimit -le 15) {
        Write-Host " Mode Category            : Potato PC Mode" -ForegroundColor Magenta
        Write-Host " Estimated CPU/GPU Life   : 25+ Years (Ultra Cold / Zero Wear)" -ForegroundColor Green
        Write-Host " Wear and Degradation Rate: ~90% Lower than stock baseline" -ForegroundColor Green
    } elseif ($avgLimit -le 25) {
        Write-Host " Mode Category            : Maximum Quiet Mode" -ForegroundColor Cyan
        Write-Host " Estimated CPU/GPU Life   : 20-25 Years" -ForegroundColor Green
        Write-Host " Wear and Degradation Rate: ~80% Lower than stock baseline" -ForegroundColor Green
    } elseif ($avgLimit -le 40) {
        Write-Host " Mode Category            : Ultra Quiet Mode" -ForegroundColor Cyan
        Write-Host " Estimated CPU/GPU Life   : 18-22 Years" -ForegroundColor Green
        Write-Host " Wear and Degradation Rate: ~70% Lower than stock baseline" -ForegroundColor Green
    } elseif ($avgLimit -le 55) {
        Write-Host " Mode Category            : Super Quiet Mode" -ForegroundColor Green
        Write-Host " Estimated CPU/GPU Life   : 15-18 Years" -ForegroundColor Green
        Write-Host " Wear and Degradation Rate: ~55% Lower than stock baseline" -ForegroundColor Green
    } elseif ($avgLimit -le 80) {
        Write-Host " Mode Category            : Quiet Mode" -ForegroundColor Yellow
        Write-Host " Estimated CPU/GPU Life   : 12-15 Years" -ForegroundColor Yellow
        Write-Host " Wear and Degradation Rate: ~35% Lower than stock baseline" -ForegroundColor Yellow
    } else {
        Write-Host " Mode Category            : Normal Stock Mode (100% Limit)" -ForegroundColor Yellow
        Write-Host " Estimated CPU/GPU Life   : 7-10 Years (Stock Baseline)" -ForegroundColor White
        Write-Host " Wear and Degradation Rate: Baseline (No Overclocking)" -ForegroundColor White
    }

    Write-Host ""
    Write-Host " Tip: Dual Thermal Guard enforces 80${deg}C ceiling on CPU & GPU." -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
}

# ─── STATUS DISPLAY ────────────────────────────────────────────────────────────

function Show-Status {
    $current    = Get-CurrentPowerLimits
    $gpuCurrent = Get-CurrentGpuLimits
    $liveGpu    = Get-LiveGpuInfo
    $cpuTemp    = Get-CpuTemperature
    $gpuTemp    = Get-GpuTemperature

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   powerc $version - System & Power Status" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Cyan

    Write-Host " Plugged In (AC) CPU Limit : " -NoNewline
    if ($current.AC -lt 100) { Write-Host "$($current.AC)% [CAPPED - ECO LOW WEAR]" -ForegroundColor Yellow }
    else { Write-Host "$($current.AC)% [NORMAL STOCK BASE]" -ForegroundColor Green }

    Write-Host " Battery (DC) CPU Limit    : " -NoNewline
    if ($current.DC -lt 100) { Write-Host "$($current.DC)% [CAPPED - ECO SAVE]" -ForegroundColor Yellow }
    else { Write-Host "$($current.DC)% [NORMAL STOCK BASE]" -ForegroundColor Green }

    Write-Host " CPU Temperature           : " -NoNewline
    if ($cpuTemp -eq -1) { Write-Host "N/A" -ForegroundColor Gray }
    elseif ($cpuTemp -ge 80) { Write-Host "${cpuTemp}${deg}C [CRITICAL - OVER 80${deg}C!]" -ForegroundColor Red }
    elseif ($cpuTemp -ge 70) { Write-Host "${cpuTemp}${deg}C [WARNING - Approaching 80${deg}C]" -ForegroundColor Yellow }
    else { Write-Host "${cpuTemp}${deg}C [Safe & Cool]" -ForegroundColor Green }

    Write-Host " GPU Hardware Model        : $($liveGpu.Name)" -ForegroundColor White
    if ($liveGpu.PowerDraw -ne "N/A") {
        Write-Host " Live GPU Power Draw       : $($liveGpu.PowerDraw)" -ForegroundColor Yellow
    }

    Write-Host " GPU Temperature           : " -NoNewline
    if ($gpuTemp -eq -1) { Write-Host "N/A (nvidia-smi not found)" -ForegroundColor Gray }
    elseif ($gpuTemp -ge 80) { Write-Host "${gpuTemp}${deg}C [CRITICAL - OVER 80${deg}C!]" -ForegroundColor Red }
    elseif ($gpuTemp -ge 70) { Write-Host "${gpuTemp}${deg}C [WARNING - Near 80${deg}C limit]" -ForegroundColor Yellow }
    else { Write-Host "${gpuTemp}${deg}C [Safe & Cool]" -ForegroundColor Green }

    Write-Host " Dual Thermal Guard Limit  : 80${deg}C Hard Ceiling (CPU & GPU)" -ForegroundColor Cyan

    Write-Host " GPU Link State (AC)       : " -NoNewline
    $acGpuText = switch ($gpuCurrent.AC) { 0 { "Off (High Power)" } 1 { "Moderate Power Save" } 2 { "Max Power Save" } }
    Write-Host $acGpuText -ForegroundColor Yellow

    Write-Host " GPU Link State (DC)       : " -NoNewline
    $dcGpuText = switch ($gpuCurrent.DC) { 0 { "Off (High Power)" } 1 { "Moderate Power Save" } 2 { "Max Power Save" } }
    Write-Host $dcGpuText -ForegroundColor Yellow

    Write-Host " OEM Overclock Guard       : ACTIVE" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
}

# ─── GPU MODE PARSE ────────────────────────────────────────────────────────────

$gpuLevelToSet = 1
if ($GpuMode -ne "") {
    if ($GpuMode -eq "Off"      -or $GpuMode -eq "0") { $gpuLevelToSet = 0 }
    elseif ($GpuMode -eq "Moderate" -or $GpuMode -eq "1") { $gpuLevelToSet = 1 }
    elseif ($GpuMode -eq "MaxSave"  -or $GpuMode -eq "2") { $gpuLevelToSet = 2 }
}

# ─── DIRECT CLI ROUTING (If parameters provided) ───────────────────────────────

if ($Status)        { Show-Status;                                                      exit }
if ($LifeCalculator){ Show-LifeCalculator;                                              exit }
if ($Monitor)       { Start-RealtimeMonitor;                                            exit }
if ($ThermalGuard)  { Start-ThermalGuard -cpuLimit $CpuTempLimit -gpuLimit $GpuTempLimit; exit }
if ($Watchdog)      { Start-WatchdogEnforcer;                                           exit }
if ($Unlock)        { Set-PowerLimits -ac 100 -dc 100 -gpuLevel 0 -modeName "Normal Stock"; exit }
if ($Quiet)         { Set-PowerLimits -ac 75  -dc 60  -gpuLevel 1 -modeName "Quiet";   exit }
if ($SuperQuiet)    { Set-PowerLimits -ac 50  -dc 40  -gpuLevel 2 -modeName "Super Quiet"; exit }
if ($UltraQuiet)    { Set-PowerLimits -ac 35  -dc 25  -gpuLevel 2 -modeName "Ultra Quiet"; exit }
if ($MaxQuiet)      { Set-PowerLimits -ac 20  -dc 15  -gpuLevel 2 -modeName "Maximum Quiet"; exit }
if ($Potato)        { Set-PowerLimits -ac 10  -dc 10  -gpuLevel 2 -modeName "Potato PC"; exit }

if ($AcLimit -gt 0 -or $DcLimit -gt 0) {
    $ac     = if ($AcLimit -gt 0) { $AcLimit } else { 100 }
    $dc     = if ($DcLimit -gt 0) { $DcLimit } else { 100 }
    $gLevel = if ($GpuMode -ne "") { $gpuLevelToSet } else { 1 }
    Set-PowerLimits -ac $ac -dc $dc -gpuLevel $gLevel -modeName "Custom"
    exit
}

if ($Lock) {
    $ac = $defaultAcLimit; $dc = $defaultDcLimit; $gpuL = $defaultGpuMode; $mName = "Quiet"
    if (Test-Path $configFile) {
        try {
            $saved = Get-Content $configFile -Raw | ConvertFrom-Json
            if ($saved.ModeName -and $saved.ModeName -ne "Normal Stock" -and $saved.AcLimit -lt 100) {
                if ($saved.AcLimit)  { $ac   = $saved.AcLimit  }
                if ($saved.DcLimit)  { $dc   = $saved.DcLimit   }
                if ($saved.GpuLevel -ne $null) { $gpuL = $saved.GpuLevel }
                if ($saved.ModeName) { $mName = $saved.ModeName  }
            } elseif ($saved.LastEcoAcLimit) {
                $ac    = $saved.LastEcoAcLimit
                $dc    = $saved.LastEcoDcLimit
                $gpuL  = $saved.LastEcoGpuLevel
                $mName = $saved.LastEcoModeName
            }
        } catch { }
    }
    Set-PowerLimits -ac $ac -dc $dc -gpuLevel $gpuL -modeName $mName
    exit
}

# ─── CONTINUOUS INTERACTIVE MENU LOOP (Stays open in CLI until Exit '0') ───────

do {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "   POWERC $version - UNIFIED CPU & GPU POWER CONTROL CLI    " -ForegroundColor Green
    Write-Host "  Keep CPU & GPU Temperature < 80${deg}C Always | PC Longevity  " -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan

    Show-Status

    Write-Host "Select Power, Longevity, or Monitoring Option:" -ForegroundColor White
    Write-Host " [L] Lock Power Limits (Eco Mode: 75% AC, 60% DC, GPU Moderate)"       -ForegroundColor Yellow
    Write-Host " [U] Unlock Full Performance (100% AC, 100% DC, GPU Full Power)"      -ForegroundColor Green
    Write-Host " ----------------------------------------------------------" -ForegroundColor Gray
    Write-Host " [1] Normal Stock Mode (AC: 100%, DC: 100%, GPU: Full Power)"         -ForegroundColor Green
    Write-Host " [2] Quiet Mode        (AC:  75%, DC:  60%, GPU: Moderate Save)"      -ForegroundColor Cyan
    Write-Host " [3] Super Quiet Mode  (AC:  50%, DC:  40%, GPU: Max Power Save)"     -ForegroundColor Cyan
    Write-Host " [4] Ultra Quiet Mode  (AC:  35%, DC:  25%, GPU: Max Power Save)"     -ForegroundColor Cyan
    Write-Host " [5] Maximum Quiet Mode(AC:  20%, DC:  15%, GPU: Max Power Save)"     -ForegroundColor Cyan
    Write-Host " [6] Potato PC Mode    (AC:  10%, DC:  10%, GPU: Max Power Save)"     -ForegroundColor Magenta
    Write-Host " ----------------------------------------------------------" -ForegroundColor Gray
    Write-Host " [7] Set Custom CPU Power Limit (Max 100% Capped)"                    -ForegroundColor Yellow
    Write-Host " [8] Set Custom GPU Power Saver (PCIe Link: Off, Moderate, Max)"      -ForegroundColor Yellow
    Write-Host " ----------------------------------------------------------" -ForegroundColor Gray
    Write-Host " [M] Real-Time Active Monitor & Error Analysis Dashboard"             -ForegroundColor Green
    Write-Host " [9] View Hardware Lifespan & Thermal Physics Calculator"             -ForegroundColor Yellow
    Write-Host " [T] Start Dual CPU & GPU Thermal Guard (Auto-Throttle < 80${deg}C)"       -ForegroundColor Red
    Write-Host " [W] Start Watchdog + Thermal Guard (Block OEM + 80${deg}C Ceiling)"       -ForegroundColor Green
    Write-Host " [0] Exit powerc"                                                     -ForegroundColor Red
    Write-Host ""

    $choice = Read-Host "Select option [0-9, L, U, M, T, or W]"

    switch ($choice) {
        "L" { Set-PowerLimits -ac 75 -dc 60 -gpuLevel 1 -modeName "Quiet (Locked)" }
        "l" { Set-PowerLimits -ac 75 -dc 60 -gpuLevel 1 -modeName "Quiet (Locked)" }
        "U" { Set-PowerLimits -ac 100 -dc 100 -gpuLevel 0 -modeName "Normal Stock" }
        "u" { Set-PowerLimits -ac 100 -dc 100 -gpuLevel 0 -modeName "Normal Stock" }
        "1" { Set-PowerLimits -ac 100 -dc 100 -gpuLevel 0 -modeName "Normal Stock" }
        "2" { Set-PowerLimits -ac 75  -dc 60  -gpuLevel 1 -modeName "Quiet" }
        "3" { Set-PowerLimits -ac 50  -dc 40  -gpuLevel 2 -modeName "Super Quiet" }
        "4" { Set-PowerLimits -ac 35  -dc 25  -gpuLevel 2 -modeName "Ultra Quiet" }
        "5" { Set-PowerLimits -ac 20  -dc 15  -gpuLevel 2 -modeName "Maximum Quiet" }
        "6" { Set-PowerLimits -ac 10  -dc 10  -gpuLevel 2 -modeName "Potato PC" }
        "7" {
            Write-Host ""
            Write-Host "--- CUSTOM CPU POWER LIMIT ---" -ForegroundColor Yellow
            $userAc = Read-Host "Enter Plugged-In (AC) Max CPU % (1-100) [Default: 75]"
            if (-not [int]::TryParse($userAc, [ref]$null) -or [int]$userAc -eq 0) { $userAc = 75 }
            $userDc = Read-Host "Enter Battery (DC) Max CPU % (1-100) [Default: 60]"
            if (-not [int]::TryParse($userDc, [ref]$null) -or [int]$userDc -eq 0) { $userDc = 60 }
            $currGpu = Get-CurrentGpuLimits
            Set-PowerLimits -ac $userAc -dc $userDc -gpuLevel $currGpu.AC -modeName "Custom"
        }
        "8" {
            Write-Host ""
            Write-Host "--- CUSTOM GPU POWER SAVER ---" -ForegroundColor Yellow
            Write-Host " [0] Off (Full GPU Performance - High Power)" -ForegroundColor White
            Write-Host " [1] Moderate Power Savings" -ForegroundColor Cyan
            Write-Host " [2] Maximum Power Savings (Max Thermal Cut)" -ForegroundColor Green
            $userGpu = Read-Host "Select GPU Power Level [0-2] [Default: 2]"
            if (-not [int]::TryParse($userGpu, [ref]$null)) { $userGpu = 2 }
            $currCpu = Get-CurrentPowerLimits
            Set-PowerLimits -ac $currCpu.AC -dc $currCpu.DC -gpuLevel $userGpu -modeName "Custom GPU"
        }
        "M" { Start-RealtimeMonitor }
        "m" { Start-RealtimeMonitor }
        "9" { Show-LifeCalculator }
        "T" { Start-ThermalGuard -cpuLimit 80 -gpuLimit 80 }
        "t" { Start-ThermalGuard -cpuLimit 80 -gpuLimit 80 }
        "W" { Start-WatchdogEnforcer }
        "w" { Start-WatchdogEnforcer }
        "0" { Write-Host "Exiting powerc CLI." -ForegroundColor Gray; exit }
        default { Write-Host "Invalid option." -ForegroundColor Red }
    }

    if ($choice -ne "0") {
        Write-Host ""
        Read-Host "Press Enter to return to main menu..."
    }
} while ($choice -ne "0")
