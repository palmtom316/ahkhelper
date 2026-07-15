# ScreenPlus Windows / AutoHotkey v2 专项代码审查

- **审查日期**：2026-07-15
- **修订日期**：2026-07-15（逐项核实；1.2.0 修订已落实，见文末状态）
- **审查范围**：`screen.ahk`、`screen.ini`、`modules/*.ahk`、`plugins/*.ahk`、`scripts/selftest.ahk`
- **审查视角**：Windows 10/11、AutoHotkey v2、Win32 剪贴板、DLL 生命周期、热键/定时器线程、托盘对象、长期内存占用
- **性质**：静态只读审查；未修改业务代码
- **核实基准**：本文件修订时仓库中的源码行号（见第 12 节）

## 1. 总体结论

当前项目模块边界清楚，主要功能链路完整。真正值得优先优化的不是静态 class、Map 或少量闭包本身，而是：

1. Windows 全局剪贴板的竞态与所有权判断；
2. 一次 AutoCopy 中多次完整 `ClipboardAll()` 带来的内存峰值；
3. DLL 卸载时悬空函数指针的短暂窗口；
4. 定时器、热键和插件的资源生命周期；
5. 剪贴板历史缺少总字节上限；
6. 仅 Windows x64 部署时仍未强制 64 位进程，且 `FallbackMode=probe` 逻辑无效。

发布前建议先完成 P0 项，再处理长期内存和结构简化。调整 Map、删几个静态字段等微优化不应优先于剪贴板与 DLL 生命周期问题。

---

## 2. P0：发布前建议修复

### 2.1 剪贴板操作存在 Windows 全局竞态

**核实状态：成立**

**位置：**

- `modules/AutoCopy.ahk:150-169`（Capture → Fingerprint → Clear → Fingerprint → Sleep → Send → Wait）
- `modules/AutoCopy.ahk:153,162`（`Clear()` 返回值未检查）
- `modules/AutoCopy.ahk:194-202`（失败/异常路径无条件 `Restore`）
- `modules/ClipboardManager.ahk:33-44,48-58,62-70`

当前流程：

```text
ClipboardAll → Fingerprint → Clear → Fingerprint → Sleep → Ctrl+C → ClipWait → 判断 → Restore
```

Windows 剪贴板是全系统共享资源，该流程不是原子操作。期间 Ditto、截图工具、Office 或其他应用可能写入剪贴板，导致：

- 把其他应用的写入误判为本次复制成功；
- AutoCopy 失败恢复时覆盖用户刚复制的新内容；
- `Clear()` 失败后仍继续，扩大误判范围。

补充：`Clear()` 中存在 `A_Clipboard := ""` → `A_Clipboard := ClipboardAll()` → `A_Clipboard := ""` 的奇怪序列（`modules/ClipboardManager.ahk:64-66`），中间一步可能引入额外剪贴板读写，建议一并简化为可靠清空。

#### 建议

使用 Win32 剪贴板序列号控制本次操作是否仍拥有剪贴板：

```ahk
DllCall("GetClipboardSequenceNumber", "UInt")
```

推荐流程：

1. 保存快照与 `sequenceBefore`；
2. 清空并确认序列号变化；清空失败则终止；
3. 发送 `Ctrl+C`，记录发送前序列号；
4. 只接受序列号再次变化的结果；
5. 恢复前再次检查序列号；
6. 仅当剪贴板仍是本操作控制的版本时恢复；
7. 快照、清空或恢复失败时终止本次操作。

---

### 2.2 AutoCopy 重复物化完整剪贴板，内存峰值过高

**核实状态：成立**

**位置：**

- `modules/AutoCopy.ahk:150` `Capture()` → `ClipboardAll()`
- `modules/AutoCopy.ahk:151` `baseline := Fingerprint()` → 再 `ClipboardAll()`
- `modules/AutoCopy.ahk:154` `emptyFp := Fingerprint()` → 再 `ClipboardAll()`
- `modules/AutoCopy.ahk:213` `IsCopySuccess` 内再 `Fingerprint()` → 再 `ClipboardAll()`
- `modules/ClipboardManager.ahk:9,35-36,96-99`（`lastSnapshot` + `Fingerprint`）

