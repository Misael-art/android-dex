#!/usr/bin/env bash
set -euo pipefail

APPIMAGE="${1:?uso: smoke-appimage.sh CAMINHO.AppImage}"
SCREENSHOT="${2:-/tmp/android-dex-appimage-smoke.png}"
QT_QPA_PLATFORM=offscreen "$APPIMAGE" --appimage-extract-and-run --demo --screenshot "$SCREENSHOT"
test -s "$SCREENSHOT"
printf 'Smoke AppImage concluído: %s\n' "$SCREENSHOT"
