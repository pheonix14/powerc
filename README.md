# powerc v2.5 - All-In-One CPU & GPU Power Control, Dual Thermal Guard & Live Monitor CLI

`powerc` is a lightweight power management utility for Windows designed to protect your PC hardware (CPU & GPU), prevent overheating, eliminate fan noise, stop overvolting/overclocking, and extend component lifespan up to **20+ years**.

**v2.5 adds Dual CPU & GPU Thermal Guard — keeping CPU and GPU temperatures strictly below 80°C at all times, with a continuous interactive CLI prompt and real-time monitoring dashboard.**

---

## ⚡ Key Features & Safety Rules

1. **Strict 100% Upper Cap Ceiling**: CPU inputs above 100% are strictly forbidden and automatically clamped to 100%. No overvolting or overclocking allowed!
2. **Dual CPU & GPU 80°C Thermal Guard**:
   - Real-time telemetry monitoring for both CPU and GPU temperatures.
   - Enforces an **80°C hard thermal ceiling**. If CPU OR GPU exceeds 80°C, automatically steps down through a throttle ladder:
     - Step 1 → Quiet Mode (75% AC / 60% DC)
     - Step 2 → Super Quiet (50% AC / 40% DC)
     - Step 3 → Ultra Quiet (35% AC / 25% DC)
     - Step 4 → Max Quiet (20% AC / 15% DC)
     - Step 5 → Potato PC 🥔 (10% AC / 10% DC) — Emergency thermal cut
   - Gradually **restores** to base mode after 60 seconds of safe temperatures.
3. **Continuous Interactive Prompt Loop**:
   - `powerc.cmd` / `powerc.ps1` stays open in a continuous menu loop — never closes automatically until you explicitly select `0` (Exit).
   - Unified `[L] Lock` and `[U] Unlock` shortcuts directly inside the interactive menu prompt.
4. **Real-Time Active Monitoring Dashboard**:
   - Live telemetry dashboard displaying real-time CPU & GPU temperatures (°C), power caps, GPU watt draw, PCIe link state, thermal guard status, and error alerts.
5. **Tiered Eco Longevity Modes**:
   - **Normal Stock Mode (100% CPU / GPU Full Power)**: Standard baseline stock speed (no overclocking).
   - **Quiet Mode (75% AC / 60% DC / GPU Moderate Save)**: Cool operation, low fan noise.
   - **Super Quiet Mode (50% AC / 40% DC / GPU Max Save)**: Silent, low heat footprint.
   - **Ultra Quiet Mode (35% AC / 25% DC / GPU Max Save)**: Very low thermal stress & energy saving.
   - **Maximum Quiet Mode (20% AC / 15% DC / GPU Max Save)**: Max noise & thermal cut.
   - **Potato PC Mode 🥔 (10% AC / 10% DC / GPU Max Save)**: Extreme longevity mode (estimated 25+ years hardware life).

---

## 🚀 Quick Usage

### 1. Interactive CLI Prompt
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
.\powerc.ps1 -Lock             # Quickly locks power limits to Eco limits
.\powerc.ps1 -Unlock           # Restores Normal Stock Mode (100% AC & DC, GPU Full Power)
.\powerc.ps1 -Monitor          # Launches Real-Time Active Monitoring & Error Analysis Dashboard
.\powerc.ps1 -LifeCalculator   # Displays CPU & GPU Hardware Lifespan Estimator
```

### 3. 🌡️ Dual CPU & GPU Thermal Guard
```powershell
.\powerc.ps1 -ThermalGuard    # Starts Dual CPU & GPU Thermal Guard (80°C hard ceiling)
.\powerc.ps1 -Watchdog        # Watchdog + Thermal Guard combined (OEM blocker + 80°C ceiling)
```

---

## 📋 Changelog

### v2.5.0
- 🌡️ **Dual CPU & GPU Thermal Guard**: Hard 80°C thermal ceiling enforced for CPU & GPU simultaneously
- 🔄 **Continuous Interactive CLI Loop**: Prompt stays open and loops until `0` Exit is chosen
- 📊 **Real-Time Active Monitoring Dashboard**: Live telemetry view (`-Monitor` or menu option `[M]`)
- 🔒 **Unified Lock & Unlock**: Quick Lock `[L]` and Unlock `[U]` directly inside interactive prompt
- 🛠️ **Cross-Shell Encoding Fix**: Dynamic `[char]176` degree symbols for fail-safe display across all Windows consoles

### v2.0.0
- 🌡️ **GPU Thermal Guard**: Real-time 80°C hard ceiling with automatic throttle ladder
- 🔗 **Extended Telemetry**: GPU power draw and NVIDIA/AMD sensor integration
