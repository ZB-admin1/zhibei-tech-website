@echo off
REM 智北科技 · 桌面端启动入口
REM 双击此文件即可启动服务器 + 打开桌面窗口
setlocal
cd /d "%~dp0"
python app.py
if errorlevel 1 (
    echo.
    echo Desktop app exited with error.
    pause
)
