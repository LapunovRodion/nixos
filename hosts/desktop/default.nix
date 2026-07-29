{ config, ... }:

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

  # ЗАПОЛНИТЬ при установке: ставится равным версии NixOS, с которой машина
  # установлена, и после этого не меняется никогда.
  system.stateVersion = "26.05";

  # ---------------------------------------------------------------
  # NVIDIA (RTX 3060, GA106 «Ampere») — драйвер + CUDA для локальных LLM.
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
    # ЗАПОЛНИТЬ после первой загрузки: `niri msg outputs`.
    # Те же имена должны стоять в ./outputs.kdl.
    primaryOutput = "DP-1";
    outputs = [ "DP-1" "DP-2" "HDMI-A-1" ];
    # 1920x1080 при scale 1 → логический размер равен физическому.
    screen = { width = 1920; height = 1080; };
    # Обычная плотность — уведомления и OSD заводского размера.
    uiScale = 1.0;
    hasBattery = false;
    # Профиля Zen на новой машине ещё нет. После первого запуска браузера
    # посмотреть имя каталога в ~/.config/zen/profiles.ini и вписать сюда —
    # тогда home-manager положит туда user.js (шрифты, стартовая страница).
    zenProfileDir = null;
    niriOutputs = ./outputs.kdl;
  };
}
