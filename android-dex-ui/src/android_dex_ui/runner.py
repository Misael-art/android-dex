"""Execução de processos com argv fechado; nunca usa shell."""

from __future__ import annotations

import os
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence

from .protocol import RpcFault


@dataclass(frozen=True, slots=True)
class RunResult:
    returncode: int
    stdout: str
    stderr: str


def run_checked(
    argv: Sequence[str | Path],
    *,
    input_text: str | None = None,
    timeout: float = 45,
    env: Mapping[str, str] | None = None,
    allow_failure: bool = False,
) -> RunResult:
    if not argv:
        raise RpcFault("E-PROCESS-ARGV", "Comando inválido", "argv vazio.")
    command = [str(item) for item in argv]
    merged_env = os.environ.copy()
    if env:
        merged_env.update({str(key): str(value) for key, value in env.items()})
    try:
        completed = subprocess.run(
            command,
            input=input_text,
            text=True,
            capture_output=True,
            timeout=timeout,
            env=merged_env,
            shell=False,
            check=False,
        )
    except FileNotFoundError as exc:
        raise RpcFault(
            "E-TOOL-MISSING",
            "Ferramenta ausente",
            f"Não encontrei {command[0]}. Execute android-dex-setup.",
            True,
            ("Executar diagnóstico",),
        ) from exc
    except subprocess.TimeoutExpired as exc:
        raise RpcFault(
            "E-PROCESS-TIMEOUT",
            "Operação excedeu o tempo",
            f"{Path(command[0]).name} não respondeu no prazo.",
            True,
            ("Tentar novamente", "Abrir diagnóstico"),
        ) from exc
    result = RunResult(completed.returncode, completed.stdout, completed.stderr)
    if completed.returncode and not allow_failure:
        detail = (completed.stderr or completed.stdout or "Falha sem saída").strip()
        raise RpcFault(
            "E-PROCESS-FAILED",
            "A operação foi recusada",
            detail[-4000:],
            True,
            ("Revisar detalhes", "Executar diagnóstico"),
        )
    return result
