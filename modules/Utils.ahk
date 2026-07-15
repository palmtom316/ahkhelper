; Utils.ahk - 通用工具函数
; 路径、列表、进程、安全 DLL 加载（x64 / LoadLibraryExW）

class Utils {
    ; LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS
    static LOAD_LIBRARY_SEARCH_FLAGS := 0x00001100
    static PathJoin(parts*) {
        sep := Chr(92)
        result := ""
        for part in parts {
            if (part = "")
                continue
            if (result = "")
                result := String(part)
            else
                result := Format("{1}{2}{3}", result, sep, part)
        }
        return result
    }

    static ResolvePath(path) {
        sep := Chr(92)
        if (path = "" || path = A_Space)
            return A_ScriptDir
        isDrivePath := RegExMatch(path, "i)^[a-z]:") && SubStr(path, 3, 1) = sep
        isUncPath := SubStr(path, 1, 2) = Format("{1}{1}", sep)
        if (isDrivePath || isUncPath)
            return path
        return this.PathJoin(A_ScriptDir, path)
    }

    static EnsureDir(path) {
        dir := this.ResolvePath(path)
        if !DirExist(dir) {
            try {
                DirCreate(dir)
            } catch as err {
                return { ok: false, path: dir, error: err.Message }
            }
        }
        return { ok: true, path: dir, error: "" }
    }

    ; 便携模式：脚本旁存在 portable.flag 时使用 A_ScriptDir
    static IsPortable() {
        return FileExist(this.PathJoin(A_ScriptDir, "portable.flag"))
    }

    ; 配置目录：便携用脚本目录，否则 %AppData%\ScreenPlus
    static GetConfigDir(appName := "ScreenPlus") {
        if this.IsPortable()
            return A_ScriptDir
        dir := this.PathJoin(A_AppData, appName)
        this.EnsureDir(dir)
        return dir
    }

    ; 日志目录：便携用脚本目录\logs，否则 %LocalAppData%\ScreenPlus\logs
    static GetLogDir(appName := "ScreenPlus") {
        if this.IsPortable() {
            dir := this.PathJoin(A_ScriptDir, "logs")
            this.EnsureDir(dir)
            return dir
        }
        localAppData := EnvGet("LocalAppData")
        if (localAppData = "")
            localAppData := A_AppData
        dir := this.PathJoin(localAppData, appName, "logs")
        this.EnsureDir(dir)
        return dir
    }

    static GetConfigPath(appName := "ScreenPlus") {
        return this.PathJoin(this.GetConfigDir(appName), "screen.ini")
    }

    ; 读取 PE Machine：0x8664=AMD64, 0x014c=x86, 0xAA64=ARM64
    static GetPeMachine(filePath) {
        try {
            f := FileOpen(filePath, "r")
            if !f
                return 0
            if (f.Length < 0x40) {
                f.Close()
                return 0
            }
            f.Seek(0x3C)
            peOffset := f.ReadUInt()
            if (peOffset + 6 > f.Length) {
                f.Close()
                return 0
            }
            f.Seek(peOffset)
            sig := f.ReadUInt()
            if (sig != 0x00004550) { ; "PE\0\0"
                f.Close()
                return 0
            }
            machine := f.ReadUShort()
            f.Close()
            return machine
        } catch {
            return 0
        }
    }

    static DescribePeMachine(machine) {
        switch machine {
            case 0x8664:
                return "AMD64"
            case 0x014C:
                return "x86"
            case 0xAA64:
                return "ARM64"
            default:
                return Format("0x{:04X}", machine)
        }
    }

