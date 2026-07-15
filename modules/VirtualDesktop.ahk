; VirtualDesktop.ahk - 虚拟桌面（x64 VirtualDesktopAccessor）
; 默认 FallbackMode=off；simulate 可选；删除无效 probe 相对路径依赖
; 卸载顺序：先撤 ready/指针，再 FreeLibrary

class VirtualDesktop {
    static enabled := true
    static useDll := true
    static dllPath := ""
    static maxDesktops := 9
    static hotkeyDesktops := 3
    static fallbackMode := "off" ; off | simulate

    static hModule := 0
    static ready := false
    static moveReady := false
    static mode := "none" ; dll | fallback | none
    static missingExports := []
    static hotkeysRegistered := false
    static registeredCount := 0

    static fnGoToDesktopNumber := 0
    static fnGetCurrentDesktopNumber := 0
    static fnGetDesktopCount := 0
    static fnMoveWindowToDesktopNumber := 0

    static Init(cfg) {
        this.ApplyConfig(cfg)
        this.ShutdownBackend()
        ok := this.StartBackend()
        Logger.Info("VirtualDesktop 初始化 " this.StatusText())
        return ok
    }

    ; Reload 统一维护后端与热键
    static Reload(cfg) {
        this.ApplyConfig(cfg)
        this.ShutdownBackend()
        ok := this.StartBackend()
        if this.enabled
            this.RegisterHotkeys()
        else
            this.UnregisterHotkeys()
        Logger.Info("VirtualDesktop 重载 " this.StatusText())
        return ok
    }

    static ApplyConfig(cfg) {
        this.enabled := cfg.GetBool("VirtualDesktop", "Enabled", true)
        this.useDll := cfg.GetBool("VirtualDesktop", "UseDll", true)
        this.dllPath := cfg.Get("VirtualDesktop", "DllPath", "")
        this.maxDesktops := cfg.GetInt("VirtualDesktop", "MaxDesktops", 9, 1, 20)
        this.hotkeyDesktops := cfg.GetInt("VirtualDesktop", "HotkeyDesktops", 3, 1, 9)
        this.fallbackMode := StrLower(cfg.Get("VirtualDesktop", "FallbackMode", "off"))
        if (this.fallbackMode != "simulate" && this.fallbackMode != "off")
            this.fallbackMode := "off"
    }

    static StartBackend() {
        this.ready := false
        this.moveReady := false
        this.mode := "none"
        this.missingExports := []

        if !this.enabled {
            Logger.Info("VirtualDesktop 已禁用")
            return false
        }

        if this.useDll {
            if this.TryLoadDll() {
                this.PublishDllReady()
                Logger.Info(Format("VirtualDesktop DLL 模式就绪 path={1} moveReady={2}", this.dllPath, this.moveReady))
                if !this.moveReady
                    Logger.Warn("缺 MoveWindowToDesktopNumber，Alt+Shift 移窗不可用")
                return true
            }
            Logger.Warn("VirtualDesktop DLL 不可用，fallbackMode=" this.fallbackMode)
        }

        if (this.fallbackMode = "simulate") {
            this.mode := "fallback"
            this.ready := true
            this.moveReady := false
            Logger.Info("VirtualDesktop simulate 回退已启用")
            return true
        }

        this.mode := "none"
        this.ready := false
        Logger.Warn("VirtualDesktop 不可用（请放置 x64 VirtualDesktopAccessor.dll）")
        return false
    }

    static PublishDllReady() {
        this.mode := "dll"
        this.ready := true
        this.moveReady := (this.fnMoveWindowToDesktopNumber != 0)
    }

    static TryLoadDll() {
        path := this.dllPath
        if (path = "")
            path := A_ScriptDir "\VirtualDesktopAccessor.dll"
        this.dllPath := Utils.ResolvePath(path)

        load := Utils.SafeLoadLibrary(this.dllPath)
        if !load.ok {
            Logger.Warn("LoadLibrary 失败: " load.error)
            return false
        }
        this.hModule := load.handle

        this.fnGoToDesktopNumber := this.ResolveProc(["GoToDesktopNumber"])
        this.fnGetCurrentDesktopNumber := this.ResolveProc(["GetCurrentDesktopNumber"])
        this.fnGetDesktopCount := this.ResolveProc(["GetDesktopCount"])
        this.fnMoveWindowToDesktopNumber := this.ResolveProc(["MoveWindowToDesktopNumber"])

        if !this.fnGoToDesktopNumber {
            this.missingExports.Push("GoToDesktopNumber")
            Logger.Warn("未找到必需导出 GoToDesktopNumber")
            this.ShutdownBackend()
            return false
        }
        if !this.fnMoveWindowToDesktopNumber
            this.missingExports.Push("MoveWindowToDesktopNumber")
        if !this.fnGetCurrentDesktopNumber
            this.missingExports.Push("GetCurrentDesktopNumber")
        if !this.fnGetDesktopCount
            this.missingExports.Push("GetDesktopCount")
        return true
    }

    static ResolveProc(names) {
        for name in names {
            try {
                addr := DllCall("GetProcAddress", "Ptr", this.hModule, "AStr", name, "Ptr")
                if addr
                    return addr
            } catch {
            }
        }
        return 0
    }

