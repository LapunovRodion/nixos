{ config, lib, modulesPath, ... }:

# =============================================================
# ЗАГЛУШКА. Этот файл ОБЯЗАН быть заменён на реальный, снятый с железа:
#
#   sudo nixos-generate-config --show-hardware-config \
#     > /mnt/etc/nixos/hardware-configuration.nix     # при установке
#   # или уже на установленной системе:
#   sudo nixos-generate-config --show-hardware-config \
#     > ~/nixos/hosts/desktop/hardware-configuration.nix
#
# Здесь заведомо ЛОЖНЫЕ UUID: они нужны лишь для того, чтобы
# `nix eval .#nixosConfigurations.desktop...` проходил с ноутбука и было
# видно, что десктопная ветка конфига вычисляется. Собрать и загрузить
# систему с этими значениями невозможно — она не найдёт корень.
# =============================================================

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usb_storage" "usbhid" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];             # kvm-amd / kvm-intel — по факту CPU
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/00000000-0000-0000-0000-000000000000";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/0000-0000";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
