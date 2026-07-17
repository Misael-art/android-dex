SHELL := /bin/bash

SCRIPTS := \
	android-dex-kit/bin/android-dex \
	android-dex-kit/bin/android-dex-connect \
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

.PHONY: test syntax lint

test: syntax
	bash tests/run.sh

syntax:
	bash -n $(SCRIPTS)

lint:
	shellcheck -x -e SC1090,SC1091,SC2034,SC2153 $(SCRIPTS)
