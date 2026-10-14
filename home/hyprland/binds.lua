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

-- Фокус монитора: стрелки и hjkl, как в Umbriel. Фокус и перенос окна
-- (Mod+J/K на краю — соседний стол), Mod+C и прочее, что зависит от
-- режима стола, — в modes.lua.
local dirs = { left = "H", down = "J", up = "K", right = "L" }
for dir, vim in pairs(dirs) do
  for _, key in ipairs({ dir, vim }) do
    bind(mod .. " + SHIFT + " .. key, hl.dsp.focus({ monitor = dir:sub(1, 1) }))
  end
end

-- Столы — свои у каждого монитора, как в niri: у левого 1–9, у следующего
-- 11–19 и т. д. (мониторы по порядку слева направо, зеркала не в счёт).
-- Mod+цифра — стол текущего монитора.
local function base(mon)
  local xs = {}
  for _, m in ipairs(hl.get_monitors()) do
    if not m.is_mirror then xs[#xs + 1] = m.x end
  end
  table.sort(xs)
  for i, x in ipairs(xs) do
    if x == mon.x then return (i - 1) * 10 end
  end
  return 0
end

for i = 1, 9 do
  bind(mod .. " + " .. i, function()
    hl.dispatch(hl.dsp.focus({ workspace = base(hl.get_active_monitor()) + i }))
  end)
  bind(mod .. " + CTRL + " .. i, function()
    hl.dispatch(hl.dsp.window.move({ workspace = base(hl.get_active_monitor()) + i }))
  end)
end

-- Подключённому монитору Hyprland даёт первый свободный номер (бывал 22) —
-- переименовываем в первый стол его диапазона.
local function fixStartWorkspaces()
  for _, m in ipairs(hl.get_monitors()) do
    local ws, b = m.active_workspace, base(m)
    if not m.is_mirror and ws and (ws.id <= b or ws.id > b + 9) and not hl.get_workspace(b + 1) then
      hl.dispatch(hl.dsp.workspace.change_id({ workspace = ws.id, id = b + 1 }))
    end
  end
end
hl.on("hyprland.start", fixStartWorkspaces)
hl.on("monitor.added", fixStartWorkspaces)

-- Соседний открытый стол этого же монитора (m±1); вниз — следующий.
for _, key in ipairs({ "Page_Down", "U", "mouse_down" }) do
  bind(mod .. " + " .. key, hl.dsp.focus({ workspace = "m+1" }))
end
for _, key in ipairs({ "Page_Up", "I", "mouse_up" }) do
  bind(mod .. " + " .. key, hl.dsp.focus({ workspace = "m-1" }))
end
bind(mod .. " + CTRL + U", hl.dsp.window.move({ workspace = "m+1" }))
bind(mod .. " + CTRL + I", hl.dsp.window.move({ workspace = "m-1" }))
bind(mod .. " + Tab", hl.dsp.focus({ workspace = "previous" }))

-- Обзор столов и окон (quickshell-overview, home/hyprland.nix): клик —
-- перейти, перетащить — на другой стол, средняя кнопка — закрыть.
bind(mod .. " + O", hl.dsp.exec_cmd("qs ipc -c overview call overview toggle"))

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
