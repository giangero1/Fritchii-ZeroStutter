// SPDX-FileCopyrightText: Copyright 2026 Fritchii ZeroStutter
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <deque>
#include <mutex>
#include <string>

#include <fmt/format.h>

#include "common/common_types.h"
#include "common/logging.h"
#include "video_core/renderer_vulkan/vk_scheduler.h"
#include "video_core/vulkan_common/vulkan_device.h"
#include "video_core/vulkan_common/vulkan_wrapper.h"

/// FRITCHII_GPU_ZONES (boot, default 1 in this test build; 0 off; ZeroStutter): GPU time of
/// the work the 4K output adds, measured with a timestamp pair around each pass, so a normal
/// play session says where the GPU's time goes (the daytime Castle Town market: 48 ms a frame
/// at 1440p -> 4K DLSS + frame generation, 20.7 ms at native 1440p). Each zone keeps a ring of
/// query pairs; results are read without waiting, once the GPU wrote them, and a line every
/// 10 s sums them up. Both timestamps are at the bottom of the pipe: the first when the work
/// before the zone is done, the second when the zone's own work is.
namespace Vulkan::GpuZones {

enum class Zone : u32 {
    Dlss,          ///< NVIDIA DLSS super resolution (Streamline evaluate)
    FrameGenInput, ///< Frame generation: the presented frame taken in (optical flow and so on)
    FrameGenMake,  ///< Frame generation: each generated frame made
    TextureDecode, ///< ASTC decode / BCn transcode passes of textures loaded (again)
    Count,
};

inline constexpr std::array<const char*, static_cast<size_t>(Zone::Count)> ZoneNames{
    "DLSS upscale", "frame gen input", "frame gen output", "texture decode"};

class Timer {
public:
    static Timer& Get() {
        static Timer timer;
        return timer;
    }

    static bool Enabled() {
        static const bool enabled = [] {
            const char* value = std::getenv("FRITCHII_GPU_ZONES");
            return value == nullptr || value[0] != '0';
        }();
        return enabled;
    }

    /// Records the zone's first timestamp. Returns the pair's slot (or ~0 when off).
    u32 Begin(const Device& device, Scheduler& scheduler, Zone zone) {
        if (!Enabled()) {
            return ~0U;
        }
        ZoneState& state = zones[static_cast<size_t>(zone)];
        std::scoped_lock lock{state.mutex};
        if (!Init(device, state)) {
            return ~0U;
        }
        Poll(device, state);
        const u32 slot = static_cast<u32>(state.next++ % Slots);
        // A slot still waiting to be read is given up (the GPU is far behind).
        std::erase(state.pending, slot);
        scheduler.RequestOutsideRenderPassOperationContext();
        scheduler.Record([pool = *state.pool, slot](vk::CommandBuffer cmdbuf) {
            cmdbuf.ResetQueryPool(pool, slot * 2, 2);
            cmdbuf.WriteTimestamp(VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, pool, slot * 2);
        });
        return slot;
    }

    /// Records the zone's second timestamp, after the zone's work was recorded.
    void End(Scheduler& scheduler, Zone zone, u32 slot) {
        if (slot == ~0U) {
            return;
        }
        ZoneState& state = zones[static_cast<size_t>(zone)];
        {
            std::scoped_lock lock{state.mutex};
            if (!state.pool) {
                return;
            }
            scheduler.RequestOutsideRenderPassOperationContext();
            scheduler.Record([pool = *state.pool, slot](vk::CommandBuffer cmdbuf) {
                cmdbuf.WriteTimestamp(VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, pool, slot * 2 + 1);
            });
            state.pending.push_back(slot);
        }
        LogIfDue(); // takes the zones' locks itself
    }

private:
    static constexpr u32 Slots = 512;

    struct ZoneState {
        std::mutex mutex;
        vk::QueryPool pool;
        bool failed{};
        u64 next{};
        std::deque<u32> pending;
        // Since the last line.
        u64 passes{};
        u64 total_ns{};
        u64 max_ns{};
    };

