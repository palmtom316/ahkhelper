# Windows/AHK v2 审查落实状态

- 日期：2026-07-15
- 对应报告：`2026-07-15-windows-ahk-v2-review.md`
- 版本：ScreenPlus 1.2.0

## 已落实

- 剪贴板 sequence 所有权与 owner 进程过滤
- 失败仅在当前 sequence 仍属本操作时恢复
- 删除 Fingerprint / lastSnapshot；旧剪贴板只 Capture 一次
- any-data 判定使用 ClipWait，不再重复物化新 ClipboardAll
- 单一 debounce timer；busy 保留 pending 最新请求
- 发送前重验 hwnd / 前台 / 白名单
- 历史单项、总字节与快照上限
- VirtualDesktop 先撤状态/指针再 FreeLibrary
- VD 未 ready 不占 Alt 数字热键；moveReady 才注册 Alt+Shift
- LoadLibraryExW、AMD64 PE 检查、x64 进程强制
- 默认 FallbackMode=off；删除 probe
- 配置迁移 AppData，日志迁移 LocalAppData；支持 portable.flag
- Logger 同日修改目录后重建 logPath
- Config 数值 Clamp
- Tray 单一 ReloadAll 路径，无双重 Build
- PluginHost 名称 Map，成功启动才 Shutdown
- 示例插件默认不加载
- ToolTip 单 timer 与多屏居中
- 静态属性使用 false 哨兵，不使用 IsSet(this.property)

## 验证

- `./scripts/verify_structure.sh`：PASS
- Linux 静态残留扫描：PASS
- Windows `scripts/selftest.ahk`：待运行
- Ahk2Exe x64 编译：待运行
- 大剪贴板/竞争/重载/DLL 热键压力测试：待运行

## 发布门槛

在 Windows x64 执行：

```bat
AutoHotkey64.exe /ErrorStdOut scripts\selftest.ahk
AutoHotkey64.exe /ErrorStdOut screen.ahk
scripts\build.cmd
```

并完成报告第 9 节压力测试后，方可标记 production PASS。
