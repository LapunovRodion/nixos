{ osConfig, pkgs, lib, ... }:

# =============================================================
# umbriel — композитор. Пришёл на смену niri (см. git history: до этого
# здесь лежал home/niri/config.kdl на 792 строки в формате KDL).
#
# Конфиг umbriel — TOML, поэтому описан здесь обычным attrset'ом и
# сериализуется pkgs.formats.toml. Так машинозависимые куски (выходы,
# автозапуск, правила окон с именами мониторов) берутся прямо из
# osConfig.local.*, а не живут отдельным include-файлом на каждый хост.
#
# Модуля programs.umbriel в home-manager нет, а апстримный flake
# композитора сюда не подключён намеренно: его nixosModules.default
# отключает модуль nixpkgs и подставляет пакет, собранный из исходников,
# мимо бинарного кэша. Пакет и модуль NixOS берём из nixpkgs, а генерацию
# config.toml делаем сами — это несколько строк в конце файла.
#
# --- ВЕРСИЯ, ПОД КОТОРУЮ НАПИСАН ЭТОТ ФАЙЛ ---
# umbriel 0-unstable-2026-08-25 (то, что лежит в nixpkgs; в свежем
# unstable на 31.08.2026 та же самая). Проект молодой и быстрый: его
# онлайн-документация описывает апстримный main и УШЛА ВПЕРЁД пакета —
# в ней есть действия и ключи, которых в собранном бинаре ещё нет
# (master-раскладка, управление высотой окна, allow_when_locked,
# workspace-move-*, column-focus-first/last и другие).
#
# Поэтому источник правды здесь — не сайт, а сам бинарь:
#     umbriel msg --help                       список действий
#     $(nix build --print-out-paths nixpkgs#umbriel)/share/umbriel/config.toml
#                                              эталонный конфиг версии
#
# Само по себе `umbriel validate` возвращает 0 даже когда молча
# выбрасывает бинды с неизвестными действиями, поэтому проверка внизу
# файла ЖЁСТКАЯ: любое предупреждение валидатора роняет сборку. Если
# после `nix flake update` конфиг вдруг перестал собираться — значит
# апстрим переименовал ключ или действие, и это ровно то место, где об
# этом надо узнать.
#
# --- ПОРЯДОК СКЛЕЙКИ, ЧИТАТЬ ПЕРЕД ПРАВКОЙ ЦВЕТОВ ---
# У niri последний include перебивал главный файл, поэтому цвета лежали
# в noctalia-theme.kdl, а заводские значения в config.kdl можно было не
# трогать. У umbriel ВСЁ НАОБОРОТ: главный файл перебивает все include.
# Значит здесь НЕЛЬЗЯ задавать ни один ключ, который пишет шаблон темы
# (home/umbriel/theme.toml.in):
#   colors.*, appearance.border_focused, border_unfocused,
#   scratchpad_border_focused, scratchpad_border_unfocused,
#   outer_border_color, insert_hint_color, backdrop_color,
#   appearance.shadow.color, overview.background_tint,
#   overview.workspace_background
# Ошибкой это не проявится — палитра просто замрёт и перестанет ехать
# за обоями.
# =============================================================

