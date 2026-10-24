#!/usr/bin/env bash
# ==============================================================================
# audio-latency-doctor.sh
# Diagnostic and verification tool for Linux rhythm gaming audio & input latency
# ==============================================================================

BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
BLUE="\033[34m"
RESET="\033[0m"

echo -e "${BOLD}${BLUE}=== Linux Rhythm Gaming Audio & Input Doctor ===${RESET}\n"

# 1. Realtime & Nice Scheduling Limits
echo -e "${BOLD}[1] Checking Realtime & Nice Scheduling Limits...${RESET}"
rt_limit=$(ulimit -r)
nice_limit=$(ulimit -e)
if [ "$rt_limit" -ge 75 ] 2>/dev/null; then
    echo -e "  ${GREEN}✓ Realtime priority limit (ulimit -r):${RESET} $rt_limit (>= 75, OK)"
else
    echo -e "  ${YELLOW}⚠ Realtime limit is $rt_limit.${RESET} Consider adding user to 'realtime' or 'audio' group in /etc/security/limits.d/"
fi
if [ "$nice_limit" -ge 30 ] 2>/dev/null; then
    echo -e "  ${GREEN}✓ Nice priority limit (ulimit -e):${RESET} $nice_limit (Allows Nice <= -10, OK)"
else
    echo -e "  ${YELLOW}ℹ Nice limit is $nice_limit.${RESET} Negative renice (-11) may require limits.conf configuration."
fi

# 2. PipeWire & WirePlumber Status
echo -e "\n${BOLD}[2] Checking PipeWire Graph Status...${RESET}"
if command -v pw-metadata >/dev/null 2>&1; then
    rate=$(pw-metadata -n settings 2>/dev/null | grep 'clock.force-rate' | grep -oP "value:'\K[^']+")
    fquant=$(pw-metadata -n settings 2>/dev/null | grep 'clock.force-quantum' | grep -oP "value:'\K[^']+")
    quantum=$(pw-metadata -n settings 2>/dev/null | grep 'clock.quantum' | head -1 | grep -oP "value:'\K[^']+")
    echo -e "  ${GREEN}✓ PipeWire settings active:${RESET} force-rate=${rate:-0 (auto)}, force-quantum=${fquant:-0 (auto)}, default-quantum=${quantum:-1024}"
else
    echo -e "  ${RED}✗ pw-metadata not found.${RESET}"
fi

# 3. CPU Governor & Kernel Scheduler (sched_ext / BORE)
echo -e "\n${BOLD}[3] Checking CPU Power Mode & Kernel Scheduler...${RESET}"
if command -v powerprofilesctl >/dev/null 2>&1; then
    profile=$(powerprofilesctl get 2>/dev/null)
    if [ "$profile" = "performance" ]; then
        echo -e "  ${GREEN}✓ CPU Profile:${RESET} performance (C-state latency minimized)"
    else
        echo -e "  ${YELLOW}ℹ CPU Profile:${RESET} $profile (Wrapper switches to 'performance' while gaming)"
    fi
elif [ -f /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference ]; then
    epp=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference)
    echo -e "  CPU EPP: $epp"
fi

if [ -f /sys/kernel/sched_ext/state ] && [ "$(cat /sys/kernel/sched_ext/state 2>/dev/null)" = "enabled" ]; then
    scx_ops=$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null)
    echo -e "  ${GREEN}✓ sched-ext scheduler:${RESET} ${scx_ops:-enabled} (Active)"
else
    echo -e "  ${BLUE}ℹ Kernel scheduler:${RESET} Standard CFS / BORE (sched-ext not enabled)"
fi

