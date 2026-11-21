# Fritchii Zero-Stutter (v6.2.3)
### *The Legend of Zelda: Ocarina of Time (Nintendo Switch 2 Remake) on PC*

[![Release](https://img.shields.io/github/v/release/giangero1/Fritchii-ZeroStutter?color=brightgreen&label=Latest%20Release)](https://github.com/giangero1/Fritchii-ZeroStutter/releases/latest)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Status](https://img.shields.io/badge/Performance-Zero--Stutter%204K-purple.svg)](#performance-showcase)

**Fritchii Zero-Stutter** is an unofficial, high-performance fork of Fritchii v6.2 engineered specifically to eliminate mid-game shader freezes, VRAM overflows, and presentation hitches in *The Legend of Zelda: Ocarina of Time Remake* on PC. 

Tuned and benchmarked on **AMD Ryzen 7 5800X3D + NVIDIA GeForce RTX 3070 8 GB** running **1440p → 4K DLSS Quality + Frame Generation**.

---

## ⚡ Core Capabilities

- 🛡️ **Smart 8 GB VRAM Engine (v6.2.3):**
  - **Zero Menu Exit Stutter:** Primary 1440p world render targets are preserved during L1 inventory access under safe headroom (>1,536 MiB reserve), stopping textures and Link models from disappearing outside Hyrule Castle.
  - **Dynamic Defragmentation (`FRITCHII_VRAM_DEFRAG`):** Consolidates sparse texture blocks on the GPU, freeing hundreds of megabytes of wasted holes so heavy scenes like daytime Castle Town Market stay locked without driver crashes.
  - **Surge Load Cleaning (`FRITCHII_AREA_CLEAN`):** Rapidly clears previous-area pools during transitions, dropping recovery times on 8 GB cards from 20 s to 1–2 s.

- ⚔️ **Zero Combat & Foliage Freezes:**
  - **SPIR-V `DontInline` Directive:** Drops NVIDIA compiler freezes from **7.6 seconds to <1 ms**, eliminating hitches when slashing grass, breaking pots, and striking enemies.
  - **Non-blocking Foliage Refresh (`EDEN_NX2_STALE_READS`):** Serves recurring wind/foliage readbacks asynchronously without stalling the CPU render thread.

- 🖼️ **Next-Gen Frame Generation Suite:**
  - Integrated support for **DLSS-G** (RTX 20/30/40 via OpenDLSSG bypass), **AMD FSR 3.1 Optical Flow**, and **Lossless Scaling FG**.
  - Accessible directly via right-click on the status bar **`FG`** indicator.

- 🧩 **Built-in Shader Setup Guide:**
  - In-app assistance (`Help → Shader setup`) guiding players on combining the ~19k base shader cache with Frizti's official ~120,000 pipeline precompile recipe for instant boots.

---

## 📊 Performance Showcase

*Tested in the daytime Castle Town Market at 1440p → 4K DLSS Quality on RTX 3070 8 GB + Ryzen 7 5800X3D:*

| Metric | Stock / Legacy | Zero-Stutter v6.2.3 |
| :--- | :---: | :---: |
| **Castle Town Market Stability** | 5–8 FPS (VRAM spill / Crash) | **46–73 FPS (Solid & Stable)** |
| **Wasted Block Fragmentation** | ~500 MiB wasted | **~50–130 MiB (Dynamic Defrag)** |
| **Free VRAM Headroom** | 0 MiB (OOM overflow) | **~1.5–2.3 GiB Safe Reserve** |
| **Castle Inventory Exit** | Textures vanish, 185 ms hitch | **Instant exit, 0 recreations** |
| **Grass / Pot Slash Stutter** | 7.6 s compile freeze | **<1 ms (Imperceptible)** |

![Castle Town Market, RTX 3070 8 GB, 1440p to 4K DLSS](https://raw.githubusercontent.com/giangero1/Fritchii-ZeroStutter/release/v6.2.3-zerostutter/docs/fritchii-6.2.2-rtx3070-4k-market-day.webp)

---

## 🚀 Quick Start Guide

1. **Download:** Grab [`fritchii-v6.2.3-zerostutter-win64.zip`](https://github.com/giangero1/Fritchii-ZeroStutter/releases/latest) from Releases.
2. **Extract:** Unzip into a folder (e.g. `D:\Games\Fritchii-6.2.3-ZeroStutter`). *Coming from v6.2.x? Simply copy your `user` folder over or replace `fritchii.exe`.*
3. **Shader Cache (Recommended):** Place the `fork-v54` cache files into `user\cache\shader\0400486024dec000\`.
   *(Optional: For the full ~120k precompiled pipelines, copy Frizti's official `recipes` folder next to `fritchii.exe` per recipe license terms).*
4. **Play:** Launch **`Play-Fritchii-6.2.3-ZeroStutter.cmd`**.

---

## ⚙️ CPU Thread Optimization

If your CPU has fewer than 8 cores, open `Play-Fritchii-6.2.3-ZeroStutter.cmd` (or `nx2_switches.txt`) and configure `EDEN_NX2_WARM_THREADS`:

| CPU Cores / Threads | Example Processors | Recommended `WARM_THREADS` |
| :--- | :--- | :---: |
| **8 Cores / 16 Threads** | AMD Ryzen 7 5800X3D / Intel Core i7-13700 | **`6`** *(Default)* |
| **6 Cores / 12 Threads** | AMD Ryzen 5 5600X / Intel Core i5-12400 | **`4`** |
| **4 Cores / 8 Threads** | Intel Core i3-12100 / AMD Ryzen 3 3300X | **`2`** |

---

<details>
<summary><b>📜 Changelog & Version Archive</b></summary>

### v6.2.3
- Fixed outdoor Castle inventory exit texture disappearance by protecting primary render targets under safe driver headroom (>1,536 MiB reserve).
- Built-in Shader Setup Guide dialog (`Help → Shader setup`).
- Decoupled `CoveredRetire` telemetry for cleaner cache diagnostics.
- Title bar version updated to `Zero-Stutter fork v6.2.3`.

### v6.2.2
- `FRITCHII_AREA_CLEAN`: Aggressive post-load cleanup keeping 8 GB cards under budget on Market re-entry.
- Dynamic VRAM budget tracking counting external background apps.
- ASTC scratch cap applied strictly near budget limits on 10 GB+ cards.
- OBS / Medal Vulkan game-capture hooks disabled inside the emulator to prevent driver hangs.

### v6.2.1
- Real-time VRAM defragmentation (`FRITCHII_VRAM_DEFRAG`) eliminating Castle Town Market memory crash.
- Added `FRITCHII_GPU_ZONES` telemetry.

### v6.0 – v6.2
- Upstream Fritchii v6.2 rebase.
- `EDEN_NX2_STALE_READS`: Asynchronous foliage readbacks eliminating the once-a-second hitch.
- White light / overexposure query carryover fix.
- Streamline DLSS-G Frame Generation enabler for RTX 30 series GPUs.

</details>

---

## 📜 Credits & License Attribution
* Built as an **unofficial modified fork** based on upstream Fritchii v6.2 (GNU GPLv3) and Lichii/Eden/yuzu contributors. Not affiliated with Frizti.
* White light fix ported from **zortos293/Lichii** (`dfde522b40`).
* **Shader precompile system by Frizti (Fritchii)** *(per GPLv3 Section 7 attribution notice; proprietary `*.nx2recipe` files are not redistributed in this fork's packages)*.
