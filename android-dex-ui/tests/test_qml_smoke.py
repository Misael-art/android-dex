from __future__ import annotations

import os
import subprocess
import sys

import pytest


@pytest.mark.parametrize("page", range(6))
def test_qml_loads_and_renders_every_page(tmp_path, page):
    screenshot = tmp_path / f"page-{page}.png"
    env = os.environ.copy()
    env["QT_QPA_PLATFORM"] = "offscreen"
    completed = subprocess.run(
        [
            sys.executable,
            "-m",
            "android_dex_ui.main",
            "--demo",
            "--page",
            str(page),
            "--screenshot",
            str(screenshot),
        ],
        env=env,
        timeout=12,
        check=False,
        capture_output=True,
        text=True,
    )
    assert completed.returncode == 0, completed.stderr
    assert screenshot.is_file()
    assert screenshot.stat().st_size > 20_000


@pytest.mark.parametrize("width,height", [(1280, 800), (960, 640)])
def test_home_is_responsive_at_supported_viewports(tmp_path, width, height):
    screenshot = tmp_path / f"home-{width}x{height}.png"
    env = os.environ.copy()
    env["QT_QPA_PLATFORM"] = "offscreen"
    completed = subprocess.run(
        [
            sys.executable,
            "-m",
            "android_dex_ui.main",
            "--demo",
            "--width",
            str(width),
            "--height",
            str(height),
            "--screenshot",
            str(screenshot),
        ],
        env=env,
        timeout=12,
        check=False,
        capture_output=True,
        text=True,
    )
    assert completed.returncode == 0, completed.stderr
    assert screenshot.stat().st_size > 15_000
