# osu! Linux Low-Latency Audio & Input Guide

[![Linux](https://img.shields.io/badge/Platform-Linux-blue?logo=linux)](https://kernel.org)
[![PipeWire](https://img.shields.io/badge/Audio-PipeWire%201.0%2B-red)](https://pipewire.org)
[![WirePlumber](https://img.shields.io/badge/Session-WirePlumber%200.5%2B-green)](https://pipewire.pages.freedesktop.org/wireplumber/)
[![Hyprland](https://img.shields.io/badge/Compositor-Hyprland%20%28Wayland%29-cyan?logo=hyprland)](https://hyprland.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Drop your **osu!lazer** audio latency on Linux from **~27ms down to ~5.1ms** while keeping Discord, browsers, and system audio working simultaneously without crackling or offset drift.

---

## What Problems Does This Solve?

1. **Delayed hitsounds (~25–30ms stock delay):** Shrinks BASS, PipeWire, and ALSA hardware ring buffers down to **32 samples (~5.12ms physical DAC delay)**.
2. **Audio crackling when Discord/Browser is opened first:** Fixes WirePlumber's "Pro Audio" IRQ lock so background apps never break osu! audio.
3. **Inconsistent offset between restarts:** Locks the hardware ring buffer so your in-game universal offset stays identical every boot.
4. **Random freezes / crashes with `chrt` or GameMode:** Safely boosts only native C/BASS audio threads to `SCHED_FIFO` while keeping `.NET` managed threads in `SCHED_OTHER` (`Nice -11`), avoiding the `.NET` Garbage Collector priority-inversion deadlock.

---

## Quick Install (2 Minutes)

### 1. Prerequisites
Make sure `pipewire-alsa` and `wireplumber` are installed:
- **Arch / CachyOS:** `sudo pacman -S pipewire-alsa wireplumber`
- **Fedora:** `sudo dnf install pipewire-alsa wireplumber`
- **Ubuntu / Debian:** `sudo apt install pipewire-alsa wireplumber`

### 2. Clone & Install Configs
Run these commands in your terminal:
```bash
git clone https://github.com/Fikser0/osu-linux-audio-latency.git
cd osu-linux-audio-latency

# 1. Install WirePlumber low-latency rule (supports both USB DACs and motherboard audio)
mkdir -p ~/.config/wireplumber/wireplumber.conf.d/
cp wireplumber/51-osu-low-latency.conf ~/.config/wireplumber/wireplumber.conf.d/
systemctl --user restart wireplumber

# 2. Install the osu!lazer launch wrapper
mkdir -p ~/.local/bin/
cp scripts/osu-lazer-wrapper.sh ~/.local/bin/osu-lazer-wrapper
chmod +x ~/.local/bin/osu-lazer-wrapper
```

### 3. Launch osu!lazer
Run `~/.local/bin/osu-lazer-wrapper` (or set it as the launch command in your `.desktop` shortcut / Steam / Lutris).

The wrapper automatically detects:
- System package (`osu-lazer` in `$PATH`)
- AppImage (`~/.local/bin/osu.AppImage` or custom `OSU_BIN=/path/to/osu.AppImage ~/.local/bin/osu-lazer-wrapper`)
- Flatpak (`sh.ppy.osu`)

### 4. In-Game Settings & Offset Calibration
1. **Audio Device:** Leave on **`Default`** (or **`PipeWire Sound Server`**) so Discord and desktop apps can play sound at the same time. *(Raw ALSA hardware devices are also supported via `OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD=-32`).*
2. **Audio Offset:** Because physical hardware delay is reduced by **~22ms**, open the in-game **Offset Wizard** (or adjust your universal offset by roughly `+15ms` to `+22ms` compared to untuned Linux).
3. **Verify Everything Works:** While osu! is running with a map playing, run the included diagnostic tool:
   ```bash
   ./scripts/audio-latency-doctor.sh
   ```

---

## Benchmarks: Before vs. After

Measured during active high-BPM gameplay with a simultaneous Discord voice call and screen share:

| Metric | Stock Linux (Default PipeWire) | With This Setup | Improvement |
|---|---|---|---|
| **PipeWire Graph Quantum** | 1024 frames (~23.2ms) | **32 frames (0.725ms)** | **-22.5ms** |
| **ALSA Hardware Delay (`delay`)** | ~1220 samples (~27.6ms) | **~226 samples (~5.12ms)** | **-22.5ms physical cut** |
| **Active Ring Fill (`appl - hw`)** | 512 – 1024 samples (~11.6 – 23.2ms) | **27 – 32 samples (~0.61ms)** | **1:1 quantum lock** |
| **Startup Order Drift** | ±25.0ms (depends on what app opened first) | **0.0ms (Locked)** | **Zero offset drift** |
| **Audio Underruns (Xruns)** | 5 – 15 drops / song | **0 underruns** | **Crackling eliminated** |

---

## Troubleshooting & Tuning for Your Hardware

### Audio crackles or pops at 32 samples on older CPUs / laptops
`32` frames (`0.725ms` quantum) is aggressive. If your CPU or USB controller crackles under load, step up to **`64` frames (`1.45ms`)**—this adds only `~0.7ms` of latency while doubling stability:
1. In `~/.config/wireplumber/wireplumber.conf.d/51-osu-low-latency.conf`, change `api.alsa.period-size = 32` to `64`.
2. Restart WirePlumber: `systemctl --user restart wireplumber`.
3. Launch the wrapper with 64-sample overrides:
   ```bash
   OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD=-64 \
   PIPEWIRE_LATENCY="64/44100" \
   PIPEWIRE_ALSA='{ alsa.format=S32_LE alsa.channels=2 alsa.buffer-bytes=1024 alsa.period-bytes=512 }' \
   ~/.local/bin/osu-lazer-wrapper
   ```

### Game volume drops to 30% when joining a Discord voice call
WirePlumber 0.5+ enables role-based volume ducking by default when a `Communication` stream (Discord/Vesktop) is active. Disable it permanently:
```bash
cat << 'EOF' > ~/.config/wireplumber/wireplumber.conf.d/52-disable-ducking.conf
wireplumber.settings = {
  linking.role-based.duck-level = 1.0
}
EOF
wpctl settings linking.role-based.duck-level 1.0
```

### `audio-latency-doctor.sh` warns about Realtime or Nice limits
Ensure your user has realtime and negative-nice permissions (or install `realtime-privileges` on Arch):
```bash
sudo tee /etc/security/limits.d/99-realtime.conf >/dev/null <<EOF
$USER - rtprio 98
$USER - nice -15
$USER - memlock unlimited
EOF
```
*(Log out and log back in for `limits.d` changes to apply).*

---

## Optional Display & Input Optimizations

### Wayland / Hyprland Zero-Lag Display Rules
Enable tearing (`wp_tearing_control_v1`) and direct scanout in `~/.config/hypr/hyprland.conf` to bypass compositor buffering:
```ini
general {
    allow_tearing = true
}

render {
    direct_scanout = true
}

# Bypass compositor presentation delay for osu!
windowrulev2 = immediate, class:^(osu!)$
windowrulev2 = immediate, class:^(sh\.ppy\.osu)$ # Flatpak

# Raw 1:1 mouse input
input {
    accel_profile = flat
    sensitivity = 0.0
}

misc {
    vrr = 0
}
```
*(Note: Keep your monitor in 8-bit SDR mode `XRGB8888` rather than `bitdepth, 10` on Hyprland so `osu!lazer` can enter `direct_scanout` without triggering a 1-second black screen KMS modeset. For Caelestia Lua configs, see [`hyprland/osu-tearing.lua`](hyprland/osu-tearing.lua)).*

### Isolate Your USB DAC from 8000Hz Keypads
An 8000Hz keypad (SayoDevice O3C, Wooting) generates **8,000 USB interrupts/sec**. If your USB DAC shares the same motherboard xHCI controller (`Bus`), audio packets compete with keypad interrupts.
- Plug your **USB Audio Interface** into a **CPU-direct USB port**.
- Plug your **8000Hz keypad, tablet, mouse, and USB mic** into **chipset USB ports**.
- Run `./scripts/audio-latency-doctor.sh` (Section 5) to verify your DAC is on its own `Bus`.

### Kernel Scheduler (`scx_lavd`) & OpenTabletDriver Priority
- **CachyOS / `sched_ext`:** Set `default_sched = "scx_lavd"` in `/etc/scx_loader.toml`.
- **OpenTabletDriver:** Give `opentabletdriver.service` `Nice=-11` so 1000Hz tablet packets are never preempted:
  ```bash
  mkdir -p ~/.config/systemd/user/opentabletdriver.service.d
  printf "[Service]\nNice=-11\n" > ~/.config/systemd/user/opentabletdriver.service.d/override.conf
  systemctl --user daemon-reload && systemctl --user restart opentabletdriver.service
  ```

---

## Technical Overview: Why Each Setting Matters

For the full signal chain diagram and math, read **[`doc/ARCHITECTURE.md`](doc/ARCHITECTURE.md)**.

<details>
<summary><b>Click to expand the 7 Linux Audio & Input Traps</b></summary>

1. **BASS Internal Device Period (`OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD=-32`):** Introduced in [`ppy/osu-framework#6724`](https://github.com/ppy/osu-framework/pull/6724), this sets `BASS_CONFIG_DEV_PERIOD = -32` samples and `BASS_CONFIG_DEV_BUFFER = 1` (rounded by BASS to `2 × period = 64` samples), shrinking BASS's device buffer in both PipeWire and Raw ALSA modes.
2. **The Pro Audio Fixed Quantum Trap (`api.alsa.disable-tsched = false`):** WirePlumber's "Pro Audio" profile defaults to IRQ mode (`disable-tsched = true`), locking the hardware buffer to the first app that opens the device (e.g. 1024 if Discord opens first). Timer-based scheduling unlocks dynamic quantums.
3. **Hardware Ring Buffer Bloat (`period-size = 32`, `headroom = 32`):** `PIPEWIRE_LATENCY="32/44100"` only shrinks the software DSP slice (0.72ms). Without locking ALSA period and headroom in WirePlumber, the kernel ring buffer retains ~27ms of hidden delay.
4. **The `snd_usb_audio` `BATCH` Flag (`api.alsa.disable-batch = true`):** The Linux USB audio driver sets `SNDRV_PCM_INFO_BATCH` on USB DACs, causing PipeWire to silently double ALSA `headroom`. Disabling it cuts USB ALSA delay from ~10.9ms to **~5.12ms** (226 samples).
5. **The `pipewire-alsa` Frame Math Trap (`period-bytes=256`, `buffer-bytes=512`):** For `S32_LE` stereo (8 bytes/frame), `period-bytes=64` is only 8 frames—smaller than the 32-frame PipeWire quantum, triggering an internal `min-avail: 58` override in `pipewire-alsa`. `256` bytes equals exactly 32 frames (1:1 with quantum 32).
6. **Clock Master Inversion (`priority.driver = 3000` vs `1000`):** Prevents USB microphones or your DAC's capture channel from stealing the PipeWire graph master clock and forcing adaptive resampling.
7. **The `.NET` GC Realtime Deadlock Trap:**
   > **NEVER boost managed `.NET` threads (`Update`, `Draw`, `Audio (GameThread):TS`, or `otd-daemon`) to `SCHED_FIFO`!**  
   > `.NET` Garbage Collection uses Stop-The-World safepoints. A managed thread in `SCHED_FIFO` starves `SCHED_OTHER` GC threads, causing an unrecoverable deadlock and silent crash. Only boost native C/BASS audio threads (`Audio*:RR|alsa-pipewire:*`) to `SCHED_FIFO`, and use `renice -n -11` (`SCHED_OTHER`) for the process.

</details>

---

## Reference Testbed

- **CPU / GPU:** AMD Ryzen 7 7700 + Radeon RX 9070 XT
- **Audio / Mic:** Focusrite Scarlett Solo 4th Gen (USB 2.0) + Fifine USB Mic
- **Input:** SayoDevice O3C (8000Hz) + Wacom CTL-480 (1000Hz `shavit` firmware, OpenTabletDriver `Nice -11`)
- **OS / Desktop:** Arch Linux (`linux-cachyos`, `scx_lavd`), Hyprland (2560x1440 @ 180Hz, 8-bit Direct Scanout + Tearing)

---

## Repository Structure

```text
osu-linux-audio-latency/
├── README.md                      # User guide & quick-start instructions
├── wireplumber/
│   └── 51-osu-low-latency.conf    # WirePlumber low-latency rule (USB & motherboard audio)
├── hyprland/
│   ├── osu-tearing.conf           # Standard Hyprland tearing & raw input config
│   └── osu-tearing.lua            # Lua/Caelestia Hyprland config snippet
├── scripts/
│   ├── osu-lazer-wrapper.sh       # Auto-detecting launch wrapper
│   └── audio-latency-doctor.sh    # Live diagnostic & latency measurement tool
└── doc/
    └── ARCHITECTURE.md            # Technical signal-chain & timing analysis
```
