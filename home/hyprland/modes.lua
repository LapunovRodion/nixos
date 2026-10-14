-- Режим стола — свой у каждого, Mod+W по кругу, Mod+Shift+W — сразу в tile:
--   tile   — dwindle, столы листаются вбок, бар Caelestia слева;
--   scroll — лента колонок как в niri, столы листаются вверх-вниз, бар сверху;
--   float  — как KDE/Windows: все окна плавают, с заголовками (bars.lua),
--            бар снизу.
-- Подключается из home/hyprland.nix (extraLuaFiles).
--
-- Режимы лежат в ~/.local/state/hypr/workspace-modes: Lua перечитывается
-- при каждом `hyprctl reload` (его делает и theme-sync при смене обоев).
-- Бар двигается файлом ~/.config/caelestia/monitors/<выход>/shell.json —
-- bar.position из патча home/caelestia/bar-position.patch, шелл следит
-- за файлом сам.

local mod = "SUPER"
local bind, dsp = hl.bind, hl.dsp

local MODES = {
  tile = { next = "scroll", bar = "left" },
  scroll = { next = "float", bar = "top", layout = "scrolling", animation = "slidevert" },
  float = { next = "tile", bar = "bottom" },
}

local home = os.getenv("HOME")
local stateDir = home .. "/.local/state/hypr"
local stateFile = stateDir .. "/workspace-modes"
local barDir = (os.getenv("XDG_CONFIG_HOME") or home .. "/.config") .. "/caelestia/monitors/"

-- id стола → режим; tile не хранится (он по умолчанию).
local modes = {}
do
  local f = io.open(stateFile)
  if f then
    for line in f:lines() do
      local id, m = line:match("^(%-?%d+) (%a+)$")
      if id and MODES[m] then modes[tonumber(id)] = m end
    end
    f:close()
  end
end

local function save()
  os.execute("mkdir -p '" .. stateDir .. "'")
  local f = io.open(stateFile, "w")
  if not f then return end
  for id, m in pairs(modes) do f:write(id, " ", m, "\n") end
  f:close()
end

local function modeOf(ws)
  return ws and modes[ws.id] or "tile"
end

local function activeMode()
  return modeOf(hl.get_active_workspace())
end

-- Раскладка и анимация стола — правилом. Правило применяется на лету,
-- выключенное — откатывает стол к общим general.layout / анимации.
local rules = {}
local function applyRule(id)
  if rules[id] then rules[id]:set_enabled(false) end
  rules[id] = nil
  local m = MODES[modes[id] or "tile"]
  if m.layout then
    rules[id] = hl.workspace_rule({ workspace = tostring(id), layout = m.layout, animation = m.animation })
  end
end

-- float-режим: окно плавает и помечено modefloat. Снимается float только
-- с помеченных — диалоги, плавающие сами по себе, такими и остаются.
local function tagged(w)
  for _, t in ipairs(w.tags or {}) do
    if t == "modefloat" then return true end
  end
  return false
end

local function setFloat(w, on)
  if on and not w.floating then
    hl.dispatch(dsp.window.float({ window = w, action = "enable" }))
    hl.dispatch(dsp.window.tag({ window = w, tag = "+modefloat" }))
  elseif not on and tagged(w) then
    hl.dispatch(dsp.window.tag({ window = w, tag = "-modefloat" }))
    hl.dispatch(dsp.window.float({ window = w, action = "disable" }))
  end
end

-- Бар каждого монитора — по режиму его активного стола. Файл пишется,
-- только если позиция меняется: шелл на каждую смену пересобирает окна.
local function syncBar()
  for _, mon in ipairs(hl.get_monitors()) do
    local want = '{ "bar": { "position": "' .. MODES[modeOf(mon.active_workspace)].bar .. '" } }\n'
    local path = barDir .. mon.name .. "/shell.json"
    local f = io.open(path)
    local have = f and f:read("*a")
    if f then f:close() end
    if have ~= want then
      os.execute("mkdir -p '" .. barDir .. mon.name .. "'")
      f = io.open(path, "w")
      if f then
        f:write(want)
        f:close()
      end
    end
  end
end

