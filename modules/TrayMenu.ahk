; TrayMenu.ahk - 托盘菜单；重载仅走 App.ReloadAll，不双重 Build

class TrayMenu {
    static appName := "ScreenPlus"
    static showAutoCopyToggle := true
    static showClipboardHistory := true
    static historyPreviewCount := 5
    static reloadCallback := false
    static aboutVersion := "1.2.0"

    static Init(cfg) {
        this.ApplyConfig(cfg)
        this.Build()
        Logger.Info("TrayMenu 初始化完成")
        return true
    }

    static Reload(cfg) {
        this.ApplyConfig(cfg)
        this.Build()
        return true
    }

    static ApplyConfig(cfg) {
        this.appName := cfg.Get("General", "AppName", "ScreenPlus")
        this.showAutoCopyToggle := cfg.GetBool("Tray", "ShowAutoCopyToggle", true)
        this.showClipboardHistory := cfg.GetBool("Tray", "ShowClipboardHistory", true)
        this.historyPreviewCount := cfg.GetInt("Tray", "HistoryPreviewCount", 5, 0, 10)
        A_IconTip := cfg.Get("Tray", "Tooltip", this.appName)
    }

    static SetReloadCallback(fn) {
        this.reloadCallback := fn
    }

    static SetVersion(ver) {
        this.aboutVersion := ver
    }

    static Build() {
        A_TrayMenu.Delete()
        A_TrayMenu.Add("关于 " this.appName, (*) => TrayMenu.ShowAbout())
        A_TrayMenu.Add()

        if this.showAutoCopyToggle {
            label := AutoCopy.enabled ? "禁用 AutoCopy" : "启用 AutoCopy"
            A_TrayMenu.Add(label, (*) => TrayMenu.ToggleAutoCopy())
        }

        A_TrayMenu.Add("重载配置", (*) => TrayMenu.ReloadConfig())
        A_TrayMenu.Add("打开日志目录", (*) => TrayMenu.OpenLogs())
        A_TrayMenu.Add("打开配置文件", (*) => TrayMenu.OpenConfig())
        A_TrayMenu.Add("状态总览", (*) => TrayMenu.ShowStatus())

        if this.showClipboardHistory
            this.AddHistoryMenu()

        A_TrayMenu.Add()
        A_TrayMenu.Add("重载脚本", (*) => Reload())
        A_TrayMenu.Add("退出", (*) => ExitApp())
        A_TrayMenu.Default := "关于 " this.appName
    }

    static AddHistoryMenu() {
        lines := ClipboardManager.GetHistorySummary(this.historyPreviewCount)
        A_TrayMenu.Add("剪贴板历史", (*) => TrayMenu.ShowHistoryPopup())
        if (lines.Length = 0) {
            A_TrayMenu.Add("  （空）", (*) => 0)
            try A_TrayMenu.Disable("  （空）")
            return
        }
        for index, line in lines {
            A_TrayMenu.Add("  " line, this.MakeHistoryHandler(index))
        }
    }

    static MakeHistoryHandler(index) {
        return (*) => TrayMenu.UseHistory(index)
    }

    static UseHistory(index) {
        if ClipboardManager.UseHistoryItem(index)
            ToolTipManager.ShowSuccess("已放入剪贴板 #" index, 1000)
        else
            ToolTipManager.ShowError("历史项无效", 1000)
    }

    static ShowHistoryPopup() {
        lines := ClipboardManager.GetHistorySummary(this.historyPreviewCount)
        text := lines.Length ? Utils.JoinList(lines, "`n") : "（历史为空）"
        ToolTipManager.Show(text, 2500)
    }

    static ToggleAutoCopy() {
        state := AutoCopy.Toggle()
        ToolTipManager.Show(state ? "AutoCopy 已启用" : "AutoCopy 已禁用", 1200)
        this.Build()
    }

    static ReloadConfig() {
        try {
            if !this.reloadCallback {
                Logger.Error("TrayMenu 未注入 Reload 回调")
                ToolTipManager.ShowError("重载未配置", 1500)
                return
            }
            this.reloadCallback.Call()
            ; App.ReloadAll 已调用 TrayMenu.Reload → Build，此处不再 Rebuild
            ToolTipManager.ShowSuccess("配置已重载", 1200)
            Logger.Info("配置重载完成")
        } catch as err {
            Logger.Error("重载配置失败: " err.Message)
            ToolTipManager.ShowError("重载失败", 1500)
        }
    }

    static OpenLogs() {
        dir := Logger.logDir
        if (dir = "")
            dir := Utils.GetLogDir(this.appName)
        Utils.EnsureDir(dir)
        if !Utils.OpenPath(dir)
            ToolTipManager.ShowError("无法打开日志目录", 1500)
    }

    static OpenConfig() {
        path := Config.path
        if FileExist(path) {
            if !Utils.OpenPath(path)
                try Run('notepad.exe "' path '"')
        } else {
            ToolTipManager.ShowError("配置文件不存在", 1500)
        }
    }

    static ShowStatus() {
        text := this.appName " v" this.aboutVersion "`n"
            . VirtualDesktop.StatusText() "`n"
            . AutoCopy.StatusText() "`n"
            . WindowFilter.StatusText() "`n"
            . ClipboardManager.StatusText() "`n"
            . PluginHost.StatusText() "`n"
            . "config=" Config.path
        ToolTipManager.Show(text, 3500)
        Logger.Info(StrReplace(text, "`n", " | "))
    }

    static ShowAbout() {
        msg := this.appName " v" this.aboutVersion "`n"
            . "AutoHotkey v2 / Windows x64`n`n"
            . "虚拟桌面: Alt+1..N`n"
            . "移动窗口: Alt+Shift+1..N`n"
            . "划词复制: 选中文本自动 Ctrl+C`n`n"
            . VirtualDesktop.StatusText()
        MsgBox(msg, this.appName, "Iconi")
    }

    static StatusText() {
        return "Tray app=" this.appName
    }
}
