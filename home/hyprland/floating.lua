-- float-стол (modes.lua) — как KDE/Windows. Плавание, центр и память
-- размера — правило окна в modes.lua; здесь то, чего у Hyprland нет:
-- второе и следующие окна лесенкой, слишком большие ужимаются, фокус по
-- клику, Mod+стрелки — снап как в Plasma, Alt+Tab, упорядочить окна.
-- Подключается из home/hyprland.nix (extraLuaFiles). Тянуть за края,
-- липкие края и тень — там же, в settings.config.
--
-- Трогаются только окна с меткой modefloat — те, что плавают из-за режима.
-- Модальные диалоги Hyprland ставит, как ставил.

local modes = require("modes")
local mod = "SUPER"
local bind, dsp = hl.bind, hl.dsp

local GAP = 10 -- general.gaps_out (home/hyprland.nix)
local BAR = 28 -- plugin.hyprbars.bar_height: заголовок рисуется над окном
local STEP = 40 -- шаг лесенки

local function isFloatWs(ws)
  return ws and not ws.special and modes.modeOf(ws) == "float"
end

local function monitorOf(w)
  return w.monitor or hl.get_active_monitor()
end

-- Рабочая область монитора: без бара Caelestia (reserved), отступов и
-- полосы заголовка. x, y, w, h — под само окно.
local function area(mon)
  local r = mon.reserved or {}
  local left, top = r.left or 0, r.top or 0
  return {
    x = mon.x + left + GAP,
    y = mon.y + top + GAP + BAR,
    w = mon.width / mon.scale - left - (r.right or 0) - 2 * GAP,
    h = mon.height / mon.scale - top - (r.bottom or 0) - 2 * GAP - BAR,
  }
end

local function setGeometry(w, x, y, width, height)
  hl.dispatch(dsp.window.resize({ window = w, x = math.floor(width), y = math.floor(height) }))
  hl.dispatch(dsp.window.move({ window = w, x = math.floor(x), y = math.floor(y) }))
end

-- Окно не вылезает за рабочую область; больше неё — ужимается.
local function clamped(a, x, y, width, height)
  width, height = math.min(width, a.w), math.min(height, a.h)
  x = math.max(a.x, math.min(x, a.x + a.w - width))
  y = math.max(a.y, math.min(y, a.y + a.h - height))
  return x, y, width, height
end

