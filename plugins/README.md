# Plugins

ScreenPlus 通过 **静态 Loader + PluginHost** 扩展，保持 AHK v2 `#Include` 可预测性。

## 约定

1. 插件源码放在本目录，例如 `MyPlugin.ahk`。
2. 在 `Loader.ahk` 中 `#Include MyPlugin.ahk`。
3. 插件文件末尾注册：

```ahk
PluginHost.Register(
    "MyPlugin",
    (cfg) => MyPlugin.Init(cfg),
    (*) => MyPlugin.Shutdown()
)
```

4. 主程序已包含：

```ahk
#Include modules\PluginHost.ahk
#Include plugins\Loader.ahk
```

5. 配置节建议：`[Plugin_MyPlugin]`（`PluginHost.ConfigSection("MyPlugin")`）。

## 生命周期

| 阶段 | 调用 |
|------|------|
| 脚本加载 | `Register`（可在 Logger 初始化前） |
| 启动 | `PluginHost.InitAll(Config)` |
| 托盘重载配置 | `PluginHost.ReloadAll`（Shutdown → Init） |
| 退出 | `PluginHost.ShutdownAll` |

单个插件异常会被宿主捕获，不拖垮主程序。

## 示例

- `ExamplePlugin.ahk`：默认关闭，ini `[Plugin_Example] Enabled=1` 开启日志演示。
