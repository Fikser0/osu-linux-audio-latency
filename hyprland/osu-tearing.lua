-- Hyprland Low-Latency Rhythm Gaming Rules (Lua / Caelestia Rice Syntax)
-- Add to your ~/.config/caelestia/hypr-user.lua

hl.config({
  general = {
    allow_tearing = true, -- Allows `immediate` window rule to work
  },
  render = {
    direct_scanout = true, -- Bypass compositor for fullscreen games (keep display at 8-bit SDR)
  },
  cursor = {
    no_hardware_cursors = false,
    use_cpu_buffer = 0,
  },
  misc = {
    vrr = 0, -- Disable VRR to prevent frame pacing stutter during tearing
  },
  input = {
    accel_profile = "flat", -- 1:1 raw input (avoid force_no_accel = true to prevent XWayland cursor desync)
    sensitivity = 0.0,
    follow_mouse = 1,
  },
})

-- Force immediate Wayland presentation and idle inhibition while focused
hl.window_rule({ match = { class = "^(osu!)$" }, immediate = true, content = "game", idle_inhibit = "focus" })
hl.window_rule({ match = { class = "^(sh%.ppy%.osu)$" }, immediate = true, content = "game", idle_inhibit = "focus" })
hl.window_rule({ match = { class = "^(osu%-lazer)$" }, immediate = true, content = "game", idle_inhibit = "focus" })
