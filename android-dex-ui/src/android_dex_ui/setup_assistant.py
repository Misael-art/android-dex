"""Verificação e instalação explícita das dependências externas."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from pathlib import Path

from .paths import project_root

TOOLS = ("adb", "fastboot", "scrcpy", "heimdall", "openssl")


def status() -> dict[str, object]:
    tools = {name: shutil.which(name) for name in TOOLS}
    return {
        "format": "android-dex.machine.v1",
        "ready": all(tools.values()),
        "tools": tools,
        "missing": [name for name, path in tools.items() if not path],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Configuração inicial do Android-DEX")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--confirm", default="")
    args = parser.parse_args(argv)
    report = status()
    if args.apply:
        if args.confirm != "INSTALAR":
            parser.error("use --confirm INSTALAR para autorizar a prévia de instalação")
        installer = Path(project_root()) / "android-dex-kit" / "install.sh"
        completed = subprocess.run([str(installer)], check=False, shell=False)
        return completed.returncode
    if args.json:
        print(json.dumps(report, ensure_ascii=False))
    else:
        print("Dependências do Android-DEX")
        for tool, path in report["tools"].items():
            print(f"  {'✓' if path else '×'} {tool}: {path or 'ausente'}")
        if report["missing"]:
            print("\nPrévia: o instalador usará o gerenciador da distribuição e autenticação do sistema.")
            print("Para continuar: android-dex-setup --apply --confirm INSTALAR")
    return 0 if report["ready"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
