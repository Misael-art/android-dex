"""Cliente síncrono JSON-RPC para o socket privado."""

from __future__ import annotations

import json
import socket
import uuid
from pathlib import Path
from typing import Any, Iterator

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

    def subscribe(self, after: int = 0, timeout: float = 45) -> Iterator[dict[str, Any]]:
        """Conexão persistente: produz os params de cada evento enviado pelo serviço.

        O serviço envia heartbeat a cada 15 s; `timeout` maior que isso detecta
        um serviço travado. Levanta ClientError ao perder a conexão.
        """
        request_id = uuid.uuid4().hex
        request = {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": "events.subscribe",
            "params": {"after": after},
        }
        encoded = json.dumps(request, separators=(",", ":")).encode() + b"\n"
        connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        connection.settimeout(timeout)
        try:
            try:
                connection.connect(str(self.path))
                connection.sendall(encoded)
                stream = connection.makefile("rb")
                ack = json.loads(stream.readline() or b"null")
            except (OSError, json.JSONDecodeError) as exc:
                raise ClientError(
                    {"code": "E-SERVICE-OFFLINE", "title": "Serviço indisponível", "detail": str(exc)}
                ) from exc
            if not isinstance(ack, dict) or ack.get("id") != request_id or "error" in ack:
                error = ack.get("error") if isinstance(ack, dict) else None
                raise ClientError(
                    error
                    if isinstance(error, dict)
                    else {"code": "E-RPC-RESPONSE", "title": "Resposta inválida", "detail": "ack"}
                )
            while True:
                try:
                    line = stream.readline()
                except OSError as exc:
                    raise ClientError(
                        {"code": "E-STREAM-LOST", "title": "Conexão perdida", "detail": str(exc)}
                    ) from exc
                if not line:
                    raise ClientError(
                        {"code": "E-STREAM-LOST", "title": "Conexão perdida", "detail": "EOF"}
                    )
                message = json.loads(line)
                yield {"event": message.get("method"), **message.get("params", {})}
        finally:
            connection.close()


RpcClient = AndroidDexClient