一次成功路径至少 4 次完整剪贴板物化；重试时 `IsCopySuccess` 还会继续调用 `Fingerprint()`。当剪贴板包含图片、Office 多格式对象、HTML、文件列表或延迟渲染格式时，内存峰值可能成倍上升。

同时，`ClipboardManager.lastSnapshot` 在 `Capture()` 成功后长期引用旧快照，直到下一次捕获或 `Shutdown()`。

#### 建议

- 删除 `Fingerprint()` 中的 `ClipboardAll()`；
- 用剪贴板序列号替代完整 Buffer 大小指纹；
- 每次 AutoCopy 只保留一份完整快照；
- 操作结束立即释放局部 `snapshot`；
- 删除全局 `lastSnapshot`，让调用方显式持有快照；
- 增加 `MaxSnapshotMb`；超过阈值时跳过 AutoCopy 或不做完整恢复。

**预期收益：** 大剪贴板场景的内存峰值可从多份副本降为约一份副本。

---

### 2.3 过滤窗口与实际接收 Ctrl+C 的窗口可能不同

**核实状态：成立**

**位置：**

- `modules/AutoCopy.ahk:116-129`（松开时取鼠标下 `hwnd`/进程并 debounce）
- `modules/AutoCopy.ahk:146-148`（可选 `WinActivate`，无等待/复核）
- `modules/AutoCopy.ahk:168`（普通 `Send("^c")`，目标是发送时前台窗口）

程序在鼠标松开时保存并过滤目标窗口，但延迟后使用普通 `Send("^c")`。实际接收方是发送时的前台窗口。如果用户在默认 120ms 延迟内切换焦点，命令可能发送给未经过白名单验证的应用。

#### 建议

复制前重新验证：

```text
IsWindow(hwnd)
→ 进程仍在白名单
→ WinExist("A") == hwnd
→ Send Ctrl+C
```

若启用 `ActivateTarget`：

1. 调用 `WinActivate`；
2. 使用短超时等待激活；
3. 再次检查前台窗口句柄；
4. 不一致则取消。

不建议默认强制激活窗口。还应考虑 Windows UIPI：普通权限脚本可能无法向管理员权限窗口发送输入。

---

### 2.4 DLL 卸载存在悬空函数指针窗口

**核实状态：成立**

**位置：**

- `modules/VirtualDesktop.ahk:150-158`（`Unload`：先 `FreeLibrary`，再清指针）
- `modules/VirtualDesktop.ahk:160-165`（`ShutdownBackend`：先 `Unload`，后 `ready := false`）

当前顺序：

```text
FreeLibrary
→ 清函数指针
→ ready=false / moveReady=false / mode=none
```

AHK 的 `Sleep`、托盘回调等可能允许热键线程介入。极端情况下，热键线程可能观察到 `ready=true` 与旧函数指针，但 DLL 已经卸载，从而调用无效地址。

补充：`Reload()`（`modules/VirtualDesktop.ahk:41-50`）会 `ShutdownBackend()` 重启后端；若 `hotkeyDesktops` 未变，不会在 Reload 内重注册热键，但后端指针已切换。`App.ReloadAll` 随后总会 `RegisterHotkeys()`，常态路径可覆盖；若未来去掉 App 侧注册，需由模块在 Reload 后统一发布状态与热键。

#### 建议

```text
进入短 Critical
→ ready=false
→ moveReady=false
→ mode=none
→ 保存 hModule 到局部变量
→ 清零函数指针和 hModule
→ FreeLibrary(局部 handle)
→ 退出 Critical
```

检查并记录 `FreeLibrary` 返回值。不要将 `Sleep`/`ClipWait`/`Send` 放入长期 `Critical`。

---

### 2.5 加强 DLL 搜索路径安全

**核实状态：成立**

**位置：** `modules/Utils.ahk:28-39`

当前使用：

```ahk
DllCall("LoadLibrary", "Str", fullPath, "Ptr")
```

