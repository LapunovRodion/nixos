{ pkgs, ... }:

# =============================================================
# Рабочий стол «Hyprland + Caelestia» — системная часть.
# Пользовательская (конфиг Hyprland, сам шелл) — home/hyprland.nix,
# подключается отсюда же, внизу.
#
# Включается одной строкой в imports modules/common.nix (вместо
# ./umbriel.nix).
# =============================================================

{
  # Модуль nixpkgs: пакет, xdg-desktop-portal-hyprland, polkit, сессия
  # в wayland-sessions. Пакет — из nixpkgs (кеш), флейк Hyprland не нужен.
  programs.hyprland.enable = true;
  # Как и было у Umbriel: всё, чего не умеет свой портал, — gtk, Secret —
  # из gnome-keyring.
  xdg.portal.config.hyprland = {
    default = [ "hyprland" "gtk" ];
    "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
  };

  # Логин-менеджер: greetd + tuigreet, сразу в Hyprland. Без --sessions:
  # стол в системе один, а пакет Hyprland кладёт ещё и «Hyprland (uwsm-managed)»,
  # которая без programs.hyprland.withUWSM падает на входе.
  # start-hyprland, а не голый Hyprland: обёртка из пакета, перезапускает
  # композитор после падения (её же зовёт hyprland.desktop).
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd start-hyprland";
      user = "greeter";
    };
  };

  # Источники данных для виджетов шелла — то же, что у noctalia включал
  # recommendedServices: Bluetooth, батарея, профили питания.
  # NetworkManager уже включён в common.nix.
  hardware.bluetooth.enable = true;
  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;

  home-manager.users.artur.imports = [ ../home/hyprland.nix ];
}
