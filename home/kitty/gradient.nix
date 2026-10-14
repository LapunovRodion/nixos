# post_hook шаблона kitty: рисует картинку-градиент из цветов свежей
# палитры. Разбор — в самом скрипте. writeShellApplication добавляет
# шебанг и `set -euo pipefail` и прогоняет shellcheck при сборке,
# поэтому в файле их нет.
#
# runtimeInputs обязателен целиком: хук запускается из user-сервиса
# (noctalia или caelestia), где PATH минимальный, — coreutils и findutils
# оттуда не взять. imagemagick при этом в systemPackages не нужен, он
# приезжает замыканием этой обёртки.
#
# Общий для обоих столов: home/noctalia.nix и home/hyprland.nix.
pkgs:
pkgs.writeShellApplication {
  name = "kitty-gradient";
  runtimeInputs = with pkgs; [ imagemagick coreutils findutils procps gawk ];
  text = builtins.readFile ./gradient.sh;
}
