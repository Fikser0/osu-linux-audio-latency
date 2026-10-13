#!/usr/bin/env bash
# ==============================================================================
# audio-latency-doctor.sh
# Diagnostic and verification tool for Linux rhythm gaming audio latency
# ==============================================================================

BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
BLUE="\033[34m"
RESET="\033[0m"

echo -e "${BOLD}${BLUE}=== Linux Rhythm Gaming Audio Doctor ===${RESET}\n"

# 1. Realtime Scheduling Limits
echo -e "${BOLD}[1] Checking Realtime Scheduling Limits...${RESET}"
rt_limit=$(ulimit -r)
if [ "$rt_limit" -ge 75 ] 2>/dev/null; then
    echo -e "  ${GREEN}✓ Realtime priority limit:${RESET} $rt_limit (>= 75, OK)"
else
    echo -e "  ${YELLOW}⚠ Realtime limit is $rt_limit.${RESET} Consider adding user to 'realtime' or 'audio' group in /etc/security/limits.d/"
fi

# 2. PipeWire & WirePlumber Status
echo -e "\n${BOLD}[2] Checking PipeWire Graph Status...${RESET}"
if command -v pw-metadata >/dev/null 2>&1; then
    rate=$(pw-metadata -n settings 2>/dev/null | grep 'clock.force-rate' | grep -oP "value:'\K[^']+")
    quantum=$(pw-metadata -n settings 2>/dev/null | grep 'clock.quantum' | head -1 | grep -oP "value:'\K[^']+")
    echo -e "  ${GREEN}✓ PipeWire settings active:${RESET} force-rate=${rate:-0 (auto)}, default-quantum=${quantum:-1024}"
else
    echo -e "  ${RED}✗ pw-metadata not found.${RESET}"
fi

# 3. CPU Governor / Energy Preference
echo -e "\n${BOLD}[3] Checking CPU Power Mode...${RESET}"
if command -v powerprofilesctl >/dev/null 2>&1; then
    profile=$(powerprofilesctl get 2>/dev/null)
    if [ "$profile" = "performance" ]; then
        echo -e "  ${GREEN}✓ CPU Profile:${RESET} performance (C-state latency minimized)"
    else
        echo -e "  ${YELLOW}ℹ CPU Profile:${RESET} $profile (Consider 'performance' mode while gaming)"
    fi
elif [ -f /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference ]; then
    epp=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference)
    echo -e "  CPU EPP: $epp"
fi

# 4. ALSA Hardware Ring Buffer Delay
echo -e "\n${BOLD}[4] Inspecting ALSA Hardware Ring Buffer Delay...${RESET}"
found_card=0
for status_file in /proc/asound/card*/pcm*p/sub*/status; do
    if [ -f "$status_file" ]; then
        state=$(grep '^state:' "$status_file" | awk '{print $2}')
        if [ "$state" = "RUNNING" ]; then
            card_dir=$(dirname "$status_file")
            delay=$(grep '^delay:' "$status_file" | awk '{print $2}')
            rate=$(grep '^rate:' "$card_dir/hw_params" 2>/dev/null | awk '{print $2}' | cut -d'(' -f1)
            period=$(grep '^period_size:' "$card_dir/hw_params" 2>/dev/null | awk '{print $2}')
            
            if [ -n "$delay" ] && [ -n "$rate" ] && [ "$rate" -gt 0 ] 2>/dev/null; then
                delay_ms=$(awk "BEGIN {printf \"%.2f\", $delay / ($rate / 1000)}")
                found_card=1
                echo -e "  ${BLUE}Device:${RESET} $card_dir"
                echo -e "  Rate: ${rate}Hz | Period Size: ${period} samples"
                if (( $(awk "BEGIN {print ($delay_ms <= 15.0)}") )); then
                    echo -e "  ${GREEN}✓ Hardware Delay:${RESET} ${delay} samples (~${delay_ms}ms) [LOCKED LOW-LATENCY]"
                else
                    echo -e "  ${YELLOW}⚠ Hardware Delay:${RESET} ${delay} samples (~${delay_ms}ms) [HIGH HARDWARE BUFFER BLOAT]"
                    echo -e "    ${YELLOW}Hint: Apply the WirePlumber rule to lock period-size=64 and headroom=32.${RESET}"
                fi
            fi
        fi
    fi
done

if [ "$found_card" -eq 0 ]; then
    echo -e "  ${YELLOW}ℹ No active ALSA playback stream currently playing audio.${RESET}"
fi

# 5. osu! Process & Thread Priority Check
echo -e "\n${BOLD}[5] Checking osu! Process & Thread Scheduling...${RESET}"
osu_pid=$(pgrep -x 'osu!' | head -1)
if [ -n "$osu_pid" ]; then
    echo -e "  ${GREEN}✓ osu! is running (PID: $osu_pid)${RESET}"
    echo -e "  Thread priorities:"
    ps -L -o tid,cls,rtprio,comm -p "$osu_pid" | while read -r tid cls prio comm; do
        case "$comm" in
            Audio*|alsa-pipewire)
                if [ "$cls" = "FF" ] && [ "$prio" -ge 70 ] 2>/dev/null; then
                    echo -e "    ${GREEN}✓ TID $tid ($comm):${RESET} $cls $prio (Realtime)"
                else
                    echo -e "    ${YELLOW}⚠ TID $tid ($comm):${RESET} $cls $prio (Normal - run wrapper for RT boost)"
                fi
                ;;
            Update*)
                if [ "$cls" = "TS" ]; then
                    echo -e "    ${GREEN}✓ TID $tid ($comm):${RESET} $cls (Managed .NET - safe from GC deadlock)"
                else
                    echo -e "    ${RED}✗ TID $tid ($comm):${RESET} $cls $prio (WARNING: Managed thread in RT causes GC crash!)"
                fi
                ;;
        esac
    done
else
    echo -e "  ${YELLOW}ℹ osu! is not running currently.${RESET}"
fi

# 6. pw-top Snapshot
echo -e "\n${BOLD}[6] PipeWire Active Stream Snapshot (pw-top):${RESET}"
if command -v pw-top >/dev/null 2>&1; then
    pw-top -b -n 2 2>&1 | tail -15 | grep -E 'QUANT|osu|Scarlett|vesktop|vencord|alsa_output' || pw-top -b -n 2 2>&1 | tail -10
fi

echo -e "\n${BOLD}${BLUE}=== Inspection Complete ===${RESET}\n"
