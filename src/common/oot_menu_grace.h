// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdlib>

namespace Common::OotMenuGrace {

using Clock = std::chrono::steady_clock;

inline bool Enabled() {
    static const bool enabled = [] {
        const char* value = std::getenv("FRITCHII_OOT_MENU_VRAM_GRACE");
        return value != nullptr && value[0] == '1';
    }();
    return enabled;
}

// The input side estimates the transition. The cache independently checks whether it can wait.
inline std::atomic<Clock::duration::rep> deadline{};
inline std::atomic<bool> escape_pressed{};

inline void Publish(Clock::time_point until) {
    deadline.store(until.time_since_epoch().count(), std::memory_order_relaxed);
}

inline bool Active(Clock::time_point now) {
    return Enabled() && now.time_since_epoch().count() < deadline.load(std::memory_order_relaxed);
}

class InputState {
public:
    Clock::time_point Update(Clock::time_point now, bool overlay_held, bool pause_pressed,
                             bool back_pressed, bool ocarina_pressed = false) {
        using namespace std::chrono_literals;
        if (pause_pressed && now >= next_pause_press) {
            // Escape may also be assigned to the emulated Plus button.
            next_pause_press = now + 100ms;
            if (now < pause_until) {
                pause_until = {};
                exit_until = now + 1s;
            } else {
                pause_until = now + 60s;
            }
        } else if (back_pressed && now < pause_until) {
            pause_until = {};
            exit_until = now + 1s;
        }
        if (ocarina_pressed) {
            ocarina_until = now + 15s;
        } else if (back_pressed && now < ocarina_until) {
            ocarina_until = {};
            exit_until = now + 1s;
        }
        if (overlay_was_held && !overlay_held) {
            exit_until = now + 1s;
        }
        overlay_was_held = overlay_held;
        // A disconnected input source or a stopped game cannot leave the hold latched.
        return (std::max)({pause_until, ocarina_until, exit_until, overlay_held ? now + 100ms : now});
    }

private:
    Clock::time_point pause_until{};
    Clock::time_point ocarina_until{};
    Clock::time_point exit_until{};
    Clock::time_point next_pause_press{};
    bool overlay_was_held{};
};

} // namespace Common::OotMenuGrace
