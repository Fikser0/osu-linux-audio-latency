# osu! Linux Low-Latency Audio & Input Guide

[![Linux](https://img.shields.io/badge/Platform-Linux-blue?logo=linux)](https://kernel.org)
[![PipeWire](https://img.shields.io/badge/Audio-PipeWire%201.0%2B-red)](https://pipewire.org)
[![WirePlumber](https://img.shields.io/badge/Session-WirePlumber%200.5%2B-green)](https://pipewire.pages.freedesktop.org/wireplumber/)
[![Hyprland](https://img.shields.io/badge/Compositor-Hyprland%20%28Wayland%29-cyan?logo=hyprland)](https://hyprland.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Cut **osu!lazer** physical ALSA+USB audio delay on Linux from **~27ms down to ~5.1ms** (~6.5–7.3ms end-to-end) while keeping Discord, browsers, and desktop audio working at the same time—without crackling or offset drift.

---

## Why Use This?

- **Removes ~22ms of stock audio delay:** Locks BASS (`OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD=-32`), `pipewire-alsa`, PipeWire quantum (`32` frames), and ALSA hardware ring buffers (`period-size=32`, `headroom=32`, `disable-batch=true`).
- **Fixes Discord/Browser startup crackling:** Forces WirePlumber timer scheduling (`disable-tsched=false`) so background apps opened first don't lock the DAC to a huge buffer.
- **Zero offset drift between restarts:** Keeps the physical ALSA delay consistent every launch.
- **No `.NET` GC crashes:** Boosts *only* native audio threads (`Audio*:RR`, `alsa-pipewire`) to `SCHED_FIFO`, keeping `.NET` managed threads at `Nice -11` (`SCHED_OTHER`).

| Metric | Stock Linux (Default PipeWire) | With This Setup |
|---|---|---|
| **PipeWire Graph Quantum** | 1024 frames (~23.2ms) | **32 frames (0.725ms)** |
| **ALSA + USB Delay (`delay`)** | ~1220 samples (~27.6ms) | **~226 samples (~5.12ms)** |
| **Active Ring Fill (`appl - hw`)** | 512 – 1024 samples (~11.6 – 23.2ms) | **27 – 32 samples (~0.61 – 0.72ms)** |
| **Startup Order Offset Drift** | ±25.0ms | **0.0ms (Locked)** |
| **Audio Xruns (Underruns)** | 5 – 15 drops / song | **0 underruns** |

---

## Quick Setup

### 1. Install Prerequisites
Make sure `pipewire`, `pipewire-alsa`, and `wireplumber` are installed:
- **Arch / CachyOS:** `sudo pacman -S pipewire pipewire-alsa wireplumber`
- **Fedora:** `sudo dnf install pipewire pipewire-alsa wireplumber`
- **Ubuntu / Debian:** `sudo apt install pipewire pipewire-alsa wireplumber`

### 2. Install Configs & Wrapper
```bash
git clone https://github.com/Fikser0/osu-linux-audio-latency.git
cd osu-linux-audio-latency

# Allow 44.1kHz in PipeWire (stock PipeWire only allows 48kHz)
mkdir -p ~/.config/pipewire/pipewire.conf.d/
cp pipewire/10-rates.conf ~/.config/pipewire/pipewire.conf.d/

# Lock WirePlumber clock master & ALSA low-latency ring buffer
mkdir -p ~/.config/wireplumber/wireplumber.conf.d/
cp wireplumber/51-osu-low-latency.conf ~/.config/wireplumber/wireplumber.conf.d/

# Restart audio stack
systemctl --user restart pipewire pipewire-pulse wireplumber

# Install the osu!lazer launch wrapper
mkdir -p ~/.local/bin/
cp scripts/osu-lazer-wrapper.sh ~/.local/bin/osu-lazer-wrapper
chmod +x ~/.local/bin/osu-lazer-wrapper
```

### 3. Launch via the Wrapper
Run `~/.local/bin/osu-lazer-wrapper` (or set it as `Exec=` in your `.desktop` shortcut / Steam / Lutris).

Auto-detected targets (override with `OSU_BIN=/path/to/osu.AppImage`):
- System package (`osu-lazer` in `$PATH`)
- AppImage (`~/.local/bin/osu.AppImage`)
- Flatpak (`sh.ppy.osu`)

### 4. In-Game Settings & Verification
1. **Audio Device:** Set to **`PipeWire Sound Server`** (or **`Default`**) so Discord and desktop apps stay audible.
2. **Display & Threading:** Set **Screen Mode** to **`Fullscreen`**, **Frame Limiter** to **`Unlimited`**, and **Threading Mode** to **`MultiThreaded`**.
3. **Audio Offset:** Hardware delay drops by ~22ms, so recalibrate via the in-game **Offset Wizard** (note: switching to a faster display like a 360Hz OLED also shifts visual timing).
4. **Verify Live:** While **a map is playing in osu!**, run:
   ```bash
   ./scripts/audio-latency-doctor.sh
   ```
   *(Running the script while idle / osu! is closed reports `~27ms` because the wrapper resets `clock.force-quantum` to `0` on exit—this is expected).*

---

## Common Fixes & Troubleshooting

### Crackling or pops at `32` frames on weaker CPUs
`32` frames (`0.725ms`) is aggressive. Stepping up to **`64` frames (`1.45ms`)** adds only `~0.7ms` while doubling margin:
1. Change `api.alsa.period-size = 32` to `64` in `~/.config/wireplumber/wireplumber.conf.d/51-osu-low-latency.conf` and restart WirePlumber (`systemctl --user restart wireplumber`).
2. Launch the wrapper with 64-frame overrides:
   ```bash
   OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD=-64 \
   PIPEWIRE_LATENCY="64/44100" \
   PIPEWIRE_ALSA='{ alsa.format=S32_LE alsa.channels=2 alsa.buffer-bytes=1024 alsa.period-bytes=512 }' \
   ~/.local/bin/osu-lazer-wrapper
   ```

### Discord / Vesktop lowers game volume by 70% during calls
WirePlumber 0.5+ applies role-based ducking (`0.3`) when a voice call is active. Disable it:
```bash
mkdir -p ~/.config/wireplumber/wireplumber.conf.d/
printf 'wireplumber.settings = {\n  linking.role-based.duck-level = 1.0\n}\n' > ~/.config/wireplumber/wireplumber.conf.d/52-disable-ducking.conf
wpctl settings linking.role-based.duck-level 1.0
```

### `audio-latency-doctor.sh` warns about Realtime or Nice limits
Grant your user realtime and negative-nice permissions (or install `realtime-privileges` on Arch):
```bash
sudo tee /etc/security/limits.d/99-realtime.conf >/dev/null <<EOF
$USER - rtprio 98
$USER - nice -15
$USER - memlock unlimited
EOF
```
*(Log out and back in for `limits.d` changes to apply).*

### `osu.AppImage` fails to start when AppImageLauncher is installed
Static `musl` AppImage runtimes conflict with `appimagelauncher`'s `binfmt_misc` handler (`memfd` breaks `/proc/self/exe`). Mask it if needed:
```bash
sudo ln -sf /dev/null /etc/binfmt.d/appimagelauncher.conf
systemctl --user disable --now appimagelauncherd.service
```

---

## Display, Input & System Tuning

### Hyprland Zero-Lag Display & Raw Input
Enable Wayland tearing (`wp_tearing_control_v1`) and fullscreen `direct_scanout` in `~/.config/hypr/hyprland.conf` (Hyprland `>= 0.53` syntax—see [`hyprland/osu-tearing.conf`](hyprland/osu-tearing.conf) or [`hyprland/osu-tearing.lua`](hyprland/osu-tearing.lua) for Caelestia Lua):
```ini
general {
    allow_tearing = true
}

render {
    direct_scanout = true
}

windowrule = match:class ^(osu!)$, immediate yes, content game, idle_inhibit focus
windowrule = match:class ^(sh\.ppy\.osu)$, immediate yes, content game, idle_inhibit focus

input {
    accel_profile = flat
    sensitivity = 0.0
}

misc {
    vrr = 0
}
```
*(Keep your display at 8-bit SDR `XRGB8888` rather than `bitdepth, 10` so `direct_scanout` engages without 1-second KMS modeset blackouts).*

### Isolate Your USB DAC from 8000Hz Keypads
An 8000Hz keypad generates 8,000 interrupts/sec. Plug your **USB DAC** into a **CPU-direct USB port**, and keep 8000Hz keypads, tablets, mice, and USB mics on **chipset USB ports**. Verify separate `Bus` numbers with `./scripts/audio-latency-doctor.sh` (Section 5).

### Kernel Scheduler (`scx_lavd`) & OpenTabletDriver
- **CachyOS / `sched_ext`:** Set `default_sched = "scx_lavd"` in `/etc/scx_loader.toml`.
- **OpenTabletDriver:** Run `otd-daemon` at `Nice=-11` (`SCHED_OTHER`, never `SCHED_FIFO`):
  ```bash
  mkdir -p ~/.config/systemd/user/opentabletdriver.service.d
  printf "[Service]\nNice=-11\n" > ~/.config/systemd/user/opentabletdriver.service.d/override.conf
  systemctl --user daemon-reload && systemctl --user restart opentabletdriver.service
  ```

---

## Optional: Pushing Latency Even Further

The default setup above (~5.1ms ALSA+USB, ~6.5–7.3ms end-to-end) hits the practical sweet spot with full desktop audio mixing. The tweaks below can trim additional latency or wakeup jitter, **at the cost of higher CPU/USB load, instability risk, or losing simultaneous desktop audio**—they are **not** applied by default.

### 1. Higher Sample Rate (`88200` / `96000` / `176400 Hz`)
If your DAC supports higher rates (check `/proc/asound/card0/stream0`), keeping a 32-frame quantum at `88200 Hz` (2× `44100`) or `176400 Hz` (4× `44100`) halves or quarters the time per quantum/headroom (`32 / 88200 = 0.36ms`; `32 / 176400 = 0.18ms`) and can shrink USB URB queue time:
- Add the target rate to `~/.config/pipewire/pipewire.conf.d/10-rates.conf` (`default.clock.allowed-rates = [ 44100 48000 88200 ]`).
- Override on launch:
  ```bash
  PIPEWIRE_LATENCY="32/88200" ~/.local/bin/osu-lazer-wrapper
  ```
  *(The wrapper derives `clock.force-rate` and `clock.force-quantum` from `PIPEWIRE_LATENCY` automatically).*
- **Tradeoff:** Higher CPU and USB bandwidth; if `BASS` opens at `44100 Hz`, PipeWire resamples (`88200`/`176400` avoids fractional resampling).

### 2. `16`-Frame Quantum & Buffer (`quantum 16` at `44100 Hz`)
PipeWire defaults to `default.clock.min-quantum = 32`. Lowering it to `16` (`0.36ms`) cuts another `~0.7–1.4ms`:
- Add `default.clock.min-quantum = 16` to `~/.config/pipewire/pipewire.conf.d/10-rates.conf`.
- Set `api.alsa.period-size = 16` and `api.alsa.headroom = 16` (or `0`) in WirePlumber, then launch with:
  ```bash
  OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD=-16 \
  PIPEWIRE_LATENCY="16/44100" \
  PIPEWIRE_ALSA='{ alsa.format=S32_LE alsa.channels=2 alsa.buffer-bytes=256 alsa.period-bytes=128 }' \
  ~/.local/bin/osu-lazer-wrapper
  ```
- **Tradeoff:** Many USB DACs enforce a higher `period_size_min` in `snd_usb_audio`, or will crackle (xrun) when Discord/streaming runs concurrently.

### 3. Direct Exclusive ALSA (`hw:X,0`, Bypassing PipeWire)
Selecting your DAC's raw ALSA device directly inside osu!lazer (still keeping `OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD=-32`) bypasses `pipewire-alsa`, the PipeWire graph quantum, and PipeWire's ALSA headroom, cutting **~1.5–2.2ms**:
- **Tradeoff:** Exclusive hardware lock—Discord, browsers, Spotify, and desktop audio cannot use that DAC while osu! is open.

### 4. Eliminating Wakeup Jitter (`/dev/cpu_dma_latency` & PCIe xHCI PM)
Even with `powerprofilesctl performance`, CPU idle states (`C3`, ~`350 µs` exit latency) and USB host controller runtime PM (`power/control = auto`) can add rare wakeup jitter on aggressive `16/32`-frame buffers:
- Hold `/dev/cpu_dma_latency` open with `0` (requires write access, e.g. `realtime` group) while osu! runs to keep CPU cores in `C0/C1`.
- Set `power/control` to `on` for your DAC's PCIe xHCI controller (`/sys/bus/pci/devices/<xhci_bdf>/power/control`).
- **Tradeoff:** Does **not** reduce average latency—under active 360Hz+ gameplay the CPU and USB bus rarely sleep anyway. Acts strictly as insurance against rare micro-xruns at ultra-low quantums (`16`/`32`).

---

## Reference Testbed & Repo Layout

- **CPU / GPU:** AMD Ryzen 7 7700 + Radeon RX 9070 XT
- **Audio / Mic:** Focusrite Scarlett Solo 4th Gen (USB 2.0) + Fifine USB Mic
- **Input:** SayoDevice O3C (8000Hz) + Wacom CTL-480 (1000Hz `shavit` firmware, OpenTabletDriver `Nice -11`)
- **OS / Display:** Arch Linux (`linux-cachyos`, `scx_lavd`), Hyprland (`AOC Q27G4SDR` 2560×1440 @ 360Hz OLED, 8-bit SDR Direct Scanout + Tearing)

```text
osu-linux-audio-latency/
├── README.md                      # Setup guide, troubleshooting & optional tweaks
├── pipewire/
│   └── 10-rates.conf              # Allows 44.1kHz + 48kHz in PipeWire
├── wireplumber/
│   └── 51-osu-low-latency.conf    # WirePlumber clock master & ALSA period/headroom rule
├── hyprland/
│   ├── osu-tearing.conf           # Hyprland >= 0.53 tearing, scanout & raw input config
│   └── osu-tearing.lua            # Caelestia / Hyprland Lua snippet
├── scripts/
│   ├── osu-lazer-wrapper.sh       # Launch wrapper (PipeWire lock, RT boost, power profiles)
│   └── audio-latency-doctor.sh    # Live diagnostic & latency measurement tool
└── doc/
    └── ARCHITECTURE.md            # Deep-dive signal chain & the 8 Linux audio/input traps
```

For full technical explanations of the signal chain and every trap, see **[`doc/ARCHITECTURE.md`](doc/ARCHITECTURE.md)**.
