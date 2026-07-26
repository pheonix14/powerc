# powerc - Power Control & Hardware Longevity CLI for Windows

`powerc` is a lightweight power management utility for Windows designed to protect your PC hardware, prevent overheating, eliminate fan noise, stop overvolting/overclocking, and extend component lifespan up to **20+ years** by controlling CPU maximum power limits.

---

## ⚡ Key Features & Safety Rules

1. **Strict 100% Upper Cap Ceiling**: Inputs above 100% are strictly forbidden and automatically clamped to 100%. No overvolting or aggressive overclocking allowed!
2. **Eliminate Turbo Boost Spikes**: Setting limits below 100% (e.g., 99%) turns off CPU turbo boost spikes, stopping thermal expansion stress cycles that degrade solder joints and silicon over time.
3. **Tiered Eco Longevity Modes**:
   - **Normal Stock Mode (100% AC / 100% DC)**: Standard baseline stock speed (no overclocking).
   - **Quiet Mode (75% AC / 60% DC)**: Cool operation, low fan noise.
   - **Super Quiet Mode (50% AC / 40% DC)**: Silent, low heat footprint.
   - **Ultra Quiet Mode (35% AC / 25% DC)**: Very low thermal stress & energy saving.
   - **Maximum Quiet Mode (20% AC / 15% DC)**: Max noise & thermal cut.
   - **Potato PC Mode 🥔 (10% AC / 10% DC)**: Extreme longevity mode (estimated 25+ years hardware life).
4. **Hardware Lifespan Calculator 🧮**: Includes a built-in estimator based on thermal wear reduction physics (Arrhenius Law).

---

## 🚀 Quick Usage

### 1. Interactive Menu
Run `powerc` or `.\powerc.ps1` in PowerShell/Command Prompt:
```powershell
.\powerc.ps1
```

### 2. Command Line Mode Switches
```powershell
.\powerc.ps1 -Quiet         # Applies Quiet Mode (75% AC / 60% DC)
.\powerc.ps1 -SuperQuiet    # Applies Super Quiet Mode (50% AC / 40% DC)
.\powerc.ps1 -UltraQuiet    # Applies Ultra Quiet Mode (35% AC / 25% DC)
.\powerc.ps1 -MaxQuiet      # Applies Max Quiet Mode (20% AC / 15% DC)
.\powerc.ps1 -Potato        # Applies Potato PC Mode 🥔 (10% AC / 10% DC)
.\powerc.ps1 -Unlock        # Restores Normal Stock Mode (100% AC & DC)
.\powerc.ps1 -LifeCalculator# Displays Hardware Lifespan & Wear Estimator
```

### 3. Quick Lock & Unlock Commands
- `.\lock.ps1`: Quickly locks power to Quiet Eco settings.
- `.\unlock.ps1`: Restores safe Normal Stock 100% settings.

### 4. Custom Power Limits (Max 100% Cap)
```powershell
.\powerc.ps1 -AcLimit 80 -DcLimit 50
```
*(If you attempt to pass a value like `-AcLimit 150`, `powerc` will automatically clamp it to `100%` to keep your hardware safe!)*

---

## 🧮 Hardware Longevity & Thermal Physics
Overheating is the #1 killer of PC CPUs and GPUs. Silicon electromigration and thermal expansion stress double for roughly every 10°C increase in temperature. 

By running in **Quiet** or **Ultra Quiet** modes, you significantly lower operating temperatures, allowing your PC to run reliably for **15 to 20+ years** without hardware degradation.
