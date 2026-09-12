{ inputs, lib, pkgs, osConfig, ... }:
# osConfig — конфиг СИСТЕМЫ. Доступен потому, что home-manager подключён
# модулем NixOS; через него читаются опции local.* (см. modules/options.nix),
# то есть всё, чем ноут отличается от десктопа.
let
  # Соответствие ЙЦУКЕН ↔ QWERTY. Нужно там, где приложение ловит ОДИНОЧНУЮ
  # клавишу без модификатора и xkb помочь не может: normal mode в nvim,
  # биндинги yazi, клавиши после префикса в tmux, буквенные бинды mpv.
  # Хоткеи с Ctrl/Alt/Super
  # к этой таблице отношения не имеют — их чинит раскладка из home/xkb.
  kbd = import ./keyboard-ru.nix { inherit lib; };

  # ---- зеркальные биндинги yazi ----
  #
  # Штатные бинды yazi (их около сотни) лежат отдельным сгенерированным
  # файлом, свои — зеркалятся функцией ниже прямо на месте, в keymap.
  yaziRu = import ./yazi-keymap-ru.nix;

  # Каждой записи keymap подставляет кириллическую клавишу, оставляя run и
  # desc. Записи, где переводить нечего (<C-y>, <Esc>), выбрасываются:
  # дубликат один в один только замусорил бы справку.
  yaziMirror =
    let
      swap =
        e:
        let
          keys = if builtins.isList e.on then e.on else [ e.on ];
          ru = map (k: kbd.mirrorMap.${k} or k) keys;
        in
        if ru == keys then null
        else e // { on = if builtins.isList e.on then ru else builtins.head ru; };
    in
    entries: lib.filter (e: e != null) (map swap entries);

  # ---- зеркальные бинды tmux ----
  #
  # Префикс Ctrl-a чинит xkb, а вот следующая клавиша идёт БЕЗ модификатора,
  # и вместо `c` в tmux прилетает `с`. Дублировать бинды руками плохо: их
  # десятки, часть заводит сам tmux, часть — плагины, и список сразу поедет.
  #
  # Поэтому зеркала снимаются с уже загруженной таблицы: `list-keys` печатает
  # готовые команды bind-key, awk подменяет в них клавишу на кириллическую,
  # `source-file` скармливает результат обратно. Любой новый бинд —
  # хоть свой, хоть плагинный — зеркалится сам.
  tmuxMirrorAwk = pkgs.writeText "tmux-mirror-ru.awk" ''
    BEGIN {
      ${lib.concatMapStrings (p: ''
        map["${lib.escape [ "\\" "\"" ] p.en}"] = "${p.ru}";
      '') kbd.mirrorPairs}
    }

    # Строка вида: bind-key [-r] [-N "..."] -T <таблица> <клавиша> <команда...>
    # Флаги идут ДО -T, команда — после клавиши, поэтому первого вхождения
    # " -T " достаточно, чтобы отделить хвост и не разбирать флаги.
    {
      i = index($0, " -T ")
      if (i == 0) next

      head = substr($0, 1, i + 3)
      rest = substr($0, i + 4)

      if (match(rest, /^ *[^ ]+ +/) == 0) next
      tbl  = substr(rest, RSTART, RLENGTH)
      rest = substr(rest, RSTART + RLENGTH)

      if (match(rest, /^[^ ]+/) == 0) next
      key  = substr(rest, RSTART, RLENGTH)
      tail = substr(rest, RSTART + RLENGTH)

      # Клавиши не из таблицы (F1, C-a, Up) пропускаем молча: им зеркало
      # не нужно, их либо не трогает раскладка, либо чинит xkb.
      if (key in map) print head tbl map[key] tail
    }
  '';

  tmuxMirror = pkgs.writeShellScript "tmux-mirror-ru" ''
    set -eu

    # tmux НЕ пинним из pkgs: скрипт зовётся через run-shell уже живым
    # сервером, и обращаться надо именно к нему, а не к своей копии.
    out=$(${pkgs.coreutils}/bin/mktemp)
    trap '${pkgs.coreutils}/bin/rm -f "$out"' EXIT

    # prefix — бинды после Ctrl-a, copy-mode-vi — навигация в буфере
    # прокрутки. Таблица root (bind -n) не нужна: там всё с модификаторами.
    for table in prefix copy-mode-vi; do
      tmux list-keys -T "$table" | ${pkgs.gawk}/bin/awk -f ${tmuxMirrorAwk} >> "$out"
    done

    if [ -s "$out" ]; then
      tmux source-file "$out"
    fi
  '';

  # ---- зеркальные бинды mpv ----
  #
  # Плеер ловит одиночные клавиши ровно как yazi: в кириллической группе `q`
  # (выйти) и `f` (полный экран) молча не срабатывают. Зеркалить весь штатный
  # список незачем — стрелки, пробел, цифры от раскладки не зависят, — поэтому
  # здесь только те бинды, которыми реально пользуются.
  #
  # ВНИМАНИЕ: буквами дело не ограничивается. `[`/`]` (скорость), `<`/`>`
  # (плейлист), `,`/`.` (по кадру) в ЙЦУКЕН сидят на х/ъ, Б/Ю и б/ю — то есть
  # ломаются наравне с буквами и зеркалятся так же.
  #
  # Автоматики уровня tmux тут не выйдет: спросить у mpv «что висит на этой
  # клавише» нельзя, так что латинский бинд приходится ПЕРЕОБЪЯВЛЯТЬ. Команды
  # ниже списаны один в один с апстримного input.conf — он лежит в самом
  # пакете, share/doc/mpv/input.conf; правишь строку — сверяйся с ним.
  mpvKeys = {
    q = "quit";
    Q = "quit-watch-later";
    p = "cycle pause";
    f = "cycle fullscreen";
    m = "cycle mute";
    T = "cycle ontop";
    s = "screenshot";
    S = "screenshot video";
    o = "show-progress";
    i = "script-binding stats/display-stats";
    I = "script-binding stats/display-stats-toggle";
    j = "cycle sub";
    J = "cycle sub down";
    v = "cycle sub-visibility";
    z = "add sub-delay -0.1";
    Z = "add sub-delay +0.1";
    l = "ab-loop";
    L = ''cycle-values loop-file "inf" "no"'';
    "[" = "multiply speed 1/1.1";
    "]" = "multiply speed 1.1";
    "{" = "multiply speed 0.5";
    "}" = "multiply speed 2.0";
    "<" = "playlist-prev";
    ">" = "playlist-next";
    "," = "frame-back-step";
    "." = "frame-step";
  };

  # Кириллическая копия поверх латинских. Клавиши, которой нет в таблице,
  # mirrorMap не находит, и запись остаётся сама собой — дубликат с тем же
  # значением при слиянии безвреден.
  #
  # Переключение аудиодорожки (`#`) в таблицу не попадает вовсе: в ЙЦУКЕН на
  # этой позиции `№`, а решётки нет ни на одной клавише. Поэтому дописывается
  # руками, отдельной записью — латинский `#` при этом остаётся штатным.
  mpvBindings =
    { "№" = "cycle audio"; }
    // mpvKeys
    // lib.mapAttrs' (k: v: lib.nameValuePair (kbd.mirrorMap.${k} or k) v) mpvKeys;
