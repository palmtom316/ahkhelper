; selftest.ahk - 契约自检（AutoHotkey v2 x64）
#Requires AutoHotkey v2.0
#SingleInstance Force
stderr := FileOpen("*", "w")
SetWorkingDir A_ScriptDir "\.."

#Include ..\modules\Utils.ahk
#Include ..\modules\Logger.ahk
#Include ..\modules\Config.ahk
#Include ..\modules\WindowFilter.ahk
#Include ..\modules\ClipboardManager.ahk
#Include ..\modules\ToolTipManager.ahk
#Include ..\modules\VirtualDesktop.ahk
#Include ..\modules\AutoCopy.ahk
#Include ..\modules\PluginHost.ahk

failCount := 0
passCount := 0

Assert(cond, msg) {
    global failCount, passCount, stderr
    if cond {
        passCount += 1
        stderr.WriteLine("PASS " msg)
    } else {
        failCount += 1
        stderr.WriteLine("FAIL " msg)
    }
}

Assert(A_PtrSize = 8, "x64 process A_PtrSize=8")
Assert(Utils.ListHas(["Code.exe"], "code.EXE"), "ListHas case-insensitive")
Assert(Utils.IsDragGesture(0, 0, 10, 0, 8), "IsDragGesture true")
Assert(!Utils.IsDragGesture(0, 0, 3, 3, 8), "IsDragGesture false")
Assert(Utils.Clamp(15, 1, 9) = 9, "Clamp")

iniPath := A_WorkingDir "\screen.ini"
Assert(FileExist(iniPath), "screen.ini exists")
Config.Init(iniPath)
Assert(Config.GetInt("AutoCopy", "DelayMs", 120, 20, 2000) >= 20, "GetInt usable")
Assert(Config.Get("VirtualDesktop", "FallbackMode", "off") != "", "FallbackMode present")

Logger.Init(Config)
initialLogPath := Logger.logPath
Logger.Init(Config)
Assert(Logger.logPath = initialLogPath, "Logger same directory keeps path")
WindowFilter.Init(Config)
wl := Config.DefaultWhitelist()
Assert(WindowFilter.IsAllowed("Code.exe", "whitelist", wl, []), "whitelist Code")
Assert(!WindowFilter.IsAllowed("evil.exe", "whitelist", wl, []), "whitelist deny")

ClipboardManager.Init(Config)
ClipboardManager.PushHistory("hello-selftest")
ClipboardManager.Reload(Config)
Assert(ClipboardManager.history.Length >= 1, "history kept on Reload")
seq := ClipboardManager.GetSequenceNumber()
Assert(seq >= 0, "sequence number non-negative")
cap := ClipboardManager.Capture()
Assert(cap is Object && cap.HasProp("ok"), "Capture returns result object")

AutoCopy.Init(Config)
Assert(AutoCopy.enabled = Config.GetBool("AutoCopy", "Enabled", true), "AutoCopy enabled")
Assert(AutoCopy.debounceTimer, "AutoCopy debounce timer callback initialized")
Assert(AutoCopy.ShouldRestore(100, 100), "SafeRestore owns matching sequence")
Assert(!AutoCopy.ShouldRestore(100, 101), "SafeRestore rejects changed sequence")
Assert(!AutoCopy.ShouldRestore(0, 0), "SafeRestore rejects unavailable sequence")

VirtualDesktop.ApplyConfig(Config)
Assert(VirtualDesktop.hotkeyDesktops >= 1 && VirtualDesktop.hotkeyDesktops <= 9, "hotkeyDesktops range")
Assert(VirtualDesktop.fallbackMode = "off" || VirtualDesktop.fallbackMode = "simulate", "fallbackMode simplified")
VirtualDesktop.enabled := true
VirtualDesktop.ready := false
VirtualDesktop.moveReady := false
Assert(!VirtualDesktop.CanRegisterSwitchHotkeys(), "VD does not register switch hotkeys when not ready")
Assert(!VirtualDesktop.CanRegisterMoveHotkeys(), "VD does not register move hotkeys when not ready")
VirtualDesktop.ready := true
Assert(VirtualDesktop.CanRegisterSwitchHotkeys(), "VD registers switch hotkeys when ready")
Assert(!VirtualDesktop.CanRegisterMoveHotkeys(), "VD move hotkeys require moveReady")
VirtualDesktop.moveReady := true
Assert(VirtualDesktop.CanRegisterMoveHotkeys(), "VD move hotkeys when moveReady")

PluginHost.Register("SelfTestPlugin", (cfg) => true, (*) => 0)
PluginHost.InitAll(Config)
Assert(PluginHost.Count() >= 1, "PluginHost count")
PluginHost.ShutdownAll()

cfgPath := Utils.GetConfigPath("ScreenPlus")
Assert(InStr(cfgPath, "screen.ini"), "config path contains screen.ini")

stderr.WriteLine("")
stderr.WriteLine("RESULT pass=" passCount " fail=" failCount)
ExitApp(failCount = 0 ? 0 : 1)
