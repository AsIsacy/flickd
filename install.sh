#!/usr/bin/env bash
set -euo pipefail

REPO="AsIsacy/flickd"
APP_NAME="Flickd"
BIN_NAME="flickd"
BUNDLE_ID="com.asisacy.flickd"
APP_DIR="${HOME}/Applications/${APP_NAME}.app"
PLIST_DST="${HOME}/Library/LaunchAgents/${BUNDLE_ID}.plist"
CONFIG_DIR="${HOME}/.config/flickd"
CONFIG_DST="${CONFIG_DIR}/config.json"
LOG_DIR="${HOME}/Library/Logs"
LOG_FILE="${LOG_DIR}/flickd.log"

if [ "${1:-}" = "--uninstall" ]; then
  launchctl bootout "gui/$(id -u)" "${PLIST_DST}" 2>/dev/null || true
  rm -f "${PLIST_DST}"
  rm -rf "${APP_DIR}"
  echo "Uninstalled ${APP_NAME}. Config kept at ${CONFIG_DST}."
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
TMP_DIR=""
cleanup() { [ -n "${TMP_DIR}" ] && rm -rf "${TMP_DIR}"; }
trap cleanup EXIT

SRC_DIR=""
if [ -n "${SCRIPT_DIR}" ] && [ -d "${SCRIPT_DIR}/${APP_NAME}.app" ]; then
  SRC_DIR="${SCRIPT_DIR}"
  echo "==> Installing from local bundle: ${SRC_DIR}/${APP_NAME}.app"
else
  TMP_DIR="$(mktemp -d)"
  echo "==> Fetching latest release metadata from github.com/${REPO}..."
  ZIP_URL="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | sed -n 's/.*"browser_download_url":[[:space:]]*"\([^"]*macos-universal\.zip\)".*/\1/p' \
    | head -n 1)"
  if [ -z "${ZIP_URL}" ]; then
    echo "ERROR: Could not find macos-universal.zip in latest release of ${REPO}" >&2
    exit 1
  fi
  echo "==> Downloading ${ZIP_URL}"
  curl -fsSL -o "${TMP_DIR}/flickd.zip" "${ZIP_URL}"
  ditto -xk "${TMP_DIR}/flickd.zip" "${TMP_DIR}/unpacked"
  APP_FOUND="$(find "${TMP_DIR}/unpacked" -maxdepth 2 -name "${APP_NAME}.app" -type d | head -n 1)"
  if [ -z "${APP_FOUND}" ]; then
    echo "ERROR: ${APP_NAME}.app not found in downloaded archive" >&2
    exit 1
  fi
  SRC_DIR="$(dirname "${APP_FOUND}")"
fi

mkdir -p "${HOME}/Applications" "${CONFIG_DIR}" "${HOME}/Library/LaunchAgents" "${LOG_DIR}"

# Stop existing LaunchAgent before replacing binary
launchctl bootout "gui/$(id -u)" "${PLIST_DST}" 2>/dev/null || true
rm -rf "${APP_DIR}"
ditto "${SRC_DIR}/${APP_NAME}.app" "${APP_DIR}"
xattr -dr com.apple.quarantine "${APP_DIR}" 2>/dev/null || true

if [ ! -f "${CONFIG_DST}" ]; then
  if [ -f "${SRC_DIR}/config.example.json" ]; then
    cp "${SRC_DIR}/config.example.json" "${CONFIG_DST}"
  else
    cat > "${CONFIG_DST}" <<'JSON'
{
  "reverseMouseScroll": true,
  "reverseMouseHorizontalScroll": false,
  "swipeFingers": 3,
  "swipeThreshold": 0.05,
  "axisDominance": 1.6,
  "maxSwipeDuration": 0.75,
  "apps": {
    "com.google.Chrome": {
      "left":  { "key": "]", "modifiers": ["cmd", "shift"] },
      "right": { "key": "[", "modifiers": ["cmd", "shift"] },
      "up":    { "key": "t", "modifiers": ["cmd"] },
      "down":  { "key": "w", "modifiers": ["cmd"] }
    },
    "com.apple.Safari": {
      "left":  { "key": "]", "modifiers": ["cmd", "shift"] },
      "right": { "key": "[", "modifiers": ["cmd", "shift"] },
      "up":    { "key": "t", "modifiers": ["cmd"] },
      "down":  { "key": "w", "modifiers": ["cmd"] }
    }
  }
}
JSON
  fi
  echo "==> Created default config: ${CONFIG_DST}"
fi

cat > "${PLIST_DST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${BUNDLE_ID}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${APP_DIR}/Contents/MacOS/${BIN_NAME}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardErrorPath</key>
    <string>${LOG_FILE}</string>
    <key>StandardOutPath</key>
    <string>${LOG_FILE}</string>
</dict>
</plist>
PLIST

launchctl bootstrap "gui/$(id -u)" "${PLIST_DST}"

echo ""
echo "Installed ${APP_DIR} and started LaunchAgent (${BUNDLE_ID})."
echo ""
echo "Next step (first-time install):"
echo "  1. Open System Settings -> Privacy & Security -> Accessibility"
echo "  2. Add & enable: ${APP_DIR}"
echo "  3. Check logs:   tail -f ${LOG_FILE}"
echo "  4. Edit config:  ${CONFIG_DST} (reload via: pkill -HUP ${BIN_NAME})"
