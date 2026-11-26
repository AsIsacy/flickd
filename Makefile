APP_NAME      := Flickd
BIN_NAME      := flickd
BUNDLE_ID     := com.asisacy.flickd
APP_DIR       := $(HOME)/Applications/$(APP_NAME).app
PLIST_DST     := $(HOME)/Library/LaunchAgents/$(BUNDLE_ID).plist
CONFIG_DST    := $(HOME)/.config/flickd/config.json
LOG_FILE      := $(HOME)/Library/Logs/flickd.log
BUILD_DIR     := build
MIN_MACOS     := 13.0
VERSION       ?= 0.1.0

SWIFT_FLAGS   := -O -whole-module-optimization \
                 -import-objc-header src/MultitouchSupport.h \
                 -framework AppKit -framework CoreGraphics -framework ApplicationServices

.PHONY: build build-universal package install uninstall restart reload status logs clean

build:
	@mkdir -p $(BUILD_DIR)
	swiftc $(SWIFT_FLAGS) src/main.swift -o $(BUILD_DIR)/$(BIN_NAME)
	@strip -x $(BUILD_DIR)/$(BIN_NAME)
	@ls -lh $(BUILD_DIR)/$(BIN_NAME)

build-universal:
	@mkdir -p $(BUILD_DIR)
	swiftc $(SWIFT_FLAGS) -target arm64-apple-macosx$(MIN_MACOS) src/main.swift -o $(BUILD_DIR)/$(BIN_NAME)-arm64
	swiftc $(SWIFT_FLAGS) -target x86_64-apple-macosx$(MIN_MACOS) src/main.swift -o $(BUILD_DIR)/$(BIN_NAME)-x86_64
	lipo -create -output $(BUILD_DIR)/$(BIN_NAME) $(BUILD_DIR)/$(BIN_NAME)-arm64 $(BUILD_DIR)/$(BIN_NAME)-x86_64
	@strip -x $(BUILD_DIR)/$(BIN_NAME)
	@rm -f $(BUILD_DIR)/$(BIN_NAME)-arm64 $(BUILD_DIR)/$(BIN_NAME)-x86_64
	@lipo -info $(BUILD_DIR)/$(BIN_NAME)
	@ls -lh $(BUILD_DIR)/$(BIN_NAME)

STAGE_DIR     := $(BUILD_DIR)/$(APP_NAME)-v$(VERSION)

package: build-universal
	@rm -rf "$(STAGE_DIR)"
	@mkdir -p "$(STAGE_DIR)/$(APP_NAME).app/Contents/MacOS"
	@cp "$(BUILD_DIR)/$(BIN_NAME)" "$(STAGE_DIR)/$(APP_NAME).app/Contents/MacOS/$(BIN_NAME)"
	@chmod +x "$(STAGE_DIR)/$(APP_NAME).app/Contents/MacOS/$(BIN_NAME)"
	@sed -e "s|<string>0.1.0</string>|<string>$(VERSION)</string>|" Info.plist > "$(STAGE_DIR)/$(APP_NAME).app/Contents/Info.plist"
	@codesign --force --sign - --identifier $(BUNDLE_ID) "$(STAGE_DIR)/$(APP_NAME).app"
	@codesign --verify --deep --strict "$(STAGE_DIR)/$(APP_NAME).app"
	@cp install.sh config.example.json README.md README.zh-CN.md LICENSE "$(STAGE_DIR)/"
	@chmod +x "$(STAGE_DIR)/install.sh"
	@ditto -c -k --norsrc --keepParent "$(STAGE_DIR)" "$(BUILD_DIR)/$(APP_NAME)-v$(VERSION)-macos-universal.zip"
	@(cd "$(BUILD_DIR)" && shasum -a 256 "$(APP_NAME)-v$(VERSION)-macos-universal.zip" > SHA256SUMS.txt)
	@ls -lh "$(BUILD_DIR)/$(APP_NAME)-v$(VERSION)-macos-universal.zip" "$(BUILD_DIR)/SHA256SUMS.txt"

install: build
	@mkdir -p "$(APP_DIR)/Contents/MacOS" "$(HOME)/.config/flickd" "$(HOME)/Library/LaunchAgents" "$(HOME)/Library/Logs"
	@cp "$(BUILD_DIR)/$(BIN_NAME)" "$(APP_DIR)/Contents/MacOS/$(BIN_NAME)"
	@chmod +x "$(APP_DIR)/Contents/MacOS/$(BIN_NAME)"
	@cp Info.plist "$(APP_DIR)/Contents/Info.plist"
	@codesign --force --sign - --identifier $(BUNDLE_ID) "$(APP_DIR)"
	@if [ ! -f "$(CONFIG_DST)" ]; then cp config.example.json "$(CONFIG_DST)"; fi
	@sed -e "s|__HOME__|$(HOME)|g" $(BUNDLE_ID).plist.template > "$(PLIST_DST)"
	@-launchctl bootout gui/$$(id -u) "$(PLIST_DST)" 2>/dev/null || true
	@launchctl bootstrap gui/$$(id -u) "$(PLIST_DST)"
	@echo "Installed $(APP_DIR) and started LaunchAgent $(BUNDLE_ID)"

uninstall:
	@-launchctl bootout gui/$$(id -u) "$(PLIST_DST)" 2>/dev/null || true
	@rm -f "$(PLIST_DST)"
	@rm -rf "$(APP_DIR)"
	@echo "Uninstalled $(APP_NAME). Config kept at $(CONFIG_DST)."

restart:
	@launchctl kickstart -k gui/$$(id -u)/$(BUNDLE_ID)

reload:
	@pkill -HUP -x $(BIN_NAME) && echo "Sent SIGHUP to $(BIN_NAME)"

status:
	@launchctl print gui/$$(id -u)/$(BUNDLE_ID) 2>/dev/null | grep -E "state =|pid =" || echo "Not loaded"
	@ps -o pid,rss,vsz,%cpu,etime,comm -p $$(pgrep -x $(BIN_NAME) 2>/dev/null || echo 0) 2>/dev/null || true

logs:
	@tail -n 30 "$(LOG_FILE)" 2>/dev/null || echo "No logs yet"

clean:
	@rm -rf $(BUILD_DIR)
