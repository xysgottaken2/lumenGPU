@echo off
cd /d "%~dp0"
if not exist LumenBridge.exe (echo Extract a complete Windows build first. & pause & exit /b 1)
start "LUMEN Bridge - Roblox connection" "%~dp0LumenBridge.exe" --connect
start "LUMEN native DXR" "%~dp0LumenGPU.exe" %*