完整路径比裸 DLL 名安全，但生产环境建议使用 `LoadLibraryExW` 并限制依赖 DLL 搜索目录，例如：

- `LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR`
- `LOAD_LIBRARY_SEARCH_DEFAULT_DIRS`

同时对 `A_LastError=193`（坏映像/架构不匹配）给出明确中文提示。

---

## 3. P1：内存与响应优化

### 3.1 剪贴板历史增加单项与总字节上限

**核实状态：成立**

**位置：**

- `modules/ClipboardManager.ahk:26-29`
- `modules/ClipboardManager.ahk:131-140`

当前只有 `HistoryMax` 条数限制，无单条字符/字节上限，无总字节上限。`HistoryMax` 也未做非负/上限 Clamp。

#### 建议配置

```ini
[Clipboard]
HistoryMax=30
HistoryItemMaxKb=512
HistoryTotalMaxMb=8
```

---

### 3.2 AutoCopy 使用单一 debounce timer

**核实状态：成立**

**位置：** `modules/AutoCopy.ahk:126-129`

每次拖选创建匿名单次计时器：

```ahk
SetTimer(() => AutoCopy.OnDebounceFire(token), -Max(delay, 1))
```

`debounceToken` 只让旧回调空操作，不会立即删除旧 timer。

#### 建议

使用单一静态回调，先 `SetTimer(cb, 0)` 取消，再 `SetTimer(cb, -delay)` 调度。

---

### 3.3 busy 时保留最新请求，而不是丢弃

**核实状态：成立**

**位置：** `modules/AutoCopy.ahk:132-137,140-142,203-204`

`OnDebounceFire` / `TryCopy` 在 `busy=true` 时直接返回，且 `finally` 不检查是否有更新的 pending generation，最新划选会丢失。

#### 建议

- `pendingRequest` 始终保存最新请求；
- `busy=true` 时只标记 `hasPending`；
- `finally` 中若 generation 已变化则重新调度。

---

### 3.4 配置值集中范围校验

**核实状态：部分成立**

已有：

- `HotkeyDesktops` 使用 `Utils.Clamp(..., 1, 9)`（`VirtualDesktop.ahk:58`）

缺少系统化 Clamp：

- `DelayMs` / `ClipWaitTimeout` / `RetryCount` / `RetryDelayMs`
- `HistoryMax` / `HistoryPreviewCount`
- `MaxFileKb` / `MinDragPixels`

建议在 `Config` 提供 `GetInt/GetFloat(..., min, max)`，避免模块散落校验。

---

### 3.5 避免托盘配置重载重复 Build

**核实状态：成立**

**位置：**

- `screen.ahk:46` `TrayMenu.Reload(Config)`（内部 `Build`）
- `modules/TrayMenu.ahk:111-128`（callback 路径结束后再次 `this.Rebuild()`）

`App.ReloadAll()` 已重建托盘；`ReloadConfig()` 末尾再次 `Rebuild()`，导致删除菜单两次、回调对象创建两套。

#### 建议

删除 `ReloadConfig()` 末尾的 `this.Rebuild()`。菜单重建只由 `App.ReloadAll()` / `TrayMenu.Reload()` 管理。

`ToggleAutoCopy()` 单独重建一次是合理的。

---

### 3.6 历史菜单项标识

**核实状态：部分成立（降级）**

**位置：**

- `modules/ClipboardManager.ahk:147-157`（摘要为 `"1. preview"`）
- `modules/TrayMenu.ahk:69-85`（菜单项 `"  " line`，闭包只绑 index）

原报告称“菜单项可能不唯一”。当前摘要已带 `A_Index ". "` 前缀，因此不同历史项在正常情况下菜单文本已不同；闭包也只捕获 index，未捕获全文。

仍建议：

- 固定展示格式 `#1 preview`；
- 避免未来改摘要格式后丢失唯一性；
- 超长预览截断策略保持稳定。

该项优先级从“中”降为“低”。

---

### 3.7 ToolTip 复用一个 timer

**核实状态：成立（低优先）**

**位置：** `modules/ToolTipManager.ahk:62-66`

每次提示创建闭包 timer。量通常不大，优先级低于 AutoCopy timer。