-- Окна стола, плавающие из-за режима, кроме skip.
local function floats(ws, skip)
  local out = {}
  for _, o in ipairs(hl.get_windows({ workspace = ws.id })) do
    if o.address ~= (skip and skip.address) and o.mapped and modes.tagged(o) and not o.pinned then
      out[#out + 1] = o
    end
  end
  return out
end

-- Новое окно: правило уже поставило его по центру со своим размером.
-- Больше 85% области (просил весь экран или так запомнил) — 60% × 65%.
-- На столе уже есть окна — на шаг вниз-вправо от последнего размещённого;
-- упёрлось в край — снова от угла.
local last = {} -- ws.id → { x, y }

local function place(w)
  local ws = w.workspace
  if not isFloatWs(ws) then return end
  local a = area(monitorOf(w))
  local width, height = w.size.x, w.size.y
  if width > a.w * 0.85 or height > a.h * 0.85 then
    width, height = a.w * 0.6, a.h * 0.65
  end
  local x, y = a.x + (a.w - width) / 2, a.y + (a.h - height) / 2
  if #floats(ws, w) > 0 and last[ws.id] then
    x, y = last[ws.id][1] + STEP, last[ws.id][2] + STEP
    if x + width > a.x + a.w or y + height > a.y + a.h then x, y = a.x, a.y end
  end
  x, y, width, height = clamped(a, x, y, width, height)
  setGeometry(w, x, y, width, height)
  last[ws.id] = { x, y }
end
modes.place = place

-- Фокус: на float-столе — по клику (2: колесо и наведение идут окну под
-- курсором, клавиатура — кликнутому), на остальных — за мышью (1).
local function syncFocus()
  local want = isFloatWs(hl.get_active_workspace()) and 2 or 1
  if hl.get_config("input.follow_mouse") ~= want then
    hl.config({ input = { follow_mouse = want } })
  end
end
syncFocus()
hl.on("hyprland.start", syncFocus)
hl.on("workspace.active", syncFocus)
hl.on("monitor.focused", syncFocus)

-- Mod+стрелки — снап, как в Plasma/Windows. Положение окна — клетка
-- h, v: -1 — левая/верхняя половина, 1 — правая/нижняя, 0 — во всю
-- ширину/высоту. Влево/вправо: половина; с противоположной половины —
-- прежний размер, с четверти — четверть с другой стороны. Вверх/вниз
-- с половины — четверть, с четверти — обратно половина; вверх с обычного —
-- развернуть, вниз с развёрнутого — прежний размер, вниз с обычного —
-- свернуть (special:minimized, как кнопка заголовка).
local snapped = {} -- address → { h, v, rect = { x, y, w, h }, prev = { x, y, w, h } }

local function rectOf(a, h, v)
  local halfW, halfH = (a.w - GAP) / 2, (a.h - GAP - BAR) / 2
  local x = h == 1 and a.x + halfW + GAP or a.x
  local y = v == 1 and a.y + halfH + GAP + BAR or a.y
  return { x, y, h == 0 and a.w or halfW, v == 0 and a.h or halfH }
end

-- Снап считается, пока окно стоит, где его поставили: утащили мышью —
-- снова обычное.
local function stateOf(w)
  local s = snapped[w.address]
  if not s then return nil end
  local r = s.rect
  if math.abs(w.at.x - r[1]) > 4 or math.abs(w.at.y - r[2]) > 4 then
    snapped[w.address] = nil
    return nil
  end
  return s
end

local function snap(dir)
  local w = hl.get_active_window()
  if not w or not modes.tagged(w) or w.fullscreen ~= 0 then return end
  local s = stateOf(w)
  local d = (dir == "left" or dir == "up") and -1 or 1
  local h, v
  if dir == "left" or dir == "right" then
    if not s or s.h == 0 then
      h, v = d, 0
    elseif s.h == -d then
      if s.v == 0 then h = nil else h, v = d, s.v end
    else
      return
    end
  else
    if not s then
      if d == 1 then
        return hl.dispatch(dsp.window.move({ window = w, workspace = "special:minimized", follow = false }))
      end
      h, v = 0, 0
    elseif s.h == 0 then
      if d == -1 then return end
      h = nil
    elseif s.v == 0 then
      h, v = s.h, d
    elseif s.v == -d then
      h, v = s.h, 0
    else
      return
    end
  end
  if h == nil then
    snapped[w.address] = nil
    local p = s.prev
    return setGeometry(w, p[1], p[2], p[3], p[4])
  end
  local r = rectOf(area(monitorOf(w)), h, v)
  snapped[w.address] = {
    h = h, v = v, rect = r,
    prev = s and s.prev or { w.at.x, w.at.y, w.size.x, w.size.y },
  }
  setGeometry(w, r[1], r[2], r[3], r[4])
end
modes.snap = snap

hl.on("window.close", function(w) snapped[w.address] = nil end)

-- Средний клик по заголовку — окно под остальные.
-- ponytail: z-порядок Lua не отдаёт; заголовки перекрылись — берётся
-- активное окно, иначе первое попавшееся.
bind("mouse:274", function()
  local ws, c = hl.get_active_workspace(), hl.get_cursor_pos()
  if not isFloatWs(ws) or not c then return end
  local hit
  for _, o in ipairs(floats(ws)) do
    if c.x >= o.at.x and c.x < o.at.x + o.size.x and c.y >= o.at.y - BAR and c.y < o.at.y then
      if o.active or not hit then hit = o end
    end
  end
  if hit then hl.dispatch(dsp.window.alter_zorder({ window = hit, mode = "bottom" })) end
end, { non_consuming = true })

-- Alt+Tab — следующее окно стола и наверх, Alt+Shift+Tab — обратно.
for keys, next in pairs({ ["ALT + Tab"] = true, ["ALT + SHIFT + Tab"] = false }) do
  bind(keys, function()
    hl.dispatch(dsp.window.cycle_next({ next = next }))
    hl.dispatch(dsp.window.bring_to_top())
  end)
end

-- Mod+A — все окна стола лесенкой, Mod+Shift+A — сеткой.
local function arrange(grid)
  local ws = hl.get_active_workspace()
  if not isFloatWs(ws) then return end
  local list = floats(ws)
  if #list == 0 then return end
  -- Давнее — ниже: история фокуса растёт от активного.
  table.sort(list, function(p, q) return p.focus_history_id > q.focus_history_id end)
  local a = area(monitorOf(list[1]))
  local cols = math.ceil(math.sqrt(#list))
  local rows = math.ceil(#list / cols)
  local cw, ch = (a.w - GAP * (cols - 1)) / cols, (a.h - (GAP + BAR) * (rows - 1)) / rows
  local width, height = a.w * 0.6, a.h * 0.65
  for i, o in ipairs(list) do
    if grid then
      local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
      setGeometry(o, a.x + col * (cw + GAP), a.y + row * (ch + GAP + BAR), cw, ch)
    else
      local x, y = clamped(a, a.x + (i - 1) * STEP, a.y + (i - 1) * STEP, width, height)
      setGeometry(o, x, y, width, height)
      last[ws.id] = { x, y }
    end
    hl.dispatch(dsp.window.alter_zorder({ window = o, mode = "top" }))
    snapped[o.address] = nil
  end
end

bind(mod .. " + A", function() arrange(false) end)
bind(mod .. " + SHIFT + A", function() arrange(true) end)
