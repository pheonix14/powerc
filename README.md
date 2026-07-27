# powerc v2 - CPU & GPU Power Control & Hardware Longevity CLI for Windows

`powerc` is a lightweight power management utility for Windows designed to protect your PC hardware (CPU & GPU), prevent overheating, eliminate fan noise, stop overvolting/overclocking, and extend component lifespan up to **20+ years**.

**v2 adds a live GPU Thermal Guard — automatically throttles power if GPU temperature exceeds 80°C.**

---

## ⚡ Key Features & Safety Rules

1. **Strict 100% Upper Cap Ceiling**: CPU inputs above 100% are strictly forbidden and automatically clamped to 100%. No overvolting or overclocking allowed!
2. **GPU Customizer & PCIe Link Saver**: Controls PCIe Link State Power Management (`ASPM`) to cut discrete/integrated GPU power draw and heat, with live NVIDIA GPU telemetry support (`nvidia-smi`).
3. **🌡️ NEW V2 — GPU Thermal Guard (80°C Hard Ceiling)**:
   - Monitors GPU temperature every **10 seconds** via `nvidia-smi`.
   - If GPU temp **≥ 80°C**, automatically steps down through a throttle ladder:
     - Step 1 → Quiet Mode (75% AC / 60% DC)
     - Step 2 → Super Quiet (50% AC / 40% DC)
     - Step 3 → Ultra Quiet (35% AC / 25% DC)
     - Step 4 → Max Quiet (20% AC / 15% DC)
     - Step 5 → Potato PC 🥔 (10% AC / 10% DC) — Emergency thermal cut
   - Gradually **restores** to base mode after 60 seconds of safe temperatures.
4. **Eliminate Turbo Boost & Voltage Spikes**: Capping CPU & GPU limits turns off thermal expansion stress cycles that degrade solder joints and silicon over time.
5. **Tiered Eco Longevity Modes**:
   - **Normal Stock Mode (100% CPU / GPU Full Power)**: Standard baseline stock speed (no overclocking).
   - **Quiet Mode (75% AC / 60% DC / GPU Moderate Save)**: Cool operation, low fan noise.
   - **Super Quiet Mode (50% AC / 40% DC / GPU Max Save)**: Silent, low heat footprint.
   - **Ultra Quiet Mode (35% AC / 25% DC / GPU Max Save)**: Very low thermal stress & energy saving.
   - **Maximum Quiet Mode (20% AC / 15% DC / GPU Max Save)**: Max noise & thermal cut.
   - **Potato PC Mode 🥔 (10% AC / 10% DC / GPU Max Save)**: Extreme longevity mode (estimated 25+ years hardware life).
6. **Hardware Lifespan Calculator 🧮**: Built-in estimator for CPU and GPU thermal degradation reduction based on semiconductor physics (Arrhenius Law). Now shows live GPU temperature.

---

## 🚀 Quick Usage

### 1. Interactive Menu
Run `powerc` or `.\powerc.ps1` in PowerShell/Command Prompt:
```powershell
.\powerc.ps1
```

### 2. Command Line Mode Switches
```powershell
.\powerc.ps1 -Quiet            # Applies Quiet Mode
.\powerc.ps1 -SuperQuiet       # Applies Super Quiet Mode
.\powerc.ps1 -UltraQuiet       # Applies Ultra Quiet Mode
.\powerc.ps1 -MaxQuiet         # Applies Max Quiet Mode
.\powerc.ps1 -Potato           # Applies Potato PC Mode 🥔
.\powerc.ps1 -Unlock           # Restores Normal Stock Mode (100% AC & DC, GPU Full Power)
.\powerc.ps1 -LifeCalculator   # Displays CPU & GPU Hardware Lifespan Estimator
```

### 3. 🌡️ NEW V2 — GPU Thermal Guard
```powershell
.\powerc.ps1 -ThermalGuard                    # Starts GPU Thermal Guard (default 80°C limit)
.\powerc.ps1 -ThermalGuard -GpuTempLimit 75   # Custom GPU temp ceiling (e.g. 75°C)
.\powerc.ps1 -Watchdog                         # Watchdog + Thermal Guard combined (OEM block + 80°C guard)
```

### 4. GPU Customizer Options
```powershell
.\powerc.ps1 -GpuMode MaxSave    # Sets GPU Link Saver to Maximum Power Savings
.\powerc.ps1 -GpuMode Moderate   # Sets GPU Link Saver to Moderate Power Savings
.\powerc.ps1 -GpuMode Off        # Sets GPU Link Saver to Full Performance (Off)
```

### 5. Custom CPU & GPU Limits
```powershell
.\powerc.ps1 -AcLimit 70 -DcLimit 50 -GpuMode MaxSave
```

---

## 🌡️ GPU Thermal Guard — How It Works

The Thermal Guard runs a real-time feedback loop every 10 seconds:

```
GPU Temp ≥ 80°C?
  YES → Step down throttle: Quiet → Super Quiet → Ultra Quiet → Max Quiet → Potato PC
  NO  → Count 6 cool cycles (~60s) then step back up to base mode
```

- Uses `nvidia-smi` for NVIDIA GPUs (auto-detected).
- Falls back to WMI thermal zones for AMD/Integrated GPUs.
- If `nvidia-smi` is unavailable, displays `N/A` and skips thermal throttle.
- Throttle restoration is **gradual** — never snaps back instantly to avoid re-heating.

---

## 🧮 Hardware Longevity & Thermal Physics
Overheating is the #1 killer of laptop/desktop CPUs and GPUs. Silicon electromigration and thermal expansion stress double for roughly every 10°C increase in operating temperature.

By running in **Quiet** or **Ultra Quiet** modes with GPU link power saving enabled, you significantly lower operating temperatures, allowing your PC to run reliably for **15 to 20+ years** without hardware degradation.

The V2 Thermal Guard ensures the GPU **never exceeds 80°C**, the threshold at which silicon aging begins to accelerate significantly.

---

## 📋 Changelog

### v2.0.0
- 🌡️ **GPU Thermal Guard**: Real-time 80°C hard ceiling with automatic throttle ladder
- 🔄 **Gradual Restoration**: Stepped recovery after GPU cools down (prevents re-heat spikes)
- 📊 **Live GPU Temp in Status**: `Show-Status` and `LifeCalculator` now display current GPU temperature
- 🔗 **Extended nvidia-smi search paths**: More robust NVIDIA detection
- 🛡️ **Watchdog V2**: Combined OEM blocker + Thermal Guard in one session
- ✨ **Custom temp limit**: `-ThermalGuard -GpuTempLimit 75` for stricter protection

### v1.0.0
- Initial release: CPU/GPU power capping, PCIe ASPM, eco-modes, watchdog, lifespan calculator
