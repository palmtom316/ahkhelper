; ClipboardManager.ahk - ClipboardAll 快照 + 序列号 + 文本历史
; 调用方显式持有 snapshot 结果对象，不缓存全局快照

class ClipboardManager {
    static history := []
    static historyMax := 30
    static historyItemMaxKb := 512
    static historyTotalMaxMb := 8
    static historyBytes := 0
    static maxSnapshotMb := 64
    static logOperations := true

    static Init(cfg) {
        this.history := []
        this.historyBytes := 0
        this.ApplyConfig(cfg)
        Logger.Info(Format("ClipboardManager 初始化 historyMax={1} itemKb={2} totalMb={3}"
            , this.historyMax, this.historyItemMaxKb, this.historyTotalMaxMb))
        return true
    }

    static Reload(cfg) {
        this.ApplyConfig(cfg)
        Logger.Info("ClipboardManager 重载 kept=" this.history.Length " bytes=" this.historyBytes)
        return true
    }

    static ApplyConfig(cfg) {
        this.historyMax := cfg.GetInt("Clipboard", "HistoryMax", 30, 0, 100)
        this.historyItemMaxKb := cfg.GetInt("Clipboard", "HistoryItemMaxKb", 512, 16, 8192)
        this.historyTotalMaxMb := cfg.GetInt("Clipboard", "HistoryTotalMaxMb", 8, 1, 256)
        this.maxSnapshotMb := cfg.GetInt("Clipboard", "MaxSnapshotMb", 64, 1, 512)
        this.logOperations := cfg.GetBool("Clipboard", "LogOperations", true)
        this.TrimHistoryToLimits()
    }

    static GetSequenceNumber() {
        try {
            return DllCall("GetClipboardSequenceNumber", "UInt")
        } catch {
            return 0
        }
    }

    static GetOwnerHwnd() {
        try {
            return DllCall("GetClipboardOwner", "Ptr")
        } catch {
            return 0
        }
    }