    ; 仅允许 AMD64 DLL；使用 LoadLibraryExW 限制搜索路径
    static SafeLoadLibrary(dllPath) {
        fullPath := this.ResolvePath(dllPath)
        if !FileExist(fullPath)
            return { ok: false, handle: 0, path: fullPath, error: "文件不存在: " fullPath }

        machine := this.GetPeMachine(fullPath)
        if (machine && machine != 0x8664) {
            return {
                ok: false,
                handle: 0,
                path: fullPath,
                error: "DLL 架构不匹配（需要 x64/AMD64，实际 " this.DescribePeMachine(machine) "）"
            }
        }

        try {
            hModule := DllCall(
                "Kernel32\LoadLibraryExW",
                "WStr", fullPath,
                "Ptr", 0,
                "UInt", this.LOAD_LIBRARY_SEARCH_FLAGS,
                "Ptr"
            )
            if !hModule {
                err := A_LastError
                msg := "LoadLibraryExW 失败, LastError=" err
                if (err = 193)
                    msg := "DLL 架构不匹配或映像无效 (ERROR_BAD_EXE_FORMAT/193)，请使用 x64 VirtualDesktopAccessor.dll"
                return { ok: false, handle: 0, path: fullPath, error: msg }
            }
            return { ok: true, handle: hModule, path: fullPath, error: "" }
        } catch as err {
            return { ok: false, handle: 0, path: fullPath, error: err.Message }
        }
    }

    static SafeFreeLibrary(hModule) {
        if !hModule
            return true
        try {
            return !!DllCall("FreeLibrary", "Ptr", hModule)
        } catch {
            return false
        }
    }

    static ParseList(text) {
        result := []
        if (text = "")
            return result
        for part in StrSplit(text, ",") {
            item := Trim(part)
            if (item != "")
                result.Push(item)
        }
        return result
    }

    static JoinList(arr, sep := ",") {
        out := ""
        for index, item in arr {
            out .= (index = 1 ? "" : sep) item
        }
        return out
    }

    static ListHas(arr, value) {
        needle := StrLower(value)
        for item in arr {
            if (StrLower(item) = needle)
                return true
        }
        return false
    }

    static GetActiveProcessName() {
        try {
            hwnd := WinExist("A")
            if !hwnd
                return ""
            return WinGetProcessName(hwnd)
        } catch {
            return ""
        }
    }

    static GetMouseWindowHwnd() {
        try {
            MouseGetPos(, , &hwnd)
            return hwnd ? hwnd : 0
        } catch {
            return 0
        }
    }

    static GetProcessNameFromHwnd(hwnd) {
        if !hwnd
            return ""
        try {
            return WinGetProcessName(hwnd)
        } catch {
            return ""
        }
    }

    static IsWindowAlive(hwnd) {
        if !hwnd
            return false
        try {
            return !!DllCall("IsWindow", "Ptr", hwnd, "Int")
        } catch {
            return false
        }
    }

    static GetForegroundHwnd() {
        try {
            return DllCall("GetForegroundWindow", "Ptr")
        } catch {
            return 0
        }
    }

    static ToBool(value, defaultValue := false) {
        if (value = "")
            return defaultValue
        v := StrLower(Trim(String(value)))
        if (v = "1" || v = "true" || v = "yes" || v = "on")
            return true
        if (v = "0" || v = "false" || v = "no" || v = "off")
            return false
        return defaultValue
    }

    static ToInt(value, defaultValue := 0) {
        if (value = "" || !IsNumber(value))
            return defaultValue
        return Integer(value)
    }

    static ToFloat(value, defaultValue := 0.0) {
        if (value = "" || !IsNumber(value))
            return defaultValue
        return Float(value)
    }

    static Clamp(value, minValue, maxValue) {
        if (value < minValue)
            return minValue
        if (value > maxValue)
            return maxValue
        return value
    }

    static IsDragGesture(x1, y1, x2, y2, minPixels) {
        return (Abs(x2 - x1) >= minPixels) || (Abs(y2 - y1) >= minPixels)
    }

    static OpenPath(path) {
        if (path = "" || !FileExist(path) && !DirExist(path))
            return false
        try {
            Run(path)
            return true
        } catch {
            try {
                Run('explorer.exe "' path '"')
                return true
            } catch {
                return false
            }
        }
    }

    ; 短临界区内执行回调（保护状态发布/撤销）
    static CriticalSection(fn, timeoutMs := 20) {
        Critical(timeoutMs)
        try {
            return fn.Call()
        } finally {
            Critical("Off")
        }
    }
}
