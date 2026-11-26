# flickd

English | [简体中文](README.zh-CN.md)

An ultra-lightweight, headless native macOS Swift daemon (**~9 MB RAM**, `0.0%` idle CPU, zero GUI / zero menu bar icon) that replaces BetterTouchTool for two everyday input needs:

1. **Per-app 3-finger trackpad swipes** (pre-configured for **Google Chrome** and **Safari**):
   - 3-finger swipe right → `⇧⌘[` (Previous tab)
   - 3-finger swipe left → `⇧⌘]` (Next tab)
   - 3-finger swipe up → `⌘T` (New tab)
   - 3-finger swipe down → `⌘W` (Close tab)
2. **Independent external mouse scroll reversal**: Reverses vertical scrolling only for discrete scroll-wheel mice (`scrollWheelEventIsContinuous == 0`), leaving Apple Trackpad and Magic Mouse natural scrolling untouched.

## Why `flickd`?

- **Tiny footprint**: Single ~124 KB native Swift binary, **~9 MB** physical memory footprint (Activity Monitor `footprint`), no Electron, no scripting VM, no helper subprocesses.
- **No accidental triggers**: Requires coherent multi-finger motion along the dominant axis within a time window; 4+ finger gestures (Mission Control / Spaces) lock out 3-finger detection until all fingers lift.
- **Zero-allocation hot path**: Built directly on macOS `MultitouchSupport` + a single `CGEventTap` for scroll wheel events, with sleep/wake recovery and `SIGHUP` hot config reload.

## Requirements

- macOS on Apple Silicon or Intel with Xcode Command Line Tools (`swiftc`)
- System Settings → **Trackpad → More Gestures**: set Mission Control / Swipe between full-screen apps to **4 fingers** (or off) so 3-finger swipes are free.

## Install & Usage

### Option 1: Prebuilt Universal Release (Apple Silicon & Intel)

```bash
curl -fsSL https://raw.githubusercontent.com/AsIsacy/flickd/main/install.sh | bash
```

Or download `Flickd-v*-macos-universal.zip` from [GitHub Releases](https://github.com/AsIsacy/flickd/releases), unzip, and run `./install.sh`.

> **Note:** Prebuilt releases are ad-hoc signed (no paid Apple Developer ID). `install.sh` automatically clears the macOS quarantine attribute (`xattr -dr com.apple.quarantine ~/Applications/Flickd.app`).

To uninstall:

```bash
curl -fsSL https://raw.githubusercontent.com/AsIsacy/flickd/main/install.sh | bash -s -- --uninstall
```

### Option 2: Build from Source

```bash
git clone https://github.com/AsIsacy/flickd.git && cd flickd
make install    # Build, package headless ~/Applications/Flickd.app, codesign, and start LaunchAgent
make status     # Check daemon status and memory usage
make reload     # Hot-reload ~/.config/flickd/config.json (sends SIGHUP)
make restart    # Restart the LaunchAgent
make logs       # View ~/Library/Logs/flickd.log
make uninstall  # Stop and remove LaunchAgent and ~/Applications/Flickd.app
```

### Grant Accessibility Permission

After `make install`, open **System Settings → Privacy & Security → Accessibility**, add `~/Applications/Flickd.app`, and enable it. `flickd` checks for permission every 3 seconds and activates automatically once granted—no restart required.

## Configuration

Edit `~/.config/flickd/config.json` and run `make reload` (or `pkill -HUP flickd`):

```json
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
```

| Option | Default | Description |
|---|---:|---|
| `reverseMouseScroll` | `true` | Reverse vertical scrolling for non-continuous external mice |
| `reverseMouseHorizontalScroll` | `false` | Reverse horizontal scrolling for external mice |
| `swipeFingers` | `3` | Number of fingers for swipe gestures (`2`–`5`) |
| `swipeThreshold` | `0.05` | Normalized trackpad distance (`0.0`–`1.0`); lower is more sensitive |
| `axisDominance` | `1.6` | Minimum primary-to-secondary axis ratio to prevent diagonal misfires |
| `maxSwipeDuration` | `0.75` | Max seconds from touch start to trigger; prevents slow drift misfires |
| `apps` | Chrome & Safari | Map of macOS `CFBundleIdentifier` → `left` / `right` / `up` / `down` shortcuts |

## License

[MIT](LICENSE)
