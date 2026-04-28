TARGET_NAME  := SkillsHub
DISPLAY_NAME := Skills Hub
BUNDLE_ID    := com.skillshub.app
BUILD_DIR    := .build
RELEASE_DIR  := $(BUILD_DIR)/release
APP_BUNDLE   := $(BUILD_DIR)/$(DISPLAY_NAME).app
DMG_FILE     := $(BUILD_DIR)/$(DISPLAY_NAME).dmg
INSTALL_DIR  := /Applications

.PHONY: build clean app dmg install uninstall run

# ─── Development ──────────────────────────────────────────────

build:
	swift build -c release

run:
	swift run $(TARGET_NAME)

clean:
	swift package clean
	rm -rf "$(APP_BUNDLE)" "$(DMG_FILE)"

# ─── App Bundle ───────────────────────────────────────────────

app: build
	@echo "▸ Creating $(DISPLAY_NAME).app..."
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(RELEASE_DIR)/$(TARGET_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(TARGET_NAME)"
	@cp Info.plist "$(APP_BUNDLE)/Contents/"
	@if [ -f Assets/AppIcon.icns ]; then \
		cp Assets/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/"; \
	fi
	@echo "✓ $(APP_BUNDLE)"

# ─── DMG ──────────────────────────────────────────────────────

dmg: app
	@echo "▸ Creating $(DISPLAY_NAME).dmg..."
	@rm -f "$(DMG_FILE)"
	@mkdir -p "$(BUILD_DIR)/dmg"
	@cp -r "$(APP_BUNDLE)" "$(BUILD_DIR)/dmg/"
	@ln -s /Applications "$(BUILD_DIR)/dmg/Applications"
	@hdiutil create \
		-volname "$(DISPLAY_NAME)" \
		-fs HFS+ \
		-srcfolder "$(BUILD_DIR)/dmg" \
		-ov \
		-quiet \
		"$(DMG_FILE)"
	@rm -rf "$(BUILD_DIR)/dmg"
	@echo "✓ $(DMG_FILE)"

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