# 4. ALSA Hardware Ring Buffer Delay
echo -e "\n${BOLD}[4] Inspecting ALSA Hardware Ring Buffer Delay...${RESET}"
found_card=0
for status_file in /proc/asound/card*/pcm*p/sub*/status; do
    if [ -f "$status_file" ]; then
        state=$(grep '^state:' "$status_file" | awk '{print $2}')
        if [ "$state" = "RUNNING" ]; then
            card_dir=$(dirname "$status_file")
            delay=$(grep '^delay' "$status_file" | awk '{print $3}')
            appl_ptr=$(grep '^appl_ptr' "$status_file" | awk '{print $3}')
            hw_ptr=$(grep '^hw_ptr' "$status_file" | awk '{print $3}')
            rate=$(grep '^rate:' "$card_dir/hw_params" 2>/dev/null | awk '{print $2}' | cut -d'(' -f1)
            period=$(grep '^period_size:' "$card_dir/hw_params" 2>/dev/null | awk '{print $2}')
            buf_size=$(grep '^buffer_size:' "$card_dir/hw_params" 2>/dev/null | awk '{print $2}')
            
            if [ -n "$delay" ] && [ -n "$rate" ] && [ "$rate" -gt 0 ] 2>/dev/null; then
                delay_ms=$(awk "BEGIN {printf \"%.2f\", $delay / ($rate / 1000)}")
                ring_fill=$((appl_ptr - hw_ptr))
                found_card=1
                echo -e "  ${BLUE}Device:${RESET} $card_dir"
                echo -e "  Rate: ${rate}Hz | Period Size: ${period} samples | Buffer Size: ${buf_size} samples | Ring Fill (appl-hw): ${ring_fill} samples"
                if (( $(awk "BEGIN {print ($delay_ms <= 6.5)}") )); then
                    echo -e "  ${GREEN}✓ Hardware Delay:${RESET} ${delay} samples (~${delay_ms}ms) [ULTRA-LOW LATENCY: period=32 + disable-batch=true]"
                elif (( $(awk "BEGIN {print ($delay_ms <= 15.0)}") )); then
                    echo -e "  ${GREEN}✓ Hardware Delay:${RESET} ${delay} samples (~${delay_ms}ms) [LOW-LATENCY LOCKED]"
                else
                    echo -e "  ${YELLOW}⚠ Hardware Delay:${RESET} ${delay} samples (~${delay_ms}ms) [HIGH HARDWARE BUFFER BLOAT]"
                    echo -e "    ${YELLOW}Hint: Apply wireplumber/51-osu-low-latency.conf (period-size=32, headroom=32, disable-batch=true).${RESET}"
                fi
            fi
        fi
    fi
done

if [ "$found_card" -eq 0 ]; then
    echo -e "  ${YELLOW}ℹ No active ALSA playback stream currently playing audio.${RESET}"
fi

# 5. USB xHCI Controller Topology Check
echo -e "\n${BOLD}[5] Checking USB Audio vs. High-Polling Input Topology...${RESET}"
for dev in /sys/bus/usb/devices/*; do
    if [ -f "$dev/product" ]; then
        prod=$(cat "$dev/product" 2>/dev/null)
        busnum=$(cat "$dev/busnum" 2>/dev/null)
        if [ -n "$busnum" ]; then
            pci_path=$(readlink -f "$dev" | grep -oP '0000:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]' | tail -1)
            echo -e "  Bus $(printf '%03d' "$busnum") (PCI ${pci_path:-unknown}): ${prod}"
        fi
    fi
done

# 6. osu! Process & Thread Priority Check
echo -e "\n${BOLD}[6] Checking osu! Process & Thread Scheduling...${RESET}"
osu_pid=$(pgrep -x 'osu!' | head -1)
if [ -n "$osu_pid" ]; then
    osu_nice=$(ps -o ni= -p "$osu_pid" | tr -d ' ')
    echo -e "  ${GREEN}✓ osu! is running (PID: $osu_pid, Nice: $osu_nice)${RESET}"
    echo -e "  Thread priorities:"
    ps -L -o tid,cls,rtprio,ni,comm -p "$osu_pid" | while read -r tid cls prio ni comm; do
        case "$comm" in
            Audio*|alsa-pipewire)
                if [ "$cls" = "FF" ] && [ "$prio" -ge 70 ] 2>/dev/null; then
                    echo -e "    ${GREEN}✓ TID $tid ($comm):${RESET} $cls $prio (Realtime)"
                elif [ "$comm" = "Audio" ] && [ "$cls" = "TS" ]; then
                    echo -e "    ${GREEN}✓ TID $tid ($comm GameThread):${RESET} $cls Nice $ni (Managed .NET - safe from GC deadlock)"
                else
                    echo -e "    ${YELLOW}⚠ TID $tid ($comm):${RESET} $cls $prio (Normal - run wrapper for RT boost)"
                fi
                ;;
            Update*)
                if [ "$cls" = "TS" ] || [ "$cls" = "B" ]; then
                    echo -e "    ${GREEN}✓ TID $tid ($comm):${RESET} $cls Nice $ni (Managed .NET - safe from GC deadlock)"
                else
                    echo -e "    ${RED}✗ TID $tid ($comm):${RESET} $cls $prio (WARNING: Managed thread in RT causes GC crash!)"
                fi
                ;;
        esac
    done
else
    echo -e "  ${YELLOW}ℹ osu! is not running currently.${RESET}"
fi

# 7. pw-top Snapshot
echo -e "\n${BOLD}[7] PipeWire Active Stream Snapshot (pw-top):${RESET}"
if command -v pw-top >/dev/null 2>&1; then
    pw-top -b -n 2 2>&1 | tail -15 | grep -E 'QUANT|osu|Scarlett|vesktop|vencord|alsa_output' || pw-top -b -n 2 2>&1 | tail -10
fi

echo -e "\n${BOLD}${BLUE}=== Inspection Complete ===${RESET}\n"
