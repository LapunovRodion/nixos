{ config, pkgs, ... }:

# =============================================================
# desktop — стационарный: NVIDIA RTX 3060 Eagle 12 ГБ, три монитора
# 1920x1080, все три воткнуты в видеокарту.
#
# Гибрида здесь нет, поэтому нет ни PRIME, ни nvidia-offload, ни фокуса
# с порядком загрузки amdgpu: DRM-устройство одно, имена выходов и так
# стабильны от загрузки к загрузке.
# =============================================================

{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "desktop";

  environment.systemPackages = [
    pkgs.wayvnc
  ];

  # 5900 — wayvnc (см. hosts/desktop/outputs.kdl). Открыт для всей локалки,
  # не только для tailscale0: через Tailscale картинка сильно лагала
  # (WireGuard-туннель добавляет задержку/накладные расходы поверх и так
  # небыстрого RFB-протокола), в локальной сети должно быть заметно
  # плавнее. Tailscale не отключаем — просто вторым путём, для
  # подключения не из дома, порт остаётся доступен и через него.
  # Без пароля (enable_auth=false в wayvnc-config) — осознанный выбор:
  # риск приемлем для доверенной домашней сети.
  networking.firewall.allowedTCPPorts = [ 5900 ];

  # ЗАПОЛНИТЬ при установке: ставится равным версии NixOS, с которой машина
  # установлена, и после этого не меняется никогда.
  system.stateVersion = "26.05";

  # ---------------------------------------------------------------
  # NVIDIA (RTX 3060, GA106 «Ampere») — драйвер для игр (Steam).
  # ---------------------------------------------------------------
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    # Обязателен для Wayland: без nvidia_drm.modeset=1 niri не запустится.
    modesetting.enable = true;
    # Открытый модуль ядра поддерживается начиная с Turing; Ampere подходит.
    open = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    # Стационару не нужны ни runtime-PM видеокарты, ни восстановление
    # VRAM после suspend — это про ноутбучные сценарии.
    powerManagement.enable = false;
  };

  # ---- Чем эта машина отличается (см. modules/options.nix) ----
  local = {
    flakeAttr = "desktop";
    # Сняты с живой машины (`niri msg outputs`). Единственный DisplayPort
    # определился как DP-2, DP-1 не существует — на угаданном имени виджеты
    # рабочего стола не появлялись нигде, потому что вешать их было не на что.
    # Те же имена стоят в ./outputs.kdl.
    #
    # Главный — центральный Dell P2214H: на нём часы, погода, sysmon и орб.
    primaryOutput = "DP-2";
    # Порядок слева направо: Acer, Dell, Samsung.
    outputs = [ "HDMI-A-2" "DP-2" "HDMI-A-1" ];
    # 1920x1080 при scale 1 → логический размер равен физическому.
    screen = { width = 1920; height = 1080; };
    # Обычная плотность — уведомления и OSD заводского размера.
    notificationScale = 1.0;
    osdScale = 1.0;
    hasBattery = false;
    # Профиля Zen на новой машине ещё нет. После первого запуска браузера
    # посмотреть имя каталога в ~/.config/zen/profiles.ini и вписать сюда —
    # тогда home-manager положит туда user.js (шрифты, стартовая страница).
    zenProfileDir = null;
    niriOutputs = ./outputs.kdl;
    wayvncConfig = ./wayvnc-config;
  };
}
