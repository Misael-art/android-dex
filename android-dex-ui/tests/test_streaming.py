from __future__ import annotations

import os
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

import pytest

from android_dex_ui import service as service_module
from android_dex_ui.client import AndroidDexClient, ClientError
from android_dex_ui.paths import socket_path
from android_dex_ui.protocol import RpcFault
from android_dex_ui.service import AndroidDexCore


def _start_server():
    ready = threading.Event()
    holder = {}
    original = service_module.RpcServer.__init__

    def capture(self, *args, **kwargs):
        original(self, *args, **kwargs)
        holder["server"] = self
        ready.set()

    service_module.RpcServer.__init__ = capture
    try:
        thread = threading.Thread(target=service_module.serve, kwargs={"demo": True}, daemon=True)
        thread.start()
        assert ready.wait(5)
    finally:
        service_module.RpcServer.__init__ = original
    path = socket_path()
    deadline = time.monotonic() + 5
    while not path.exists() and time.monotonic() < deadline:
        time.sleep(0.02)
    return holder["server"]


def test_subscribe_streams_events_in_order():
    server = _start_server()
    try:
        client = AndroidDexClient(socket_path())
        received = []

        def consume():
            for event in client.subscribe(after=0, timeout=5):
                received.append(event)
                if len(received) == 3:
                    return

        consumer = threading.Thread(target=consume, daemon=True)
        consumer.start()
        time.sleep(0.2)
        for index in range(3):
            server.core._emit("job.progress", "job", "corr", progress=index)
        consumer.join(5)
        assert [row["progress"] for row in received] == [0, 1, 2]
        assert [row["seq"] for row in received] == [1, 2, 3]
        assert received[0]["event"] == "job.progress"
        assert received[0]["jobId"] == "job"
    finally:
        server.shutdown()


def test_subscribe_is_rejected_through_plain_dispatch():
    core = AndroidDexCore(demo=True)
    with pytest.raises(RpcFault, match="E-RPC-STREAM"):
        core.dispatch("events.subscribe", {})


def test_subscribe_rejects_bad_cursor():
    server = _start_server()
    try:
        client = AndroidDexClient(socket_path())
        with pytest.raises(ClientError) as info:
            next(client.subscribe(after=-1, timeout=5))
        assert info.value.error["code"] == "E-PARAM-AFTER"
    finally:
        server.shutdown()


def test_job_list_returns_recent_jobs_first():
    core = AndroidDexCore(demo=True)
    core._jobs = {
        "a": {"jobId": "a", "createdAt": "2026-01-01T00:00:00Z", "status": "completed"},
        "b": {"jobId": "b", "createdAt": "2026-02-01T00:00:00Z", "status": "failed"},
    }
    assert [row["jobId"] for row in core.dispatch("job.list", {})["jobs"]] == ["b", "a"]
    assert len(core.dispatch("job.list", {"limit": 1})["jobs"]) == 1
    with pytest.raises(RpcFault, match="E-PARAM-LIMIT"):
        core.dispatch("job.list", {"limit": 0})


def test_socket_activation_uses_inherited_fd(tmp_path):
    path = tmp_path / "activated.sock"
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    listener.bind(str(path))
    listener.listen()
    os.set_inheritable(listener.fileno(), True)
    src = Path(__file__).resolve().parents[1] / "src"
    env = {**os.environ, "PYTHONPATH": str(src), "LISTEN_FDS": "1"}
    # dup2 para o fd 3 e exec: o PID do python é o mesmo do shell (LISTEN_PID=$$).
    process = subprocess.Popen(
        [
            "bash",
            "-c",
            f'exec 3<&{listener.fileno()}; LISTEN_PID=$$ exec "$0" -m android_dex_ui.service --demo',
            sys.executable,
        ],
        env=env,
        pass_fds=(listener.fileno(),),
    )
    listener.close()
    try:
        client = AndroidDexClient(path)
        deadline = time.monotonic() + 10
        while True:
            try:
                snapshot = client.call("system.snapshot", timeout=2)
                break
            except ClientError:
                if time.monotonic() > deadline:
                    raise
                time.sleep(0.1)
        assert snapshot["devices"][0]["serial"] == "PIXEL8-DEMO"
        assert not socket_path().exists()
    finally:
        process.terminate()
        process.wait(5)
