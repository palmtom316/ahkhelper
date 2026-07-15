; WindowFilter.ahk - 进程白名单/黑名单

class WindowFilter {
    static mode := "whitelist"
    static whitelist := []
    static blacklist := []

    static Init(cfg) {
        this.Reload(cfg)
        Logger.Info("WindowFilter 初始化 " this.Describe())
        return true
    }

    static Reload(cfg) {
        this.mode := StrLower(cfg.Get("AutoCopy", "FilterMode", "whitelist"))
        if (this.mode != "whitelist" && this.mode != "blacklist" && this.mode != "off")
            this.mode := "whitelist"
        this.whitelist := Utils.ParseList(cfg.Get("WindowFilter", "Whitelist", ""))
        this.blacklist := Utils.ParseList(cfg.Get("WindowFilter", "Blacklist", ""))
        return true
    }

    static IsAllowed(processName := "", mode := "", whitelist := 0, blacklist := 0) {
        name := (processName = "") ? Utils.GetActiveProcessName() : processName
        if (name = "")
            return false

        useMode := (mode = "") ? this.mode : StrLower(mode)
        useWl := (whitelist is Array) ? whitelist : this.whitelist
        useBl := (blacklist is Array) ? blacklist : this.blacklist

        switch useMode {
            case "off":
                return true
            case "blacklist":
                return !Utils.ListHas(useBl, name)
            default:
                return Utils.ListHas(useWl, name)
        }
    }

    static Describe() {
        return "mode=" this.mode " wl=" this.whitelist.Length " bl=" this.blacklist.Length
    }

    static StatusText() {
        return this.Describe()
    }
}
