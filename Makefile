APP_NAME      := Flickd
BIN_NAME      := flickd
BUNDLE_ID     := com.asisacy.flickd
APP_DIR       := $(HOME)/Applications/$(APP_NAME).app
PLIST_DST     := $(HOME)/Library/LaunchAgents/$(BUNDLE_ID).plist
CONFIG_DST    := $(HOME)/.config/flickd/config.json
LOG_FILE      := $(HOME)/Library/Logs/flickd.log
BUILD_DIR     := build

.PHONY: build install uninstall start stop restart reload status logs clean

build:
	@mkdir -p $(BUILD_DIR)
	swiftc -O -whole-module-optimization \
		-import-objc-header src/MultitouchSupport.h \
		-framework AppKit -framework CoreGraphics -framework ApplicationServices \
		src/main.swift -o $(BUILD_DIR)/$(BIN_NAME)
	@strip -x $(BUILD_DIR)/$(BIN_NAME)
	@ls -lh $(BUILD_DIR)/$(BIN_NAME)

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
