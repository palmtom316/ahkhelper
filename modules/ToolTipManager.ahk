; ToolTipManager.ahk - 统一提示；单一 hide timer

class ToolTipManager {
    static defaultMs := 1500
    static position := "mouse"
    static hideToken := 0
    static hideTimer := false
    static pendingHideToken := 0

    static Init(cfg) {
        this.hideTimer := (*) => ToolTipManager.HideIfCurrent()
        this.ApplyConfig(cfg)
        Logger.Info("ToolTipManager 初始化 defaultMs=" this.defaultMs " pos=" this.position)
        return true
    }

    static Reload(cfg) {
        this.ApplyConfig(cfg)
        return true
    }

    static ApplyConfig(cfg) {
        this.defaultMs := cfg.GetInt("ToolTip", "DefaultMs", 1500, 200, 10000)
        this.position := StrLower(cfg.Get("ToolTip", "Position", "mouse"))
    }

    static Show(text, durationMs := -1, x := "", y := "") {
        if (text = "")
            return
        ms := (durationMs < 0) ? this.defaultMs : durationMs
        this.ShowAt(text, x, y)
        if (ms > 0)
            this.ScheduleHide(ms)
    }

    static ShowSuccess(text, durationMs := -1) {
        this.Show("[OK] " text, durationMs)
    }

    static ShowError(text, durationMs := -1) {
        this.Show("[ERR] " text, durationMs)
    }

    static ShowAt(text, x := "", y := "") {
        try {
            if (x != "" && y != "") {
                ToolTip(text, x, y)
                return
            }
            if (this.position = "center") {
                ; 使用鼠标所在显示器工作区居中
                MouseGetPos(&mx, &my)
                mon := 0
                try mon := MonitorGetPrimary()
                loop MonitorGetCount() {
                    MonitorGet(A_Index, &l, &t, &r, &b)
                    if (mx >= l && mx < r && my >= t && my < b) {
                        mon := A_Index
                        break
                    }
                }
                if mon {
                    MonitorGetWorkArea(mon, &wl, &wt, &wr, &wb)
                    ToolTip(text, (wl + wr) // 2, (wt + wb) // 2)
                } else {
                    ToolTip(text, A_ScreenWidth // 2, A_ScreenHeight // 2)
                }
            } else {
                ToolTip(text)
            }
        } catch as err {
            Logger.Debug("ToolTip 显示失败: " err.Message)
        }
    }

    static Hide(*) {
        try ToolTip()
    }

    static ScheduleHide(ms) {
        this.hideToken += 1
        this.pendingHideToken := this.hideToken
        if !this.hideTimer
            this.hideTimer := (*) => ToolTipManager.HideIfCurrent()
        try SetTimer(this.hideTimer, 0)
        SetTimer(this.hideTimer, -ms)
    }

    static HideIfCurrent(*) {
        if (this.pendingHideToken = this.hideToken)
            this.Hide()
    }

    static StatusText() {
        return "ToolTip pos=" this.position " defaultMs=" this.defaultMs
    }

    static Shutdown() {
        if this.hideTimer
            try SetTimer(this.hideTimer, 0)
        this.Hide()
    }
}
