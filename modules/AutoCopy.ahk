; AutoCopy.ahk - 划词自动复制
; 流程：debounce → 重验窗口 → Capture 一次 → Clear → sequence → Ctrl+C
;      → sequence 变化判定 → 失败仅在仍持有剪贴板时 Restore

class AutoCopy {
    static enabled := true
    static delayMs := 120
    static clipWaitTimeout := 0.5
    static retryCount := 1
    static retryDelayMs := 80
    static minDragPixels := 8
    static showTip := true
    static tipMs := 800
    static waitForAnyData := false
    static activateTarget := false

    static pressX := 0
    static pressY := 0
    static tracking := false
    static busy := false
    static hotkeysRegistered := false

    static generation := 0
    static hasPending := false
    static pendingHwnd := 0
    static pendingProcess := ""
    static debounceTimer := false

    static Init(cfg) {
        this.debounceTimer := (*) => AutoCopy.ProcessPending()
        this.ApplyConfig(cfg)
        Logger.Info(Format("AutoCopy 初始化 enabled={1} delay={2} retry={3} anyData={4}"
            , this.enabled, this.delayMs, this.retryCount, this.waitForAnyData))
        return true
    }

    static Reload(cfg) {
        this.ApplyConfig(cfg)
        Logger.Info("AutoCopy 重载 enabled=" this.enabled)
        return true
    }

    static ApplyConfig(cfg) {
        this.enabled := cfg.GetBool("AutoCopy", "Enabled", true)
        this.delayMs := cfg.GetInt("AutoCopy", "DelayMs", 120, 20, 2000)
        this.clipWaitTimeout := cfg.GetFloat("AutoCopy", "ClipWaitTimeout", 0.5, 0.05, 5.0)
        this.retryCount := cfg.GetInt("AutoCopy", "RetryCount", 1, 0, 3)
        this.retryDelayMs := cfg.GetInt("AutoCopy", "RetryDelayMs", 80, 10, 1000)
        this.minDragPixels := cfg.GetInt("AutoCopy", "MinDragPixels", 8, 1, 100)
        this.showTip := cfg.GetBool("AutoCopy", "ShowTip", true)
        this.tipMs := cfg.GetInt("AutoCopy", "TipMs", 800, 200, 5000)
        this.waitForAnyData := cfg.GetBool("AutoCopy", "WaitForAnyData", false)
        this.activateTarget := cfg.GetBool("AutoCopy", "ActivateTarget", false)
    }

    static Enable() {
        this.enabled := true
        Config.Set("AutoCopy", "Enabled", "1")
        Logger.Info("AutoCopy 已启用")
    }

    static Disable() {
        this.enabled := false
        Config.Set("AutoCopy", "Enabled", "0")
        this.CancelDebounce()
        this.hasPending := false
        Logger.Info("AutoCopy 已禁用")
    }

    static Toggle() {
        if this.enabled
            this.Disable()
        else
            this.Enable()
        return this.enabled
    }

    static RegisterHotkeys() {
        if this.hotkeysRegistered
            return
        Hotkey("~LButton", (*) => AutoCopy.OnButtonDown())
        Hotkey("~LButton Up", (*) => AutoCopy.OnButtonUp())
        this.hotkeysRegistered := true
        Logger.Info("AutoCopy 鼠标热键已注册")
    }

    static UnregisterHotkeys() {
        if !this.hotkeysRegistered
            return
        try Hotkey("~LButton", "Off")
        try Hotkey("~LButton Up", "Off")
        this.hotkeysRegistered := false
    }

    static OnButtonDown(*) {
        if !this.enabled
            return
        MouseGetPos(&x, &y)
        this.pressX := x
        this.pressY := y
        this.tracking := true
    }

    static OnButtonUp(*) {
        if !this.enabled || !this.tracking
            return
        this.tracking := false

        MouseGetPos(&x, &y)
        if !Utils.IsDragGesture(this.pressX, this.pressY, x, y, this.minDragPixels)
            return

        hwnd := Utils.GetMouseWindowHwnd()
        processName := Utils.GetProcessNameFromHwnd(hwnd)
        if !WindowFilter.IsAllowed(processName) {
            Logger.Debug("AutoCopy 跳过（过滤） process=" processName " hwnd=" hwnd)
            return
        }

        this.pendingHwnd := hwnd
        this.pendingProcess := processName
        this.generation += 1
        this.hasPending := true
        this.ScheduleDebounce()
    }

    static CancelDebounce() {
        if this.debounceTimer
            try SetTimer(this.debounceTimer, 0)
    }

    static ScheduleDebounce() {
        this.CancelDebounce()
        delay := Max(this.delayMs, 1)
        SetTimer(this.debounceTimer, -delay)
    }

    static ProcessPending(*) {
        if !this.enabled || !this.hasPending
            return
        if this.busy {
            ; 保留 pending，busy 结束后 finally 再调度
            return
        }
        this.hasPending := false
        gen := this.generation
        hwnd := this.pendingHwnd
        processName := this.pendingProcess
        this.TryCopy(processName, hwnd, gen)
    }

