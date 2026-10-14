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
    AutoHotkey 安装目录(含 v2\AutoHotkey64.exe 与 Compiler\Ahk2Exe.exe)
    默认 "C:\Program Files\AutoHotkey";若该目录缺组件,会自动回退到用户级
    (%LocalAppData%\Programs\AutoHotkey) 等常见位置。

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
$OutExe    = Join-Path $OutDir "ScreenPlus.exe"

# ---- 定位 AutoHotkey 安装目录 ----
# 优先使用 -AhkDir;若其中缺少 Ahk2Exe(官方安装器需访问 api.github.com,
# 在部分网络下会失败),再尝试常见位置,包括用户级安装目录。
function Resolve-AhkDir([string]$Preferred) {
    $candidates = @($Preferred)
    if ($env:LOCALAPPDATA) {
        $candidates += (Join-Path $env:LOCALAPPDATA "Programs\AutoHotkey")
    }
    if ($env:ProgramFiles) {
        $candidates += (Join-Path $env:ProgramFiles "AutoHotkey")
    }
    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} "AutoHotkey")
    }
    foreach ($dir in $candidates) {
        if ([string]::IsNullOrEmpty($dir)) { continue }
        if ((Test-Path -LiteralPath (Join-Path $dir "Compiler\Ahk2Exe.exe")) -and
            (Test-Path -LiteralPath (Join-Path $dir "v2\AutoHotkey64.exe"))) {
            return $dir
        }
    }
    return $Preferred   # 均未命中,交由后续 Assert 报错
}

$resolvedAhkDir = Resolve-AhkDir $AhkDir
if ($resolvedAhkDir -ne $AhkDir) {
    Write-Host "[INFO] -AhkDir 缺少组件,改用: $resolvedAhkDir" -ForegroundColor Yellow
}
$AhkDir    = $resolvedAhkDir
$AhkExe    = Join-Path $AhkDir "v2\AutoHotkey64.exe"
$Compiler  = Join-Path $AhkDir "Compiler\Ahk2Exe.exe"

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

# Ahk2Exe 退出码提示(十进制码 = 0x30 段错误,见 Ahk2Exe ErrorCodes.md)
function Get-Ahk2ExeHint([int]$Code) {
    switch ($Code) {
        49 { return "无法写入目标 exe。常见原因:Base 文件只读,或目标 exe 正在运行。" }
        50 { return "无法打开脚本或某个 #Include 文件。" }
        51 { return "未指定源文件。" }
        52 { return "指定的 Base 文件不存在。" }
        65 { return "无法复制 Base 文件到目标位置(权限或磁盘空间?)。" }
        default { return "" }
    }
}

Assert-File $EntryAhk "入口脚本 screen.ahk"
Assert-File $AhkExe  "AutoHotkey64.exe (v2 x64)"
Assert-File $Compiler "Ahk2Exe.exe 编译器"

# 校验 x64(Ahk2Exe 用 64 位 base 才能产出纯 x64 exe)
$baseBits = (Get-Item -LiteralPath $AhkExe).Length  # 仅存在性提示
Write-Host "[INFO] base size = $baseBits bytes(将作为 /base 使用)"

# Ahk2Exe 需要可写的 Base:它先把 Base 复制到临时文件,再写入脚本资源。
# 只读的 Base 会使 BeginUpdateResource 失败,Ahk2Exe 以退出码 49 结束。
# 这里准备一份可写的临时副本,避免修改用户的 AutoHotkey 安装目录。
$BaseForCompile = $AhkExe
$tempBase = $null
if ((Get-Item -LiteralPath $AhkExe).IsReadOnly) {
    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("ScreenPlus-base-{0}.exe" -f ([guid]::NewGuid().ToString("N")))
    try {
        Copy-Item -LiteralPath $AhkExe -Destination $tempBase -Force
        Set-ItemProperty -LiteralPath $tempBase -Name IsReadOnly -Value $false
        $BaseForCompile = $tempBase
        Write-Host "[INFO] Base 只读 → 已改用可写临时副本: $tempBase" -ForegroundColor Yellow
    } catch {
        Write-Host "[FAIL] 无法准备可写 Base 副本: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# ---- 输出目录 ----
# -Clean 会删掉整个 OutDir,而 portable.flag.example 模板就住在默认 OutDir(dist\)。
# 先读入模板字节(优先源码 dist\,退化到 OutDir 内),清空后再写回,避免被一起删掉。
$portableTemplate = Join-Path $OutDir "portable.flag.example"
$portableBytes    = $null
foreach ($cand in @((Join-Path $Source "dist\portable.flag.example"), $portableTemplate)) {
    if (Test-Path -LiteralPath $cand) {
        $portableBytes = [System.IO.File]::ReadAllBytes($cand)
        break
    }
}

if ($Clean -and (Test-Path -LiteralPath $OutDir)) {
    Write-Host "[CLEAN] 清空 $OutDir"
    Remove-Item -LiteralPath $OutDir -Recurse -Force
}
if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}
if ($null -ne $portableBytes) {
    [System.IO.File]::WriteAllBytes($portableTemplate, $portableBytes)
    Write-Host "[KEEP] portable.flag.example 已保留"
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
$AhkShort   = To-ShortPath $BaseForCompile

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
# 注意:退出码 0 表示成功,不能用 -not 判断(0 在 PowerShell 中为假)。
# 仅当 ExitCode 为 $null 时才回退到 $LASTEXITCODE。
if ($null -eq $code) { $code = $LASTEXITCODE }
if ($null -eq $code) { $code = -1 }
if ($code -ne 0 -or -not (Test-Path -LiteralPath $OutExe)) {
    Write-Host "[FAIL] Ahk2Exe 退出码=$code,未生成 exe" -ForegroundColor Red
    $hint = Get-Ahk2ExeHint $code
    if ($hint) { Write-Host "[HINT] $hint" -ForegroundColor Yellow }
    if (Test-Path "$OutDir\_ahk2exe.err.log") {
        Write-Host "---- stderr ----" -ForegroundColor Yellow
        Get-Content "$OutDir\_ahk2exe.err.log" -ErrorAction SilentlyContinue
    }
    if (Test-Path "$OutDir\_ahk2exe.out.log") {
        Write-Host "---- stdout ----" -ForegroundColor Yellow
        Get-Content "$OutDir\_ahk2exe.out.log" -ErrorAction SilentlyContinue
    }
    if ($tempBase -and (Test-Path -LiteralPath $tempBase)) {
        Remove-Item -LiteralPath $tempBase -Force -ErrorAction SilentlyContinue
    }
    exit 1
}

# 清理临时 Base 副本
if ($tempBase -and (Test-Path -LiteralPath $tempBase)) {
    Remove-Item -LiteralPath $tempBase -Force -ErrorAction SilentlyContinue
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
        @{ src = Join-Path $Source "VirtualDesktopAccessor.dll"; dst = $OutExe                        }
        @{ src = Join-Path $Source "screen.ini";                dst = Join-Path $OutDir "screen.ini"   }
        @{ src = (Join-Path $Source "dist\portable.flag.example"); dst = $portableTemplate           }
    )
    foreach ($c in $copies) {
        if ($c.src -eq $c.dst) { continue }   # 同路径无需复制(默认 OutDir 即 dist)
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
