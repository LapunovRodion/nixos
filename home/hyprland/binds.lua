-- Бинды Hyprland. Перенесены из home/umbriel/config.toml там, где у Hyprland
-- есть аналог. Подключается из home/hyprland.nix (extraLuaFiles).
-- Справка по API: hl.dsp.* — https://wiki.hypr.land/Configuring/Start/

local mod = "SUPER"
local bind, exec, global = hl.bind, hl.dsp.exec_cmd, hl.dsp.global

-- Приложения
bind(mod .. " + T", exec("kitty"))
bind(mod .. " + D", global("caelestia:launcher"))
bind(mod .. " + B", exec("zen-beta"))
bind(mod .. " + E", exec("thunar"))
bind(mod .. " + ALT + E", exec("kitty -e yazi"))
bind("SUPER + ALT + L", global("caelestia:lock"))
bind("SUPER + ALT + S", exec("pkill orca || exec orca"), { locked = true })

-- Окна
bind(mod .. " + Q", hl.dsp.window.close())
bind(mod .. " + F", hl.dsp.window.fullscreen({ mode = "maximized" })) -- бар остаётся
bind(mod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
bind(mod .. " + N", hl.dsp.window.float())

-- Фокус монитора: стрелки и hjkl, как в Umbriel. Фокус и перенос окна,
-- Mod+C и прочее, что зависит от режима стола, — в modes.lua.
local dirs = { left = "H", down = "J", up = "K", right = "L" }
for dir, vim in pairs(dirs) do
  for _, key in ipairs({ dir, vim }) do
    bind(mod .. " + SHIFT + " .. key, hl.dsp.focus({ monitor = dir:sub(1, 1) }))
  end
end

-- Столы
for i = 1, 9 do
  bind(mod .. " + " .. i, hl.dsp.focus({ workspace = i }))
  bind(mod .. " + CTRL + " .. i, hl.dsp.window.move({ workspace = i }))
end
for _, key in ipairs({ "Page_Down", "U", "mouse_down" }) do
  bind(mod .. " + " .. key, hl.dsp.focus({ workspace = "e+1" }))
end
for _, key in ipairs({ "Page_Up", "I", "mouse_up" }) do
  bind(mod .. " + " .. key, hl.dsp.focus({ workspace = "e-1" }))
end
bind(mod .. " + CTRL + U", hl.dsp.window.move({ workspace = "e+1" }))
bind(mod .. " + CTRL + I", hl.dsp.window.move({ workspace = "e-1" }))
bind(mod .. " + Tab", hl.dsp.focus({ workspace = "previous" }))

-- Обзор всех столов (плагин hyprtasking): сетка, окна тащатся мышью.
bind(mod .. " + O", function() hl.plugin.hyprtasking.toggle("all") end)

-- Окно мышью: Mod+ЛКМ — двигать, Mod+ПКМ — тянуть размер.
bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Скриншоты, буфер, запись
-- Область — сразу в буфер (screenshotClip). Простой caelestia:screenshot
-- открывает снимок в редакторе swappy (он в PATH самой Caelestia).
bind("Print", global("caelestia:screenshotClip")) -- область
bind(mod .. " + S", global("caelestia:screenshotClip"))
bind(mod .. " + CTRL + S", global("caelestia:screenshot")) -- область → swappy
bind("CTRL + Print", exec("caelestia screenshot")) -- весь экран: буфер + файл
bind(mod .. " + SHIFT + S", exec("caelestia screenshot"))
bind(mod .. " + V", exec("pkill fuzzel || caelestia clipboard"))
bind(mod .. " + ALT + R", exec("screenrec"))

-- Сессия
bind(mod .. " + SHIFT + E", hl.dsp.exit())
bind("CTRL + ALT + Delete", global("caelestia:session"))
bind(mod .. " + SHIFT + P", hl.dsp.dpms({ action = "off" }))

-- Звук, медиа, яркость — работают и на локскрине; громкость/яркость с повтором.
local lr = { locked = true, repeating = true }
bind("XF86AudioRaiseVolume", exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1+ -l 1.0"), lr)
bind("XF86AudioLowerVolume", exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1-"), lr)
bind("XF86MonBrightnessUp", global("caelestia:brightnessUp"), lr)
bind("XF86MonBrightnessDown", global("caelestia:brightnessDown"), lr)
bind(mod .. " + F8", global("caelestia:brightnessUp"), lr)
bind(mod .. " + F7", global("caelestia:brightnessDown"), lr)

local l = { locked = true }
bind("XF86AudioMute", exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), l)
bind("XF86AudioMicMute", exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), l)
bind("XF86AudioPlay", exec("playerctl play-pause"), l)
bind("XF86AudioStop", exec("playerctl stop"), l)
bind("XF86AudioPrev", exec("playerctl previous"), l)
bind("XF86AudioNext", exec("playerctl next"), l)
