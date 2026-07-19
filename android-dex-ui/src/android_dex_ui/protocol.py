"""Contrato JSON-RPC local, pequeno e fail-closed."""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any

JSONRPC_VERSION = "2.0"
MACHINE_FORMAT = "android-dex.machine.v1"
MAX_MESSAGE_BYTES = 1024 * 1024


@dataclass(slots=True)
class RpcFault(Exception):
    code: str
    title: str
    detail: str
    recoverable: bool = False
    actions: tuple[str, ...] = ()

    def to_object(self) -> dict[str, Any]:
        return {
            "code": self.code,
            "title": self.title,
            "detail": self.detail,
            "recoverable": self.recoverable,
            "actions": list(self.actions),
        }


def parse_request(raw: bytes) -> tuple[str | int | None, str, dict[str, Any]]:
    if len(raw) > MAX_MESSAGE_BYTES:
        raise RpcFault("E-RPC-SIZE", "Mensagem muito grande", "O limite é 1 MiB.")
    try:
        value = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RpcFault("E-RPC-JSON", "JSON inválido", str(exc)) from exc
    if not isinstance(value, dict) or value.get("jsonrpc") != JSONRPC_VERSION:
        raise RpcFault("E-RPC-ENVELOPE", "Envelope inválido", "Use JSON-RPC 2.0.")
    request_id = value.get("id")
    if request_id is not None and not isinstance(request_id, (str, int)):
        raise RpcFault("E-RPC-ID", "ID inválido", "id deve ser string, inteiro ou null.")
    method = value.get("method")
    params = value.get("params", {})
    if not isinstance(method, str) or not method:
        raise RpcFault("E-RPC-METHOD", "Método inválido", "method é obrigatório.")
    if not isinstance(params, dict):
        raise RpcFault("E-RPC-PARAMS", "Parâmetros inválidos", "params deve ser objeto.")
    return request_id, method, params


def success(request_id: str | int | None, result: Any) -> bytes:
    return _encode({"jsonrpc": JSONRPC_VERSION, "id": request_id, "result": result})


def failure(request_id: str | int | None, fault: RpcFault) -> bytes:
    return _encode({"jsonrpc": JSONRPC_VERSION, "id": request_id, "error": fault.to_object()})


def event(name: str, job_id: str, correlation_id: str, data: dict[str, Any]) -> bytes:
    return _encode(
        {
            "jsonrpc": JSONRPC_VERSION,
            "method": name,
            "params": {"jobId": job_id, "correlationId": correlation_id, **data},
        }
    )


def _encode(value: dict[str, Any]) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8") + b"\n"
