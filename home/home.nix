{ inputs, lib, pkgs, osConfig, ... }:
# osConfig — конфиг СИСТЕМЫ. Доступен потому, что home-manager подключён
# модулем NixOS; через него читаются опции local.* (см. modules/options.nix),
# то есть всё, чем ноут отличается от десктопа.
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
  home.file = lib.mkIf (osConfig.local.zenProfileDir != null) {
    ".config/zen/${osConfig.local.zenProfileDir}/user.js".text = ''
    user_pref("devtools.chrome.enabled", true);
    user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

    // Моноширинный на страницах: <pre>, <code>, любой листинг.
    // Раздельно для латиницы и кириллицы — Firefox держит настройку
    // шрифта на каждую систему письма, и одной x-western мало:
    // на русских страницах язык определяется как x-cyrillic.
    user_pref("font.name.monospace.x-western", "LythMonoTerm Nerd Font");
    user_pref("font.name.monospace.x-cyrillic", "LythMonoTerm Nerd Font");

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
  };

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
    # мелкие удобные абревиатуры; расширю позже
    shellAbbrs = {
      gs = "git status";
      gc = "git commit";
      lg = "lazygit";
    };
  };

  # --- умный cd: хук `z` вписывается в fish автоматически ---
  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
  };

  # --- файловый менеджер: хук `y` (сменить каталог при выходе) ---
  programs.yazi = {
    enable = true;
    enableFishIntegration = true;

    # mount.yazi — список дисков прямо в yazi: клавиша M открывает панель,
    # там смонтировать/отмонтировать флешку. Ходит через udisksctl, поэтому
    # sudo не спрашивает (нужен services.udisks2 — включён в configuration.nix).
    # Точка монтирования получается вида /run/media/artur/<метка тома>.
    plugins.mount = "${inputs.yazi-plugins}/mount.yazi";

    keymap.mgr.prepend_keymap = [
      {
        on = "M";
        run = "plugin mount";
        desc = "Диски: смонтировать / отмонтировать";
      }
    ];
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
  # Имя и почту НЕ задаю: глобального ~/.gitconfig у меня нет, личность
  # прописана по репозиториям, и так и остаётся.
  programs.git.enable = true;
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

    # Lyth Mono — обводочный, кегль снова можно дробить. Вариант Term:
    # у него сужены стрелки и геометрические символы, чтобы не ломать
    # сетку в TUI. Nerd-глифы вшиты, fallback ни за чем не нужен.
    font = {
      name = "LythMonoTerm Nerd Font";
      size = 11.5;
    };

    settings = {
      # Рамку и тень рисует niri, свои декорации не нужны.
      hide_window_decorations = "yes";
      window_padding_width = 14;
      confirm_os_window_close = 0;

      # Прозрачность. background_blur здесь бесполезен: он требует
      # протокола блюра от композитора, а у niri его нет.
      # 1.0 — прозрачность целиком отдана niri (window-rule по app-id
      # kitty), иначе два коэффициента перемножаются. Так фон гаснет
      # одинаково и под промптом, и под TUI, который красит его сам.
      background_opacity = "1.0";
      dynamic_background_opacity = "yes";

      # Табы: скошенный powerline вместо заводских прямоугольников.
      # Панель появляется от двух табов (tab_bar_min_tabs по умолчанию 2).
      tab_bar_edge = "top";
      tab_bar_style = "powerline";
      tab_powerline_style = "slanted";
      active_tab_font_style = "bold";

      # Шлейф за курсором (kitty 0.47). Значение — порог в МИЛЛИСЕКУНДАХ:
      # шлейф рисуется только за курсором, простоявшим дольше порога,
      # иначе он тянулся бы за каждой перерисовкой TUI.
      cursor_trail = 3;
      cursor_trail_start_threshold = 2;
      cursor_shape = "beam";

      # Лигатуры нужны, но под курсором разъезжаются — там показываем раздельно.
      disable_ligatures = "cursor";

      scrollback_lines = 20000;
      enable_audio_bell = "no";
    };

    # Палитра от noctalia. Путь ОБЯЗАН быть абсолютным.
    # Относительный include kitty резолвит относительно каталога САМОГО
    # конфига (lib/kitty/kitty/conf/utils.py:372), а конфиг теперь лежит
    # в /nix/store — тема бы не нашлась, и цвета молча съехали бы на
    # дефолтные. expanduser в путях include поддерживается (там же, 295),
    # поэтому "~" работает.
    extraConfig = ''
      include ~/.config/kitty/themes/noctalia.conf
    '';
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

    # тема в тон noctalia (Catppuccin)
    colorschemes.catppuccin = {
      enable = true;
      settings.flavour = "mocha";
    };

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
    };

    globals.mapleader = " ";   # leader = пробел

    plugins = {
      web-devicons.enable = true;   # иконки для дерева/telescope
      telescope.enable = true;      # быстрый поиск файлов/по содержимому
      treesitter.enable = true;     # умная подсветка
      nvim-tree.enable = true;      # дерево файлов слева
      lualine.enable = true;        # статусная строка
      gitsigns.enable = true;       # git-пометки в gutter
      comment.enable = true;        # gcc — закомментить строку
      nvim-autopairs.enable = true; # авто-закрытие скобок
      which-key.enable = true;      # подсказки по хоткеям

      # автодополнение
      cmp = {
        enable = true;
        autoEnableSources = true;
        settings.sources = [
          { name = "nvim_lsp"; }
          { name = "path"; }
          { name = "buffer"; }
        ];
      };

      # LSP: подсветка ошибок + автодополнение по языкам
      lsp = {
        enable = true;
        servers = {
          nixd.enable = true;      # nix
          lua_ls.enable = true;    # lua
          bashls.enable = true;    # bash
        };
      };
    };

    # горячие клавиши
    keymaps = [
      { key = "<leader>ff"; action = "<cmd>Telescope find_files<cr>"; options.desc = "Найти файл"; }
      { key = "<leader>fg"; action = "<cmd>Telescope live_grep<cr>"; options.desc = "Поиск по содержимому"; }
      { key = "<leader>e";  action = "<cmd>NvimTreeToggle<cr>";      options.desc = "Дерево файлов"; }
    ];
  };
}
