#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail=0
need() {
  if [[ ! -e "$1" ]]; then echo "MISSING: $1"; fail=1; else echo "OK: $1"; fi
}
echo "== structure =="
for f in screen.ahk screen.ini modules/{Utils,Config,Logger,ClipboardManager,AutoCopy,VirtualDesktop,WindowFilter,TrayMenu,ToolTipManager,PluginHost}.ahk plugins/Loader.ahk scripts/selftest.ahk; do
  need "$f"
done
echo
echo "== review-driven markers =="
grep -q 'GetClipboardSequenceNumber' modules/ClipboardManager.ahk && echo OK: sequence number || { echo FAIL: sequence; fail=1; }
grep -qE 'static lastSnapshot|this\.lastSnapshot' modules/ClipboardManager.ahk && { echo FAIL: lastSnapshot still present; fail=1; } || echo OK: no lastSnapshot
grep -qE 'static Fingerprint|Fingerprint\(' modules/ClipboardManager.ahk && { echo FAIL: Fingerprint still present; fail=1; } || echo OK: no Fingerprint
grep -q 'GetSequenceNumber' modules/ClipboardManager.ahk && echo OK: GetSequenceNumber
grep -q 'GetOwnerProcessName' modules/ClipboardManager.ahk && echo OK: clipboard owner filter || { echo FAIL: clipboard owner filter; fail=1; }
grep -q 'debounceTimer' modules/AutoCopy.ahk && echo OK: single debounce timer || { echo FAIL: debounceTimer; fail=1; }
grep -q 'RevalidateTarget' modules/AutoCopy.ahk && echo OK: RevalidateTarget || { echo FAIL: revalidate; fail=1; }
grep -q 'SafeRestore' modules/AutoCopy.ahk && echo OK: SafeRestore || { echo FAIL: SafeRestore; fail=1; }
grep -q 'ShouldRestore' modules/AutoCopy.ahk && echo OK: sequence ownership predicate || { echo FAIL: ShouldRestore; fail=1; }
grep -q 'IsSet(this\.' modules/*.ahk && { echo FAIL: IsSet property expression remains; fail=1; } || echo OK: no IsSet property expressions
grep -q 'CanRegisterSwitchHotkeys' modules/VirtualDesktop.ahk && echo OK: VD ready-aware hotkeys || { echo FAIL: VD hotkey readiness; fail=1; }
grep -q 'newLogDir != this.logDir' modules/Logger.ahk && echo OK: Logger path reload || { echo FAIL: Logger path reload; fail=1; }
grep -q 'ShutdownBackend' modules/VirtualDesktop.ahk && echo OK: ShutdownBackend
grep -q 'Critical' modules/VirtualDesktop.ahk && echo OK: Critical unload || { echo FAIL: critical unload; fail=1; }
grep -q 'LoadLibraryExW' modules/Utils.ahk && echo OK: LoadLibraryExW || { echo FAIL: LoadLibraryExW; fail=1; }
grep -q 'A_PtrSize' screen.ahk && echo OK: x64 guard || { echo FAIL: x64 guard; fail=1; }
grep -q 'GetConfigPath' screen.ahk && echo OK: AppData config path || { echo FAIL: config path; fail=1; }
grep -q 'this.Rebuild()' modules/TrayMenu.ahk && { echo FAIL: Tray still double Rebuild; fail=1; } || echo OK: no double Rebuild
grep -q 'plugins := Map' modules/PluginHost.ahk && echo OK: PluginHost Map || { echo FAIL: PluginHost Map; fail=1; }
grep -qE '^[[:space:]]*#Include[[:space:]]+ExamplePlugin' plugins/Loader.ahk && { echo FAIL: ExamplePlugin still included; fail=1; } || echo OK: Example not included by default
grep -q 'FallbackMode", "off"' modules/Config.ahk && echo OK: default fallback off || true
echo
if [[ "$fail" -eq 0 ]]; then echo "RESULT: PASS"; exit 0; fi
echo "RESULT: FAIL"; exit 1
