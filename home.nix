{ inputs, pkgs, ... }:
{
  imports = [
    inputs.noctalia.homeModules.default
    inputs.nixvim.homeModules.nixvim
  ];

  home.stateVersion = "26.05";

  programs.noctalia = {
    enable = true;
    systemd.enable = true;   # автозапуск как user-сервис
    settings = {
      theme = { mode = "dark"; source = "builtin"; builtin = "Catppuccin"; };
      # приложения из шелла — как systemd-юниты, иначе умирают при рестарте сервиса
      launch_apps_as_systemd_services = true;
    };
  };

  # =============================================================
  # Batch 2 — пользовательские CLI-инструменты (декларативно)
  # Всё через programs.* модули: пакет + конфиг + интеграция с fish
  # разом, в git, а не голые бинарники. См. [[05 - Лог установки NixOS]].
  # =============================================================

  # --- fish: логин-шелл (системная сторона — в configuration.nix) ---
  programs.fish = {
    enable = true;
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

  # --- ls -> lsd, с иконками; алиасы в fish ---
  programs.lsd = {
    enable = true;
    enableFishIntegration = true;
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
