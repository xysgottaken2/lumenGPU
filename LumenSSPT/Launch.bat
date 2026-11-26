@echo off
cd /d "%~dp0"
if not exist .venv\Scripts\python.exe goto missing
.venv\Scripts\python.exe app.py %*
if errorlevel 1 pause
exit /b
:missing
echo Run Setup.ps1 first.
pause
