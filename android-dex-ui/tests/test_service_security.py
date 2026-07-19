from __future__ import annotations

import os
import stat

import pytest

from android_dex_ui.protocol import RpcFault
from android_dex_ui.service import AndroidDexCore


def test_method_allowlist_rejects_arbitrary_commands():
    core = AndroidDexCore(demo=True)
    with pytest.raises(RpcFault, match="E-RPC-NOT-ALLOWED"):
        core.dispatch("process.run", {"command": "rm", "args": ["-rf", "/"]})


def test_demo_snapshot_and_dex_fallback_contract():
    core = AndroidDexCore(demo=True)
    snapshot = core.dispatch("system.snapshot", {})
    assert snapshot["format"] == "android-dex.machine.v1"
    assert snapshot["devices"][0]["model"] == "Pixel 8 Pro"
    plan = core.dispatch("desktop.plan", {"serial": "PIXEL8-DEMO", "mode": "auto"})
    assert plan["runtimeMode"] == "dex"
    assert plan["fallback"] == "mirror"


def test_snapshot_stays_available_when_adb_is_missing(monkeypatch):
    core = AndroidDexCore(demo=False)

    def missing(_params):
        raise RpcFault("E-ADB-MISSING", "ADB não instalado", "Execute o setup.", True)

    monkeypatch.setattr(core, "device_list", missing)
    snapshot = core.dispatch("system.snapshot", {})
    assert snapshot["devices"] == []
    assert snapshot["deviceError"]["code"] == "E-ADB-MISSING"


def test_multiple_devices_require_explicit_serial(monkeypatch):
    core = AndroidDexCore(demo=True)
    first = core._demo_devices()[0]
    second = {**first, "serial": "SECOND-DEMO", "model": "Segundo"}
    monkeypatch.setattr(core, "_demo_devices", lambda: [first, second])
    with pytest.raises(RpcFault, match="E-DEVICE-AMBIGUOUS"):
        core.dispatch("desktop.plan", {"mode": "auto"})


def test_second_desktop_session_is_rejected():
    core = AndroidDexCore(demo=True)
    core.dispatch("desktop.start", {"serial": "PIXEL8-DEMO", "mode": "auto"})
    with pytest.raises(RpcFault, match="E-SESSION-ACTIVE"):
        core.dispatch("desktop.start", {"serial": "PIXEL8-DEMO", "mode": "mirror"})


def test_plan_binds_hash_and_detects_changed_artifact(tmp_path):
    image = tmp_path / "recovery.img"
    image.write_bytes(b"first")
    core = AndroidDexCore(demo=True)
    plan = core.dispatch(
        "maintenance.plan",
        {"serial": "PIXEL8-DEMO", "action": "boot-recovery", "recoveryImage": str(image)},
    )
    assert plan["commitAllowed"] is True
    assert plan["requiredConfirmation"] == "SIM"
    assert plan["bindings"][0]["size"] == 5
    image.write_bytes(b"changed")
    with pytest.raises(RpcFault, match="E-ARTIFACT-CHANGED"):
        core.dispatch(
            "maintenance.apply", {"planId": plan["planId"], "confirmation": "SIM"}
        )


def test_symlink_artifact_is_rejected(tmp_path):
    image = tmp_path / "real.img"
    image.write_bytes(b"image")
    link = tmp_path / "link.img"
    link.symlink_to(image)
    core = AndroidDexCore(demo=True)
    with pytest.raises(RpcFault, match="E-PATH-SYMLINK"):
        core.dispatch(
            "maintenance.plan",
            {"serial": "PIXEL8-DEMO", "action": "boot-recovery", "recoveryImage": str(link)},
        )


def test_samsung_requires_permanent_phrase_and_stays_guided(monkeypatch):
    core = AndroidDexCore(demo=True)
    samsung = {
        **core._demo_devices()[0],
        "serial": "SAMSUNG-DEMO",
        "manufacturer": "Samsung",
        "model": "Galaxy S24",
    }
    monkeypatch.setattr(core, "_demo_devices", lambda: [samsung])
    plan = core.dispatch(
        "maintenance.plan", {"serial": "SAMSUNG-DEMO", "action": "unlock"}
    )
    assert plan["requiredConfirmation"] == "KNOX PERMANENTE"
    assert plan["commitAllowed"] is False
    with pytest.raises(RpcFault, match="E-COMMIT-UNSUPPORTED"):
        core.dispatch(
            "maintenance.apply",
            {"planId": plan["planId"], "confirmation": "KNOX PERMANENTE"},
        )


def test_low_battery_is_rechecked_before_apply(tmp_path, monkeypatch):
    image = tmp_path / "recovery.img"
    image.write_bytes(b"recovery")
    core = AndroidDexCore(demo=True)
    low_battery = {**core._demo_devices()[0], "battery": 12}
    monkeypatch.setattr(core, "_demo_devices", lambda: [low_battery])
    plan = core.dispatch(
        "maintenance.plan",
        {"serial": "PIXEL8-DEMO", "action": "boot-recovery", "recoveryImage": str(image)},
    )
    with pytest.raises(RpcFault, match="E-BATTERY-LOW"):
        core.dispatch("maintenance.apply", {"planId": plan["planId"], "confirmation": "SIM"})


def test_private_state_permissions(tmp_path):
    core = AndroidDexCore(demo=True)
    plan = core.dispatch("maintenance.plan", {"serial": "PIXEL8-DEMO", "action": "unlock"})
    plans_dir = tmp_path / "state" / "android-dex-ui" / "plans"
    plan_file = plans_dir / f"{plan['planId']}.json"
    assert stat.S_IMODE(plans_dir.stat().st_mode) == 0o700
    assert stat.S_IMODE(plan_file.stat().st_mode) == 0o600
    persisted = plan_file.read_text(encoding="utf-8").lower()
    assert '"confirmation":' not in persisted
    assert '"requiredconfirmation":"sim"' in persisted
