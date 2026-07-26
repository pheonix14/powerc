# powerc - CPU & GPU Power Control & Hardware Longevity CLI for Windows

`powerc` is a lightweight power management utility for Windows designed to protect your PC hardware (CPU & GPU), prevent overheating, eliminate fan noise, stop overvolting/overclocking, and extend component lifespan up to **20+ years** by controlling CPU & GPU maximum power limits and PCIe Link State Power Management.

---

## ⚡ Key Features & Safety Rules

1. **Strict 100% Upper Cap Ceiling**: CPU inputs above 100% are strictly forbidden and automatically clamped to 100%. No overvolting or aggressive overclocking allowed!
2. **GPU Customizer & PCIe Link Saver**: Controls PCIe Link State Power Management (`ASPM`) to cut discrete/integrated GPU power draw and heat, with live NVIDIA GPU telemetry support (`nvidia-smi`).
3. **Eliminate Turbo Boost & Voltage Spikes**: Capping CPU & GPU limits turns off thermal expansion stress cycles that degrade solder joints and silicon over time.
4. **Tiered Eco Longevity Modes**:
   - **Normal Stock Mode (100% CPU / GPU Full Power)**: Standard baseline stock speed (no overclocking).
   - **Quiet Mode (75% AC / 60% DC / GPU Moderate Save)**: Cool operation, low fan noise.
   - **Super Quiet Mode (50% AC / 40% DC / GPU Max Save)**: Silent, low heat footprint.
   - **Ultra Quiet Mode (35% AC / 25% DC / GPU Max Save)**: Very low thermal stress & energy saving.
   - **Maximum Quiet Mode (20% AC / 15% DC / GPU Max Save)**: Max noise & thermal cut.
   - **Potato PC Mode 🥔 (10% AC / 10% DC / GPU Max Save)**: Extreme longevity mode (estimated 25+ years hardware life).
5. **Hardware Lifespan Calculator 🧮**: Includes a built-in estimator for CPU and GPU thermal degradation reduction based on semiconductor physics (Arrhenius Law).

---

## 🚀 Quick Usage

### 1. Interactive Menu
Run `powerc` or `.\powerc.ps1` in PowerShell/Command Prompt:
```powershell
.\powerc.ps1
```

### 2. Command Line Mode Switches
```powershell
.\powerc.ps1 -Quiet         # Applies Quiet Mode
.\powerc.ps1 -SuperQuiet    # Applies Super Quiet Mode
.\powerc.ps1 -UltraQuiet    # Applies Ultra Quiet Mode
.\powerc.ps1 -MaxQuiet      # Applies Max Quiet Mode
.\powerc.ps1 -Potato        # Applies Potato PC Mode 🥔
.\powerc.ps1 -Unlock        # Restores Normal Stock Mode (100% AC & DC, GPU Full Power)
.\powerc.ps1 -LifeCalculator# Displays CPU & GPU Hardware Lifespan Estimator
```

### 3. GPU Customizer Options
```powershell
.\powerc.ps1 -GpuMode MaxSave   # Sets GPU Link Saver to Maximum Power Savings (Max thermal cut)
.\powerc.ps1 -GpuMode Moderate  # Sets GPU Link Saver to Moderate Power Savings
.\powerc.ps1 -GpuMode Off       # Sets GPU Link Saver to Full Performance (Off)
```

### 4. Custom CPU & GPU Limits
```powershell
.\powerc.ps1 -AcLimit 70 -DcLimit 50 -GpuMode MaxSave
```

---

## 🧮 Hardware Longevity & Thermal Physics
Overheating is the #1 killer of laptop/desktop CPUs and GPUs. Silicon electromigration and thermal expansion stress double for roughly every 10°C increase in operating temperature. 

By running in **Quiet** or **Ultra Quiet** modes with GPU link power saving enabled, you significantly lower operating temperatures, allowing your PC to run reliably for **15 to 20+ years** without hardware degradation.
