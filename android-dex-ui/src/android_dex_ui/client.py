"""Cliente síncrono JSON-RPC para o socket privado."""

from __future__ import annotations

import json
import socket
import uuid
from pathlib import Path
from typing import Any

from .paths import socket_path
class ClientError(RuntimeError):
    def __init__(self, error: dict[str, Any]) -> None:
        self.error = error
        super().__init__(str(error.get("detail") or error.get("title") or "Falha RPC"))


class AndroidDexClient:
    def __init__(self, path: Path | None = None) -> None:
        self.path = path or socket_path()

    def call(self, method: str, params: dict[str, Any] | None = None, timeout: float = 30) -> Any:
        request_id = uuid.uuid4().hex
        request = {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": method,
            "params": params or {},
        }
        encoded = json.dumps(request, ensure_ascii=False, separators=(",", ":")).encode() + b"\n"
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(timeout)
            try:
                connection.connect(str(self.path))
            except OSError as exc:
                raise ClientError(
                    {
                        "code": "E-SERVICE-OFFLINE",
                        "title": "Serviço indisponível",
                        "detail": str(exc),
                        "recoverable": True,
                        "actions": ["Iniciar android-dexd"],
                    }
                ) from exc
            connection.sendall(encoded)
            chunks = bytearray()
            while not chunks.endswith(b"\n"):
                chunk = connection.recv(65536)
                if not chunk:
                    break
                chunks.extend(chunk)
        try:
            response = json.loads(chunks)
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            raise ClientError(
                {"code": "E-RPC-RESPONSE", "title": "Resposta inválida", "detail": str(exc)}
            ) from exc
        if response.get("id") != request_id:
            raise ClientError(
                {
                    "code": "E-RPC-ID",
                    "title": "Resposta inválida",
                    "detail": "O ID da resposta não confere.",
                }
            )
        error = response.get("error")
        if isinstance(error, dict):
            raise ClientError(error)
        return response.get("result")


RpcClient = AndroidDexClient
