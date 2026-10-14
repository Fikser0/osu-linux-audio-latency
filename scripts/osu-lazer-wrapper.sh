#!/usr/bin/env bash
# ==============================================================================
# osu-lazer-wrapper.sh
# Production launch wrapper for ultra-low audio latency in osu!lazer on Linux
# ==============================================================================

# 1. OpenTabletDriver Integration (Optional)
# Uncomment if using OpenTabletDriver and wanting daemon auto-management:
# was_otd_active=$(systemctl --user is-active opentabletdriver.service 2>/dev/null)

# 2. Lock PipeWire Graph Clock Rate
# Prevents dynamic resampling to 48kHz when apps like Discord/Chrome start
pw-metadata -n settings 0 clock.force-rate 44100 >/dev/null 2>&1

# 3. CPU Power Governor Automation
# Switch CPU into performance mode to lock core boost & eliminate C-state wake latency
if command -v powerprofilesctl >/dev/null 2>&1; then
    powerprofilesctl set performance >/dev/null 2>&1
fi

cleanup() {
    # Restore automatic PipeWire graph rate
    pw-metadata -n settings 0 clock.force-rate 0 >/dev/null 2>&1
    # Restore balanced CPU power profile
    if command -v powerprofilesctl >/dev/null 2>&1; then
        powerprofilesctl set balanced >/dev/null 2>&1
    fi
}
trap cleanup EXIT

# 4. Realtime Audio Thread Boosting
# Target: Native C BASS audio and alsa-pipewire driver threads.
# CRITICAL NOTE: The threads use SCHED_RESET_ON_FORK; the '-R' flag is MANDATORY.
# CRITICAL WARNING: NEVER boost managed .NET CLR threads (like 'Update' or 'Draw').
# Starving the .NET GC threads causes deadlocks and silent process crashes.
OSU_RT_PRIO=75

rt_boost() {
    local pid=""
    for _ in $(seq 60); do
        pid=$(pgrep -x 'osu!' | head -1)
        [ -n "$pid" ] && break
        sleep 1
    done
    [ -z "$pid" ] && return

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
# Quantum 32 @ 44.1kHz = 0.725ms software buffer slice.
# alsa.buffer-bytes=1024 (128 frames) gives safety margin to prevent xruns
# during heavy map loading or Discord screen sharing.
PIPEWIRE_LATENCY="32/44100" \
PIPEWIRE_ALSA='{ alsa.format=S32_LE alsa.channels=2 alsa.buffer-bytes=1024 alsa.period-bytes=64 }' \
/usr/bin/osu-lazer "$@"

# 6. Cleanup Background Boost Daemon
kill "$RT_PID" 2>/dev/null
