# ADR 0001: VirtualDesktopAccessor DLL Contract

## Status

Accepted (2026-07-15)

## Context

ScreenPlus must preserve Alt+1/2/3 and Alt+Shift+1/2/3 for virtual desktops.
Windows has no stable public API for this across all builds; community DLLs wrap private COM interfaces.

## Decision

1. Prefer **Ciantic/VirtualDesktopAccessor** style DLL named `VirtualDesktopAccessor.dll` next to the script/exe.
2. **Required export**: `GoToDesktopNumber` (0-based desktop index, `Int`).
3. **Move export**: `MoveWindowToDesktopNumber(hwnd, desktopNumber)` — if missing, switch still works, move hotkeys show a tip.
4. **Optional**: `GetCurrentDesktopNumber`, `GetDesktopCount`, `IsWindowOnDesktopNumber`.
5. User numbering is **1-based**; convert with `index - 1` at the DLL boundary.
6. `FallbackMode`:
   - `off` (default): disable VD when DLL is unavailable.
   - `simulate`: absolute blind Left×N / Right×N (optional, not recommended).
7. Runtime requires Windows x64 / AutoHotkey 64-bit (`A_PtrSize=8`) and AMD64 DLL (PE Machine `0x8664`).

## Consequences

- Accurate move-window requires the DLL; fallback cannot faithfully implement Alt+Shift.
- Windows feature updates may break the DLL; users must upgrade the DLL independently of ScreenPlus.
- Hotkey count is configurable via `HotkeyDesktops` (1–9), not hard-coded forever at 3.
