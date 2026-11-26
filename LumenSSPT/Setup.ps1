param([switch]$DemoOnly,[switch]$Rebuild)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if ($Rebuild -or -not (Test-Path 'build\LumenSSPT.exe') -or -not (Test-Path 'build\trace.cso')) {
    if (-not (Test-Path 'Build.ps1')) { throw 'Prebuilt files missing; re-extract the Windows x64 Actions artifact.' }
    & "$PSScriptRoot\Build.ps1"
} else { Write-Host 'Using precompiled DXR worker and shader; no compiler required.' }
if (-not (Test-Path '.venv\Scripts\python.exe')) {
    py -3.11 -m venv .venv
    if ($LASTEXITCODE -ne 0) { throw 'Install 64-bit Python 3.11 with the py launcher.' }
}
$python = '.\.venv\Scripts\python.exe'
& $python -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { throw 'pip update failed' }
& $python -m pip install -r requirements.txt
if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed' }
if (-not $DemoOnly) {
    New-Item -ItemType Directory -Force models | Out-Null
    if (-not (Test-Path models/depth.onnx)) {
        $url='https://huggingface.co/onnx-community/depth-anything-v2-small/resolve/34f40a4/onnx/model.onnx'
        Write-Host 'Downloading Depth Anything V2 Small ONNX from Hugging Face...'
        Invoke-WebRequest -Uri $url -OutFile models/depth.onnx.partial
        Move-Item models/depth.onnx.partial models/depth.onnx -Force
    }
}
Write-Host 'Setup complete. Run Demo.bat or Launch.bat.'
