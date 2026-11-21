// SPDX-FileCopyrightText: Copyright 2026 Eden Emulator Project
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <algorithm>
#include <array>
#include <chrono>
#include <cstring>
#include <optional>
#include <span>

#include <fmt/ranges.h>

#include "common/logging.h"
#include "common/nx2_hitch.h"
#include "core/core.h"
#include "core/hle/kernel/k_process.h"
#include "core/memory.h"

namespace Service {

// Read-only diagnostics for OoT v131072. Screen membership is evidence for validation.
// The renderer does not consume this sample or use it to decide what to reclaim.
class Nx2OotMenuTrace {
public:
    void OnGuestPresent(Core::System& system, std::chrono::steady_clock::time_point now) {
        if (!Common::Nx2Hitch::OotStateTraceEnabled() || now < next_sample) {
            return;
        }
        next_sample = now + std::chrono::milliseconds{20};
        auto* const process = system.ApplicationProcess();
        if (!process || process->GetProgramId() != ProgramId) {
            return;
        }
        if (!checked_process || *checked_process != process->GetProcessId()) {
            checked_process = process->GetProcessId();
            previous.reset();
            const auto& build = system.GetApplicationProcessBuildID();
            main = std::equal(BuildId.begin(), BuildId.end(), build.begin())
                       ? process->GetOotMainCodeAddress()
                       : 0;
            LOG_INFO(Service, "OoT guest state trace: {}", main ? "v131072 probe active"
                                                                 : "unsupported executable");
        }
        if (main == 0) {
            return;
        }

        const Sample sample = ReadSample(process->GetMemory());
        if (sample == previous && now < next_heartbeat) {
            return;
        }
        previous = sample;
        next_heartbeat = now + std::chrono::seconds{2};
        LOG_INFO(Service,
                 "OoT guest state: scene object {:#x}, menu slots [{}, {}, {}, {}], "
                 "selector {}, map flag {}, ocarina play {}, display {}, screens ready {}, "
                 "active item menu {}, overlay {}, map {}, ocarina {}, loading fade {}, "
                 "visible screen vtables [{:#x}]",
                 sample.scene, sample.menu[0], sample.menu[1], sample.menu[2], sample.menu[3],
                 sample.selector, sample.map_flag, sample.ocarina_play, sample.ocarina_display,
                 sample.screens_ready, sample.active[0], sample.active[1], sample.active[2],
                 sample.active[3], sample.active[4],
                 fmt::join(std::span{sample.visible}.first(sample.visible_count), ", "));
    }

private:
    static constexpr u64 ProgramId = 0x0400486024DEC000;
    static constexpr std::array<u8, 20> BuildId{
        0xE0, 0xF3, 0xCC, 0xFA, 0xF5, 0x00, 0x65, 0xAE, 0x4E, 0xA0,
        0x1E, 0xB5, 0xAE, 0xB1, 0x3B, 0x1A, 0x45, 0xDA, 0x33, 0x48,
    };
    // Module-relative singleton slots used by the game's UI and ocarina query routines.
    static constexpr u64 UiManager = 0x4E7CFA8;
    static constexpr u64 ScreenRegistry = 0x4E84518;
    static constexpr u64 PlayerManager = 0x4E97648;
    static constexpr u64 SceneRegistry = 0x4E950A8;
    static constexpr u64 OcarinaManagerVtable = 0x4BA1978;
    static constexpr u64 DataStart = 0x484D000;
    static constexpr u64 DataEnd = 0x4D46B80;
    // Instance vtables for UIPlusMenuScreen (item menu), UIMenuOverlayScreen,
    // UIMapMenuScreen, UIOcarinaScreen, and UILoadingFadeScreen.
    static constexpr std::array<u64, 5> ScreenVtables{
        0x4BEBAA8, 0x4BE8AA0, 0x4BE8300, 0x4BEA4F8, 0x4BE7B30,
    };

