param([string]$DxcPath = "")
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
function CheckExit { if ($LASTEXITCODE -ne 0) { throw "Build command failed with exit code $LASTEXITCODE" } }
if (-not $DxcPath) {
    $cmd = Get-Command dxc.exe -ErrorAction SilentlyContinue
    if ($cmd) { $DxcPath = $cmd.Source }
}
if (-not $DxcPath) {
    $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (Test-Path $kits) {
        $candidate = Get-ChildItem $kits -Directory | Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'x64\dxc.exe' } | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($candidate) { $DxcPath = $candidate }
    }
}
if (-not $DxcPath) { throw 'DXC not found. Install a current Windows SDK or download Microsoft DXC and rerun with -DxcPath C:\path\to\dxc.exe.' }
if (-not (Test-Path $DxcPath)) { throw "DXC not found: $DxcPath" }
$DxcPath = (Resolve-Path $DxcPath).Path
& cmake -S . -B build -G 'Visual Studio 17 2022' -A x64 "-DDXC_EXECUTABLE=$DxcPath"
CheckExit
& cmake --build build --config Release --parallel
CheckExit
if (-not (Test-Path LumenBridge.exe)) {
    $env:GOOS='windows'; $env:GOARCH='amd64'; $env:CGO_ENABLED='0'
    & go mod tidy
    CheckExit
    & go build -trimpath -ldflags '-s -w' -o LumenBridge.exe .
    CheckExit
}
New-Item -ItemType Directory -Force dist | Out-Null
Copy-Item build\Release\LumenGPU.exe,build\Release\LumenDraco.exe,build\Release\trace.cso,build\Release\resolve.cso,build\Release\wavelet.cso,build\Release\estimateMotion.cso,build\Release\interpolateFrame.cso,LumenBridge.exe,Install_LumenGPU_0.2.lua,Launch.bat,Connect-Roblox.bat,README.txt -Destination dist -Force
Copy-Item build\_deps\draco-src\LICENSE -Destination dist\DRACO-LICENSE.txt -Force
$notice = 'build\_deps\draco-src\NOTICE'; if (Test-Path $notice) { Copy-Item $notice -Destination dist\DRACO-NOTICE.txt -Force }
Write-Host 'Native application built in dist. Run Launch.bat after reading README.txt.'