---

## 4. P1：结构简化

### 4.1 删除 baseline/Fingerprint/RequireContentChange 的复杂路径

**核实状态：成立**

**位置：**

- `modules/AutoCopy.ahk:151,154,212-234`
- `modules/ClipboardManager.ahk:96-122`
- `screen.ini` / `Config.DefaultMap` 中 `RequireContentChange`

文本模式在清空成功后，只要 `after["text"] != ""` 且相对 `emptyFp` 有变化，就会在 `IsCopySuccess` 前半段直接返回 true（约 224-229 行）。`RequireContentChange` 与 `baseline` 仅覆盖少见分支，却额外触发完整 `ClipboardAll()`。

#### 建议

以序列号 + 文本/任意数据存在性替代 `Fingerprint`/`HasChangedSince`/`baseline`。

---

### 4.2 删除全局 lastSnapshot

**核实状态：成立**

**位置：**

- `modules/ClipboardManager.ahk:9,35-36,48-49,202-203`
- `modules/AutoCopy.ahk:144,150,195,202`（调用方已持有局部 `snapshot`）

双重所有权增加隐式恢复风险，并延长大快照存活时间。

---

### 4.3 VirtualDesktop 热键重注册只由一层负责

**核实状态：成立**

**位置：**

- `modules/VirtualDesktop.ahk:41-48`（count 变化时模块内 `ReregisterHotkeys`）
- `screen.ahk:39-43`（`Reload` 后 App 再 `RegisterHotkeys`/`UnregisterHotkeys`）

当 `HotkeyDesktops` 变化时会双重重注册；当未变化时依赖 App 侧补一次。建议模块 `Reload()` 统一负责热键与后端状态，App 只调用 `Reload()`。

---

### 4.4 删除 TrayMenu 的重载兜底编排

**核实状态：成立**

**位置：** `modules/TrayMenu.ahk:113-124`

既支持注入 callback，又保留逐模块 Reload 兜底。`screen.ahk:84` 总会注入 callback，双路径易漂移。

#### 建议

callback 未设置时报错；唯一重载入口为 `App.ReloadAll()`。

---

### 4.5 空 Shutdown 不必为接口统一而保留

**核实状态：成立**

| 模块 | Shutdown 内容 |
|------|----------------|
| `AutoCopy` | 有实质：取消 debounce、注销热键 |
| `VirtualDesktop` | 有实质：注销热键 + 卸载 DLL |
| `ToolTipManager` | 有实质：Hide |
| `ClipboardManager` | 仅清 `lastSnapshot` |
| `Logger` | 空 |
| `TrayMenu` | 空 |
| `WindowFilter` | 空 |

建议仅资源型模块保留 `Shutdown`。

---

### 4.6 示例插件不默认编入生产脚本

**核实状态：成立**

**位置：** `plugins/Loader.ahk:10` 无条件 `#Include ExamplePlugin.ahk`

示例默认关闭业务逻辑，但仍注册并参与 Init/Reload/Shutdown。生产 Loader 建议默认注释该 Include。

---

### 4.7 PluginHost 改用名称键控 Map

**核实状态：成立**

**位置：** `modules/PluginHost.ahk:8-25,44-61`

- 数组存储，无同名去重；
- 无 Unregister；
- `ShutdownAll` 对所有带 `exitFn` 的条目调用退出，不区分是否 `ok` 成功启动；
- `ReloadAll = ShutdownAll + InitAll`，不清理重复注册。

当前静态 Loader 只注册一次，短期不会自然膨胀；但插件若在 Init/Reload 再次 Register，会增长。

---

## 5. P2：Windows 体验与稳定性

### 5.1 短临界区保护状态发布

**核实状态：建议保留（设计建议，非既有 bug 证明）**

适用于 pending 替换、busy/generation 更新、VD 后端指针发布/撤销。不要把 `Sleep`/`ClipWait`/`Send` 放入长期 Critical。

---

### 5.2 剪贴板锁定失败做有限重试

**核实状态：成立（缺失能力）**

