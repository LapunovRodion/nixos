#!/usr/bin/env bash
# Тянет свежий манифест релиза claude-code (version + checksum'ы по платформам)
# с downloads.claude.ai. Оверлей в modules/common.nix скармливает его
# derivation'у из nixpkgs через .override { manifest = ...; }.
#
#   ./pkgs/update-claude-code-manifest.sh          # latest
#   ./pkgs/update-claude-code-manifest.sh 2.1.280  # конкретная версия
#
# Дальше — обычный rebuild. Когда версия доедет до nixpkgs, оверлей и этот
# скрипт удаляются, остаётся голый ccPkgs.claude-code.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

BASE_URL="https://downloads.claude.ai/claude-code-releases"
VERSION="${1:-$(curl -fsSL "$BASE_URL/latest")}"

curl -fsSL "$BASE_URL/$VERSION/manifest.zst.json" --output claude-code-manifest.json
echo "claude-code -> $VERSION"