    bool Init(const Device& device, ZoneState& state) {
        if (state.pool) {
            return true;
        }
        if (state.failed) {
            return false;
        }
        const auto physical = device.GetPhysical();
        const u32 bits =
            physical.GetQueueFamilyProperties()[device.GetGraphicsFamily()].timestampValidBits;
        const float period = physical.GetProperties().limits.timestampPeriod;
        if (bits == 0 || bits > 64 || period <= 0.0f) {
            state.failed = true;
            return false;
        }
        mask = bits == 64 ? ~u64{0} : (u64{1} << bits) - 1;
        period_ns = period;
        try {
            state.pool = device.GetLogical().CreateQueryPool({
                .sType = VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO,
                .pNext = nullptr,
                .flags = 0,
                .queryType = VK_QUERY_TYPE_TIMESTAMP,
                .queryCount = Slots * 2,
                .pipelineStatistics = 0,
            });
        } catch (const vk::Exception& error) {
            LOG_WARNING(Render_Vulkan, "FRITCHII_GPU_ZONES unavailable: {}", error.what());
            state.failed = true;
            return false;
        }
        static std::once_flag logged;
        std::call_once(logged, [] {
            LOG_INFO(Render_Vulkan, "FRITCHII_GPU_ZONES: timing DLSS, frame generation and "
                                    "texture decode on the GPU (a line every 10 s)");
        });
        return true;
    }

    /// Reads the pairs the GPU finished, oldest first, without waiting.
    void Poll(const Device& device, ZoneState& state) {
        while (!state.pending.empty()) {
            const u32 slot = state.pending.front();
            std::array<u64, 4> values{}; // value, availability, value, availability
            const VkResult result = device.GetLogical().GetQueryResults(
                *state.pool, slot * 2, 2, sizeof(values), values.data(), sizeof(u64) * 2,
                VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WITH_AVAILABILITY_BIT);
            if ((result != VK_SUCCESS && result != VK_NOT_READY) || values[1] == 0 ||
                values[3] == 0) {
                break;
            }
            state.pending.pop_front();
            const u64 begin = values[0] & mask;
            const u64 end = values[2] & mask;
            if (end < begin) {
                continue;
            }
            const u64 ns = static_cast<u64>(static_cast<double>(end - begin) * period_ns);
            if (ns > 1'000'000'000ULL) {
                continue; // a pair split across a long pause: not the zone's time
            }
            ++state.passes;
            state.total_ns += ns;
            state.max_ns = (std::max)(state.max_ns, ns);
        }
    }

    void LogIfDue() {
        const auto now = std::chrono::steady_clock::now();
        std::scoped_lock lock{log_mutex};
        if (last_log == std::chrono::steady_clock::time_point{}) {
            last_log = now;
            return;
        }
        const auto elapsed = now - last_log;
        if (elapsed < std::chrono::seconds{10}) {
            return;
        }
        last_log = now;
        const double seconds = std::chrono::duration<double>(elapsed).count();
        std::string text;
        for (size_t index = 0; index < zones.size(); ++index) {
            ZoneState& state = zones[index];
            std::unique_lock zone_lock{state.mutex, std::try_to_lock};
            if (!zone_lock.owns_lock()) {
                continue; // the zone's thread holds it; its numbers go in the next line
            }
            if (state.passes == 0) {
                continue;
            }
            const double ms_per_s = static_cast<double>(state.total_ns) / 1e6 / seconds;
            const double avg_ms =
                static_cast<double>(state.total_ns) / 1e6 / static_cast<double>(state.passes);
            text += fmt::format("{}{} {:.1f} ms/s ({:.1f} passes/s, {:.2f} ms each, longest "
                                "{:.2f} ms)",
                                text.empty() ? "" : "; ", ZoneNames[index], ms_per_s,
                                static_cast<double>(state.passes) / seconds, avg_ms,
                                static_cast<double>(state.max_ns) / 1e6);
            state.passes = 0;
            state.total_ns = 0;
            state.max_ns = 0;
        }
        if (!text.empty()) {
            LOG_INFO(Render_Vulkan, "GPU zones (FRITCHII_GPU_ZONES) last {:.0f} s: {}", seconds,
                     text);
        }
    }

    std::array<ZoneState, static_cast<size_t>(Zone::Count)> zones;
    u64 mask{~u64{0}};
    double period_ns{1.0};
    std::mutex log_mutex;
    std::chrono::steady_clock::time_point last_log{};
};

/// Times the work recorded in its lifetime as `zone`.
class Scope {
public:
    Scope(const Device& device, Scheduler& scheduler_, Zone zone_)
        : scheduler{scheduler_}, zone{zone_},
          slot{Timer::Get().Begin(device, scheduler_, zone_)} {}
    ~Scope() {
        Timer::Get().End(scheduler, zone, slot);
    }
    Scope(const Scope&) = delete;
    Scope& operator=(const Scope&) = delete;

private:
    Scheduler& scheduler;
    Zone zone;
    u32 slot;
};

} // namespace Vulkan::GpuZones
