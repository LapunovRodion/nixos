{ config, ... }:

# =============================================================
# noctalia — шелл: бар, док, виджеты рабочего стола, локскрин,
# тема, шаблоны тем, плагины.
#
# ЕДИНСТВЕННЫЙ ИСТОЧНИК ПРАВДЫ — этот файл.
#
# У noctalia два конфига, и они склеиваются в таком порядке
# (src/config/config_validate.cpp): сначала config-dir *.toml
# (его генерирует отсюда home-manager, read-only симлинк в
# /nix/store), ПОТОМ state-dir settings.toml — и он перекрывает.
# В state пишет GUI настроек, при любом клике.
#
# Поэтому договорённость: ~/.local/state/noctalia/settings.toml
# держим ПУСТЫМ. Настройки GUI — это черновик: покрутил, понравилось —
# перенёс сюда и закоммитил, иначе следующая чистка state всё сотрёт.
# Посмотреть, что накрутил GUI:  noctalia config export merged
#
# Разбор — в хранилище, [[08 - Кастомизация (rice)]].
# =============================================================

{
  programs.noctalia = {
    enable = true;
    systemd.enable = true; # автозапуск как user-сервис

    settings = {

      # ---- Оболочка ------------------------------------------------
      shell = {
        font_family = "JetBrainsMono Nerd Font";
        lang = "ru";
        app_icon_color = "primary";
        polkit_agent = true; # агент авторизации: без него sudo-диалоги GUI не всплывают
        password_style = "random";
        screen_time_enabled = true;
        # приложения из шелла — как systemd-юниты, иначе умирают при рестарте
        # сервиса. Ключ живёт именно в [shell]: на верхнем уровне noctalia
        # писала «unknown section» и молча игнорировала.
        launch_apps_as_systemd_services = true;

        # Панели (лаунчер, control center, буфер, сессия) — стеклянные.
        # solid → soft → glass: у glass фон полупрозрачный и карточки
        # внутри панели тоже просвечивают. Работает вместе с [backdrop]
        # ниже: панель прозрачная, а десктоп под ней размыт.
        panel.transparency_mode = "glass";
      };

      # ---- Backdrop ------------------------------------------------
      # Слой между десктопом и открытой панелью: размывает и подкрашивает
      # ВСЁ, что под ней. Без него стекло показывает резкую картинку и
      # текст на панели читается плохо.
      backdrop = {
        enabled = true;
        blur_intensity = 0.5; # 0.0 — без размытия, 1.0 — максимум
        tint_intensity = 0.3; # подкраска цветом surface поверх размытия
      };

      # ---- Тема ----------------------------------------------------
      theme = {
        mode = "dark";
        # Палитра генерируется ИЗ ОБОЕВ (Material You), а не берётся готовой.
        source = "wallpaper";
        wallpaper_scheme = "m3-content";
        # Запасные варианты — не действуют, пока source = "wallpaper",
        # но сохранены как выбор: на них переключаться сменой source.
        builtin = "Gruvbox";
        community_palette = "Oxocarbon";

        # Шаблоны: noctalia рендерит текущую палитру в конфиги чужих
        # приложений. Пишет в СВОЙ файл (напр. ~/.config/kitty/themes/
        # noctalia.conf), а post_hook дописывает в главный конфиг строку
        # include. Перекрашивается всё разом при смене обоев.
        # Список id: noctalia theme --list-templates
        templates = {
          # "niri" из встроенных УБРАН намеренно: он пишет плоский
          # active-color, а мне нужна градиентная рамка фокуса. Вместо него
          # свой шаблон ниже, templates.user.niri — он покрывает всё, что
          # делал встроенный, плюс градиент. Держать оба нельзя: два файла
          # определяли бы один и тот же focus-ring.
          builtin_ids = [ "btop" "gtk3" "gtk4" "kitty" "qt" ];
          # telegram — под AyuGram (форк Telegram Desktop, формат палитры тот же).
          # ОСОБЫЙ СЛУЧАЙ: у этого шаблона нет post_hook, он только кладёт файл
          # ~/.config/telegram-desktop/themes/noctalia.tdesktop-theme. Сам Telegram
          # держит тему в tdata и файл с диска не перечитывает — импорт руками,
          # через Настройки → Чаты → ⋮ → Создать тему → Импортировать.
          # Значит и при смене палитры (source = "wallpaper") импорт надо повторять.
          community_ids = [ "zen-browser" "neovim" "obsidian" "fuzzel" "lazygit" "yazi" "telegram" ];

          # Свой шаблон niri. input_path абсолютный (путь в /nix/store),
          # так что noctalia берёт его как есть — resolveConfigPath
          # достраивает только относительные пути.
          # Файл в store read-only, но шаблон его лишь читает.
          # post_hook не нужен: строка include уже стоит в config.kdl,
          # а niri сам перечитывает конфиг при изменении файла.
          user.niri = {
            input_path = "${./niri/theme.kdl.in}";
            output_path = "~/.config/niri/noctalia-theme.kdl";
          };
        };
      };

      # ---- Обои ----------------------------------------------------
      wallpaper = {
        automation.enabled = true;
        # Путь берём из САМОГО ПАКЕТА, а не хардкодом в /nix/store:
        # иначе после обновления noctalia путь протухнет и обоев не будет.
        default.path = "${config.programs.noctalia.package}/share/noctalia/assets/noctalia-wallpaper.png";
        # wallpaper.last сознательно НЕ объявлен: это runtime-состояние,
        # его пишет сама noctalia при каждой смене обоев.
      };

      # ---- Бар -----------------------------------------------------
      bar.default = {
        capsule = true;
        margin_ends = 0;
        start = [ "group:g1" "wallpaper" "pulse" "nix-monitor" ];
        center = [ "workspaces" "cat" ];
        end = [
          "control-center"
          "tray"
          "media"
          "network"
          "volume"
          "bluetooth"
          "battery"
          "session"
        ];
        # Часы — отдельной «капсулой» на фоне surface_variant.
        capsule_group = [
          {
            id = "g1";
            enabled = true;
            members = [ "clock" ];
            fill = "surface_variant";
            opacity = 1.0;
            padding = 6.0;
          }
        ];
      };

      # Привязка имён виджетов бара к записям плагинов.
      # Без этих трёх строк "pulse"/"nix-monitor"/"cat" в списках выше —
      # просто неизвестные имена.
      widget = {
        pulse.type = "lowcache/claude-companion:pulse";
        nix-monitor.type = "avivbintangaringga/nix-monitor:nix-monitor";
        cat.type = "noctalia/bongocat:cat";
      };

      # ---- Док -----------------------------------------------------
      dock = {
        enabled = true;
        reserve_space = false; # не отъедать место у окон
        smart_auto_hide = true; # прячется, когда на воркспейсе есть окна
      };

      # ---- Плагины -------------------------------------------------
      # Код плагинов ставится витриной в ~/.local/state/noctalia/plugins/,
      # это НЕ декларативно. Здесь — какие из поставленных включены.
      # Их внешние зависимости (bw, python3, playerctl, evtest) — в
      # configuration.nix; без них плагин молча мёртв.
      plugins.enabled = [
        "noctalia/bitwarden"
        "noctalia/bongocat"
        "lowcache/claude-companion"
        "avivbintangaringga/nix-monitor"
      ];

      plugin_settings."avivbintangaringga/nix-monitor" = {
        # Кнопка Update. Порядок намеренный: бамп lock → КОММИТ → rebuild,
        # чтобы поколение всегда отвечало коммиту. Коммитится только
        # flake.lock, прочие правки в дереве не затрагиваются.
        update_command =
          "cd /home/artur/nixos"
          + " && nix flake update"
          + " && git commit -m 'flake.lock: bump (via nix-monitor)' -- flake.lock"
          + " && sudo nixos-rebuild switch --flake .#nixos";
      };

      # ---- Уведомления и OSD ---------------------------------------
      # 0.7 — экран 2880x1800 при scale 1.75, дефолтный размер великоват.
      notification.scale = 0.7;
      osd.scale = 0.7;

      # ---- Бездействие ---------------------------------------------
      idle = {
        behavior_order = [ "lock" "screen-off" "lock-and-suspend" ];
        behavior = {
          lock = { enabled = true; action = "lock"; timeout = 600.0; };
          screen-off = { enabled = true; action = "screen_off"; timeout = 660.0; };
          lock-and-suspend = { enabled = false; action = "lock_and_suspend"; timeout = 900.0; };
        };
      };

      location.auto_locate = true; # координаты по IP: погода + ночной режим

      # ---- Виджеты рабочего стола ----------------------------------
      # ВНИМАНИЕ: output прибит к имени выхода. На гибриде имена скакали
      # между загрузами (eDP-1 / eDP-2) и виджеты исчезали — вылечено
      # boot.initrd.kernelModules = [ "amdgpu" ] в configuration.nix.
      # cx/cy — координаты центра в логических пикселях.
      desktop_widgets = {
        schema_version = 2;
        widget_order = [
          "desktop-widget-0000000000000001"
          "desktop-widget-0000000000000002"
          "desktop-widget-0000000000000003"
          "desktop-widget-0000000000000004"
          "desktop-widget-0000000000000005"
        ];
        grid = { visible = true; cell_size = 16; major_interval = 4; };
        widget = {
          # часы
          desktop-widget-0000000000000001 = {
            type = "clock";
            output = "eDP-1";
            cx = 247.0; cy = 130.5;
            box_width = 384.0; box_height = 128.0;
            rotation = 0.0;
            settings = {
              clock_style = "digital";
              font_family = "JetBrainsMono Nerd Font";
              center_text = false;
              background_radius = 0;
              shadow = true;
              timezone = "";
            };
          };
          # монитор ресурсов: RAM + CPU графиком
          desktop-widget-0000000000000002 = {
            type = "sysmon";
            output = "eDP-1";
            cx = 151.0; cy = 258.5;
            box_width = 192.0; box_height = 128.0;
            rotation = 0.0;
            settings = {
              display = "graph";
              gauge_layout = "horizontal";
              stat = "ram_pct";
              stat2 = "cpu_usage";
              background_radius = 0;
            };
          };
          # визуализатор звука
          desktop-widget-0000000000000003 = {
            type = "audio_visualizer";
            output = "eDP-1";
            cx = 823.0; cy = 898.5;
            box_width = 0.0; box_height = 0.0;
            rotation = 0.0;
            settings = { bands = 32; show_when_idle = true; };
          };
          # погода (координаты — из location.auto_locate)
          desktop-widget-0000000000000004 = {
            type = "weather";
            output = "eDP-1";
            cx = 247.0; cy = 402.5;
            box_width = 384.0; box_height = 160.0;
            rotation = 0.0;
            settings = { show_forecast = true; background_radius = 0; };
          };
          # орб claude-companion: дышит в такт сессии Claude Code
          desktop-widget-0000000000000005 = {
            type = "lowcache/claude-companion:orb";
            output = "eDP-1";
            cx = 343.0; cy = 258.5;
            box_width = 192.0; box_height = 128.0;
            rotation = 0.0;
            settings.background_radius = 0;
          };
        };
      };

      # ---- Виджеты локскрина ---------------------------------------
      # Форма ввода пароля продублирована на оба имени выхода — это
      # обход той же чехарды eDP-1/eDP-2, который noctalia сделала сама.
      # После фикса initrd имя стабильно eDP-1, запись @eDP-2 можно
      # выкинуть — оставлена как страховка, ничего не стоит.
      lockscreen_widgets =
        let
          loginBox = out: {
            type = "login_box";
            output = out;
            cx = 823.0; cy = 910.0;
            box_width = 400.0; box_height = 70.0;
            rotation = 0.0;
            settings = {
              background_color = "surface_variant";
              background_opacity = 0.88;
              background_radius = 12.0;
              center_password_text = false;
              input_opacity = 1.0;
              input_radius = 6.0;
              show_caps_lock = true;
              show_keyboard_layout = true;
              show_login_button = true;
              show_password_hint = true;
            };
          };
        in
        {
          enabled = true;
          schema_version = 2;
          widget_order = [ "lockscreen-login-box@eDP-1" "lockscreen-login-box@eDP-2" ];
          grid = { visible = true; cell_size = 16; major_interval = 4; };
          widget = {
            "lockscreen-login-box@eDP-1" = loginBox "eDP-1";
            "lockscreen-login-box@eDP-2" = loginBox "eDP-2";
          };
        };
    };
  };
}
