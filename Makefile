.PHONY: build install smoke hotkey-smoke

build:
	./Scripts/build.sh

install:
	./Scripts/install-local.sh

smoke:
	./Scripts/smoke-test.sh

hotkey-smoke:
	./Scripts/hotkey-smoke-test.sh
