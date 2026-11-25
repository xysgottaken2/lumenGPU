LUMEN GPU 0.2 - native DXR prototype (SOURCE + BUILT BRIDGE)
==========================================================
This package is NOT a finished native Windows renderer executable. LumenBridge.exe
is a real compiled Windows x64 loopback HTTP bridge. LumenGPU.exe and trace.cso
must be built on Windows. No browser is used. No DLL injection or Roblox client
modification. Only use the Studio installer in your own local test experience.

Requirements to run the completed native build:
- Windows 10/11 with a current graphics driver and DirectX Raytracing Tier 1.1
  plus Shader Model 6.5 (the application checks both). RTX 2060 is a target.
- Roblox Studio local Play test, HTTP Requests enabled.

Build option A: local Windows PC
1. Install Visual Studio 2022 Build Tools with Desktop development with C++,
   a current Windows SDK and CMake tools. Ensure cmake is on PATH (Developer
   PowerShell for VS is suitable). The build needs Microsoft's dxc.exe; the
   script checks PATH and Windows Kits. If absent, get the official DXC from
   https://github.com/microsoft/DirectXShaderCompiler/releases and specify its
   x64 dxc.exe with -DxcPath. Go is only needed if rebuilding the supplied bridge.
2. In the extracted project folder run:
   .\Build-Windows.ps1
   Or .\Build-Windows.ps1 -DxcPath 'C:\path\to\dxc.exe'
   The script creates dist/ containing LumenGPU.exe, trace.cso and the bridge.
   If PowerShell blocks script execution, use an authorized Developer PowerShell
   environment or have the build done in CI; do not change system security policy.

Build option B: GitHub Actions (no local C++ tools)
1. Put the extracted source files at the root of a repository you control,
   including the hidden .github/workflows/windows-build.yml path.
2. In Actions select Build LUMEN GPU Windows x64, Run workflow. The workflow
   builds bridge and native application, then uploads LumenGPU-0.2-Windows-x64.
   This workflow is supplied but has NOT been run by the author in this environment.
   If the hosted Windows SDK lacks DXC, install Microsoft's DXC in the runner
   and supply its path to Build-Windows.ps1. Check logs for build errors.
3. Download and extract the artifact if the build succeeds.

Run the completed build:
- Double-click Launch.bat. A console hosts the local bridge; a native window
  renders a Cornell-box-like demo. No browser. Keep the console open.
- Launch.bat 1280 720 (from Command Prompt) selects a different internal resolution.
  Default 640x360; permitted 160x90 through 1920x1080. Window stretches output.
- B cycles maximum secondary bounces 0..4; S cycles SPP 1/2/4; A toggles stationary
  accumulation; R resets accumulation; D forces demo or returns to automatic
  Studio selection; F11 toggles borderless fullscreen; Esc closes the renderer.
  Controls and completed presentation-loop FPS appear in the window title.
- Paste Install_LumenGPU_0.2.lua into Studio Command Bar in Edit mode. Enable
  HTTP Requests under Experience Settings > Security. Enter local Play and press P
  in Studio to start/stop sending scene updates. Keep controlling your avatar
  in Studio, not the external window. Stop any older LUMEN CPU renderer first.
- Close the bridge console when finished. Server binds 127.0.0.1:8765 only.

What's implemented in source:
- Native D3D12 compute dispatch using DXR 1.1 RayQuery::TraceRayInline, shared
  triangle cube BLAS and per-part TLAS instances; no software BVH fallback.
- Diffuse bounces, approximate glossy metallic reflections, direct sun shadow
  sampling, emissive hits, ACES-style display transform, stationary accumulation.
- Native swapchain, no GPU->CPU image readback. CPU waits for each GPU dispatch;
  first implementation prioritizes correctness over pipelining.
- Background HTTP polling; v0.1 Studio protocol retained, local binary state endpoint.

Limitations:
- No OptiX, denoiser, DLSS, full GGX/MIS, texture/mesh export, or Dear ImGui yet.
- Boxes only; native Roblox materials simplified. Camera ~5 Hz, geometry ~1 Hz;
  motion is not fluid at those update rates. Character poses approximate boxes.
- Fixed internal resolution per launch, no input forwarding, no in-game display.
- Build environment lacked Windows SDK, DXC and GPU. C++/HLSL compilation,
  Windows execution, Studio connectivity and GPU FPS are unverified.
- Bridge Go tests passed; protocol parser can be tested on Linux (see tests).
  Native build workflow was not executed here. The source may require build fixes.

V0.2.1 hotfix: reinstall Install_LumenGPU_0.2.lua from this build. F2 in native window captures WASD/mouse/Space and sends local controls to the Studio client (first-person). Esc or loss of focus releases capture; controls expire on disconnect. F3 cycles path-traced / albedo / normals / sky-only; F4/F5 lower/raise exposure. Excludes local avatar and camera-enclosing boxes from exported geometry; PathIgnore=true excludes other problematic parts. Native lighting includes a small approximate ambient floor. Studio polling ~6 Hz, so movement/view latency remains. This patch is not runtime-tested.
