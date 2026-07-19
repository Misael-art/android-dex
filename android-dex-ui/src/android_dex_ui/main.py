"""Inicialização da aplicação Android-DEX em Qt Quick."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from PySide6.QtCore import QTimer, QUrl
from PySide6.QtGui import QFont, QFontDatabase, QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

from .client import AndroidDexClient, ClientError
from .controller import AppController
from .paths import socket_path


def _wait_for_service(client: AndroidDexClient, timeout: float = 4.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            client.call("system.snapshot")
            return
        except ClientError as exc:
            # Uma resposta de domínio (por exemplo, ADB ainda ausente) prova que
            # o daemon foi iniciado. A janela deve poder abrir o diagnóstico.
            if exc.error.get("code") != "E-SERVICE-OFFLINE":
                return
            time.sleep(0.08)
    raise RuntimeError("O serviço android-dexd não respondeu a tempo.")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Interface Android-DEX")
    parser.add_argument("--demo", action="store_true", help="usa um aparelho fictício")
    parser.add_argument("--screenshot", type=Path, help="salva uma captura e encerra")
    parser.add_argument("--page", type=int, choices=range(6), help=argparse.SUPPRESS)
    parser.add_argument("--width", type=int, help=argparse.SUPPRESS)
    parser.add_argument("--height", type=int, help=argparse.SUPPRESS)
    parser.add_argument("--service", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--setup", action="store_true", help="verifica dependências externas")
    args = parser.parse_args(argv)

    if args.service:
        from .service import serve

        serve(demo=args.demo)
        return 0
    if args.setup:
        from .setup_assistant import main as setup_main

        return setup_main([])

    demo_process: subprocess.Popen[bytes] | None = None
    if args.demo:
        demo_socket = (
            Path(tempfile.gettempdir())
            / f"android-dex-demo-{os.getuid()}-{os.getpid()}"
            / "core.sock"
        )
        os.environ["ANDROID_DEX_SOCKET"] = str(demo_socket)

    client = AndroidDexClient(socket_path())
    try:
        client.call("system.snapshot")
    except ClientError:
        if getattr(sys, "frozen", False):
            command = [sys.executable, "--service"]
        else:
            command = [sys.executable, "-m", "android_dex_ui.service"]
        if args.demo:
            command.append("--demo")
        demo_process = subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=not args.demo,
        )
        _wait_for_service(client)

    app = QGuiApplication(sys.argv[:1])
    app.setApplicationName("Android-DEX")
    app.setOrganizationName("Android-DEX")
    root = Path(__file__).resolve().parent
    for font_file in ("Inter-Variable.ttf", "MaterialSymbolsRounded.ttf"):
        QFontDatabase.addApplicationFont(str(root / "assets" / "fonts" / font_file))
    app.setFont(QFont("Inter", 11))

    engine = QQmlApplicationEngine()
    controller = AppController(client)
    engine.rootContext().setContextProperty("backend", controller)
    engine.load(QUrl.fromLocalFile(str(root / "qml" / "Main.qml")))
    if not engine.rootObjects():
        if demo_process is not None and args.demo:
            demo_process.terminate()
        return 2
    root_window = engine.rootObjects()[0]
    if args.width:
        root_window.setWidth(args.width)
    if args.height:
        root_window.setHeight(args.height)
    controller.refresh()
    if args.page is not None:
        root_window.setProperty("section", args.page)
    if args.screenshot:
        target = args.screenshot.resolve()

        def capture() -> None:
            image = root_window.screen().grabWindow(root_window.winId()).toImage()
            target.parent.mkdir(parents=True, exist_ok=True)
            if not image.save(str(target)):
                print(f"Falha ao salvar captura em {target}", file=sys.stderr)
            app.quit()

        QTimer.singleShot(1400, capture)
    result = app.exec()
    if demo_process is not None and args.demo:
        demo_process.terminate()
        demo_process.wait(timeout=2)
    return result


if __name__ == "__main__":
    raise SystemExit(main())
