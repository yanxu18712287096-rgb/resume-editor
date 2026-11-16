@echo off
chcp 65001 >nul 2>&1
cd /d "%~dp0"

echo.
echo   =================================================
echo      我的简历 - 一键启动
echo   =================================================
echo.

REM 使用 PowerShell 脚本进行智能环境检测与自动安装
powershell -ExecutionPolicy Bypass -File "%~dp0run.ps1"

REM 如果 ps1 执行失败（例如 PowerShell 版本过低），回退到原方案
if errorlevel 1 (
    echo.
    echo   [WARN] PowerShell 方案不可用，尝试回退方案...
    echo.
    where python >nul 2>&1
    if errorlevel 1 (
        where py >nul 2>&1
        if errorlevel 1 (
            echo   [ERROR] 未找到 Python。请安装 Python 3 并添加到 PATH：
            echo          https://www.python.org/downloads/
            pause
            exit /b 1
        )
        py -3 "%~dp0start_all.py"
    ) else (
        python "%~dp0start_all.py"
    )
    if errorlevel 1 pause
)