local function setMode(m)
  local ws = hl.get_active_workspace()
  if not ws or ws.special or modeOf(ws) == m then return end
  modes[ws.id] = m ~= "tile" and m or nil
  save()
  applyRule(ws.id)
  for _, w in ipairs(hl.get_windows({ workspace = ws.id })) do
    setFloat(w, m == "float")
  end
  syncBar()
end

for id in pairs(modes) do applyRule(id) end
syncBar()
hl.on("hyprland.start", syncBar)
hl.on("monitor.added", syncBar)
hl.on("workspace.active", syncBar)

hl.on("window.open", function(w)
  if modeOf(w.workspace) == "float" then setFloat(w, true) end
end)
-- Спецстолы (свёрнутые окна — special:minimized) окно не трогают.
hl.on("window.move_to_workspace", function(w, ws)
  if ws and not ws.special then setFloat(w, modeOf(ws) == "float") end
end)

bind(mod .. " + W", function() setMode(MODES[activeMode()].next) end)
bind(mod .. " + SHIFT + W", function() setMode("tile") end)

-- Бинды, разные по режимам. Таблица: режим → диспетчер; нет режима — default.
local function byMode(t)
  return function()
    local d = t[activeMode()] or t.default
    if d then hl.dispatch(d) end
  end
end

-- Вверх/вниз в ленте — как window-focus-or-workspace-* в niri: на краю
-- колонки фокус уходит на соседний стол.
local function focusOrWorkspace(dir, ws)
  return function()
    local before = hl.get_active_window()
    hl.dispatch(dsp.focus({ direction = dir }))
    local after = hl.get_active_window()
    if (before and before.address) == (after and after.address) then
      hl.dispatch(dsp.focus({ workspace = ws }))
    end
  end
end

local dirs = { left = "H", down = "J", up = "K", right = "L" }
local swap = { left = "swapcol l", right = "swapcol r" }
local edge = { down = "e+1", up = "e-1" }
for dir, vim in pairs(dirs) do
  for _, key in ipairs({ dir, vim }) do
    bind(mod .. " + " .. key, byMode({
      scroll = edge[dir] and focusOrWorkspace(dir, edge[dir]),
      default = dsp.focus({ direction = dir }),
    }))
    bind(mod .. " + CTRL + " .. key, byMode({
      scroll = swap[dir] and dsp.layout(swap[dir]),
      default = dsp.window.move({ direction = dir }),
    }))
  end
end

-- Ширина: в ленте — колонка (Mod+R — по кругу из explicit_column_widths),
-- в tile — поворот деления, в остальном — размер окна.
bind(mod .. " + R", byMode({ scroll = dsp.layout("colresize +conf"), tile = dsp.layout("togglesplit") }))
bind(mod .. " + SHIFT + R", byMode({ scroll = dsp.layout("colresize -conf") }))
bind(mod .. " + Minus", byMode({
  scroll = dsp.layout("colresize -0.1"),
  default = dsp.window.resize({ x = -80, y = -60, relative = true }),
}), { repeating = true })
bind(mod .. " + Equal", byMode({
  scroll = dsp.layout("colresize +0.1"),
  default = dsp.window.resize({ x = 80, y = 60, relative = true }),
}), { repeating = true })

-- Колонки ленты: забрать окно в соседнюю / выставить в свою.
bind(mod .. " + BracketLeft", byMode({ scroll = dsp.layout("consume_or_expel prev") }))
bind(mod .. " + BracketRight", byMode({ scroll = dsp.layout("consume_or_expel next") }))
bind(mod .. " + Comma", byMode({ scroll = dsp.layout("consume") }))
bind(mod .. " + Period", byMode({ scroll = dsp.layout("expel") }))
bind(mod .. " + C", byMode({ scroll = dsp.layout("center"), default = dsp.window.center() }))
bind(mod .. " + SHIFT + mouse_down", byMode({ scroll = dsp.focus({ direction = "right" }) }))
bind(mod .. " + SHIFT + mouse_up", byMode({ scroll = dsp.focus({ direction = "left" }) }))

-- Свёрнутые окна (кнопка «—» в заголовке): Mod+M — показать/спрятать,
-- Mod+Shift+M — вернуть активное окно на текущий стол.
bind(mod .. " + M", dsp.workspace.toggle_special("minimized"))
bind(mod .. " + SHIFT + M", function()
  local ws = hl.get_active_workspace()
  if ws then hl.dispatch(dsp.window.move({ workspace = ws.id })) end
end)
