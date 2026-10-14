{ config, lib, pkgs, ... }:

# =============================================================
# Окружение разработки: контейнеры.
#
# Виртуалка с Windows (libvirt + virt-manager, под AutoCAD) убрана
# 2026-10-14 — вернуть можно из git-истории.
#
# Модуль подключается ТОЛЬКО из hosts/laptop — на desktop эта машинерия
# не нужна. Закрыто флагом local.dev.containers, поэтому снимается в два
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

    (lib.mkIf cfg.containers.enable {
      # 14 ГБ ОЗУ на контейнеры и рабочее окружение. Сжатый swap в памяти
      # заметно мягче, чем уход в отказ по OOM.
      zramSwap.enable = true;
    })

  ];
}
