-- Выходы ноутбука для Hyprland (подключается из home/hyprland.nix).
--
-- Масштаб 1.8, а не 1.75 как в Umbriel: Hyprland принимает только масштаб,
-- на который панель 2880x1800 делится нацело (1.8 → 1600x1000), а на
-- «грязный» ругается и подбирает ближайший сам. Крупнее — 1.6 (1800x1125).
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 1.8, bitdepth = 10 })
-- Внешний монитор — куда угодно справа, нативное разрешение.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
