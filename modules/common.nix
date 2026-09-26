{ config, pkgs, lib, inputs, ... }:

let
  # specify-cli (GitHub Spec Kit) — нет в nixpkgs, пакуем из PyPI сами.
  # См. pkgs/specify-cli.nix. Заменяет прежний `uv tool install`.
  specify-cli = pkgs.python3Packages.callPackage ../pkgs/specify-cli.nix { };

  # Iosevka-сборка мимо nixpkgs — см. pkgs/lyth-mono.nix. Был основным
  # моноширинным, теперь запасной: терминал и вся моноширина уехали на
  # JetBrains Mono.
  lyth-mono = pkgs.callPackage ../pkgs/lyth-mono.nix { };

  # ---------------------------------------------------------------
  # vpn — состояние туннеля (сам клиент hysteria — в блоке «3» ниже)
  # ---------------------------------------------------------------
  # Сервер один, выбирать нечего: команда только показывает, работает ли
  # туннель и с какой задержкой, и умеет его перезапустить. Прошлые версии
  # умели перебирать серверы и переключаться между ними сами — от этого
  # было больше путаницы, чем пользы, поэтому всё убрано.
  proxyAddr = "127.0.0.1:3128";
  # Проверяем не «поднялся ли туннель», а достижимость того, ради чего он
  # заведён. Любой HTTP-ответ = успех (на / прилетает 404): важен факт
  # ответа, а не код.
  realUrl = "https://api.anthropic.com/";

  vpn = pkgs.writeShellApplication {
    name = "vpn";
    runtimeInputs = with pkgs; [ curl systemd coreutils gawk ];
    text = ''
      unit=hysteria-client

      # Состояние = юнит жив И через прокси реально ходит трафик. Локальный
      # порт 3128 hysteria открывает только после успешного хендшейка,
      # поэтому ответ через него и есть доказательство живого туннеля.
      status() {
        local state out code time ip
        state=$(systemctl is-active "$unit" || true)
        if [ "$state" != active ]; then
          echo "✗ сервис $unit: $state — посмотри: systemctl status $unit"
          return 1
        fi

        if ! out=$(curl -sS -m 15 -x "http://${proxyAddr}" -o /dev/null \
                     -w '%{http_code} %{time_total}' "${realUrl}" 2>&1); then
          echo "✗ туннель не отвечает: $out"
          return 1
        fi
        read -r code time <<< "$out"
        # 403 отдаёт региональная блокировка Anthropic: канал есть, но claude
        # через него не пойдёт. Без этой строки «работает, а claude нет» —
        # загадка.
        if [ "$code" = 403 ]; then
          echo "✗ Anthropic блокирует этот адрес (403) — claude работать не будет"
        else
          echo "● работает — $unit, ${proxyAddr}"
        fi
        echo "  пинг: $(awk -v t="$time" 'BEGIN { printf "%.0f", t * 1000 }') мс (api.anthropic.com → $code)"
        ip=$(curl -sS -m 10 -x "http://${proxyAddr}" https://api.ipify.org 2>/dev/null || echo "?")
        echo "  адрес: $ip"
        [ "$code" != 403 ]
      }

      restart() {
        # sudo, а не голый systemctl: агента polkit в сессии под niri нет,
        # и запрос прав упёрся бы в «Interactive authentication required».
        sudo systemctl restart "$unit"
        echo -n "перезапускаю"
        # Хендшейк укладывается в штатный таймаут hysteria (20 с); ждём 25.
        for _ in $(seq 25); do
          if curl -sS -m 3 -o /dev/null -x "http://${proxyAddr}" "${realUrl}"; then
            break
          fi
          echo -n "."
          sleep 1
        done
        echo
        status
      }

      case "''${1:-}" in
        ""|st|status) status ;;
        restart) restart ;;
        -h|--help|help)
          echo "vpn            работает ли туннель, пинг и внешний адрес"
          echo "vpn restart    перезапустить hysteria-client (спросит пароль)"
          ;;
        *) echo "не знаю команду: $1 (см. vpn -h)" >&2; exit 1 ;;
      esac
    '';
  };

  # claude-code, всегда ходящий через hysteria (http-прокси на 3128).
  # Обёртка, а не глобальные HTTPS_PROXY — через VPN идёт только claude,
  # остальная система работает напрямую.
  # Именно http-прокси, а не socks5: он резолвит имена на стороне сервера,
  # поэтому не упирается в отсутствие IPv6 у VPN-сервера.
  #
  # Заодно здесь глушится самообновление скилла archify (см. home.nix): его
  # версия пришпилена flake.lock, а собственная проверка в лучшем случае
  # бесполезна, в худшем — предложит агенту выполнить `npx skills add` поверх
  # каталога в /nix/store, доступного только на чтение. Переменная нужна ровно
  # внутри сессий claude, поэтому живёт в обёртке, а не в sessionVariables.
  claude-code-vpn = pkgs.symlinkJoin {
    name = "claude-code-vpn";
    paths = [ pkgs.claude-code ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/claude \
        --set HTTPS_PROXY "http://127.0.0.1:3128" \
        --set HTTP_PROXY  "http://127.0.0.1:3128" \
        --set NO_PROXY    "localhost,127.0.0.1,::1" \
        --set ARCHIFY_UPDATE_CHECK_DISABLED "1"
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
  # `default` — единственный пакет флейка (официальный .deb, уже самодостаточный
  # Electron-трей без FHS-костылей), в отличие от старого k3d3-флейка с
  # claude-desktop-with-fhs.
  claude-desktop-base = inputs.claude-desktop.packages.${pkgs.stdenv.hostPlatform.system}.default;
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
# =============================================================
# Общая часть обеих машин. Всё, что зависит от железа — имя хоста,
# видеодрайвер, модули initrd, stateVersion, hardware-configuration —
# живёт в hosts/<имя>/default.nix, а не здесь.
# =============================================================
{
  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  # Без лимита /boot (1 ГБ) копит ядра и initrd всех поколений. 10 записей
  # в меню — откатиться есть куда, а раздел не переполнится.
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # zswap — сжатый кеш страниц ПЕРЕД свопом на диске: страница сначала
  # жмётся zstd и остаётся в RAM, и только вытесненное из этого пула
  # уезжает на диск по-настоящему.
  #
  # Зачем: на стационаре в свопе стабильно висело ~6 ГБ при 15 ГБ RAM
  # (Steam, zen с десятком процессов, electron-приложения, claude), и
  # /proc/pressure/io показывал `full avg300=8.49` — система целиком
  # стояла на диске 8.5% времени. Проявлялось это как секундные паузы на
  # холодном старте приложений: нажатие Mod+T и терминал через три
  # секунды. Разжать страницу из RAM на порядки дешевле, чем прочитать
  # её с диска.
  #
  # max_pool_percent=20 — потолок пула, доля физической RAM. Заводские
  # 20 и есть, пишем явно, чтобы цифра была на виду при подкрутке.
  #
  # Ядерные параметры, поэтому применяются ТОЛЬКО ПОСЛЕ ПЕРЕЗАГРУЗКИ,
  # одного nixos-rebuild switch мало. Проверка после неё:
  #   cat /sys/module/zswap/parameters/enabled   → Y
  boot.kernelParams = [
    "zswap.enabled=1"
    "zswap.compressor=zstd"
    "zswap.zpool=zsmalloc"
    "zswap.max_pool_percent=20"
  ];

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

  # Раскладка — в home/niri/config.kdl (блок xkb), services.xserver.xkb
  # под niri никто не читает.

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users."artur" = {
    isNormalUser = true;
    description = "artur";
    extraGroups = [ "networkmanager" "wheel" ];
    shell = pkgs.fish;   # логин-шелл fish (Batch 2)
    # Кому можно по SSH. Пароль выключен (см. services.openssh внизу), так
    # что это единственный вход — и он в git, а не в ~/.ssh/authorized_keys,
    # который на новой машине пришлось бы заводить руками. Файл sshd по-прежнему
    # читает, но источник правды — здесь; новую машину дописывать сюда.
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMbdnhp9h+DnqjB1n/Q9Em5T3usUkzUxpZyL/gk9FZYR artur@nixos"
    ];
  };

  # fish на системном уровне: регистрирует /etc/shells + vendor-completions.
  # Пользовательский конфиг fish — в home.nix (programs.fish).
  programs.fish.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Оверлей: xwayland-satellite из своего flake-входа (см. ниже).
  # claude-code берётся из основного nixpkgs как есть: отдельный вход
  # nixpkgs-cc и подмена манифеста сняты 2026-09-26, когда nixpkgs догнал
  # ту же версию (2.1.280). Если снова понадобится CLI свежее nixpkgs —
  # вернуть можно из git-истории.
  nixpkgs.overlays = [
    (final: prev: {
        # xwayland-satellite из main: в релизном 0.8.2 меню-бар Steam
        # закрывается сразу после открытия. Полное объяснение и условие
        # удаления — у одноимённого input в flake.nix.
        #
        # Берётся derivation из nixpkgs с подменённым src, а НЕ готовый пакет
        # из flake апстрима: тот собирает через cargoLock.lockFile, то есть
        # fetchCrate по каждому крейту — а это https://crates.io/api/v1/...,
        # который на UA nix'ового curl отвечает 403 (index.crates.io и
        # static.crates.io при этом доступны, проверено). fetchCargoVendor
        # ходит именно туда, поэтому сборка проходит. src — сам flake-вход,
        # так что ревизия пиннится в flake.lock и своего sha256 не требует.
        # cargoHash из nixpkgs не подошёл бы: Cargo.lock в main изменился.
        xwayland-satellite = prev.xwayland-satellite.overrideAttrs (old: {
          version = "0.8.2-unstable-2026-09-09";   # add2795, merge PR #494
          src = inputs.xwayland-satellite;
          cargoDeps = prev.rustPlatform.fetchCargoVendor {
            src = inputs.xwayland-satellite;
            hash = "sha256-s1gl9eR6Mt2QLrhfcowstPFjzwE/lz4PJhJzWYHoIHg=";
          };
          meta = old.meta // {
            changelog = "https://github.com/Supreeeme/xwayland-satellite/pull/494";
          };
        });
      })
  ];

  # ---------------------------------------------------------------
  # Nix: flakes + бинарный кэш noctalia
  # ---------------------------------------------------------------
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    # Одинаковые файлы в сторе схлопываются в хардлинки прямо при сборке.
    auto-optimise-store = true;
    extra-substituters = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    ];
  };

  # nh — обёртка над nix: ребилд с прогрессом и диффом пакетов, чистка стора.
  # Модулем, а не пакетом: он же задаёт NH_FLAKE (путь к флейку, чтобы
  # `nh os switch` работал из любого каталога) и еженедельную чистку.
  #
  # Чистка заменила nix.gc: без неё стор за месяц дорос до 81 ГБ при
  # закрытии текущей системы в 21.8 ГБ — каждая ревизия nixpkgs тянет своё
  # закрытие, а поколения копились. nh clean all, в отличие от nix.gc, берёт
  # ещё пользовательские профили и gcroots (direnv, result-ссылки).
  # --keep 5 --keep-since 14d: откатиться есть куда, дубли не растут.
  programs.nh = {
    enable = true;
    flake = "/home/artur/nixos";
    clean = {
      enable = true;
      dates = "weekly";
      extraArgs = "--keep 5 --keep-since 14d";
    };
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

  # Обязателен вместе с xdg.portal: document-portal монтирует
  # /run/user/1000/doc через FUSE и без setuid-обёртки fusermount3
  # падает на каждом входе («fuse init failed»), из-за чего система
  # всегда висит в состоянии degraded. Обёртки создаёт только этот
  # модуль — самого пакета fuse3 в systemPackages недостаточно.
  programs.fuse.enable = true;

  # ---------------------------------------------------------------
  # 2. noctalia v5 (шелл)
  # ---------------------------------------------------------------
  programs.noctalia = {
    enable = true;
    recommendedServices.enable = true;  # NetworkManager, Bluetooth, UPower, power-profiles-daemon
  };

  # ---------------------------------------------------------------
  # 3. Hysteria (VPN-клиент, http-прокси на 3128)
  # ---------------------------------------------------------------
  # Конфиг с ключом сервера — секрет, поэтому лежит в репозитории
  # ЗАШИФРОВАННЫМ (secrets/hysteria-client.age, agenix) и расшифровывается
  # при активации системы приватным ключом хоста (/etc/ssh/ssh_host_ed25519_key).
  # path задан явно: юнит и сам hysteria продолжают видеть привычный
  # /etc/hysteria/client.yaml, только теперь это симлинк в /run/agenix.
  # Получатели (кто может расшифровать) перечислены в secrets/secrets.nix;
  # после добавления новой машины — `agenix -r` и коммит.
  # Сменить сервер: `agenix -e hysteria-client.age` из каталога secrets/.
  age.secrets.hysteria-client = {
    file = ../secrets/hysteria-client.age;
    path = "/etc/hysteria/client.yaml";
    mode = "0400";
  };

  # Сервер один и перебора нет: юнит просто держит клиент живым, а жив ли
  # туннель на самом деле — показывает команда `vpn` (см. let выше).
  systemd.services.hysteria-client = {
    description = "Hysteria 2 client";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.hysteria}/bin/hysteria client -c ${config.age.secrets.hysteria-client.path}";
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
    wget
    fd                    # быстрый find; его же берут telescope и yazi, если есть
    uv                    # python-тулчейн и раннер (uvx) для проектов
    # Нужен скиллу archify (см. home.nix): SKILL.md велит агенту звать
    # `node bin/archify.mjs`, а claude-code свой node наружу не отдаёт.
    # Зависимостей у скилла нет, поэтому голого интерпретатора хватает.
    nodejs_22
    # niri окружение
    kitty                # терминал (единственный; вместо alacritty/rio)
    xwayland-satellite   # X11-приложения
    # Зеркалирование монитора. Своего дублирования выходов у niri нет:
    # wl-mirror показывает содержимое одного выхода в окне, которое можно
    # сразу развернуть на весь экран на другом мониторе.
    #
    # Последний аргумент — ИСТОЧНИК, --fullscreen-output — ПРИЁМНИК:
    #   wl-mirror --fullscreen-output HDMI-A-2 HDMI-A-1   Acer → Samsung
    #   wl-mirror HDMI-A-1                                просто окном
    #
    # Осторожно с -f: это --freeze (заморозить картинку), а НЕ fullscreen.
    # Полный экран без указания монитора — -F.
    #
    # При запуске ругается «missing ext_image_copy_capture protocol»: этого
    # протокола у niri нет, wl-mirror сам откатывается на screencopy-dmabuf
    # и работает. Сообщение безобидное.
    wl-mirror
    # сеть
    hysteria
    vpn        # `vpn` — статус и пинг, `vpn restart` — перезапуск; см. let выше
    # agenix — CLI для работы с секретами: `agenix -e <файл>.age` править,
    # `agenix -r` перешифровать на всех получателей из secrets/secrets.nix.
    # Запускать ИЗ каталога secrets/ — он ищет secrets.nix рядом.
    inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
    # 4. Claude Code (CLI, unfree) — обёрнутый на VPN, см. let выше
    claude-code-vpn
    # 5. Obsidian (unfree) — само хранилище синхронизируется через syncthing ниже
    obsidian

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
    # satty (редактор снимка) — programs.satty в home/home.nix, вместе с конфигом
    wf-recorder          # запись видео экрана
    libnotify            # notify-send — индикация записи (демон уведомлений = noctalia)
    screenrec            # обёртка старт/стоп записи с таймером, см. let выше
    # ---- Картинки ----
    # gthumb — просмотрщик + быстрые правки (кроп, поворот, ресайз, коррекция)
    # и пакетные операции над папкой; единственный хендлер image/* для
    # xdg-open. satty в эту роль не входит: он аннотирует свежий снимок из
    # пайплайна noctalia/grim, а не готовый файл с диска.
    gthumb
    # aseprite — пиксель-арт и спрайтовая анимация (unfree: кэша нет,
    # собирается локально вместе со своим skia)
    aseprite
    # CLI-утилиты
    gh          # github-cli
    lazygit
    ripgrep     # уже подтягивался как зависимость — теперь объявлен явно
    ouch        # архиватор «одной командой»; им же живёт плагин ouch.yazi
                # (превью содержимого архивов и упаковка по C) — см. home.nix
    # Мультиплексора здесь НЕТ, и это единственное место в файле, где пакет
    #   объявлен не тут. Стоял tmux (+ smug как описатель сессий), теперь
    #   zellij — и его ставит модуль home-manager, programs.zellij в
    #   home/home.nix. Разнести пакет и конфиг, как у kitty и mpv, не выходит:
    #   модуль кладёт finalPackage в home.packages сам и тем же путём
    #   подставляет абсолютный путь бинаря в автозапуск fish. Продублируй
    #   пакет здесь — и в системе будут две разные копии zellij, а автозапуск
    #   позовёт не ту, что в PATH.

    # ---- Зависимости плагинов noctalia (см. [[08 - Кастомизация (rice)]]) ----
    # Плагины ставятся из витрины noctalia (состояние — в ~/.local/state/noctalia),
    # но их внешние зависимости обязаны быть в системе, иначе плагин молча мёртв.
    bitwarden-cli   # `bw` — плагин noctalia/bitwarden ходит в локальный `bw serve`,
                    # а не в облако. Под свой Vaultwarden: `bw config server <url>`
                    # ОДИН РАЗ до логина (или Server URL в настройках плагина).
    python3         # хуки и MCP-шим плагина lowcache/claude-companion (stdlib, без pip)
    playerctl       # «что играет»: шим claude-companion + медиа-бинды niri
    fzf             # file-search и nix-search; home-manager кладёт свой fzf
                    # только в профиль пользователя, а не в PATH сервиса noctalia
    glib            # gdbus — file-search
    nix-search-tv   # индекс для nix-search (/nix в лаунчере)
    qrencode        # qrcode

    # ---- Видимость пакетов (чеклист [[04]], «Просмотр установленного») ----
    # В NixOS источник правды — сам конфиг. nix-tree отвечает на то, чего
    # конфиг не покрывает: кто кого тянет и сколько весит. Дифф поколений
    # печатает nh после каждого switch, nix-index — модулем ниже.
    nix-tree

    # ---- Batch 3a: мессенджеры, торрент (из nixpkgs) ----
    vesktop           # Discord-клиент (вместо discord)
    ayugram-desktop   # форк Telegram (бинарник называется AyuGram)
    qbittorrent       # торренты

    # specify-cli — CLI Spec Kit (`specify init`/`/specify`/`/plan`/`/tasks`
    # в Claude Code), см. pkgs/specify-cli.nix
    specify-cli

    # ---- Связь с телефоном ----
    # Из тройки KDE Connect / scrcpy / LocalSend взят только LocalSend (ревизия
    # 2026-07-27): нужна была разовая передача файлов, а не уведомления и экран.
    # Фоновая синхронизация папок и так на syncthing (см. ниже).
    localsend

    # ---- Batch 3b: браузер (из стороннего flake) ----
    # Zen — ветка Twilight (ночные сборки) вместо стабильной (ревизия 2026-07-28).
    # twilight, а не twilight-official: первый берёт зеркало, которое сам flake
    # пересобирает и пиннит по хешу (обновляется через nix flake update), второй
    # тянет катящийся официальный релиз и ломает eval, как только upstream
    # перевыложит архив под тем же URL.
    # Профиль общий со стабильной версией (Vendor=Mozilla, Name=Zen у обеих),
    # так что история, вкладки, user.js и тема из noctalia остаются на месте.
    # Бинарь и .desktop называются zen-twilight, а не zen-beta.
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.twilight
    # claude-desktop сюда НЕ входит: ставится модулем programs.claude-desktop
    # ниже (свой пакет claude-desktop-vpn, обёрнутый на VPN, см. let выше)

    # ---- Офис ----
    # OnlyOffice — редактор документов (docx/xlsx/pptx), бинарная сборка от
    # вендора со своим Qt внутри (замыкание ~2.1 ГиБ, берётся из кеша).
    # Единственный офисный пакет в системе, поэтому он же и хендлер
    # office-форматов для xdg-open — mimeApps настраивать не требуется.
    # Бинарь и .desktop называются onlyoffice-desktopeditors.
    onlyoffice-desktopeditors

    # ---- Почта ----
    thunderbird
    tutanota-desktop

    # ---- Продуктивность ----
    super-productivity   # таск-менеджер / таймтрекер

    # ---- Музыка ----
    # Aonsoku — десктоп-клиент Navidrome/Subsonic. Библиотека стримится
    # с сервера; Downloads (трек/альбом/артист/плейлист) сохраняет файлы
    # локально для офлайн-прослушивания.
    aonsoku

    # ---- Видео ----
    # mpv — плеер локальных файлов (в первую очередь того, что накачал
    # qbittorrent) и ссылок: yt-dlp вшит в обёртку пакета, поэтому
    # `mpv <ссылка на youtube>` работает без отдельной установки.
    # Взят вместо VLC ради веса и того, что настраивается декларативно:
    # конфиг и бинды (включая кириллические зеркала) — programs.mpv в
    # home/home.nix, здесь только пакет, схема та же, что у kitty.
    # Плеер в системе единственный, поэтому он же хендлер video/* для
    # xdg-open — mimeApps настраивать не требуется.
    mpv

    # ---- Игры: Lutris (второй способ, кроме Steam см. ниже) ----
    # Не-Steam Windows-игры: GOG, Epic, автономные .exe. Отдельного
    # NixOS-модуля programs.lutris в этом срезе nixpkgs ещё нет —
    # заводим обычными пакетами. 32-битная графика уже включена модулем
    # steam ниже, отдельно не нужна. Системный wine и winetricks — база
    # и ручная донастройка префиксов; сам Lutris при установке игры
    # докачивает свои раннеры (wine-ge, DXVK, vkd3d) под конкретную игру.
    # Ноут (гибрид, PRIME offload): чтобы игра шла на dGPU, а не на iGPU,
    # в настройках игры в Lutris → System options → Command prefix
    # прописать nvidia-offload — тот же приём, что и для Steam ниже.
    lutris
    mangohud   # оверлей FPS/нагрузки: MANGOHUD=1 %command% в Steam, или в Lutris
    wineWow64Packages.stable   # не wineWowPackages — тот deprecated в этом nixpkgs
    winetricks

    # ---- Чистка диска ----
    # ncdu — TUI-обход каталогов по размеру, удаление клавишей `d`.
    #   Домашка: `ncdu ~`, вся система: `sudo ncdu / --exclude /nix`.
    ncdu
  ];

  # nix-index — «какой пакет даёт этот бинарь», плюс обработчик
  # command-not-found в fish: набрал неизвестную команду — подсказал пакет.
  # Базу собирает апстрим nix-index-database раз в неделю (вход во flake.nix,
  # модуль подключён в mkHost), руками `nix-index` запускать не нужно.
  # comma: `, cowsay hi` — запустить программу из nixpkgs, не устанавливая.
  programs.nix-index.enable = true;
  programs.nix-index-database.comma.enable = true;
  # Штатный command-not-found ходит в базу channels, которых при flake-подходе
  # нет, — он тут нерабочий. Плюс модуль nix-index на него ругается assert'ом.
  programs.command-not-found.enable = false;

  # TRIM для SSD раз в неделю. Без него контроллер со временем пишет
  # медленнее: он не знает, какие блоки файловая система уже освободила.
  services.fstrim.enable = true;

  # Обновления прошивок через LVFS: BIOS/EC ноутбука, SSD, док-станции.
  # Ничего не ставит сам — смотреть и применять руками:
  #   fwupdmgr refresh && fwupdmgr get-updates && fwupdmgr update
  services.fwupd.enable = true;

  # udisks2 — демон, который умеет монтировать съёмные носители БЕЗ sudo:
  # разрешение выдаётся через polkit локальной сессии. Даёт команду udisksctl
  # и точки монтирования в /run/media/artur/<метка>.
  # Сам по себе он ничего не монтирует автоматически — монтирование руками
  # из yazi (плагин mount, см. home.nix, клавиша M).
  services.udisks2.enable = true;

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
  # Claude Desktop — модулем стороннего флейка (nixosModules.default),
  # см. flake.nix и claude-desktop-vpn в let выше.
  # ---------------------------------------------------------------
  programs.claude-desktop = {
    enable = true;
    package = claude-desktop-vpn;
    # Cowork — агент работает в QEMU micro-VM. Модуль сам заводит symlink'и
    # OVMF/virtiofsd в /usr (приложение проверяет только эти абсолютные
    # пути, без env-переопределений) и boot.kernelModules = [ "vhost_vsock" ].
    # Доступ к /dev/kvm — через группу kvm ниже.
    cowork.enable = true;
    cowork.kvmUsers = [ "artur" ];
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
  # ВАЖНО про ноут: там гибрид (дисплей на AMD, NVIDIA по PRIME offload),
  # и игра по умолчанию пойдёт на iGPU. Чтобы она шла на dGPU, в свойствах
  # игры в Steam → Launch Options прописать:  nvidia-offload %command%
  # На десктопе видеокарта одна — ничего дописывать не нужно.
  programs.steam.enable = true;

  # gamemode — на время игры поднимает приоритет процесса и переключает
  # CPU governor на performance. В Steam: Launch Options → gamemoderun %command%
  # (вместе с оверлеем: gamemoderun mangohud %command%). В Lutris — галка
  # «Enable Feral GameMode» в System options.
  programs.gamemode.enable = true;
  # gamescope — микрокомпозитор Valve вокруг одной игры: своё разрешение,
  # FSR-апскейл, ограничение FPS, изоляция от niri. Когда игра капризничает
  # с полноэкранным режимом под Wayland:
  #   gamescope -W 1920 -H 1080 -f -- %command%
  programs.gamescope.enable = true;

  # ---------------------------------------------------------------
  # nix-ld — динамический линковщик-заглушка для generic-бинарников
  # ---------------------------------------------------------------
  # Без него /lib64/ld-linux-x86-64.so.2 указывает на stub-ld, который просто
  # печатает ошибку вместо запуска. Ломает конкретно pressure-vessel
  # (контейнер Steam Linux Runtime, который umu/Proton поднимает поверх уже
  # существующей FHS-песочницы Lutris) — сторонние Windows-установщики через
  # Proton падают на инициализации этого вложенного контейнера с "Could not
  # start dynamically linked executable". С nix-ld он получает нормальный
  # ld.so и работает как на обычном дистрибутиве.
  programs.nix-ld.enable = true;

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
      # Iosevka-сборка с Nerd-глифами внутри. Держим ради охвата:
      # ~17900 кодовых точек — ловит то, чего нет в JetBrains Mono.
      # Четыре веса плюс курсивы.
      # Основным больше не является — узкий, и на крупном кегле это
      # видно; моноширина везде уехала на JetBrains Mono.
      lyth-mono

      # Основной гротеск: интерфейсы GTK и текст в вебе, где сайт
      # не назвал шрифт сам. Берём ibm-plex.sans, а не ibm-plex
      # целиком: полный пакет тянет арабский, деванагари, тайский,
      # иврит, японский и корейский — 334 МиБ замыкания против 5.3.
      # Не путать с ibm-plex.sans-variable: там семейство называется
      # «IBM Plex Sans Var», и defaultFonts по имени его не найдёт.
      ibm-plex.sans

      # Основной шрифт с засечками: длинные статьи, читалки, всё,
      # что просит serif. ParaType рисовал его по госпрограмме под
      # русский, так что кириллица здесь первична, а не пририсована
      # к латинице задним числом.
      paratype-pt-serif

      nerd-fonts.jetbrains-mono   # ttf-jetbrains-mono-nerd
      noto-fonts                  # noto-fonts
      noto-fonts-cjk-sans         # noto-fonts-cjk
      # DejaVu, Liberation и Noto Color Emoji отдельно не нужны: их уже
      # ставит enableDefaultPackages выше.
    ];
    fontconfig.defaultFonts = {
      # JetBrains Mono самодостаточен: сборка Nerd Fonts, иконки и
      # powerline у него свои. Lyth — страховка на экзотику,
      # у Lyth охват шире всех (~17900 знаков).
      # Здесь ВЕЗДЕ имена без суффикса Mono: он нужен только терминалу,
      # где иконочные глифы обязаны быть одинарной ширины (см.
      # programs.kitty в home/home.nix).
      monospace = [ "JetBrainsMono Nerd Font" "LythMonoTerm Nerd Font" ];

      # Noto остаётся вторым не как «запасной похуже», а как ловец
      # экзотики: у Plex 893 знака, у PT Serif 717 — обоим хватает
      # на кириллицу с типографикой, но на греческом, деванагари
      # или стрелках подхватит уже Noto.
      sansSerif = [ "IBM Plex Sans" "Noto Sans" ];
      serif     = [ "PT Serif" "Noto Serif" ];
      emoji     = [ "Noto Color Emoji" ];
    };
  };

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  # Только по ключу: порт 22 открыт, а пароль — это подбор. Ключи — в
  # users.users.artur.openssh.authorizedKeys выше.
  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
  };
  # Побочный, но важный эффект: host-ключ /etc/ssh/ssh_host_ed25519_key,
  # который agenix использует для расшифровки секретов.
}
