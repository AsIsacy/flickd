# flickd

极简、无 GUI、超低内存占用的 macOS 原生 Swift 守护进程，替代 BetterTouchTool 的两个核心日常功能：

1. **触控板三指轻扫手势（按 App 生效）**：默认仅在 **Google Chrome** 与 **Safari** 下生效：
   - 三指向右轻扫 → `⇧⌘[`（上一个标签页）
   - 三指向左轻扫 → `⇧⌘]`（下一个标签页）
   - 三指向上轻扫 → `⌘T`（新建标签页）
   - 三指向下轻扫 → `⌘W`（关闭当前标签页）
2. **外接普通鼠标独立反转滚轮**：仅对非连续滚轮（`scrollWheelEventIsContinuous == 0`）反转垂直滚动，不影响触控板与 Magic Mouse。

## 配置文件

`~/.config/flickd/config.json`（修改后运行 `make reload` 或 `pkill -HUP flickd` 热加载，无需重启）：

- `reverseMouseScroll`: 是否反转外接鼠标垂直滚轮（默认 `true`）
- `reverseMouseHorizontalScroll`: 是否反转外接鼠标水平滚轮（默认 `false`）
- `swipeFingers`: 手势指数量（默认 `3`；超过该指数量如 4 指切桌面会自动锁定，绝不误触发）
- `swipeThreshold`: 触发阈值，触控板归一化距离 `0.0 ~ 1.0`（默认 `0.05`，调小更灵敏、调大更防误触）
- `axisDominance`: 主轴方向比（默认 `1.6`，防止斜向滑动误触）
- `maxSwipeDuration`: 单次滑动最长耗时秒数（默认 `0.75`，防止手指搭在触控板上慢漂移误触）
- `apps`: 按 `CFBundleIdentifier` 映射 `left` / `right` / `up` / `down` 快捷键

## 常用命令

```bash
git clone https://github.com/AsIsacy/flickd.git && cd flickd
make install    # 编译、打包无头 Flickd.app、签名并注册 LaunchAgent 开机自启
make status     # 查看运行状态与内存占用
make reload     # 热加载 ~/.config/flickd/config.json
make restart    # 重启守护进程
make logs       # 查看 ~/Library/Logs/flickd.log
make uninstall  # 停止并移除 LaunchAgent 与 ~/Applications/Flickd.app
```

> 实测常驻物理内存仅 **~9 MB**（Activity Monitor 同口径 `footprint`），空闲 CPU `0.0%`，无 GUI / 无菜单栏图标。

## 权限说明

首次安装后需在 **系统设置 → 隐私与安全性 → 辅助功能** 中勾选 `~/Applications/Flickd.app`（`flickd` 每 3 秒自动检测权限，勾选后立刻生效，无需重启）。
