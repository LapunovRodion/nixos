{ config, pkgs, lib, inputs, ... }:

let
  # tuistore + его зависимость ricekit — обоих нет в nixpkgs, пакуем сами.
  # Разбор и оговорка про императивный one-key-install — в pkgs/tuistore.nix.
  ricekit = pkgs.python3Packages.callPackage ./pkgs/ricekit.nix { };
  tuistore = pkgs.python3Packages.callPackage ./pkgs/tuistore.nix { inherit ricekit; };

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

  # Запись экрана одной кнопкой: первый вызов — старт, повторный — стоп.
  # Пока идёт запись, висит уведомление с таймером (обновляется каждые 5 с),
  # чтобы не гадать, пишется сейчас или нет. Демон уведомлений — noctalia.
  screenrec = pkgs.writeShellApplication {
    name = "screenrec";
    runtimeInputs = with pkgs; [ wf-recorder libnotify procps coreutils ];
    text = ''
      dir="$HOME/Videos"
      run="''${XDG_RUNTIME_DIR:-/tmp}"
      idfile="$run/screenrec.notify-id"     # id уведомления, чтобы обновлять его же
      tickfile="$run/screenrec.ticker-pid"  # фоновый цикл-таймер
      namefile="$run/screenrec.filename"

      if pgrep -x wf-recorder >/dev/null 2>&1; then
        # --- СТОП ---
        if [ -f "$tickfile" ]; then kill "$(cat "$tickfile")" 2>/dev/null || true; fi
        # SIGINT, а не SIGKILL: wf-recorder должен корректно дописать контейнер
        pkill -INT -x wf-recorder || true
        for _ in $(seq 1 60); do
          pgrep -x wf-recorder >/dev/null 2>&1 || break
          sleep 0.1
        done
        file="$(cat "$namefile" 2>/dev/null || echo "")"
        id="$(cat "$idfile" 2>/dev/null || echo "")"
        if [ -n "$id" ]; then
          notify-send -a screenrec -r "$id" -t 6000 "Запись остановлена" "$file"
        else
          notify-send -a screenrec -t 6000 "Запись остановлена" "$file"
        fi
        rm -f "$idfile" "$tickfile" "$namefile"
      else
        # --- СТАРТ ---
        mkdir -p "$dir"
        file="$dir/rec-$(date +%Y-%m-%d_%H-%M-%S).mp4"
        echo "$file" > "$namefile"
        wf-recorder -f "$file" >/dev/null 2>&1 &
        sleep 1
        if ! pgrep -x wf-recorder >/dev/null 2>&1; then
          notify-send -a screenrec -u critical "Запись не запустилась" "wf-recorder завершился сразу"
          rm -f "$namefile"
          exit 1
        fi
        # -p печатает id уведомления → потом обновляем его же, а не плодим новые
        id="$(notify-send -a screenrec -p -t 0 "Идёт запись экрана" "00:00" 2>/dev/null || echo "")"
        echo "$id" > "$idfile"
        (
          start="$(date +%s)"
          while pgrep -x wf-recorder >/dev/null 2>&1; do
            sleep 5
            el=$(( $(date +%s) - start ))
            ts="$(printf '%02d:%02d' $(( el / 60 )) $(( el % 60 )))"
            if [ -n "$id" ]; then
              notify-send -a screenrec -r "$id" -t 0 "Идёт запись экрана" "$ts" || true
            fi
          done
        ) &
        echo $! > "$tickfile"
      fi
    '';
  };

  # Claude Desktop, целиком ходящий через hysteria (http-прокси на 3128).
  # Это Electron: сам бинарь запускается лаунчером по .desktop (Exec=claude-desktop,
  # резолвится через PATH), поэтому заворачиваем бинарь — обёртка подхватится сама.
  # Chromium под niri (нет GNOME/KDE) берёт прокси из СТРОЧНЫХ http_proxy/https_proxy;
  # дочерние node/MCP-процессы («ноды») — из привычных HTTP_PROXY/HTTPS_PROXY.
  # Задаём оба регистра → через VPN идёт и приложение, и его ноды («полностью»).
  claude-desktop-base = inputs.claude-desktop.packages.${pkgs.system}.claude-desktop-with-fhs;
  claude-desktop-vpn = pkgs.symlinkJoin {
    name = "claude-desktop-vpn";
    paths = [ claude-desktop-base ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/claude-desktop \
        --set https_proxy "http://127.0.0.1:3128" \
        --set http_proxy  "http://127.0.0.1:3128" \
        --set all_proxy   "http://127.0.0.1:3128" \
        --set no_proxy    "localhost,127.0.0.1,::1" \
        --set HTTPS_PROXY "http://127.0.0.1:3128" \
        --set HTTP_PROXY  "http://127.0.0.1:3128" \
        --set ALL_PROXY   "http://127.0.0.1:3128" \
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

  # amdgpu грузится из initrd — ДО nvidia. Иначе два DRM-устройства гибрида
  # (amdgpu + nvidia) регистрируются в гонке, и minor'ы меняются местами от
  # загруза к загрузу: встроенная матрица зовётся то eDP-1, то eDP-2
  # (а подсветка — то amdgpu_bl1, то amdgpu_bl2). Всё, что привязано к имени
  # выхода, при этом отваливается — так пропали виджеты рабочего стола
  # noctalia, прибитые к eDP-2. Матрица физически на amdgpu (0000:65:00.0),
  # поэтому фиксируем его первым: панель всегда eDP-1.
  # Список сливается с пустым boot.initrd.kernelModules из hardware-configuration.nix.
  boot.initrd.kernelModules = [ "amdgpu" ];

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
    # input — чтение /dev/input/event*: нужно плагину noctalia bongocat,
    # он смотрит нажатия клавиш через evtest. Применяется после релогина.
    extraGroups = [ "networkmanager" "wheel" "input" ];
    packages = with pkgs; [];
    shell = pkgs.fish;   # логин-шелл fish (Batch 2)
  };

  # fish на системном уровне: регистрирует /etc/shells + vendor-completions.
  # Пользовательский конфиг fish — в home.nix (programs.fish).
  programs.fish.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Оверлей: claude-code берём из отдельного свежего входа nixpkgs-cc,
  # а не из основного nixpkgs. Так CLI обновляется независимо (nix flake
  # update nixpkgs-cc), не таща за собой весь unstable. claude-code-vpn
  # в let-блоке оборачивает уже этот, свежий, pkgs.claude-code.
  nixpkgs.overlays = [
    (final: prev:
      let
        # Импортируем nixpkgs-cc со своим config (не legacyPackages — там дефолтный
        # config без allowUnfree, а claude-code unfree).
        ccPkgs = import inputs.nixpkgs-cc {
          system = prev.stdenv.hostPlatform.system;
          config.allowUnfree = true;
        };
      in {
        # >>> ВРЕМЕННОЕ ПЕРЕОПРЕДЕЛЕНИЕ (откатить, когда nixpkgs догонит) <<<
        # nixpkgs-cc сейчас даёт 2.1.217 (срез до релиза Opus 5, 2026-07-24) — этот
        # CLI ещё не знает про Opus 5. Тянем свежий прибилд 2.1.220 напрямую с
        # downloads.claude.ai (тот же источник, что и сам пакет).
        # ОТКАТ: убрать .overrideAttrs, оставить голый `ccPkgs.claude-code`, затем
        # `nix flake update nixpkgs-cc` — вернёмся к версии из nixpkgs.
        claude-code = ccPkgs.claude-code.overrideAttrs (old: {
          version = "2.1.220";
          src = prev.fetchurl {
            url = "https://downloads.claude.ai/claude-code-releases/2.1.220/linux-x64/claude";
            hash = "sha256-Z09h8g/zBvMQDPkgDkw2xLcCeLW+8ohFSYGblCqJyGM=";
          };
        });
      })
  ];

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
  # Ollama НЕ стартует при загрузке — поднимаю вручную `systemctl start ollama`,
  # когда нужен ИИ (иначе демон висит ~375 МБ вхолостую). Сервис остаётся определён,
  # модель как обычно грузится по запросу и выгружается через keep-alive.
  systemd.services.ollama.wantedBy = lib.mkForce [ ];

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
    # Буфер обмена: история — ВСТРОЕННАЯ в noctalia (`panel-toggle clipboard`),
    # поэтому cliphist/wl-clip-persist не нужны. wl-clipboard оставлен ради
    # wl-copy/wl-paste в CLI и пайплайнах.
    wl-clipboard
    # Скриншоты снимает noctalia (`screenshot-region` / `screenshot-fullscreen`).
    # Эти пакеты закрывают то, чего нет ни у неё, ни у niri: аннотации и видео.
    grim                 # захват в файл из CLI (для скриптов/пайплайнов)
    slurp                # выбор области мышью → координаты, в связке с grim
    satty                # редактор снимка: стрелки, текст, размытие
    wf-recorder          # запись видео экрана
    libnotify            # notify-send — индикация записи (демон уведомлений = noctalia)
    screenrec            # обёртка старт/стоп записи с таймером, см. let выше
    # CLI-утилиты
    gh          # github-cli
    lazygit
    ripgrep     # уже подтягивался как зависимость — теперь объявлен явно

    # ---- Зависимости плагинов noctalia (см. [[08 - Кастомизация (rice)]]) ----
    # Плагины ставятся из витрины noctalia (состояние — в ~/.local/state/noctalia),
    # но их внешние зависимости обязаны быть в системе, иначе плагин молча мёртв.
    bitwarden-cli   # `bw` — плагин noctalia/bitwarden ходит в локальный `bw serve`,
                    # а не в облако. Под свой Vaultwarden: `bw config server <url>`
                    # ОДИН РАЗ до логина (или Server URL в настройках плагина).
    python3         # хуки и MCP-шим плагина lowcache/claude-companion (stdlib, без pip)
    playerctl       # «что играет»: шим claude-companion + медиа-бинды niri
    evtest          # bongocat читает им нажатия клавиш; плюс группа `input` выше

    # ---- Видимость пакетов (чеклист [[04]], «Просмотр установленного») ----
    # В NixOS источник правды — сам конфиг, «пакетный менеджер как в Arch» не нужен.
    # Эти двое отвечают на вопросы, которых конфиг не покрывает.
    # (третий, nix-index, подключён модулем ниже — ему нужна не только программа)
    nvd         # читаемый diff поколений: что реально изменилось после rebuild
    nix-tree    # TUI по замыканию: кто кого тянет и сколько весит

    # ---- Batch 3a: мессенджеры, торрент (из nixpkgs) ----
    vesktop           # Discord-клиент (вместо discord)
    ayugram-desktop   # форк Telegram (бинарник называется AyuGram)
    qbittorrent       # торренты

    # torlink — TUI-искалка торрентов, дополняет qbittorrent (тот качает и сидит).
    # Из flake апстрима, см. flake.nix. ВНИМАНИЕ: бинарь называется `torlnk`,
    # без второй "i" — так он опубликован в npm, так же зовётся и в пакете.
    inputs.torlink.packages.${pkgs.system}.default

    # tuistore — витрина TUI-приложений (не установщик, см. pkgs/tuistore.nix)
    tuistore

    # ---- Книги ----
    # Читалка. Библиотека живёт на сервере (Grimmory, http://server:6060),
    # книги берутся по OPDS, место чтения синхронизируется через
    # Custom Sync Server (kosync-протокол) на тот же адрес. Syncthing не участвует.
    # Тот же Readest ставится на телефон — интерфейс и настройки одинаковые.
    readest

    # ---- Связь с телефоном ----
    # Из тройки KDE Connect / scrcpy / LocalSend взят только LocalSend (ревизия
    # 2026-07-27): нужна была разовая передача файлов, а не уведомления и экран.
    # Фоновая синхронизация папок и так на syncthing (см. ниже).
    localsend

    # ---- Batch 3b: браузер + claude-desktop (из сторонних flake) ----
    inputs.zen-browser.packages.${pkgs.system}.default
    # claude-desktop — обёрнут на VPN (claude-desktop-vpn в let выше), а не голый пакет
    claude-desktop-vpn
  ];

  # plocate — быстрый поиск по имени файла (updatedb по таймеру).
  # Правильный способ в NixOS — модуль, а не просто пакет.
  services.locate = {
    enable = true;
    package = pkgs.plocate;
  };

  # nix-index — «какой пакет даёт этот бинарь». Модулем, а не пакетом: он ещё
  # вешает обработчик command-not-found на fish (набрал неизвестную команду —
  # подсказал, в каком пакете она лежит).
  # ВАЖНО: базу надо построить один раз руками — `nix-index` (несколько минут,
  # качает file-listings). Без неё nix-locate будет ругаться на отсутствие индекса.
  programs.nix-index.enable = true;
  # Штатный command-not-found ходит в базу channels, которых при flake-подходе
  # нет, — он тут нерабочий. Плюс модуль nix-index на него ругается assert'ом.
  programs.command-not-found.enable = false;

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
  # Steam — модулем, а не пакетом
  # ---------------------------------------------------------------
  # `pkgs.steam` в systemPackages не хватает: модуль ещё включает 32-битную
  # графику (hardware.graphics.enable32Bit — без неё не запустится ничего
  # 32-битного, а это половина библиотеки) и ставит steam-run.
  # На гибридном ноуте (дисплей на AMD, NVIDIA по PRIME offload) игры по
  # умолчанию пойдут на iGPU. Чтобы игра шла на RTX 4050, в её свойствах в
  # Steam → Launch Options прописать:  nvidia-offload %command%
  programs.steam.enable = true;

  # ---------------------------------------------------------------
  # LocalSend — порт для обнаружения и приёма файлов
  # ---------------------------------------------------------------
  # Протокол один и тот же на обоих: UDP — multicast-обнаружение устройств,
  # TCP — сама передача. Без этой дырки телефон ноут просто не увидит
  # (отправлять с ноута можно было бы, принимать — нет).
  networking.firewall.allowedTCPPorts = [ 53317 ];
  networking.firewall.allowedUDPPorts = [ 53317 ];

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
