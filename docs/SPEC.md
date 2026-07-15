
# ScreenPlus Codex Specification

## Objective
Build a production-quality AutoHotkey v2 productivity toolkit.

### Core Features
- Preserve existing virtual desktop shortcuts:
  - Alt+1/2/3
  - Alt+Shift+1/2/3
- AutoCopy for selected content (compatible with Ditto)
- Clipboard manager using ClipboardAll()
- Modular architecture
- INI configuration
- Tray menu
- Logging
- Plugin-ready

## Architecture
screenplus/
  screen.ahk
  screen.ini
  README.md
  LICENSE
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
  plugins/
  docs/

## AutoCopy
Workflow:
Mouse selection -> delay -> whitelist filter -> Ctrl+C ->
ClipWait -> retry(optional) -> success -> Ditto records.
On failure restore ClipboardAll().

Whitelist by default:
WINWORD.EXE
EXCEL.EXE
POWERPNT.EXE
Code.exe
Obsidian.exe
Typora.exe
notepad++.exe
chrome.exe
msedge.exe
firefox.exe
Acrobat.exe
FoxitPDFReader.exe
WeChat.exe

## Requirements
- AutoHotkey v2 only
- Chinese comments
- No duplicated code
- PascalCase functions
- camelCase variables
- Handle DLL/file errors safely
- Compile with Ahk2Exe
