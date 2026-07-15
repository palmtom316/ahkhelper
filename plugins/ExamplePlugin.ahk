; ExamplePlugin.ahk - 插件宿主示例（默认空操作，可作模板）

class ExamplePlugin {
    static enabled := false

    static Init(cfg) {
        ; 默认关闭：需要演示时在 ini 设置 [Plugin_Example] Enabled=1
        section := PluginHost.ConfigSection("Example")
        this.enabled := Utils.ToBool(cfg.Get(section, "Enabled", "0"), false)
        if this.enabled
            Logger.Info("ExamplePlugin 已启用（示例）")
        return true
    }

    static Shutdown() {
        if this.enabled
            Logger.Info("ExamplePlugin 退出")
    }
}

; 使用 fat-arrow 绑定，避免方法引用丢失 this
PluginHost.Register(
    "Example",
    (cfg) => ExamplePlugin.Init(cfg),
    (*) => ExamplePlugin.Shutdown()
)
