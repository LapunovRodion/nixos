-- Заголовки окон (плагин hyprbars) — у плавающих окон, то есть у всех окон
-- float-стола (modes.lua) и у диалогов на остальных. У тайловых их снимает
-- правило hyprbars:no_bar в home/hyprland.nix. Подключается оттуда же.
-- Размер и шрифт — там же, в settings.config.plugin.hyprbars; здесь то,
-- что зависит от палитры обоев (как рамки в colors.lua).

-- require отдаёт true, если модуль вернул nil (схемы ещё нет).
local c = require("colors")
if type(c) ~= "table" then c = {} end
local function col(name, fallback)
  return "rgb(" .. (c[name] or fallback) .. ")"
end

hl.config({
  plugin = {
    hyprbars = {
      bar_color = col("surfaceContainer", "1b1a10"),
      ["col.text"] = col("onSurface", "ebe5d2"),
      inactive_button_color = col("surfaceContainerHighest", "282619"),
    },
  },
})

-- Кнопки справа налево: закрыть, развернуть, свернуть (на special:minimized,
-- вернуть — Mod+M / Mod+Shift+M, см. modes.lua), поверх всех (pin: окно
-- над остальными и на всех столах; повторно — открепить).
local function button(bg, fg, icon, action)
  hl.plugin.hyprbars.add_button({
    bg_color = col(bg[1], bg[2]),
    fg_color = col(fg[1], fg[2]),
    size = 14,
    icon = icon,
    action = "hyprctl dispatch '" .. action .. "'",
  })
end

button({ "error", "ffb4ab" }, { "onError", "690005" }, "󰖭", "hl.dsp.window.close()")
button({ "tertiary", "d1c88b" }, { "onTertiary", "363100" }, "󰖯",
  [[hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })]])
button({ "secondary", "cdc6b0" }, { "onSecondary", "343020" }, "󰖰",
  [[hl.dsp.window.move({ workspace = "special:minimized", follow = false })]])
button({ "primary", "d6c76d" }, { "onPrimary", "373100" }, "󰐃", "hl.dsp.window.pin()")