`Capture`/`Clear`/`Restore` 失败后基本直接返回或继续，没有 10–20ms × 3 的有限重试。

---

### 5.3 多显示器 ToolTip 居中

**核实状态：成立**

**位置：** `modules/ToolTipManager.ahk:48-50`

```ahk
ToolTip(text, A_ScreenWidth // 2, A_ScreenHeight // 2)
```

使用主屏尺寸，不是鼠标/目标窗口所在显示器。鼠标模式无此问题。

---

### 5.4 管理员权限窗口给出明确提示

**核实状态：建议保留（设计建议）**

当前失败只记“复制失败”，无 UIPI/权限差异提示。不建议默认以管理员运行整个工具。

---

### 5.5 Logger 避免每条日志 FileGetSize

**核实状态：成立（修正行号）**

**位置：**

- `modules/Logger.ahk:52-61`（每次 `Write` 调用 `RotateIfNeeded`）
- `modules/Logger.ahk:73-77`（`FileGetSize`）

原报告写 `Logger.ahk:58` 为 `FileGetSize` 不准确；`:58` 是 `EnsureLogPath()`，`FileGetSize` 在 `:77`。

INFO 低频问题不大；DEBUG 高频时有额外元数据 I/O。可用内存 `currentSize` 近似累计，达阈值再实测。

---

## 6. 推荐的简化后核心流程

### 6.1 AutoCopy

```text
OnButtonUp
→ 校验拖拽
→ 保存 {hwnd, process, generation}
→ 重置单一 timer

Timer
→ 若 busy：保留 pending
→ 重新校验窗口/前台/白名单
→ Capture ClipboardAll（仅一次）
→ Clear 失败则结束
→ 记录 clipboard sequence
→ Send Ctrl+C
→ 等 sequence 变化
→ 检查文本或任意数据
→ 成功：释放 snapshot
→ 失败：若 sequence 仍归本操作，恢复 snapshot
→ 释放 snapshot
→ 若有 pending，重新调度
```

### 6.2 ClipboardManager 最小接口

```text
Capture()
Restore(snapshot)
ClearWithRetry()
GetSequenceNumber()
WaitForSequenceChange(oldSeq, timeout)
GetText()
PushHistory(text)
UseHistoryItem(index)
```

可删除：`Fingerprint`、`HasChangedSince`、`lastSnapshot` 及指纹用途的复杂 `EstimateSize`。

### 6.3 VirtualDesktop 最小状态

```text
enabled
mode
hModule
goToProc
moveProc
getCurrentProc
getCountProc
hotkeyCount
```

可删除当前未使用的 `fnIsWindowOnDesktopNumber`（解析于 `VirtualDesktop.ahk:120,157`，无业务调用）。

---

## 7. 不值得优先处理的微优化

以下对象占用远小于一次大型 `ClipboardAll()`，不应优先：

- `Config.cache` 的少量 Map；
- 默认白名单中的十几个字符串；
- 静态 class 本身；
- `StatusText()` 字符串拼接；
- `ToolTipManager.hideToken` 一个整数；
- 零到数个插件的注册表；
- 中文注释和文档文件体积。

---

## 8. 推荐实施顺序

| 顺序 | 优化 | 核实 | 预期收益 |
|------|------|------|----------|
| 1 | `GetClipboardSequenceNumber` + 恢复所有权检查 | 成立 | 防止误认和覆盖用户新剪贴板 |
| 2 | 删除 Fingerprint、重复 ClipboardAll、lastSnapshot | 成立 | 最大内存优化 |
| 3 | 复制前重新验证 hwnd、前台与权限 | 成立 | 防止输入发送给错误窗口 |
| 4 | VD 先撤状态再 FreeLibrary | 成立 | 消除潜在进程崩溃 |
| 5 | 单 timer + pending latest request | 成立 | 减少闭包并避免丢操作 |
| 6 | 历史单项/总字节上限 | 成立 | 控制长期内存 |
| 7 | 配置集中 Clamp | 部分 | 防止异常配置 |
| 8 | 去掉重复 Tray Build / 统一 VD 热键重注册 | 成立 | 简化生命周期 |
| 9 | PluginHost Map 去重、成功启动才 Shutdown | 成立 | 防止长期重载增长 |
| 10 | Logger size 缓存、多屏 Tooltip | 成立/低优先 | 体验优化 |
| 11 | x64 强制 + 固定 DLL + AppData 部署 | 成立 | 部署确定性 |

