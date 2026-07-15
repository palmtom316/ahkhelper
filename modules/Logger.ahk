; Logger.ahk - 文件日志；内存累计大小，减少每次 FileGetSize

class Logger {
    static enabled := true
    static level := "INFO"
    static logDir := ""
    static maxFileKb := 1024
    static logPath := ""
    static logDate := ""
    static currentSize := 0
    static levelRank := Map(
        "DEBUG", 10,
        "INFO", 20,
        "WARN", 30,
        "ERROR", 40
    )

    static Init(cfg) {
        this.enabled := cfg.GetBool("Logger", "Enabled", true)
        this.level := StrUpper(cfg.Get("Logger", "Level", "INFO"))
        this.maxFileKb := cfg.GetInt("Logger", "MaxFileKb", 1024, 64, 10240)
        configured := Trim(cfg.Get("Logger", "LogDir", ""))
        if (configured != "")
            newLogDir := Utils.ResolvePath(configured)
        else
            newLogDir := Utils.GetLogDir(cfg.Get("General", "AppName", "ScreenPlus"))

        dirResult := Utils.EnsureDir(newLogDir)
        if !dirResult.ok {
            this.enabled := false
            return false
        }
        newLogDir := dirResult.path
        if (newLogDir != this.logDir) {
            this.logDir := newLogDir
            this.logPath := ""
            this.logDate := ""
            this.currentSize := 0
        }
        this.EnsureLogPath()
        this.Info("Logger 初始化完成 path=" this.logPath " level=" this.level)
        return true
    }

    static Reload(cfg) {
        return this.Init(cfg)
    }

    static EnsureLogPath() {
        today := A_YYYY A_MM A_DD
        if (this.logPath = "" || this.logDate != today) {
            this.logDate := today
            this.logPath := this.logDir "\screenplus-" today ".log"
            this.currentSize := 0
            if FileExist(this.logPath) {
                try this.currentSize := FileGetSize(this.logPath)
                catch
                    this.currentSize := 0
            }
        }
    }

    static Debug(msg) => this.Write("DEBUG", msg)
    static Info(msg) => this.Write("INFO", msg)
    static Warn(msg) => this.Write("WARN", msg)
    static Error(msg) => this.Write("ERROR", msg)

    static Write(level, msg) {
        if !this.enabled
            return
        if !this.ShouldLog(level)
            return
        try {
            this.EnsureLogPath()
            this.RotateIfNeeded()
            line := FormatTime(, "yyyy-MM-dd HH:mm:ss") " [" level "] " msg "`r`n"
            FileAppend(line, this.logPath, "UTF-8")
            ; UTF-8 近似字节数
            this.currentSize += StrPut(line, "UTF-8") - 1
        } catch {
        }
    }

    static ShouldLog(level) {
        current := this.levelRank.Has(StrUpper(this.level)) ? this.levelRank[StrUpper(this.level)] : 20
        target := this.levelRank.Has(StrUpper(level)) ? this.levelRank[StrUpper(level)] : 20
        return target >= current
    }

    static RotateIfNeeded() {
        if (this.logPath = "")
            return
        limit := this.maxFileKb * 1024
        if (this.currentSize <= limit) {
            ; 偶尔校验真实大小
            if (this.currentSize > 0 && Mod(this.currentSize, 65536) > 60000) {
                try this.currentSize := FileGetSize(this.logPath)
                catch
                    return
            }
            if (this.currentSize <= limit)
                return
        }
        try {
            if FileExist(this.logPath) {
                try this.currentSize := FileGetSize(this.logPath)
                if (this.currentSize <= limit)
                    return
                bak := this.logPath ".1"
                if FileExist(bak)
                    FileDelete(bak)
                FileMove(this.logPath, bak, 1)
            }
            this.currentSize := 0
        } catch {
        }
    }

    static StatusText() {
        return "Logger enabled=" this.enabled " level=" this.level " path=" this.logPath
    }
}
