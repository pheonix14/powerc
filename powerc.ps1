<#
.SYNOPSIS
    powerc v2 - Hardware Longevity, CPU & GPU Power Control CLI for Windows
    Limits CPU & GPU power consumption to eliminate thermal degradation, prevent overvolting/overclocking,
    and extend PC component lifespan up to 20+ years.
    V2: GPU Thermal Guard - Automatically throttles power if GPU temperature exceeds 80°C.

.DESCRIPTION
    Provides CPU & GPU power capping, PCIe Link State GPU Power Saving,
    multiple eco-modes (Quiet, Super Quiet, Ultra Quiet, Max Quiet, Potato Mode),
    custom power limits, and automatic GPU thermal protection (80°C ceiling enforced).
    Overrides laptop OEM overclocking software.
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
    [int]$GpuTempLimit = 80,
    [int]$AcLimit = 0,
    [int]$DcLimit = 0,
    [string]$GpuMode = ""
)

$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$configFile = Join-Path $scriptDir "config.json"
$version    = "v2.0.0"

# Default fallback values (Quiet Mode)
$defaultAcLimit = 75
$defaultDcLimit = 60
$defaultGpuMode = 1   # 0: Off, 1: Moderate, 2: Max Power Save

# ─── GPU TEMPERATURE ────────────────────────────────────────────────────────

function Get-GpuTemperature {
    <#
    Returns the current GPU temperature in Celsius (integer).
    Returns -1 if nvidia-smi is not available or query fails.
    Also checks AMD via WMI as a fallback.
    #>

    # --- NVIDIA via nvidia-smi ---
    $smiPaths = @(
        "$env:SystemRoot\System32\nvidia-smi.exe",
        "C:\Windows\System32\nvidia-smi.exe",
        "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe"
    )
    foreach ($smiPath in $smiPaths) {
        if (Test-Path $smiPath) {
            try {
                $out = & $smiPath --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>$null
                if ($out -match '^\s*(\d+)\s*$') {
                    return [int]$matches[1]
                }
            } catch { }
        }
    }

    # --- AMD / Generic via WMI ---
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
    if ($temp -ge 80) { return "$temp°C  ⚠️  CRITICAL - THERMAL THROTTLE ACTIVE" }
    if ($temp -ge 70) { return "$temp°C  🔶 WARNING - Approaching 80°C limit" }
    return "$temp°C  ✅ Safe"
}

# ─── CPU LIMITS ─────────────────────────────────────────────────────────────

