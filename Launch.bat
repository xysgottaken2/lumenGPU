@echo off
cd /d "%~dp0"
if not exist LumenGPU.exe (
  echo The native renderer has not been built. Read README.txt and run Build-Windows.ps1.
  pause
  exit /b 1
)
if not exist trace.cso (
  echo Missing trace.cso. Run the Windows build first.
  pause
  exit /b 1
)
start "LUMEN local bridge - close when done" "%~dp0LumenBridge.exe"
start "LUMEN native DXR" "%~dp0LumenGPU.exe" %*
