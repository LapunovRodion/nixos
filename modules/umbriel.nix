{ config, pkgs, inputs, ... }:

# =============================================================
# Рабочий стол «Umbriel + noctalia» — системная часть.
# Пользовательская (конфиги umbriel, весь noctalia.nix, X-сервер для
# Steam) — home/umbriel.nix, подключается отсюда же, внизу.
#
# Включается строкой imports в modules/common.nix.
# =============================================================

{
  imports = [ inputs.noctalia.nixosModules.default ];

  # ---------------------------------------------------------------
  # Композитор: Umbriel
  # ---------------------------------------------------------------
  # Umbriel — от авторов noctalia, конфиг в home/umbriel/config.toml.
  # Модуль и пакет — из nixpkgs (бинарник из кеша), свой flake не нужен.
  # niri (был запасной сессией) убран 2026-10-08, конфиг — в git-истории.
  programs.umbriel.enable = true;
  # Его umbriel-portals.conf знает только umbriel и gtk, а Secret берётся
  # из gnome-keyring (пароли Zen, Telegram, git-credential и т.п.).
  xdg.portal.config.umbriel = {
    default = [ "umbriel" "gtk" ];
    "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
  };

  # Логин-менеджер: greetd + tuigreet. По умолчанию — Umbriel; F3 в
  # tuigreet — выбор другой сессии из --sessions.
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions --cmd start-umbriel";
      user = "greeter";
    };
  };

  # ---------------------------------------------------------------
  # noctalia v5 (шелл)
  # ---------------------------------------------------------------
  programs.noctalia = {
    enable = true;
    recommendedServices.enable = true;  # NetworkManager, Bluetooth, UPower, power-profiles-daemon
  };

  # Steam (и игры из него) — на X-сервере xwayland-satellite :7, а не на
  # встроенном Xwayland Umbriel: там главное окно Steam не появляется.
  # Сервис — systemd.user.services.xwayland-satellite-steam в home/umbriel.nix.
  # Игра капризничает под satellite → Launch Options: DISPLAY=:0 %command%
  # Побочно: steam-run тоже получает DISPLAY=:7.
  programs.steam.package = pkgs.steam.override { extraEnv.DISPLAY = ":7"; };

  home-manager.users.artur.imports = [ ../home/umbriel.nix ];
}
