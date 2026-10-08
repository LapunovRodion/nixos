{ config, osConfig, lib, pkgs, inputs, ... }:

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

  # Плагины сообщества — как есть из flake-входа, кроме точечных правок
  # под read-only /nix/store. Каталог плагина (pluginDir) здесь лежит в
  # сторе, а некоторые плагины пишут прямо в него:
  #   qrcode — кладёт qr-N.png рядом со своим кодом и падает с
  #            «failed to generate the QR code». Переводим на pluginDataDir():
  #            ~/.local/state/noctalia/plugins/data/yocraft/qrcode,
  #            noctalia сама создаёт каталог.
  #   web-search — держит кэш недавних запросов в pluginDir/cache; без
  #            правки запись молча не проходит и история не запоминается.
  # --replace-fail: если апстрим поправит сам, сборка упадёт и напомнит
  # убрать правку.
  communityPlugins = pkgs.applyPatches {
    name = "noctalia-community-plugins";
    src = inputs.noctalia-community-plugins;
    postPatch = ''
      substituteInPlace qrcode/panel.luau \
        --replace-fail 'noctalia.pluginDir()' 'noctalia.pluginDataDir()'
      substituteInPlace web-search/*.luau \
        --replace-fail 'noctalia.pluginDir()' 'noctalia.pluginDataDir()'
    '';
  };

  # Чистка state-файла перед стартом — см. ExecStartPre внизу файла.
  noctaliaStateReset = pkgs.writers.writePython3Bin "noctalia-state-reset" { } (
    builtins.readFile ./noctalia-state-reset.py
  );

  # post_hook шаблона kitty: рисует картинку-градиент из цветов свежей
  # палитры. Разбор — в самом скрипте. writeShellApplication добавляет
  # шебанг и `set -euo pipefail` и прогоняет shellcheck при сборке,
  # поэтому в файле их нет.
  #
  # runtimeInputs обязателен целиком: хук запускается из user-сервиса
  # noctalia, где PATH минимальный, — coreutils и findutils оттуда не
  # взять. imagemagick при этом в systemPackages не нужен, он приезжает
  # замыканием этой обёртки.
  kittyGradient = pkgs.writeShellApplication {
    name = "kitty-gradient";
    runtimeInputs = with pkgs; [ imagemagick coreutils findutils procps gawk ];
    text = builtins.readFile ./kitty/gradient.sh;
  };
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
# Поэтому договорённость: настройки GUI — это черновик. Покрутил,
# понравилось — перенёс сюда и закоммитил. Теперь это не на честном
# слове: перед каждым стартом noctalia (ExecStartPre внизу) из state
# выбрасывается всё, кроме текущих обоев, — то есть до перезапуска
# шелла или перезагрузки. Накрученное в прошлой сессии лежит в
# ~/.local/state/noctalia/settings.toml.prev.
# Посмотреть, что накрутил GUI сейчас:  noctalia config export merged
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
        # Rubik — шрифт Caelestia (ставится в modules/common.nix, fonts).
        font_family = "Rubik";
        lang = "ru";
        app_icon_color = "primary";
        polkit_agent = true; # агент авторизации: без него sudo-диалоги GUI не всплывают
        password_style = "random";
        screen_time_enabled = true;
        # приложения из шелла — как systemd-юниты, иначе умирают при рестарте
        # сервиса. Ключ живёт именно в [shell]: на верхнем уровне noctalia
        # писала «unknown section» и молча игнорировала.
        launch_apps_as_systemd_services = true;

        # ---- В духе Caelestia (выбрано 2026-10-08 в конфигураторе) ----
        # Скругления всего шелла крупнее заводских: 0 — квадрат, 2 — максимум.
        corner_radius_scale = 1.5;

        # Подписи раскладок двумя буквами (виджет keyboard_layout в баре).
        # Имена точные, из `umbriel keyboard-layouts`: ru-latin xkb
        # называет «Russian (latin fallback)».
        keyboard_layout.custom_labels = {
          "English (US)" = "EN";
          "Russian (latin fallback)" = "RU";
        };

        # Панели «мягкие»: solid → soft → glass. Чуть прозрачные, размытие
        # под ними даёт [backdrop] ниже и layer_rule в umbriel/config.toml.
        # Все выезжают из бара (attached), как ящики Caelestia, а не
        # всплывают по центру; contact_shadow у бара прячет шов.
        panel = {
          transparency_mode = "soft";
          launcher_placement = "attached";
          clipboard_placement = "attached";
          control_center_placement = "attached";
          session_placement = "attached";
        };

        # Множитель скорости ВСЕХ анимаций шелла (панели, лаунчер Mod+D,
        # OSD): длительность делится на него (animation_manager.cpp), 2.0 —
        # вдвое быстрее заводского. Диапазон 0.1–4.0. Совсем без анимаций —
        # animation.enabled = false. Было 2.0; под Caelestia — заводская
        # скорость, чтобы выезд панелей из бара был виден.
        animation.speed = 1.0;
      };

      # ---- Backdrop ------------------------------------------------
      # Слой между десктопом и открытой панелью: размывает и подкрашивает
      # ВСЁ, что под ней.
      #
      # ВКЛЮЧЁН с переездом на Umbriel. В niri он был выключен: обои там
      # лежали в backdrop композитора, и этот слой размывал их ПОСТОЯННО.
      # В Umbriel обои — обычный background-слой, проблемы нет.
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
        # m3-content — ближе всего к цветам самих обоев. Было "soft".
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
          # "kitty" УБРАН по двум причинам, что расписаны в шапке
          # kitty/theme.conf.in: встроенный берёт terminal_background как
          # есть (сильно подкрашенный обоями), а его apply.sh дописывает
          # строку include в ~/.config/kitty/kitty.conf — read-only симлинк
          # на /nix/store. Хук падал на первом же touch («Permission
          # denied» в journalctl --user -u noctalia при каждой ротации
          # обоев), и pkill -USR1 в его конце никогда не выполнялся:
          # открытые окна не перекрашивались. Держать оба нельзя — два
          # шаблона писали бы один и тот же themes/noctalia.conf.
          builtin_ids = [ "btop" "gtk3" "gtk4" "qt" ];
          # telegram — под AyuGram (форк Telegram Desktop, формат палитры тот же).
          # ОСОБЫЙ СЛУЧАЙ: у этого шаблона нет post_hook, он только кладёт файл
          # ~/.config/telegram-desktop/themes/noctalia.tdesktop-theme. Сам Telegram
          # держит тему в tdata и файл с диска не перечитывает — импорт руками,
          # через Настройки → Чаты → ⋮ → Создать тему → Импортировать.
          # Значит и при смене палитры (source = "wallpaper") импорт надо повторять.
          #
          # "neovim" УБРАН намеренно, и это не уборка, а необходимость. Тема
          # редактора теперь статичная (см. home.nix, colorschemes.catppuccin),
          # то есть строки `pcall(require, 'matugen')` в init.lua больше нет.
          # А apply.sh этого шаблона, не найдя lazy.nvim, идёт во вторую ветку,
          # грепает init.lua ровно на эту строку и, не найдя её, дописывает
          # вызов сам — в read-only симлинк на /nix/store. Запись падает,
          # скрипт стоит на `set -euo pipefail`, и post_hook валится на каждой
          # смене обоев. Держать шаблон включённым можно только вместе с той
          # строкой; раз строки нет — нет и шаблона.
          community_ids = [ "zen-browser" "obsidian" "lazygit" "yazi" "telegram" ];

          # Umbriel — шаблон ВСТРОЕННЫЙ (из пакета noctalia), но подключён
          # как user: у builtin "umbriel" apply.sh дописывает include в
          # config.toml, а тот — read-only симлинк (та же беда, что с kitty).
          # Include уже стоит в home/umbriel/config.toml, Umbriel сам
          # перечитывает файл при изменении.
          user.umbriel = {
            input_path = "${config.programs.noctalia.package}/share/noctalia/assets/templates/umbriel/umbriel.toml";
            output_path = "~/.config/umbriel/noctalia.toml";
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

          # Свой шаблон kitty вместо встроенного (см. builtin_ids выше).
          # output_path тот же, что был у встроенного, поэтому строку
          # include в home.nix менять не пришлось.
          #
          # post_hook рисует картинку-градиент фона и шлёт kitty SIGUSR1.
          # Читает он цвета из ТОЛЬКО ЧТО отрендеренного output_path —
          # маркерные строки в конце theme.conf.in кладутся ради него.
          user.kitty = {
            input_path = "${./kitty/theme.conf.in}";
            output_path = "~/.config/kitty/themes/noctalia.conf";
            post_hook = "${kittyGradient}/bin/kitty-gradient";
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
      # Плавающий «остров» сверху: отступ от края и от концов экрана.
      # Набор виджетов — как у Caelestia: лаунчер и столы, заголовок окна
      # по центру, статус и часы справа. Прежний набор (плагины nix-monitor,
      # nix-status, pulse, media, раскладка, часы капсулой) — в git-истории.
      # control-center оставлен сверх Caelestia: иначе центр управления
      # (медиа, погода, графики) открыть нечем.
      bar.default = {
        position = "top";
        thickness = 36; # было 44 — бар выходил слишком высоким
        margin_edge = 10;
        # Длиннее, чем было (180): плагинов в баре прибавилось.
        margin_ends = 80;
        # Иконки и текст на 20% крупнее заводских — мелкие терялись.
        scale = 1.2;
        capsule = false;
        contact_shadow = true; # тень на шве бара и выехавшей из него панели
        # Часы и раскладка — слева, сразу за лаунчером.
        start = [ "launcher" "clock" "keyboard_layout" "workspaces" "umbriel-layout" ];
        center = [ "active_window" ];
        # battery — только там, где батарея есть: на десктопе виджет
        # показывал бы пустоту.
        # Плагины (см. plugins.enabled): агенты, игровой режим, процессы, OCR.
        end = [ "claude-cockpit" "gamer-mode" "procmon" "ocr" "tailscale" "tray" "network" "bluetooth" "volume" ]
          ++ lib.optional hasBattery "battery"
          ++ [ "control-center" "session" ];
      };

      # Привязка имён виджетов бара к записям плагинов.
      # Без этих строк "pulse"/"nix-monitor" в списках выше —
      # просто неизвестные имена.
      widget = {
        pulse.type = "lowcache/claude-companion:pulse";
        nix-monitor.type = "avivbintangaringga/nix-monitor:nix-monitor";
        nix-status.type = "mindnbytes/nix-status:status";
        umbriel-layout.type = "noctalia/umbriel-companion:bar";
        # В баре — только значок, без процентов лимитов (5 ч / неделя):
        # они остаются в панели по клику.
        claude-cockpit = {
          type = "nightwatch75/claude-cockpit:widget";
          usage_percent_display = "none";
        };
        gamer-mode.type = "nomadcxx/gamer-mode:gamermode";
        # Только значок CPU, без числа процессов рядом.
        procmon = {
          type = "weinguyen/procmon:widget";
          show_count = false;
        };
        ocr.type = "fel/ocr:ocr";
        tailscale.type = "davemhammer/tailscale:status";

        # Раскладка в баре — короткой подписью (сами подписи — в
        # shell.keyboard_layout.custom_labels выше).
        keyboard_layout.display = "short";

        # Пилюли с номерами; пустые столы не показываются.
        workspaces = {
          style = "regular";
          hide_when_empty = true;
        };
      };

      # ---- Док -----------------------------------------------------
      # Выключен: в Caelestia дока нет, запуск — лаунчером из бара.
      dock = {
        enabled = false;
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
        auto_update = "none";  # none | official | all; обновляет git-источники, здесь их нет
        source = [
          {
            name = "official";
            kind = "path";
            location = "${inputs.noctalia-official-plugins}";
          }
          {
            name = "community";
            kind = "path";
            location = "${communityPlugins}";  # с правками, см. let выше
          }
        ];

        # Какие из доступных плагинов включены. Их внешние зависимости
        # (bw, python3, playerctl, fzf, gdbus, nix-search-tv) — в
        # modules/common.nix; без них плагин молча мёртв.
        #
        # bongocat снят 2026-09-26 вместе с группой input: ради котика
        # любой процесс сессии мог читать сырые нажатия клавиатуры.
        enabled = [
          "noctalia/bitwarden"
          "lowcache/claude-companion"
          "avivbintangaringga/nix-monitor"
          # Значок в баре: ↻ — booted ≠ current (нужна перезагрузка, например
          # после обновления драйвера NVIDIA), ⇧ — ~/nixos собирается не в ту
          # систему, что запущена (есть незасвиченные правки). Клик — панель:
          # сравнение замыканий, обновление инпутов флейка.
          "mindnbytes/nix-status"
          # QR-код из текста/ссылки, офлайн (qrencode). Mod+Alt+Q в niri.
          "yocraft/qrcode"

          # ---- Выбрано 2026-10-08 на «полке плагинов» ----
          # Раскладка текущего стола Umbriel (scrolling/dwindle/master) и
          # подкарта клавиш рядом со столами — пара к Mod+W. Официальный.
          "noctalia/umbriel-companion"
          # Claude Code: лимиты подписки (5 ч / неделя), токены и стоимость;
          # все локальные сессии по проектам — resume в kitty одним кликом;
          # правка CLAUDE.md. Лимиты берёт у Anthropic по токену из
          # ~/.claude/.credentials.json — тем же запросом, что сам Claude Code.
          # (Был fel/agent-glow — снят 2026-10-08, этот нагляднее.)
          "nightwatch75/claude-cockpit"
          # Игровой режим: правый клик — приостановить фоновых «пожирателей»
          # (встроенный список: торренты, ollama, fstrim…) и включить
          # performance; повторно — вернуть как было. Левый клик — панель
          # с CPU/GPU/RAM. Свой список — настройка targets (JSON).
          "nomadcxx/gamer-mode"
          # Таблица процессов в стиле bottom: сортировка, поиск, kill.
          "weinguyen/procmon"
          # Выделил область → распознанный текст в буфере (tesseract,
          # языки — plugin_settings ниже, пакет — modules/common.nix).
          "fel/ocr"
          # Для стола (см. desktop_widgets): обратный отсчёт и стикеры.
          "noctalia/timer"
          "remo/noctes"
          # Tailscale: подключение, пиры, exit node, флаги — из бара. Права —
          # оператор в modules/common.nix (services.tailscale.extraSetFlags).
          "davemhammer/tailscale"

          # ---- Лаунчер (Mod+D): префикс + запрос ----
          # Встроенное без префикса: приложения, калькулятор с единицами и
          # валютами (`100 usd to byn`, курсы тянет сам, в т.ч. НБРБ), эмодзи,
          # окна, сессия.
          "noctalia/translator"        # /tr текст → en;  /tr ru hello → ru
          "notfinaldev/web-search"     # /web запрос; попадает и в общий поиск
          "knyrps/nix-search"          # /nix ripgrep — nixpkgs, опции NixOS и HM
          "nightwatch75/file-search"   # /fs отчёт — файлы по мере набора
          "weinguyen/shell-command"    # /sh htop — команда в терминале
          "srounce/systemd"            # /svc hysteria — start/stop/restart юнитов
          # game-launcher сознательно НЕ включён: при первом запуске он
          # компилирует свой C-код через `cc` в каталог плагина — мимо nix,
          # а каталог плагина тут read-only.
        ];
      };

      # Без flake_dir плагин умеет только поколения; с ним — ещё проверку
      # «конфиг ≠ запущенная система» и обновление инпутов.
      plugin_settings."mindnbytes/nix-status" = {
        flake_dir = "/home/artur/nixos";
        nixos_configuration = flakeAttr;
      };

      # Без них cockpit искал бы VS Code/Zed и сам выбирал терминал.
      # editor_command делится по пробелам, путь к CLAUDE.md дописывается в конец.
      plugin_settings."nightwatch75/claude-cockpit" = {
        terminal = "kitty";
        editor_command = "kitty -e nvim";
      };

      # Русский + английский разом: tesseract склеивает модели через «+».
      plugin_settings."fel/ocr".languages = "eng+rus";

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
      # Громкость/яркость — вертикальной полосой у правого края, как в
      # Caelestia (для вертикальной ориентации позиция — position_vertical).
      osd.orientation = "vertical";
      osd.position_vertical = "center_right";

      # Экран блокировки — на размытом снимке рабочего стола, а не на обоях.
      lockscreen.blurred_desktop = true;

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
      # Набор выбран 2026-10-08 в конструкторе стола, координаты выставлены
      # вручную в редакторе (noctalia msg desktop-widgets-edit) и перенесены
      # сюда из state: сам редактор пишет в ~/.local/state/noctalia/
      # settings.toml, а его чистит noctalia-state-reset при каждом старте.
      # Слева — часы и погода, справа — календарь, стикер, таймер, снизу —
      # визуализатор. Правый край и низ — через fromRight/fromBottom, чтобы
      # на экране ноута (1645×1029) виджеты не уехали за край.
      #
      # Визуализатор — только там, где нет батареи. 2026-09-24 powertop
      # показал: анимированные виджеты не дают экрану ноута 120 Гц
      # простаивать (kworker commit_work 64% CPU, 22–25 Вт в простое).
      # Остальные статичные — можно везде.
      desktop_widgets = {
        schema_version = 2;
        widget_order = [
          "desktop-widget-0000000000000004"
          "desktop-weather"
          "desktop-calendar"
          "desktop-timer"
          "desktop-note-1"
        ] ++ lib.optional (!hasBattery) "desktop-widget-0000000000000003";
        grid = { visible = true; cell_size = 16; major_interval = 4; };
        widget = {
          # часы: только время, по центру своей коробки, цветом primary,
          # шрифт — общий шелла (Rubik)
          desktop-widget-0000000000000004 = {
            type = "clock";
            output = primaryOutput;
            cx = 216.0; cy = 148.0;
            box_width = 304.0; box_height = 144.0;
            rotation = 0.0;
            settings = {
              clock_style = "digital";
              center_text = true;
              color = "primary";
              background = false;
            };
          };
          # погода с прогнозом на 3 дня (служба — weather.enabled ниже,
          # координаты — location.auto_locate)
          desktop-weather = {
            type = "weather";
            output = primaryOutput;
            cx = 247.0; cy = 316.0;
            box_width = 416.0; box_height = 208.0;
            rotation = 0.0;
            settings = {
              show_forecast = true;
              forecast_days = 3;
              shadow = true;
              background = false;
              background_radius = 0;
            };
          };
          # сетка месяца; событий нет, пока не подключён [calendar]
          desktop-calendar = {
            type = "calendar";
            output = primaryOutput;
            cx = fromRight 532.0; cy = 316.0;
            box_width = 384.0; box_height = 416.0;
            rotation = 0.0;
            settings = {
              show_events = false;
              show_week_numbers = false;
              background = true;
              background_opacity = 0.0;
              background_radius = 0;
            };
          };
          # Стикер remo/noctes. Объявлен ЗДЕСЬ, а не кнопкой «+» плагина:
          # плагин пишет листы в state, а его чистит noctalia-state-reset —
          # лист пропадал бы на каждом старте шелла. key — постоянная связь
          # с заметкой в notes.json плагина.
          desktop-note-1 = {
            type = "remo/noctes:note";
            output = primaryOutput;
            cx = fromRight 220.0; cy = 220.0;
            box_width = 240.0; box_height = 224.0;
            rotation = 0.0;
            settings = {
              key = "desk-1";
              background_opacity = 0.0;
              background_radius = 0;
            };
          };
          # таймер плагина noctalia/timer — тот же отсчёт, что в его панели
          desktop-timer = {
            type = "noctalia/timer:desktop";
            output = primaryOutput;
            cx = fromRight 220.0; cy = 428.0;
            box_width = 240.0; box_height = 192.0;
            rotation = 0.0;
            settings = {
              color = "primary";
              background = true;
              background_opacity = 0.0;
              background_padding = 0;
              background_radius = 0;
            };
          };
          # визуализатор звука — по центру у нижнего края (только desktop)
          desktop-widget-0000000000000003 = {
            type = "audio_visualizer";
            output = primaryOutput;
            cx = centerX; cy = fromBottom 108.0;
            box_width = 0.0; box_height = 0.0;
            rotation = 0.0;
            settings = { bands = 32; show_when_idle = true; };
          };
        };
      };

      # Служба погоды. Была выключена (заводское enabled = false), и виджет
      # погоды показывал заглушку. Координаты — location.auto_locate по IP.
      weather.enabled = true;

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
            # Размер коробки — заводской для v5: в неё теперь помещаются
            # медиа, погода и кнопки сессии, старые 400x70 были от формы
            # с одним полем ввода.
            box_width = 720.0; box_height = 196.0;
            # Разрешение, под которое посчитаны координаты: по нему noctalia
            # пересчитывает раскладку, если экран окажется другим.
            placement_width = scr.width * 1.0;
            placement_height = scr.height * 1.0;
            rotation = 0.0;
            settings = {
              background_color = "surface_variant";
              background_opacity = 0.88;
              background_radius = 12.0;
              center_password_text = false;
              input_opacity = 1.0;
              input_radius = 6.0;
              layout = "regular";
              show_caps_lock = true;
              show_keyboard_layout = true;
              show_login_button = true;
              show_media = true;
              show_session_buttons = true;
              # Карточка статуса над формой ввода. Ошибки и предупреждение
              # Caps Lock показываются и без неё.
              show_unlock_hint = true;
              show_weather = true;
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

  # Перед каждым стартом — чистка state-файла (см. шапку файла).
  # Без неё GUI рано или поздно перекрывает этот конфиг: так уже было со
  # списком плагинов — после ребилда noctalia подняла старый список из state,
  # и плагины лаунчера молча оказались выключены.
  # Остаются только wallpaper.last и wallpaper.monitors.*: это не
  # настройки, а текущие обои, которые noctalia пишет туда сама.
  systemd.user.services.noctalia.Service.ExecStartPre =
    "${noctaliaStateReset}/bin/noctalia-state-reset";

  # Каталог обоев читается только при старте, а ребилд лишь подменяет
  # симлинк ~/Pictures/wallpaper на новый путь в /nix/store — запущенная
  # noctalia об этом не узнаёт. Путь к обоям в юните меняет его хеш,
  # и home-manager перезапускает шелл, когда набор обоев изменился.
  systemd.user.services.noctalia.Unit.X-Restart-Triggers = [ "${../wallpapers}" ];
}
