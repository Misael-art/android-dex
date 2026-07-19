SHELL := /bin/bash

SCRIPTS := \
	android-dex-kit/bin/android-dex \
	android-dex-kit/bin/android-dex-connect \
	android-dex-kit/bin/android-dex-doctor \
	android-dex-kit/install.sh \
	android-dex-kit/uninstall.sh \
	android-dex-kit/lib/common.sh \
	android-dex-flash/bin/android-dex-flash \
	android-dex-flash/install.sh \
	android-dex-flash/uninstall.sh \
	android-dex-flash/lib/common.sh \
	android-dex-flash/lib/flash-common.sh \
	$(wildcard android-dex-flash/lib/drivers/*.sh) \
	tests/run.sh

.PHONY: test syntax lint powershell ui-test qml-test ui-smoke appimage appdir

test: syntax
	bash tests/run.sh

syntax:
	bash -n $(SCRIPTS)

lint:
	shellcheck -x -e SC1090,SC1091,SC2034,SC2153 $(SCRIPTS)

powershell:
	@if command -v pwsh >/dev/null 2>&1; then pwsh -NoProfile -File tests/powershell-syntax.ps1; else echo "pwsh ausente; parser PowerShell será validado no job Windows da CI"; fi

ui-test:
	QT_QPA_PLATFORM=offscreen python3 -m pytest -q android-dex-ui/tests

qml-test:
	@runner="$$(if [ -x /usr/lib/qt6/bin/qmltestrunner ]; then printf /usr/lib/qt6/bin/qmltestrunner; else command -v qmltestrunner; fi)"; \
	[ -n "$$runner" ] || { echo "qmltestrunner Qt 6 ausente" >&2; exit 1; }; \
	QT_QPA_PLATFORM=offscreen "$$runner" -input android-dex-ui/qml-tests \
		-import android-dex-ui/src/android_dex_ui/qml -o -,txt

ui-smoke:
	QT_QPA_PLATFORM=offscreen python3 -m android_dex_ui.main --demo --screenshot /tmp/android-dex-ui-smoke.png

appimage:
	bash android-dex-ui/appimage/build-appimage.sh

appdir:
	bash android-dex-ui/appimage/build-appimage.sh --appdir-only