---

## 9. Windows 验证与压力测试

### 9.1 大剪贴板内存测试

- 复制 50–200 MB 图片、Office 对象或大文本；
- 观察 AutoCopy 前后 Working Set 与 Private Bytes；
- 操作结束后确认快照内存可回落；
- 确认未长期持有旧 ClipboardAll。

### 9.2 剪贴板竞争测试

AutoCopy 期间由 Ditto / PowerToys / 截图工具 / Office 连续写入剪贴板，验证：

- 不误认其他应用写入；
- 失败恢复不覆盖用户新内容；
- 剪贴板锁定短暂失败能有限重试。

### 9.3 配置重载压力测试

连续重载配置 500 次，观察：

- 进程句柄数；
- Private Bytes；
- timer / hotkey 是否增加；
- 托盘菜单是否重复；
- PluginHost 条目是否增长。

### 9.4 DLL 与热键竞争测试

持续按 `Alt+1/2/3`，同时重复重载配置，验证：

- 无悬空函数指针调用；
- 无进程崩溃；
- DLL 句柄不泄漏；
- 热键数量不增长。

### 9.5 推荐工具

- 任务管理器：Working Set；
- Process Explorer：Private Bytes、Handles；
- Windows Performance Recorder：事件与 I/O；
- `GetProcessHandleCount`：自动化句柄泄漏断言。

---

## 10. 验证边界与残余风险

本报告基于 Linux 环境下的静态代码审查，未执行：

```bat
AutoHotkey64.exe /ErrorStdOut scripts\selftest.ahk
Ahk2Exe.exe /in screen.ahk /out ScreenPlus.exe
```

也未在真实 Windows 10/11 环境执行热键竞争、真实剪贴板竞争、DLL 卸载压力、托盘重建压力与大剪贴板内存测试。

因此本报告不提供 Windows 运行或 Ahk2Exe 编译 PASS 结论。

---

## 11. Windows x64 专用评估

### 11.1 结论

若 ahkhelper 明确只运行于 **Windows AMD64（x64）**，没有根本性 ABI 问题，反而可以显著缩小兼容范围。

当前 VirtualDesktop 相关 DllCall 类型基本符合 Win64 ABI：

- `HWND`、模块句柄与函数地址使用 `Ptr`：正确（如 `VirtualDesktop.ahk:175,198`）；
- 桌面编号使用 `Int`：正确；
- Win64 只有统一的 x64 调用约定，无需区分 32 位 `stdcall` / `cdecl`。

但是，当前实现只是文档中写明 x64，运行时并没有真正强制 64 位 AHK 进程；部署路径、DLL 架构错误提示以及 VD fallback 仍有平台级问题。

---

### 11.2 启动时强制 64 位进程

**核实状态：成立（缺失能力）**

**位置：** `screen.ahk:4`

```ahk
#Requires AutoHotkey v2.0
```

无 `A_PtrSize` 检查。用户仍可能用 `AutoHotkey32.exe` 启动，随后 x64 DLL 加载失败并降级。

#### 建议

```ahk
if (A_PtrSize != 8) {
    MsgBox("ScreenPlus 仅支持 Windows x64 / AutoHotkey 64-bit。", "ScreenPlus", "Iconx")
    ExitApp(1)
}
```

64 位 AHK 进程的 `A_PtrSize` 为 **8**。

---

### 11.3 编译必须固定使用 64 位 Base

**核实状态：成立（文档有、构建未强制）**

`docs/INSTALL.md` 已说明 Unicode 64-bit / `AutoHotkey64.exe`，但仓库无 `scripts/build.cmd`、无 Ahk2Exe Base 指令强制。

建议增加固定构建脚本与 PE Machine 检查（`8664`）。

---

### 11.4 VirtualDesktopAccessor.dll 固定为 AMD64