    static GetOwnerProcessId() {
        hwnd := this.GetOwnerHwnd()
        if !hwnd
            return 0
        pid := 0
        try {
            DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid, "UInt")
            return pid
        } catch {
            return 0
        }
    }

    static GetOwnerProcessName() {
        hwnd := this.GetOwnerHwnd()
        return hwnd ? Utils.GetProcessNameFromHwnd(hwnd) : ""
    }

    static IsOwnedByCurrentProcess() {
        pid := this.GetOwnerProcessId()
        if !pid
            return false
        try {
            return pid = DllCall("GetCurrentProcessId", "UInt")
        } catch {
            return false
        }
    }

    ; 捕获完整剪贴板；过大时返回 {ok:false}
    static Capture() {
        try {
            snap := ClipboardAll()
            size := this.EstimateSize(snap)
            maxBytes := this.maxSnapshotMb * 1024 * 1024
            if (size > maxBytes) {
                Logger.Warn("Clipboard 快照过大 size=" size " max=" maxBytes)
                return { ok: false, data: "", size: size, error: "snapshot_too_large" }
            }
            return { ok: true, data: snap, size: size, error: "" }
        } catch as err {
            Logger.Error("ClipboardManager.Capture 失败: " err.Message)
            return { ok: false, data: "", size: 0, error: err.Message }
        }
    }

    static Restore(snapshot) {
        if !(snapshot is Object) || !snapshot.HasProp("data") {
            ; 兼容直接传入 ClipboardAll 缓冲
            data := snapshot
        } else {
            if !snapshot.ok
                return false
            data := snapshot.data
        }
        loop 3 {
            try {
                A_Clipboard := data
                if this.logOperations
                    Logger.Debug("Clipboard 已恢复")
                return true
            } catch as err {
                if (A_Index = 3) {
                    Logger.Error("ClipboardManager.Restore 失败: " err.Message)
                    return false
                }
                Sleep(15)
            }
        }
        return false
    }

    ; 可靠清空；有限重试
    static ClearWithRetry(maxAttempts := 3) {
        loop maxAttempts {
            try {
                A_Clipboard := ""
                ; 确认文本为空即可（不必再 ClipboardAll）
                if (this.GetText() = "")
                    return true
            } catch as err {
                if (A_Index = maxAttempts)
                    Logger.Error("ClipboardManager.Clear 失败: " err.Message)
            }
            Sleep(15)
        }
        return false
    }

    static GetText() {
        try {
            return A_Clipboard
        } catch {
            return ""
        }
    }

    static SetText(text) {
        try {
            A_Clipboard := text
            this.PushHistory(text)
            return true
        } catch as err {
            Logger.Error("ClipboardManager.SetText 失败: " err.Message)
            return false
        }
    }

    ; 等待序列号变化，返回最终序列和可用内容状态。
    ; ClipWait 只检查格式可用性，不物化完整 ClipboardAll。
    static WaitForSequenceChange(oldSeq, timeoutSec := 0.5, waitForAnyData := false
        , expectedProcessName := "") {
        deadline := A_TickCount + Integer(timeoutSec * 1000)
        targetSeq := 0
        targetChanged := false
        loop {
            cur := this.GetSequenceNumber()
            if (cur != 0 && cur != oldSeq) {
                ownerName := this.GetOwnerProcessName()
                ownerMatches := (expectedProcessName = ""
                    || ownerName = ""
                    || StrLower(ownerName) = StrLower(expectedProcessName))
                if ownerMatches {
                    targetSeq := cur
                    targetChanged := true
                    hasData := false
                    try hasData := !!ClipWait(0.01, waitForAnyData ? 1 : 0)
                    if hasData {
                        return {
                            changed: true,
                            seq: cur,
                            hasData: true,
                            ownerProcess: ownerName
                        }
                    }
                }
            }
            if (A_TickCount >= deadline)
                break
            Sleep(10)
        }
        return {
            changed: targetChanged,
            seq: targetSeq,
            hasData: false,
            ownerProcess: ""
        }
    }

    static RememberCurrentText() {
        text := this.GetText()
        if (text != "")
            this.PushHistory(text)
    }

    static PushHistory(text) {
        if (text = "")
            return
        maxChars := this.historyItemMaxKb * 1024 // 2  ; UTF-16 近似
        if (StrLen(text) > maxChars)
            text := SubStr(text, 1, maxChars) "…"

        if (this.history.Length > 0 && this.history[1] = text)
            return

        itemBytes := StrPut(text, "UTF-8") - 1
        this.history.InsertAt(1, text)
        this.historyBytes += itemBytes
        this.TrimHistoryToLimits()
        if this.logOperations
            Logger.Debug("Clipboard 历史 +1 n=" this.history.Length " bytes=" this.historyBytes)
    }

    static TrimHistoryToLimits() {
        maxTotal := this.historyTotalMaxMb * 1024 * 1024
        while (this.history.Length > this.historyMax && this.history.Length > 0) {
            removed := this.history.Pop()
            this.historyBytes -= (StrPut(removed, "UTF-8") - 1)
        }
        while (this.historyBytes > maxTotal && this.history.Length > 0) {
            removed := this.history.Pop()
            this.historyBytes -= (StrPut(removed, "UTF-8") - 1)
        }
        if (this.historyBytes < 0)
            this.historyBytes := 0
    }

    static ClearHistory() {
        this.history := []
        this.historyBytes := 0
    }

    static GetHistorySummary(maxItems := 5) {
        lines := []
        count := Min(maxItems, this.history.Length)
        loop count {
            item := this.history[A_Index]
            preview := RegExReplace(item, "[\r\n]+", " ")
            if (StrLen(preview) > 40)
                preview := SubStr(preview, 1, 40) "..."
            lines.Push("#" A_Index " " preview)
        }
        return lines
    }

    static UseHistoryItem(index) {
        if (index < 1 || index > this.history.Length)
            return false
        return this.SetText(this.history[index])
    }

    static EstimateSize(data) {
        try {
            if (data is Buffer)
                return data.Size
            try {
                if data.HasProp("Size")
                    return data.Size
            } catch {
            }
            return StrLen(String(data))
        } catch {
            return 0
        }
    }

    static StatusText() {
        return Format("Clipboard history={1}/{2} bytes={3}", this.history.Length, this.historyMax, this.historyBytes)
    }
}
