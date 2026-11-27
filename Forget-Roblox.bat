@echo off
cd /d "%~dp0"
if not exist LumenBridge.exe (echo Extract a complete Windows build first. & pause & exit /b 1)
echo Close any running LumenBridge session before forgetting authorization.
LumenBridge.exe --forget
pause
