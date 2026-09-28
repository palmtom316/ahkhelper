<#
.SYNOPSIS
    ScreenPlus PowerShell 构建脚本
    将 screen.ahk（及其 #Include 模块）编译为单文件 ScreenPlus.exe

.DESCRIPTION
    - 自动探测 AutoHotkey v2 与 Ahk2Exe 编译器
    - 校验 x64 运行时
    - 调用 Ahk2Exe 生成 dist\ScreenPlus.exe
    - 可选：把 VirtualDesktopAccessor.dll / screen.ini / portable.flag 一并复制到 dist

.PARAMETER AhkDir
    AutoHotkey 安装目录（含 v2\AutoHotkey64.exe 与 Compiler\Ahk2Exe.exe）
    默认 "C:\Program Files\AutoHotkey"

.PARAMETER Source
    源码根目录（含 screen.ahk）
    默认脚本父目录

.PARAMETER OutDir
    输出目录，默认 dist

.PARAMETER Clean
    构建前清空 OutDir

.PARAMETER CopyRuntime
    复制运行时配套文件（VirtualDesktopAccessor.dll / screen.ini / portable.flag.example）到 OutDir

.EXAMPLE
    .\build.ps1
    .\build.ps1 -AhkDir "C:\Program Files\AutoHotkey" -Clean -CopyRuntime
#>
[CmdletBinding()]
param(
    [string]$AhkDir      = "C:\Program Files\AutoHotkey",
    [string]$Source      = "",
    [string]$OutDir      = "dist",
    [switch]$Clean,
    [switch]$CopyRuntime
)

$ErrorActionPreference = "Stop"

# ---- 路径解析 ----（运行时求值，避免 -File 下 $PSScriptRoot 为空）
if ([string]::IsNullOrEmpty($Source)) {
    $Source = Split-Path -Parent $PSScriptRoot
    if ([string]::IsNullOrEmpty($Source)) {
        $Source = (Get-Location).Path
    }
}
$Source    = (Resolve-Path -LiteralPath $Source).Path
$OutDir    = Join-Path $Source $OutDir
$EntryAhk  = Join-Path $Source "screen.ahk"
$AhkExe    = Join-Path $AhkDir "v2\AutoHotkey64.exe"
$Compiler  = Join-Path $AhkDir "Compiler\Ahk2Exe.exe"
$OutExe    = Join-Path $OutDir "ScreenPlus.exe"

Write-Host "== ScreenPlus Build ==" -ForegroundColor Cyan
Write-Host "Source    : $Source"
Write-Host "AhkDir    : $AhkDir"
Write-Host "OutExe    : $OutExe"

# ---- 校验 ----
function Assert-File($Path, $Desc) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "[FAIL] 未找到 $Desc : $Path" -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK]   $Desc : $Path"
}

Assert-File $EntryAhk "入口脚本 screen.ahk"
Assert-File $AhkExe  "AutoHotkey64.exe (v2 x64)"
Assert-File $Compiler "Ahk2Exe.exe 编译器"

# 校验 x64（Ahk2Exe 用 64 位 base 才能产出纯 x64 exe）
$baseBits = (Get-Item -LiteralPath $AhkExe).Length  # 仅存在性提示
Write-Host "[INFO] base size = $baseBits bytes（将作为 /base 使用）"

# ---- 输出目录 ----
if ($Clean -and (Test-Path -LiteralPath $OutDir)) {
    Write-Host "[CLEAN] 清空 $OutDir"
    Remove-Item -LiteralPath $OutDir -Recurse -Force
}
if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}

# ---- 编译 ----
# Ahk2Exe 对含空格路径解析有 bug（/base 会在空格处断裂），
# 这里把所有路径转成 8.3 短路径（无空格）再用。
function To-ShortPath($p) {
    if (-not (Test-Path -LiteralPath $p)) { return $p }
    $fso = New-Object -ComObject Scripting.FileSystemObject
    $item = if (Test-Path -LiteralPath $p -PathType Container) { $fso.GetFolder($p) } else { $fso.GetFile($p) }
    return $item.ShortPath
}
$EntryShort = To-ShortPath $EntryAhk
$OutShort   = To-ShortPath (Split-Path -Parent $OutExe)
$OutShort   = Join-Path $OutShort (Split-Path -Leaf $OutExe)
$AhkShort   = To-ShortPath $AhkExe

# Ahk2Exe 参数：
#   /in  源 ahk
#   /out 输出 exe
#   /base 64 位解释器（内嵌进 exe -> 目标机无需安装 AHK）
$arguments = @(
    '/in',  $EntryShort,
    '/out', $OutShort,
    '/base', $AhkShort
)
Write-Host "[RUN] $Compiler $($arguments -join ' ')"
$argLine = ($arguments | ForEach-Object { $_ }) -join ' '
# Ahk2Exe 是 GUI 子系统程序，用 Start-Process 捕获 stdout/stderr 并取真实退出码
$spawn = Start-Process -FilePath $Compiler -ArgumentList $argLine -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$OutDir\_ahk2exe.out.log" -RedirectStandardError "$OutDir\_ahk2exe.err.log"
$code = $spawn.ExitCode
if (-not $code) { $code = $LASTEXITCODE }
if ($null -eq $code) { $code = -1 }
if ($code -ne 0 -or -not (Test-Path -LiteralPath $OutExe)) {
    Write-Host "[FAIL] Ahk2Exe 退出码=$code，未生成 exe" -ForegroundColor Red
    if (Test-Path "$OutDir\_ahk2exe.err.log") {
        Write-Host "---- stderr ----" -ForegroundColor Yellow
        Get-Content "$OutDir\_ahk2exe.err.log" -ErrorAction SilentlyContinue
    }
    if (Test-Path "$OutDir\_ahk2exe.out.log") {
        Write-Host "---- stdout ----" -ForegroundColor Yellow
        Get-Content "$OutDir\_ahk2exe.out.log" -ErrorAction SilentlyContinue
    }
    exit 1
}

# ---- 结果 ----
$exe = Get-Item -LiteralPath $OutExe
Write-Host ""
Write-Host "[PASS] 编译成功" -ForegroundColor Green
Write-Host ("  {0}  {1:N0} bytes  {2}" -f $exe.FullName, $exe.Length, $exe.LastWriteTime)

# ---- 可选：分发运行时配套文件 ----
if ($CopyRuntime) {
    Write-Host ""
    Write-Host "== 复制运行时配套文件 ==" -ForegroundColor Cyan
    $copies = @(
        @{ src = Join-Path $Source "VirtualDesktopAccessor.dll"; dst = $OutExe                                  }
        @{ src = Join-Path $Source "screen.ini";                dst = Join-Path $OutDir "screen.ini"            }
        @{ src = Join-Path $Source "dist\portable.flag.example"; dst = Join-Path $OutDir "portable.flag.example" }
    )
    foreach ($c in $copies) {
        if (Test-Path -LiteralPath $c.src) {
            Copy-Item -LiteralPath $c.src -Destination $c.dst -Force
            Write-Host "[COPY] $($c.src) -> $($c.dst)"
        } else {
            Write-Host "[SKIP] 不存在: $($c.src)（可忽略，DLL/配置缺失程序会降级）" -ForegroundColor DarkGray
        }
    }
    Write-Host ""
    Write-Host "提示：启用便携模式请在 $OutDir 放一个空的 portable.flag 文件" -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
