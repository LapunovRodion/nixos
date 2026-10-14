-- Цвета рамок окон — из палитры Caelestia, то есть от обоев. Подключается
-- из home/hyprland.nix (extraLuaFiles).
--
-- current.lua пишет `caelestia` при каждой смене схемы (theme.enableHypr),
-- а перечитывается он только с конфигом — reload делает хук перекраски
-- (home/caelestia/theme-sync.sh). Пары как были в Umbriel: фокус —
-- tertiary, остальные — tertiaryContainer. Файла ещё нет (чистая машина,
-- обои ни разу не ставились) — остаются цвета Hyprland по умолчанию.
local ok, c = pcall(dofile, os.getenv("HOME") .. "/.config/hypr/scheme/current.lua")
if ok and type(c) == "table" then
  hl.config({
    general = {
      col = {
        active_border = "rgb(" .. c.tertiary .. ")",
        inactive_border = "rgb(" .. c.tertiaryContainer .. ")",
      },
    },
  })
end

-- Палитра — модулем для bars.lua (заголовки окон); nil, если схемы ещё нет.
return ok and type(c) == "table" and c or nil
