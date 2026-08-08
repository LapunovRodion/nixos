{ config, pkgs, ... }:

# =============================================================
# laptop — ASUS ROG Zephyrus G14 GA403UU.
# Гибрид: AMD iGPU (Radeon 780M, на нём матрица) + NVIDIA RTX 4050 (dGPU).
# Панель 2880x1800, scale 1.75 → логические 1645x1029.
# =============================================================

{
  # dev.nix подключён только здесь: контейнеры и виртуализация нужны на
  # рабочей машине, на desktop им делать нечего. Выключается флагами
  # local.dev.* ниже.
  imports = [ ./hardware-configuration.nix ../../modules/dev.nix ];

  networking.hostName = "laptop";

  environment.systemPackages = [
    # vncviewer — подключение к desktop:5900 по Tailscale (см. wayvnc на desktop).
    pkgs.tigervnc
  ];

  # Первая установка была на 26.05 — значение не меняется никогда,
  # оно фиксирует семантику дефолтов, а не версию системы.
  system.stateVersion = "26.05";

  # amdgpu грузится из initrd — ДО nvidia. Иначе два DRM-устройства гибрида
  # (amdgpu + nvidia) регистрируются в гонке, и minor'ы меняются местами от
  # загруза к загрузу: встроенная матрица зовётся то eDP-1, то eDP-2
  # (а подсветка — то amdgpu_bl1, то amdgpu_bl2). Всё, что привязано к имени
  # выхода, при этом отваливается — так пропали виджеты рабочего стола
  # noctalia, прибитые к eDP-2. Матрица физически на amdgpu (0000:65:00.0),
  # поэтому фиксируем его первым: панель всегда eDP-1.
  # Список сливается с пустым boot.initrd.kernelModules из hardware-configuration.nix.
  boot.initrd.kernelModules = [ "amdgpu" ];

  # ---------------------------------------------------------------
  # NVIDIA (RTX 4050, dGPU) — драйвер для игр.
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

  # ---- Чем эта машина отличается (см. modules/options.nix) ----
  local = {
    flakeAttr = "laptop";
    primaryOutput = "eDP-1";
    outputs = [ "eDP-1" ];
    # Панель 2880x1800 при scale 1.75. Все координаты виджетов —
    # в ЛОГИЧЕСКИХ пикселях, поэтому здесь размер после деления.
    screen = { width = 1645; height = 1029; };
    # На этой плотности заводской размер великоват. Значения разные:
    # уведомления читаются с расстояния, OSD мелькает под рукой.
    notificationScale = 0.95;
    osdScale = 0.7;
    hasBattery = true;
    zenProfileDir = "vkvdhp86.Default Profile";
    niriOutputs = ./outputs.kdl;

    # Окружение разработки (см. modules/dev.nix). Выставить в false и
    # сделать switch — podman и libvirt уйдут из системы.
    dev = {
      containers.enable = true;   # Oracle XE для плагина AutoCAD
      vm.enable = true;           # гостевая Windows с самим AutoCAD
    };
  };
}
