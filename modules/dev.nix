{ config, lib, pkgs, ... }:

# =============================================================
# Окружение разработки: контейнеры и виртуализация.
#
# Модуль подключается ТОЛЬКО из hosts/laptop — на desktop эта машинерия
# не нужна. Всё закрыто флагами local.dev.*, поэтому снимается в два
# действия: выключить флаг → switch. Файл при этом можно и удалить
# целиком вместе со строкой импорта, ничего больше на него не ссылается.
#
# Что rebuild НЕ уберёт: образы и слои в ~/.local/share/containers/storage.
# Их надо снести до выключения флага — `podman system reset`. Данные
# конкретных баз сюда не попадают, они живут bind-mount'ами в каталогах
# проектов.
# =============================================================

let
  cfg = config.local.dev;
in
{
  options.local.dev = {
    containers.enable = lib.mkEnableOption ''
      podman в rootless-режиме плюс dockerCompat (команда `docker` как
      алиас). Именно podman, а не docker: демон docker работает от root,
      а членство в группе docker фактически равно root на машине.
      Для rootless всё уже готово — subuid/subgid у artur заданы,
      newuidmap в wrappers, cgroup-делегирование в user.slice работает
    '';

    vm.enable = lib.mkEnableOption ''
      libvirtd + virt-manager для гостевых Windows-машин (AutoCAD).
      UEFI через OVMF и swtpm — иначе не поставить Windows 11;
      для Windows 10 хватило бы и без них, но лишним не будет
    '';
  };

  config = lib.mkMerge [

    (lib.mkIf cfg.containers.enable {
      virtualisation.podman = {
        enable = true;
        # Команда `docker` начинает указывать на podman. Удобно, потому что
        # вся документация и скрипты в проектах написаны под docker.
        dockerCompat = true;
        # Без этого контейнеры в одной сети не видят друг друга по имени.
        defaultNetwork.settings.dns_enabled = true;
      };

      # `podman compose` сам ничего не умеет — он делегирует внешнему
      # провайдеру и без него ругается. Ставим здесь, а не в devShell
      # проекта: без podman он всё равно бесполезен, и уходит вместе с ним.
      environment.systemPackages = [ pkgs.podman-compose ];
    })

    (lib.mkIf cfg.vm.enable {
      virtualisation.libvirtd = {
        enable = true;
        # Гостевые машины не поднимаются сами при загрузке: на ноутбуке
        # Windows с AutoCAD нужна изредка и ест 8 ГБ из 14.
        onBoot = "ignore";
        onShutdown = "shutdown";
        # OVMF отдельно включать больше не нужно: в nixpkgs 26.11 подопцию
        # qemu.ovmf убрали, образы UEFI теперь идут вместе с QEMU.
        # Остаётся только swtpm — эмуляция TPM, без неё не поставить Win11.
        qemu.swtpm.enable = true;
      };

      programs.virt-manager.enable = true;

      # Сливается со списком из common.nix, перечислять остальные не нужно.
      users.users."artur".extraGroups = [ "libvirtd" ];

      # Oracle для расширения AutoCAD поднят контейнером на хосте, а гость
      # видит его как 192.168.122.1:1521. Само по себе это не работает:
      # libvirt открывает гостю только DNS и DHCP, а остальные порты хоста
      # режет фаервол. Открываем на мосту, а не глобально — снаружи база
      # не нужна и светить её незачем.
      networking.firewall.interfaces.virbr0.allowedTCPPorts = [ 1521 ];

      environment.systemPackages = [
        # В programs.virt-manager не входит: у менеджера свой встроенный
        # просмотрщик. Отдельный клиент удобнее, когда нужна консоль одной
        # конкретной машины без всего интерфейса.
        pkgs.virt-viewer

        # Драйверы virtio для гостевой Windows: без viostor установщик не
        # увидит диск, без NetKVM не будет сети. Пакет распакован каталогом,
        # а не ISO — образ для привода собирается из него через xorriso.
        pkgs.virtio-win
      ];
    })

    (lib.mkIf (cfg.containers.enable || cfg.vm.enable) {
      # 14 ГБ ОЗУ на всё сразу — Oracle в контейнере (~2 ГБ), гостевая
      # Windows (8 ГБ) и рабочее окружение. Сжатый swap в памяти заметно
      # мягче, чем уход в отказ по OOM.
      zramSwap.enable = true;
    })

  ];
}
