# ScreenPlus / ahkhelper — Agent Instructions

## Product

- **Product name**: ScreenPlus
- **Repo folder**: ahkhelper
- **Runtime**: AutoHotkey v2 only (never v1 syntax)
- **Version**: 1.2.0+
- **Platform**: Windows x64 only (`A_PtrSize=8`)

## Source of truth

1. `docs/SPEC.md` — product requirements
2. `docs/TASK.md` — implementation order
3. `CONTEXT.md` — domain language
4. `docs/adr/` — architecture decisions (e.g. VD DLL contract)
5. `screen.ini` + `Config.DefaultMap` — runtime defaults

## Coding rules

- Chinese comments for modules and non-obvious logic
- Classes / functions: `PascalCase`
- Variables: `camelCase`
- Module surface: `Init` / `Reload` / `StatusText` / `Shutdown` where applicable
- No duplicated business logic — shared helpers in `Utils` or owner module
- Handle DLL / file / clipboard errors safely (try/catch, log, degrade)
- AutoCopy filters by **mouse-under window**, revalidates before Send, uses clipboard sequence ownership
- Config defaults under `%AppData%\ScreenPlus` unless `portable.flag`
- Config hot-reload goes through `App.ReloadAll` only (Tray must not re-orchestrate modules)

## Architecture

```
screen.ahk          → bootstrap + App.ReloadAll
modules/*.ahk       → one concern per file (+ PluginHost)
plugins/Loader.ahk  → static includes + Register
screen.ini          → user configuration
logs/               → runtime logs
scripts/            → verify_structure.sh, selftest.ahk
```

## Verification

Before claiming PASS:

- [ ] `./scripts/verify_structure.sh` → PASS
- [ ] Hotkeys: Alt+1..N / Alt+Shift+1..N (`HotkeyDesktops`)
- [ ] AutoCopy: debounce → filter → copy → ClipWait → retry → restore ClipboardAll
- [ ] PluginHost + Loader included
- [ ] On Windows: `AutoHotkey64.exe /ErrorStdOut scripts\selftest.ahk` exit 0
- [ ] On Windows: Ahk2Exe compile `screen.ahk` when claiming compile PASS

```bat
AutoHotkey64.exe /ErrorStdOut scripts\selftest.ahk
Ahk2Exe.exe /in screen.ahk /out ScreenPlus.exe
```

## Agent skills

- Use `CONTEXT.md` for domain language before planning.
- Use `docs/adr/` for durable architectural decisions.
- Use `.pi/plans/` for temporary plans/spikes.
- Use `tdd` for behavior changes, `diagnosing-bugs` for bugs, `codebase-design` for module/interface work.
- Do not return PASS unless checks actually ran (or environment limits are explicitly stated).

## Safety

- Do not commit secrets.
- Do not force-push or rewrite shared history without approval.
- Prefer smallest safe change over broad refactors.