    ; 先撤可见状态与函数指针，再 FreeLibrary
    static ShutdownBackend() {
        Critical(20)
        this.ready := false
        this.moveReady := false
        this.mode := "none"
        h := this.hModule
        this.hModule := 0
        this.fnGoToDesktopNumber := 0
        this.fnGetCurrentDesktopNumber := 0
        this.fnGetDesktopCount := 0
        this.fnMoveWindowToDesktopNumber := 0
        Critical("Off")
        if h {
            if !Utils.SafeFreeLibrary(h)
                Logger.Warn("FreeLibrary 返回失败")
        }
    }

    static GoTo(desktopIndex) {
        if !this.ready || !this.enabled
            return false
        index := Utils.Clamp(Integer(desktopIndex), 1, this.maxDesktops)

        if (this.mode = "dll" && this.fnGoToDesktopNumber) {
            try {
                DllCall(this.fnGoToDesktopNumber, "Int", index - 1)
                Logger.Debug("切换桌面 DLL -> " index)
                return true
            } catch as err {
                Logger.Error("GoTo DLL 失败: " err.Message)
            }
        }
        return this.GoToFallback(index)
    }

    static MoveActiveWindowTo(desktopIndex) {
        if !this.ready || !this.enabled
            return false
        index := Utils.Clamp(Integer(desktopIndex), 1, this.maxDesktops)
        hwnd := WinExist("A")
        if !hwnd {
            Logger.Warn("MoveActiveWindowTo: 无活动窗口")
            return false
        }

        if (this.mode = "dll" && this.fnMoveWindowToDesktopNumber) {
            try {
                DllCall(this.fnMoveWindowToDesktopNumber, "Ptr", hwnd, "Int", index - 1)
                Logger.Debug("移动窗口 DLL hwnd=" hwnd " -> " index)
                return true
            } catch as err {
                Logger.Error("MoveWindow DLL 失败: " err.Message)
            }
        }

        ToolTipManager.Show("移窗需要 x64 VirtualDesktopAccessor.dll", 1800)
        Logger.Warn("MoveActiveWindowTo 不可用 mode=" this.mode)
        return false
    }

    static GetCurrent() {
        if (this.mode = "dll" && this.fnGetCurrentDesktopNumber) {
            try {
                n := DllCall(this.fnGetCurrentDesktopNumber, "Int")
                return n + 1
            } catch {
                return 0
            }
        }
        return 0
    }

    static GetCount() {
        if (this.mode = "dll" && this.fnGetDesktopCount) {
            try {
                return DllCall(this.fnGetDesktopCount, "Int")
            } catch {
                return 0
            }
        }
        return 0
    }

    ; simulate：盲切；off：不可用
    static GoToFallback(desktopIndex) {
        if (this.fallbackMode != "simulate" || this.mode != "fallback") {
            ToolTipManager.Show("请安装 x64 VirtualDesktopAccessor.dll", 2000)
            return false
        }
        try {
            loop this.maxDesktops {
                Send("#^{Left}")
                Sleep(40)
            }
            if (desktopIndex > 1) {
                loop (desktopIndex - 1) {
                    Send("#^{Right}")
                    Sleep(40)
                }
            }
            Logger.Debug("切换桌面 simulate -> " desktopIndex)
            return true
        } catch as err {
            Logger.Error("GoToFallback simulate 失败: " err.Message)
            return false
        }
    }

    static RegisterHotkeys() {
        if !this.CanRegisterSwitchHotkeys() {
            this.UnregisterHotkeys()
            Logger.Info("VirtualDesktop 后端未就绪，不占用 Alt 数字热键")
            return
        }
        this.ReregisterHotkeys()
    }

    static CanRegisterSwitchHotkeys() {
        return this.enabled && this.ready
    }

    static CanRegisterMoveHotkeys() {
        return this.CanRegisterSwitchHotkeys() && this.moveReady
    }

    static ReregisterHotkeys() {
        this.UnregisterHotkeys()
        if !this.CanRegisterSwitchHotkeys()
            return
        count := this.hotkeyDesktops
        registerMove := this.CanRegisterMoveHotkeys()
        loop count {
            i := A_Index
            Hotkey("!" i, this.MakeGoHandler(i))
            if registerMove
                Hotkey("!+" i, this.MakeMoveHandler(i))
        }
        this.registeredCount := count
        this.hotkeysRegistered := true
        Logger.Info(Format("VirtualDesktop 热键已注册 Alt+1..{1} move={2}", count, registerMove))
    }

    static MakeGoHandler(desktopIndex) {
        return (*) => VirtualDesktop.GoTo(desktopIndex)
    }

    static MakeMoveHandler(desktopIndex) {
        return (*) => VirtualDesktop.MoveActiveWindowTo(desktopIndex)
    }

    static UnregisterHotkeys() {
        loop 9 {
            i := A_Index
            try Hotkey("!" i, "Off")
            try Hotkey("!+" i, "Off")
        }
        this.hotkeysRegistered := false
        this.registeredCount := 0
    }

    static StatusText() {
        cur := this.GetCurrent()
        cnt := this.GetCount()
        miss := Utils.JoinList(this.missingExports, ",")
        text := Format("VD mode={1} ready={2} move={3} keys={4}", this.mode, this.ready, this.moveReady, this.hotkeyDesktops)
        if cur
            text .= " current=" cur
        if cnt
            text .= " count=" cnt
        if (miss != "")
            text .= " missing=" miss
        return text
    }

    static Shutdown() {
        this.UnregisterHotkeys()
        this.ShutdownBackend()
    }
}
