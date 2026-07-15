# CONTEXT.md — ScreenPlus Domain Language

## Purpose

Windows 生产力辅助：在不打断工作流的前提下，提供虚拟桌面导航与划词自动复制。

## Terms

| Term | Meaning |
|------|---------|
| ScreenPlus | 本工具产品名 |
| Virtual Desktop (VD) | Windows 虚拟桌面；用户编号从 1 开始 |
| AutoCopy | 鼠标划选后自动发送 Ctrl+C 的功能 |
| ClipboardAll | AHK 完整剪贴板快照（含多格式），用于备份/恢复 |
| WindowFilter | 按进程名白名单/黑名单决定是否 AutoCopy |
| Ditto | 第三方剪贴板管理器；AutoCopy 成功后应能被其记录 |
| FallbackMode | `off`（默认，无 DLL 禁用 VD）/ `simulate`（键盘盲切） |
| ConfigDir | 默认 `%AppData%\ScreenPlus`；便携模式为脚本目录 |
| SequenceNumber | `GetClipboardSequenceNumber`，用于 AutoCopy 所有权判定 |
| PluginHost | 插件注册与 Init/Shutdown/Reload 宿主 |
| Loader | `plugins/Loader.ahk` 静态 Include 清单 |
| Debounce | AutoCopy 在 DelayMs 内多次划选只执行最后一次 |

## Invariants

1. **仅 AHK v2** — 不使用 v1 命令语法。
2. **剪贴板安全** — AutoCopy 失败必须尝试恢复进入前的 `ClipboardAll`。
3. **热键兼容** — `Alt+1..N` 与 `Alt+Shift+1..N`（N=`HotkeyDesktops`，默认 3）。
4. **配置可重载** — `App.ReloadAll` 覆盖 VD / AutoCopy / Filter / Logger / Tray / Plugins。
5. **DLL 可选** — 缺少 x64 DLL 时默认禁用 VD（`FallbackMode=off`），不崩溃退出。
6. **单实例** — `#SingleInstance Force`。
7. **过滤目标** — AutoCopy 按鼠标下窗口过滤，发送前重验前台/句柄。
8. **剪贴板安全** — 失败恢复前核对序列号，避免覆盖他人写入。
9. **仅 x64** — `A_PtrSize=8`，AMD64 DLL。
10. **插件隔离** — 单插件异常不得中断主程序启动。

## Module ownership

| Module | Owns |
|--------|------|
| Config | INI 路径、缓存、DefaultMap |
| Logger | 文件日志级别、按日/大小轮转 |
| Utils | 路径、列表、进程/鼠标窗口、LoadLibrary |
| WindowFilter | 进程允许判定 |
| ClipboardManager | 快照/恢复/指纹/文本历史 |
| AutoCopy | 划选 debounce 与复制状态机 |
| VirtualDesktop | 桌面切换/移窗、DLL 契约、热键 |
| ToolTipManager | UI 提示 |
| PluginHost | 插件注册与生命周期 |
| TrayMenu | 托盘交互 |
| screen.ahk / App | 组装、`ReloadAll`、退出 |

## Out of scope (v1.x)

- 跨机器同步
- 完整 GUI 设置中心（以 INI + 托盘为主）
- 自动下载 DLL
- 完整剪贴板历史 UI（托盘摘要 + 内存历史即可）
