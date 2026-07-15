ScreenPlus 1.2.0 发布包
======================

文件说明
--------
ScreenPlus.exe              主程序（x64，Ahk2Exe 编译）
screen.ini                  默认配置（首次运行可复制到 %AppData%\ScreenPlus）
VirtualDesktopAccessor.dll  虚拟桌面 DLL（与 exe 同目录，可选但推荐）

运行
----
双击 ScreenPlus.exe，或：
  ScreenPlus.exe

便携模式
--------
在 exe 同目录放置空文件 portable.flag
配置与日志将使用 exe 目录而非 AppData。

自启
----
shell:startup 放入 ScreenPlus.exe 快捷方式。

热键（默认 HotkeyDesktops=3）
----
Alt+1 / Alt+2 / Alt+3           切换虚拟桌面
Alt+Shift+1 / 2 / 3             将当前窗口移到对应桌面

要求
----
Windows 10 22H2 / Windows 11 x64

更多：docs/INSTALL.md