    static TryCopy(processName := "", hwnd := 0, gen := 0) {
        if !this.enabled || this.busy
            return
        this.busy := true
        snapshot := false
        ownedSeq := 0
        try {
            if !this.RevalidateTarget(hwnd, processName) {
                Logger.Debug("AutoCopy 取消：目标窗口校验失败 process=" processName)
                return
            }

            cap := ClipboardManager.Capture()
            if !cap.ok {
                if (cap.error = "snapshot_too_large") {
                    if this.showTip
                        ToolTipManager.ShowError("剪贴板过大，已跳过", this.tipMs)
                }
                return
            }
            snapshot := cap
            initialSeq := ClipboardManager.GetSequenceNumber()
            if (initialSeq = 0) {
                Logger.Warn("AutoCopy 无法读取剪贴板序列号，中止")
                return
            }

            if !ClipboardManager.ClearWithRetry() {
                Logger.Warn("AutoCopy 清空剪贴板失败，中止")
                ; 仅当失败清空已由本进程取得剪贴板所有权时恢复
                if ClipboardManager.IsOwnedByCurrentProcess()
                    ClipboardManager.Restore(snapshot)
                snapshot := false
                return
            }
            ownedSeq := ClipboardManager.GetSequenceNumber()
            if (ownedSeq = 0) {
                Logger.Warn("AutoCopy 清空后序列号不可用，立即恢复")
                ClipboardManager.Restore(snapshot)
                snapshot := false
                return
            }

            attempts := this.retryCount + 1
            success := false

            loop attempts {
                attempt := A_Index
                if (attempt > 1) {
                    if !this.RevalidateTarget(hwnd, processName)
                        break
                    if !ClipboardManager.ClearWithRetry()
                        break
                    ownedSeq := ClipboardManager.GetSequenceNumber()
                    Sleep(this.retryDelayMs)
                } else {
                    Sleep(20)
                }

                seqBeforeSend := ClipboardManager.GetSequenceNumber()
                Send("^c")
                copyResult := ClipboardManager.WaitForSequenceChange(
                    seqBeforeSend,
                    this.clipWaitTimeout,
                    this.waitForAnyData,
                    processName
                )
                if copyResult.changed
                    ownedSeq := copyResult.seq
                if copyResult.changed && copyResult.hasData {
                    ClipboardManager.RememberCurrentText()
                    success := true
                    Logger.Info(Format("AutoCopy 成功 process={1} attempt={2} len={3}"
                        , processName, attempt, StrLen(ClipboardManager.GetText())))
                    break
                }
            }

            if success {
                if this.showTip
                    ToolTipManager.ShowSuccess("已复制", this.tipMs)
            } else {
                this.SafeRestore(snapshot, ownedSeq)
                Logger.Warn("AutoCopy 失败 process=" processName)
                if this.showTip
                    ToolTipManager.ShowError("复制失败", this.tipMs)
            }
        } catch as err {
            Logger.Error("AutoCopy.TryCopy 异常: " err.Message)
            try this.SafeRestore(snapshot, ownedSeq)
        } finally {
            snapshot := false
            this.busy := false
            if this.enabled && (this.hasPending || this.generation != gen)
                this.ScheduleDebounce()
        }
    }

    static SafeRestore(snapshot, ownedSeq) {
        if !snapshot
            return false
        cur := ClipboardManager.GetSequenceNumber()
        if this.ShouldRestore(ownedSeq, cur)
            return ClipboardManager.Restore(snapshot)
        Logger.Info("AutoCopy 跳过恢复：剪贴板序列已变化 owned=" ownedSeq " cur=" cur)
        return false
    }

    ; 仅恢复仍由当前操作最后一次写入的剪贴板版本。
    static ShouldRestore(ownedSeq, currentSeq) {
        return ownedSeq != 0 && currentSeq != 0 && currentSeq = ownedSeq
    }

    ; 重新验证目标窗口仍在、进程仍允许、前台匹配（或成功激活）
    static RevalidateTarget(hwnd, processName) {
        if !hwnd || !Utils.IsWindowAlive(hwnd)
            return false
        name := Utils.GetProcessNameFromHwnd(hwnd)
        if (name = "")
            name := processName
        if !WindowFilter.IsAllowed(name)
            return false

        fg := Utils.GetForegroundHwnd()
        if (fg = hwnd)
            return true

        if this.activateTarget {
            try {
                WinActivate("ahk_id " hwnd)
                loop 10 {
                    if (Utils.GetForegroundHwnd() = hwnd)
                        return true
                    Sleep(20)
                }
            } catch {
            }
            return false
        }

        ; 未要求激活：若前台已变，取消以免复制到错误窗口
        Logger.Debug("AutoCopy 前台已切换 fg=" fg " target=" hwnd)
        return false
    }

    static StatusText() {
        return Format("AutoCopy enabled={1} busy={2} pending={3} anyData={4}"
            , this.enabled, this.busy, this.hasPending, this.waitForAnyData)
    }

    static Shutdown() {
        this.CancelDebounce()
        this.hasPending := false
        this.UnregisterHotkeys()
    }
}
