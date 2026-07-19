# -*- mode: python ; coding: utf-8 -*-
from pathlib import Path

project = Path(SPEC).resolve().parents[1]
package = project / "src" / "android_dex_ui"
datas = [
    (str(package / "qml"), "android_dex_ui/qml"),
    (str(package / "assets"), "android_dex_ui/assets"),
]
binaries = []
hiddenimports = []

a = Analysis(
    [str(project / "appimage" / "launcher.py")],
    pathex=[str(project / "src")],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="android-dex-ui",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    name="android-dex-ui",
)
