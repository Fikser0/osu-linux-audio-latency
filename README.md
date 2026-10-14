# osu! Linux Low Latency Audio & Input Guide

[![Linux](https://img.shields.io/badge/Platform-Linux-blue?logo=linux)](https://kernel.org)
[![PipeWire](https://img.shields.io/badge/Audio-PipeWire%201.0%2B-red)](https://pipewire.org)
[![WirePlumber](https://img.shields.io/badge/Session-WirePlumber%200.5%2B-green)](https://pipewire.pages.freedesktop.org/wireplumber/)
[![Hyprland](https://img.shields.io/badge/Compositor-Hyprland%20%28Wayland%29-cyan?logo=hyprland)](https://hyprland.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

The complete, battle-tested guide to achieving ultra-low, jitter-free audio and display latency for **osu!lazer** (and rhythm games) on modern Linux.

---

## Benchmarks & Verified Results

Tested under active high-BPM gameplay with simultaneous Discord voice call and screen sharing:

| Metric | Stock / Untuned Linux | With This Setup | Improvement |
|---|---|---|---|
| **PipeWire DSP Quantum** | 1024 frames (~23.2ms) | **32 frames (0.725ms)** | **-22.5ms** |
| **ALSA Hardware Ring Buffer** | ~1150 samples (~26.5ms) | **~480 samples (~10.8ms)** | **-15.7ms physical cut** |
| **Startup Sequence Jitter** | ±25.0ms (Discord vs osu! first) | **0.0ms (Locked buffer)** | **Eliminates offset drift** |
| **Active Playback Xruns (ERR)** | 5 – 15 underruns / song | **0 underruns across 10 min** | **Zero audio drops** |
| **Game Audio Threads** | Regular `SCHED_OTHER` (Priority 0) | **Realtime `SCHED_FIFO 75`** | **Immune to CPU preemption** |
| **Wayland Display Presentation** | Mailbox / Double-buffered VSync | **Direct Hardware Tearing** | **Bypasses compositor lag** |

---

## Verified Benchmark Testbed

- **CPU:** AMD Ryzen 7 7700 (Zen 4, 8C/16T @ 5.3 GHz boost)
- **GPU:** AMD Radeon RX 9070 XT
- **Memory:** 32GB DDR5
- **Audio Interface:** Focusrite Scarlett Solo (4th Gen, USB 2.0 Audio)
- **Microphone:** Fifine USB Condenser Microphone
- **Monitor:** 2560x1440 @ 180Hz (DisplayPort 1.4)
- **OS & Kernel:** Arch Linux (`linux-cachyos` with BORE scheduler)
- **Compositor:** Hyprland (Wayland)

---

## Audio Interfaces vs. Motherboard (Onboard) Audio

| Factor | Dedicated USB DAC (Scarlett, Motu, Topping) | Motherboard Audio (Realtek ALC, Intel HDA) |
|---|---|---|
| **Driver** | `snd_usb_audio` | `snd_hda_intel` |
| **Profile Trap** | Often defaults to "Pro Audio" (locks quantum in IRQ mode). | Usually defaults to "Analog Stereo" (already timer-based). |
| **Transport Latency** | ~8ms USB Request Block (URB) controller FIFO. | PCIe direct memory access (DMA), slightly lower bus delay. |
| **Clock Stability** | Independent hardware crystal; vulnerable to USB mic clock inversion. | Motherboard bus clock; also vulnerable to USB mic clock inversion. |
| **WirePlumber Rule** | Match `~alsa_output.usb-.*` | Match `~alsa_output.pci-.*` |

---

## Quick Start (3 Steps)

### Step 1: Install the WirePlumber Rule
This rule fixes the Pro Audio fixed-quantum bug, prevents USB microphones from stealing the master clock, and locks the ALSA hardware ring buffer to ~2ms.

Copy [`wireplumber/51-osu-low-latency.conf`](wireplumber/51-osu-low-latency.conf) into your user config:
```bash
mkdir -p ~/.config/wireplumber/wireplumber.conf.d/
cp wireplumber/51-osu-low-latency.conf ~/.config/wireplumber/wireplumber.conf.d/
systemctl --user restart wireplumber
```

### Step 2: Install the Launch Wrapper
The wrapper script manages CPU power profiles, locks the PipeWire graph rate to 44.1kHz, and boosts native audio threads to Realtime priority (`SCHED_FIFO 75`).

Copy [`scripts/osu-lazer-wrapper.sh`](scripts/osu-lazer-wrapper.sh) to your local bin:
```bash
mkdir -p ~/.local/bin/
cp scripts/osu-lazer-wrapper.sh ~/.local/bin/osu-lazer-wrapper
chmod +x ~/.local/bin/osu-lazer-wrapper
```
Set your desktop launcher, Steam, or Lutris command to launch via `/home/$USER/.local/bin/osu-lazer-wrapper`.

### Step 3: Verify Your Setup
Run the included doctor script to audit your realtime limits, hardware buffer delay, and active thread priorities:
```bash
./scripts/audio-latency-doctor.sh
```

---

## Wayland & Hyprland Zero-Lag Display Rules

To achieve minimum display input lag under Wayland, enable tearing presentation (`wp_tearing_control_v1`) to bypass compositor double-buffering.

### Standard Hyprland (`~/.config/hypr/hyprland.conf`)
```ini
general {
    allow_tearing = true
}

# Bypass compositor presentation delay for osu!
windowrulev2 = immediate, class:^(osu!)$
windowrulev2 = immediate, class:^(sh\.ppy\.osu)$ # Flatpak
windowrulev2 = immediate, class:^(osu-lazer)$

# Raw mouse input
input {
    accel_profile = flat
    force_no_accel = true
}

# Optional: Disable VRR to prevent frame pacing stutter during tearing
misc {
    vrr = 0
}
```

*(For Lua / Caelestia rice users, see [`hyprland/osu-tearing.lua`](hyprland/osu-tearing.lua)).*

---

## Deep-Dive: The 4 Hidden Linux Traps

For an in-depth breakdown of the audio signal chain and timing analysis, see **[`doc/ARCHITECTURE.md`](doc/ARCHITECTURE.md)**.

### 1. The Pro Audio Fixed Quantum Trap
WirePlumber's "Pro Audio" profile defaults to `api.alsa.disable-tsched = true` (IRQ mode). The hardware period locks to whatever app opens the card first. If Discord opens it at 1024, osu! cannot request 32 or 64 without crackling. Overriding `disable-tsched = false` enables dynamic quantums.

### 2. Hardware Ring Buffer Bloat
`PIPEWIRE_LATENCY="32/44100"` only changes the PipeWire software slice (~0.7ms). If ALSA's hardware ring buffer initialized with large period and headroom from an earlier app, **26ms of physical delay remains hidden in the kernel buffer** (`/proc/asound/.../status`). Locking `period-size = 64` and `headroom = 32` permanently eliminates this.

### 3. Realtime Scheduling: The .NET GC Deadlock Trap
> [!CAUTION]
> **NEVER boost managed .NET CLR threads (`Update`, `Draw`, or managed `Audio (GameThread)`) to `SCHED_FIFO`!**  
> In .NET 10 (used by osu!lazer), Garbage Collection uses Stop-The-World safepoints. A managed thread running in `SCHED_FIFO 75` starves background GC worker threads (`SCHED_OTHER 0`), causing an unrecoverable priority-inversion deadlock and silent crash.  
> **Only boost native C/BASS audio threads:** Match `Audio*:RR|alsa-pipewire:*` (BASS spawns its native thread with `RR`, while managed threads start with `TS`).

### 4. Recalibrating In-Game Offset
After eliminating ~16ms of physical hardware delay, any previous large negative offset in `~/.local/share/osu/game.ini` (e.g. `AudioOffset = -30.0`) will cause your hits to register ~16ms early. Run the in-game Offset Wizard to set a clean baseline.

---

## Repository Structure

```
osu-linux-audio-latency/
├── README.md                      # Complete guide & documentation
├── LICENSE                        # MIT License
├── wireplumber/
│   └── 51-osu-low-latency.conf    # WirePlumber rule (USB & PCI DACs)
├── hyprland/
│   ├── osu-tearing.conf           # Standard Hyprland tearing & raw input rules
│   └── osu-tearing.lua            # Lua/Caelestia Hyprland config snippet
├── scripts/
│   ├── osu-lazer-wrapper.sh       # Production launch wrapper
│   └── audio-latency-doctor.sh    # One-click diagnostic doctor tool
└── doc/
    └── ARCHITECTURE.md            # Deep-dive signal chain & timing analysis
```

---

## Contributing & Issues
Feel free to open an issue or pull request with your hardware specs, distribution notes, or compositor configurations!
