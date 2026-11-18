# Fritchii Zero-Stutter Custom Build (v6.0)
### *The Legend of Zelda: Ocarina of Time (Nintendo Switch 2 Remake) on PC*

[![Release](https://img.shields.io/github/v/release/giangero1/Fritchii-ZeroStutter?color=brightgreen&label=Release)](https://github.com/giangero1/Fritchii-ZeroStutter/releases)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

**Fritchii Zero-Stutter** is an unofficial, modified high-performance fork of Fritchii engineered from the ground up to solve the core architectural stuttering, compilation freezes, memory leaks, and visual regressions in *The Legend of Zelda: Ocarina of Time Remake* on PC.

Our latest **v6.0 Zero-Stutter update** upgrades the engine onto **upstream Fritchii v6.0** (`c36d853a96` — 1,191 commits over v5.8.4, adding the 3rd GPU draw-recording thread, shared 6-core JIT code cache, pot-room fix, and 8 GB small-card VRAM mode) while restoring **full Multi-Engine Frame Generation** (**NVIDIA DLSS-G via OpenDLSSG for RTX 30-series Ampere**, **native Vulkan Compute FSR 3.1 Optical Flow**, and **LSFG**) and every Zero-Stutter C++ pillar.

---

## 🏛️ The Core Zero-Stutter Pillars

This repository focuses on five inviolable engine fixes that eliminate hitches and crashes during gameplay:

### 1. Compute Shader `DontInline` Directive (Combat Freeze Fix)
* **The Problem:** Upstream SPIR-V compilation inlines massive compute global memory helpers by default, causing NVIDIA driver compiler spikes lasting **up to 7.6 seconds** whenever Link hits grass, smashes pots, or strikes enemies.
* **The Solution:** Defaults `inline_mode = 2` (compute-only `spv::FunctionControlMask::DontInline`, keeping graphics shaders inlined for full FPS) in `spirv_emit_context.cpp`, while supporting runtime overrides via `EDEN_NX2_SPIRV_INLINE_GLOBALS=0/1/2/3` (including v6's shared-search `=3` mode) or `EDEN_NX2_COMPUTE_NOINLINE`. Compiler freezes drop from **7.6s down to <1 ms**, delivering instant, zero-stutter combat.

### 2. `GuessMissing` Disk Pipeline Cache Fallback (Boot & Traversal)
* **The Problem:** Pipelines with unrecorded constant buffer descriptors are ordinarily discarded upstream inside `CreateCachedGraphicsPipeline`, triggering heavy runtime hitching during world traversal.
* **The Solution:** Injects `env.SetGuessMissing(&guess)` in `vk_pipeline_cache.cpp` so **100% of the 28,612 pre-warmed `fork-v54` pipelines** deserialize cleanly from disk cache during boot.

### 3. Upstream Fritchii v6.0 Architecture & Memory Protection
* **3rd GPU Draw-Recording Thread (`FRITCHII_ONEF_*`):** Removes the Castle Town Market CPU bottleneck for locked 60+ base FPS.
* **Shared 6-Core JIT Code Cache & 8 GB Small-Card Mode (`FRITCHII_SMALL_CARD=2`):** Saves ~1 GB RAM, cuts area-load stutters by ~25%, fixes Pot Room texture pool crashes, and keeps RTX 3070 8 GB GPUs strictly inside VRAM budget.

### 4. Occlusion Query Sample Preservation (`03534dc645`)
* **The Problem:** Sample counts exceeding the query bank bound were dropped via `ResetCounter()` across query submissions, causing sudden white flashes and overexposure when rotating the camera.
* **The Solution:** Carries sample counts across bank limits in `vk_query_cache.cpp`, eliminating lighting washouts.

### 5. Multi-Core Hardware Boost Suite (`Play-Fritchii-6.0-ZeroStutter.cmd`)
* Launches `fritchii.exe` at high priority with `EDEN_NX2_SPIRV_INLINE_GLOBALS=2`, 6 pipeline warming threads (`EDEN_NX2_WARM_THREADS=6`), `EDEN_NX2_PRELOAD_ALL_PIPELINES=1`, built-in Graphics Pipeline Library (GPL) neutralization, and all v6 built-in switches preserved.

---

## 🔥 New in Update v6.0: Full 4K 127 FPS Frame Generation + v6 Engine

The v6.0 Zero-Stutter release restores the entire Frame Generation subsystem removed in upstream v6 (`9f95262d0f`), unlocks FrameGen controls inside v6's Graphics UI, and integrates Streamline DLSS-G directly into the v6 presentation swapchain:

![Fritchii v6.0 Zero-Stutter 4K 127 FPS — 1440p to 4K DLSS Quality J + DLSS-G 2X on RTX 3070](docs/fritchii-6.0-4k-127fps.png)

* **Verified Performance (Forest Temple — Full `1440p → 4K` DLSS Quality J + DLSS-G 2X):** **127 FPS** (**63 Base Game FPS + 64 Generated Frames**), **93% GPU**, **54% CPU**, **15.69 ms frame time**, **0 ms latency overhead** on **RTX 3070 8GB + Ryzen 7 5800X3D**.

### 1. RTX 30-Series (Ampere) DLSS Frame Generation
* Pre-configured with the **OpenDLSSG + FakeNVAPI** runtime (`version.dll`, `opendlssg.ini`, `fakenvapi.dll`, `nvapi64.dll`, and `nvngx_dlssg.dll`) plus our Streamline error-32 bypass (`974f72f592`).
* Unlocks DLSS Frame Generation (`DLSS-G 2X`) on **RTX 3070, 3080, and 3090** GPUs with zero latency penalty (`LAT 0 ms`).

### 2. Native Vulkan Compute FSR 3.1 Optical Flow & LSFG Fallback
* Fully native optical flow interpolation running on SPIR-V Vulkan compute shaders (`fsr3_optical_flow_comp_spv.h` / `fsr3_frame_interpolation_comp_spv.h`) plus Lossless Scaling (`LSFG`) fallback.
* Works across all modern GPUs directly from the **`FG`** status bar button or Graphics settings.

### 3. Upstream `(IDLE)` Frame Gen Ghost Counter Bug Fixed
* Fixed the upstream bug in `frame_gen.cpp` where `generated_frames` stayed stuck at `(IDLE)` during presentation.
* Pre-allocates swapchain frame queues (`generations = std::max(Settings::FrameGenMaxGenerations(), 1)`) and enables storage views (`storage_required = true`) so toggling Frame Gen on the fly never drops frames.

### 4. Dynamic In-Engine DLSS Render Scaling & v6 Upscaler Controls
* Built-in upstream v6 DLSS quality scaling (`#1589`), DLSS camera jitter, Texture Sharpness, `1080p`–`8K` upscaler outputs, and live status bar readouts (`1440p → 4K · DLSS`).

---

## 💾 Pre-Warmed 28,612 Shader Cache (`fork-v54`)

To eliminate gameplay shader compilation hitches right from boot (Fritchii v6 still reads `vulkan-frizti.fork-v54.bin` and re-translates the guest pipeline records through our `GuessMissing` fallback):
- 🔗 **Primary Mirror (Google Drive):** [Download Verified 28,612 Shaders](https://drive.google.com/file/d/1pa3T-D7lTcuo9B1RHP1HoejbtdUDqS6O/view)
- 🔗 **Alternative Mirror (Gofile):** [Download via Gofile Mirror](https://gofile.io/d/GBTsYoTL)

Extract `vulkan-frizti.fork-v54.bin` and `vulkan_used-frizti.fork-v54.bin` directly into:
```text
fritchii-v6.0-zerostutter-win64/
├── Play-Fritchii-6.0-ZeroStutter.cmd
├── nx2_switches.txt
├── fritchii.exe
├── lichii.exe
└── user/
    └── cache/
        └── shader/
            └── 0400486024dec000/    <--- EXTRACT SHADER FILES HERE
                ├── vulkan-frizti.fork-v54.bin
                └── vulkan_used-frizti.fork-v54.bin
```
*(Tip: For v6.0, you only need the `fork-v54` files — skip any older `fork-v52` / `fork-v53` / old `precompiled` files so v6 doesn't prompt to clear stale caches.)*

---

## ⚙️ CPU Core & Thread Tuning (For 6-Core & 4-Core Users)

If your CPU has fewer than 8 cores, open `Play-Fritchii-6.0-ZeroStutter.cmd` (or **Tools → Switches** / `nx2_switches.txt`) and adjust `EDEN_NX2_WARM_THREADS`:

| CPU Cores / Threads | Example Processors | Recommended `WARM_THREADS` |
| :--- | :--- | :---: |
| **8 Cores / 16 Threads** | AMD Ryzen 7 5800X3D / Intel Core i7-13700 | **`6`** *(Default)* |
| **6 Cores / 12 Threads** | AMD Ryzen 5 5600X / Intel Core i5-12400 | **`4`** |
| **4 Cores / 8 Threads** | Intel Core i3-12100 / AMD Ryzen 3 3300X | **`2`** |

---

## 🚀 Quick Start Guide

1. Download **`fritchii-v6.0-zerostutter-win64.zip`** from [Releases](https://github.com/giangero1/Fritchii-ZeroStutter/releases/latest).
2. Extract the archive into a clean folder (e.g. `D:\Games\Fritchii-6.0-ZeroStutter`).
3. *(Recommended)* Drop `vulkan-frizti.fork-v54.bin` and `vulkan_used-frizti.fork-v54.bin` from the Google Drive / Gofile shader mirror into `user\cache\shader\0400486024dec000\`.
4. Run **`Play-Fritchii-6.0-ZeroStutter.cmd`** to launch `fritchii.exe` with `GPL=false` and `EDEN_NX2_SPIRV_INLINE_GLOBALS=2`!
5. Right-click the **`FG`** button on the bottom status bar (or open **Emulation → Configure → Graphics**) to switch between **DLSS-G**, **Optical Flow**, or **LSFG** at any time.

---

## 📜 Credits & License Attribution
* Built as an **unofficial modified fork** based on upstream Fritchii v6.0 (GNU GPLv3) and Lichii/Eden/yuzu contributors — not affiliated with or presented as Frizti's original release.
* **Shader precompile system by Frizti (Fritchii)** *(per GPLv3 Section 7 attribution notice; proprietary `*.nx2recipe` files are not redistributed in this fork's packages)*.

---

## 📦 Previous Versions (Preserved Backups)
- **Fritchii v5.9.0 Zero-Stutter (120+ FPS Proven Backup):** Permanently archived in the [v5.9.0 Release](https://github.com/giangero1/Fritchii-ZeroStutter/releases/tag/v5.9.0-zerostutter) and on the [`release/v5.9.0-zerostutter`](https://github.com/giangero1/Fritchii-ZeroStutter/tree/release/v5.9.0-zerostutter) branch.
- **Fritchii v5.8.4 Zero-Stutter:** Permanently archived in the [v5.8.4 Release](https://github.com/giangero1/Fritchii-ZeroStutter/releases/tag/v5.8.4-zerostutter-r1).
- **Fritchii v5.3 Zero-Stutter:** Permanently archived in the [v5.3 Release](https://github.com/giangero1/Fritchii-ZeroStutter/releases/tag/v5.3-zerostutter-r1) and on the [`backup/v5.3`](https://github.com/giangero1/Fritchii-ZeroStutter/tree/backup/v5.3) branch.
