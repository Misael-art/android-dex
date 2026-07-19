from __future__ import annotations

import os
import stat
import subprocess
import sys
import time

from android_dex_ui.client import AndroidDexClient


def test_socket_mode_and_roundtrip(tmp_path):
    socket_file = tmp_path / "private" / "core.sock"
    env = os.environ.copy()
    env["ANDROID_DEX_SOCKET"] = str(socket_file)
    process = subprocess.Popen(
        [sys.executable, "-m", "android_dex_ui.service", "--demo"], env=env
    )
    try:
        deadline = time.monotonic() + 5
        while not socket_file.exists() and time.monotonic() < deadline:
            time.sleep(0.04)
        assert socket_file.exists()
        assert stat.S_IMODE(socket_file.parent.stat().st_mode) == 0o700
        assert stat.S_IMODE(socket_file.stat().st_mode) == 0o600
        snapshot = AndroidDexClient(socket_file).call("system.snapshot")
        assert snapshot["demo"] is True
    finally:
        process.terminate()
        process.wait(timeout=4)
