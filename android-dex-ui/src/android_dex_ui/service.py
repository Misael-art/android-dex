"""Serviço local Android-DEX: JSON-RPC, allowlist e planos vinculados."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import secrets
import shutil
import signal
import socket
import socketserver
import struct
import subprocess
import threading
import time
import uuid
from pathlib import Path
from typing import Any, Callable

from .paths import find_entrypoint, log_dir, socket_path, state_dir
from .protocol import MACHINE_FORMAT, RpcFault, failure, parse_request, success
from .runner import run_checked
from .state import ensure_private_dir, read_json, write_json

PLAN_TTL_SECONDS = 600
SERIAL_PATTERN = re.compile(r"^[A-Za-z0-9_.:-]{1,160}$")
ENDPOINT_PATTERN = re.compile(
    r"^(?:[A-Za-z0-9.-]+|\[[0-9A-Fa-f:]+\]):(?:[1-9][0-9]{0,4})$"
)
DESTRUCTIVE_ACTIONS = {
    "unlock",
    "root",
    "flash-firmware",
    "restore-boot",
    "boot-recovery",
}
COMMIT_POLICY = {
    "pixel": {"unlock", "boot-recovery"},
    "motorola": {"unlock"},
}


def _now() -> float:
    return time.time()


def _utc_text(timestamp: float | None = None) -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(timestamp or _now()))


class AndroidDexCore:
    def __init__(self, *, demo: bool = False) -> None:
        self.demo = demo
        self._lock = threading.RLock()
        self._jobs_path = state_dir() / "jobs.json"
        self._sessions_path = state_dir() / "sessions.json"
        self._plans_dir = state_dir() / "plans"
        self._events: list[dict[str, Any]] = []
        self._jobs: dict[str, dict[str, Any]] = read_json(self._jobs_path, {})
        self._sessions: dict[str, dict[str, Any]] = read_json(self._sessions_path, {})
        ensure_private_dir(self._plans_dir)
        ensure_private_dir(log_dir())
        self.methods: dict[str, Callable[[dict[str, Any]], Any]] = {
            "system.snapshot": self.system_snapshot,
            "device.list": self.device_list,
            "desktop.plan": self.desktop_plan,
            "desktop.start": self.desktop_start,
            "desktop.stop": self.desktop_stop,
            "wifi.discover": self.wifi_discover,
            "wifi.pair": self.wifi_pair,
            "wifi.connect": self.wifi_connect,
            "session.list": self.session_list,
            "doctor.run": self.doctor_run,
            "tweaks.restore": self.tweaks_restore,
            "maintenance.capabilities": self.maintenance_capabilities,
            "firmware.verify": self.firmware_verify,
            "firmware.checkRollback": self.firmware_check_rollback,
            "firmware.backupBoot": self.firmware_backup_boot,
            "firmware.extractPayload": self.firmware_extract_payload,
            "maintenance.plan": self.maintenance_plan,
            "maintenance.apply": self.maintenance_apply,
            "maintenance.cancel": self.maintenance_cancel,
            "job.status": self.job_status,
            "events.poll": self.events_poll,
        }

    def dispatch(self, method: str, params: dict[str, Any]) -> Any:
        handler = self.methods.get(method)
        if handler is None:
            raise RpcFault(
                "E-RPC-NOT-ALLOWED",
                "Ação não permitida",
                f"O método {method!r} não pertence à allowlist.",
            )
        return handler(params)

    def _emit(self, name: str, job_id: str, correlation_id: str, **data: Any) -> None:
        with self._lock:
            self._events.append(
                {
                    "event": name,
                    "jobId": job_id,
                    "correlationId": correlation_id,
                    "timestamp": _utc_text(),
                    **data,
                }
            )
            self._events = self._events[-200:]

    def events_poll(self, params: dict[str, Any]) -> dict[str, Any]:
        after = params.get("after", 0)
        if not isinstance(after, int) or after < 0:
            raise RpcFault("E-PARAM-AFTER", "Cursor inválido", "after deve ser inteiro.")
        with self._lock:
            return {"cursor": len(self._events), "events": self._events[after:]}

    def _tool(self, name: str) -> str:
        try:
            return str(find_entrypoint(name))
        except FileNotFoundError as exc:
            raise RpcFault(
                "E-TOOL-MISSING",
                "Componente ausente",
                f"Não encontrei {name}. Execute android-dex-setup.",
                True,
                ("Abrir diagnóstico",),
            ) from exc

    def _adb(self) -> str:
        located = shutil.which("adb")
        if not located:
            raise RpcFault(
                "E-ADB-MISSING",
                "ADB não instalado",
                "Instale Android platform-tools pelo assistente de configuração.",
                True,
                ("Executar configuração",),
            )
        return located

    def _demo_devices(self) -> list[dict[str, Any]]:
        return [
            {
                "serial": "PIXEL8-DEMO",
                "state": "device",
                "transport": "USB",
                "model": "Pixel 8 Pro",
                "manufacturer": "Google",
                "device": "husky",
                "sdk": "35",
                "android": "15",
                "battery": 87,
                "desktopCapable": True,
                "authorized": True,
            }
        ]

    def device_list(self, _params: dict[str, Any]) -> dict[str, Any]:
        if self.demo:
            return {"format": MACHINE_FORMAT, "devices": self._demo_devices()}
        result = run_checked([self._adb(), "devices", "-l"], timeout=12)
        devices: list[dict[str, Any]] = []
        for line in result.stdout.splitlines()[1:]:
            fields = line.split()
            if len(fields) < 2:
                continue
            serial, state = fields[0], fields[1]
            details = {
                key: value
                for item in fields[2:]
                if ":" in item
                for key, value in [item.split(":", 1)]
            }
            row: dict[str, Any] = {
                "serial": serial,
                "state": state,
                "transport": "Wi-Fi" if re.search(r":\d+$", serial) else "USB",
                "model": details.get("model", "").replace("_", " "),
                "manufacturer": "",
                "device": details.get("device", ""),
                "sdk": "",
                "android": "",
                "battery": None,
                "desktopCapable": False,
                "authorized": state == "device",
            }
            if state == "device":
                props = self._device_properties(serial)
                row.update(props)
            devices.append(row)
        return {"format": MACHINE_FORMAT, "devices": devices}

    def _device_properties(self, serial: str) -> dict[str, Any]:
        keys = {
            "manufacturer": "ro.product.manufacturer",
            "model": "ro.product.model",
            "device": "ro.product.device",
            "sdk": "ro.build.version.sdk",
            "android": "ro.build.version.release",
            "fingerprint": "ro.build.fingerprint",
            "securityPatch": "ro.build.version.security_patch",
        }
        values: dict[str, Any] = {}
        for output_key, prop in keys.items():
            result = run_checked(
                [self._adb(), "-s", serial, "shell", "getprop", prop],
                timeout=8,
                allow_failure=True,
            )
            values[output_key] = result.stdout.strip()
        battery = run_checked(
            [self._adb(), "-s", serial, "shell", "dumpsys", "battery"],
            timeout=8,
            allow_failure=True,
        )
        match = re.search(r"^\s*level:\s*(\d+)", battery.stdout, re.MULTILINE)
        values["battery"] = int(match.group(1)) if match else None
        secondary = run_checked(
            [
                self._adb(),
                "-s",
                serial,
                "shell",
                "cmd",
                "package",
                "has-feature",
                "android.software.activities_on_secondary_displays",
            ],
            timeout=8,
            allow_failure=True,
        )
        manufacturer = str(values.get("manufacturer", "")).lower()
        values["desktopCapable"] = secondary.stdout.strip() == "true" or "samsung" in manufacturer
        return values

    def _selected_device(self, params: dict[str, Any]) -> dict[str, Any]:
        devices = [
            item
            for item in self.device_list({})["devices"]
            if item["state"] == "device" and item["authorized"]
        ]
        serial = params.get("serial", "")
        if serial:
            if not isinstance(serial, str) or not SERIAL_PATTERN.fullmatch(serial):
                raise RpcFault("E-DEVICE-SERIAL", "Serial inválido", "Formato de serial recusado.")
            matches = [item for item in devices if item["serial"] == serial]
            if len(matches) != 1:
                raise RpcFault(
                    "E-DEVICE-OFFLINE",
                    "Aparelho indisponível",
                    f"{serial} não está online e autorizado.",
                    True,
                    ("Atualizar dispositivos",),
                )
            return matches[0]
        if len(devices) != 1:
            raise RpcFault(
                "E-DEVICE-AMBIGUOUS",
                "Escolha um aparelho",
                "É necessário haver exatamente um aparelho ou informar o serial.",
                True,
                ("Abrir dispositivos",),
            )
        return devices[0]

    def system_snapshot(self, _params: dict[str, Any]) -> dict[str, Any]:
        snapshot: dict[str, Any] = {
            "format": MACHINE_FORMAT,
            "timestamp": _utc_text(),
            "demo": self.demo,
            "tools": {
                name: bool(shutil.which(name))
                for name in ("adb", "fastboot", "scrcpy", "heimdall", "openssl")
            },
            "sessions": self.session_list({})["sessions"],
            "jobs": list(self._jobs.values()),
        }
        try:
            snapshot["devices"] = self.device_list({})["devices"]
        except RpcFault as fault:
            # A tela inicial continua útil quando a máquina ainda não possui ADB.
            snapshot["devices"] = []
            snapshot["deviceError"] = fault.to_object()
        return snapshot

    def desktop_plan(self, params: dict[str, Any]) -> dict[str, Any]:
        device = self._selected_device(params)
        mode = params.get("mode", "auto")
        if mode not in {"auto", "dex", "mirror"}:
            raise RpcFault("E-DESKTOP-MODE", "Modo inválido", "Use auto, dex ou mirror.")
        runtime_mode = mode
        if mode == "auto":
            runtime_mode = "dex" if device.get("desktopCapable") else "mirror"
        return {
            "planId": uuid.uuid4().hex,
            "device": device,
            "requestedMode": mode,
            "runtimeMode": runtime_mode,
            "fallback": "mirror" if mode == "auto" else None,
            "changes": ["Iniciar scrcpy no aparelho selecionado"],
            "reversible": True,
        }

    def desktop_start(self, params: dict[str, Any]) -> dict[str, Any]:
        plan = self.desktop_plan(params)
        active = [
            session
            for session in self.session_list({})["sessions"]
            if session.get("status") == "running"
        ]
        if active:
            raise RpcFault(
                "E-SESSION-ACTIVE",
                "Já existe uma sessão em execução",
                "Encerre a sessão atual antes de iniciar outra para preservar a restauração exata dos ajustes.",
                True,
                ("Abrir sessões",),
            )
        if self.demo:
            session = {
                "id": uuid.uuid4().hex,
                "serial": plan["device"]["serial"],
                "mode": plan["runtimeMode"],
                "status": "running",
                "startedAt": _utc_text(),
                "pid": 0,
                "demo": True,
            }
            self._sessions[session["id"]] = session
            write_json(self._sessions_path, self._sessions)
            return session
        command = [self._tool("android-dex"), "--device", plan["device"]["serial"]]
        if plan["requestedMode"] == "dex":
            command.append("--dex")
        elif plan["requestedMode"] == "mirror":
            command.append("--mirror")
        logfile = log_dir() / f"desktop-{int(_now())}.log"
        handle = logfile.open("ab", buffering=0)
        try:
            process = subprocess.Popen(
                command,
                stdin=subprocess.DEVNULL,
                stdout=handle,
                stderr=subprocess.STDOUT,
                shell=False,
                start_new_session=True,
            )
        finally:
            handle.close()
        session = {
            "id": uuid.uuid4().hex,
            "serial": plan["device"]["serial"],
            "mode": plan["runtimeMode"],
            "status": "running",
            "startedAt": _utc_text(),
            "pid": process.pid,
            "log": str(logfile),
        }
        self._sessions[session["id"]] = session
        write_json(self._sessions_path, self._sessions)
        self._emit("session.changed", session["id"], session["id"], session=session)
        return session

    def desktop_stop(self, _params: dict[str, Any]) -> dict[str, Any]:
        if not self.demo:
            run_checked([self._tool("android-dex"), "--stop"], timeout=20, allow_failure=True)
        for session in self._sessions.values():
            if session.get("status") == "running":
                session["status"] = "stopped"
                session["stoppedAt"] = _utc_text()
        write_json(self._sessions_path, self._sessions)
        return {"stopped": True, "sessions": list(self._sessions.values())}

    def session_list(self, _params: dict[str, Any]) -> dict[str, Any]:
        changed = False
        for session in self._sessions.values():
            pid = int(session.get("pid", 0) or 0)
            if session.get("status") == "running" and pid > 0:
                try:
                    os.kill(pid, 0)
                except ProcessLookupError:
                    session["status"] = "finished"
                    session["finishedAt"] = _utc_text()
                    changed = True
                except PermissionError:
                    session["status"] = "unknown"
        if changed:
            write_json(self._sessions_path, self._sessions)
        return {"sessions": sorted(self._sessions.values(), key=lambda row: row["startedAt"], reverse=True)}

    def wifi_discover(self, _params: dict[str, Any]) -> dict[str, Any]:
        if self.demo:
            return {"endpoints": ["192.168.1.24:37123"], "output": "Endpoint demo"}
        result = run_checked([self._tool("android-dex-connect"), "--discover"], timeout=20)
        endpoints = re.findall(r"(?<!\w)(?:\d{1,3}\.){3}\d{1,3}:\d{1,5}", result.stdout)
        return {"endpoints": sorted(set(endpoints)), "output": result.stdout.strip()}

    def wifi_connect(self, params: dict[str, Any]) -> dict[str, Any]:
        endpoint = self._endpoint(params.get("endpoint"))
        if self.demo:
            return {"connected": True, "endpoint": endpoint}
        result = run_checked([self._adb(), "connect", endpoint], timeout=20)
        if "connected" not in result.stdout.lower():
            raise RpcFault("E-WIFI-CONNECT", "Conexão Wi-Fi falhou", result.stdout.strip(), True)
        return {"connected": True, "endpoint": endpoint, "output": result.stdout.strip()}

    def wifi_pair(self, params: dict[str, Any]) -> dict[str, Any]:
        endpoint = self._endpoint(params.get("endpoint"))
        code = params.get("code")
        if not isinstance(code, str) or not re.fullmatch(r"\d{6}", code):
            raise RpcFault("E-WIFI-CODE", "Código inválido", "Informe exatamente 6 dígitos.")
        if self.demo:
            return {"paired": True, "endpoint": endpoint}
        result = run_checked(
            [self._tool("android-dex-connect"), endpoint],
            input_text=f"{code}\n",
            timeout=35,
        )
        return {"paired": True, "endpoint": endpoint, "output": result.stdout.strip()}

    def _endpoint(self, value: Any) -> str:
        if not isinstance(value, str) or not ENDPOINT_PATTERN.fullmatch(value):
            raise RpcFault("E-WIFI-ENDPOINT", "Endereço inválido", "Use IP:PORTA.")
        port = int(value.rsplit(":", 1)[1])
        if port > 65535:
            raise RpcFault("E-WIFI-ENDPOINT", "Porta inválida", "A porta máxima é 65535.")
        return value

    def doctor_run(self, params: dict[str, Any]) -> dict[str, Any]:
        device = self._selected_device(params)
        if self.demo:
            return {
                "serial": device["serial"],
                "status": "warning",
                "output": "ADB OK\nscrcpy OK\nUSB autorizado\nModo desktop confirmado",
            }
        result = run_checked(
            [self._tool("android-dex-doctor"), "--device", device["serial"]],
            timeout=35,
            allow_failure=True,
        )
        return {
            "serial": device["serial"],
            "status": "ok" if result.returncode == 0 else "warning",
            "returncode": result.returncode,
            "output": (result.stdout + result.stderr).strip(),
        }

    def tweaks_restore(self, params: dict[str, Any]) -> dict[str, Any]:
        device = self._selected_device(params)
        if not self.demo:
            run_checked(
                [self._tool("android-dex"), "--device", device["serial"], "--restore-tweaks"],
                timeout=30,
            )
        return {"restored": True, "serial": device["serial"]}

    def maintenance_capabilities(self, params: dict[str, Any]) -> dict[str, Any]:
        device = self._selected_device(params)
        oem = self._oem(device)
        if self.demo:
            output = "Pixel/AOSP: unlock e recovery temporário disponíveis; firmware persistente permanece guiado."
        else:
            result = run_checked(
                [self._tool("android-dex-flash"), "--model", device["model"], "caps"],
                timeout=30,
                allow_failure=True,
            )
            output = (result.stdout + result.stderr).strip()
        return {
            "device": device,
            "oem": oem,
            "commitActions": sorted(COMMIT_POLICY.get(oem, set())),
            "output": output,
        }

    def firmware_verify(self, params: dict[str, Any]) -> dict[str, Any]:
        return self._firmware_readonly("verify-firmware", params, "firmwarePath")

    def firmware_check_rollback(self, params: dict[str, Any]) -> dict[str, Any]:
        return self._firmware_readonly("check-rollback", params, "firmwarePath")

    def firmware_backup_boot(self, params: dict[str, Any]) -> dict[str, Any]:
        device = self._selected_device(params)
        env = {"FLASH_DEVICE_SERIAL": device["serial"]}
        partition = params.get("partition", "boot")
        if partition not in {"boot", "init_boot"}:
            raise RpcFault("E-BOOT-PARTITION", "Partição inválida", "Use boot ou init_boot.")
        env["BOOT_PARTITION"] = partition
        if self.demo:
            return {"created": True, "output": "Backup demo validado com SHA-256."}
        result = run_checked([self._tool("android-dex-flash"), "backup-boot"], env=env, timeout=180)
        return {"created": True, "output": (result.stdout + result.stderr).strip()}

    def firmware_extract_payload(self, params: dict[str, Any]) -> dict[str, Any]:
        payload = self._file(params.get("payloadPath"))
        output = self._output_dir(params.get("outputPath"))
        if self.demo:
            return {"extracted": True, "outputPath": str(output), "output": "Extração demo."}
        result = run_checked(
            [self._tool("android-dex-flash"), "extract-payload", payload, output],
            timeout=900,
        )
        return {"extracted": True, "outputPath": str(output), "output": (result.stdout + result.stderr).strip()}

    def _firmware_readonly(
        self, command: str, params: dict[str, Any], path_key: str
    ) -> dict[str, Any]:
        device = self._selected_device(params)
        path = self._existing_path(params.get(path_key))
        if self.demo:
            return {"verified": True, "command": command, "output": "Validação demo concluída."}
        result = run_checked(
            [self._tool("android-dex-flash"), command, path],
            env={"FLASH_DEVICE_SERIAL": device["serial"]},
            timeout=180,
        )
        return {"verified": True, "command": command, "output": (result.stdout + result.stderr).strip()}

    def maintenance_plan(self, params: dict[str, Any]) -> dict[str, Any]:
        action = params.get("action")
        if action not in DESTRUCTIVE_ACTIONS:
            raise RpcFault("E-MAINT-ACTION", "Ação inválida", "Ação destrutiva fora da allowlist.")
        device = self._selected_device(params)
        oem = self._oem(device)
        env, path_args, bindings = self._maintenance_inputs(action, params)
        required = "KNOX PERMANENTE" if oem == "samsung" else "SIM"
        commit_allowed = action in COMMIT_POLICY.get(oem, set())
        preview = self._preview(action, device, env, path_args, required)
        plan_id = secrets.token_urlsafe(18)
        created = _now()
        plan = {
            "format": "android-dex.maintenance-plan.v1",
            "planId": plan_id,
            "createdAt": _utc_text(created),
            "expiresAt": created + PLAN_TTL_SECONDS,
            "action": action,
            "serial": device["serial"],
            "model": device.get("model", ""),
            "device": device.get("device", ""),
            "fingerprint": device.get("fingerprint", ""),
            "oem": oem,
            "requiredConfirmation": required,
            "commitAllowed": commit_allowed,
            "bindings": bindings,
            "environment": env,
            "pathArgs": [str(path) for path in path_args],
            "preview": preview,
        }
        write_json(self._plans_dir / f"{plan_id}.json", plan)
        return {key: value for key, value in plan.items() if key != "environment"}

    def _preview(
        self,
        action: str,
        device: dict[str, Any],
        env: dict[str, str],
        path_args: list[Path],
        required: str,
    ) -> str:
        if self.demo:
            return (
                f"Aparelho: {device['model']} ({device['serial']})\n"
                f"Ação: {action}\nDry-run: nenhuma partição será gravada."
            )
        if self._oem(device) == "samsung" and action == "unlock":
            return (
                "Samsung exige confirmação física no aparelho. O Knox e-fuse é permanente.\n"
                "Esta ação permanece somente guiada e não aceita commit."
            )
        argv = [
            self._tool("android-dex-flash"),
            "--model",
            str(device["model"]),
            action,
            *path_args,
        ]
        input_text = f"{required}\n" if required == "KNOX PERMANENTE" else None
        result = run_checked(
            argv,
            input_text=input_text,
            env={**env, "FLASH_DEVICE_SERIAL": str(device["serial"])},
            timeout=90,
            allow_failure=True,
        )
        return (result.stdout + result.stderr).strip()[-12000:]

    def maintenance_apply(self, params: dict[str, Any]) -> dict[str, Any]:
        plan_id = params.get("planId")
        confirmation = params.get("confirmation")
        if not isinstance(plan_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{8,80}", plan_id):
            raise RpcFault("E-PLAN-ID", "Plano inválido", "Identificador de plano recusado.")
        plan_path = self._plans_dir / f"{plan_id}.json"
        plan = read_json(plan_path, None)
        if not isinstance(plan, dict):
            raise RpcFault("E-PLAN-MISSING", "Plano não encontrado", "Crie uma nova prévia.")
        if _now() > float(plan.get("expiresAt", 0)):
            raise RpcFault("E-PLAN-EXPIRED", "Plano expirado", "Crie uma nova prévia.", True)
        if confirmation != plan.get("requiredConfirmation"):
            raise RpcFault("E-CONFIRMATION", "Confirmação não confere", "A ação foi bloqueada.")
        action = plan.get("action")
        if action not in DESTRUCTIVE_ACTIONS:
            raise RpcFault("E-PLAN-ACTION", "Plano inválido", "A ação do plano foi recusada.")
        if not plan.get("commitAllowed"):
            raise RpcFault(
                "E-COMMIT-UNSUPPORTED",
                "Execução automática indisponível",
                "O driver mantém esta ação somente guiada.",
                False,
            )
        current = self._selected_device({"serial": plan["serial"]})
        if (
            current.get("model") != plan.get("model")
            or current.get("device") != plan.get("device")
            or current.get("fingerprint", "") != plan.get("fingerprint", "")
        ):
            raise RpcFault(
                "E-PLAN-DEVICE-CHANGED",
                "Identidade do aparelho mudou",
                "A prévia não pertence ao estado atual. Crie outro plano.",
            )
        current_oem = self._oem(current)
        if (
            plan.get("oem") != current_oem
            or action not in COMMIT_POLICY.get(current_oem, set())
        ):
            raise RpcFault(
                "E-PLAN-POLICY",
                "Política de execução mudou",
                "O driver atual não autoriza executar esta ação automaticamente.",
            )
        battery = current.get("battery")
        if isinstance(battery, int) and battery < 20:
            raise RpcFault(
                "E-BATTERY-LOW",
                "Bateria insuficiente",
                f"O aparelho está com {battery}%. Carregue ao menos até 20% antes de continuar.",
                True,
                ("Recarregar aparelho", "Criar nova prévia"),
            )
        self._verify_bindings(plan.get("bindings", []))
        job_id = uuid.uuid4().hex
        correlation_id = uuid.uuid4().hex
        job = {
            "jobId": job_id,
            "correlationId": correlation_id,
            "kind": "maintenance.apply",
            "action": action,
            "serial": plan["serial"],
            "status": "queued",
            "progress": 0,
            "cancelable": False,
            "createdAt": _utc_text(),
        }
        with self._lock:
            self._jobs[job_id] = job
            write_json(self._jobs_path, self._jobs)
        self._emit("job.progress", job_id, correlation_id, progress=0, status="queued")
        thread = threading.Thread(
            target=self._apply_worker,
            args=(job_id, correlation_id, plan, confirmation),
            daemon=True,
        )
        thread.start()
        return job

    def _apply_worker(
        self,
        job_id: str,
        correlation_id: str,
        plan: dict[str, Any],
        confirmation: str,
    ) -> None:
        self._update_job(job_id, status="running", progress=10, startedAt=_utc_text())
        self._emit("job.progress", job_id, correlation_id, progress=10, status="running")
        try:
            if self.demo:
                time.sleep(0.2)
                output = "Execução demo concluída."
            else:
                env = {
                    **{str(key): str(value) for key, value in plan.get("environment", {}).items()},
                    "FLASH_DEVICE_SERIAL": str(plan["serial"]),
                    "ALLOW_DESTRUCTIVE": "1",
                    "REQUIRE_TYPED_CONFIRM": "1",
                }
                argv = [
                    self._tool("android-dex-flash"),
                    "--model",
                    str(plan["model"]),
                    "--commit",
                    str(plan["action"]),
                    *[str(value) for value in plan.get("pathArgs", [])],
                ]
                input_text = f"{confirmation}\n"
                if confirmation == "KNOX PERMANENTE":
                    input_text += "SIM\n"
                result = run_checked(argv, input_text=input_text, env=env, timeout=1800)
                output = (result.stdout + result.stderr).strip()[-12000:]
            self._update_job(
                job_id,
                status="completed",
                progress=100,
                completedAt=_utc_text(),
                output=output,
            )
            self._emit("job.completed", job_id, correlation_id, progress=100, output=output)
        except RpcFault as fault:
            self._update_job(
                job_id,
                status="failed",
                completedAt=_utc_text(),
                error=fault.to_object(),
            )
            self._emit("job.failed", job_id, correlation_id, error=fault.to_object())
        except Exception:
            fault = RpcFault(
                "E-JOB-CRASH",
                "Execução interrompida",
                "O serviço interrompeu o job com segurança. Revise o diagnóstico antes de tentar novamente.",
                True,
                ("Abrir diagnóstico", "Criar nova prévia"),
            )
            self._update_job(
                job_id,
                status="failed",
                completedAt=_utc_text(),
                error=fault.to_object(),
            )
            self._emit("job.failed", job_id, correlation_id, error=fault.to_object())

    def maintenance_cancel(self, params: dict[str, Any]) -> dict[str, Any]:
        job_id = params.get("jobId")
        job = self._jobs.get(str(job_id))
        if not job:
            raise RpcFault("E-JOB-MISSING", "Job não encontrado", "Atualize a lista.")
        if not job.get("cancelable"):
            raise RpcFault(
                "E-JOB-CRITICAL",
                "Cancelamento bloqueado",
                "Uma gravação crítica não pode ser interrompida com segurança.",
            )
        return {"cancelled": False}

    def job_status(self, params: dict[str, Any]) -> dict[str, Any]:
        job_id = params.get("jobId")
        if not isinstance(job_id, str) or job_id not in self._jobs:
            raise RpcFault("E-JOB-MISSING", "Job não encontrado", "Atualize a lista.")
        return self._jobs[job_id]

    def _update_job(self, job_id: str, **changes: Any) -> None:
        with self._lock:
            self._jobs[job_id].update(changes)
            write_json(self._jobs_path, self._jobs)

    def _maintenance_inputs(
        self, action: str, params: dict[str, Any]
    ) -> tuple[dict[str, str], list[Path], list[dict[str, Any]]]:
        env: dict[str, str] = {}
        paths: list[Path] = []
        if action == "flash-firmware":
            paths.append(self._existing_path(params.get("firmwarePath")))
        elif action == "root":
            image = self._file(params.get("patchedImage"))
            env["PATCHED_IMG"] = str(image)
            env["PATCHED_SHA256"] = self._sha256(image)
            partition = params.get("partition", "boot")
            if partition not in {"boot", "init_boot"}:
                raise RpcFault("E-ROOT-PARTITION", "Partição inválida", "Use boot ou init_boot.")
            env["ROOT_PARTITION"] = partition
        elif action == "restore-boot":
            image = self._file(params.get("bootImage"))
            env["BOOT_IMG"] = str(image)
            env["BOOT_SHA256"] = self._sha256(image)
            partition = params.get("partition", "boot")
            if partition not in {"boot", "init_boot"}:
                raise RpcFault("E-BOOT-PARTITION", "Partição inválida", "Use boot ou init_boot.")
            env["BOOT_PARTITION"] = partition
        elif action == "boot-recovery":
            image = self._file(params.get("recoveryImage"))
            env["RECOVERY_IMG"] = str(image)
            env["RECOVERY_SHA256"] = self._sha256(image)
        bindings: list[dict[str, Any]] = []
        for path in [*paths, *[Path(value) for key, value in env.items() if key.endswith("_IMG")]]:
            bindings.extend(self._bind_path(path))
        return env, paths, bindings

    def _bind_path(self, path: Path) -> list[dict[str, Any]]:
        if path.is_symlink():
            raise RpcFault("E-PATH-SYMLINK", "Atalho recusado", f"{path} é link simbólico.")
        files = [path] if path.is_file() else sorted(item for item in path.rglob("*") if item.is_file())
        if len(files) > 256:
            raise RpcFault("E-PATH-SCOPE", "Bundle grande demais", "Máximo de 256 arquivos.")
        bindings = []
        for item in files:
            resolved = item.resolve(strict=True)
            if item.is_symlink():
                raise RpcFault("E-PATH-SYMLINK", "Atalho recusado", f"{item} é link simbólico.")
            bindings.append(
                {"path": str(resolved), "sha256": self._sha256(resolved), "size": resolved.stat().st_size}
            )
        return bindings

    def _verify_bindings(self, bindings: list[dict[str, Any]]) -> None:
        for binding in bindings:
            path = Path(str(binding.get("path", "")))
            if not path.is_file() or path.is_symlink():
                raise RpcFault("E-ARTIFACT-CHANGED", "Artefato mudou", f"{path} não é arquivo regular.")
            if path.stat().st_size != binding.get("size") or self._sha256(path) != binding.get("sha256"):
                raise RpcFault(
                    "E-ARTIFACT-CHANGED",
                    "Artefato mudou após a prévia",
                    f"O hash de {path.name} não confere. Crie um novo plano.",
                )

    def _existing_path(self, value: Any) -> Path:
        if not isinstance(value, str) or not value:
            raise RpcFault("E-PATH-MISSING", "Arquivo obrigatório", "Escolha um arquivo ou diretório.")
        path = Path(value).expanduser()
        if path.is_symlink():
            raise RpcFault("E-PATH-SYMLINK", "Atalho recusado", f"{path} é link simbólico.")
        try:
            resolved = path.resolve(strict=True)
        except OSError as exc:
            raise RpcFault("E-PATH-MISSING", "Caminho não encontrado", str(path)) from exc
        if resolved.is_symlink() or not (resolved.is_file() or resolved.is_dir()):
            raise RpcFault("E-PATH-TYPE", "Caminho inválido", "Use arquivo ou diretório regular.")
        return resolved

    def _file(self, value: Any) -> Path:
        path = self._existing_path(value)
        if not path.is_file():
            raise RpcFault("E-PATH-TYPE", "Arquivo obrigatório", f"{path} não é arquivo.")
        return path

    def _output_dir(self, value: Any) -> Path:
        if not isinstance(value, str) or not value:
            raise RpcFault("E-OUTPUT-MISSING", "Destino obrigatório", "Escolha um diretório de saída.")
        path = Path(value).expanduser().resolve(strict=False)
        if path.exists() and (not path.is_dir() or any(path.iterdir())):
            raise RpcFault("E-OUTPUT-NOT-EMPTY", "Destino não está vazio", str(path))
        parent = path.parent
        if not parent.is_dir():
            raise RpcFault("E-OUTPUT-PARENT", "Diretório pai ausente", str(parent))
        return path

    def _sha256(self, path: Path) -> str:
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            while chunk := handle.read(1024 * 1024):
                digest.update(chunk)
        return digest.hexdigest()

    def _oem(self, device: dict[str, Any]) -> str:
        identity = f"{device.get('manufacturer', '')} {device.get('model', '')}".lower()
        if "samsung" in identity:
            return "samsung"
        if "google" in identity or "pixel" in identity:
            return "pixel"
        if "xiaomi" in identity or "redmi" in identity or "poco" in identity:
            return "xiaomi"
        if "motorola" in identity or "lenovo" in identity:
            return "motorola"
        if "oneplus" in identity:
            return "oneplus"
        if "oppo" in identity or "realme" in identity:
            return "oppo"
        if "sony" in identity:
            return "sony"
        return "generic"


class RpcHandler(socketserver.StreamRequestHandler):
    server: "RpcServer"

    def handle(self) -> None:
        if hasattr(socket, "SO_PEERCRED"):
            credentials = self.connection.getsockopt(
                socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i")
            )
            _pid, peer_uid, _gid = struct.unpack("3i", credentials)
            if peer_uid != os.getuid():
                self.wfile.write(
                    failure(
                        None,
                        RpcFault(
                            "E-PEER-UID",
                            "Cliente recusado",
                            "O socket aceita apenas processos do mesmo usuário.",
                        ),
                    )
                )
                return
        raw = self.rfile.readline(1024 * 1024 + 1)
        request_id: str | int | None = None
        try:
            request_id, method, params = parse_request(raw.rstrip(b"\n"))
            payload = success(request_id, self.server.core.dispatch(method, params))
        except RpcFault as fault:
            payload = failure(request_id, fault)
        except Exception as exc:
            payload = failure(
                request_id,
                RpcFault("E-INTERNAL", "Falha interna", str(exc), True, ("Abrir diagnóstico",)),
            )
        self.wfile.write(payload)


class RpcServer(socketserver.ThreadingUnixStreamServer):
    daemon_threads = True
    allow_reuse_address = False

    def __init__(self, address: str, core: AndroidDexCore) -> None:
        self.core = core
        super().__init__(address, RpcHandler)


def serve(*, demo: bool = False) -> None:
    path = socket_path()
    ensure_private_dir(path.parent)
    try:
        if path.exists():
            path.unlink()
        server = RpcServer(str(path), AndroidDexCore(demo=demo))
        path.chmod(0o600)
        signal.signal(signal.SIGTERM, lambda *_args: threading.Thread(target=server.shutdown).start())
        server.serve_forever(poll_interval=0.25)
    finally:
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def main() -> int:
    parser = argparse.ArgumentParser(description="Serviço local Android-DEX")
    parser.add_argument("--demo", action="store_true", help="estado visual sem comandos externos")
    args = parser.parse_args()
    serve(demo=args.demo)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
