-- Hyprland Low-Latency Rhythm Gaming Rules (Lua / Caelestia Rice Syntax)
-- Add to your ~/.config/caelestia/hypr-user.lua

hl.config({
  general = {
    allow_tearing = true, -- Allows `immediate` window rule to work
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

-- Force immediate Wayland presentation for osu! (bypasses compositor vsync)
hl.window_rule({ match = { class = "^(osu!)$" }, immediate = true })
hl.window_rule({ match = { class = "^(sh%.ppy%.osu)$" }, immediate = true })
hl.window_rule({ match = { class = "^(osu%-lazer)$" }, immediate = true })
