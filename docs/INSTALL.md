# ScreenPlus 安装指南

## 环境要求

- **Windows 10 22H2 / Windows 11 x64 only**（`A_PtrSize=8`，拒绝 32 位 AHK）
- [AutoHotkey v2.0+](https://www.autohotkey.com/) **64-bit**
- （推荐）[VirtualDesktopAccessor.dll](https://github.com/Ciantic/VirtualDesktopAccessor/releases) **x64**  
  契约见 [adr/0001-virtualdesktop-accessor.md](adr/0001-virtualdesktop-accessor.md)

## 配置与日志路径

| 模式 | 配置 | 日志 |
|------|------|------|
| 默认 | `%AppData%\ScreenPlus\screen.ini` | `%LocalAppData%\ScreenPlus\logs\` |
| 便携 | 脚本目录 `screen.ini` | 脚本目录 `logs\` |

便携：在 exe/脚本旁放置空文件 `portable.flag`。

## 源码运行

1. 解压/克隆到例如 `C:\Tools\ScreenPlus`。
2. 确认 `screen.ahk`、`screen.ini`、`modules\`、`plugins\Loader.ahk` 存在。
3. 运行：

```bat
"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" screen.ahk
```

4. 托盘出现图标；启动提示可能带 `(VD降级)` 表示未加载 DLL。

## VirtualDesktopAccessor.dll

| 场景 | 行为 |
|------|------|
| 有 DLL 且导出齐全 | `mode=dll`，切换+移窗可用 |
| 有 DLL 但缺 Move 导出 | 切换可用，移窗提示不可用 |
| `FallbackMode=off`（默认） | 无 DLL 时禁用 VD |
| `FallbackMode=simulate` | Win+Ctrl 方向键盲切（不推荐） |

```ini
[VirtualDesktop]
UseDll=1
DllPath=
HotkeyDesktops=3
FallbackMode=off
```

## 开机自启

- 启动文件夹：`shell:startup` 放入 `screen.ahk` 快捷方式  
- 或任务计划：登录时启动 `AutoHotkey64.exe` + `screen.ahk` 全路径

## Ahk2Exe 编译

1. 打开 Ahk2Exe，Source=`screen.ahk`，Base=Unicode 64-bit。  
2. 输出如 `ScreenPlus.exe`。  
3. 与 exe 同目录放置：

| 文件 | 说明 |
|------|------|
| `screen.ini` | 配置（可首次自动生成默认键） |
| `VirtualDesktopAccessor.dll` | 可选 |

模块与插件经 `#Include` 编入主脚本，一般**不必**再拷 `modules\`。

```bat
Ahk2Exe.exe /in screen.ahk /out ScreenPlus.exe /base "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
```

## 验证清单（Windows）

```bat
:: 契约自检（退出码 0 为通过）
"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut scripts\selftest.ahk

:: 语法加载主脚本（需手动退出托盘）
"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut screen.ahk
```

手工冒烟：

1. Chrome/Code 划选 → 提示已复制，Ditto 有记录  
2. 非白名单进程划选 → 不复制  
3. `Alt+1/2/3` 切桌面（有 DLL）  
4. `Alt+Shift+1` 移窗（有 DLL）  
5. 托盘改 ini → 重载配置 → VD/AutoCopy 状态更新  
6. 托盘剪贴板历史可点  

## 与 Ditto

成功复制后为正常剪贴板写入，Ditto 可记录；失败时 Restore `ClipboardAll`，避免脏历史。

## 卸载

托盘退出 → 删除启动项 → 删除目录。日志在 `logs\`。

## 故障排查

| 现象 | 处理 |
|------|------|
| VD 降级 / 移窗提示 | 放置匹配架构的 DLL；看托盘「状态总览」 |
| 划词不复制 | 检查鼠标下进程是否在白名单；增大 `DelayMs` |
| 假成功/假失败 | 检查目标窗口焦点、`WaitForAnyData` 与日志中的 sequence 信息 |
| 启动失败 | 查看 `logs\fatal.log` 与当日 log |
