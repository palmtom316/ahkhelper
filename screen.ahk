; ScreenPlus - AutoHotkey v2 生产力工具包（仅 Windows x64）
; 入口：模块加载、x64 检查、AppData 配置、热键与托盘

#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent()
SendMode("Input")
CoordMode("Mouse", "Screen")
CoordMode("ToolTip", "Screen")

;@Ahk2Exe-Base AutoHotkey64.exe
;@Ahk2Exe-SetName ScreenPlus
;@Ahk2Exe-SetVersion 1.2.0
;@Ahk2Exe-SetDescription ScreenPlus productivity toolkit

#Include modules\Utils.ahk
#Include modules\Logger.ahk
#Include modules\Config.ahk
#Include modules\WindowFilter.ahk
#Include modules\ClipboardManager.ahk
#Include modules\ToolTipManager.ahk
#Include modules\VirtualDesktop.ahk
#Include modules\AutoCopy.ahk
#Include modules\PluginHost.ahk
#Include modules\TrayMenu.ahk
#Include plugins\Loader.ahk

class App {
    static name := "ScreenPlus"
    static version := "1.2.0"
    static booted := false

    static ReloadAll() {
        Config.Reload()
        Logger.Reload(Config)
        ToolTipManager.Reload(Config)
        ClipboardManager.Reload(Config)
        WindowFilter.Reload(Config)
        ; VirtualDesktop.Reload 内部统一热键
        VirtualDesktop.Reload(Config)
        AutoCopy.Reload(Config)
        PluginHost.ReloadAll(Config)
        TrayMenu.Reload(Config)
        App.name := Config.Get("General", "AppName", "ScreenPlus")
        Logger.Info(Format("App.ReloadAll 完成 {1} {2}", VirtualDesktop.StatusText(), AutoCopy.StatusText()))
    }
}

Main()

Main() {
    try {
        RequireX64()
        Bootstrap()
    } catch as err {
        detail := err.Message
        try detail .= "`n" err.File ":" err.Line
        try {
            logDir := Utils.GetLogDir("ScreenPlus")
            Utils.EnsureDir(logDir)
            FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [FATAL] " detail "`r`n", logDir "\fatal.log", "UTF-8")
        } catch {
        }
        MsgBox("ScreenPlus 启动失败:`n" detail, "ScreenPlus", "Iconx")
        ExitApp(1)
    }
}

RequireX64() {
    if (A_PtrSize != 8) {
        MsgBox("ScreenPlus 仅支持 Windows x64 / AutoHotkey 64-bit。`n当前 A_PtrSize=" A_PtrSize, "ScreenPlus", "Iconx")
        ExitApp(1)
    }
}

Bootstrap() {
    SetWorkingDir(A_ScriptDir)

    configPath := Utils.GetConfigPath("ScreenPlus")
    Config.Init(configPath)
    Logger.Init(Config)

    App.name := Config.Get("General", "AppName", "ScreenPlus")
    A_IconTip := Config.Get("Tray", "Tooltip", App.name)

    ToolTipManager.Init(Config)
    ClipboardManager.Init(Config)
    WindowFilter.Init(Config)
    VirtualDesktop.Init(Config)
    AutoCopy.Init(Config)

    TrayMenu.SetVersion(App.version)
    TrayMenu.SetReloadCallback((*) => App.ReloadAll())
    TrayMenu.Init(Config)

    VirtualDesktop.RegisterHotkeys()
    AutoCopy.RegisterHotkeys()
    PluginHost.InitAll(Config)

    App.booted := true
    Logger.Info(Format("ScreenPlus 启动完成 version={1} config={2} {3} {4} {5}"
        , App.version, Config.path, VirtualDesktop.StatusText(), AutoCopy.StatusText(), PluginHost.StatusText()))

    if Config.GetBool("General", "ShowStartupTip", true) {
        ms := Config.GetInt("General", "StartupTipMs", 2000, 500, 10000)
        tipExtra := (VirtualDesktop.mode = "dll") ? "" : " (VD不可用)"
        ToolTipManager.Show(App.name " v" App.version " 已启动" tipExtra, ms)
    }

    OnExit(OnAppExit)
}

OnAppExit(exitReason, exitCode) {
    try Logger.Info("ScreenPlus 退出 reason=" exitReason " code=" exitCode)
    try PluginHost.ShutdownAll()
    try AutoCopy.Shutdown()
    try VirtualDesktop.Shutdown()
    try ToolTipManager.Shutdown()
}
