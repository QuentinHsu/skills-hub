TARGET_NAME  := SkillsHub
DISPLAY_NAME := Skills Hub
BUNDLE_ID    := com.skillshub.app
BUILD_DIR    := .build
RELEASE_DIR  := $(BUILD_DIR)/release
APP_BUNDLE   := $(BUILD_DIR)/$(DISPLAY_NAME).app
DMG_FILE     := $(BUILD_DIR)/$(DISPLAY_NAME).dmg
INSTALL_DIR  := /Applications
RELEASE_KIT_DIR ?= ../../open-source/workflow/release-kits/macos/swiftpm-sparkle
RELEASE_KIT_BUILD := $(RELEASE_KIT_DIR)/Scripts/build.sh

.PHONY: build clean app dmg install uninstall run

# ─── Development ──────────────────────────────────────────────

build:
	swift build -c release

run:
	swift run $(TARGET_NAME)

clean:
	swift package clean
	rm -rf "$(APP_BUNDLE)" "$(DMG_FILE)" dist

# ─── App Bundle ───────────────────────────────────────────────

app:
	@APP_PROJECT_DIR="$(CURDIR)" \
	 APP_TARGET_NAME="$(TARGET_NAME)" \
	 APP_DISPLAY_NAME="$(DISPLAY_NAME)" \
	 APP_BUNDLE_NAME="$(DISPLAY_NAME)" \
	 APP_BUNDLE_ID="$(BUNDLE_ID)" \
	 APP_MIN_MACOS="15.0" \
	 APP_ICON_PATH="Assets/AppIcon.icns" \
	 APP_REPOSITORY="QuentinHsu/skills-hub" \
	 "$(RELEASE_KIT_BUILD)" app

# ─── DMG ──────────────────────────────────────────────────────

dmg:
	@APP_PROJECT_DIR="$(CURDIR)" \
	 APP_TARGET_NAME="$(TARGET_NAME)" \
	 APP_DISPLAY_NAME="$(DISPLAY_NAME)" \
	 APP_BUNDLE_NAME="$(DISPLAY_NAME)" \
	 APP_BUNDLE_ID="$(BUNDLE_ID)" \
	 APP_MIN_MACOS="15.0" \
	 APP_ICON_PATH="Assets/AppIcon.icns" \
	 APP_REPOSITORY="QuentinHsu/skills-hub" \
	 "$(RELEASE_KIT_BUILD)" dmg

# ─── Install / Uninstall ─────────────────────────────────────

install: app
	@echo "▸ Installing to $(INSTALL_DIR)..."
	@rm -rf "$(INSTALL_DIR)/$(DISPLAY_NAME).app"
	@cp -r "$(APP_BUNDLE)" "$(INSTALL_DIR)/"
	@echo "✓ $(INSTALL_DIR)/$(DISPLAY_NAME).app"

uninstall:
	@echo "▸ Removing $(INSTALL_DIR)/$(DISPLAY_NAME).app..."
	@rm -rf "$(INSTALL_DIR)/$(DISPLAY_NAME).app"
	@echo "✓ Removed"
