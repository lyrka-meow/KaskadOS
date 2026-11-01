CALAMARES_BUILD_DIR ?= $(CURDIR)/build/calamares
CALAMARES_JOBS ?= 8
CALAMARES_PREVIEW_DIR := $(CALAMARES_BUILD_DIR)/kaskados-preview

.PHONY: check iso iso-update iso-update-package component clean live-profile manager manager-run calamares-configure calamares-build calamares-run calamares-preview

check:
	./scripts/check-profile.sh

iso: check
	./scripts/build-iso-offline.sh

iso-update: check
	./scripts/prepare-live-profile.sh
	./scripts/cache-iso-packages.sh

iso-update-package:
	@test -n "$(PACKAGE)" || { echo 'Использование: make iso-update-package PACKAGE=имя-пакета' >&2; exit 2; }
	./scripts/cache-iso-packages.sh "$(PACKAGE)"

component:
	@test -n "$(NAME)" || { echo 'Использование: make component NAME=calamares' >&2; exit 2; }
	./scripts/build-component.sh "$(NAME)"

live-profile: check
	./scripts/package-ready-components.sh

clean:
	./scripts/clean-work.sh

manager:
	cmake -S tools/kaskados-manager -B build/kaskados-manager -G Ninja
	cmake --build build/kaskados-manager

manager-run: manager
	./build/kaskados-manager/kaskados-manager --project "$(CURDIR)"

calamares-configure:
	cmake -S components/calamares -B "$(CALAMARES_BUILD_DIR)" -G Ninja \
		-DWITH_QT6=ON \
		-DINSTALL_CONFIG=ON \
		-DBUILD_TESTING=OFF \
		-DBUILD_SCHEMA_TESTING=OFF \
		-DCMAKE_BUILD_TYPE=Release

calamares-build: calamares-configure
	cmake --build "$(CALAMARES_BUILD_DIR)" --parallel "$(CALAMARES_JOBS)"

calamares-run: calamares-build
	cd "$(CALAMARES_BUILD_DIR)" && ./calamares -d

# Developer-only visual review. The preview settings deliberately contain no
# exec phase, so walking through every page cannot partition a disk or install.
calamares-preview: calamares-build
	rm -rf "$(CALAMARES_PREVIEW_DIR)"
	mkdir -p "$(CALAMARES_PREVIEW_DIR)/modules"
	install -m 0644 "$(CURDIR)/tools/calamares-preview/settings.conf" "$(CALAMARES_PREVIEW_DIR)/settings.conf"
	install -m 0644 "$(CURDIR)/components/calamares/src/modules/welcome/welcome.conf" "$(CALAMARES_PREVIEW_DIR)/modules/welcome.conf"
	install -m 0644 "$(CURDIR)/components/calamares/src/modules/locale/locale.conf" "$(CALAMARES_PREVIEW_DIR)/modules/locale.conf"
	install -m 0644 "$(CURDIR)/components/calamares/src/modules/keyboard/keyboard.conf" "$(CALAMARES_PREVIEW_DIR)/modules/keyboard.conf"
	install -m 0644 "$(CURDIR)/components/calamares/src/modules/partition/partition.conf" "$(CALAMARES_PREVIEW_DIR)/modules/partition.conf"
	install -m 0644 "$(CURDIR)/components/calamares/src/modules/users/users.conf" "$(CALAMARES_PREVIEW_DIR)/modules/users.conf"
	install -m 0644 "$(CURDIR)/tools/calamares-preview/modules/shellprocess@preview.conf" "$(CALAMARES_PREVIEW_DIR)/modules/shellprocess@preview.conf"
	install -m 0644 "$(CURDIR)/tools/calamares-preview/modules/finished.conf" "$(CALAMARES_PREVIEW_DIR)/modules/finished.conf"
	mkdir -p "$(CALAMARES_PREVIEW_DIR)/qml/calamares"
	ln -s "$(CALAMARES_BUILD_DIR)/src/qml/calamares-qt6/slideshow" "$(CALAMARES_PREVIEW_DIR)/qml/calamares/slideshow"
	ln -s "$(CALAMARES_BUILD_DIR)/src/branding" "$(CALAMARES_PREVIEW_DIR)/branding"
	cd "$(CALAMARES_BUILD_DIR)" && KASKADOS_CALAMARES_PREVIEW=1 ./calamares -d -c "$(CALAMARES_PREVIEW_DIR)"
