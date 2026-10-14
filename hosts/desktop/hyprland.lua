-- Выходы десктопа для Hyprland (подключается из home/hyprland.nix).
-- Имена и порядок — те же, что в ./umbriel.toml: Acer, Dell, Samsung.

hl.monitor({ output = "HDMI-A-1", mode = "1920x1080", position = "0x0", scale = 1 })    -- Acer S221HQL
hl.monitor({ output = "DP-2", mode = "1920x1080", position = "1920x0", scale = 1 })     -- Dell P2214H
-- Samsung — зеркало Acer. В Umbriel это делал wl-mirror окном на весь
-- экран, у Hyprland зеркалирование своё.
hl.monitor({ output = "HDMI-A-2", mode = "1920x1080", position = "3840x0", scale = 1, mirror = "HDMI-A-1" })

-- wayvnc на тот же HDMI-A-1 — курсор с ноута попадает туда, куда смотрит TV.
hl.on("hyprland.start", function()
  hl.exec_cmd("wayvnc -o HDMI-A-1")
end)
