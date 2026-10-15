# Перекраска приложений под обои — wallpaper.postHook Caelestia CLI.
#
# Шебанга и `set -euo pipefail` нет намеренно: файл вставляется в
# pkgs.writeShellApplication (home/hyprland.nix), а тот дописывает и то,
# и другое, и прогоняет shellcheck при сборке.
#
# Цепочка: `caelestia wallpaper` (лаунчер, Nexus или таймер ротации) →
# схема Caelestia для шелла и рамок Hyprland → этот хук. Окружение даёт
# сам caelestia: WALLPAPER_PATH, SCHEME_NAME, SCHEME_MODE, SCHEME_VARIANT.
#
# Палитру приложениям считает утилита noctalia (`noctalia theme`, разово,
# шелл не запускается): шаблоны написаны под её движок — фильтры
# set_alpha/lighten/set_hue, варианты .light/.dark, — у Caelestia такого нет.
# Вариант схемы берётся у Caelestia, режим — всегда тёмный, как у шелла.
# Генераторы Material You разные, поэтому оттенки — «почти», не бит в бит.
#
# THEME_TEMPLATES подставляет home/hyprland.nix: user.toml (kitty, Claude,
# btop, gtk) и каталоги шаблонов сообщества из home/theme-templates.

# Схема не от обоев (выбрана готовая через `>scheme`) — приложения не трогаем.
[ "${SCHEME_NAME:-}" = dynamic ] || exit 0

# Пути в шаблонах — $XDG_CONFIG_HOME/…; в окружении сервиса их может не быть.
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# Варианты Caelestia → схемы noctalia. У expressive/fidelity/neutral
# аналога нет, для них — content (ближе всего к цветам самой картинки).
case "${SCHEME_VARIANT:-}" in
  tonalspot) scheme=m3-tonal-spot ;;
  fruitsalad) scheme=m3-fruit-salad ;;
  content | rainbow | monochrome) scheme="m3-$SCHEME_VARIANT" ;;
  vibrant) scheme=vibrant ;;
  *) scheme=m3-content ;;
esac

# Каждый template.toml — отдельным вызовом: {{ config_dir }} в хуках
# шаблона указывает на каталог его toml. Упавший шаблон не мешает остальным.
for cfg in "$THEME_TEMPLATES"/user.toml "$THEME_TEMPLATES"/*/template.toml; do
  noctalia theme "$WALLPAPER_PATH" --scheme "$scheme" \
    --default-mode dark -c "$cfg" >/dev/null 2>&1 ||
    echo "theme-sync: $cfg не отрисовался" >&2
done

# Рамки окон читают ~/.config/hypr/scheme/current.lua (его пишет caelestia)
# только при загрузке конфига — см. home/hyprland/colors.lua.
hyprctl reload config-only >/dev/null || true

# Обзор столов читает палитру только при старте (опрос выключен).
systemctl --user try-restart quickshell-overview.service || true
