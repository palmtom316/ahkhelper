# ScreenPlus

AutoHotkey v2 生产力工具包：虚拟桌面快捷键、划词自动复制（兼容 Ditto）、剪贴板管理、托盘控制与可扩展插件架构。

**版本：** 1.2.0（仅 Windows x64）

## 功能

| 功能 | 说明 |
|------|------|
| 虚拟桌面 | `Alt+1..N` 切换；`Alt+Shift+1..N` 移窗（需 x64 DLL）；默认无 DLL 则禁用 |
| AutoCopy | debounce → 重验窗口 → 序列号所有权 → `Ctrl+C` → 失败安全恢复 |
| 剪贴板 | 单次 `ClipboardAll` 快照、历史条数+字节上限、托盘取用 |
| 配置 | 默认 `%AppData%\ScreenPlus\screen.ini`；`portable.flag` 便携 |
| 日志 | 默认 `%LocalAppData%\ScreenPlus\logs\` |
| 托盘 | AutoCopy 开关、历史、状态、关于；重载走 `App.ReloadAll` |
| 插件 | `PluginHost` Map + `plugins/Loader.ahk`（默认不加载示例） |

## 快捷键

| 快捷键 | 动作 |
|--------|------|
| `Alt+1` … `Alt+N` | 切换到虚拟桌面 N（默认 N=3） |
| `Alt+Shift+1` … `N` | 将当前窗口移到桌面 N（需 DLL） |
| 鼠标左键拖选 | 在白名单应用中自动复制选中内容 |

## 目录结构

```
ahkhelper/                 # 仓库根（产品名 ScreenPlus）
  screen.ahk               # 入口 + App.ReloadAll
  screen.ini
  modules/
    Config.ahk
    VirtualDesktop.ahk
    ClipboardManager.ahk
    AutoCopy.ahk
    WindowFilter.ahk
    TrayMenu.ahk
    ToolTipManager.ahk
    Logger.ahk
    Utils.ahk
    PluginHost.ahk
  plugins/
    Loader.ahk
    ExamplePlugin.ahk
  docs/
    SPEC.md
    INSTALL.md
    CHANGELOG.md
    adr/
  scripts/
    verify_structure.sh
    selftest.ahk
  logs/
```

## 快速开始

1. 安装 [AutoHotkey v2](https://www.autohotkey.com/)。
2. （推荐）放置 [VirtualDesktopAccessor.dll](https://github.com/Ciantic/VirtualDesktopAccessor)（见 [ADR 0001](docs/adr/0001-virtualdesktop-accessor.md)）。
3. 双击 `screen.ahk`，或见 [docs/INSTALL.md](docs/INSTALL.md)。
4. 编辑 `screen.ini` 后：托盘 → **重载配置**。

## AutoCopy 流程

```
LButton 拖选 → 单一 debounce timer
  → 重验 hwnd / 白名单 / 前台
  → Capture 一次 ClipboardAll（有大小上限）
  → Clear（失败则中止）
  → 记录 sequence → Ctrl+C → 等待 sequence 变化
  → 成功：历史 + Ditto 可记录；释放快照
  → 失败：仅当 sequence 仍属本操作时 Restore
```

相关 ini：`WaitForAnyData`、`ActivateTarget`、`FilterMode`、`MaxSnapshotMb`。

## 虚拟桌面

- 仅 x64 `VirtualDesktopAccessor.dll`（PE `0x8664`）
- 必需导出：`GoToDesktopNumber`
- 移窗导出：`MoveWindowToDesktopNumber`
- `FallbackMode`：`off`（默认）/ `simulate`

## 默认白名单

`WINWORD.EXE`、`EXCEL.EXE`、`POWERPNT.EXE`、`Code.exe`、`Obsidian.exe`、`Typora.exe`、`notepad++.exe`、`chrome.exe`、`msedge.exe`、`firefox.exe`、`Acrobat.exe`、`FoxitPDFReader.exe`、`WeChat.exe`

## 插件

见 [plugins/README.md](plugins/README.md)。主程序已 `#Include plugins\Loader.ahk`。

## 验证

```bash
# Linux/mac 结构校验
./scripts/verify_structure.sh

# Windows AHK 契约自检
AutoHotkey64.exe /ErrorStdOut scripts\selftest.ahk
```

## 编译

Ahk2Exe 编译 `screen.ahk`；同目录保留 `screen.ini` 与 DLL。详见 [docs/INSTALL.md](docs/INSTALL.md)。

## 开发约定

- 仅 AutoHotkey v2；中文注释；`PascalCase` 方法 / `camelCase` 变量
- 领域语言：`CONTEXT.md`；架构决策：`docs/adr/`
- Agent：`AGENTS.md`

## 许可证

MIT — 见 [LICENSE](LICENSE)。
