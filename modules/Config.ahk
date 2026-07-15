; Config.ahk - INI 配置读写
; DefaultMap 为默认源；支持 GetInt/GetFloat 范围限制；路径支持 AppData

class Config {
    static path := ""
    static cache := Map()
    static templateName := "screen.ini"
    static appName := "ScreenPlus"

    static Init(iniPath := "") {
        if (iniPath = "")
            this.path := Utils.GetConfigPath(this.appName)
        else
            this.path := Utils.ResolvePath(iniPath)

        ; 若 AppData 无配置，尝试从脚本目录模板复制
        if !FileExist(this.path)
            this.WriteDefaults()
        this.Reload()
        this.appName := this.Get("General", "AppName", "ScreenPlus")
        return this.path
    }

    static Reload() {
        this.cache := Map()
        defaults := this.DefaultMap()
        for section, keys in defaults {
            this.cache[section] := Map()
            for key, defaultValue in keys {
                this.cache[section][key] := this.ReadRaw(section, key, defaultValue)
            }
        }
        return true
    }

    static Get(section, key, defaultValue := "") {
        if (this.cache.Has(section) && this.cache[section].Has(key))
            return this.cache[section][key]
        value := this.ReadRaw(section, key, defaultValue)
        if !this.cache.Has(section)
            this.cache[section] := Map()
        this.cache[section][key] := value
        return value
    }

    static GetInt(section, key, defaultValue := 0, minValue := -2147483648, maxValue := 2147483647) {
        v := Utils.ToInt(this.Get(section, key, defaultValue), defaultValue)
        return Utils.Clamp(v, minValue, maxValue)
    }

    static GetFloat(section, key, defaultValue := 0.0, minValue := -1.0e30, maxValue := 1.0e30) {
        v := Utils.ToFloat(this.Get(section, key, defaultValue), defaultValue)
        if (v < minValue)
            return minValue
        if (v > maxValue)
            return maxValue
        return v
    }

    static GetBool(section, key, defaultValue := false) {
        return Utils.ToBool(this.Get(section, key, defaultValue ? "1" : "0"), defaultValue)
    }

    static Set(section, key, value) {
        try {
            IniWrite(String(value), this.path, section, key)
            if !this.cache.Has(section)
                this.cache[section] := Map()
            this.cache[section][key] := String(value)
            return true
        } catch as err {
            try Logger.Error("Config.Set 失败 " section "." key " err=" err.Message)
            return false
        }
    }

    static ReadRaw(section, key, defaultValue := "") {
        try {
            return IniRead(this.path, section, key, defaultValue)
        } catch {
            return defaultValue
        }
    }

    static DefaultMap() {
        return Map(
            "General", Map(
                "AppName", "ScreenPlus",
                "ShowStartupTip", "1",
                "StartupTipMs", "2000"
            ),
            "VirtualDesktop", Map(
                "Enabled", "1",
                "UseDll", "1",
                "DllPath", "",
                "MaxDesktops", "9",
                "HotkeyDesktops", "3",
                "FallbackMode", "off"
            ),
            "AutoCopy", Map(
                "Enabled", "1",
                "DelayMs", "120",
                "ClipWaitTimeout", "0.5",
                "RetryCount", "1",
                "RetryDelayMs", "80",
                "MinDragPixels", "8",
                "ShowTip", "1",
                "TipMs", "800",
                "FilterMode", "whitelist",
                "WaitForAnyData", "0",
                "ActivateTarget", "0"
            ),
            "WindowFilter", Map(
                "Whitelist", "WINWORD.EXE,EXCEL.EXE,POWERPNT.EXE,Code.exe,Obsidian.exe,Typora.exe,notepad++.exe,chrome.exe,msedge.exe,firefox.exe,Acrobat.exe,FoxitPDFReader.exe,WeChat.exe",
                "Blacklist", ""
            ),
            "Clipboard", Map(
                "HistoryMax", "30",
                "HistoryItemMaxKb", "512",
                "HistoryTotalMaxMb", "8",
                "MaxSnapshotMb", "64",
                "LogOperations", "1"
            ),
            "Logger", Map(
                "Enabled", "1",
                "LogDir", "",
                "Level", "INFO",
                "MaxFileKb", "1024"
            ),
            "Tray", Map(
                "Tooltip", "ScreenPlus",
                "ShowAutoCopyToggle", "1",
                "ShowClipboardHistory", "1",
                "HistoryPreviewCount", "5"
            ),
            "ToolTip", Map(
                "DefaultMs", "1500",
                "Position", "mouse"
            )
        )
    }

    static WriteDefaults() {
        try {
            parent := ""
            SplitPath(this.path, , &parent)
            if (parent != "")
                Utils.EnsureDir(parent)

            templateScript := Utils.PathJoin(A_ScriptDir, this.templateName)
            if (FileExist(templateScript) && this.path != templateScript) {
                FileCopy(templateScript, this.path, 1)
                return
            }
            defaults := this.DefaultMap()
            for section, keys in defaults {
                for key, value in keys {
                    IniWrite(String(value), this.path, section, key)
                }
            }
        } catch as err {
            throw Error("无法创建默认配置: " err.Message)
        }
    }

    static DefaultWhitelist() {
        return Utils.ParseList(this.DefaultMap()["WindowFilter"]["Whitelist"])
    }
}
