# post_hook шаблона kitty: рисует картинку-градиент из цветов свежей
# палитры. Разбор — в самом скрипте. writeShellApplication добавляет
# шебанг и `set -euo pipefail` и прогоняет shellcheck при сборке,
# поэтому в файле их нет.
#
# runtimeInputs обязателен целиком: хук запускается из user-сервиса
# noctalia, где PATH минимальный, — coreutils и findutils
# оттуда не взять. imagemagick при этом в systemPackages не нужен, он
# приезжает замыканием этой обёртки.
pkgs:
pkgs.writeShellApplication {
  name = "kitty-gradient";
  runtimeInputs = with pkgs; [ imagemagick coreutils findutils procps gawk ];
  text = builtins.readFile ./gradient.sh;
}
