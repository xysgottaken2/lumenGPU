$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
function Require-Success { if ($LASTEXITCODE -ne 0) { throw "External command failed: $LASTEXITCODE" } }
$dx = Get-Command dxc.exe -ErrorAction SilentlyContinue
if ($dx) { $dxc = $dx.Source } else {
    $sdk = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $dxc = Get-ChildItem "$sdk\*\x64\dxc.exe" -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $dxc) { throw 'DXC not found.' }
cmake -S . -B build -G 'Visual Studio 17 2022' -A x64
Require-Success
cmake --build build --config Release --parallel
Require-Success
& $dxc -T cs_6_5 -E main -O3 -Fo build/trace.cso shaders/trace.hlsl
Require-Success
Write-Host 'Native DXR worker and shader built.'
