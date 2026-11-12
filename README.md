# Fritchii v5.8.4 Zero-Stutter Custom Build
### *The Legend of Zelda: Ocarina of Time (Nintendo Switch 2 Remake) on PC*

[![Release](https://img.shields.io/github/v/release/giangero1/Fritchii-ZeroStutter?color=brightgreen&label=Release)](https://github.com/giangero1/Fritchii-ZeroStutter/releases)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

Welcome to **Fritchii v5.8.4 Zero-Stutter**, an updated personal build featuring both our proven zero-stutter C++ engine patches and critical upstream fixes for the late-game white texture wash and glowing light bugs.

> [!NOTE]
> **Target Hardware & Configuration**:  
> This build was custom-tailored for the following PC setup:
> - **CPU:** AMD Ryzen 7 5800X3D (8 Cores / 16 Threads, 96 MB 3D V-Cache)
> - **GPU:** NVIDIA GeForce RTX 3070 (8 GB VRAM)
> - **RAM:** 32 GB DDR4
> - **OS:** Windows 10 / 11 64-bit
>
> If you have an NVIDIA RTX card and a modern high-cache CPU on Windows, this fork eliminates the notorious combat stutters (sword slashing, pot smashing, enemy attacks), traversal hitches, and late-game white texture bugs experienced with stock builds.

---

## 🛡️ Critical Visual & Rendering Fixes Included

1. **Fix for Spreading White Textures & Glowing Geometry (PR #1199):**
   - Fixes the bug where entering new areas or dungeons causes geometry to read freed GPU memory, producing `NaN` coordinates that turned terrain and character meshes solid white.
   - Refreshes stale SMMU device backing and unmaps destroyed GPU ranges upon area transitions.
2. **Nov 10 Upstream Occlusion Query Fix (`bda09fbc77`):**
   - Carries sample counts across query submissions rather than dropping counts past 1,024 slots. Eliminates camera-movement white flashes and overexposure.
3. **Compute Shader Storage Write Extent Protection:**
   - Fully tracks compute program storage buffers, preventing persistent glowing triangle artifacts in long play sessions.

---

## ⚡ Zero-Stutter C++ Engine Patches (Proven on RTX 3070 + 5800X3D)

1. **Compute Shader `DontInline` Directive:**
   - Forces `spv::FunctionControlMask::DontInline` on compute global memory helpers in `spirv_emit_context.cpp`.
   - Drops NVIDIA SPIR-V compiler freezes from **7.6 seconds down to <1 ms**, completely eliminating combat freezes when slashing grass, attacking enemies, and hitting pots.
2. **`GuessMissing` Disk Cache Fallback:**
   - Fallback in `CreateCachedGraphicsPipeline` prevents pipelines with unrecorded constant buffer descriptors from being discarded.
   - Ensures **100% of 28,612 pipelines** compile cleanly from disk cache at boot.
3. **Hardware Boost Launcher Suite (`Play-Fritchii-5.8.4-Boost.cmd`):**
   - Dual draw-call multi-core workers (`EDEN_NX2_SPLIT=2`), 6 pipeline warming threads (`EDEN_NX2_WARM_THREADS=6`), and syncpoint batching (`EDEN_NX2_PERF_ON=index_rebind,clean_words,fence_flush`).
   - Built-in GPL neutralization (`use_graphics_pipeline_library=false`).

---

## 💾 Pre-Warmed 28,612 Shader Cache

To ensure you experience zero shader compilation hitches from the very first second:
- 🔗 **Primary Mirror (Google Drive):** [Download Verified 28,612 Shaders](https://drive.google.com/file/d/1pa3T-D7lTcuo9B1RHP1HoejbtdUDqS6O/view)
- 🔗 **Alternative Mirror (Gofile):** [Download via Gofile Mirror](https://gofile.io/d/GBTsYoTL)

Extract the shader files directly into:
```text
lichii-zerostutter-win64/
├── Play-Fritchii-5.8.4-Boost.cmd
├── nx2_switches.txt
├── lichii.exe
└── user/
    └── cache/
        └── shader/
            └── 0400486024dec000/    <--- EXTRACT ALL SHADER FILES HERE
                ├── vulkan-frizti.fork-v54.bin
                ├── warm-graphics.bin
                ├── warm-compute.bin
                └── vulkan_static_pipelines.bin
```

---

## ⚙️ CPU Core & Thread Tuning (For 6-Core & 4-Core Users)

If your CPU has fewer than 8 cores, open `Play-Fritchii-5.8.4-Boost.cmd` (or `nx2_switches.txt`) and adjust `EDEN_NX2_WARM_THREADS`:

| CPU Cores / Threads | Example Processors | Recommended `WARM_THREADS` |
| :--- | :--- | :---: |
| **8 Cores / 16 Threads** | AMD Ryzen 7 5800X3D / Intel Core i7-13700 | **`6`** *(Default)* |
| **6 Cores / 12 Threads** | AMD Ryzen 5 5600X / Intel Core i5-12400 | **`4`** |
| **4 Cores / 8 Threads** | Intel Core i3-12100 / AMD Ryzen 3 3300X | **`2`** |

---

## 🚀 Quick Start
1. Download `lichii-zerostutter-win64.zip` from [Releases](https://github.com/giangero1/Fritchii-ZeroStutter/releases/latest).
2. Extract the archive into a folder of your choice.
3. (Recommended) Drop the pre-warmed shaders from Google Drive into `user\cache\shader\0400486024dec000\`.
4. Run `Play-Fritchii-5.8.4-Boost.cmd` to play!

---

## 📦 Previous Versions
- The previous stable Fritchii v5.3 build remains permanently archived in the [v5.3 Release](https://github.com/giangero1/Fritchii-ZeroStutter/releases/tag/v5.3-zerostutter-r1) and on the [`backup/v5.3`](https://github.com/giangero1/Fritchii-ZeroStutter/tree/backup/v5.3) branch.
