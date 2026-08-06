{ config, osConfig, lib, inputs, ... }:

let
  # Машинозависимое — из опций local.* (объявлены в modules/options.nix,
  # заданы в hosts/<машина>/default.nix). osConfig — конфиг системы.
  inherit (osConfig.local)
    primaryOutput outputs hasBattery flakeAttr notificationScale osdScale;
  scr = osConfig.local.screen;

  # Координаты виджетов — в ЛОГИЧЕСКИХ пикселях, от центра виджета.
  # Те, что прижаты к левому верхнему углу, остаются числами: на любом
  # экране они окажутся там же. А вот прижатые к центру, к низу и к
  # правому краю обязаны считаться от размера экрана, иначе на другом
  # мониторе уедут.
  centerX = scr.width * 1.0 / 2;
  fromRight = margin: scr.width * 1.0 - margin;
  fromBottom = margin: scr.height * 1.0 - margin;
in

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
        font_family = "LythMonoTerm Nerd Font";
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
        wallpaper_scheme = "soft";
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

          # Тема Claude Code. Формат — свой, кастомные темы он читает из
          # ~/.claude/themes/*.json, имя файла становится slug'ом. Каталог
          # noctalia создаст сама, а post_hook не нужен: Claude Code держит
          # каталог тем под watcher'ом и перекрашивает даже открытую сессию.
          # Включается разово: "theme": "custom:noctalia" в
          # ~/.claude/settings.json (или /theme). Сам settings.json вне git —
          # Claude Code пишет в него сам, как noctalia в свой state.
          user.claude = {
            input_path = "${./claude/theme.json.in}";
            output_path = "~/.claude/themes/noctalia.json";
          };
        };
      };

      # ---- Обои ----------------------------------------------------
      wallpaper = {
        automation.enabled = true;
        # Папка, из которой шелл предлагает обои и крутит их автоматикой.
        # Сами картинки лежат в git (~/nixos/wallpapers) и раскладываются
        # по этому пути через home.file — см. home.nix. Путь оставлен
        # прежним, абсолютным: он же прописан в state, и подмена его на
        # store-путь протухала бы при каждой смене набора обоев.
        directory = "/home/artur/Pictures/wallpaper";
        # Обои по умолчанию — только ЗАТРАВКА для чистой машины, где ещё
        # пуст state: путь берётся из самого пакета, чтобы файл заведомо
        # существовал и не протух после обновления noctalia.
        #
        # Ставить сюда конкретную картинку из ~/Pictures бессмысленно, и
        # это проверено: при automation.enabled ротация переписывает
        # wallpaper.default.path в state на очередные обои, а state
        # перекрывает этот файл. Значение в git расходилось бы с реальным
        # уже через несколько минут.
        default.path = "${config.programs.noctalia.package}/share/noctalia/assets/noctalia-wallpaper.png";
        # wallpaper.last и wallpaper.monitors.* по той же причине НЕ
        # объявлены: чистое runtime-состояние.
      };

      # ---- Бар -----------------------------------------------------
      bar.default = {
        capsule = true;
        margin_ends = 0;
        start = [ "group:g1" "wallpaper" "pulse" "nix-monitor" "keyboard_layout" ];
        center = [ "workspaces" "cat" ];
        # battery — только там, где батарея есть: на десктопе виджет
        # показывал бы пустоту.
        end = [
          "control-center"
          "tray"
          "media"
          "network"
          "volume"
          "bluetooth"
        ]
        ++ lib.optional hasBattery "battery"
        ++ [ "session" ];
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
      # Раньше код плагинов ставила витрина — клонировала репозитории в
      # ~/.local/state/noctalia/plugins/ и раскладывала копии. На новой
      # машине это пришлось бы повторять кликами.
      #
      # Теперь оба репозитория пиннятся во flake, а сюда прописываются
      # источниками вида kind = "path": для них noctalia читает файлы
      # плагина ПРЯМО из каталога источника (src/scripting/plugin_file_cache.cpp),
      # ничего не клонируя и никуда не записывая, — а каталог в /nix/store
      # ровно такой, только read-only. Раскладка репозиториев (<плагин>/plugin.toml)
      # совпадает с тем, что ждёт сканер (src/scripting/plugin_catalog.cpp).
      #
      # Имена источников оставлены заводскими (official/community): под ними
      # плагины уже прописаны в состоянии и в витрине.
      #
      # ЦЕНА РЕШЕНИЯ: кнопка Update в витрине больше ничего не делает — она
      # умеет только git-источники. Обновление плагинов теперь такое:
      #   nix flake update noctalia-community-plugins && rebuild
      plugins = {
        auto_update = false;   # обновляет git-источники; здесь их нет
        source = [
          {
            name = "official";
            kind = "path";
            location = "${inputs.noctalia-official-plugins}";
          }
          {
            name = "community";
            kind = "path";
            location = "${inputs.noctalia-community-plugins}";
          }
        ];

        # Какие из доступных плагинов включены. Их внешние зависимости
        # (bw, python3, playerctl, evtest) — в modules/common.nix;
        # без них плагин молча мёртв.
        enabled = [
          "noctalia/bitwarden"
          "noctalia/bongocat"
          "lowcache/claude-companion"
          "avivbintangaringga/nix-monitor"
        ];
      };

      plugin_settings."avivbintangaringga/nix-monitor" = {
        # Кнопка Update. Порядок намеренный: бамп lock → КОММИТ → rebuild,
        # чтобы поколение всегда отвечало коммиту. Коммитится только
        # flake.lock, прочие правки в дереве не затрагиваются.
        # Имя хоста во флейке подставляется из local.flakeAttr: у машин
        # разные цели сборки, а команда одна.
        update_command =
          "cd /home/artur/nixos"
          + " && nix flake update"
          + " && git commit -m 'flake.lock: bump (via nix-monitor)' -- flake.lock"
          + " && sudo nixos-rebuild switch --flake .#${flakeAttr}";
      };

      # ---- Уведомления и OSD ---------------------------------------
      # Зависит от плотности экрана: на hidpi-панели ноута заводской
      # размер великоват (там 0.7), на обычном 1080p — в самый раз.
      notification.scale = notificationScale;
      osd.scale = osdScale;

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
      # ВНИМАНИЕ: output прибит к ИМЕНИ выхода — если имя не совпадёт,
      # виджет просто не появится, без единого сообщения. Имя берётся из
      # local.primaryOutput. На гибридном ноуте имена ещё и скакали между
      # загрузами (eDP-1 / eDP-2) — вылечено порядком загрузки модулей DRM,
      # см. boot.initrd.kernelModules в hosts/laptop/default.nix.
      # cx/cy — координаты центра в логических пикселях.
      desktop_widgets = {
        schema_version = 2;
        widget_order = [
          "desktop-widget-0000000000000001"
          "desktop-widget-0000000000000002"
          "desktop-widget-0000000000000003"
          "desktop-widget-0000000000000004"
          "desktop-widget-0000000000000005"
          "desktop-widget-0000000000000006"
          "desktop-widget-0000000000000007"
        ];
        grid = { visible = true; cell_size = 16; major_interval = 4; };
        widget = {
          # часы
          desktop-widget-0000000000000001 = {
            type = "clock";
            output = primaryOutput;
            cx = 247.0; cy = 130.5;
            box_width = 384.0; box_height = 128.0;
            rotation = 0.0;
            settings = {
              clock_style = "digital";
              font_family = "LythMonoTerm Nerd Font";
              center_text = false;
              background = false;
              background_radius = 0;
              shadow = true;
              timezone = "";
            };
          };
          # монитор ресурсов: RAM + CPU графиком
          desktop-widget-0000000000000002 = {
            type = "sysmon";
            output = primaryOutput;
            cx = 151.0; cy = 258.5;
            box_width = 192.0; box_height = 128.0;
            rotation = 0.0;
            settings = {
              display = "graph";
              gauge_layout = "horizontal";
              stat = "ram_pct";
              stat2 = "cpu_usage";
              background = true;
              background_radius = 0;
            };
          };
          # визуализатор звука — по центру, у нижнего края
          desktop-widget-0000000000000003 = {
            type = "audio_visualizer";
            output = primaryOutput;
            cx = centerX; cy = fromBottom 130.5;
            box_width = 0.0; box_height = 0.0;
            rotation = 0.0;
            settings = { bands = 32; show_when_idle = true; };
          };
          # погода (координаты — из location.auto_locate)
          desktop-widget-0000000000000004 = {
            type = "weather";
            output = primaryOutput;
            cx = 247.0; cy = 402.5;
            box_width = 384.0; box_height = 160.0;
            rotation = 0.0;
            settings = {
              show_forecast = true;
              background = false;
              background_radius = 0;
            };
          };
          # орб claude-companion: дышит в такт сессии Claude Code
          desktop-widget-0000000000000005 = {
            type = "lowcache/claude-companion:orb";
            output = primaryOutput;
            cx = 343.0; cy = 258.5;
            box_width = 192.0; box_height = 128.0;
            rotation = 0.0;
            settings = {
              background = true;
              background_radius = 0;
            };
          };
          # Сеть двумя стрелками-циферблатами у правого края: приём и
          # отдача разнесены по разным виджетам, потому что у sysmon на
          # циферблате помещается одна величина плюс вторая мелким
          # шрифтом (здесь — температура CPU под приёмом).
          desktop-widget-0000000000000006 = {
            type = "sysmon";
            output = primaryOutput;
            cx = fromRight 118.0; cy = 98.5;
            box_width = 128.0; box_height = 64.0;
            rotation = 0.0;
            settings = {
              display = "gauge";
              stat = "net_rx";
              stat2 = "cpu_temp";
              background = false;
            };
          };
          desktop-widget-0000000000000007 = {
            type = "sysmon";
            output = primaryOutput;
            cx = fromRight 118.0; cy = 162.5;
            box_width = 128.0; box_height = 64.0;
            rotation = 0.0;
            settings = {
              display = "gauge";
              stat = "net_tx";
              stat2 = "";
              background = false;
            };
          };
        };
      };

      # ---- Виджеты локскрина ---------------------------------------
      # Форма ввода пароля кладётся на КАЖДЫЙ выход машины: на многомониторной
      # сборке иначе пришлось бы угадывать, на каком экране появится ввод.
      # Раньше здесь была ручная пара @eDP-1/@eDP-2 — страховка от чехарды
      # имён на гибриде; теперь список выходов берётся из local.outputs.
      lockscreen_widgets =
        let
          loginBox = out: {
            type = "login_box";
            output = out;
            cx = centerX; cy = fromBottom 119.0;
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
          # ВЫКЛЮЧЕНО (перенесено из state, 2026-07-29): на экране блокировки
          # своя раскладка виджетов не используется, работает заводская.
          # Описание формы ввода ниже оставлено — включается сменой этой
          # строки на true, и тогда она разложится по всем выходам машины.
          enabled = false;
          schema_version = 2;
          widget_order = map (out: "lockscreen-login-box@${out}") outputs;
          grid = { visible = true; cell_size = 16; major_interval = 4; };
          widget = lib.listToAttrs (
            map (out: lib.nameValuePair "lockscreen-login-box@${out}" (loginBox out)) outputs
          );
        };
    };
  };
}
