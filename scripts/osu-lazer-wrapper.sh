#!/usr/bin/env bash
# ==============================================================================
# osu-lazer-wrapper.sh
# Production launch wrapper for ultra-low audio & input latency in osu!lazer
# ==============================================================================

export OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD="${OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD:--32}"
export PIPEWIRE_LATENCY="${PIPEWIRE_LATENCY:-32/44100}"
export PIPEWIRE_ALSA="${PIPEWIRE_ALSA:-{ alsa.format=S32_LE alsa.channels=2 alsa.buffer-bytes=512 alsa.period-bytes=256 }}"

launch_osu() {
    if [ -n "$OSU_BIN" ]; then
        exec "$OSU_BIN" "$@"
    elif command -v osu-lazer >/dev/null 2>&1; then
        exec osu-lazer "$@"
    elif [ -x "$HOME/.local/bin/osu.AppImage" ]; then
        exec "$HOME/.local/bin/osu.AppImage" "$@"
    elif command -v flatpak >/dev/null 2>&1 && flatpak info sh.ppy.osu >/dev/null 2>&1; then
        exec flatpak run \
            --env=OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD="$OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD" \
            --env=PIPEWIRE_LATENCY="$PIPEWIRE_LATENCY" \
            --env=PIPEWIRE_ALSA="$PIPEWIRE_ALSA" \
            sh.ppy.osu "$@"
    else
        echo "Error: osu!lazer binary not found. Set OSU_BIN=/path/to/osu.AppImage" >&2
        return 1
    fi
}

# 1. If osu! is already running, forward URI/beatmap args directly without touching active hooks
if pgrep -x 'osu!' >/dev/null 2>&1; then
    launch_osu "$@"
fi

# 2. OpenTabletDriver Auto-Management (Optional)
# Uncomment to start OpenTabletDriver on game launch and stop it on exit if it wasn't running:
# was_otd_active=$(systemctl --user is-active opentabletdriver.service 2>/dev/null)
# systemctl --user start opentabletdriver.service 2>/dev/null

# 3. Lock PipeWire Graph Clock Rate & Quantum (derived from PIPEWIRE_LATENCY, default 32/44100)
# Requires 44100 (or target rate) in PipeWire allowed-rates (see pipewire/10-rates.conf)
TARGET_QUANTUM="${PIPEWIRE_LATENCY%%/*}"
TARGET_RATE="${PIPEWIRE_LATENCY##*/}"
pw-metadata -n settings 0 clock.force-rate "${TARGET_RATE:-44100}" >/dev/null 2>&1
pw-metadata -n settings 0 clock.force-quantum "${TARGET_QUANTUM:-32}" >/dev/null 2>&1

# 4. CPU & GPU Low-Latency Power Profile Automation
if command -v powerprofilesctl >/dev/null 2>&1; then
    powerprofilesctl set performance >/dev/null 2>&1
fi

# Auto-detect AMD DRM device and switch to VR Low-Latency profile (mode 4) if writable via udev
AMD_DRM_DEV=""
for dev in /sys/class/drm/card[0-9]/device; do
    if [ "$(basename "$(readlink -f "$dev/driver" 2>/dev/null)")" = "amdgpu" ]; then
        AMD_DRM_DEV="$dev"
        break
    fi
done

if [ -n "$AMD_DRM_DEV" ] && [ -w "$AMD_DRM_DEV/power_dpm_force_performance_level" ]; then
    # If using LACT daemon, set LACT_GPU_ID (from `lact cli list`) to temporarily detach/reattach it
    [ -n "$LACT_GPU_ID" ] && command -v lact >/dev/null 2>&1 && lact cli --gpu-id "$LACT_GPU_ID" detach >/dev/null 2>&1
    echo manual > "$AMD_DRM_DEV/power_dpm_force_performance_level" 2>/dev/null
    echo 4 > "$AMD_DRM_DEV/pp_power_profile_mode" 2>/dev/null
fi

cleanup() {
    kill "$RT_PID" 2>/dev/null
    pw-metadata -n settings 0 clock.force-quantum 0 >/dev/null 2>&1
    pw-metadata -n settings 0 clock.force-rate 0 >/dev/null 2>&1
    if command -v powerprofilesctl >/dev/null 2>&1; then
        powerprofilesctl set balanced >/dev/null 2>&1
    fi
    if [ -n "$AMD_DRM_DEV" ] && [ -w "$AMD_DRM_DEV/power_dpm_force_performance_level" ]; then
        echo auto > "$AMD_DRM_DEV/power_dpm_force_performance_level" 2>/dev/null
        [ -n "$LACT_GPU_ID" ] && command -v lact >/dev/null 2>&1 && lact cli --gpu-id "$LACT_GPU_ID" reattach >/dev/null 2>&1
    fi
    # if [ "$was_otd_active" != "active" ]; then
    #     systemctl --user stop opentabletdriver.service >/dev/null 2>&1
    # fi
}
trap cleanup EXIT

# 5. Realtime Audio Thread Boosting & Process Nice Priority
# Target for SCHED_FIFO: Native C BASS audio (Audio*:RR) and alsa-pipewire driver threads.
# Target for Nice -11: Whole osu! process (keeps managed .NET Update/Draw & GC threads balanced).
# CRITICAL: '-R' (SCHED_RESET_ON_FORK) is mandatory; NEVER boost managed .NET threads to SCHED_FIFO.
OSU_RT_PRIO=75

rt_boost() {
    local pid=""
    for _ in $(seq 60); do
        pid=$(pgrep -x 'osu!' | head -1)
        [ -n "$pid" ] && break
        sleep 1
    done
    [ -z "$pid" ] && return

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

# 6. Launch osu!lazer (keep child process under wrapper so cleanup trap runs on exit)
( launch_osu "$@" )
