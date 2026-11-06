# ConnectNow: build, package and publish from the command line.
# No need to ever open Xcode: `make app` is enough.

APP_NAME    := ConnectNow
PRODUCT     := ConnectNow
CLI_PRODUCT := ConnectNowCLI
# Name of the command-line tool, shipped in ConnectNow.app/Contents/Helpers.
CLI_NAME    := connectnow
APP         := $(APP_NAME).app
SCRATCH     ?= .build
CONFIG      ?= release
INFO_PLIST  := Resources/Info.plist
ICON        := Resources/AppIcon.icns
SIGN_ID     ?= -

# Version: VERSION variable, else latest git tag (without the leading "v"), else 0.0.0.
VERSION      ?= $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)
ifeq ($(strip $(VERSION)),)
VERSION      := 0.0.0
endif
BUILD_NUMBER ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
ZIP          := $(APP_NAME).zip

# The Command Line Tools sometimes ship a broken SwiftPM: prefer Xcode when it is installed.
ifeq ($(origin DEVELOPER_DIR),undefined)
ifneq ($(wildcard /Applications/Xcode.app/Contents/Developer),)
export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
endif
endif

SWIFT        := swift
SWIFT_FLAGS  := -c $(CONFIG) --scratch-path $(SCRATCH)
# `make universal app zip` (or UNIVERSAL=1): every target uses the arm64 + x86_64 binary.
UNIVERSAL    ?= $(if $(filter universal,$(MAKECMDGOALS)),1,0)
ifeq ($(UNIVERSAL),1)
SWIFT_FLAGS  += --arch arm64 --arch x86_64
endif

.PHONY: all build universal app _bundle run test zip install icon og clean help

all: app

help:
	@echo "Targets: build universal app run test zip install icon og clean"
	@echo "Variables: VERSION=$(VERSION) SCRATCH=$(SCRATCH) CONFIG=$(CONFIG) UNIVERSAL=$(UNIVERSAL)"
	@echo "Toolchain: $${DEVELOPER_DIR:-$$(xcode-select -p)}"

## App and command-line tool for the current architecture.
build:
	$(SWIFT) build $(SWIFT_FLAGS) --product $(PRODUCT)
	$(SWIFT) build $(SWIFT_FLAGS) --product $(CLI_PRODUCT)

## Universal executables (arm64 + x86_64). `make universal app` packages these binaries.
universal:
	$(SWIFT) build -c $(CONFIG) --scratch-path $(SCRATCH) --arch arm64 --arch x86_64 --product $(PRODUCT)
	$(SWIFT) build -c $(CONFIG) --scratch-path $(SCRATCH) --arch arm64 --arch x86_64 --product $(CLI_PRODUCT)

## Package the binary into ConnectNow.app, inject the version and ad-hoc sign it.
app: $(if $(filter 1,$(UNIVERSAL)),universal,build)
	@$(MAKE) --no-print-directory _bundle UNIVERSAL=$(UNIVERSAL)

_bundle:
	@set -e; \
	BIN_DIR="$$($(SWIFT) build $(SWIFT_FLAGS) --show-bin-path)"; \
	test -x "$$BIN_DIR/$(PRODUCT)" || { echo "Binary not found: $$BIN_DIR/$(PRODUCT)"; exit 1; }; \
	test -x "$$BIN_DIR/$(CLI_PRODUCT)" || { echo "Binary not found: $$BIN_DIR/$(CLI_PRODUCT)"; exit 1; }; \
	echo "Packaging $(APP) $(VERSION) ($(BUILD_NUMBER)) from $$BIN_DIR"; \
	rm -rf "$(APP)"; \
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources" "$(APP)/Contents/Helpers"; \
	cp "$$BIN_DIR/$(PRODUCT)" "$(APP)/Contents/MacOS/$(APP_NAME)"; \
	cp "$$BIN_DIR/$(CLI_PRODUCT)" "$(APP)/Contents/Helpers/$(CLI_NAME)"; \
	cp "$(ICON)" "$(APP)/Contents/Resources/AppIcon.icns"; \
	cp "$(INFO_PLIST)" "$(APP)/Contents/Info.plist"; \
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" "$(APP)/Contents/Info.plist"; \
	plutil -replace CFBundleVersion -string "$(BUILD_NUMBER)" "$(APP)/Contents/Info.plist"; \
	printf 'APPL????' > "$(APP)/Contents/PkgInfo"; \
	for b in "$$BIN_DIR"/*.bundle; do \
		[ -d "$$b" ] || continue; \
		echo "  resources: $$(basename "$$b")"; \
		ditto "$$b" "$(APP)/Contents/Resources/$$(basename "$$b")"; \
	done; \
	plutil -lint "$(APP)/Contents/Info.plist" >/dev/null; \
	codesign --force --sign "$(SIGN_ID)" --options runtime --timestamp=none --identifier com.connectnow.cli "$(APP)/Contents/Helpers/$(CLI_NAME)"; \
	codesign --force --sign "$(SIGN_ID)" --options runtime --timestamp=none "$(APP)"; \
	codesign --verify --strict "$(APP)"; \
	echo "OK: $(APP) ($$(lipo -archs "$(APP)/Contents/MacOS/$(APP_NAME)"))"

run: app
	open -W "$(APP)"

test:
	$(SWIFT) test --scratch-path $(SCRATCH)

## Distributable archive (the signature lives inside the bundle, so extended attributes are dropped).
zip:
	@test -d "$(APP)" || $(MAKE) --no-print-directory app
	rm -f "$(ZIP)"
	ditto -c -k --norsrc --noextattr --keepParent "$(APP)" "$(ZIP)"
	@echo "OK: $(ZIP)"

install: app
	rm -rf "/Applications/$(APP)"
	ditto "$(APP)" "/Applications/$(APP)"
	@echo "Installed to /Applications/$(APP)"

## Regenerate icon.svg, icon.png (1024) and AppIcon.icns from Resources/Icon/make_svg.py.
## Optional: the committed PNG/icns are used by default. Needs python3 and rsvg-convert (brew install librsvg).
icon:
	./scripts/make-icon.sh

## Regenerate docs/og.png, the image shown when the website is shared, from scripts/og.html. Needs Google Chrome.
og:
	./scripts/make-og.sh

clean:
	rm -rf "$(APP)" $(APP_NAME)*.zip
	$(SWIFT) package clean --scratch-path $(SCRATCH) 2>/dev/null || true
