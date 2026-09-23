"""Tabela única de famílias OEM.

Fonte de verdade para o serviço (driver do android-dex-flash) e espelhada por
`normalize_profile_key` em android-dex-kit/bin/android-dex (perfil desktop).
`tests/test_oem.py` falha se as duas divergirem.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class OemFamily:
    key: str
    patterns: tuple[str, ...]
    flash_driver: str
    desktop_profile: str


# A ordem importa: a primeira família cujo padrão aparece na identidade vence.
OEM_FAMILIES: tuple[OemFamily, ...] = (
    OemFamily("samsung", ("samsung",), "samsung", "samsung"),
    OemFamily("google", ("google", "pixel"), "pixel", "google"),
    OemFamily("xiaomi", ("xiaomi", "redmi", "poco"), "xiaomi", "xiaomi"),
    OemFamily("motorola", ("motorola", "lenovo"), "motorola", "motorola"),
    OemFamily("oneplus", ("oneplus",), "oneplus", "oneplus"),
    OemFamily("oppo", ("oppo", "realme"), "oppo", "oneplus"),
    OemFamily("sony", ("sony",), "sony", "generic"),
)
GENERIC = OemFamily("generic", (), "generic", "generic")


def classify(manufacturer: str = "", model: str = "") -> OemFamily:
    identity = f"{manufacturer} {model}".lower()
    for family in OEM_FAMILIES:
        if any(pattern in identity for pattern in family.patterns):
            return family
    return GENERIC