**核实状态：成立（提示不足）**

`Utils.SafeLoadLibrary` 只返回通用 `LastError`，未特判 193，也未读取 PE Machine。

| Machine | 架构 | 处理 |
|---------|------|------|
| `0x8664` | AMD64 | 允许 |
| `0x014c` | x86 | 拒绝 |
| `0xAA64` | ARM64 | 拒绝 |

---

### 11.5 `FallbackMode=probe` 当前逻辑无效

**核实状态：成立**

**位置：**

- `modules/VirtualDesktop.ahk:211-220`（`GetCurrent` 仅 `mode="dll"` 时返回桌面号）
- `modules/VirtualDesktop.ahk:235-248`（fallback 中调用 `GetCurrent`，probe 分支）

进入 fallback 后 `mode="fallback"`，故 `GetCurrent()` 恒为 0，`probe` 永远走“请安装 DLL”，无法相对切换。

#### 建议

x64 发行包固定附带 DLL 时：删除 `UseDll` / `probe` / 键盘模拟；DLL 不可用仅禁用 VD。  
若仍保留无 DLL 模式：只保留 `simulate|off`，删除无效 `probe`。

---

### 11.6 不要假设 EXE 安装目录可写

**核实状态：成立**

当前配置与日志默认位于 `A_ScriptDir`：

- `screen.ahk:71` `Config.Init(A_ScriptDir "\screen.ini")`
- `screen.ahk:60-62` `A_ScriptDir "\logs\fatal.log"`
- `modules/Config.ahk:12` / `modules/Logger.ahk` 相对 `logs`

安装到 `C:\Program Files\ScreenPlus` 时，普通权限通常无法写入。

#### 建议目录

```text
程序：%ProgramFiles%\ScreenPlus\ScreenPlus.exe
配置：%AppData%\ScreenPlus\screen.ini
日志：%LocalAppData%\ScreenPlus\logs\
```

便携模式可用旁路 `portable.flag` 继续使用 `A_ScriptDir`。

---

### 11.7–11.10 x64 简化项

**核实状态：建议保留**

- 删除 x86/ARM64 兼容分支与文档模糊表达；
- 固定 DLL 后可删除 fallback 状态机，显著缩短 `VirtualDesktop.ahk`（当前约 350 行）；
- 当前 Win64 `DllCall` 类型与 `GetProcAddress(..., "AStr", ...)` 无需改变；
- 删除未使用的 `fnIsWindowOnDesktopNumber` 解析。

---

### 11.11–11.13 仍必须做的优化

**核实状态：成立**

- x64 不会消除 ClipboardAll 多份复制问题（见 2.2）；
- 序列号 API 返回 `DWORD`，声明保持 `UInt`；
- 使用 `LoadLibraryExW` + 正确卸载顺序（见 2.4、2.5）。

---

### 11.14 明确最低 Windows 版本

**核实状态：建议保留**

```text
支持：Windows 10 22H2 x64、Windows 11 23H2/24H2 x64
不支持：Windows 7/8、Windows ARM64、Windows Server、32 位 Windows
```

VirtualDesktopAccessor 兼容性受 Windows 功能更新影响，建议随包固定已测 DLL 版本。

---

### 11.15 推荐 x64 发布结构

```text
ScreenPlus\
  ScreenPlus.exe                 x64
  VirtualDesktopAccessor.dll     AMD64
  LICENSE
  portable.flag                  可选
```

默认数据目录：

```text
%AppData%\ScreenPlus\screen.ini
%LocalAppData%\ScreenPlus\logs\
```

---

### 11.16 Windows x64 最终判断

| 项目 | 结论 | 核实 |
|------|------|------|
| 当前 `Ptr` / `Int` DllCall 类型 | 基本正确 | 成立 |
| 能否运行于 Windows x64 | 可以 | 成立 |
| 是否强制 64 位 AHK 进程 | 未强制 | 成立 |
| x86/ARM64 DLL 误放提示 | 不足 | 成立 |
| `probe` fallback | 逻辑无效 | 成立 |
| Program Files 部署 | 配置/日志写入可能失败 | 成立 |
| x64 后是否仍需内存优化 | 需要 | 成立 |
| 是否应保留复杂 fallback | 固定 DLL 时建议删除 | 建议 |