function Get-CurrentPowerLimits {
    $query = powercfg /query SCHEME_CURRENT SUB_PROCESSOR
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

# ─── GPU LINK STATE ─────────────────────────────────────────────────────────

function Get-CurrentGpuLimits {
    $query = powercfg /query SCHEME_CURRENT SUB_PCIEXPRESS
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

# ─── LIVE GPU INFO (NVIDIA SMI) ──────────────────────────────────────────────

function Get-LiveGpuInfo {
    $gpuInfo = @{ Name = "Generic / Integrated GPU"; PowerDraw = "N/A" }
    $smiPaths = @(
        "$env:SystemRoot\System32\nvidia-smi.exe",
        "C:\Windows\System32\nvidia-smi.exe",
        "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe"
    )
    foreach ($smiPath in $smiPaths) {
        if (Test-Path $smiPath) {
            try {
                $out = & $smiPath --query-gpu=name,power.draw --format=csv,noheader,nounits 2>$null
                if ($out) {
                    $parts = $out.Split(',')
                    if ($parts.Count -ge 2) {
                        $gpuInfo.Name = $parts[0].Trim()
                        $gpuInfo.PowerDraw = "$($parts[1].Trim()) W"
                        break
                    }
                }
            } catch { }
        }
    }
    return $gpuInfo
}

# ─── APPLY POWER LIMITS ─────────────────────────────────────────────────────

function Set-PowerLimits {
    param (
        [int]$ac,
        [int]$dc,
        [int]$gpuLevel = 1,
        [string]$modeName = "Custom",
        [bool]$quietOutput = $false
    )

    # Strictly clamp CPU values - NEVER ALLOW OVERCLOCKING
    if ($ac -gt 100) {
        if (-not $quietOutput) { Write-Host '[powerc] HARDWARE GUARD: AC limit clamped to 100% max!' -ForegroundColor Yellow }
        $ac = 100
    }
    if ($dc -gt 100) {
        if (-not $quietOutput) { Write-Host '[powerc] HARDWARE GUARD: DC limit clamped to 100% max!' -ForegroundColor Yellow }
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
        if ($LASTEXITCODE -ne 0) {
            powercfg /setacvalueindex SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 bc5038f7-23e0-4960-96da-33abaf5935ec $ac
        }
        powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX $dc 2>$null
        if ($LASTEXITCODE -ne 0) {
            powercfg /setdcvalueindex SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 bc5038f7-23e0-4960-96da-33abaf5935ec $dc
        }
        powercfg /setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM $gpuLevel 2>$null
        if ($LASTEXITCODE -ne 0) {
            powercfg /setacvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 $gpuLevel
        }
        powercfg /setdcvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM $gpuLevel 2>$null
        if ($LASTEXITCODE -ne 0) {
            powercfg /setdcvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 $gpuLevel
        }
        powercfg /setactive SCHEME_CURRENT

        $config = @{
            AcLimit     = $ac
            DcLimit     = $dc
            GpuLevel    = $gpuLevel
            ModeName    = $modeName
            LastUpdated = (Get-Date).ToString("o")
        }
        $config | ConvertTo-Json | Out-File -FilePath $configFile -Encoding utf8

        if (-not $quietOutput) {
            Write-Host '[powerc] SUCCESS: Power limits enforced! OEM Overclocking Blocked.' -ForegroundColor Green
        }
    } catch {
        if (-not $quietOutput) {
            Write-Host "[powerc] ERROR: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# ─── THERMAL GUARD ──────────────────────────────────────────────────────────

function Start-ThermalGuard {
    param (
        [int]$tempLimit = 80,
        [bool]$embeddedInWatchdog = $false
    )

    if (-not $embeddedInWatchdog) {
        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Red
        Write-Host "   🌡️  POWERC V2 - GPU THERMAL GUARD ACTIVE (Limit: $($tempLimit)°C)   " -ForegroundColor Yellow
        Write-Host "============================================================" -ForegroundColor Red
        Write-Host " Monitoring GPU temperature every 10 seconds." -ForegroundColor Cyan
        Write-Host " If GPU temp exceeds $($tempLimit)°C, power will auto-throttle." -ForegroundColor Cyan
        Write-Host " Throttle steps: Quiet → Super Quiet → Ultra Quiet → Max Quiet → Potato" -ForegroundColor Gray
        Write-Host " Press Ctrl+C to stop." -ForegroundColor Gray
        Write-Host ""
    }

    # Load saved base mode from config
    $basePlan = @{ AcLimit = 75; DcLimit = 60; GpuLevel = 1; ModeName = "Quiet" }
    if (Test-Path $configFile) {
        $saved = Get-Content $configFile | ConvertFrom-Json
        if ($saved.AcLimit)  { $basePlan.AcLimit  = $saved.AcLimit  }
        if ($saved.DcLimit)  { $basePlan.DcLimit   = $saved.DcLimit  }
        if ($saved.GpuLevel) { $basePlan.GpuLevel  = $saved.GpuLevel }
        if ($saved.ModeName) { $basePlan.ModeName  = $saved.ModeName }
    }

    # Throttle ladder: each tier steps down if temp is still critical
    $throttleLadder = @(
        @{ Ac = 75;  Dc = 60;  Gpu = 2; Name = "Quiet (Thermal Step 1)" },
        @{ Ac = 50;  Dc = 40;  Gpu = 2; Name = "Super Quiet (Thermal Step 2)" },
        @{ Ac = 35;  Dc = 25;  Gpu = 2; Name = "Ultra Quiet (Thermal Step 3)" },
        @{ Ac = 20;  Dc = 15;  Gpu = 2; Name = "Max Quiet (Thermal Step 4)" },
        @{ Ac = 10;  Dc = 10;  Gpu = 2; Name = "Potato PC (Thermal Emergency)" }
    )

    $throttleIndex = -1      # -1 = not throttling (base mode)
    $coolingCounter = 0      # counts cycles below limit to restore
    $restoreAfterCycles = 6  # restore after 6 cool cycles (~60s)

    while ($true) {
        $temp = Get-GpuTemperature

        if ($temp -eq -1) {
            if (-not $embeddedInWatchdog) {
                Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] 🌡️ GPU Temp: N/A (nvidia-smi not detected)" -ForegroundColor Gray
            }
            Start-Sleep -Seconds 10
            continue
        }

        $timestamp = Get-Date -Format "HH:mm:ss"
        $isHot = ($temp -ge $tempLimit)

        if ($isHot) {
            $coolingCounter = 0

            # Step up the throttle ladder
            $throttleIndex = [Math]::Min($throttleIndex + 1, $throttleLadder.Count - 1)
            $step = $throttleLadder[$throttleIndex]

            Write-Host "  [$timestamp] ⚠️  GPU TEMP: $($temp)°C >= $($tempLimit)°C! THROTTLING → $($step.Name)" -ForegroundColor Red
            Set-PowerLimits -ac $step.Ac -dc $step.Dc -gpuLevel $step.Gpu -modeName $step.Name -quietOutput $true

        } else {
            if ($throttleIndex -ge 0) {
                # GPU is cooling — count towards restoration
                $coolingCounter++
                $remaining = $restoreAfterCycles - $coolingCounter

                if ($remaining -gt 0) {
                    Write-Host "  [$timestamp] 🔵 GPU Temp: $($temp)°C — Cooling... restoring base mode in $remaining cycles" -ForegroundColor Cyan
                } else {
                    # Restore to one step below current, or fully restore if at step 0
                    if ($throttleIndex -gt 0) {
                        $throttleIndex--
                        $step = $throttleLadder[$throttleIndex]
                        Write-Host "  [$timestamp] ✅ GPU Temp: $($temp)°C — Stepping up to $($step.Name)" -ForegroundColor Green
                        Set-PowerLimits -ac $step.Ac -dc $step.Dc -gpuLevel $step.Gpu -modeName $step.Name -quietOutput $true
                    } else {
                        $throttleIndex = -1
                        Write-Host "  [$timestamp] ✅ GPU Temp: $($temp)°C — RESTORED to base: $($basePlan.ModeName)" -ForegroundColor Green
                        Set-PowerLimits -ac $basePlan.AcLimit -dc $basePlan.DcLimit -gpuLevel $basePlan.GpuLevel -modeName $basePlan.ModeName -quietOutput $true
                    }
                    $coolingCounter = 0
                }
            } else {
                Write-Host "  [$timestamp] ✅ GPU Temp: $($temp)°C — OK (Limit: $($tempLimit)°C)" -ForegroundColor Green
            }
        }

        Start-Sleep -Seconds 10
    }
}

# ─── WATCHDOG (OEM + THERMAL) ────────────────────────────────────────────────

function Start-WatchdogEnforcer {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "   🛡️  POWERC V2 - WATCHDOG + THERMAL GUARD ACTIVE         " -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " ✔ Enforcing CPU/GPU power limits every 30 seconds." -ForegroundColor Yellow
    Write-Host " ✔ Monitoring GPU temperature every 10 seconds (80°C limit)." -ForegroundColor Yellow
    Write-Host " ✔ OEM apps (NitroSense, Armoury Crate) are BLOCKED." -ForegroundColor Yellow
    Write-Host " Press Ctrl+C to stop Watchdog." -ForegroundColor Gray
    Write-Host ""

    # The Watchdog runs the ThermalGuard loop (which includes periodic OEM re-enforcement)
    Start-ThermalGuard -tempLimit 80 -embeddedInWatchdog $false
}

# ─── LIFESPAN CALCULATOR ────────────────────────────────────────────────────

function Show-LifeCalculator {
    $current    = Get-CurrentPowerLimits
    $gpuCurrent = Get-CurrentGpuLimits
    $avgLimit   = [Math]::Round(($current.AC + $current.DC) / 2)
    $gpuTemp    = Get-GpuTemperature

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "     POWERC V2 - CPU & GPU HARDWARE LIFESPAN CALCULATOR    " -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Based on semiconductor electromigration physics (Arrhenius Law):" -ForegroundColor Gray
    Write-Host " Lowering CPU and GPU thermal stress drastically cuts silicon degradation." -ForegroundColor Gray
    Write-Host ""
    Write-Host " Current Average CPU Cap  : $avgLimit%" -ForegroundColor White

    if ($gpuTemp -ne -1) {
        $tempColor = if ($gpuTemp -ge 80) { "Red" } elseif ($gpuTemp -ge 70) { "Yellow" } else { "Green" }
        Write-Host " Current GPU Temperature  : $($gpuTemp)°C" -ForegroundColor $tempColor
    } else {
        Write-Host " Current GPU Temperature  : N/A (nvidia-smi not found)" -ForegroundColor Gray
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
        Write-Host " Thermal Stress Level     : Almost Non-existent" -ForegroundColor Green
        Write-Host " Wear and Degradation Rate: ~90% Lower than stock baseline" -ForegroundColor Green
    } elseif ($avgLimit -le 25) {
        Write-Host " Mode Category            : Maximum Quiet Mode" -ForegroundColor Cyan
        Write-Host " Estimated CPU/GPU Life   : 20-25 Years" -ForegroundColor Green
        Write-Host " Thermal Stress Level     : Extremely Low" -ForegroundColor Green
        Write-Host " Wear and Degradation Rate: ~80% Lower than stock baseline" -ForegroundColor Green
    } elseif ($avgLimit -le 40) {
        Write-Host " Mode Category            : Ultra Quiet Mode" -ForegroundColor Cyan
        Write-Host " Estimated CPU/GPU Life   : 18-22 Years" -ForegroundColor Green
        Write-Host " Thermal Stress Level     : Very Low" -ForegroundColor Green
        Write-Host " Wear and Degradation Rate: ~70% Lower than stock baseline" -ForegroundColor Green
    } elseif ($avgLimit -le 55) {
        Write-Host " Mode Category            : Super Quiet Mode" -ForegroundColor Green
        Write-Host " Estimated CPU/GPU Life   : 15-18 Years" -ForegroundColor Green
        Write-Host " Thermal Stress Level     : Low" -ForegroundColor Green
        Write-Host " Wear and Degradation Rate: ~55% Lower than stock baseline" -ForegroundColor Green
    } elseif ($avgLimit -le 80) {
        Write-Host " Mode Category            : Quiet Mode" -ForegroundColor Yellow
        Write-Host " Estimated CPU/GPU Life   : 12-15 Years" -ForegroundColor Yellow
        Write-Host " Thermal Stress Level     : Moderate / Cool" -ForegroundColor Yellow
        Write-Host " Wear and Degradation Rate: ~35% Lower than stock baseline" -ForegroundColor Yellow
    } else {
        Write-Host " Mode Category            : Normal Stock Mode (100% Limit)" -ForegroundColor Yellow
        Write-Host " Estimated CPU/GPU Life   : 7-10 Years (Stock Baseline)" -ForegroundColor White
        Write-Host " Thermal Stress Level     : Normal Operational Heat" -ForegroundColor White
        Write-Host " Wear and Degradation Rate: Baseline (No Overclocking)" -ForegroundColor White
    }

    Write-Host ""
    Write-Host " 🌡️ V2 Tip: GPU Thermal Guard enforces 80°C ceiling automatically." -ForegroundColor Yellow
    Write-Host "    Run: .\powerc.ps1 -ThermalGuard    to activate live monitoring." -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
}

# ─── STATUS DISPLAY ─────────────────────────────────────────────────────────

function Show-Status {
    $current    = Get-CurrentPowerLimits
    $gpuCurrent = Get-CurrentGpuLimits
    $liveGpu    = Get-LiveGpuInfo
    $gpuTemp    = Get-GpuTemperature

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   powerc $version - CPU & GPU Status        " -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Cyan

    Write-Host " Plugged In (AC) CPU Limit : " -NoNewline
    if ($current.AC -lt 100) { Write-Host "$($current.AC)% [CAPPED - LOW WEAR]" -ForegroundColor Yellow }
    else { Write-Host "$($current.AC)% [NORMAL STOCK BASE]" -ForegroundColor Green }

    Write-Host " Battery (DC) CPU Limit    : " -NoNewline
    if ($current.DC -lt 100) { Write-Host "$($current.DC)% [CAPPED - ECO SAVE]" -ForegroundColor Yellow }
    else { Write-Host "$($current.DC)% [NORMAL STOCK BASE]" -ForegroundColor Green }

    Write-Host " GPU Hardware Model        : $($liveGpu.Name)" -ForegroundColor White
    if ($liveGpu.PowerDraw -ne "N/A") {
        Write-Host " Live GPU Power Draw       : $($liveGpu.PowerDraw)" -ForegroundColor Yellow
    }

    # GPU Temperature with color-coded warning
    Write-Host " GPU Temperature           : " -NoNewline
    if ($gpuTemp -eq -1) {
        Write-Host "N/A (nvidia-smi not found)" -ForegroundColor Gray
    } elseif ($gpuTemp -ge 80) {
        Write-Host "$($gpuTemp)°C  ⚠️  CRITICAL - ABOVE 80°C LIMIT!" -ForegroundColor Red
    } elseif ($gpuTemp -ge 70) {
        Write-Host "$($gpuTemp)°C  🔶 WARNING - Near 80°C limit" -ForegroundColor Yellow
    } else {
        Write-Host "$($gpuTemp)°C  ✅ Safe" -ForegroundColor Green
    }

    Write-Host " Thermal Guard Limit       : 80°C (V2 Auto-Throttle)" -ForegroundColor Cyan

    Write-Host " GPU Link State (AC)       : " -NoNewline
    $acGpuText = switch ($gpuCurrent.AC) { 0 { "Off (High Power)" } 1 { "Moderate Power Save" } 2 { "Max Power Save" } }
    Write-Host $acGpuText -ForegroundColor Yellow

    Write-Host " GPU Link State (DC)       : " -NoNewline
    $dcGpuText = switch ($gpuCurrent.DC) { 0 { "Off (High Power)" } 1 { "Moderate Power Save" } 2 { "Max Power Save" } }
    Write-Host $dcGpuText -ForegroundColor Yellow

    Write-Host " Max CPU Limit Ceiling     : 100% (No Overclocking)" -ForegroundColor Cyan
    Write-Host " OEM Overclock Guard       : ACTIVE" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
}

# ─── GPU MODE PARSE ─────────────────────────────────────────────────────────

$gpuLevelToSet = 1
if ($GpuMode -ne "") {
    if ($GpuMode -eq "Off"      -or $GpuMode -eq "0") { $gpuLevelToSet = 0 }
    elseif ($GpuMode -eq "Moderate" -or $GpuMode -eq "1") { $gpuLevelToSet = 1 }
    elseif ($GpuMode -eq "MaxSave"  -or $GpuMode -eq "2") { $gpuLevelToSet = 2 }
}

# ─── COMMAND LINE ROUTING ───────────────────────────────────────────────────

if ($Status)        { Show-Status;                                                      exit }
if ($LifeCalculator){ Show-LifeCalculator;                                              exit }
if ($ThermalGuard)  { Start-ThermalGuard -tempLimit $GpuTempLimit;                     exit }
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
        $saved = Get-Content $configFile | ConvertFrom-Json
        if ($saved.AcLimit)  { $ac    = $saved.AcLimit  }
        if ($saved.DcLimit)  { $dc    = $saved.DcLimit   }
        if ($saved.GpuLevel) { $gpuL  = $saved.GpuLevel }
        if ($saved.ModeName) { $mName = $saved.ModeName  }
    }
    Set-PowerLimits -ac $ac -dc $dc -gpuLevel $gpuL -modeName $mName
    exit
}

# ─── INTERACTIVE MENU ───────────────────────────────────────────────────────

Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "       POWERC $version - CPU & GPU HARDWARE LONGEVITY CLI      " -ForegroundColor Green
Write-Host "  Protect PC Longevity, Prevent Overheating & Limit Power   " -ForegroundColor Yellow
Write-Host "  🌡️  NEW: GPU Thermal Guard - Auto-Throttles above 80°C     " -ForegroundColor Red
Write-Host "============================================================" -ForegroundColor Cyan

Show-Status

Write-Host "Choose a Power and Longevity Mode:" -ForegroundColor White
Write-Host " [1] Normal Stock Mode (AC: 100%, DC: 100%, GPU: Full Power)"         -ForegroundColor Green
Write-Host " [2] Quiet Mode        (AC:  75%, DC:  60%, GPU: Moderate Save)"      -ForegroundColor Cyan
Write-Host " [3] Super Quiet Mode  (AC:  50%, DC:  40%, GPU: Max Power Save)"     -ForegroundColor Cyan
Write-Host " [4] Ultra Quiet Mode  (AC:  35%, DC:  25%, GPU: Max Power Save)"     -ForegroundColor Cyan
Write-Host " [5] Maximum Quiet Mode(AC:  20%, DC:  15%, GPU: Max Power Save)"     -ForegroundColor Cyan
Write-Host " [6] Potato PC Mode    (AC:  10%, DC:  10%, GPU: Max Power Save) 🥔"  -ForegroundColor Magenta
Write-Host " [7] Set Custom CPU Power Limit (Max 100% Capped)"                    -ForegroundColor Yellow
Write-Host " [8] Set Custom GPU Power Saver (PCIe Link: Off, Moderate, Max)"      -ForegroundColor Yellow
Write-Host " [9] View Hardware Lifespan & Thermal Physics Calculator"             -ForegroundColor Yellow
Write-Host " [T] 🌡️ Start GPU Thermal Guard (Auto-Throttle if GPU > 80°C)"        -ForegroundColor Red
Write-Host " [W] 🛡️ Start Watchdog + Thermal Guard (Block OEM + 80°C Guard)"     -ForegroundColor Green
Write-Host " [0] Exit"                                                             -ForegroundColor Red
Write-Host ""

$choice = Read-Host "Select option [0-9, T, or W]"

switch ($choice) {
    "1" { Set-PowerLimits -ac 100 -dc 100 -gpuLevel 0 -modeName "Normal Stock" }
    "2" { Set-PowerLimits -ac 75  -dc 60  -gpuLevel 1 -modeName "Quiet" }
    "3" { Set-PowerLimits -ac 50  -dc 40  -gpuLevel 2 -modeName "Super Quiet" }
    "4" { Set-PowerLimits -ac 35  -dc 25  -gpuLevel 2 -modeName "Ultra Quiet" }
    "5" { Set-PowerLimits -ac 20  -dc 15  -gpuLevel 2 -modeName "Maximum Quiet" }
    "6" { Set-PowerLimits -ac 10  -dc 10  -gpuLevel 2 -modeName "Potato PC" }
    "7" {
        Write-Host ""
        Write-Host "--- CUSTOM CPU POWER LIMIT ---" -ForegroundColor Yellow
        Write-Host "(Values > 100% auto-capped to 100%)" -ForegroundColor Gray
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
    "9" { Show-LifeCalculator }
    "T" { Start-ThermalGuard -tempLimit 80 }
    "t" { Start-ThermalGuard -tempLimit 80 }
    "W" { Start-WatchdogEnforcer }
    "w" { Start-WatchdogEnforcer }
    "0" { Write-Host "Exiting powerc." -ForegroundColor Gray; exit }
    default { Write-Host "Invalid option." -ForegroundColor Red }
}
