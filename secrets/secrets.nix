# =============================================================
# Список получателей для agenix: кто может расшифровать какой секрет.
#
# Этот файл читает ТОЛЬКО CLI `agenix` (запускать из этого каталога) —
# в саму систему он не импортируется. Хранить его в git безопасно:
# здесь одни публичные ключи.
#
# Ключи двух видов, и оба нужны:
#   - пользовательский (~/.ssh/id_ed25519) — им я правлю секреты
#     командой `agenix -e`, с любой машины, где этот ключ есть;
#   - host-ключ каждой машины (/etc/ssh/ssh_host_ed25519_key) — им
#     система расшифровывает секрет при активации, ещё до логина.
#
# ДОБАВЛЕНИЕ МАШИНЫ: установить её, взять `cat /etc/ssh/ssh_host_ed25519_key.pub`,
# вписать сюда, выполнить `agenix -r` (перешифровать все секреты на новый
# список), закоммитить. Пока ключа тут нет, машина секрет не прочитает —
# hysteria на ней просто не поднимется, остальное работает.
# =============================================================

let
  # Пользователь (один и тот же ключ на всех машинах).
  artur = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMbdnhp9h+DnqjB1n/Q9Em5T3usUkzUxpZyL/gk9FZYR artur@nixos";

  # Хосты. Имя root@nixos у ноутбучного ключа осталось от прежнего
  # networking.hostName — сам ключ при переименовании не меняется.
  laptop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHMLtQmA3v+EQx/JWOW77g/C36B9vyEj4gSTQIaXQO2y root@nixos";
  # У десктопа имя в комментарии тоже root@nixos, и по той же причине:
  # ключ сгенерирован при первой загрузке, когда машина ещё называлась
  # заводским "nixos", а networking.hostName = "desktop" приехал позже.
  desktop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPHiXnkJ52owpYEsNxknI9gFLKRQBMm3bv6FZWO0Yq7t root@nixos";

  hosts = [ laptop desktop ];
in
{
  # Конфиг hysteria-клиента: адрес сервера, пароль, obfs-ключ.
  # Разворачивается в /etc/hysteria/client.yaml (см. modules/common.nix).
  "hysteria-client.age".publicKeys = [ artur ] ++ hosts;
}
