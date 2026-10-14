{ inputs, pkgs, osConfig, ... }:

# =============================================================
# Рабочий стол «Umbriel + noctalia» — пользовательская часть.
# Подключается из modules/umbriel.nix, а не из home.nix: стол
# переключается одной строкой в modules/common.nix.
# =============================================================

{
  # В home-manager (с 2026-08) есть свой programs.noctalia — он конфликтует
  # с модулем из флейка noctalia. Отключаем встроенный, оставляем флейковый.
  disabledModules = [ "programs/noctalia" ];

  imports = [
    inputs.noctalia.homeModules.default
    ./noctalia.nix        # весь конфиг шелла — бар, док, виджеты, тема, плагины
  ];

  # =============================================================
  # Umbriel — конфиг композитора: общий файл + машинозависимый
  # (мониторы) через include. Оба — read-only симлинки в /nix/store,
  # поэтому всё генерируемое (цвета noctalia) тоже подключается include'ом.
  # Модуль programs.umbriel из home-manager не нужен — он умеет только
  # положить этот же файл.
  # =============================================================
  xdg.configFile."umbriel/config.toml".source = ./umbriel/config.toml;
  xdg.configFile."umbriel/outputs.toml".source = osConfig.local.umbrielOutputs;

  # Отдельный X-сервер для Steam (DISPLAY=:7 задан в programs.steam.package,
  # modules/umbriel.nix). Встроенный XWM Umbriel создаёт главное окно Steam,
  # но не показывает его (проверено 2026-10-10: X11-kitty показал, Steam —
  # нет; под xwayland-satellite окно появилось). Остальные X-приложения —
  # по-прежнему на встроенном Xwayland (:0).
  systemd.user.services.xwayland-satellite-steam = {
    Unit = {
      Description = "xwayland-satellite :7 for Steam";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.xwayland-satellite}/bin/xwayland-satellite :7";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
