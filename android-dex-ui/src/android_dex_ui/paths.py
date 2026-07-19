"""Caminhos XDG e descoberta dos entrypoints do workspace/instalação."""

from __future__ import annotations

import os
import shutil
from pathlib import Path


def project_root() -> Path | None:
    explicit = os.environ.get("ANDROID_DEX_PROJECT_ROOT")
    candidates = [Path(explicit)] if explicit else []
    candidates.append(Path(__file__).resolve().parents[3])
    for candidate in candidates:
        if (candidate / "android-dex-kit/bin/android-dex").is_file():
            return candidate.resolve()
    return None


def runtime_dir() -> Path:
    base = Path(os.environ.get("XDG_RUNTIME_DIR", f"/tmp/android-dex-{os.getuid()}"))
    return base / "android-dex"


def socket_path() -> Path:
    override = os.environ.get("ANDROID_DEX_SOCKET")
    return Path(override) if override else runtime_dir() / "core.sock"


def state_dir() -> Path:
    base = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    return base / "android-dex-ui"


def log_dir() -> Path:
    return state_dir() / "logs"


def find_entrypoint(name: str) -> Path:
    root = project_root()
    if root:
        relative = {
            "android-dex": "android-dex-kit/bin/android-dex",
            "android-dex-connect": "android-dex-kit/bin/android-dex-connect",
            "android-dex-doctor": "android-dex-kit/bin/android-dex-doctor",
            "android-dex-flash": "android-dex-flash/bin/android-dex-flash",
        }.get(name)
        if relative and (root / relative).is_file():
            return (root / relative).resolve()
    located = shutil.which(name)
    if located:
        return Path(located).resolve()
    raise FileNotFoundError(name)