let
  settings = {

    # Тема от noctalia. Путь АБСОЛЮТНЫЙ намеренно: относительные include
    # резолвятся от каталога главного файла (src/config/config_merge.cpp,
    # expandPath от path.parent_path()), а главный файл у нас — симлинк в
    # /nix/store, так что "noctalia.toml" рисковал бы искаться в сторе.
    # Тильда разворачивается самим umbriel.
    #
    # Файла может ещё не быть (чистая машина, обои не менялись) — это
    # штатно: umbriel помечает include отсутствующим и подхватит его,
    # как только noctalia его напишет.
    include.files = [ "~/.config/umbriel/noctalia.toml" ];

    general = {
      # Машинозависимый автозапуск (см. hosts/<машина>/default.nix).
      # Шелл noctalia сюда не входит — он поднимается своим user-юнитом.
      autostart = osConfig.local.autostart;

      # X11-приложения через xwayland-satellite. Бинарь берётся из PATH,
      # и pkgs.umbriel уже обёрнут им (wrapProgram в nixpkgs), отдельно
      # ставить не нужно.
      xwayland = true;

      # Шпаргалка по хоткеям при каждом старте не нужна — она открывается
      # на Mod+Slash. Аналог `hotkey-overlay { skip-at-startup }` у niri.
      show_cheatsheet = false;

      mod_key = "Super";
    };

    workspaces = {
      # Повторное нажатие Mod+<номер> на текущем воркспейсе возвращает на
      # предыдущий. Частичная замена niri'шному Mod+Tab
      # (focus-workspace-previous): отдельного действия для него в этой
      # версии нет.
      back_and_forth = true;
    };

    input = {
      keyboard = {
        # ru-latin вместо ru — своя раскладка из ~/.config/xkb/symbols
        # (файл home/xkb/symbols-ru-latin, кладётся в home.nix). Кириллица
        # там та же самая, но на 3-4 уровнях лежит латиница, и хоткеи с
        # Ctrl/Alt/Super работают в русской группе так же, как в английской.
        #
        # custom:types — штатная опция xkeyboard-config, подключающая
        # ~/.config/xkb/types/custom. Без неё тип LATIN_FALLBACK не
        # найдётся и раскладка не соберётся.
        layout = "us,ru-latin";
        options = "grp:caps_toggle,custom:types";
        # numlock у niri включался строкой `numlock`; в этой версии
        # umbriel такого ключа нет вовсе (появился в апстриме позже).
      };

      touchpad = {
        tap = true;
        natural_scroll = true;
      };

      # Тема курсоров. Сам пакет ставится в home.nix (home.pointerCursor);
      # без темы в системе композитор не находит crosshair, и курсор при
      # выделении области (slurp) пропадает.
      cursor = {
        theme = "catppuccin-latte-dark-cursors";
        size = 24;
      };
    };

    layout = {
      # В этой версии раскладок две: scrolling и dwindle (master добавили
      # в апстриме позже). Переключение по кругу — на Mod+Ctrl+F.
      mode = "scrolling";
      gap = 16;
      # Ширины, между которыми переключает Mod+R: 1/3, 1/2, 2/3 экрана.
      width_presets = [ 0.33333 0.5 0.66667 ];
      scrolling.default_width_fraction = 0.5;
    };

    appearance = {
      # Ширина рамки. ВНИМАНИЕ на разницу с niri: там был focus-ring,
      # который рисовался только вокруг активного окна. Здесь рамка есть
      # у всех окон, различаются только цвета (border_focused /
      # border_unfocused — из шаблона темы).
      border_width = 4;

      # Согласовано с барами noctalia (bar radius 12). Содержимое окна
      # обрезается по этому же радиусу, отдельного clip-to-geometry,
      # как в niri, задавать не нужно.
      corner_radius = 12;

      # У umbriel это true по умолчанию — приложения просят убрать свои
      # декорации. Оставляем false, как было при niri: иначе GTK-окна на
      # переезде разом лишились бы заголовков. Переключается одной строкой.
      prefer_no_csd = false;

      # Тень. Геометрия перенесена из niri, кроме spread — такого
      # параметра у umbriel нет. Цвет — из шаблона темы.
      shadow = {
        enabled = true;
        softness = 30;
        offset_x = 0;
        offset_y = 5;
      };

      # Блюр от композитора — то, чего у niri не было вовсе. Включает
      # размытие под стеклянными панелями noctalia (layer_rule ниже) и
      # под полупрозрачным kitty (window_rule ниже).
      # passes/radius/noise/brightness/contrast/saturation — заводские.
      blur = {
        enabled = true;
        optimized = true;
      };
    };

    # Масштаб миниатюр. Меньше — больше воркспейсов влезает на экран.
    # Обои под миниатюрами umbriel показывает сам, поэтому хаки, которые
    # для этого держались в конфиге niri (layer-rule place-within-backdrop
    # на noctalia-wallpaper и background-color "transparent" у layout),
    # не переносились и больше не нужны. Подкраска и подложка под
    # воркспейсами — из шаблона темы.
    overview.zoom = 0.5;

    # Горячий угол слева сверху отключён: слишком легко задеть случайно.
    # Overview остаётся на Mod+O. Заводской конфиг umbriel вешает на этот
    # угол overview-open, поэтому строка нужна явно — остальные три угла
    # выключены по умолчанию.
    hot_corners.top_left.enabled = false;

    window_rule = [
      # Блюр всем окнам. Само по себе ничего не меняет для непрозрачных
      # окон — работает там, где сквозь окно видно фон (kitty ниже).
      { blur = true; blur_optimized = true; }

      # Терминал полупрозрачен ВСЕГДА.
      #
      # Своей настройки kitty (background_opacity) для этого мало: она
      # красит только ячейки с фоном по умолчанию. Любой TUI — nvim, yazi,
      # lazygit — заливает экран собственным цветом фона, и такие ячейки
      # рисуются глухими. Поэтому прозрачность задаётся здесь: композитор
      # гасит поверхность окна целиком, независимо от того, что внутри.
      #
      # Расплата: текст тоже становится полупрозрачным. Отсюда 0.92, а не
      # 0.85 — на более низких значениях буквы начинают спорить с обоями.
      # background_opacity в kitty при этом снят в 1.0 (см. home.nix),
      # иначе множители перемножались бы и фон уходил в 0.8.
      {
        match.app_id = "^kitty$";
        opacity = 0.92;
      }

      # Плавающий Picture-in-Picture. Регулярка по заголовку, а не по
      # app-id: у XDG-shell нет семантической роли PiP, браузеры её никак
      # не помечают.
      {
        match.title = "^(Picture-in-Picture|Picture in picture)$";
        default_floating = true;
      }

      # Окно настроек самой noctalia — плавающим и заводного размера.
      {
        match.app_id = "^dev\\.noctalia\\.Noctalia$";
        default_floating = true;
        default_size = [ 1020 900 ];
      }

      # Диалог выбора окна/экрана для скриншеринга (портал umbriel).
      {
        match.app_id = "^dev\\.noctalia\\.UmbrielSharePicker$";
        default_floating = true;
        default_size = [ 800 600 ];
      }
    ]
    # Машинозависимые правила — последними, поэтому перебивают всё выше.
    ++ osConfig.local.windowRules;

    # Стеклянные панели noctalia (panel.transparency_mode = "glass" в
    # noctalia.nix) получают настоящее размытие под собой. Раньше эту роль
    # пытался играть слой backdrop самой noctalia — теперь он выключен,
    # размывает композитор.
    #
    # blur_ignore_alpha 0.5: не размывать там, где поверхность почти
    # прозрачна, иначе размытие вылезает за видимые края панели.
    # blur_optimized = false — как в эталонном конфиге umbriel для слоёв:
    # панели перерисовываются часто, оптимизированный путь на них мылит.
    layer_rule = [
      {
        match.namespace = "^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd|desktop-widget-.*)$";
        blur = true;
        blur_ignore_alpha = 0.5;
        blur_optimized = false;
      }
    ];

    # Таблица выходов — единственное в конфиге, что целиком зависит от
    # машины (см. local.outputConfig в hosts/<машина>/default.nix).
    output = osConfig.local.outputConfig;

    # =========================================================
    # Бинды.
    #
    # Перенесены из config.kdl niri везде, где у ЭТОЙ версии umbriel есть
    # эквивалентное действие. Полный список — `umbriel msg --help`; он
    # заметно короче того, что обещает сайт (см. шапку файла).
    #
    # Чего в этой версии нет, и поэтому клавиши остались пустыми:
    #   Mod+Home/End, Mod+Ctrl+Home/End  — column-focus/move-to-first/last
    #   Mod+Shift+U/I/Page_Up/Page_Down  — перестановка воркспейсов
    #   Mod+Shift+Minus/Equal            — управление высотой окна
    #   Mod+Shift+R, Mod+Ctrl+Shift+R    — обратный цикл ширины, цикл высоты
    #   Mod+Shift+N                      — переход между floating и tiling
    # Табличная форма { action = …; allow_when_locked = true; } тоже
    # появилась позже, поэтому медиа- и яркостные бинды НЕ работают на
    # заблокированном экране (у niri работали).
    #
    # Три бинда сознательно расходятся с дефолтами umbriel — в пользу уже
    # наработанной привычки: Mod+T это терминал (а не floating), Mod+Space —
    # переключатель окон noctalia (а не scratchpad), Mod+Q — закрыть окно.
    # =========================================================
    keybinds = {
      # ---- Приложения ----
      "Mod+Slash" = "cheatsheet-toggle";
      "Mod+T" = "spawn:kitty";
      "Mod+D" = "spawn:fuzzel";
      "Mod+B" = "spawn:zen-twilight";
      # yazi — TUI, поэтому запускается внутри kitty.
      "Mod+E" = "spawn:kitty -e yazi";
      # Блокировка — встроенный локскрин noctalia (он же срабатывает по
      # idle-таймауту, см. noctalia.nix).
      "Super+Alt+L" = "spawn:noctalia msg session lock";
      "Super+Alt+S" = "spawn:pkill orca || exec orca";

      # ---- Громкость и медиа ----
      # "-l 1.0" ограничивает громкость сотней процентов.
      "XF86AudioRaiseVolume" = "spawn:wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1+ -l 1.0";
      "XF86AudioLowerVolume" = "spawn:wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1-";
      "XF86AudioMute" = "spawn:wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
      "XF86AudioMicMute" = "spawn:wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
      "XF86AudioPlay" = "spawn:playerctl play-pause";
      "XF86AudioStop" = "spawn:playerctl stop";
      "XF86AudioPrev" = "spawn:playerctl previous";
      "XF86AudioNext" = "spawn:playerctl next";

      # ---- Яркость ----
      # Через noctalia: свой OSD, шаг берётся из настроек шелла.
      # brightnessctl в системе нет.
      "XF86MonBrightnessUp" = "spawn:noctalia msg brightness-up";
      "XF86MonBrightnessDown" = "spawn:noctalia msg brightness-down";
      # Дубль на Mod+F7/F8: Fn-ряд на ноуте неудобен. Именно с Mod, а не
      # голые F7/F8 — иначе композитор перехватывал бы их у приложений.
      "Mod+F7" = "spawn:noctalia msg brightness-down";
      "Mod+F8" = "spawn:noctalia msg brightness-up";

      # ---- Окна: фокус ----
      "Mod+O" = { action = "overview-toggle"; repeat = false; };
      "Mod+Q" = { action = "window-close"; repeat = false; };

      "Mod+Left" = "window-focus-left";
      "Mod+Down" = "window-focus-down";
      "Mod+Up" = "window-focus-up";
      "Mod+Right" = "window-focus-right";
      "Mod+H" = "window-focus-left";
      # J/K у niri были гибридными (на краю колонки уходили на соседний
      # воркспейс) — window-focus-or-workspace-* в этой версии нет,
      # поэтому они просто дублируют стрелки.
      "Mod+J" = "window-focus-down";
      "Mod+K" = "window-focus-up";
      "Mod+L" = "window-focus-right";
      # Обход окон по кругу. У niri на этой клавише был предыдущий
      # воркспейс; его роль частично взял workspaces.back_and_forth выше.
      "Mod+Tab" = "window-focus-next";

      # ---- Окна: перенос ----
      "Mod+Ctrl+Left" = "column-move-left";
      "Mod+Ctrl+Down" = "window-move-down";
      "Mod+Ctrl+Up" = "window-move-up";
      "Mod+Ctrl+Right" = "column-move-right";
      "Mod+Ctrl+H" = "column-move-left";
      "Mod+Ctrl+J" = "window-move-down";
      "Mod+Ctrl+K" = "window-move-up";
      "Mod+Ctrl+L" = "column-move-right";

      # ---- Мониторы ----
      "Mod+Shift+Left" = "output-focus-left";
      "Mod+Shift+Down" = "output-focus-down";
      "Mod+Shift+Up" = "output-focus-up";
      "Mod+Shift+Right" = "output-focus-right";
      "Mod+Shift+H" = "output-focus-left";
      "Mod+Shift+J" = "output-focus-down";
      "Mod+Shift+K" = "output-focus-up";
      "Mod+Shift+L" = "output-focus-right";

      "Mod+Shift+Ctrl+Left" = "column-move-to-output-left";
      "Mod+Shift+Ctrl+Down" = "column-move-to-output-down";
      "Mod+Shift+Ctrl+Up" = "column-move-to-output-up";
      "Mod+Shift+Ctrl+Right" = "column-move-to-output-right";
      "Mod+Shift+Ctrl+H" = "column-move-to-output-left";
      "Mod+Shift+Ctrl+J" = "column-move-to-output-down";
      "Mod+Shift+Ctrl+K" = "column-move-to-output-up";
      "Mod+Shift+Ctrl+L" = "column-move-to-output-right";

      # ---- Воркспейсы ----
      # niri переносил на соседний воркспейс всю КОЛОНКУ; здесь есть
      # только перенос окна — column-move-to-workspace-* не существует.
      "Mod+Page_Down" = "workspace-next";
      "Mod+Page_Up" = "workspace-previous";
      "Mod+U" = "workspace-next";
      "Mod+I" = "workspace-previous";
      "Mod+Ctrl+Page_Down" = "window-move-to-workspace-next";
      "Mod+Ctrl+Page_Up" = "window-move-to-workspace-previous";
      "Mod+Ctrl+U" = "window-move-to-workspace-next";
      "Mod+Ctrl+I" = "window-move-to-workspace-previous";

      # ---- Колесо ----
      # Раскладка своя, не дефолтная: Mod+колесо — воркспейсы,
      # Mod+Shift+колесо — окна. Ограничителя частоты (cooldown-ms у
      # niri) у umbriel нет, прокрутка идёт резвее.
      "Mod+WheelDown" = "workspace-next";
      "Mod+WheelUp" = "workspace-previous";
      "Mod+Ctrl+WheelDown" = "window-move-to-workspace-next";
      "Mod+Ctrl+WheelUp" = "window-move-to-workspace-previous";
      "Mod+WheelRight" = "window-focus-right";
      "Mod+WheelLeft" = "window-focus-left";
      "Mod+Ctrl+WheelRight" = "column-move-right";
      "Mod+Ctrl+WheelLeft" = "column-move-left";
      "Mod+Shift+WheelDown" = "window-focus-right";
      "Mod+Shift+WheelUp" = "window-focus-left";
      "Mod+Ctrl+Shift+WheelDown" = "column-move-right";
      "Mod+Ctrl+Shift+WheelUp" = "column-move-left";

      # ---- Воркспейсы по номеру ----
      "Mod+1" = "workspace-switch:1";
      "Mod+2" = "workspace-switch:2";
      "Mod+3" = "workspace-switch:3";
      "Mod+4" = "workspace-switch:4";
      "Mod+5" = "workspace-switch:5";
      "Mod+6" = "workspace-switch:6";
      "Mod+7" = "workspace-switch:7";
      "Mod+8" = "workspace-switch:8";
      "Mod+9" = "workspace-switch:9";
      "Mod+Ctrl+1" = "window-move-to-workspace:1";
      "Mod+Ctrl+2" = "window-move-to-workspace:2";
      "Mod+Ctrl+3" = "window-move-to-workspace:3";
      "Mod+Ctrl+4" = "window-move-to-workspace:4";
      "Mod+Ctrl+5" = "window-move-to-workspace:5";
      "Mod+Ctrl+6" = "window-move-to-workspace:6";
      "Mod+Ctrl+7" = "window-move-to-workspace:7";
      "Mod+Ctrl+8" = "window-move-to-workspace:8";
      "Mod+Ctrl+9" = "window-move-to-workspace:9";

      # Переключатель окон noctalia — поиск по всем воркспейсам, в отличие
      # от overview (Mod+O), который показывает только текущий монитор.
      "Mod+Space" = "spawn:noctalia msg window-switcher";

      # ---- Колонки: состав и размеры ----
      # У niri было две пары: скобки (consume-or-expel) и запятая/точка
      # (consume/expel). Здесь действий всего два, поэтому обе пары ведут
      # к ним же — привычка работает и та, и другая.
      "Mod+Comma" = "window-consume-left";
      "Mod+Period" = "window-expel-right";
      "Mod+BracketLeft" = "window-consume-left";
      "Mod+BracketRight" = "window-expel-right";

      "Mod+R" = "window-cycle-width";
      "Mod+Minus" = "window-modify-width:-0.1";
      "Mod+Equal" = "window-modify-width:0.1";

      "Mod+F" = "window-toggle-maximize";
      "Mod+Shift+F" = "window-toggle-fullscreen";
      # Разворот без зазоров, отступов и рамок — как двойной клик по
      # заголовку в обычном оконном менеджере.
      "Mod+M" = "window-toggle-maximize-to-edges";
      "Mod+C" = "window-center";

      # Mod+V отдан истории буфера обмена, поэтому floating живёт на N.
      "Mod+N" = "window-toggle-floating";

      # ---- На клавишах, освободившихся от niri ----
      # Scratchpad — «полка» на каждом выходе: убрать окно с глаз и
      # вернуть по хоткею. У niri аналога не было.
      # Клавиша W держала toggle-column-tabbed-display, которого здесь нет.
      "Mod+W" = "window-move-to-scratchpad";
      "Mod+Shift+W" = "scratchpad-toggle";
      "Mod+Ctrl+W" = "window-restore-from-scratchpad";
      "Mod+Alt+W" = "scratchpad-focus-next";
      # Закрепить окно поверх остальных и на всех воркспейсах.
      # (Клавиша держала toggle-keyboard-shortcuts-inhibit — его нет.)
      "Mod+Escape" = "window-toggle-pinned";
      # Раскладка текущего воркспейса: scrolling ↔ dwindle.
      # (Клавиша держала expand-column-to-available-width — его нет.)
      "Mod+Ctrl+F" = "workspace-set-layout:toggle";
      # (Клавиша держала reset-window-height — его нет.)
      "Mod+Ctrl+R" = "config-reload";

      # ---- Скриншоты, запись, буфер ----
      # Своих скриншотов у umbriel нет (у niri были встроенные), всё
      # снимает noctalia — единым видом с остальным шеллом.
      # На ноуте клавиши Print нет, поэтому дубль на Mod+S.
      "Print" = "spawn:noctalia msg screenshot-region";
      "Ctrl+Print" = "spawn:noctalia msg screenshot-fullscreen";
      "Mod+S" = "spawn:noctalia msg screenshot-region";
      "Mod+Shift+S" = "spawn:noctalia msg screenshot-fullscreen";
      # История буфера обмена — встроенная панель noctalia, свой демон
      # не нужен.
      "Mod+V" = "spawn:noctalia msg panel-toggle clipboard";
      # Запись экрана: первое нажатие — старт, второе — стоп. Пока идёт,
      # висит уведомление с таймером.
      "Mod+Alt+R" = "spawn:screenrec";

      # ---- Сессия ----
      # session-quit спрашивает подтверждение на экране.
      "Mod+Shift+E" = "session-quit";
      "Ctrl+Alt+Delete" = "session-quit";
      # Погасить мониторы. Обратно — любым вводом.
      "Mod+Shift+P" = "dpms-off";
    };
  };

  tomlFormat = pkgs.formats.toml { };
  rawConfig = tomlFormat.generate "umbriel-config.toml" settings;

  # Проверка конфига на этапе сборки.
  #
  # ЖЁСТКАЯ намеренно. Само `umbriel validate` возвращает 0, даже когда
  # выбрасывает бинд с неизвестным действием или игнорирует неизвестный
  # ключ — на одних кодах возврата опечатка доехала бы до живой сессии и
  # проявилась молча не работающей клавишей. Поэтому любое предупреждение
  # валидатора роняет сборку.
  #
  # Единственное ожидаемое исключение — отсутствующий include с темой:
  # в сборочной песочнице ~/.config/umbriel/noctalia.toml не существует
  # и существовать не может.
  #
  # Раскладку валидатор проверяет по-настоящему: он собирает keymap, а
  # ru-latin и тип custom лежат в ~/.config/xkb, которого в песочнице
  # нет. Поэтому те же самые файлы подкладываются через штатную
  # переменную libxkbcommon XKB_CONFIG_EXTRA_PATH — так проверка ловит и
  # опечатку в самих xkb-файлах, а не только в конфиге композитора.
  checkedConfig = pkgs.runCommand "umbriel-config.toml" { } ''
    mkdir -p xkb/types xkb/symbols
    cp ${./xkb/types-custom} xkb/types/custom
    cp ${./xkb/symbols-ru-latin} xkb/symbols/ru-latin
    export XKB_CONFIG_EXTRA_PATH="$PWD/xkb"

    set +e
    ${lib.getExe pkgs.umbriel} validate -c ${rawConfig} > log 2>&1
    status=$?
    set -e
    cat log

    if [ "$status" -ne 0 ]; then
      echo "umbriel validate завершился с кодом $status" >&2
      exit "$status"
    fi

    if grep -v 'include not found' log | grep -qE 'warning:|WRN'; then
      echo >&2
      echo "Валидатор umbriel выдал предупреждения — конфиг принят не целиком." >&2
      echo "Список действий этой версии: umbriel msg --help" >&2
      grep -v 'include not found' log | grep -E 'warning:|WRN' >&2
      exit 1
    fi

    cp ${rawConfig} $out
  '';
in

{
  xdg.configFile."umbriel/config.toml".source = checkedConfig;
}
