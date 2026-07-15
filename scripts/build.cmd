@echo off
setlocal
set ROOT=%~dp0..
set AHK_BASE=%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe
set AHK2EXE=%ProgramFiles%\AutoHotkey\Compiler\Ahk2Exe.exe
if not exist "%AHK_BASE%" (
  echo AutoHotkey64.exe not found: %AHK_BASE%
  exit /b 1
)
if not exist "%AHK2EXE%" (
  echo Ahk2Exe.exe not found: %AHK2EXE%
  exit /b 1
)
if not exist "%ROOT%\dist" mkdir "%ROOT%\dist"
"%AHK2EXE%" /in "%ROOT%\screen.ahk" /out "%ROOT%\dist\ScreenPlus.exe" /base "%AHK_BASE%"
if errorlevel 1 exit /b 1
echo Built %ROOT%\dist\ScreenPlus.exe
echo Place x64 VirtualDesktopAccessor.dll next to the exe.
endlocal
