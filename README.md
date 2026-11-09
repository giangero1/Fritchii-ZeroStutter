# Fritchii v5.3 Zero-Stutter Custom Build
### *The Legend of Zelda: Ocarina of Time (Nintendo Switch 2 Remake) on PC*

[![Release](https://img.shields.io/github/v/release/giangero1/Fritchii-ZeroStutter?color=brightgreen&label=Release)](https://github.com/giangero1/Fritchii-ZeroStutter/releases)
[![Build Status](https://img.shields.io/github/actions/workflow/status/giangero1/Fritchii-ZeroStutter/build-release.yml?branch=main&label=CI%20Build)](https://github.com/giangero1/Fritchii-ZeroStutter/actions)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

This is a personal, independent public fork of **Fritchii v5.3 / Lichii**, custom-tailored to achieve a **locked 60 FPS with zero stutters** in *The Legend of Zelda: Ocarina of Time (Switch 2 Remake)* on PC.

> [!NOTE]
> **Target Hardware & Configuration**:  
> This build was custom-tailored for the following PC setup:
> - **CPU:** AMD Ryzen 7 5800X3D (8 Cores / 16 Threads, 96 MB 3D V-Cache)
> - **GPU:** NVIDIA GeForce RTX 3070 (8 GB VRAM)
> - **RAM:** 32 GB DDR4
> - **OS:** Windows 11 64-bit
>
> If you have an NVIDIA RTX card and a modern high-cache CPU on Windows, this fork eliminates the notorious combat stutters (sword slashing, pot smashing, enemy attacks) and traversal hitches experienced with stock builds.

---

## ⚡ Why Stock Emulators Stutter on NVIDIA Windows

Stock Fritchii / Lichii and other emulators suffer from two primary bottlenecks on NVIDIA Windows drivers:

1. **Compute Shader Function Inlining (7.6-Second GPU Freezes):**
   When attacking enemies, breaking pots, cutting grass, or triggering particle effects, the emulator emits complex compute shaders. The NVIDIA Vulkan driver's SPIR-V optimizer attempts to inline large global memory helper functions, causing shader compilation to spike up to **7,600 ms (7.6 seconds)** right in the middle of combat!
2. **Missing Constant Buffer Descriptors (Cache Discards):**
   The stock disk pipeline cache reader discards valid cached graphics pipelines whenever they lack pre-recorded constant buffer descriptor metadata. Instead of loading from disk, the emulator discards them, forcing full re-compilation while traversing the overworld.

---

## 🛡️ The 3 Zero-Stutter Pillars Implemented

### Pillar 1: Compute Shader `DontInline` Directive
- **File:** `src/shader_recompiler/backend/spirv/spirv_emit_context.cpp`
- **Fix:** Injects `spv::FunctionControlMask::DontInline` into compute global memory helper functions when `EDEN_NX2_COMPUTE_NOINLINE=1`.
- **Result:** Drops NVIDIA driver compile times from **7.6 seconds down to <1 ms**, completely eliminating mid-combat frame freezes.

### Pillar 2: `GuessMissing` Disk Cache Fallback
- **File:** `src/video_core/renderer_vulkan/vk_pipeline_cache.cpp`
- **Fix:** Injects `static const GuessMissing guess{};` and `env.SetGuessMissing(&guess)` into `CreateCachedGraphicsPipeline`.
- **Result:** Pipelines with unrecorded constant buffer descriptors are safely guessed rather than discarded, allowing **100% of 28,612 pipeline caches** to load at boot.

### Pillar 3: Hardware Boost Launcher Suite
- **Launcher:** [`Play-Fritchii-5.3-Boost.cmd`](Play-Fritchii-5.3-Boost.cmd)
- **Engine Flags:**
  - `EDEN_NX2_COMPUTE_NOINLINE=1`: Activates Pillar 1 SPIR-V non-inlining.
  - `EDEN_NX2_PRELOAD_ALL_PIPELINES=1`: Forces all compiled pipelines into VRAM at startup.
  - `EDEN_NX2_SPLIT=2`: Dedicated dual multi-core Vulkan draw-call dispatch worker.
  - `EDEN_NX2_WARM_THREADS=6`: Affinitized pipeline warmup thread pool.
  - `EDEN_NX2_PERF_ON=index_rebind,clean_words,fence_flush`: Draw-call and fence syncpoint batching.
  - `use_graphics_pipeline_library=false`: Disables dynamic Graphics Pipeline Library (GPL) runtime stalls.

---

## 🚀 Quick Start Guide (For Viewers & Players)

### Step 1: Download the Zero-Stutter Build
Grab the latest pre-compiled archive from the [Releases](https://github.com/giangero1/Fritchii-ZeroStutter/releases) page:
- **`lichii-zerostutter-win64.zip`** (Compiled with Clang 19 ThinLTO).

### Step 2: Download the Pre-Warmed 28,612 Shader Pack
Download my verified full shader cache archive:
- 🔗 **Google Drive Shader Cache:** [Download Full Shader Pack](https://drive.google.com/file/d/1pa3T-D7lTcuo9B1RHP1HoejbtdUDqS6O/view)

Extract the shader files directly into:
```text
user/cache/shader/0400486024dec000/
```

### Step 3: Launch with Boost
Double-click:
```cmd
Play-Fritchii-5.3-Boost.cmd
```
All RTX 3070 / Ryzen 5800X3D boost environment variables will be injected automatically, and your game will boot with 100% pre-loaded pipelines at a locked 60 FPS.

---

## 🛠️ Automated Upgrade Engine

Want to rebase these exact zero-stutter C++ patches onto future upstream releases?

Run:
```cmd
Upgrade-Fritchii.cmd
```
This script will automatically checkout the specified git tag, apply the `GuessMissing`, `compute_noinline`, and `Header` patches, compile via Clang ThinLTO, and configure the runtime launcher.

---

## ⚖️ Upstream & Disclaimer

This is a personal hobbyist fork for streaming and educational purposes.
- Upstream base: [Frizti/Fritchii](https://github.com/Frizti/Fritchii) and [zortos293/Lichii](https://github.com/zortos293/Lichii).
- Please do not submit bug reports or issues related to this custom build to the upstream developers.
