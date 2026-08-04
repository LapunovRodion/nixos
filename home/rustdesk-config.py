#!/usr/bin/env python3
# Проставить в RustDesk2.toml адреса своего сервера, не трогая остальное.
#
# Зачем скрипт, а не xdg.configFile (симлинк в /nix/store): RustDesk держит
# в этом же файле свои обычные настройки (тема, вид списка, размеры окна) и
# перезаписывает его целиком — read-only файл он записать не смог бы.
# Поэтому файл остаётся обычным, а здесь только выставляются наши ключи.
#
# Вызывается из home.nix (home.activation), путь к файлу — единственный
# аргумент. Никогда не завершается с ошибкой: сломанная активация не должна
# ронять весь nixos-rebuild switch из-за настроек одной программы.

import json
import os
import sys
import tomllib

# Свой сервер: hbbs/hbbr на домашней машине (/opt/rustdesk), слушает только
# на Tailscale-IP. key — публичный ключ сервера (data/id_ed25519.pub); без
# него hbbs, запущенный с флагом `-k _`, соединение не примет.
WANT = {
    "custom-rendezvous-server": "100.114.48.114",
    "relay-server": "100.114.48.114:21117",
    "key": "+IZuAer2eXEvMrrZcBd6AGKzKbGUwVrEqGZe9p+jIJo=",
}


def dump(value):
    """Значение → TOML. json.dumps даёт корректную basic string с экранированием."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        return "[" + ", ".join(dump(item) for item in value) + "]"
    return json.dumps(str(value))


def render(data, prefix=""):
    """Обратная сериализация: сначала скаляры уровня, потом вложенные таблицы."""
    lines = []
    tables = {}
    for key, value in data.items():
        if isinstance(value, dict):
            tables[key] = value
        else:
            lines.append(f"{key} = {dump(value)}")
    for name, table in tables.items():
        full = f"{prefix}{name}"
        lines.append("")
        lines.append(f"[{full}]")
        lines.extend(render(table, prefix=f"{full}."))
    return lines


def main(path):
    data = {}
    if os.path.exists(path):
        with open(path, "rb") as fh:
            try:
                data = tomllib.load(fh)
            except tomllib.TOMLDecodeError as exc:
                # Разбирать нечего — отодвигаем файл и пишем свой с нуля,
                # чтобы не затереть чужие данные молча.
                os.replace(path, path + ".broken")
                print(f"rustdesk: {path} не разбирается ({exc}), сохранён как .broken")

    options = data.get("options")
    if not isinstance(options, dict):
        options = {}
        data["options"] = options

    if all(options.get(key) == value for key, value in WANT.items()):
        return  # уже настроено, файл не трогаем

    options.update(WANT)

    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    tmp = path + ".new"
    with open(tmp, "w") as fh:
        fh.write("\n".join(render(data)).lstrip("\n") + "\n")
    os.replace(tmp, path)  # атомарно: RustDesk не увидит файл наполовину
    print(f"rustdesk: прописан свой ID/relay-сервер в {path}")


if __name__ == "__main__":
    try:
        main(sys.argv[1])
    except Exception as exc:  # noqa: BLE001 — см. шапку: активацию не роняем
        print(f"rustdesk: настройки не применены ({exc})", file=sys.stderr)
