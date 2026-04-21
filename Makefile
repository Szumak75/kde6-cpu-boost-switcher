BUILD_DIR ?= build
PREFIX ?= /usr
CMAKE ?= cmake
SUDO ?= sudo
JOBS ?= $(shell nproc)
CONFIGURE_ARGS ?=
PLASMA_QUIT_CMD ?= $(shell sh -c 'for cmd in kquitapp6 kquitapp; do command -v $$cmd >/dev/null 2>&1 && { printf "%s" "$$cmd"; exit 0; }; done')
PLASMA_START_CMD ?= $(shell sh -c 'for cmd in kstart6 kstart; do command -v $$cmd >/dev/null 2>&1 && { printf "%s" "$$cmd"; exit 0; }; done')

.PHONY: help configure reconfigure build rebuild install install-plasmoid install-system reinstall \
	enable-restore-service start-restore-service restart-plasma show-plasma-tools translations clean distclean

help:
	@printf '%s\n' \
		'Available targets:' \
		'  make configure              Configure CMake in $(BUILD_DIR) with PREFIX=$(PREFIX)' \
		'  make build                  Configure and build the project' \
		'  make rebuild                Re-run configure and rebuild everything' \
		'  make install                Install plasmoid and system components' \
		'  make install-plasmoid       Install the plasmoid package and KAuth client' \
		'  make install-system         Install helper, D-Bus, Polkit, and systemd files' \
		'  make reinstall              Install everything and restart Plasma Shell' \
		'  make enable-restore-service Enable the boot-time restore systemd service' \
		'  make start-restore-service  Start the boot-time restore systemd service once' \
		'  make restart-plasma         Restart Plasma Shell after installation' \
		'  make show-plasma-tools      Show the detected Plasma restart commands' \
		'  make translations           Rebuild packaged translation catalogs' \
		'  make clean                  Clean build outputs in $(BUILD_DIR)' \
		'  make distclean              Remove $(BUILD_DIR)' \
		'' \
		'Overridable variables:' \
		'  BUILD_DIR=$(BUILD_DIR)' \
		'  PREFIX=$(PREFIX)' \
		'  JOBS=$(JOBS)' \
		'  SUDO=$(SUDO)' \
		'  CONFIGURE_ARGS=$(CONFIGURE_ARGS)' \
		'  PLASMA_QUIT_CMD=$(PLASMA_QUIT_CMD)' \
		'  PLASMA_START_CMD=$(PLASMA_START_CMD)'

configure:
	$(CMAKE) -B $(BUILD_DIR) -S . -DCMAKE_INSTALL_PREFIX=$(PREFIX) $(CONFIGURE_ARGS)

reconfigure: configure

build: configure
	$(CMAKE) --build $(BUILD_DIR) -j$(JOBS)

rebuild: configure
	$(CMAKE) --build $(BUILD_DIR) --clean-first -j$(JOBS)

install: install-plasmoid install-system

install-plasmoid: build
	$(SUDO) $(CMAKE) --install $(BUILD_DIR) --component Plasmoid

install-system: build
	$(SUDO) $(CMAKE) --install $(BUILD_DIR) --component KAuthSystem

reinstall: install restart-plasma

enable-restore-service:
	$(SUDO) systemctl enable cpuboost-restore.service

start-restore-service:
	$(SUDO) systemctl start cpuboost-restore.service

restart-plasma:
	@if [ -z "$(PLASMA_QUIT_CMD)" ]; then echo "No supported plasmashell stop command found (tried: kquitapp6, kquitapp)."; exit 1; fi
	@if [ -z "$(PLASMA_START_CMD)" ]; then echo "No supported plasmashell start command found (tried: kstart6, kstart)."; exit 1; fi
	@echo "Restarting plasmashell with $(PLASMA_QUIT_CMD) and $(PLASMA_START_CMD)"
	@$(PLASMA_QUIT_CMD) plasmashell && $(PLASMA_START_CMD) plasmashell > /dev/null 2>&1 || { echo "Failed to restart plasmashell. Please restart it manually."; exit 1; }

show-plasma-tools:
	@printf 'PLASMA_QUIT_CMD=%s\nPLASMA_START_CMD=%s\n' "$(PLASMA_QUIT_CMD)" "$(PLASMA_START_CMD)"

translations:
	./scripts/build-translations.sh

clean:
	@if [ -d "$(BUILD_DIR)" ]; then $(CMAKE) --build $(BUILD_DIR) --target clean; fi

distclean:
	$(CMAKE) -E rm -rf $(BUILD_DIR)
