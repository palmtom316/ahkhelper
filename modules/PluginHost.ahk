; PluginHost.ahk - 名称键控插件宿主

class PluginHost {
    static plugins := Map()  ; name -> {name, initFn, exitFn, ok, error, started}
    static started := false

    static Register(name, initFn, exitFn := false) {
        if (name = "" || !initFn)
            return false
        if this.plugins.Has(name) {
            try Logger.Warn("PluginHost 重复注册，替换: " name)
        }
        this.plugins[name] := {
            name: name,
            initFn: initFn,
            exitFn: exitFn,
            ok: false,
            error: "",
            started: false
        }
        try Logger.Info("PluginHost 已注册插件: " name)
        return true
    }

    static InitAll(cfg) {
        this.started := true
        for name, entry in this.plugins {
            try {
                result := entry.initFn.Call(cfg)
                entry.ok := (result = "" || result = true || result = 1)
                entry.started := entry.ok
                entry.error := ""
                Logger.Info("插件启动 " name " ok=" entry.ok)
            } catch as err {
                entry.ok := false
                entry.started := false
                entry.error := err.Message
                Logger.Error("插件启动失败 " name ": " err.Message)
            }
        }
        return true
    }

    static ShutdownAll() {
        names := []
        for name, entry in this.plugins
            names.Push(name)
        ; 逆序
        i := names.Length
        while (i >= 1) {
            name := names[i]
            entry := this.plugins[name]
            if entry.started && entry.exitFn {
                try entry.exitFn.Call()
                catch as err {
                    Logger.Warn("插件退出异常 " name ": " err.Message)
                }
            }
            entry.started := false
            i -= 1
        }
        this.started := false
    }

    static ReloadAll(cfg) {
        this.ShutdownAll()
        this.InitAll(cfg)
    }

    static Count() {
        return this.plugins.Count
    }

    static StatusText() {
        okCount := 0
        for name, entry in this.plugins {
            if entry.ok
                okCount += 1
        }
        return "Plugins registered=" this.plugins.Count " ok=" okCount
    }

    static ConfigSection(name) {
        return "Plugin_" name
    }
}
