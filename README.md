# osu! Linux Low Latency Audio & Input Guide

[![Linux](https://img.shields.io/badge/Platform-Linux-blue?logo=linux)](https://kernel.org)
[![PipeWire](https://img.shields.io/badge/Audio-PipeWire%201.0%2B-red)](https://pipewire.org)
[![WirePlumber](https://img.shields.io/badge/Session-WirePlumber%200.5%2B-green)](https://pipewire.pages.freedesktop.org/wireplumber/)
[![Hyprland](https://img.shields.io/badge/Compositor-Hyprland%20%28Wayland%29-cyan?logo=hyprland)](https://hyprland.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

The complete, battle-tested guide to achieving ultra-low, jitter-free audio, input, and display latency for **osu!lazer** (and rhythm games) on modern Linux.

---

## Benchmarks & Verified Results

Tested under active high-BPM gameplay with simultaneous Discord voice call and screen sharing:

| Metric | Stock / Untuned Linux | With This Setup | Improvement |
|---|---|---|---|
| **PipeWire DSP Quantum** | 1024 frames (~23.2ms) | **32 frames (0.725ms)** | **-22.5ms** |
| **ALSA Hardware Ring Buffer (`delay`)** | ~1220 samples (~27.6ms) | **~226 samples (~5.12ms)** | **-22.5ms physical cut** |
| **ALSA Active Ring Fill (`appl - hw`)** | 512 – 1024 samples (~11.6 – 23.2ms) | **27 – 32 samples (~0.61ms)** | **1:1 quantum lock** |
| **Startup Sequence Jitter** | ±25.0ms (Discord vs osu! first) | **0.0ms (Locked buffer)** | **Eliminates offset drift** |
| **Active Playback Xruns (ERR)** | 5 – 15 underruns / song | **0 underruns across 10 min** | **Zero audio drops** |
| **Game & Input Scheduling** | Regular `SCHED_OTHER` (Priority 0) | **`SCHED_FIFO 75` (Audio) + `Nice -11` / `scx_lavd`** | **Immune to CPU preemption** |
| **Wayland Display & GPU P-State** | Mailbox VSync + Dynamic GPU Downclock | **Direct Tearing + AMD `VR` Profile** | **Zero compositor/clock lag** |

---

## Verified Benchmark Testbed

- **CPU:** AMD Ryzen 7 7700 (Zen 4, 8C/16T @ 5.3 GHz boost)
- **GPU:** AMD Radeon RX 9070 XT (`pp_power_profile_mode = 4` VR Low-Latency)
- **Memory:** 32GB DDR5
- **Audio Interface:** Focusrite Scarlett Solo (4th Gen, USB 2.0 Audio — isolated on CPU-direct xHCI root hub)
- **Microphone:** Fifine USB Condenser Microphone
- **Keypad & Tablet:** SayoDevice O3C (8000 Hz USB High-Speed) + Wacom CTL-480 (1000 Hz `shavit` firmware, OpenTabletDriver `Nice -11`)
- **Monitor:** 2560x1440 @ 180Hz (DisplayPort)
- **OS, Kernel & Scheduler:** Arch Linux (`linux-cachyos`, `scx_lavd` Latency-critical Virtual Deadline / BORE)
- **Compositor:** Hyprland (Wayland)

---

## Audio Interfaces vs. Motherboard (Onboard) Audio

| Factor | Dedicated USB DAC (Scarlett, Motu, Topping) | Motherboard Audio (Realtek ALC, Intel HDA) |
|---|---|---|
| **Driver** | `snd_usb_audio` | `snd_hda_intel` |
| **Profile Trap** | Often defaults to "Pro Audio" (locks quantum in IRQ mode) and sets `BATCH` flag (doubles headroom). | Usually defaults to "Analog Stereo" (already timer-based). |
| **Transport Latency** | ~3.5ms – 4.5ms USB Request Block (URB) controller FIFO when `disable-batch = true` & `period-size = 32`. | PCIe direct memory access (DMA), ~1.5ms – 2.5ms bus delay. |
| **USB Bus Contention** | Vulnerable to xHCI IRQ jitter if sharing a USB controller with an 8000Hz keypad. | On PCIe bus; unaffected by USB keypad polling. |
| **WirePlumber Rule** | Match `~alsa_output.usb-.*` | Match `~alsa_output.pci-.*` |

---

## Quick Start (3 Steps)

### Step 1: Install the WirePlumber Rule
This rule fixes the Pro Audio fixed-quantum bug, disables the USB `BATCH` headroom multiplier, prevents USB microphones (or your DAC's input channel) from stealing the master clock, and locks the ALSA hardware period to 32 frames (~5.12ms total physical delay).

Copy [`wireplumber/51-osu-low-latency.conf`](wireplumber/51-osu-low-latency.conf) into your user config:
```bash
mkdir -p ~/.config/wireplumber/wireplumber.conf.d/
cp wireplumber/51-osu-low-latency.conf ~/.config/wireplumber/wireplumber.conf.d/
systemctl --user restart wireplumber
```

### Step 2: Install the Launch Wrapper
The wrapper script locks the PipeWire graph to `44100 Hz` and `32` quantum, switches the CPU to `performance` (and optionally AMD GPU to `VR` low-latency mode), boosts the `osu!` process to `Nice -11`, and promotes native audio threads to Realtime priority (`SCHED_FIFO 75`).

Copy [`scripts/osu-lazer-wrapper.sh`](scripts/osu-lazer-wrapper.sh) to your local bin:
```bash
mkdir -p ~/.local/bin/
cp scripts/osu-lazer-wrapper.sh ~/.local/bin/osu-lazer-wrapper
chmod +x ~/.local/bin/osu-lazer-wrapper
```
Set your desktop launcher, Steam, or Lutris command to launch via `/home/$USER/.local/bin/osu-lazer-wrapper`.

### Step 3: Verify Your Setup
Run the included doctor script to audit your realtime/nice limits, PipeWire quantum, kernel scheduler, USB xHCI bus topology, hardware buffer delay, and active thread priorities:
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

# Raw 1:1 mouse input (avoid deprecated force_no_accel = true to prevent XWayland cursor desync)
input {
    accel_profile = flat
    sensitivity = 0.0
}

# Disable VRR to prevent frame pacing stutter during tearing
misc {
    vrr = 0
}
```

*(For Lua / Caelestia rice users, see [`hyprland/osu-tearing.lua`](hyprland/osu-tearing.lua)).*

---

## System & Hardware Optimizations (Optional but Recommended)

### 1. Isolate Your USB DAC from 8000Hz Keypads (USB xHCI Topology)
An 8000Hz keypad (e.g., SayoDevice O3C, Wooting 60HE/80HE) generates **8,000 USB microframe interrupts per second**, plus 1,000 interrupts/s from a 1000Hz tablet. If your USB Audio Interface shares the same motherboard xHCI controller (`Bus`), Isochronous audio URBs compete with HID interrupt transfers on the same kernel IRQ line.
- Plug your **USB Audio Interface** into a **CPU-direct USB port** (dedicated xHCI controller on the CPU's PCIe root complex).
- Plug your **8000Hz keypad, 1000Hz tablet,mouse, and USB mic** into **chipset USB ports**.
- Run `./scripts/audio-latency-doctor.sh` (Section 5) to verify that your DAC is on its own PCI xHCI address.

### 2. Kernel Scheduler (`scx_lavd`) & OpenTabletDriver Priority
On `linux-cachyos` or kernels with `sched_ext`:
- Enable **`scx_lavd`** (Latency-critical Virtual Deadline scheduler) in `/etc/scx_loader.toml`:
  ```toml
  default_sched = "scx_lavd"
  ```
- Give `opentabletdriver.service` negative nice priority (`Nice=-11`) so 1000Hz tablet packets are never preempted:
  ```bash
  mkdir -p ~/.config/systemd/user/opentabletdriver.service.d
  printf "[Service]\nNice=-11\n" > ~/.config/systemd/user/opentabletdriver.service.d/override.conf
  systemctl --user daemon-reload && systemctl --user restart opentabletdriver.service
  ```

---

## Deep-Dive: The 7 Hidden Linux Traps

For a complete breakdown of the audio signal chain and timing math, see **[`doc/ARCHITECTURE.md`](doc/ARCHITECTURE.md)**.

1. **The Pro Audio Fixed Quantum Trap:** WirePlumber's "Pro Audio" profile defaults to `api.alsa.disable-tsched = true` (IRQ mode), locking the hardware buffer to the first app that opens the device (e.g., 1024 if Discord opens first). Setting `api.alsa.disable-tsched = false` unlocks dynamic timer-based scheduling.
2. **Hardware Ring Buffer Bloat:** `PIPEWIRE_LATENCY="32/44100"` only shrinks the software DSP slice (0.72ms). Without locking `api.alsa.period-size = 32` and `api.alsa.headroom = 32`, ALSA's kernel ring buffer retains ~27ms of hidden delay.
3. **The `snd_usb_audio` `BATCH` Flag Trap:** The Linux USB audio driver sets the `SNDRV_PCM_INFO_BATCH` flag on USB DACs, causing PipeWire to silently **double** the ALSA `headroom` and minimum period. Setting `api.alsa.disable-batch = true` cuts physical USB ALSA delay from ~10.9ms down to **~5.12ms** (226 samples).
4. **The `pipewire-alsa` `period-bytes` Frame Math Trap:** For `S32_LE` 2-channel audio (8 bytes/frame), setting `alsa.period-bytes=64` equals only 8 frames—smaller than the 32-frame PipeWire quantum. This triggers an internal `min-avail: 58` floor in `pipewire-alsa` that overrides `PIPEWIRE_LATENCY="32/44100"`. Setting `alsa.period-bytes=256` (32 frames) and `alsa.buffer-bytes=512` (64 frames) aligns 1:1 with quantum 32 (`appl_ptr - hw_ptr = 27` samples).
5. **Clock Master Inversion:** USB microphones (and your USB DAC's own capture node) can preempt your DAC output as the PipeWire graph clock driver, forcing adaptive resampling. Setting `priority.driver = 3000` on `alsa_output.usb-*` and `1000` on `alsa_input.usb-*` locks the DAC output crystal as master.
6. **Realtime Scheduling: The .NET GC Deadlock Trap:**
   > [!CAUTION]
   > **NEVER boost managed .NET CLR threads (`Update`, `Draw`, `Audio (GameThread):TS`, or `otd-daemon`) to `SCHED_FIFO`!**  
   > In .NET 10, Garbage Collection uses Stop-The-World safepoints. A managed thread running in `SCHED_FIFO 75` starves background GC worker threads (`SCHED_OTHER 0`), causing a priority-inversion deadlock and silent crash.  
   > **Safe Pattern:** Only boost native C/BASS audio threads (`Audio*:RR|alsa-pipewire:*`) to `SCHED_FIFO 75`, and use `renice -n -11` (`SCHED_OTHER`) for the `osu!` and `otd-daemon` processes.
7. **Recalibrating In-Game Offset:** After cutting ~22ms of physical hardware delay (down to ~5.1ms), recalibrate `AudioOffset` in `~/.local/share/osu/game.ini` via the in-game Offset Wizard.

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
│   └── audio-latency-doctor.sh    # Diagnostic doctor tool
└── doc/
    └── ARCHITECTURE.md            # Deep-dive signal chain & timing analysis
```

---

## Contributing & Issues
Feel free to open an issue or pull request with your hardware specs, distribution notes, or compositor configurations!