    struct Sample {
        u64 scene{};
        std::array<s32, 4> menu{-1, -1, -1, -1};
        int selector{-1};
        int map_flag{-1};
        s32 ocarina_play{-1};
        s32 ocarina_display{-1};
        bool screens_ready{};
        std::array<bool, ScreenVtables.size()> active{};
        std::array<u64, 32> visible{};
        size_t visible_count{};
        bool operator==(const Sample&) const = default;
    };

    template <typename T>
    static std::optional<T> Read(Core::Memory::Memory& memory, u64 address) {
        if (!address || (address & Core::Memory::YUZU_PAGEMASK) +
                            sizeof(T) > Core::Memory::YUZU_PAGESIZE) {
            return std::nullopt;
        }
        const u8* const host = memory.GetPointerSilent(address);
        if (!host) {
            return std::nullopt;
        }
        T value;
        std::memcpy(&value, host, sizeof(value));
        return value;
    }

    static u64 Pointer(Core::Memory::Memory& memory, u64 address) {
        return Read<u64>(memory, address).value_or(0);
    }

    Sample ReadSample(Core::Memory::Memory& memory) const {
        Sample sample;
        if (const u64 ui = Pointer(memory, main + UiManager)) {
            if (const auto menu = Read<decltype(sample.menu)>(memory, ui + 0x52C)) {
                sample.menu = *menu;
            }
            sample.selector = Read<u8>(memory, ui + 0x53C).value_or(0xFF);
            sample.map_flag = Read<u8>(memory, ui + 0x53D).value_or(0xFF);
        }
        if (const u64 scenes = Pointer(memory, main + SceneRegistry)) {
            sample.scene = Pointer(memory, Pointer(memory, scenes + 0x58));
        }
        if (const u64 player = Pointer(memory, main + PlayerManager)) {
            if (const u64 components = Pointer(memory, player + 0x1F0);
                components && Read<s32>(memory, components + 0x50).value_or(0) > 0x20) {
                if (const u64 entries = Pointer(memory, components + 0x58)) {
                    if (const u64 ocarina = Pointer(memory, entries + 0x100);
                        ocarina && Pointer(memory, ocarina) == main + OcarinaManagerVtable) {
                        sample.ocarina_play = Read<s32>(memory, ocarina + 0x230).value_or(-1);
                        sample.ocarina_display = Read<s32>(memory, ocarina + 0x278).value_or(-1);
                    }
                }
            }
        }
        if (const u64 registry = Pointer(memory, main + ScreenRegistry)) {
            const u32 count = Read<u32>(memory, registry + 0x8).value_or(0);
            const u64 entries = Pointer(memory, registry + 0x10);
            sample.screens_ready = entries && count > 0 && count <= 512;
            if (sample.screens_ready) {
                for (u32 index = 0; index < count; ++index) {
                    const u64 screen = Pointer(memory, entries + index * sizeof(u64));
                    const u64 vtable = Pointer(memory, screen);
                    if (vtable < main + DataStart || vtable >= main + DataEnd) {
                        continue;
                    }
                    // The game's screen-visible predicate at main+0xA687F0.
                    const bool visible =
                        Read<u8>(memory, screen + 0x1A6).value_or(0) == 2 &&
                        Read<u8>(memory, screen + 0x1A5).value_or(0xFF) < 0x80;
                    if (!visible) {
                        continue;
                    }
                    const u64 offset = vtable - main;
                    if (sample.visible_count < sample.visible.size()) {
                        sample.visible[sample.visible_count++] = offset;
                    }
                    for (size_t kind = 0; kind < ScreenVtables.size(); ++kind) {
                        if (offset == ScreenVtables[kind]) {
                            sample.active[kind] = true;
                            break;
                        }
                    }
                }
            }
        }
        return sample;
    }

    std::optional<u64> checked_process;
    std::optional<Sample> previous;
    std::chrono::steady_clock::time_point next_sample{};
    std::chrono::steady_clock::time_point next_heartbeat{};
    u64 main{};
};

} // namespace Service
