# Перед стартом noctalia: из state-файла выбрасывается всё, кроме текущих
# обоев. Зачем — в home/noctalia.nix, у ExecStartPre.
import json
import os
import sys
import tomllib

state = (os.environ.get("XDG_STATE_HOME")
         or os.path.expanduser("~/.local/state"))
path = os.path.join(state, "noctalia", "settings.toml")

try:
    with open(path, "rb") as f:
        raw = f.read()
except FileNotFoundError:
    sys.exit(0)

try:
    data = tomllib.loads(raw.decode())
except (tomllib.TOMLDecodeError, UnicodeDecodeError):
    data = {}  # битый файл: сохранить в .prev и начать с чистого

# Прошлое содержимое — на случай, если в GUI накручено то, что стоит
# перенести в noctalia.nix. Одна копия, перезаписывается каждый старт.
with open(path + ".prev", "wb") as f:
    f.write(raw)


def value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    return json.dumps(v, ensure_ascii=False)  # строки и массивы строк


out = []
if "config_version" in data:
    out.append(f"config_version = {value(data['config_version'])}")


def table(name, t):
    out.append("")
    out.append(f"[{name}]")
    for k, v in t.items():
        if not isinstance(v, dict):
            out.append(f"{json.dumps(k)} = {value(v)}")


wallpaper = data.get("wallpaper", {})
if isinstance(wallpaper.get("last"), dict):
    table("wallpaper.last", wallpaper["last"])
for mon, t in (wallpaper.get("monitors") or {}).items():
    if isinstance(t, dict):
        table(f"wallpaper.monitors.{json.dumps(mon)}", t)

tmp = path + ".tmp"
with open(tmp, "w") as f:
    f.write("\n".join(out) + "\n")
os.replace(tmp, path)
