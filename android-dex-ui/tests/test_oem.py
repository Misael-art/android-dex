from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from android_dex_ui.oem import OEM_FAMILIES, classify

ROOT = Path(__file__).resolve().parents[2]
KIT = ROOT / "android-dex-kit/bin/android-dex"

IDENTITIES = [
    "Samsung Galaxy S24",
    "Google Pixel 8 Pro",
    "Xiaomi 14",
    "Redmi Note 13",
    "POCO F6",
    "motorola edge 50",
    "LENOVO Tab P12",
    "OnePlus 12",
    "OPPO Find X7",
    "realme GT 6",
    "Sony Xperia 1 VI",
    "Nothing Phone 2",
    "",
]


def _kit_profile(identity: str) -> str:
    # Extrai só a função do script do kit e a executa isoladamente.
    source = KIT.read_text(encoding="utf-8")
    start = source.index("normalize_profile_key() {")
    end = source.index("\n}\n", start) + 3
    script = source[start:end] + 'normalize_profile_key "$1"\n'
    return subprocess.run(
        ["bash", "-c", script, "kit", identity], capture_output=True, text=True, check=True
    ).stdout.strip()


@pytest.mark.parametrize("identity", IDENTITIES)
def test_kit_profile_matches_shared_table(identity):
    assert _kit_profile(identity) == classify(identity).desktop_profile


def test_profiles_exist_for_every_desktop_profile():
    for family in OEM_FAMILIES:
        assert (ROOT / "android-dex-kit/profiles" / f"{family.desktop_profile}.env").is_file()


def test_flash_drivers_exist_for_every_family():
    drivers = ROOT / "android-dex-flash/lib/drivers"
    for family in OEM_FAMILIES:
        assert (drivers / f"{family.flash_driver}.sh").is_file(), family.flash_driver
