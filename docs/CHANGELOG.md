# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/) 风格,版本号语义化。

## [Unreleased]

### Fixed

- **build.ps1 成功码误判**:`if (-not $code)` 把退出码 0(成功)当作假值,回退成 -1,
  导致已生成 exe 仍报 `[FAIL]`。改为仅在 `$null` 时回退到 `$LASTEXITCODE`。
- **只读 Base 导致 Ahk2Exe 退出码 49**:Ahk2Exe 先复制 Base 再写资源,只读 Base 会使
  `BeginUpdateResource` 失败。`build.ps1` 检测到只读 Base 时自动改用可写临时副本,
  不再修改用户的 AutoHotkey 安装目录。
- **Ahk2Exe 定位**:`-AhkDir` 缺少 `Compiler\Ahk2Exe.exe` 时,自动回退到用户级/常见安装目录
  (`%LocalAppData%\Programs\AutoHotkey` 等)。
- **错误提示**:Ahk2Exe 失败时按退出码给出可读提示(49/50/51/52/65)。
- **`-Clean` 误删模板**:`-Clean` 会递归清空 `dist\`,而 `dist\portable.flag.example`
  模板就在其中,导致 `-CopyRuntime` 报 `[SKIP]`。现在先读入模板,清空后写回。
- **`-CopyRuntime` 路径**:模板源从硬编码 `dist\` 改为 `$Source\dist\`,并增加 src==dst
  守卫,自定义 `-OutDir` 时不再错拷。

### Docs

- `INSTALL.md`:补充一键脚本用法、Ahk2Exe 安装受限网络的手动步骤、退出码 49 / -1 排查项。

## [1.2.0] - 2026-07-15

### Fixed / Improved（按 `docs/reviews/2026-07-15-windows-ahk-v2-review.md` 逐项落地）

- **剪贴板**：`GetClipboardSequenceNumber` 所有权；失败恢复前核对序列号；删除 `Fingerprint`/`lastSnapshot`；单次 `ClipboardAll` 快照
- **AutoCopy**：单一 debounce timer；busy 保留最新 pending；发送前 `RevalidateTarget`；`Clear` 失败中止
- **历史内存**：`HistoryItemMaxKb` / `HistoryTotalMaxMb` / `MaxSnapshotMb`
- **VirtualDesktop**：先撤 ready/指针再 `FreeLibrary`；默认 `FallbackMode=off`；删除无效 `probe`；去掉未用导出
- **Utils**：`LoadLibraryExW` + PE Machine(x64) 校验；错误 193 提示
- **x64**：启动 `A_PtrSize=8` 强制；Ahk2Exe Base 指令；`scripts/build.cmd`
- **路径**：默认配置 `%AppData%\ScreenPlus`，日志 `%LocalAppData%\ScreenPlus\logs`；`portable.flag` 便携
- **Tray**：去掉双重 Build；重载仅走 `App.ReloadAll`
- **PluginHost**：`Map` 名称键控；仅成功启动才 Shutdown
- **Loader**：默认不 Include ExamplePlugin
- **Config**：`GetInt`/`GetFloat`/`GetBool` 范围限制
- **Logger**：内存累计大小，减少每次 `FileGetSize`
- **ToolTip**：单一 hide timer；多显示器 center
- **复审修复**：移除 `IsSet(this.property)`；恢复按最终 copy sequence；剪贴板 owner 进程过滤；VD 不就绪不占 Alt 热键；Logger 同日切换目录生效

### Changed

- 版本号 1.2.0
- 移除 `RequireContentChange` 配置项

## [1.1.0] - 2026-07-15

### Fixed / Improved（对照审查报告全量补丁）

- **AutoCopy**：按鼠标下窗口进程过滤；debounce 只执行最后一次选区；成功判定基于清空后内容/格式变化；支持 `WaitForAnyData` / `ActivateTarget` / `RequireContentChange`
- **ClipboardManager**：`Init`/`Reload` 分离，重载不清历史；指纹与二进制 Size 估计；历史项可从托盘取用
- **VirtualDesktop**：钉死导出契约（见 ADR 0001）；`HotkeyDesktops` 可配置；`FallbackMode=probe|simulate|off`；支持 `Reload` 与热键重注册
- **TrayMenu**：关于可点击；状态总览；剪贴板历史菜单；统一走 `App.ReloadAll`（含 VD）
- **Plugin-ready**：`PluginHost` + `plugins/Loader.ahk` + `ExamplePlugin` 生命周期
- **Config**：DefaultMap 增补新键；缺失 ini 时优先复制模板
- **Logger**：跨日自动切换日志文件
- **ToolTip**：`[OK]`/`[ERR]` ASCII 前缀，避免字体乱码
- **文档**：ADR、selftest、INSTALL/README/CONTEXT 更新

### Added

- `modules/PluginHost.ahk`
- `plugins/Loader.ahk` / `ExamplePlugin.ahk`
- `scripts/selftest.ahk`
- `docs/adr/0001-virtualdesktop-accessor.md`

## [1.0.0] - 2026-07-15

### Added

- 模块化 AutoHotkey v2 架构与入口 `screen.ahk`
- Config / VirtualDesktop / ClipboardManager / AutoCopy / WindowFilter
- ToolTipManager / TrayMenu / Logger / Utils
- screen.ini、README、INSTALL、CHANGELOG、MIT LICENSE
- AGENTS.md / CONTEXT.md / 结构校验脚本
