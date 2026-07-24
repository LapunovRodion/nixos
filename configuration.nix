{ config, pkgs, lib, inputs, ... }:

let
  # claude-code, всегда ходящий через hysteria (http-прокси на 3128).
  # Обёртка, а не глобальные HTTPS_PROXY — через VPN идёт только claude,
  # остальная система работает напрямую.
  # Именно http-прокси, а не socks5: он резолвит имена на стороне сервера,
  # поэтому не упирается в отсутствие IPv6 у VPN-сервера.
  claude-code-vpn = pkgs.symlinkJoin {
    name = "claude-code-vpn";
    paths = [ pkgs.claude-code ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/claude \
        --set HTTPS_PROXY "http://127.0.0.1:3128" \
        --set HTTP_PROXY  "http://127.0.0.1:3128" \
        --set NO_PROXY    "localhost,127.0.0.1,::1"
    '';
  };
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "nixos"; # Define your hostname.

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/Minsk";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users."artur" = {
    isNormalUser = true;
    description = "artur";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [];
    shell = pkgs.fish;   # логин-шелл fish (Batch 2)
  };

  # fish на системном уровне: регистрирует /etc/shells + vendor-completions.
  # Пользовательский конфиг fish — в home.nix (programs.fish).
  programs.fish.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # ---------------------------------------------------------------
  # NVIDIA (RTX 4050, dGPU) — драйвер + CUDA для локальных LLM.
  # Ноут ROG Zephyrus G14 GA403UU: гибрид AMD iGPU (дисплей) + NVIDIA (по запросу).
  # PRIME offload: дисплей на amdgpu, NVIDIA просыпается под нагрузку/`nvidia-offload`.
  # ---------------------------------------------------------------
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    open = true;                        # открытый модуль ядра — ок для RTX 40xx (Ada)
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    powerManagement.enable = true;      # корректные suspend/resume + runtime-PM dGPU
    prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true;  # обёртка `nvidia-offload <app>`
      amdgpuBusId = "PCI:101:0:0";      # AMD iGPU  (0000:65:00.0)
      nvidiaBusId = "PCI:1:0:0";        # NVIDIA    (0000:01:00.0)
    };
  };

  # ---------------------------------------------------------------
  # Ollama — раннер локальных LLM (движок llama.cpp), OpenAI-API на :11434.
  # Основной под Hermes 3 8B; 14B через авто-оффлоад. llama.cpp — позже точечно.
  # ---------------------------------------------------------------
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;         # CUDA-сборка → использует RTX 4050
    environmentVariables = {
      OLLAMA_FLASH_ATTENTION = "1";     # нужно для квантованного KV-кэша
      OLLAMA_KV_CACHE_TYPE = "q4_0";    # 4-бит KV → влезает 64K контекста в 6 ГБ (путь 1)
      OLLAMA_CONTEXT_LENGTH = "65536";  # Hermes Agent требует минимум 64K контекста
    };
  };

  # ---------------------------------------------------------------
  # Nix: flakes + бинарный кэш noctalia
  # ---------------------------------------------------------------
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    extra-substituters = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    ];
  };

  # ---------------------------------------------------------------
  # 1. niri (compositor)
  # ---------------------------------------------------------------
  programs.niri.enable = true;

  # Логин-менеджер: greetd + tuigreet, сразу в niri-сессию
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd niri-session";
      user = "greeter";
    };
  };

  # Портал для скриншотов/скриншеринга
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # ---------------------------------------------------------------
  # 2. noctalia v5 (шелл)
  # ---------------------------------------------------------------
  programs.noctalia = {
    enable = true;
    recommendedServices.enable = true;  # NetworkManager, Bluetooth, UPower, power-profiles-daemon
  };

  # ---------------------------------------------------------------
  # 3. Hysteria (VPN-клиент)
  # ---------------------------------------------------------------
  systemd.services.hysteria-client = {
    description = "Hysteria 2 client";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.hysteria}/bin/hysteria client -c /etc/hysteria/client.yaml";
      Restart = "on-failure";
      RestartSec = 5;
      CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_BIND_SERVICE" ];
      AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_BIND_SERVICE" ];
    };
  };

  # ---------------------------------------------------------------
  # Пакеты
  # ---------------------------------------------------------------
  environment.systemPackages = with pkgs; [
    # базовое
    git
    vim
    wget
    # niri окружение
    fuzzel               # лаунчер
    kitty                # терминал (единственный; вместо alacritty/rio)
    xwayland-satellite   # X11-приложения
    # сеть
    hysteria
    # 4. Claude Code (CLI, unfree) — обёрнутый на VPN, см. let выше
    claude-code-vpn
    # 5. Obsidian (unfree) — само хранилище синхронизируется через syncthing ниже
    obsidian
    # 6. Hermes Agent (харнесс, управление системой) — бинарь `hermes` (с TUI).
    #    Пакет `minimal`: bin/hermes уже включает TUI (symlink ui-tui + HERMES_TUI_DIR),
    #    но БЕЗ облачных SDK из `full` (anthropic/bedrock/voice/matrix) — не нужны под
    #    локальный Ollama. Модуль во flake.nix импортирован, но НЕ enable (его enable =
    #    always-on gateway, крашится без провайдера). Провайдер укажу интерактивно:
    #    `hermes model` → Custom endpoint → Ollama.
    inputs.hermes-agent.packages.${pkgs.system}.minimal

    # ---- Перенос по чеклисту [[04 - План переноса на NixOS]] ----
    # Терминал: kitty — объявлен выше в блоке «niri окружение» как единственный.
    # niri: история буфера обмена + сохранение содержимого после закрытия окна
    cliphist
    wl-clip-persist
    # CLI-утилиты
    gh          # github-cli
    lazygit
    ripgrep     # уже подтягивался как зависимость — теперь объявлен явно

    # ---- Batch 3a: мессенджеры, торрент (из nixpkgs) ----
    vesktop           # Discord-клиент (вместо discord)
    ayugram-desktop   # форк Telegram (бинарник называется AyuGram)
    qbittorrent       # торренты

    # ---- Batch 3b: браузер + claude-desktop (из сторонних flake) ----
    inputs.zen-browser.packages.${pkgs.system}.default
    inputs.claude-desktop.packages.${pkgs.system}.claude-desktop-with-fhs
  ];

  # plocate — быстрый поиск по имени файла (updatedb по таймеру).
  # Правильный способ в NixOS — модуль, а не просто пакет.
  services.locate = {
    enable = true;
    package = pkgs.plocate;
  };

  # ---------------------------------------------------------------
  # 5. Syncthing — синхронизация хранилища Obsidian
  # ---------------------------------------------------------------
  # Работает от пользователя artur, иначе права на ~/Obsidian будут root'овые.
  # Web-UI: http://127.0.0.1:8384 — наружу не открыт намеренно,
  # с другой машины удобнее пробросить: ssh -L 8384:127.0.0.1:8384 artur@<host>
  services.syncthing = {
    enable = true;
    user = "artur";
    group = "users";
    dataDir = "/home/artur";
    configDir = "/home/artur/.config/syncthing";
    openDefaultPorts = true;   # 22000/tcp+udp (обмен), 21027/udp (обнаружение)
  };

  # ---------------------------------------------------------------
  # 6. Tailscale — mesh-VPN до остальных машин
  # ---------------------------------------------------------------
  # Модуль сам ставит firewall.checkReversePath = "loose" — без этого
  # ломается маршрутизация через tailscale0.
  # После ребилда авторизация делается один раз вручную: sudo tailscale up
  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # ---------------------------------------------------------------
  # Шрифты (Batch 4)
  # Арчевые имена из плана → атрибуты nixpkgs; nerd-fonts переехали
  # в неймспейс nerd-fonts.*, noto-emoji → noto-fonts-color-emoji.
  # ---------------------------------------------------------------
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      nerd-fonts.jetbrains-mono   # ttf-jetbrains-mono-nerd
      nerd-fonts.meslo-lg         # ttf-meslo-nerd
      noto-fonts                  # noto-fonts
      noto-fonts-cjk-sans         # noto-fonts-cjk
      noto-fonts-color-emoji      # noto-fonts-emoji
      dejavu_fonts                # ttf-dejavu
      liberation_ttf              # ttf-liberation
      open-sans                   # ttf-opensans
      cantarell-fonts             # cantarell-fonts
    ];
    fontconfig.defaultFonts = {
      monospace = [ "JetBrainsMono Nerd Font" "MesloLGS Nerd Font" ];
      sansSerif = [ "Noto Sans" "Open Sans" "Cantarell" ];
      serif     = [ "Noto Serif" ];
      emoji     = [ "Noto Color Emoji" ];
    };
  };

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = true;

  system.stateVersion = "26.05"; # Did you read the comment?
}
