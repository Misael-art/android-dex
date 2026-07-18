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

.PHONY: test syntax lint powershell

test: syntax
	bash tests/run.sh

syntax:
	bash -n $(SCRIPTS)

lint:
	shellcheck -x -e SC1090,SC1091,SC2034,SC2153 $(SCRIPTS)

powershell:
	@if command -v pwsh >/dev/null 2>&1; then pwsh -NoProfile -File tests/powershell-syntax.ps1; else echo "pwsh ausente; parser PowerShell será validado no job Windows da CI"; fi