in
{
  imports = [
    inputs.noctalia.homeModules.default
    inputs.nixvim.homeModules.nixvim
    ./noctalia.nix        # весь конфиг шелла — бар, док, виджеты, тема, плагины
  ];

  home.stateVersion = "26.05";

  # =============================================================
  # niri — конфиг композитора, теперь в git.
  #
  # Модуля programs.niri в home-manager нет, поэтому файл подключается
  # как есть. Источник правды — ~/nixos/niri/config.kdl, в ~/.config
  # ложится read-only симлинк в /nix/store.
  #
  # ВАЖНО: раз файл read-only, дописать в него строку include больше
  # никто не может — apply.sh шаблонов noctalia именно это и делал.
  # Поэтому include стоит в самом файле, в конце (см. niri/config.kdl).
  # =============================================================
  xdg.configFile."niri/config.kdl".source = ./niri/config.kdl;

  # Единственная машинозависимая часть конфига композитора — блоки output
  # (разрешение, масштаб, взаимное расположение мониторов). Файл берётся из
  # hosts/<машина>/outputs.kdl и подключается строкой include в config.kdl.
  xdg.configFile."niri/outputs.kdl".source = osConfig.local.niriOutputs;

  # =============================================================
  # Раскладка, в которой хоткеи не зависят от языка.
  #
  # Проблема: в кириллической группе Ctrl+ф — это Ctrl+Cyrillic_ef, и
  # приложение такой хоткей не узнаёт. Свои бинды niri переживает (он ищет
  # латинский кейсим по всем группам), а вот GTK/Qt/Electron, префикс tmux
  # и биндинги fish/readline ломаются все разом.
  #
  # Решение: своя раскладка ru-latin, где на 3-4 уровнях лежит латиница, и
  # свой тип клавиши, включающий эти уровни по Ctrl/Alt/Super. Подробности —
  # в комментариях внутри самих файлов.
  #
  # Пересобирать системный xkeyboard-config не нужно: libxkbcommon
  # просматривает ~/.config/xkb ПЕРВЫМ, а тип подключается штатной опцией
  # custom:types (см. options в niri/config.kdl).
  # =============================================================
  xdg.configFile."xkb/types/custom".source = ./xkb/types-custom;
  xdg.configFile."xkb/symbols/ru-latin".source = ./xkb/symbols-ru-latin;

  # wayvnc — конфиг VNC-сервера, null на машинах без него (см. modules/options.nix).
  xdg.configFile."wayvnc/config" = lib.mkIf (osConfig.local.wayvncConfig != null) {
    source = osConfig.local.wayvncConfig;
  };

  # =============================================================
  # Zen — настройки профиля.
  #
  # Модуль homeModules из flake зен-браузера сознательно НЕ подключён:
  # он заводит профиль под своим именем, а тут уже живёт готовый со
  # всей историей и вкладками. Пишем прямо в его user.js.
  #
  # Имя каталога профиля с рандомным префиксом — из ~/.config/zen/
  # profiles.ini, и на каждой машине оно своё, поэтому лежит в
  # local.zenProfileDir. Пока профиля нет (значение null), файл не
  # пишется вовсе: home-manager подставил бы его в несуществующий
  # каталог и молча ничего не сделал.
  #
  # Первые две строки были в файле и раньше, правились руками; здесь
  # они сохранены как есть, иначе перезатёрлись бы.
  # =============================================================
  home.file = lib.mkMerge [
    {
      # =============================================================
      # Плагин claude-companion — по пути, которого больше нет.
      #
      # Хуки Claude Code (~/.claude/settings.json, семь записей) зовут
      # hooks/pulse.py по пути ВНУТРИ состояния noctalia:
      #   ~/.local/state/noctalia/plugins/materialized/community/claude-companion
      # Раньше туда клала копию витрина. Теперь плагины берутся из
      # /nix/store (см. noctalia.nix, источники kind = "path"), и этот
      # каталог не создаётся вовсе.
      #
      # Цена ошибки высокая и проверена на себе: PreToolUse-хук с
      # несуществующим файлом блокирует КАЖДЫЙ вызов инструмента, то
      # есть Claude Code перестаёт работать целиком, а не «орб не
      # дышит». На чистой машине это случилось бы сразу.
      #
      # Поэтому путь закрепляем симлинком в store. Через home-manager,
      # а не руками: симлинк пересоздаётся при каждом ребилде и потому
      # переживает `nix flake update noctalia-community-plugins`, после
      # которого путь в store меняется.
      #
      # Сам settings.json при этом не трогается.
      # =============================================================
      ".local/state/noctalia/plugins/materialized/community/claude-companion".source =
        "${inputs.noctalia-community-plugins}/claude-companion";

      # =============================================================
      # Обои — в git, каталогом целиком.
      #
      # Раньше картинки лежали только в ~/Pictures/wallpaper и в
      # репозиторий не входили: на новой машине конфиг приезжал, а обои
      # нет, и шелл откатывался на дефолт из пакета noctalia.
      #
      # Путь назначения тот же, что и был, — /home/artur/Pictures/wallpaper,
      # тот самый, что стоит в wallpaper.directory (см. noctalia.nix).
      # Поэтому абсолютные пути в state (wallpaper.last, wallpaper.monitors.*)
      # остаются валидными и текущие обои после ребилда не слетают.
      #
      # Плата за декларативность: каталог становится симлинком в
      # /nix/store и доступен только на чтение. Скачать картинку прямо
      # в него больше нельзя — новые обои кладутся в ~/nixos/wallpapers,
      # коммитятся и приезжают ребилдом.
      # =============================================================
      "Pictures/wallpaper".source = ../wallpapers;
    }

    (lib.mkIf (osConfig.local.zenProfileDir != null) {
      ".config/zen/${osConfig.local.zenProfileDir}/user.js".text = ''
    user_pref("devtools.chrome.enabled", true);
    user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

    // Моноширинный на страницах: <pre>, <code>, любой листинг.
    // Раздельно для латиницы и кириллицы — Firefox держит настройку
    // шрифта на каждую систему письма, и одной x-western мало:
    // на русских страницах язык определяется как x-cyrillic.
    // Без суффикса Mono, в отличие от kitty: там он нужен, чтобы
    // иконочные глифы не ломали сетку терминала, а на веб-странице
    // ужимать нечего.
    user_pref("font.name.monospace.x-western", "JetBrainsMono Nerd Font");
    user_pref("font.name.monospace.x-cyrillic", "JetBrainsMono Nerd Font");

    // Своя стартовая страница. Живёт НА СЕРВЕРЕ отдельным сервисом
    // (/opt/startpage: nginx на 127.0.0.1:8095 + tailscale serve на :8445),
    // локальной копии сознательно нет — страница одна для всех устройств.
    // Обратная сторона: без поднятого tailscale вместо неё будет ошибка сети.
    //
    // Это кнопка «домой» и новые окна. НОВУЮ ВКЛАДКУ так не подменить:
    // у Zen нет настройки под кастомный URL, zen.urlbar.replace-newtab лишь
    // возвращает старую страницу — для этого понадобилось бы расширение.
    //
    // browser.startup.page здесь сознательно не задан: в профиле его нет,
    // значит работает дефолт сборки, а жёсткая единица отобрала бы
    // восстановление прошлой сессии при запуске.
    user_pref("browser.startup.homepage", "https://server.taila27ec6.ts.net:8445");
      '';

      # =============================================================
      # Градиент боковой панели — ОТДЕЛЬНЫМ файлом рядом с userChrome.css,
      # а не его содержимым.
      #
      # chrome/userChrome.css принадлежит community-шаблону noctalia
      # zen-browser: его apply.sh начинается с `touch "$user_chrome"` под
      # set -euo pipefail, так что read-only симлинк в /nix/store на этом
      # месте уронил бы хук целиком — Zen остался бы вообще без темы.
      # Зато содержимое файла шаблон сохраняет: sed удаляет из него только
      # строки с `zen-browser/zen-userChrome.css` и дописывает свою
      # @import сверху.
      #
      # Поэтому один раз РУКАМИ в chrome/userChrome.css второй строкой:
      #   @import "noctalia-gradient.css";
      # (путь относительный, резолвится от каталога chrome/; должен идти
      # ПОСЛЕ строки noctalia — см. шапку zen/gradient.css). Шаг
      # одноразовый на машину и всё равно попадает в ручную настройку
      # профиля: пока zenProfileDir = null, профиля нет вовсе.
      #
      # Цвета в самом CSS не подставляются: там var(--primary) и
      # var(--tertiary) из палитры, которую объявляет импорт noctalia
      # выше по каскаду. Своего шаблона в noctalia.nix не нужно.
      # =============================================================
      ".config/zen/${osConfig.local.zenProfileDir}/chrome/noctalia-gradient.css".source =
        ./zen/gradient.css;
    })
  ];

  # Тема курсоров. До этого в системе не было НИ ОДНОЙ — niri ругался
  # "error loading xcursor crosshair: no default icon", из-за чего slurp
  # (выделение области под скриншот) выглядел так, будто ничего не запустилось.
  # pointerCursor сам ставит пакет, XCURSOR_THEME/SIZE и настройки GTK.
  #
  # catppuccin-cursors собран по вариантам (latteDark, mochaDark, …), каждый
  # выход содержит ровно одну тему. Имя темы внутри пакета не совпадает с
  # именем атрибута — оно kebab-case: catppuccin-latte-dark-cursors.
  home.pointerCursor = {
    # Раньше генерация конфига включалась самим фактом объявления блока,
    # теперь home-manager это ругает как deprecated и хочет явный флаг.
    enable = true;
    package = pkgs.catppuccin-cursors.latteDark;
    name = "catppuccin-latte-dark-cursors";
    size = 24;
    gtk.enable = true;
  };

  # noctalia (шелл) — целиком в ./noctalia.nix, см. imports выше.

  # =============================================================
  # Batch 2 — пользовательские CLI-инструменты (декларативно)
  # Всё через programs.* модули: пакет + конфиг + интеграция с fish
  # разом, в git, а не голые бинарники. См. [[05 - Лог установки NixOS]].
  # =============================================================

  # --- fish: логин-шелл (системная сторона — в configuration.nix) ---
  programs.fish = {
    enable = true;
    # Убрать заводское "Welcome to fish, the friendly interactive shell"
    # при каждом открытии терминала. Опция типа lines, поэтому строка
    # ДОПИСЫВАЕТСЯ к тому, что уже вносят другие модули (zoxide и т.д.).
    interactiveShellInit = ''
      set -g fish_greeting ""
    '';
    # =============================================================
    # Сокращения (abbr, не alias): разворачиваются в полную команду
    # прямо в строке ввода, поэтому видно, что именно выполнится, и
    # можно поправить перед Enter.
    #
    # КАК ЗАВЕСТИ СВОЁ: дописать строку `имя = "команда";` ниже, `ns`,
    # открыть НОВЫЙ терминал. В уже открытых старый набор доживёт до
    # закрытия — abbr в fish посессионные.
    #
    # Если курсор должен встать в середину команды, а не в конец,
    # вместо строки пишется набор (маркер % = место курсора):
    #   моё = { setCursor = true; expansion = "команда %-и-хвост"; };
    #
    # Прежде чем занимать короткое имя — проверить, свободно ли оно:
    # `abbr --query имя` и `type имя`. Уже заняты: ls/ll/la/lla/lt —
    # алиасами модуля eza, y — функцией yazi, z — zoxide.
    #
    # Правило именования: всё, что про nix, начинается на n. Поэтому
    # чистка стора — ngc, а не gc: gc занят гитом и остаётся за ним.
    # =============================================================
    shellAbbrs = {
      gs = "git status";
      gc = "git commit";
      lg = "lazygit";

      # ---- nix ----
      # Через nh, а не голый nixos-rebuild. Причин три: сборка идёт с
      # прогрессом (пакет обёрнут с nix-output-monitor), после
      # переключения печатается дифф пакетов (nvd), и — главное —
      # конфигурация выбирается по hostname. Имени машины в строке нет
      # вообще, поэтому одно и то же сокращение верно и на десктопе, и
      # на ноуте: networking.hostName у них ровно desktop и laptop.
      # Прошлое поколение этих сокращений на этом и горело — там был
      # прибит гвоздями #desktop.
      #
      # Путь к флейку берётся из NH_FLAKE (см. sessionVariables ниже),
      # так что всё работает из любого каталога, а не только из ~/nixos.
      ns = "nh os switch";   # пересобрать и переключиться
      nb = "nh os build";    # только собрать, систему не трогать
      # Три способа применить конфиг, и путать их дорого:
      #   ns  — активировать И сделать загрузочным по умолчанию
      #   nt  — активировать, но в загрузчик НЕ писать: перезагрузка
      #         вернёт прошлое поколение. Для рискованных правок.
      #   nbo — наоборот, применить со следующей загрузки, текущую
      #         сессию не трогая.
      nt = "nh os test";
      nbo = "nh os boot";
      nrb = "nh os rollback";
      # Чистка стора руками. Еженедельный автоматический GC уже есть
      # (nix.gc в modules/common.nix), но он берёт только СИСТЕМНЫЕ
      # поколения старше 14 дней; nh clean all добавляет к ним
      # пользовательские профили и gcroots. Посмотреть, что удалится,
      # не удаляя: nh clean all --dry-run.
      ngc = "nh clean all --keep 5 --keep-since 14d";
      nse = "nh search";
      # Пакет во временный шелл, без установки в систему: курсор встаёт
      # сразу после # — дописать имя и Enter.
      nsh = {
        setCursor = true;
        expansion = "nix shell nixpkgs#%";
      };
      # Обновить инпуты флейка. Курсор — под имя инпута; оставить пустым
      # значит обновить все. --flake нужен, потому что иначе команда
      # смотрит в текущий каталог, а не в конфиг.
      nfu = {
        setCursor = true;
        expansion = "nix flake update % --flake /home/artur/nixos";
      };
    };
  };

  # Путь к флейку для nh (см. сокращения выше). Без него `nh os switch`
  # требует путь аргументом и работает только из ~/nixos.
  # Строкой, а не через config.home.homeDirectory: так же захардкожено
  # в home/noctalia.nix, где собирается команда кнопки Update.
  home.sessionVariables.NH_FLAKE = "/home/artur/nixos";

  # --- умный cd: хук `z` вписывается в fish автоматически ---
  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
  };

  # --- автозагрузка окружения проекта по .envrc (use flake и т.п.) ---
  programs.direnv = {
    enable = true;
    enableFishIntegration = true;
    # Кэширует devShell из flake — без этого nix develop пересобирался бы
    # заново при каждом cd.
    nix-direnv.enable = true;
  };

  # --- файловый менеджер: хук `y` (сменить каталог при выходе) ---
  programs.yazi = {
    enable = true;
    enableFishIntegration = true;

    # Плагины кладутся как есть (setup = false у всех): вызовы require(...)
    # собраны руками в initLua ниже, чтобы настройка была в одном месте,
    # а не размазана между атрибутами и лишним файлом.
    plugins = {
      # mount — список дисков прямо в yazi: клавиша M открывает панель,
      # там смонтировать/отмонтировать флешку. Ходит через udisksctl, поэтому
      # sudo не спрашивает (нужен services.udisks2 — включён в configuration.nix).
      # Точка монтирования получается вида /run/media/artur/<метка тома>.
      mount = "${inputs.yazi-plugins}/mount.yazi";

      # --- внешний вид ---
      full-border = "${inputs.yazi-plugins}/full-border.yazi";  # рамка вокруг панелей
      git = "${inputs.yazi-plugins}/git.yazi";                  # git-статус колонкой в листинге

      # --- поведение ---
      smart-enter = "${inputs.yazi-plugins}/smart-enter.yazi";  # l: войти в каталог ИЛИ открыть файл
      smart-filter = "${inputs.yazi-plugins}/smart-filter.yazi"; # фильтр, не выходя из режима ввода
      smart-paste = "${inputs.yazi-plugins}/smart-paste.yazi";  # вставка в каталог под курсором
      jump-to-char = "${inputs.yazi-plugins}/jump-to-char.yazi"; # f<символ>, как в vim
      chmod = "${inputs.yazi-plugins}/chmod.yazi";
      diff = "${inputs.yazi-plugins}/diff.yazi";
      toggle-pane = "${inputs.yazi-plugins}/toggle-pane.yazi";
      zoom = "${inputs.yazi-plugins}/zoom.yazi";

      # --- сторонние, каждый своим input (см. flake.nix) ---
      ouch = inputs.ouch-yazi;
      starship = inputs.starship-yazi;
    };

    # Тема НЕ трогается: flavor "noctalia" генерит сам noctalia в
    # ~/.config/yazi/flavors/, а theme.toml он же правит своим apply.sh.
    # Отдать theme.toml под home-manager нельзя — HM делает симлинк
    # read-only, и post_hook шаблона на нём падает.
    initLua = ''
      -- Рамка вокруг всех панелей. ROUNDED, чтобы совпадать со скруглениями
      -- бара noctalia и рамками fzf (--border=rounded).
      require("full-border"):setup { type = ui.Border.ROUNDED }

      -- Значки git-статуса. order = 1500 — правее размера файла.
      require("git"):setup { order = 1500 }

      -- Приглашение starship в шапке. Конфиг берётся общий, ~/.config/starship.toml,
      -- так что шапка yazi выглядит ровно как приглашение в fish.
      require("starship"):setup()
    '';

    settings = {
      # Фетчеры считаются в фоне на каждый файл в листинге.
      # id снят сознательно: он нужен только для yazi <= v26.1.22, у нас 26.5.
      plugin.prepend_fetchers = [
        { url = "*"; run = "git"; group = "git"; }
        { url = "*/"; run = "git"; group = "git"; }
      ];

      # Превью архивов через ouch — вместо голого списка имён показывает дерево.
      plugin.prepend_previewers = [
        {
          mime = "application/{*zip,tar,bzip2,7z*,rar,xz,zstd,java-archive}";
          run = "ouch";
        }
      ];
    };

    keymap = {
      # Свои бинды и их зеркала идут ПЕРЕД зеркалами штатных: в prepend_keymap
      # выигрывает первое совпадение, а переопределения ниже (l → smart-enter,
      # p → smart-paste, f → jump-to-char) должны победить и в русской
      # раскладке тоже, а не откатиться к заводскому поведению yazi.
      mgr.prepend_keymap =
        let
          own = [
          {
            on = "M";
            run = "plugin mount";
            desc = "Диски: смонтировать / отмонтировать";
          }

          # l вместо штатного enter: на каталоге — войти, на файле — открыть.
          {
            on = "l";
            run = "plugin smart-enter";
            desc = "Войти в каталог или открыть файл";
          }

          # f перехвачен у штатного `filter --smart` и отдан прыжку по символу,
          # а фильтр переехал на F — в варианте smart-filter он всё равно лучше:
          # не выходит из ввода и сам проваливается в единственный подошедший каталог.
          {
            on = "f";
            run = "plugin jump-to-char";
            desc = "Прыгнуть к файлу на символ";
          }
          {
            on = "F";
            run = "plugin smart-filter";
            desc = "Умный фильтр";
          }

          # p вместо штатного paste: кладёт в каталог под курсором, а не в текущий.
          {
            on = "p";
            run = "plugin smart-paste";
            desc = "Вставить в каталог под курсором";
          }

          {
            on = [ "c" "m" ];
            run = "plugin chmod";
            desc = "chmod на выделенных";
          }

          # Не <C-d>, как советует README плагина: там штатный «полстраницы вниз».
          {
            on = "<C-y>";
            run = "plugin diff";
            desc = "Diff выделенного с файлом под курсором";
          }

          {
            on = "T";
            run = "plugin toggle-pane max-preview";
            desc = "Развернуть / свернуть превью";
          }

          # Не +/-, как советует README: `-` занят штатным symlink.
          # Пара +/= выбрана как соседние клавиши (+ это Shift+=).
          {
            on = "+";
            run = "plugin zoom 1";
            desc = "Приблизить превью";
          }
          {
            on = "=";
            run = "plugin zoom -1";
            desc = "Отдалить превью";
          }

          {
            on = "C";
            run = "plugin ouch";
            desc = "Упаковать в архив";
          }
        ];
        in
        own ++ yaziMirror own ++ yaziRu.mgr;

      # Остальные режимы своих биндов не имеют — только зеркала штатных.
      # input и cmp сознательно не зеркалятся: там набирают текст, и подмена
      # кириллицы на латиницу сломала бы ввод (см. home/yazi-keymap-ru.nix).
      tasks.prepend_keymap = yaziRu.tasks;
      spot.prepend_keymap = yaziRu.spot;
      pick.prepend_keymap = yaziRu.pick;
      confirm.prepend_keymap = yaziRu.confirm;
      help.prepend_keymap = yaziRu.help;
    };
  };

  # --- ls -> eza, с иконками и статусом git прямо в листинге ---
  # Заменил lsd: eza умеет колонку git и --group-directories-first.
  # Держать оба нельзя — оба вешают свой алиас на ls.
  programs.eza = {
    enable = true;
    enableFishIntegration = true;
    icons = "auto";
    git = true;
    extraOptions = [ "--group-directories-first" "--header" ];
  };

  # --- bat: cat с подсветкой ---
  # theme = "ansi" — тема, которая берёт цвета из ANSI-палитры терминала,
  # то есть из темы kitty, то есть из обоев. Своя тема тут не нужна.
  programs.bat = {
    enable = true;
    config = {
      theme = "ansi";
      style = "numbers,changes,header";
    };
  };

  # --- fzf: нечёткий поиск, Ctrl+R и Ctrl+T в fish ---
  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
    defaultOptions = [
      "--height=45%"
      "--layout=reverse"
      "--border=rounded"
      "--info=inline"
      # --color=16: своих цветов не выдумывать, брать 16 ANSI из терминала
      "--color=16"
    ];
  };

  # --- git + delta: диффы сплитом с подсветкой ---
  # programs.git включён именно ради delta: интеграция пишется в
  # programs.git.iniContent, а он превращается в файл только когда
  # модуль git включён (modules/programs/delta.nix, hasGitConfig).
  # Имя и почта — глобально, отсюда: ~/.config/git/config пишет home-manager
  # (симлинк в /nix/store), так что `git config --global` туда не запишет,
  # менять личность можно только здесь. Репозиторий, которому нужна другая
  # подпись, перебивает это своим `git config --local user.*`.
  # credential.helper — не идентичность, а способ авторизации: gh уже
  # залогинен (gh auth login), пусть git берёт токен оттуда вместо
  # запроса логина/пароля по https.
  programs.git.enable = true;
  programs.git.userName = "Rodion";
  programs.git.userEmail = "lapunov.rodion@gmail.com";
  programs.git.extraConfig = {
    credential.helper = "!gh auth git-credential";
  };
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true; # n/N — прыгать по файлам в диффе
      line-numbers = true;
      side-by-side = true;
      hyperlinks = true;
      syntax-theme = "ansi";
    };
  };

  # --- starship: приглашение ---
  # Все цвета заданы ИМЕНАМИ ANSI, ни одного hex — поэтому промпт едет за
  # палитрой обоев через терминал. Допустимые имена (starship их знает
  # ровно восемь + bright-варианты): black, red, green, yellow, blue,
  # purple, cyan, white. НЕ magenta — такое имя starship не понимает и
  # выбрасывает стиль целиком, без единого предупреждения.
  #
  # Встроенный шаблон starship у noctalia сознательно НЕ включён: он не
  # пишет свой файл, а вклинивается в ~/.config/starship.toml между
  # маркерами "# >>> NOCTALIA STARSHIP PALETTE >>>" (assets/templates/
  # starship/apply.sh). С HM это несовместимо — файл read-only симлинк.
  programs.starship = {
    enable = true;
    enableFishIntegration = true;

    # Transient prompt: после выполнения команды приглашение сворачивается
    # до одного "❯". Скроллбек перестаёт быть стеной из повторяющихся
    # сегментов — остаются только команды и их вывод. Пишет строчку
    # enable_transience в инициализацию fish (HM, programs/starship.nix:185).
    enableTransience = true;

    settings = {
      add_newline = true;

      # Две строки в рамке. Всё, что идёт ПОСЛЕ $fill, прижимается к
      # правому краю терминала, а промежуток затягивается точками.
      format = lib.concatStrings [
        "[╭─](blue)"
        "$os"
        "$directory"
        "$git_branch"
        "$git_state"
        "$git_status"
        "$git_metrics"
        "$nix_shell"
        "$fill"
        "$claude_model"
        "$claude_context"
        "$claude_cost"
        "$cmd_duration"
        "$status"
        "$jobs"
        "$battery"
        "$time"
        "$line_break"
        "[╰─](blue)"
        "$character"
      ];

      # Линия между левым и правым блоком.
      #
      # Цвет всей «обвязки» (рамка, точки, часы) — blue, а не bold black.
      # bold black = ANSI color8, тёмно-серый: в текущей палитре это
      # #393939 на фоне #161616, контраст 1.6:1 — не видно вообще. И это
      # свойство не конкретных обоев: color8 в ЛЮБОЙ тёмной палитре
      # останется тёмно-серым, так что «ехать за обоями» здесь значит
      # «быть невидимым всегда». blue — это color4, у noctalia он совпадает
      # со стартом градиента рамки окон в niri и с активной вкладкой kitty.
      fill = {
        symbol = "·";
        style = "blue";
      };

      # Снежинка NixOS. Дефолт — эмодзи ❄️, но она двойной ширины и
      # ломает выравнивание; берём глиф из Nerd Font (U+F313).
      os = {
        disabled = false;
        format = "[$symbol]($style)";
        style = "bold blue";
        symbols.NixOS = " ";
      };

      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
        vimcmd_symbol = "[❮](bold yellow)";
      };

      # Путь тусклый, корень репозитория — ярче: сразу видно, где начинается
      # проект и где я внутри него.
      directory = {
        style = "blue";
        repo_root_style = "bold blue";
        truncation_length = 3;
        truncation_symbol = "…/";
        truncate_to_repo = false;
        read_only = " 󰌾";
      };

      # Дефолтный формат — "on  master"; слово "on" лишнее, глифа достаточно.
      git_branch = {
        # ИМЕННО purple: у starship нет цвета "magenta" — неизвестное имя
        # молча отбрасывается вместе со всем стилем, ветка выходит белой.
        style = "bold purple";
        format = "[$symbol$branch]($style) ";
      };
      git_state.style = "bold red";
      git_status = {
        style = "bold yellow";
        ahead = "⇡$count";
        behind = "⇣$count";
        diverged = "⇕⇡$ahead_count⇣$behind_count";
      };

      # Сколько строк добавлено и убрано в рабочем дереве.
      git_metrics = {
        disabled = false;
        added_style = "bold green";
        deleted_style = "bold red";
        format = "([+$added]($added_style))([−$deleted]($deleted_style)) ";
      };

      # Показывать длительность только у команд дольше 2 секунд.
      cmd_duration = {
        min_time = 2000;
        style = "yellow";
        format = "[$duration]($style) ";
      };

      # Код выхода упавшей команды. По умолчанию модуль выключен.
      status = {
        disabled = false;
        symbol = "✘ ";
        style = "bold red";
        format = "[$symbol$status]($style) ";
      };

      jobs = {
        symbol = "";
        style = "bold cyan";
        format = "[$symbol$number]($style) ";
      };

      # Батарея показывается ТОЛЬКО когда пора беспокоиться: до 15% красным,
      # до 30% жёлтым, выше — молчит. Порог в display — верхняя граница,
      # поэтому список идёт по возрастанию.
      battery = {
        format = "[$symbol$percentage]($style) ";
        display = [
          { threshold = 15; style = "bold red"; }
          { threshold = 30; style = "bold yellow"; }
        ];
      };

      time = {
        disabled = false;
        format = "[ $time]($style)";
        time_format = "%R";
        style = "blue";
      };

      # Видеть, что сижу в nix shell / nix develop.
      nix_shell = {
        symbol = " ";
        style = "bold cyan";
        format = "via [$symbol$state]($style) ";
      };

      # Модули Claude Code (starship 1.26, включены по умолчанию): модель,
      # шкала заполнения контекста с порогами 30/60/80 и стоимость сессии.
      # Вне сессии не рисуются — у нулевого порога стоит hidden = true.
      # Эмодзи в symbol оставлены дефолтными: они точно есть в любом шрифте,
      # в отличие от глифов робота и монеты из Nerd Font.
      claude_context.gauge_width = 5;
    };
  };

  # --- kitty ---
  programs.kitty = {
    enable = true;

    # Вариант Mono, и это не косметика: у сборок Nerd Fonts именно в нём
    # иконочные глифы ужаты до ОДИНАРНОЙ ширины ячейки. В обычном
    # «JetBrainsMono Nerd Font» они двойные и разъезжаются по сетке в
    # любом TUI. Та же причина, по которой у стоявшего здесь раньше
    # Lyth Mono брался вариант Term.
    #
    # Nerd-глифы вшиты, поэтому ни symbol_map, ни запасного шрифта не
    # нужно. Лигатуры у JetBrains есть — значит disable_ligatures ниже
    # не висит впустую.
    #
    # Шрифт шире Iosevka, из которой собран Lyth: на 13 pt в окно
    # помещается заметно меньше колонок, чем помещалось на 11.5.
    font = {
      name = "JetBrainsMono Nerd Font Mono";
      size = 13;
    };

    settings = {
      # Рамку и тень рисует niri, свои декорации не нужны.
      hide_window_decorations = "yes";
      window_padding_width = 14;
      # Когда окно в терминале одно (обычный случай — разделением занят
      # niri), воздуха можно дать больше. На сплиты продолжает
      # действовать window_padding_width выше.
      single_window_padding_width = 20;
      confirm_os_window_close = 0;

      # Прозрачности НЕТ НИГДЕ, и 1.0 стоит явно.
      #
      # Раньше здесь было то же 1.0, но по другой причине: прозрачность
      # целиком отдавалась niri (window-rule по app-id kitty, opacity
      # 0.92), а два коэффициента иначе перемножались бы. Теперь и та
      # window-rule снята — при 0.92 поверх светлых обоев фон терминала
      # на две трети состоял из обоев, и никакой чернотой темы это не
      # пробивалось. Замеры и разбор — в home/niri/config.kdl, на месте
      # снятого правила.
      #
      # background_blur включать бессмысленно при любом раскладе: он
      # требует протокола блюра от композитора, а у niri его нет.
      background_opacity = "1.0";
      # Оставлено, чтобы прозрачность можно было попробовать на живую
      # (kitty @ set-background-opacity), не пересобирая систему.
      dynamic_background_opacity = "yes";

      # Фон — вертикальный градиент, темнее сверху. Настройки «градиент»
      # у kitty нет, есть только картинка; её рисует post_hook шаблона
      # темы (home/kitty/gradient.sh) из цветов текущей палитры.
      #
      # ПУТЬ — ГЛОБ, И ЭТО НЕ УКРАШЕНИЕ. kitty подменяет фоновую картинку
      # на релоаде, только если изменилась строка пути (boss.py:989), а
      # глоб раскрывается при разборе конфига (options/utils.py:876).
      # Поэтому скрипт пишет файл с новым именем при каждой смене палитры
      # — иначе фон остался бы от прежних обоев. Подробности — в скрипте.
      #
      # Если каталог пуст (чистая машина до первого применения темы) —
      # kitty просто заливает фон цветом background из темы, который
      # совпадает с серединой градиента.
      background_image = "~/.config/kitty/backgrounds/*.png";
      background_image_layout = "scaled";
      # Без интерполяции на растяжении 512 px по высоте до высоты экрана
      # видны ступеньки.
      background_image_linear = "yes";
      # Гасить картинку нечем: она уже нарисована цветами палитры.
      background_tint = "0.0";
      background_tint_gaps = "0.0";

      # Табы: скошенный powerline вместо заводских прямоугольников.
      # Панель появляется от двух табов (tab_bar_min_tabs по умолчанию 2).
      tab_bar_edge = "top";
      tab_bar_style = "powerline";
      tab_powerline_style = "slanted";
      active_tab_font_style = "bold";
      # Поля панели табов (в pt): первое — от края окна, второе — до
      # содержимого. Панель перестаёт быть приклеенной к тексту.
      tab_bar_margin_height = "6.0 6.0";
      tab_bar_margin_width = "8.0";
      tab_bar_align = "center";
      # Номер таба перед заголовком: по нему же переключение (Ctrl+Shift+N).
      tab_title_template = "{index}  {title}";

      # Шлейф за курсором (kitty 0.47). Значение — порог в МИЛЛИСЕКУНДАХ:
      # шлейф рисуется только за курсором, простоявшим дольше порога,
      # иначе он тянулся бы за каждой перерисовкой TUI.
      cursor_trail = 3;
      cursor_trail_start_threshold = 2;
      cursor_shape = "beam";
      # Шлейф гаснет быстрее заводского (0.1 0.4): меньше «мыла» при
      # быстром движении по строке.
      cursor_trail_decay = "0.05 0.3";
      # Мигание с плавным затуханием, а не рубленое вкл/выкл.
      cursor_blink_interval = "0.6 ease-in-out";
      cursor_stop_blinking_after = "12.0";
      # В неактивном сплите курсор — контур: видно, где он, но глаз не тянет.
      cursor_shape_unfocused = "hollow";

      # Лигатуры нужны, но под курсором разъезжаются — там показываем раздельно.
      disable_ligatures = "cursor";

      # Скроллбар (kitty 0.48). Показывается при наведении на правый край,
      # чтобы не отъедать колонку постоянно. Ширина и радиус — в ширинах
      # ячейки, радиус обязан быть меньше ширины. Трек невидимый: нужна
      # только сама ручка.
      scrollbar = "hovered";
      scrollbar_width = "0.4";
      scrollbar_radius = "0.2";
      scrollbar_gap = "0.15";
      scrollbar_handle_color = "selection_background";
      scrollbar_handle_opacity = "0.7";
      scrollbar_track_opacity = "0.0";

      # Указатель мыши убирается сразу, как начал печатать (отрицательное
      # значение именно это и означает), а не через 3 секунды.
      mouse_hide_wait = "-1.0";
      # Текст в неактивном сплите чуть тусклее — видно, где фокус.
      inactive_text_alpha = "0.9";

      scrollback_lines = 20000;
      enable_audio_bell = "no";
      # Звонок выключен, поэтому единственный сигнал — короткая вспышка.
      visual_bell_duration = "0.12 ease-out";
    };

    # Палитра от noctalia. Путь ОБЯЗАН быть абсолютным.
    # Относительный include kitty резолвит относительно каталога САМОГО
    # конфига (lib/kitty/kitty/conf/utils.py:372), а конфиг теперь лежит
    # в /nix/store — тема бы не нашлась, и цвета молча съехали бы на
    # дефолтные. expanduser в путях include поддерживается (там же, 295),
    # поэтому "~" работает.
    extraConfig = ''
      # Здесь стояли три modify_font: cell_height 110% ради межстрочного
      # воздуха на 11.5 pt и две правки подчёркивания. Сняты вместе со
      # сменой шрифта: на 13 pt воздуха хватает и так (110% сверху съедали
      # бы заметную долю строк на 1080p), а числа для подчёркивания
      # ставились под метрики Lyth и к JetBrains отношения не имеют —
      # пусть шрифт считает их сам.
      #
      # Гамма и добавочный контраст при наложении глифов на фон. На Linux
      # заводское — «1.0 0»; второе число поднято, потому что светлый текст
      # на почти чёрном фоне заводскими настройками выходит тонковатым.
      text_composition_strategy 1.0 12

      include ~/.config/kitty/themes/noctalia.conf
    '';
  };

  # ЗАТРАВОЧНАЯ картинка для glob'а background_image. Нужна ровно для
  # одного случая: каталог backgrounds пуст — чистая машина до первого
  # применения темы, или тема снята. Без неё kitty при КАЖДОМ запуске
  # печатает в stderr питоновский traceback (проверено):
  #   Failed to convert image at .../backgrounds/*.png to bitmap
  #   FileNotFoundError: ... '.../backgrounds/*.png'
  # Не смертельно, но шумно, и мусорит в выводе скриптов.
  #
  # Имя выбрано так, чтобы файл сортировался ПОСЛЕ сгенерированных
  # bg-<hex>.png ('s' > 'f'): kitty показывает ПЕРВУЮ картинку из
  # раскрытого glob'а, значит настоящая всегда перебивает затравку.
  # Уборку в gradient.sh затравка переживает: home-manager кладёт сюда
  # симлинк, а find там стоит на -type f.
  #
  # Цвета нейтральные, не из палитры: на этом этапе палитры ещё нет.
  # Параметры magick — те же, что в gradient.sh.
  xdg.configFile."kitty/backgrounds/bg-seed.png".source =
    pkgs.runCommand "kitty-bg-seed.png" { } ''
      ${pkgs.imagemagick}/bin/magick -size 256x512 'gradient:#060607-#111214' \
        -attenuate 0.03 +noise Gaussian -depth 8 png:"$out"
    '';

  # --- tmux ---
  # Пакет объявлен в systemPackages (modules/common.nix), здесь только
  # конфиг — ровно та же схема, что у kitty выше.
  #
  # Берётся ради одного: сессия переживает закрытие терминала. Делить
  # экран на панели по-хорошему незачем (этим занят niri), но раз уж
  # панели есть, биндам стоит быть привычными — отсюда всё ниже.
  programs.tmux = {
    enable = true;

    # Заводской префикс Ctrl-b требует тянуться мизинцем через весь ряд.
    # Ctrl-a ближе; модуль на смену префикса сам дописывает
    # `bind C-a send-prefix` (HM, modules/programs/tmux.nix:99), поэтому
    # «в начало строки» в fish внутри tmux — это Ctrl-a Ctrl-a.
    prefix = "C-a";

    # Окна и панели нумеруются с 1: на цифровом ряду 1 идёт первой,
    # а 0 стоит за 9 — с нуля попадать неудобно.
    baseIndex = 1;

    # copy-mode с биндами vim — как в nixvim ниже, чтобы не переучиваться.
    # customPaneNavigationAndResize действует ТОЛЬКО при keyMode = "vi"
    # (там же, :74) и даёт hjkl на переход между панелями, HJKL на размер.
    keyMode = "vi";
    customPaneNavigationAndResize = true;
    resizeAmount = 5;

    mouse = true;         # колесо — скроллбек, клик — панель, драг границы — размер
    focusEvents = true;   # vim узнаёт про потерю фокуса, autoread оживает
    historyLimit = 50000; # заводские 2000 строк кончаются на первом же сборочном логе

    # Заводские 500 мс — это пауза после Esc, в vim она ощущается как
    # залипание. 0 не ставлю: по ssh при нуле рвутся escape-последовательности.
    escapeTime = 10;

    # Без этого TERM внутри tmux = "screen", и подсветка деградирует до 8 цветов.
    terminal = "tmux-256color";

    # =========================================================
    # Плагины.
    #
    # ПОРЯДОК В ИТОГОВОМ ФАЙЛЕ (HM, modules/programs/tmux.nix:360) —
    # mkBefore(база) → плагины → mkAfter(extraConfig). То есть всё, что
    # плагин должен УВИДЕТЬ при загрузке, обязано лежать в его собственном
    # extraConfig: он идёт прямо перед его run-shell. Из общего extraConfig
    # ниже плагин уже ничего не прочитает — тот выполняется последним.
    # На этом ловится prefix-highlight, см. его блок.
    #
    # Имена пакетов обязаны начинаться на "tmuxplugin", иначе модуль роняет
    # eval по assertion (там же, :118).
    # =========================================================
    plugins = with pkgs.tmuxPlugins; [
      # ---- floax: всплывающая панель поверх окна ----
      {
        plugin = tmux-floax;
        extraConfig = ''
          # Заводской бинд p ЗАТЕНЯЕТ previous-window. Оставлен как есть:
          # так написано во всех гайдах по плагину, а на предыдущее окно
          # у нас и так повешен Alt-H без префикса.
          set -g @floax-bind 'p'
          set -g @floax-bind-menu 'P'
          set -g @floax-width '80%'
          set -g @floax-height '80%'
          # Панель открывается в каталоге текущей панели, а не в $HOME.
          set -g @floax-change-path 'true'
          # Плагин принимает ТОЛЬКО восемь базовых имён (black..white), не hex —
          # то есть цвет берётся из палитры терминала, как у всего остального.
          set -g @floax-border-color 'blue'
          set -g @floax-text-color 'blue'
        '';
      }

      # ---- sessionx: переключалка сессий на fzf ----
      {
        plugin = tmux-sessionx;
        extraConfig = ''
          # O, а не o: строчная занята под next-pane.
          set -g @sessionx-bind 'O'
          # Показывать в списке не только живые сессии, но и каталоги из базы
          # zoxide (programs.zoxide ниже) — прыжок в проект сразу создаёт сессию.
          set -g @sessionx-zoxide-mode 'on'
          set -g @sessionx-preview-enabled 'true'
          set -g @sessionx-preview-ratio '55%'
          set -g @sessionx-window-width '80%'
          set -g @sessionx-window-height '75%'
          # Текущую сессию из списка убрать — прыгать в себя незачем.
          set -g @sessionx-filter-current 'true'
        '';
      }

      # ---- which-key: всплывающая шпаргалка по биндам ----
      {
        plugin = tmux-which-key;
        extraConfig = ''
          # ОБЯЗАТЕЛЬНО. Без этого плагин при старте копирует config.yaml и
          # init.tmux к себе в каталог установки — то есть в /nix/store, куда
          # писать нельзя, и падает. С флагом он уходит в
          #   ~/.config/tmux/plugins/tmux-which-key/config.yaml   (меню)
          #   ~/.local/share/tmux/plugins/tmux-which-key/init.tmux (сборка)
          # Апстрим держит эту опцию ровно для «immutable or declarative
          # operating systems» (README, раздел @tmux-which-key-xdg-enable).
          #
          # Оба файла — ИЗМЕНЯЕМОЕ состояние, nix ими не управляет: они
          # создаются из примеров при первом запуске плагина.
          set -g @tmux-which-key-xdg-enable 1

          # ОБЯЗАТЕЛЬНО ВТОРОЕ. Плагин копирует шаблоны из /nix/store
          # обычным `cp`, а тот сохраняет права источника — то есть 0444.
          # Дальше автосборка меню зовёт build.py, который открывает
          # init.tmux на запись, и падает на своей же копии:
          #   PermissionError: [Errno 13] .../init.tmux
          # а вместе с ним валится весь plugin.sh.tmux (там `set -e`), и
          # бинд на Space не доходит до tmux вообще.
          #
          # Автосборка нужна только чтобы пересобрать меню из config.yaml.
          # Скопированный init.tmux уже готовый и рабочий, так что просто
          # выключаем её — плагин ограничивается source-file, а чтение
          # read-only файла никого не смущает.
          #
          # Цена: правки в config.yaml сами по себе ни на что не влияют.
          # Если понадобится своё меню — снять права-только-чтение и
          # прогнать build.py руками:
          #   chmod u+w ~/.local/share/tmux/plugins/tmux-which-key/init.tmux
          #   chmod u+w ~/.config/tmux/plugins/tmux-which-key/config.yaml
          # либо собрать init.tmux в nix и положить через xdg.dataFile.
          set -g @tmux-which-key-disable-autobuild 1
        '';
      }

      # ---- prefix-highlight: индикатор нажатого префикса ----
      {
        plugin = prefix-highlight;
        extraConfig = ''
          set -g @prefix_highlight_fg 'colour0'
          set -g @prefix_highlight_bg 'colour4'
          set -g @prefix_highlight_prefix_prompt ' ^A '
          # Заодно подсвечивать copy-mode: видно, что ты не в оболочке и
          # клавиши уходят не туда, куда привык.
          set -g @prefix_highlight_show_copy_mode 'on'
          set -g @prefix_highlight_copy_mode_attr 'fg=colour0,bg=colour3'
          set -g @prefix_highlight_copy_prompt ' COPY '
          # Когда префикс не нажат — пусто, чтобы строка не дёргалась.
          set -g @prefix_highlight_empty_prompt ""

          # status-left стоит ЗДЕСЬ, а не в общем extraConfig, и это не каприз.
          # Плагин не добавляет формат от себя: он читает текущее значение
          # status-left, подменяет в нём литерал #{prefix_highlight} на готовую
          # строку и записывает обратно (prefix_highlight.tmux:97). Значит
          # плейсхолдер обязан существовать ДО его run-shell. Общий extraConfig
          # выполняется после плагинов и просто затёр бы результат.
          set -g status-left "#[fg=colour4,bold] #S #[default]#{prefix_highlight}"
        '';
      }
    ];

    extraConfig = ''
      # ---- truecolor ----
      # tmux-256color объявляет 256 цветов; RGB добавляется оверрайдом на
      # ВНЕШНИЙ терминал, а не на внутренний. kitty представляется как
      # xterm-kitty; вторая запись — на случай ssh с чужой машины.
      set -ga terminal-overrides ",xterm-kitty:RGB,xterm-256color:RGB"

      # ---- сплиты ----
      # | и - вместо % и ": символ совпадает с направлением разреза.
      # -c "#{pane_current_path}" — новая панель открывается в текущем
      # каталоге, а не в $HOME (заводское поведение, которое всех бесит).
      unbind '"'
      unbind %
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind c new-window -c "#{pane_current_path}"

      # ---- окна ----
      # Закрыли окно посередине — остальные перенумеровываются, дырок в
      # ряду 1..9 не остаётся.
      set -g renumber-windows on
      # Соседнее окно без префикса, одной комбинацией.
      bind -n M-H previous-window
      bind -n M-L next-window

      # ---- буфер обмена ----
      # Выделение как в vim: v — начать, y — скопировать. copy-pipe отдаёт
      # выделенное в wl-copy (wl-clipboard в systemPackages), то есть в
      # СИСТЕМНЫЙ буфер, а не только во внутренний буфер tmux.
      bind -T copy-mode-vi v send-keys -X begin-selection
      bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "wl-copy"
      # Мышью: отпустили кнопку — скопировалось, но copy-mode не закрылся и
      # вид не прыгнул в конец скроллбека (в этом весь смысл -no-clear).
      bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-no-clear "wl-copy"
      # OSC52: тот же буфер работает, когда tmux крутится на УДАЛЁННОЙ машине
      # по ssh — там wl-copy нет, последовательность уходит в kitty, и уже он
      # кладёт текст в wayland-буфер. Локально дублирует wl-copy, не мешает.
      set -g set-clipboard on

      # ---- перезагрузка конфига ----
      # Сам файл — read-only симлинк в /nix/store, правки идут через rebuild.
      # Бинд нужен, чтобы подхватить новый конфиг в уже живой сессии, не
      # убивая её.
      bind r source-file ~/.config/tmux/tmux.conf \; display "конфиг перечитан"

      # ---- статус-строка ----
      # Цвета — номерами ANSI-палитры (colour0..15), ни одного hex: строка
      # едет за темой kitty, которую красит noctalia по обоям. Тот же приём,
      # что у bat, fzf, delta и starship выше.
      # bg=default — фон терминала, то есть прозрачность от niri сохраняется.
      set -g status-position bottom
      set -g status-style "bg=default,fg=colour7"
      set -g status-interval 5
      # status-left задаётся НЕ здесь, а в блоке плагина prefix-highlight
      # выше — иначе подстановка плейсхолдера была бы затёрта, см. там же.
      # Длину поднял с 30: индикатор префикса добавляет ширины.
      set -g status-left-length 60
      set -g status-right "#[fg=colour8]%H:%M "
      set -g window-status-format " #I:#W "
      set -g window-status-current-format " #I:#W "
      set -g window-status-current-style "fg=colour4,bold"
      set -g pane-border-style "fg=colour8"
      set -g pane-active-border-style "fg=colour4"
      set -g message-style "bg=colour4,fg=colour0"
      # Заводская 750 мс — сообщение исчезает раньше, чем успеваешь прочесть.
      set -g display-time 2000

      # ---- раскладка ----
      # Зеркалит все бинды таблиц prefix и copy-mode-vi в кириллицу, чтобы
      # Ctrl-a c и Ctrl-a с делали одно и то же. Стоит В САМОМ КОНЦЕ и это
      # важно: снимок таблицы берётся на момент запуска, всё, что биндится
      # позже, в зеркало не попадёт. extraConfig модуль кладёт после
      # плагинов (HM, modules/programs/tmux.nix:360), так что их бинды
      # уже на месте. Подробности — у tmuxMirror в начале файла.
      run-shell ${tmuxMirror}
    '';
  };

  # --- smug: сессии tmux из описания ---
  # Пакет — в systemPackages (modules/common.nix), здесь только конфиг:
  # ровно та же схема, что у tmux выше и у kitty.
  #
  # smug ищет сессии в ~/.config/smug/*.yml. Кроме того он подхватывает
  # `.smug.yml` из ТЕКУЩЕГО каталога — то есть описание сессии можно класть
  # прямо в репозиторий проекта и в этот флейк не тащить вовсе.
  #
  # Симлинком кладётся ТОЛЬКО сам yml, а каталог ~/.config/smug остаётся
  # настоящим и на запись. Это важно: туда smug пишет smug.log при запуске
  # с флагом -d, и туда же можно бросить одноразовый конфиг мимо git.
  #
  # TEMPLATE.yml.example, лежащий рядом в home/smug/, намеренно НЕ подключён:
  # это шпаргалка по формату для правок здесь, в рабочем каталоге smug ей
  # делать нечего.
  xdg.configFile."smug/nixos.yml".source = ./smug/nixos.yml;

  # --- mpv: видеоплеер ---
  # Пакет — в systemPackages (modules/common.nix), здесь только конфиг:
  # ровно та же схема, что у kitty, tmux и smug выше.
  programs.mpv = {
    enable = true;

    config = {
      # Аппаратное декодирование. Именно auto-safe, а не auto: включается
      # только на связках драйвер+кодек из белого списка (nvdec на десктопе,
      # vaapi на ноуте), на всём остальном честный софт вместо чёрного кадра
      # или артефактов. На ноуте это ещё и батарея: 4K иначе греет процессор.
      hwdec = "auto-safe";

      # Не закрывать окно на последнем кадре, а вставать на паузу: иначе
      # конец серии — это внезапно пустой рабочий стол.
      keep-open = "yes";

      # Продолжать с места остановки: при выходе по `q` позиция пишется в
      # ~/.local/state/mpv/watch_later. Досмотреть фильм в два захода без
      # этого можно только вручную отматывая.
      save-position-on-quit = true;

      # Субтитры, лежащие рядом с файлом. fuzzy — подхватывать «Movie.ru.srt»
      # к «Movie.mkv», а не только точное совпадение имени: как раз случай
      # раздач, которые качает qbittorrent.
      sub-auto = "fuzzy";
      # Порядок выбора дорожек, если их в контейнере несколько.
      slang = "rus,ru,eng,en";
      alang = "rus,ru,eng,en";

      # Тихие дорожки: до 130 %, дальше уже слышны искажения.
      volume-max = 130;

      # Скриншот (`s`) по умолчанию падает в каталог, откуда запущен mpv, —
      # то есть куда попало. Кладём к остальным картинкам, png без потерь.
      screenshot-directory = "~/Pictures";
      screenshot-format = "png";
    };

    # Латинские бинды + их кириллические зеркала, см. let выше.
    bindings = mpvBindings;
  };

  # --- монитор ресурсов (вместо glances) ---
  programs.btop.enable = true;

  # --- аварийный простой редактор ---
  programs.micro.enable = true;

  # --- neovim через nixvim: весь конфиг описан на nix, декларативно ---
  programs.nixvim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    # ---- Тема: статичный синтаксис, фон от noctalia ----
    #
    # Раньше цвет редактора выводился из обоев: шаблон community/neovim
    # рендерил ~/.config/nvim/lua/matugen.lua с вызовом base16-colorscheme,
    # и это была та же линия, что у bat (theme = "ansi") и fzf (--color=16).
    # Не сработало, и причина структурная. В base16 восемь акцентных слотов,
    # а в Material You акцентных ролей четыре — primary, secondary, tertiary,
    # error. Остальные четыре слота шаблон брал из *_fixed_dim-вариантов,
    # которые в Material You совпадают с базовым цветом до хекса: base0D
    # (функции) = base0B (строки), base0E (ключевые слова) = base0A (типы).
    # Восемь слотов схлопывались в четыре цвета, а из этих четырёх primary
    # и secondary отличались на 3 единицы RGB. В итоге ключевые слова, типы,
    # функции и строки красились одним синим — на C# это видно особенно
    # хорошо. Развести дубли было бы мало: Material You выводит всю палитру
    # из одного цвета обоев, потолок здесь — три различимых акцента.
    #
    # Поэтому синтаксис фиксируем, а связь с обоями сохраняем через фон:
    # transparent_background отдаёт фон терминалу, а kitty noctalia красит
    # по-прежнему (см. programs.kitty ниже). Общий тон едет за картинкой,
    # читаемость кода от неё больше не зависит, и шва в паддингах kitty нет.
    #
    # integrations не перечисляем: default_integrations в модуле по умолчанию
    # true, и cmp, telescope, gitsigns, nvimtree, treesitter, which-key,
    # trouble, indent-blankline, lualine подхватываются сами.
    #
    # ВАЖНО: вместе с любым colorschemes.* нужен telescope.highlightTheme =
    # null, иначе вернётся старая беда с $BAT_THEME — см. блок telescope ниже.
    colorschemes.catppuccin = {
      enable = true;
      settings = {
        flavour = "mocha";
        transparent_background = true;
        term_colors = true;
      };
    };

    # Ссылки в комментариях не выделяем. Парсер `comment` (инъекция в тело
    # `///`) вешает на URL захват @string.special.url, а catppuccin красит его
    # голубым курсивом с подчёркиванием — groups/treesitter.lua:37. В доксигеновых
    # комментариях, где ссылка на MSDN стоит почти над каждым объявлением, это
    # рвёт текст полосами. Линкуем группу на @comment: цвет тогда едет за темой
    # сам, отдельный хекс держать не нужно.
    #
    # Именно highlightOverride, а не highlight: первый попадает в
    # extraConfigLuaPost, то есть ПОСЛЕ `colorscheme catppuccin`, второй — в Pre,
    # и тема его затрёт. custom_highlights самой catppuccin тоже не подходит:
    # она мержит группы через tbl_deep_extend("keep", …), и массив style из темы
    # возвращается назад целиком.
    #
    # @markup.link.url намеренно не трогаем — это ссылки в markdown, там
    # выделение уместно.
    highlightOverride."@string.special.url".link = "@comment";

    # базовые опции редактора
    opts = {
      number = true;
      relativenumber = true;
      shiftwidth = 2;
      tabstop = 2;
      expandtab = true;
      smartindent = true;
      ignorecase = true;
      smartcase = true;
      termguicolors = true;
      scrolloff = 8;
      signcolumn = "yes";

      # История отмен переживает закрытие файла (~/.local/state/nvim/undo).
      undofile = true;
      # Заводские 4000 мс — задержка перед CursorHold, на ней висят подсветка
      # ссылок и всплывающая диагностика от LSP. 250 мс ощущается мгновенным.
      updatetime = 250;
      # Сколько ждать продолжения аккорда: столько живёт окно which-key.
      timeoutlen = 400;
      splitbelow = true;
      splitright = true;
      cursorline = true;
      # Перенос длинных строк выключен: в коде он ломает счёт строк глазами.
      wrap = false;
      # :q с несохранёнными правками спрашивает, а не отказывается молча.
      confirm = true;
      mouse = "a";

      # Normal и visual mode работают в русской раскладке: й = q, ц = w и так
      # далее (таблица — в home/keyboard-ru.nix). Insert mode langmap не
      # трогает вообще, русский текст набирается как обычно.
      langmap = kbd.langmap;

      # Обязателен в паре с langmap. Иначе перевод применяется ЕЩЁ РАЗ к тому,
      # что вернул пользовательский маппинг, и <leader>ff перестаёт открывать
      # Telescope. Заводское значение в neovim уже false, но пусть стоит явно —
      # опция ровно про этот случай.
      langremap = false;
    };

    globals.mapleader = " ";   # leader = пробел

    # Системный буфер обмена вместо безымянного регистра: y/p работают с тем
    # же wl-copy, что и остальной wayland-десктоп. Провайдер объявлен явно,
    # иначе nixvim ищет xclip/xsel и в чистом wayland-сеансе не находит.
    # Сам wl-clipboard уже в systemPackages (modules/common.nix).
    clipboard = {
      register = "unnamedplus";
      providers.wl-copy.enable = true;
    };

    # Диагностика: сортировка по важности (ошибка выигрывает у подсказки на
    # той же строке) и рамка у всплывающего окна — в тон остальным окнам LSP.
    diagnostic.settings = {
      virtual_text = true;
      severity_sort = true;
      float.border = "rounded";
    };

    # ---- LSP: общее для ВСЕХ серверов ----
    #
    # Это новый модуль nixvim (`lsp.*`, поверх vim.lsp), а не legacy
    # `plugins.lsp.*` ниже. Разделение осознанное:
    #   * серверы остаются в legacy-модуле — он сам подмешивает им
    #     capabilities от nvim-cmp, и переписывать рабочее незачем;
    #   * а keymaps нужны ИМЕННО отсюда: они вешаются на событие LspAttach и
    #     потому срабатывают и для roslyn, которого поднимает не nixvim, а
    #     плагин roslyn.nvim. Кеймапы legacy-модуля до него не дотянулись бы.
    lsp = {
      # Подсказки типов и имён параметров прямо в тексте. Для C# это половина
      # смысла LSP: var и целевые типы иначе просто не видно.
      inlayHints.enable = true;

      # Те самые capabilities для серверов мимо legacy-модуля (roslyn).
      # Без них cmp не получит от сервера ни сниппетов, ни дорезолвки
      # документации. `*` — псевдосервер vim.lsp.config с общими значениями.
      servers."*".config.capabilities.__raw =
        "require('cmp_nvim_lsp').default_capabilities()";

      # Все клавиши пишутся ЛАТИНИЦЕЙ — в русской раскладке их подхватит
      # langmap выше (gd = пв, K = Л и так далее). См. комментарий к langmap.
      keymaps = [
        { key = "gd"; lspBufAction = "definition";      options.desc = "К определению"; }
        { key = "gD"; lspBufAction = "declaration";     options.desc = "К объявлению"; }
        { key = "gi"; lspBufAction = "implementation";  options.desc = "К реализации"; }
        { key = "gt"; lspBufAction = "type_definition"; options.desc = "К определению типа"; }
        { key = "gr"; action = "<cmd>Telescope lsp_references<cr>"; options.desc = "Использования"; }
        { key = "K";  lspBufAction = "hover";           options.desc = "Документация"; }

        { key = "<leader>rn"; lspBufAction = "rename";      options.desc = "Переименовать"; }
        { key = "<leader>ca"; lspBufAction = "code_action"; options.desc = "Действия с кодом"; }
        {
          key = "<leader>cf";
          action = "<cmd>lua require('conform').format({ lsp_format = 'fallback' })<cr>";
          options.desc = "Форматировать файл";
        }

        # vim.diagnostic.goto_next/goto_prev выпилены в neovim 0.11,
        # актуальный интерфейс — jump({ count = ... }).
        {
          key = "[d";
          action.__raw = "function() vim.diagnostic.jump({ count = -1, float = true }) end";
          options.desc = "Предыдущая диагностика";
        }
        {
          key = "]d";
          action.__raw = "function() vim.diagnostic.jump({ count = 1, float = true }) end";
          options.desc = "Следующая диагностика";
        }
      ];
    };

    plugins = {
      web-devicons.enable = true;   # иконки для дерева/telescope
      nvim-tree.enable = true;      # дерево файлов слева
      lualine.enable = true;        # статусная строка
      gitsigns = {
        enable = true;              # git-пометки в gutter
        settings = {
          # Различия ВНУТРИ строки, а не «строка целиком изменена». Без
          # этого inline-превью (<leader>hi) показывает две почти
          # одинаковые строки, и отличие приходится искать глазами.
          word_diff = true;
          # Тот же бордюр, что у диагностических float'ов выше.
          preview_config.border = "rounded";
        };
      };

      # Оверлей diff по всему файлу: старые строки — виртуальными строками
      # над новыми, как рисуют дифф ИИ-агенты. У gitsigns для этого есть
      # show_deleted, но он помечен deprecated и в setup() ИГНОРИРУЕТСЯ с
      # предупреждением, поэтому постоянный оверлей взят у mini.diff.
      # Бинд — <leader>ho, группа «Git-ханки».
      mini = {
        enable = true;
        modules.diff = {
          # style ЯВНО, а не дефолтом. mini.diff выводит его из vim.go.number
          # на момент setup(), и полагаться на порядок вычисления opts не
          # стоит. Смысл выбора: signcolumn остаётся за gitsigns, mini.diff
          # красит колонку номеров — два индикатора не дерутся за место.
          view.style = "number";

          # Навигация и стейдж уже висят на gitsigns (]c/[c, <leader>hs/hr).
          # Свой набор gh/gH/]h поставил бы рядом конкурирующие бинды на ту
          # же работу, поэтому гасится целиком: пустая строка = «не вешать».
          mappings = {
            apply = "";
            reset = "";
            textobject = "";
            goto_first = "";
            goto_prev = "";
            goto_next = "";
            goto_last = "";
          };
        };
      };
      comment.enable = true;        # gcc — закомментить строку
      nvim-autopairs.enable = true; # авто-закрытие скобок
      nvim-surround.enable = true;  # cs"' — поменять окружающие кавычки
      todo-comments.enable = true;  # подсветка TODO/FIXME
      indent-blankline.enable = true;
      lspkind.enable = true;        # иконки видов символов в меню cmp
      luasnip.enable = true;        # движок сниппетов, нужен cmp ниже
      bufferline.enable = true;     # строка буферов сверху

      # :Bdelete вместо штатного :bdelete. Разница ровно одна, но
      # существенная: штатный вместе с буфером закрывает и ОКНО, в котором
      # тот показан. При сплите или открытом дереве файлов раскладка
      # разъезжается на каждом закрытии вкладки. :Bdelete подставляет в
      # окно соседний буфер и оставляет геометрию как была.
      # Кеймапы — ниже, группа <leader>b.
      bufdelete.enable = true;

      # Прогресс LSP в углу. Не косметика: roslyn грузит solution десятки
      # секунд, и без индикатора это неотличимо от «ничего не работает».
      fidget.enable = true;

      # Список диагностик по проекту одним окном.
      trouble.enable = true;

      # lazygit прямо в редакторе — тот же, что по абревиатуре `lg` в fish.
      lazygit.enable = true;

      # Отдельное окно side-by-side: слева HEAD, справа рабочее дерево,
      # список изменённых файлов сбоку. Нужен там, где inline не годится —
      # когда ревьюится не ханк, а ветка или коммит целиком. Бинды —
      # группа <leader>g.
      diffview.enable = true;

      # Подсказки по хоткеям. spec задаёт НАЗВАНИЯ групп — без него вместо
      # них показываются безымянные «+prefix».
      which-key = {
        enable = true;
        settings.spec = [
          { __unkeyed-1 = "<leader>b"; group = "Буферы"; }
          { __unkeyed-1 = "<leader>f"; group = "Поиск"; }
          { __unkeyed-1 = "<leader>c"; group = "Код"; }
          { __unkeyed-1 = "<leader>d"; group = ".NET"; }
          { __unkeyed-1 = "<leader>g"; group = "Git"; }
          { __unkeyed-1 = "<leader>h"; group = "Git-ханки"; }
          { __unkeyed-1 = "<leader>x"; group = "Диагностика"; }
          { __unkeyed-1 = "<leader>r"; group = "Рефакторинг"; }
        ];
      };

      treesitter = {
        enable = true;
        # ОБЯЗАТЕЛЬНО: без явного highlight nvim-treesitter ставит парсеры, но
        # не включает подсветку — раньше конфиг именно этим и грешил, вся
        # раскраска шла от старого regex-синтаксиса.
        # Грамматики отдельно перечислять не нужно: nixvim по умолчанию
        # собирает allGrammars, там уже есть c_sharp, xml, latex, markdown.
        settings = {
          highlight.enable = true;
          indent.enable = true;
        };
      };

      telescope = {
        enable = true;

        # Гасим подсветку превью «под тему редактора». Опция highlightTheme
        # в модуле nixvim объявлена как `default = config.colorscheme`, и при
        # непустом значении модуль пишет в конфиг `let $BAT_THEME = '<схема>'`.
        # Переменная перебивает programs.bat (theme = "ansi") ровно внутри
        # telescope-превью — из-за этого Catppuccin отсюда когда-то и убрали.
        # Пока colorschemes.* не был включён, значение выходило пустым само
        # собой; теперь схема есть, поэтому гасим явно.
        highlightTheme = null;

        # Нативный фильтр на C: на дереве исходников .NET разница с
        # ванильным lua-матчером заметна глазом.
        extensions.fzf-native.enable = true;

        keymaps = {
          "<leader>ff" = { action = "find_files";           options.desc = "Найти файл"; };
          "<leader>fg" = { action = "live_grep";            options.desc = "Поиск по содержимому"; };
          "<leader>fb" = { action = "buffers";              options.desc = "Буферы"; };
          "<leader>fh" = { action = "help_tags";            options.desc = "Справка"; };
          "<leader>fd" = { action = "diagnostics";          options.desc = "Диагностики проекта"; };
          "<leader>fr" = { action = "resume";               options.desc = "Повторить прошлый поиск"; };
          "<leader>fs" = { action = "lsp_document_symbols"; options.desc = "Символы файла"; };
        };
      };

      # автодополнение
      cmp = {
        enable = true;
        autoEnableSources = true;
        settings = {
          sources = [
            { name = "nvim_lsp"; }
            { name = "luasnip"; }
            { name = "path"; }
            { name = "buffer"; }
          ];

          # Как cmp разворачивает сниппет. Без этого пункт дополнения от
          # roslyn вставится сырым текстом вида `${1:value}`: сервер шлёт
          # сниппеты, потому что cmp_nvim_lsp объявил их поддержку.
          snippet.expand = ''
            function(args)
              require('luasnip').lsp_expand(args.body)
            end
          '';

          # Без этого блока у меню автодополнения НЕТ клавиш вообще: cmp не
          # раздаёт пресет сам, и <CR>/<C-Space> просто ничего не делают.
          # `cmp` и `luasnip` — локальные переменные в сгенерированном
          # init.lua, поэтому обращаемся к ним напрямую.
          mapping.__raw = ''
            cmp.mapping.preset.insert({
              ['<C-b>'] = cmp.mapping.scroll_docs(-4),
              ['<C-f>'] = cmp.mapping.scroll_docs(4),
              ['<C-Space>'] = cmp.mapping.complete(),
              ['<C-e>'] = cmp.mapping.abort(),
              ['<CR>'] = cmp.mapping.confirm({ select = true }),
              ['<Tab>'] = cmp.mapping(function(fallback)
                local luasnip = require('luasnip')
                if cmp.visible() then
                  cmp.select_next_item()
                elseif luasnip.expand_or_locally_jumpable() then
                  luasnip.expand_or_jump()
                else
                  fallback()
                end
              end, { 'i', 's' }),
              ['<S-Tab>'] = cmp.mapping(function(fallback)
                local luasnip = require('luasnip')
                if cmp.visible() then
                  cmp.select_prev_item()
                elseif luasnip.locally_jumpable(-1) then
                  luasnip.jump(-1)
                else
                  fallback()
                end
              end, { 'i', 's' }),
            })
          '';
        };
      };

      # Форматирование одним фронтендом на все языки. lsp_format = fallback:
      # если для типа файла форматтер не задан, работает сам языковой сервер.
      conform-nvim = {
        enable = true;
        settings = {
          formatters_by_ft = {
            c = [ "clang-format" ];
            cpp = [ "clang-format" ];
            cs = [ "csharpier" ];
            nix = [ "nixfmt" ];
            lua = [ "stylua" ];
            sh = [ "shfmt" ];
            # Только лишние пустые строки в конце файла. trim_whitespace сюда
            # намеренно НЕ добавлен: в markdown два пробела на конце строки —
            # это перенос, и стричь их молча при сохранении нельзя.
            "_" = [ "trim_newlines" ];
          };
          format_on_save = {
            lsp_format = "fallback";
            # csharpier — обычное .NET-приложение, первый запуск в сессии
            # уходит на прогрев рантайма; заводских 500 мс ему не хватает.
            timeout_ms = 3000;
          };
        };
      };

      # LSP: подсветка ошибок + автодополнение по языкам.
      # Здесь именно legacy-модуль (`plugins.lsp`), он раздаёт своим серверам
      # capabilities от cmp. Кеймапы — выше, в `lsp.keymaps`.
      lsp = {
        enable = true;
        servers = {
          nixd.enable = true;      # nix
          lua_ls.enable = true;    # lua
          bashls.enable = true;    # bash
          texlab.enable = true;    # latex — в mymathlib на вход идут .tex с формулами

          # ---- C/C++ ----
          #
          # Пакет сервера — clang-tools, nixvim подставляет его сам по имени.
          # В нём же лежит clang-format, которым форматирует conform выше:
          # это единственный форматтер, которого нет в extraPackages, потому
          # что он приезжает вместе с языковым сервером.
          clangd = {
            enable = true;

            # Пакет уходит в КОНЕЦ PATH обёртки nvim, а не в начало. Смысл тот
            # же, что у dotnet: тулчейн живёт в devShell проекта, и если там
            # есть свой clang-tools — выигрывать должен он, чтобы clangd и
            # clang-format совпадали по версии с компилятором проекта.
            # Нет своего — работает этот.
            packageFallback = true;

            cmd = [
              "clangd"
              "--background-index"        # индексирует проект целиком в фоне
              "--clang-tidy"              # проверки clang-tidy прямо в диагностике
              "--completion-style=detailed"

              # Главный флаг всей этой затеи. По умолчанию clangd НЕ
              # спрашивает у компилятора из compile_commands.json, где лежат
              # его встроенные заголовки, а берёт пути, вшитые в него при
              # сборке. Красного экрана на #include <iostream> из-за этого не
              # будет: nixpkgs собирает clang-tools в паре со своим gcc, и
              # libstdc++ находится. Беда тоньше — находится ЧУЖОЙ, не тот,
              # что стоит в devShell проекта. Проверено на месте: проект,
              # приколоченный к gcc 14, без этого флага разбирается clangd по
              # заголовкам от gcc 15.3 из замыкания clang-tools. Ошибок ноль,
              # а расхождения в свежих <ranges>/<expected> — молча твои.
              # Глоб даёт clangd право спросить у любого драйвера из стора его
              # настоящие пути включения. Одной звёздочки на хеш хватает: `*`
              # здесь, в отличие от шелла, проходит и через слэши.
              "--query-driver=/nix/store/*/bin/*"
            ];
          };
        };
      };

      # ---- C# ----
      #
      # roslyn.nvim — обвязка над настоящим Roslyn LS от Microsoft (тем же,
      # что стоит за C# Dev Kit в VS Code). Пакет roslyn-ls плагин тянет в
      # PATH neovim сам, объявлять его в extraPackages не нужно.
      #
      # ВАЖНО: одновременно с ним нельзя включать `lsp.servers.roslyn_ls` —
      # на буфер сядут два одинаковых клиента, nixvim про это предупредит.
      #
      # ВАЖНО-2: roslyn-ls в nixpkgs собран с useDotnetFromEnv, то есть SDK
      # он берёт ИЗ PATH, а не носит с собой. В mymathlib .NET живёт только в
      # devShell флейка — отсюда плагин direnv ниже, без него сервер
      # поднимется, но solution не загрузит.
      roslyn = {
        enable = true;
        settings = {
          broad_search = true;  # ищет .sln выше каталога открытого файла
          lock_target = true;   # не перепрыгивает между решениями по ходу работы
          silent = true;
        };
      };

      # Обвязки вроде easy-dotnet.nvim здесь сознательно НЕТ. Она выглядит
      # уместной, но каждая её команда ходит по RPC в отдельный сервер
      # dotnet-easydotnet — .NET global tool, которого нет в nixpkgs; плагин
      # доставляет его сам, императивно, в ~/.dotnet/tools. Один бинарь вне
      # /nix/store и вне git ради трёх команд — размен неудачный, тем более
      # что заводскими настройками она поднимает ещё и свой Roslyn поверх
      # roslyn.nvim. Вместо неё — dotnet напрямую, см. extraConfigLua ниже.

      # direnv внутри редактора: nvim, запущенный не из подготовленного
      # шелла, всё равно увидит окружение из .envrc проекта. Ради этого всё
      # и затевалось — см. комментарий к roslyn выше.
      direnv = {
        enable = true;
        settings = {
          auto = 1;
          silent_load = 1;  # иначе каждое переключение буфера пишет в :messages
        };
      };
    };

    # ---- .NET без плагина-обвязки ----
    #
    # dotnet запускается в терминальном сплите, цель ищется вверх по дереву
    # от ОТКРЫТОГО ФАЙЛА, а не от текущего каталога neovim: иначе команды
    # ломаются ровно тогда, когда редактор открыт из корня репозитория, а
    # правится файл где-то в src/.
    extraConfigLua = ''
      local function dotnet_term(cmd)
        vim.cmd("botright 15split")
        vim.cmd("terminal " .. cmd)
        vim.cmd("startinsert")
      end

      local function nearest(pattern)
        local from = vim.fs.dirname(vim.api.nvim_buf_get_name(0))
        if from == nil or from == "" then
          from = vim.fn.getcwd()
        end
        return vim.fs.find(function(name)
          return name:match(pattern) ~= nil
        end, { upward = true, path = from, type = "file" })[1]
      end

      -- Решение целиком, если оно есть: `dotnet build` по .sln собирает и
      -- библиотеку, и тесты разом. Одиночный .csproj — запасной вариант для
      -- проектов без решения.
      local function solution_or_project()
        return nearest("%.sln$") or nearest("%.slnx$") or nearest("%.csproj$")
      end

      _G.nixvim_dotnet = {
        build = function()
          local t = solution_or_project()
          if t then dotnet_term("dotnet build " .. vim.fn.shellescape(t)) end
        end,
        test = function()
          local t = solution_or_project()
          if t then dotnet_term("dotnet test " .. vim.fn.shellescape(t)) end
        end,
        restore = function()
          local t = solution_or_project()
          if t then dotnet_term("dotnet restore " .. vim.fn.shellescape(t)) end
        end,
        -- run умеет только проект: по решению dotnet не знает, что запускать.
        run = function()
          local t = nearest("%.csproj$")
          if t then dotnet_term("dotnet run --project " .. vim.fn.shellescape(t)) end
        end,
      }

      -- ---- C++: .h ↔ .cpp ----
      --
      -- switchSourceHeader — не стандартный метод LSP, а собственное
      -- расширение clangd, поэтому идёт голым запросом к клиенту, а не через
      -- vim.lsp.buf.*. Клиент ищется по имени: в буфере может сидеть не он
      -- один (например, ещё и typos-подобный сервер), а метод понимает
      -- только clangd.
      _G.nixvim_cpp = {
        switch_source_header = function()
          local client = vim.lsp.get_clients({ bufnr = 0, name = "clangd" })[1]
          if not client then
            vim.notify("clangd не подключён к этому буферу", vim.log.levels.WARN)
            return
          end
          client:request(
            "textDocument/switchSourceHeader",
            vim.lsp.util.make_text_document_params(0),
            function(err, result)
              if err or not result then
                vim.notify("Парный файл не найден", vim.log.levels.INFO)
                return
              end
              vim.cmd.edit(vim.uri_to_fname(result))
            end,
            0
          )
        end,
      }

      -- ---- Declutter: спрятать шум, не трогая файл ----
      --
      -- conceal прячет только отрисовку: буфер не меняется, сохранять нечего.
      -- Комментарии и ключевые слова — независимые флаги, чтобы можно было убрать
      -- документацию, оставив сигнатуры, и наоборот.
      local declutter_ns = vim.api.nvim_create_namespace("declutter")

      -- Атрибуты ищутся буквально: `[` и `]` — спецсимволы Lua-паттернов.
      local declutter_attrs = {
        "[[nodiscard]]",
        "[[maybe_unused]]",
        "[[likely]]",
        "[[unlikely]]",
      }

      -- Голые слова — только по границе (%f), иначе `inline` поймается внутри
      -- `newline`, а `constexpr` внутри `is_constexpr`.
      local declutter_words = {
        "constexpr",
        "consteval",
        "constinit",
        "noexcept",
        "inline",
      }

      -- Состояние по буферам: { comments = bool, words = bool }.
      local declutter_state = {}

      -- Разобрать буфер и вернуть парсер. Нужен обеим половинам: комментарии берутся
      -- запросом по дереву, а слова спрашивают у дерева, не внутри ли они строки.
      -- Без явного parse() дерева может не быть вовсе, и get_node вернёт nil.
      local function declutter_parse(buf)
        local ok, parser = pcall(vim.treesitter.get_parser, buf)
        if not ok or not parser then return nil end
        local trees = parser:parse()
        if not trees then return nil end
        return parser, trees
      end

      local function declutter_conceal(buf, row, col, end_col)
        vim.api.nvim_buf_set_extmark(buf, declutter_ns, row, col, {
          end_row = row,
          end_col = end_col,
          conceal = "",
        })
      end

      -- Комментарии берём у treesitter, а не регуляркой: иначе `//` внутри строки
      -- тоже уедет в невидимое, а многострочный /* */ наоборот не поймается.
      local function declutter_comments(buf)
        local parser, trees = declutter_parse(buf)
        if not parser then return end

        local ok_q, query = pcall(vim.treesitter.query.parse, parser:lang(), "(comment) @c")
        if not ok_q then return end

        for _, tree in ipairs(trees) do
          for _, node in query:iter_captures(tree:root(), buf, 0, -1) do
            local srow, scol, erow, ecol = node:range()
            local first = vim.api.nvim_buf_get_lines(buf, srow, srow + 1, false)[1] or ""

            if first:sub(1, scol):match("^%s*$") then
              -- Занимает строки целиком — убираем строки, иначе останутся пустые полосы.
              for row = srow, erow do
                vim.api.nvim_buf_set_extmark(buf, declutter_ns, row, 0, { conceal_lines = "" })
              end
            elseif srow == erow then
              -- Хвостовой после кода: гасим вместе с пробелами перед ним.
              local col = scol
              while col > 0 and first:sub(col, col):match("%s") do
                col = col - 1
              end
              declutter_conceal(buf, srow, col, ecol)
            end
          end
        end
      end

      -- Слово внутри строкового литерала или комментария — не ключевое слово, а
      -- текст. Отличить их регуляркой нельзя, поэтому спрашиваем у treesitter.
      local function declutter_is_text(buf, row, col)
        local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf, pos = { row, col } })
        if not ok or not node then return false end
        local kind = node:type()
        return kind:find("string") ~= nil or kind:find("comment") ~= nil or kind:find("char") ~= nil
      end

      local function declutter_keywords(buf)
        declutter_parse(buf)

        for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
          local hits = {}

          for _, attr in ipairs(declutter_attrs) do
            local init = 1
            while true do
              local s, e = line:find(attr, init, true)
              if not s then break end
              hits[#hits + 1] = { s, e }
              init = e + 1
            end
          end

          for _, word in ipairs(declutter_words) do
            local init = 1
            while true do
              local s, e = line:find("%f[%w_]" .. word .. "%f[^%w_]", init)
              if not s then break end
              hits[#hits + 1] = { s, e }
              init = e + 1
            end
          end

          for _, hit in ipairs(hits) do
            if not declutter_is_text(buf, row - 1, hit[1] - 1) then
              -- Съедаем пробелы справа, чтобы `[[nodiscard]] constexpr bool`
              -- схлопнулось в `bool`, а не в `   bool`.
              local stop = hit[2]
              while stop < #line and line:sub(stop + 1, stop + 1) == " " do
                stop = stop + 1
              end
              declutter_conceal(buf, row - 1, hit[1] - 1, stop)
            end
          end
        end
      end

      local function declutter_apply(buf)
        vim.api.nvim_buf_clear_namespace(buf, declutter_ns, 0, -1)

        local st = declutter_state[buf]
        if not st then return end
        if st.comments then declutter_comments(buf) end
        if st.words then declutter_keywords(buf) end
      end

      _G.nixvim_declutter = {
        toggle = function(what)
          local buf = vim.api.nvim_get_current_buf()
          local st = declutter_state[buf] or { comments = false, words = false }

          if what == "off" then
            st.comments, st.words = false, false
          elseif what == "comments" then
            st.comments = not st.comments
          elseif what == "words" then
            st.words = not st.words
          else
            -- all: включить оба, а если уже оба — выключить.
            local on = not (st.comments and st.words)
            st.comments, st.words = on, on
          end

          local any = st.comments or st.words
          declutter_state[buf] = any and st or nil

          -- 3 — прятать полностью, без замены символом. concealcursor без "n":
          -- под курсором строка видна как есть, иначе её не отредактировать.
          vim.wo.conceallevel = any and 3 or 0
          vim.wo.concealcursor = any and "nc" or ""

          local group = vim.api.nvim_create_augroup("declutter_" .. buf, { clear = true })
          if any then
            vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave" }, {
              group = group,
              buffer = buf,
              callback = function() declutter_apply(buf) end,
            })
            vim.api.nvim_create_autocmd("BufWipeout", {
              group = group,
              buffer = buf,
              callback = function() declutter_state[buf] = nil end,
            })
          end

          declutter_apply(buf)
        end,
      }

      vim.api.nvim_create_user_command("Declutter", function(opts)
        _G.nixvim_declutter.toggle(opts.args ~= "" and opts.args or "all")
      end, {
        nargs = "?",
        complete = function()
          return { "comments", "words", "all", "off" }
        end,
        desc = "Скрыть комментарии / ключевые слова",
      })
    '';

    # Форматтеры для conform выше. Языковые серверы сюда НЕ добавляются:
    # их пакеты nixvim подставляет сам по plugins.lsp.servers.*.
    # По той же причине здесь нет clang-format: он лежит в clang-tools,
    # который уже приехал вместе с сервером clangd (см. plugins.lsp.servers).
    extraPackages = with pkgs; [
      csharpier
      nixfmt
      stylua
      shfmt
    ];

    # горячие клавиши
    keymaps = [
      # ---- Переходы между окнами ----
      #
      # Сокращения к <C-w>h и компании. Нужны не только ради дерева: снизу
      # открывается терминал dotnet, сбоку — список Trouble, и выбираться
      # оттуда штатным аккордом каждый раз утомительно.
      #
      # Раскладка тут ни при чём: Ctrl-сочетания чинит xkb (home/xkb), а не
      # langmap, поэтому Ctrl+р работает так же, как Ctrl+h.
      { key = "<C-h>"; action = "<C-w>h"; options.desc = "Окно слева"; }
      { key = "<C-j>"; action = "<C-w>j"; options.desc = "Окно снизу"; }
      { key = "<C-k>"; action = "<C-w>k"; options.desc = "Окно сверху"; }
      { key = "<C-l>"; action = "<C-w>l"; options.desc = "Окно справа"; }

      # Выход из терминального режима. ИМЕННО двойной Esc, а не одиночный:
      # одиночный сломал бы lazygit, который открывается тем же терминалом и
      # сам использует Esc для возврата на шаг назад. После <Esc><Esc>
      # работают обычные <C-h>/<C-j> выше.
      { mode = "t"; key = "<Esc><Esc>"; action = "<C-\\><C-n>"; options.desc = "Выйти из терминала"; }

      # ---- Дерево файлов ----
      { key = "<leader>e"; action = "<cmd>NvimTreeToggle<cr>";   options.desc = "Дерево файлов"; }
      # Открыть дерево и сразу встать на файл, который правишь. Без этого
      # дерево открывается там, где его закрыли, и текущий файл приходится
      # искать глазами.
      { key = "<leader>o"; action = "<cmd>NvimTreeFindFile<cr>"; options.desc = "Показать файл в дереве"; }

      { key = "<leader>gg"; action = "<cmd>LazyGit<cr>"; options.desc = "LazyGit"; }

      # Diffview — ревью side-by-side. `main...HEAD` (ТРИ точки) — дифф от
      # точки расхождения, а не от текущего main: то же, что показывает
      # pull request, и правки, приехавшие в main после ветвления, в него
      # не попадают.
      { key = "<leader>gd"; action = "<cmd>DiffviewOpen<cr>";             options.desc = "Diffview: рабочее дерево"; }
      { key = "<leader>gm"; action = "<cmd>DiffviewOpen main...HEAD<cr>"; options.desc = "Diffview: ветка против main"; }
      { key = "<leader>gf"; action = "<cmd>DiffviewFileHistory %<cr>";    options.desc = "История текущего файла"; }
      { key = "<leader>gq"; action = "<cmd>DiffviewClose<cr>";            options.desc = "Закрыть Diffview"; }

      # Буферы
      { key = "<S-h>"; action = "<cmd>BufferLineCyclePrev<cr>"; options.desc = "Предыдущий буфер"; }
      { key = "<S-l>"; action = "<cmd>BufferLineCycleNext<cr>"; options.desc = "Следующий буфер"; }

      # Закрыть вкладку из строки буферов сверху. Именно :Bdelete, а не
      # :bdelete — почему, расписано у bufdelete.enable выше.
      #
      # Заглавная D — с восклицательным знаком: закрывает, ВЫБРОСИВ
      # несохранённые правки. Без него :Bdelete на грязном буфере просто
      # ругается «No write since last change», и это правильно: терять
      # написанное по опечатке в хоткее не должно быть легко.
      { key = "<leader>bd"; action = "<cmd>Bdelete<cr>";  options.desc = "Закрыть буфер"; }
      { key = "<leader>bD"; action = "<cmd>Bdelete!<cr>"; options.desc = "Закрыть буфер, отбросив правки"; }
      # Разгрести строку буферов, когда их набралось два десятка.
      { key = "<leader>bo"; action = "<cmd>BufferLineCloseOthers<cr>"; options.desc = "Закрыть все, кроме текущего"; }

      # Диагностика списком
      { key = "<leader>xx"; action = "<cmd>Trouble diagnostics toggle<cr>"; options.desc = "Диагностики"; }
      { key = "<leader>xq"; action = "<cmd>Trouble qflist toggle<cr>";      options.desc = "Quickfix"; }

      # .NET — обёртки из extraConfigLua выше
      { key = "<leader>db"; action.__raw = "function() _G.nixvim_dotnet.build() end";   options.desc = "Собрать решение"; }
      { key = "<leader>dt"; action.__raw = "function() _G.nixvim_dotnet.test() end";    options.desc = "Прогнать тесты"; }
      { key = "<leader>dr"; action.__raw = "function() _G.nixvim_dotnet.run() end";     options.desc = "Запустить проект"; }
      { key = "<leader>dR"; action.__raw = "function() _G.nixvim_dotnet.restore() end"; options.desc = "Restore"; }

      # C++ — обёртка из extraConfigLua выше. Группа <leader>c («Код») в
      # which-key уже объявлена, новую заводить не нужно.
      { key = "<leader>ch"; action.__raw = "function() _G.nixvim_cpp.switch_source_header() end"; options.desc = "Заголовок ↔ реализация"; }

      # Declutter — обёртка из extraConfigLua выше. Флаги независимые: можно
      # убрать документацию, оставив сигнатуры, и наоборот.
      { key = "<leader>cc"; action.__raw = "function() _G.nixvim_declutter.toggle('comments') end"; options.desc = "Скрыть комментарии"; }
      { key = "<leader>ck"; action.__raw = "function() _G.nixvim_declutter.toggle('words') end";    options.desc = "Скрыть ключевые слова"; }
      { key = "<leader>cd"; action.__raw = "function() _G.nixvim_declutter.toggle('all') end";      options.desc = "Скрыть и то, и другое"; }

      # Git-ханки (gitsigns)
      { key = "]c"; action = "<cmd>Gitsigns next_hunk<cr>"; options.desc = "Следующий ханк"; }
      { key = "[c"; action = "<cmd>Gitsigns prev_hunk<cr>"; options.desc = "Предыдущий ханк"; }
      { key = "<leader>hp"; action = "<cmd>Gitsigns preview_hunk<cr>"; options.desc = "Показать ханк"; }
      { key = "<leader>hs"; action = "<cmd>Gitsigns stage_hunk<cr>";   options.desc = "Застейджить ханк"; }
      { key = "<leader>hr"; action = "<cmd>Gitsigns reset_hunk<cr>";   options.desc = "Откатить ханк"; }

      # Старый код на месте, а не плавающим окном поверх кода, как <leader>hp
      # выше. hi — один ханк под курсором (gitsigns), ho — весь файл разом
      # (mini.diff, переключатель).
      { key = "<leader>hi"; action = "<cmd>Gitsigns preview_hunk_inline<cr>"; options.desc = "Старый код ханка на месте"; }
      { key = "<leader>hw"; action = "<cmd>Gitsigns toggle_word_diff<cr>";    options.desc = "Различия по словам"; }
      {
        key = "<leader>ho";
        action.__raw = "function() require('mini.diff').toggle_overlay() end";
        options.desc = "Оверлей diff по всему файлу";
      }
    ];
  };
}
