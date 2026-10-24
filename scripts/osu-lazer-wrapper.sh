#!/usr/bin/env bash
# ==============================================================================
# osu-lazer-wrapper.sh
# Production launch wrapper for ultra-low audio & input latency in osu!lazer
# ==============================================================================

# 1. OpenTabletDriver / Wacom Pen Toggle Integration (Optional)
# Uncomment if using OpenTabletDriver and wanting daemon auto-management:
# was_otd_active=$(systemctl --user is-active opentabletdriver.service 2>/dev/null)
# systemctl --user start opentabletdriver.service 2>/dev/null

# 2. Lock PipeWire Graph Clock Rate (44.1kHz) & Quantum (32 frames = 0.725ms)
# Prevents dynamic resampling to 48kHz or quantum inflation when Discord/Chrome are open
pw-metadata -n settings 0 clock.force-rate 44100 >/dev/null 2>&1
pw-metadata -n settings 0 clock.force-quantum 32 >/dev/null 2>&1

# 3. CPU & GPU Low-Latency Power Profile Automation
# Switch CPU into performance mode to lock core boost & eliminate C-state wake latency
if command -v powerprofilesctl >/dev/null 2>&1; then
    powerprofilesctl set performance >/dev/null 2>&1
fi

# Optional: Switch AMD GPU to VR Low-Latency power profile (profile 4) if writable via udev rule
# (If using LACT daemon, detach before writing sysfs and reattach in cleanup)
AMD_DRM_DEV="/sys/class/drm/card1/device"
if [ -w "$AMD_DRM_DEV/power_dpm_force_performance_level" ]; then
    echo manual > "$AMD_DRM_DEV/power_dpm_force_performance_level" 2>/dev/null
    echo 4 > "$AMD_DRM_DEV/pp_power_profile_mode" 2>/dev/null
fi

cleanup() {
    kill "$RT_PID" 2>/dev/null
    # Restore automatic PipeWire graph quantum and rate
    pw-metadata -n settings 0 clock.force-quantum 0 >/dev/null 2>&1
    pw-metadata -n settings 0 clock.force-rate 0 >/dev/null 2>&1
    # Restore balanced CPU power profile
    if command -v powerprofilesctl >/dev/null 2>&1; then
        powerprofilesctl set balanced >/dev/null 2>&1
    fi
    # Restore automatic AMD GPU power profile
    if [ -w "$AMD_DRM_DEV/power_dpm_force_performance_level" ]; then
        echo auto > "$AMD_DRM_DEV/power_dpm_force_performance_level" 2>/dev/null
    fi
    # Optional: Stop OpenTabletDriver if it wasn't running prior to game launch
    # if [ "$was_otd_active" != "active" ]; then
    #     systemctl --user stop opentabletdriver.service >/dev/null 2>&1
    # fi
}
trap cleanup EXIT

# 4. Realtime Audio Thread Boosting & Process Nice Priority
# Target for SCHED_FIFO: Native C BASS audio (Audio*:RR) and alsa-pipewire driver threads.
# Target for Nice -11: Whole osu! process (boosts managed .NET Update/Draw & GC threads
#                      together in SCHED_OTHER/BORE/scx_lavd without priority inversion).
# CRITICAL NOTE: The threads use SCHED_RESET_ON_FORK; the '-R' flag is MANDATORY.
# CRITICAL WARNING: NEVER boost managed .NET CLR threads ('Update', 'Draw', 'Audio (GameThread):TS')
# to SCHED_FIFO! Starving .NET GC worker threads causes safepoint deadlocks and silent crashes.
OSU_RT_PRIO=75

rt_boost() {
    local pid=""
    for _ in $(seq 60); do
        pid=$(pgrep -x 'osu!' | head -1)
        [ -n "$pid" ] && break
        sleep 1
    done
    [ -z "$pid" ] && return

    # Boost overall process nice priority (requires RLIMIT_NICE / CAP_SYS_NICE)
    renice -n -11 -p "$pid" >/dev/null 2>&1

    while kill -0 "$pid" 2>/dev/null; do
        ps -L -o tid=,cls=,comm= -p "$pid" | while read -r tid cls comm; do
            case "$comm:$cls" in
                Audio*:RR|alsa-pipewire:*)
                    chrt -f -R -p "$OSU_RT_PRIO" "$tid" 2>/dev/null
                    ;;
            esac
        done
        sleep 5
    done
}
rt_boost &
RT_PID=$!

# 5. Launch osu!lazer
# - OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD=-32: Sets BASS internal device period to 32 samples
#   and device buffer to 64 samples (2x period), working for both PipeWire and Raw ALSA devices.
# - Frame math: S32_LE (4 bytes) * 2 channels = 8 bytes/frame.
# - alsa.period-bytes=256 -> exactly 32 frames (0.725ms), matching PipeWire quantum 32 1:1.
#   (Avoids pipewire-alsa's internal min-avail=58 floor when period-bytes is too small).
# - alsa.buffer-bytes=512 -> 64 frames (1.45ms) total ring buffer (~0.6ms actual appl-hw delta).
export OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD="${OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD:--32}"
export PIPEWIRE_LATENCY="${PIPEWIRE_LATENCY:-32/44100}"
export PIPEWIRE_ALSA="${PIPEWIRE_ALSA:-{ alsa.format=S32_LE alsa.channels=2 alsa.buffer-bytes=512 alsa.period-bytes=256 }}"

if [ -n "$OSU_BIN" ]; then
    "$OSU_BIN" "$@"
elif command -v osu-lazer >/dev/null 2>&1; then
    osu-lazer "$@"
elif [ -x "$HOME/.local/bin/osu.AppImage" ]; then
    "$HOME/.local/bin/osu.AppImage" "$@"
elif command -v flatpak >/dev/null 2>&1 && flatpak info sh.ppy.osu >/dev/null 2>&1; then
    flatpak run --env=OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD="$OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD" \
                --env=PIPEWIRE_LATENCY="$PIPEWIRE_LATENCY" \
                --env=PIPEWIRE_ALSA="$PIPEWIRE_ALSA" \
                sh.ppy.osu "$@"
else
    echo "Error: osu!lazer binary not found. Set OSU_BIN=/path/to/osu.AppImage" >&2
    exit 1
fi
