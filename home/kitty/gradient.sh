# Градиент фона kitty — post_hook шаблона темы.
#
# Шебанга и `set -euo pipefail` здесь нет намеренно: файл вставляется в
# pkgs.writeShellApplication (home/noctalia.nix), а тот дописывает и то,
# и другое, и прогоняет shellcheck при сборке.
#
# Зачем вообще картинка. Градиента как настройки у kitty нет; единственный
# способ — background_image. Картинка рисуется из тех же цветов палитры,
# что и остальная тема: два hex'а лежат маркерными строками в
# themes/noctalia.conf, который noctalia отрендерила прямо перед вызовом
# этого хука (см. kitty/theme.conf.in).
#
# ПОЧЕМУ ИМЯ ФАЙЛА ВЕРСИОНИРУЕТСЯ ХЕШЕМ. kitty на релоаде (SIGUSR1)
# подменяет фоновую картинку, только если изменилась СТРОКА пути:
#   lib/kitty/kitty/boss.py:989 — if opts.background_image != global_opts.background_image
# Перезапись файла по постоянному пути была бы молча проигнорирована, и
# фон остался бы от прежних обоев. Но background_image принимает glob и
# раскрывает его при разборе конфига (kitty/options/utils.py:876,
# sorted(glob(x))), поэтому новое имя внутри glob'а меняет разобранное
# значение — и картинка перезагружается. В home.nix поэтому стоит
#   background_image ~/.config/kitty/backgrounds/*.png
# Альтернатива — kitten @ set-background-image — потребовала бы
# allow_remote_control, то есть открытый сокет управления. Не нужно.

conf_dir="${XDG_CONFIG_HOME:-$HOME/.config}/kitty"
theme_file="$conf_dir/themes/noctalia.conf"
bg_dir="$conf_dir/backgrounds"

# Строки вида «# noctalia-gradient-top #05060a» — три поля, цвет третьим.
top=$(awk '$2 == "noctalia-gradient-top"    { print $3; exit }' "$theme_file")
bottom=$(awk '$2 == "noctalia-gradient-bottom" { print $3; exit }' "$theme_file")

if [ -z "$top" ] || [ -z "$bottom" ]; then
    echo "kitty-gradient: маркеры градиента не найдены в $theme_file" >&2
    exit 1
fi

hash=$(printf '%s-%s' "$top" "$bottom" | sha256sum | cut -c1-8)
out="$bg_dir/bg-$hash.png"

mkdir -p "$bg_dir"

# ImageMagick кладёт первый цвет наверх — это и есть «темнее сверху».
#
# +noise — не украшение, а дизеринг. Между крайними цветами около
# трёх десятков ступеней 8-битной шкалы (светлота 2→14 %), растянутых
# на всю высоту экрана: без шума видны ровные горизонтальные полосы
# в три десятка пикселей каждая. Раньше их отчасти маскировал подмес
# обоев — окно гасилось до opacity 0.92 и служил случайным дизером;
# прозрачности больше нет, так что вся работа на шуме.
#
# attenuate подобран замером: 0.03 даёт разброс около ±1/255, ровно на
# один шаг квантования (при 0.35 — уже ±24/255, то есть заметная крупа).
# Если полосы всё же проступят — 0.05.
if [ ! -f "$out" ]; then
    magick -size 256x512 "gradient:$top-$bottom" \
        -attenuate 0.03 +noise Gaussian -depth 8 "$out"
fi

# Прежние картинки — вон: glob в background_image раскрывается в
# отсортированный список, и лишние файлы просто заняли бы VRAM (kitty
# держит их все, показывая первый).
#
# bg-seed.png не трогаем. Это затравка от home-manager (см. home.nix):
# симлинк на /nix/store, который держит glob непустым, пока тема ещё ни
# разу не применялась. -type f её и так не поймает, но лишнее условие
# страхует на случай, если home-manager однажды начнёт копировать файл
# вместо симлинка.
find "$bg_dir" -maxdepth 1 -type f -name 'bg-*.png' \
    ! -name "bg-$hash.png" ! -name 'bg-seed.png' -delete

# Перечитать конфиг в уже открытых окнах. Именно этого шага не хватало
# встроенному шаблону: его apply.sh падал раньше, чем доходил до сигнала.
pkill -USR1 -x kitty >/dev/null 2>&1 || true
