{ config, inputs, lib, osConfig, pkgs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  noctalia = inputs.noctalia.packages.${system}.default;

  # Caelestia с bar.position (left/top/bottom): невлитый PR #1748, перенесён
  # патчем — подробности в шапке патча. Собирается как with-cli из флейка
  # шелла, только из пропатченного исходника: PR трогает и C++-плагин
  # (отдельная деривация), так что overrideAttrs шелла не хватило бы.
  caelestiaSrc = pkgs.applyPatches {
    name = "caelestia-shell-bar-position";
    src = inputs.caelestia-shell;
    patches = [ ./caelestia/bar-position.patch ];
  };
  caelestiaShell = pkgs.callPackage "${caelestiaSrc}/nix" (with inputs.caelestia-shell.inputs; {
    rev = inputs.caelestia-shell.rev;
    stdenv = pkgs.clangStdenv;
    quickshell = quickshell.packages.${system}.default.override { withX11 = false; withI3 = false; };
    caelestia-cli = caelestia-cli.packages.${system}.default;
    m3shapes = m3shapes.packages.${system}.default;
    withCli = true;
  });
  builtinTemplates = "${noctalia}/share/noctalia/assets/templates";
  cfgHome = config.xdg.configHome;

  # Шаблоны тем для theme-sync. Те же, что были в home/noctalia.nix
  # (theme.templates), только в формате `noctalia theme -c`: встроенные
  # btop/gtk — из пакета noctalia, kitty/Claude — свои. qt не перенесён:
  # qt5ct/qt6ct как платформенной темы тут нет, файлы никто бы не читал.
  userTemplates = (pkgs.formats.toml { }).generate "user.toml" {
    templates = {
      kitty = {
        input_path = "${./kitty/theme.conf.in}";
        output_path = "${cfgHome}/kitty/themes/noctalia.conf";
        post_hook = "${import ./kitty/gradient.nix pkgs}/bin/kitty-gradient";
      };
      claude = {
        input_path = "${./claude/theme.json.in}";
        output_path = "${config.home.homeDirectory}/.claude/themes/noctalia.json";
      };
      btop = {
        input_path = "${builtinTemplates}/btop/btop.theme";
        output_path = "${cfgHome}/btop/themes/noctalia.theme";
        post_hook = "bash '${builtinTemplates}/btop/apply.sh'";
      };
      # gtk3 и gtk4 зовут один apply.sh (он правит оба gtk.css) — не параллельно.
      gtk3 = {
        input_path = "${builtinTemplates}/gtk/gtk3.css";
        output_path = "${cfgHome}/gtk-3.0/noctalia.css";
        post_hook = "bash '${builtinTemplates}/gtk/apply.sh' {{ mode }}";
        hook_async = false;
      };
      gtk4 = {
        input_path = "${builtinTemplates}/gtk/gtk4.css";
        output_path = "${cfgHome}/gtk-4.0/noctalia.css";
        post_hook = "bash '${builtinTemplates}/gtk/apply.sh' {{ mode }}";
        hook_async = false;
      };
    };
  };

  # user.toml + шаблоны сообщества (zen, obsidian, yazi, lazygit, telegram).
  # Те скачаны витриной noctalia и лежат в git как есть, со своими apply.sh.
  themeTemplates = pkgs.runCommand "theme-templates" { } ''
    cp -r ${./theme-templates} $out
    chmod u+w $out
    cp ${userTemplates} $out/user.toml
  '';

  # PATH — для noctalia, hyprctl и apply.sh шаблонов (cmp, pgrep, python3 —
  # obsidian, dconf — gtk). Хук зовётся из сервисов caelestia и таймера.
  themeSync = pkgs.writeShellApplication {
    name = "caelestia-theme-sync";
    runtimeInputs = [ noctalia osConfig.programs.hyprland.package ] ++ (with pkgs; [
      bash coreutils findutils gnugrep gnused gawk diffutils procps python3 dconf
    ]);
    text = "THEME_TEMPLATES=${themeTemplates}\n" + builtins.readFile ./caelestia/theme-sync.sh;
  };
in

# =============================================================
# Рабочий стол «Hyprland + Caelestia» — пользовательская часть.
# Подключается из modules/hyprland.nix, а не из home.nix: стол
# переключается одной строкой в modules/common.nix.
#
# Бинды перенесены из home/umbriel/config.toml один в один там, где у
# Hyprland есть аналог; настройки шелла — перенос из home/noctalia.nix.
# Цвета от обоев: caelestia → шелл и рамки, theme-sync → приложения.
# Справка: https://wiki.hypr.land  Проверка: hyprctl configerrors
# =============================================================

{
  imports = [ inputs.caelestia-shell.homeManagerModules.default ];

  # Шелл стартует systemd-юнитом на graphical-session.target (его поднимает
  # hyprland-session.target ниже), не через exec-once.
  # Перезапуск: systemctl --user restart caelestia
  programs.caelestia = {
    enable = true;
    package = caelestiaShell;
    cli.enable = true;   # `caelestia` — скриншоты, буфер, запись, схемы

    # Иконки в окнах шелла (выбор файла и т. п.) Quickshell берёт из темы
    # иконок Qt, а платформенной темы Qt тут нет — вместо иконок были
    # розово-чёрные «нет текстуры». Тема — та же, что у GTK (home.nix).
    systemd.environment = [ "QS_ICON_THEME=${config.gtk.iconTheme.name}" ];

    # ~/.config/caelestia/cli.json. Схема «dynamic» (от обоев) включается
    # разово: caelestia scheme set -n dynamic. Светлая/тёмная и вариант
    # схемы Caelestia выбирает по картинке сама (services.smartScheme).
    cli.settings = {
      # Приложения красит theme-sync (шаблоны noctalia). Из встроенного у
      # Caelestia оставлены только рамки Hyprland и vesktop (тему включить
      # разово в самом vesktop: Settings → Themes → caelestia).
      # Выключено: term/gtk/btop — их делают шаблоны noctalia, и встроенные
      # переписали бы их файлы; qt — нет qtengine; остальное не установлено.
      theme = {
        enableHypr = true;
        enableDiscord = true;
        enableTerm = false;
        enableGtk = false;
        enableQt = false;
        enableBtop = false;
        enableSpicetify = false;
        enablePandora = false;
        enableFuzzel = false;
        enableNvtop = false;
        enableHtop = false;
        enableWarp = false;
        enableChromium = false;
        enableZed = false;
        enableCava = false;
      };
      wallpaper.postHook = "${themeSync}/bin/caelestia-theme-sync";
    };

    # Генерируется в ~/.config/caelestia/shell.json — read-only симлинк,
    # так что окно настроек (Nexus) сохранять не может: как с noctalia,
    # покрутил там — перенёс сюда. Справка по ключам — README шелла,
    # раздел «Example configuration».
    settings = {
      general.apps.terminal = [ "kitty" ];

      # Как было в noctalia: блокировка через 10 мин, экран гаснет через 11,
      # без сна. Заводское у Caelestia — 3 / 5 / suspendThenHibernate на 10.
      general.idle.timeouts = [
        { timeout = 600; idleAction = "lock"; }
        { timeout = 660; idleAction = "dpms off"; returnAction = "dpms on"; }
      ];

      # Те же обои, что были у noctalia (раскладываются из ~/nixos/wallpapers,
      # см. home.nix). Заводское — ~/Pictures/Wallpapers.
      paths.wallpaperDir = "~/Pictures/wallpaper";

      # Полупрозрачные панели; размытие под ними — layer_rule ниже.
      appearance.transparency.enabled = true;

      # Пустые столы не показываются.
      bar.workspaces.showUnoccupied = false;

      # Часы на столе — слева сверху, где стояли в noctalia.
      background.desktopClock = { enabled = true; position = "top-left"; };

      # Гибрид с NVIDIA (ноут): график GPU в панели — по iGPU из sysfs.
      # Auto выбрал бы nvidia-smi раз в секунду, а он будит спящую dGPU.
      services = lib.mkIf osConfig.hardware.nvidia.prime.offload.enable {
        gpuType = "Generic";
      };

      # Список заменяется целиком, поэтому перечислены все заводские значки.
      # Отличия: kbLayout (раскладка, по умолчанию выкл.) и батарея только
      # там, где она есть.
      bar.statusIcons = [
        { id = "lockStatus"; enabled = true; }
        { id = "audio"; enabled = false; }
        { id = "microphone"; enabled = false; }
        { id = "kbLayout"; enabled = true; }
        { id = "network"; enabled = true; }
        { id = "bluetooth"; enabled = true; }
        { id = "battery"; enabled = osConfig.local.hasBattery; }
      ];
    };
  };

  # Агент polkit: окна «введите пароль» для GUI (монтирование в Thunar и
  # т. п.). В noctalia он был встроен, в Caelestia его нет.
  services.hyprpolkitagent.enable = true;

  # Смена обоев раз в 30 минут, случайно — как automation в noctalia.
  # Цвета шелла и приложений едут следом (см. theme-sync выше).
  # Сменить сразу: systemctl --user start caelestia-wallpaper
  systemd.user.services.caelestia-wallpaper = {
    Unit.Description = "Случайные обои Caelestia";
    Service = {
      Type = "oneshot";
      ExecStart = "${config.programs.caelestia.cli.package}/bin/caelestia wallpaper -r ${config.home.homeDirectory}/Pictures/wallpaper";
    };
  };
  systemd.user.timers.caelestia-wallpaper = {
    Unit.Description = "Случайные обои Caelestia раз в 30 минут";
    Timer = { OnActiveSec = "30min"; OnUnitActiveSec = "30min"; };
    Install.WantedBy = [ "timers.target" ];
  };

  # История буфера для `caelestia clipboard` (Mod+V).
  services.cliphist.enable = true;

  wayland.windowManager.hyprland = {
    enable = true;
    # Пакет и портал — из programs.hyprland (modules/hyprland.nix), здесь
    # только конфиг, иначе две разные сборки.
    package = null;
    portalPackage = null;
    # Всё окружение сессии — в systemd: приложения из лаунчера Caelestia
    # (он systemd-юнит) должны видеть те же переменные, что и терминал.
    systemd.variables = [ "--all" ];

    # Конфиг — Lua (hyprland.lua; формат по умолчанию с home.stateVersion
    # 26.05). Каждый ключ settings — вызов hl.<ключ>(…), так что
    # settings.config → hl.config({ … }).
    settings.config = {
      input = {
        # ru-latin и custom:types — своя раскладка из ~/.config/xkb, хоткеи
        # с Ctrl/Alt/Super в русской группе как в английской (см. home.nix).
        kb_layout = "us,ru-latin";
        kb_options = "grp:caps_toggle,custom:types";
        numlock_by_default = true;
        touchpad.natural_scroll = true;
      };

      general = {
        # Обычный тайлинг. Лента колонок (scrolling) и «как в KDE» — режимы
        # отдельных столов, Mod+W (./hyprland/modes.lua).
        layout = "dwindle";
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
      };
      # Для столов в режиме scroll.
      scrolling = {
        column_width = 0.5;
        explicit_column_widths = "0.33333, 0.5, 0.66667";
      };
      decoration.rounding = 16;

      misc = {
        # Свои обои и логотип Hyprland не нужны — фон рисует Caelestia.
        disable_hyprland_logo = true;
        force_default_wallpaper = 0;
      };

      plugin = {
        # Обзор столов, Mod+O (binds.lua). Сетка 3×3 — столы 1–9.
        hyprtasking = {
          layout = "grid";
          gap_size = 20;
          grid = { rows = 3; cols = 3; };
        };
        # Заголовки окон; цвета от обоев и кнопки — ./hyprland/bars.lua.
        hyprbars = {
          bar_height = 28;
          bar_text_font = "Rubik";
          bar_text_size = 11;
          bar_padding = 10;
          bar_button_padding = 8;
          bar_blur = true;
          bar_precedence_over_border = true;
          on_double_click = "hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"toggle\" })'";
        };
      };
    };

    # Плагины грузятся до extraLuaFiles, так что hl.plugin.* там уже есть.
    # Собраны под тот же Hyprland из nixpkgs, что и programs.hyprland.
    plugins = with pkgs.hyprlandPlugins; [ hyprtasking hyprbars ];

    # Заголовки — только у плавающих окон (правило динамическое: снял
    # float — заголовок пропал).
    settings.window_rule = [{
      name = "hyprbars-tiled";
      match.float = false;
      "hyprbars:no_bar" = true;
    }];

    # Размытие под полупрозрачными панелями Caelestia. Бар и все выезжающие
    # панели — один слой caelestia-drawers на весь экран; ignore_alpha
    # не размывает его прозрачную часть (иначе мутным стал бы весь экран).
    settings.layer_rule = [{
      name = "caelestia-blur";
      match.namespace = "^caelestia-drawers$";
      blur = true;
      ignore_alpha = 0.57;
    }];

    # Мониторы и автозапуск под них — hosts/<машина>/hyprland.lua,
    # бинды — ./hyprland/binds.lua, режимы столов — ./hyprland/modes.lua,
    # заголовки окон — ./hyprland/bars.lua. Все подключаются require'ом.
    extraLuaFiles = {
      host = osConfig.local.hyprlandOutputs;
      binds = ./hyprland/binds.lua;
      colors = ./hyprland/colors.lua;
      modes = ./hyprland/modes.lua;
      bars = ./hyprland/bars.lua;
    };
  };
}
