#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ANDROID_DEX_BUILD_DIR:-$ROOT_DIR/build}"
VENV_DIR="$BUILD_DIR/venv"
APPDIR="$BUILD_DIR/Android-DEX.AppDir"
PYTHON_BIN="${PYTHON_BIN:-python3}"
APPIMAGETOOL_BIN="${APPIMAGETOOL_BIN:-$(command -v appimagetool || true)}"

mkdir -p "$BUILD_DIR"
"$PYTHON_BIN" -m venv "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install --upgrade pip
"$VENV_DIR/bin/python" -m pip install 'PySide6-Essentials>=6.8' pyinstaller
"$VENV_DIR/bin/python" -m PyInstaller --clean --noconfirm \
  --distpath "$BUILD_DIR/pyinstaller" \
  --workpath "$BUILD_DIR/pyinstaller-work" \
  "$ROOT_DIR/appimage/android-dex-ui.spec"

rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/lib/android-dex" "$APPDIR/usr/bin"
cp -a "$BUILD_DIR/pyinstaller/android-dex-ui/." "$APPDIR/usr/lib/android-dex/"
cp "$ROOT_DIR/appimage/AppRun" "$APPDIR/AppRun"
cp "$ROOT_DIR/appimage/android-dex-ui.desktop" "$APPDIR/android-dex-ui.desktop"
cp "$ROOT_DIR/src/android_dex_ui/assets/images/android-dex-ui-icon.png" "$APPDIR/android-dex-ui.png"
chmod 0755 "$APPDIR/AppRun" "$APPDIR/usr/lib/android-dex/android-dex-ui"
ln -s ../lib/android-dex/android-dex-ui "$APPDIR/usr/bin/android-dex-ui"

if [ "${1:-}" = "--appdir-only" ]; then
  printf 'AppDir criado em %s\n' "$APPDIR"
  exit 0
fi
if [ -z "$APPIMAGETOOL_BIN" ]; then
  printf 'appimagetool não encontrado. Defina APPIMAGETOOL_BIN ou use --appdir-only.\n' >&2
  exit 2
fi
ARCH="${ARCH:-$(uname -m)}" "$APPIMAGETOOL_BIN" "$APPDIR" "$BUILD_DIR/Android-DEX-$(uname -m).AppImage"
printf 'AppImage criado em %s\n' "$BUILD_DIR/Android-DEX-$(uname -m).AppImage"