**推荐路线：**将产品明确收敛为“Windows 10 22H2 / Windows 11 x64 + AutoHotkey x64 + 固定版本 x64 VirtualDesktopAccessor.dll”，删除无效 `probe`/复杂 simulate 兼容层，并把配置与日志迁移到 AppData。

---

## 12. 逐项核实记录

对照当前源码逐项核查后的结果：

| 编号 | 原结论 | 核实结果 | 修订说明 |
|------|--------|----------|----------|
| 2.1 | 剪贴板竞态 | **成立** | 补充 `Clear` 返回值未检查与 Clear 内部奇怪序列 |
| 2.2 | 多次 ClipboardAll | **成立** | 成功路径至少 4 次物化；行号已校准 |
| 2.3 | 过滤窗 ≠ 接收窗 | **成立** | 行号改为 116-129 / 146-148 / 168 |
| 2.4 | DLL 卸载顺序 | **成立** | FreeLibrary 先于 ready=false；补充 Reload 交互 |
| 2.5 | LoadLibrary 安全 | **成立** | 仍为 `LoadLibrary` |
| 3.1 | 历史无字节上限 | **成立** | 仅 HistoryMax |
| 3.2 | 多 timer 闭包 | **成立** | |
| 3.3 | busy 丢最新请求 | **成立** | |
| 3.4 | 配置未 Clamp | **部分成立** | HotkeyDesktops 已 Clamp |
| 3.5 | 托盘双重 Build | **成立** | |
| 3.6 | 历史菜单不唯一 | **部分成立** | 已有 `N. ` 前缀，降为低优先 |
| 3.7 | ToolTip timer | **成立** | 低优先 |
| 4.1 | Fingerprint/RCC 可删 | **成立** | 常见路径提前返回 |
| 4.2 | lastSnapshot 双所有权 | **成立** | |
| 4.3 | VD 热键双重注册 | **成立** | count 变化时双重；未变化依赖 App |
| 4.4 | Tray 兜底编排 | **成立** | |
| 4.5 | 空 Shutdown | **成立** | 表格式核实 |
| 4.6 | Example 默认 Include | **成立** | Loader:10 |
| 4.7 | PluginHost 数组 | **成立** | Shutdown 不区分 ok |
| 5.3 | 多屏 center | **成立** | |
| 5.5 | 每条日志 FileGetSize | **成立** | **修正**：FileGetSize 在 :77，非 :58 |
| 11.2 | 无 A_PtrSize 强制 | **成立** | |
| 11.5 | probe 无效 | **成立** | GetCurrent 仅 dll mode |
| 11.6 | Program Files 写权限 | **成立** | 配置/日志均 A_ScriptDir |

### 原报告中已修正的不准确点

1. **行号漂移/错位**
   - `AutoCopy.ahk:119` 不是过滤逻辑本身，而是跳过日志；过滤在 116-120。
   - `AutoCopy.ahk:194` 是 `} else {`，`Restore` 在 195。
   - `TrayMenu.ahk:66` 是 Default 关于菜单，历史菜单在 69-80。
   - `Logger.ahk:58` 是 `EnsureLogPath`，`FileGetSize` 在 77。
   - `VirtualDesktop.ahk:40` 为空行，`Reload` 从 41 开始。
2. **3.6 历史菜单唯一性偏重**  
   摘要已含序号前缀，不构成高风险唯一性缺陷。
3. **3.4 配置完全无范围限制**  
   不准确；`HotkeyDesktops` 已有 1–9 Clamp。
4. **Clear 行为**  
   原报告提到失败继续；现补充 Clear 内部三步序列本身也值得修复。

### 未在本轮推翻的核心风险

剪贴板竞态、多份 `ClipboardAll`、发送目标窗口漂移、DLL 卸载顺序、`probe` 无效、未强制 x64 进程、Program Files 写路径 —— 均与当前源码一致，维持 P0/P1 建议。
