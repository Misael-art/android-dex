from __future__ import annotations

import json
import socket
import threading
import time

import pytest

from android_dex_ui import service as service_module
from android_dex_ui.paths import socket_path, state_dir
from android_dex_ui.protocol import RpcFault
from android_dex_ui.service import EVENT_BUFFER, AndroidDexCore


def _demo_plan(core, tmp_path):
    image = tmp_path / "recovery.img"
    image.write_bytes(b"recovery")
    return core.dispatch(
        "maintenance.plan",
        {"serial": "PIXEL8-DEMO", "action": "boot-recovery", "recoveryImage": str(image)},
    )


def _wait_job(core, job_id, timeout=5.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        job = core.dispatch("job.status", {"jobId": job_id})
        if job["status"] not in {"queued", "running"}:
            return job
        time.sleep(0.05)
    raise AssertionError("job não terminou")


def test_plan_is_single_use(tmp_path):
    core = AndroidDexCore(demo=True)
    plan = _demo_plan(core, tmp_path)
    job = core.dispatch("maintenance.apply", {"planId": plan["planId"], "confirmation": "SIM"})
    assert _wait_job(core, job["jobId"])["status"] == "completed"
    with pytest.raises(RpcFault, match="E-PLAN-MISSING"):
        core.dispatch("maintenance.apply", {"planId": plan["planId"], "confirmation": "SIM"})


def test_failed_validation_does_not_consume_plan(tmp_path):
    core = AndroidDexCore(demo=True)
    plan = _demo_plan(core, tmp_path)
    with pytest.raises(RpcFault, match="E-CONFIRMATION"):
        core.dispatch("maintenance.apply", {"planId": plan["planId"], "confirmation": "NAO"})
    job = core.dispatch("maintenance.apply", {"planId": plan["planId"], "confirmation": "SIM"})
    assert job["status"] == "queued"


def test_event_cursor_keeps_growing_past_buffer():
    core = AndroidDexCore(demo=True)
    for index in range(EVENT_BUFFER + 50):
        core._emit("job.progress", "job", "corr", progress=index)
    first = core.dispatch("events.poll", {"after": 0})
    assert first["cursor"] == EVENT_BUFFER + 50
    assert first["truncated"] is True
    assert len(first["events"]) == EVENT_BUFFER
    core._emit("job.completed", "job", "corr")
    second = core.dispatch("events.poll", {"after": first["cursor"]})
    assert [row["event"] for row in second["events"]] == ["job.completed"]
    assert second["truncated"] is False
    assert second["cursor"] == first["cursor"] + 1


def test_stale_cursor_from_previous_daemon_resets():
    core = AndroidDexCore(demo=True)
    core._emit("job.progress", "job", "corr")
    result = core.dispatch("events.poll", {"after": 999})
    assert len(result["events"]) == 1


def test_concurrent_desktop_start_allows_single_session():
    core = AndroidDexCore(demo=True)
    barrier = threading.Barrier(4)
    outcomes: list[str] = []

    def start():
        barrier.wait()
        try:
            core.dispatch("desktop.start", {"serial": "PIXEL8-DEMO", "mode": "auto"})
            outcomes.append("ok")
        except RpcFault as fault:
            outcomes.append(fault.code)

    threads = [threading.Thread(target=start) for _ in range(4)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    assert outcomes.count("ok") == 1
    assert outcomes.count("E-SESSION-ACTIVE") == 3


def test_running_jobs_are_interrupted_on_restart():
    path = state_dir() / "jobs.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"j1": {"jobId": "j1", "status": "running"}}))
    core = AndroidDexCore(demo=True)
    job = core.dispatch("job.status", {"jobId": "j1"})
    assert job["status"] == "interrupted"
    assert job["error"]["code"] == "E-JOB-INTERRUPTED"


def test_cancel_blocks_critical_and_cancels_queued_job(tmp_path):
    core = AndroidDexCore(demo=True)
    plan = _demo_plan(core, tmp_path)
    job = core.dispatch("maintenance.apply", {"planId": plan["planId"], "confirmation": "SIM"})
    with pytest.raises(RpcFault, match="E-JOB-CRITICAL"):
        core.dispatch("maintenance.cancel", {"jobId": job["jobId"]})
    with core._lock:
        core._jobs["c1"] = {"jobId": "c1", "status": "queued", "cancelable": True}
    assert core.dispatch("maintenance.cancel", {"jobId": "c1"}) == {
        "cancelled": True,
        "status": "cancelling",
    }
    core._apply_worker("c1", "corr", {}, "SIM")
    assert core.dispatch("job.status", {"jobId": "c1"})["status"] == "cancelled"


def test_reused_pid_marks_session_finished(monkeypatch):
    core = AndroidDexCore(demo=True)
    import os

    core._sessions["s1"] = {
        "id": "s1",
        "status": "running",
        "startedAt": "2026-01-01T00:00:00Z",
        "pid": os.getpid(),
        "procStart": "not-the-same",
    }
    sessions = core.dispatch("session.list", {})["sessions"]
    assert sessions[0]["status"] == "finished"


def test_failed_stop_does_not_mark_session_stopped(monkeypatch):
    core = AndroidDexCore(demo=False)
    core._sessions["s1"] = {"id": "s1", "status": "running", "startedAt": "x", "pid": 0}
    monkeypatch.setattr(core, "_tool", lambda name: "/bin/false")
    with pytest.raises(RpcFault, match="E-STOP-FAILED"):
        core.dispatch("desktop.stop", {})
    assert core._sessions["s1"]["status"] == "stop-failed"


def test_second_daemon_does_not_steal_socket():
    thread = threading.Thread(target=service_module.serve, kwargs={"demo": True}, daemon=True)
    thread.start()
    path = socket_path()
    deadline = time.monotonic() + 5
    while not path.exists() and time.monotonic() < deadline:
        time.sleep(0.05)
    assert path.exists()
    assert (path.stat().st_mode & 0o777) == 0o600
    with pytest.raises(SystemExit, match="já está em execução"):
        service_module.serve(demo=True)
    probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    probe.connect(str(path))
    probe.close()
