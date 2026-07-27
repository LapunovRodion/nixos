{ inputs, pkgs, ... }:
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

  # Тема курсоров. До этого в системе не было НИ ОДНОЙ — niri ругался
  # "error loading xcursor crosshair: no default icon", из-за чего slurp
  # (выделение области под скриншот) выглядел так, будто ничего не запустилось.
  # pointerCursor сам ставит пакет, XCURSOR_THEME/SIZE и настройки GTK.
  home.pointerCursor = {
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Classic";
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
  # Все цвета заданы ИМЕНАМИ ANSI (green, blue, magenta…), ни одного hex.
  # Поэтому промпт едет за палитрой обоев через терминал.
  #
  # Встроенный шаблон starship у noctalia сознательно НЕ включён: он не
  # пишет свой файл, а вклинивается в ~/.config/starship.toml между
  # маркерами "# >>> NOCTALIA STARSHIP PALETTE >>>" (assets/templates/
  # starship/apply.sh). С HM это несовместимо — файл read-only симлинк.
  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    settings = {
      add_newline = true;

      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
        vimcmd_symbol = "[❮](bold yellow)";
      };

      directory = {
        style = "bold blue";
        truncation_length = 3;
        truncate_to_repo = false;
        read_only = " 󰌾";
      };

      git_branch.style = "bold magenta";
      git_state.style = "bold red";
      git_status = {
        style = "bold yellow";
        ahead = "⇡$count";
        behind = "⇣$count";
        diverged = "⇕⇡$ahead_count⇣$behind_count";
      };

      # Показывать длительность только у команд дольше 2 секунд.
      cmd_duration = {
        min_time = 2000;
        style = "yellow";
        format = "took [$duration]($style) ";
      };

      # Видеть, что сижу в nix shell / nix develop.
      nix_shell = {
        symbol = " ";
        style = "bold cyan";
        format = "via [$symbol$state]($style) ";
      };
    };
  };

  # --- kitty ---
  programs.kitty = {
    enable = true;

    font = {
      name = "JetBrainsMono Nerd Font";
      size = 11.5;
    };

    settings = {
      # Рамку и тень рисует niri, свои декорации не нужны.
      hide_window_decorations = "yes";
      window_padding_width = 14;
      confirm_os_window_close = 0;

      # Прозрачность. background_blur здесь бесполезен: он требует
      # протокола блюра от композитора, а у niri его нет.
      background_opacity = "0.88";
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
