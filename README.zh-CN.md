# flickd

[English](README.md) | 简体中文

极简、无 GUI、超低内存占用（实测物理内存仅 **~9 MB**、空闲 CPU `0.0%`、无菜单栏图标）的 macOS 原生 Swift 守护进程，用于替代 BetterTouchTool 的两个核心日常功能：

1. **触控板三指轻扫手势（按 App 生效）**：默认在 **Google Chrome** 与 **Safari** 下生效：
   - 三指向右轻扫 → `⇧⌘[`（上一个标签页）
   - 三指向左轻扫 → `⇧⌘]`（下一个标签页）
   - 三指向上轻扫 → `⌘T`（新建标签页）
   - 三指向下轻扫 → `⌘W`（关闭当前标签页）
2. **外接普通鼠标独立反转滚轮**：仅对非连续滚轮（`scrollWheelEventIsContinuous == 0`）反转垂直滚动，不影响触控板与 Magic Mouse 的自然滚动方向。

## 特点

- **极致轻量**：单个约 124 KB 原生 Swift 编译产物，Activity Monitor 同口径物理内存（`footprint`）约 **9 MB**，无脚本虚拟机、无 WebView、无多余子进程。
- **防误触设计**：要求三指沿主轴同向移动且在限定时间内完成；超过三指（如四指切桌面/调度中心）会自动锁定直至全部抬手，绝不误触发 `⌘W`。
- **热重载与休眠自恢复**：监听 `NSWorkspace` 休眠唤醒事件自动重挂触控板与 `CGEventTap`，支持 `SIGHUP` 热加载配置。

## 环境要求

- macOS（Apple Silicon 或 Intel）+ Xcode Command Line Tools（`swiftc`）
- **系统设置 → 触控板 → 更多手势**：将调度中心与切换全屏 App 设为 **四指**（或关闭），避免与三指手势冲突。

## 安装与常用命令

```bash
git clone https://github.com/AsIsacy/flickd.git && cd flickd
make install    # 编译、打包无头 ~/Applications/Flickd.app、签名并注册 LaunchAgent 开机自启
make status     # 查看运行状态与内存占用
make reload     # 热加载 ~/.config/flickd/config.json（发送 SIGHUP）
make restart    # 重启守护进程
make logs       # 查看 ~/Library/Logs/flickd.log
make uninstall  # 停止并移除 LaunchAgent 与 ~/Applications/Flickd.app
```

### 授予辅助功能权限

执行 `make install` 后，打开 **系统设置 → 隐私与安全性 → 辅助功能**，点击 `+` 添加 `~/Applications/Flickd.app` 并打开开关。`flickd` 每 3 秒自动检测权限，勾选后立刻生效，无需重启。

## 配置文件

编辑 `~/.config/flickd/config.json` 后运行 `make reload`（或 `pkill -HUP flickd`）即可生效：

| 配置项 | 默认值 | 说明 |
|---|---:|---|
| `reverseMouseScroll` | `true` | 是否反转外接普通鼠标垂直滚轮 |
| `reverseMouseHorizontalScroll` | `false` | 是否反转外接普通鼠标水平滚轮 |
| `swipeFingers` | `3` | 手势指数量（`2`～`5`） |
| `swipeThreshold` | `0.05` | 触发阈值（触控板归一化距离 `0.0`～`1.0`），越小越灵敏 |
| `axisDominance` | `1.6` | 主轴方向比，防止斜向滑动误触 |
| `maxSwipeDuration` | `0.75` | 单次滑动最长耗时（秒），防止手指搭在触控板上慢漂移误触 |
| `apps` | Chrome / Safari | 按 `CFBundleIdentifier` 映射 `left` / `right` / `up` / `down` 快捷键 |

## 许可协议

[MIT](LICENSE)
