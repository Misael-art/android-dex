"""Ponte enxuta entre o contrato JSON-RPC e a interface QML."""

from __future__ import annotations

from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

from PySide6.QtCore import Property, QObject, QTimer, Signal, Slot

from .client import AndroidDexClient, ClientError


class AppController(QObject):
    snapshotChanged = Signal()
    selectedSerialChanged = Signal()
    busyChanged = Signal()
    messageChanged = Signal()
    maintenanceChanged = Signal()
    jobChanged = Signal()

    def __init__(self, client: AndroidDexClient) -> None:
        super().__init__()
        self._client = client
        self._snapshot: dict[str, Any] = {"devices": [], "sessions": [], "tools": {}}
        self._selected_serial = ""
        self._busy = False
        self._message: dict[str, Any] = {}
        self._maintenance: dict[str, Any] = {}
        self._job: dict[str, Any] = {}
        self._event_cursor = 0
        self._poller = QTimer(self)
        self._poller.setInterval(1250)
        self._poller.timeout.connect(self.pollEvents)
        self._poller.start()

    @Property("QVariantMap", notify=snapshotChanged)
    def snapshot(self) -> dict[str, Any]:
        return self._snapshot

    @Property("QVariantList", notify=snapshotChanged)
    def devices(self) -> list[dict[str, Any]]:
        return list(self._snapshot.get("devices", []))

    @Property("QVariantList", notify=snapshotChanged)
    def sessions(self) -> list[dict[str, Any]]:
        return list(self._snapshot.get("sessions", []))

    @Property(str, notify=selectedSerialChanged)
    def selectedSerial(self) -> str:
        return self._selected_serial

    @Property("QVariantMap", notify=snapshotChanged)
    def selectedDevice(self) -> dict[str, Any]:
        devices = self._snapshot.get("devices", [])
        for device in devices:
            if device.get("serial") == self._selected_serial:
                return device
        return devices[0] if devices else {}

    @Property(bool, notify=busyChanged)
    def busy(self) -> bool:
        return self._busy

    @Property("QVariantMap", notify=messageChanged)
    def message(self) -> dict[str, Any]:
        return self._message

    @Property("QVariantMap", notify=maintenanceChanged)
    def maintenance(self) -> dict[str, Any]:
        return self._maintenance

    @Property("QVariantMap", notify=jobChanged)
    def job(self) -> dict[str, Any]:
        return self._job

    def _set_busy(self, value: bool) -> None:
        if self._busy != value:
            self._busy = value
            self.busyChanged.emit()

    def _notice(self, title: str, detail: str = "", level: str = "info") -> None:
        self._message = {"title": title, "detail": detail, "level": level}
        self.messageChanged.emit()

    def _call(self, method: str, params: dict[str, Any] | None = None) -> Any:
        self._set_busy(True)
        try:
            return self._client.call(method, params or {})
        except ClientError as exc:
            error = exc.error
            self._notice(
                str(error.get("title", "Não foi possível concluir")),
                str(error.get("detail", exc)),
                "error",
            )
            return None
        finally:
            self._set_busy(False)

    @Slot()
    def refresh(self) -> None:
        result = self._call("system.snapshot")
        if result is None:
            return
        self._snapshot = result
        devices = self._snapshot.get("devices", [])
        serials = {device.get("serial") for device in devices}
        if self._selected_serial not in serials:
            self._selected_serial = devices[0].get("serial", "") if devices else ""
            self.selectedSerialChanged.emit()
        self.snapshotChanged.emit()

    @Slot(str)
    def selectDevice(self, serial: str) -> None:
        if serial != self._selected_serial:
            self._selected_serial = serial
            self.selectedSerialChanged.emit()
            self.snapshotChanged.emit()

    @Slot(str)
    def startDesktop(self, mode: str = "auto") -> None:
        result = self._call(
            "desktop.start", {"serial": self._selected_serial, "mode": mode}
        )
        if result is not None:
            self._notice("Sessão iniciada", str(result.get("detail", "Desktop pronto.")), "success")
            self.refresh()

    @Slot(str)
    def stopDesktop(self, session_id: str = "") -> None:
        params: dict[str, Any] = {"serial": self._selected_serial}
        if session_id:
            params["sessionId"] = session_id
        result = self._call("desktop.stop", params)
        if result is not None:
            self._notice("Sessão encerrada", "Os ajustes temporários foram restaurados.", "success")
            self.refresh()

    @Slot()
    def discoverWifi(self) -> None:
        result = self._call("wifi.discover")
        if result is not None:
            self._snapshot["wifi"] = result
            self.snapshotChanged.emit()
            self._notice("Busca concluída", f"{len(result.get('endpoints', []))} dispositivo(s) encontrado(s).")

    @Slot(str)
    def connectWifi(self, endpoint: str) -> None:
        result = self._call("wifi.connect", {"endpoint": endpoint})
        if result is not None:
            self._notice("Conectado por Wi‑Fi", endpoint, "success")
            self.refresh()

    @Slot(str, str)
    def pairWifi(self, endpoint: str, code: str) -> None:
        result = self._call("wifi.pair", {"endpoint": endpoint, "code": code})
        if result is not None:
            self._notice("Pareamento concluído", endpoint, "success")
            self.refresh()

    @Slot()
    def runDoctor(self) -> None:
        result = self._call("doctor.run", {"serial": self._selected_serial})
        if result is not None:
            self._snapshot["doctor"] = result
            self.snapshotChanged.emit()
            self._notice("Diagnóstico concluído", str(result.get("summary", "Verificação finalizada.")), "success")

    @Slot()
    def restoreTweaks(self) -> None:
        result = self._call("tweaks.restore", {"serial": self._selected_serial})
        if result is not None:
            self._notice("Ajustes restaurados", "O aparelho voltou ao estado anterior.", "success")

    @Slot(str, str, str)
    def planMaintenance(self, action: str, artifact_url: str, partition: str = "") -> None:
        params: dict[str, Any] = {"serial": self._selected_serial, "action": action}
        if artifact_url:
            parsed = urlparse(artifact_url)
            path = unquote(parsed.path) if parsed.scheme == "file" else artifact_url
            path_key = {
                "flash-firmware": "firmwarePath",
                "root": "patchedImage",
                "restore-boot": "bootImage",
                "boot-recovery": "recoveryImage",
            }.get(action, "artifactPath")
            params[path_key] = str(Path(path))
        if partition:
            params["partition"] = partition
        result = self._call("maintenance.plan", params)
        if result is not None:
            self._maintenance = result
            self.maintenanceChanged.emit()
            self._notice("Prévia segura criada", "Revise todos os riscos antes de confirmar.")

    @Slot(str)
    def applyMaintenance(self, confirmation: str) -> None:
        plan_id = self._maintenance.get("planId", "")
        result = self._call(
            "maintenance.apply", {"planId": plan_id, "confirmation": confirmation}
        )
        if result is not None:
            self._job = result
            self.jobChanged.emit()
            self._notice("Operação iniciada", "Não desconecte o cabo durante a etapa crítica.")

    @Slot()
    def cancelMaintenance(self) -> None:
        job_id = self._job.get("jobId", "")
        if not job_id:
            return
        result = self._call("maintenance.cancel", {"jobId": job_id})
        if result is not None:
            self._job = result
            self.jobChanged.emit()

    @Slot()
    def pollEvents(self) -> None:
        try:
            result = self._client.call("events.poll", {"after": self._event_cursor})
        except ClientError:
            return
        self._event_cursor = int(result.get("cursor", self._event_cursor))
        events = result.get("events", [])
        if not events:
            return
        latest = events[-1]
        self._job = latest
        self.jobChanged.emit()
        if latest.get("event") in {"job.completed", "job.failed"}:
            self._notice(
                "Operação concluída" if latest.get("event") == "job.completed" else "Operação interrompida",
                str(latest.get("detail", "")),
                "success" if latest.get("event") == "job.completed" else "error",
            )
            self.refresh()

    @Slot()
    def clearMessage(self) -> None:
        self._message = {}
        self.messageChanged.emit()
