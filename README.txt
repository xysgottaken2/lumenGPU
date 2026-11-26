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

V0.2.2 control diagnostics: install matching bridge, renderer, shader and Lua together. F2 ON / HTTP 204 / [x,z] in title means native input captured and posted. Studio button Input ON means the bridge response reached client. Movement and camera update now run on Heartbeat; /api/update-controls is an explicit endpoint. F2 or Esc releases mouse. This is a targeted unverified runtime fix, not a confirmed cause. Studio may still throttle background simulation. Previous /api/update?controls=1 remains compatible on the new bridge.

V0.2.3: third-person orbit camera (6–20 studs initial distance, collision ray), local avatar geometry captured by client separately from world snapshot; body parts and accessories remain box approximations. World snapshot ~0.65s, avatar and camera ~0.135s plus request time, native poll ~25ms plus requests. F6 toggles short camera smoothing; adds a little latency but reduces discrete jumps. Title shows observed scene sync Hz separately from render FPS. HTTP request budget still limits live responsiveness; no claim of 144Hz game sync. Reinstall Lua and replace executables together. Runtime and new native build unverified at commit time.

V0.3 experimental update: persistent Studio WebSocket at ws://127.0.0.1:8765/api/ws with HTTP fallback. Studio sends camera/avatar at target 60 Hz, world snapshot once per second. Native HTTP polls locally with unchanged-revision omission. Scene capacity 16,384 boxes total (16,320 world plus 64 avatar); no nearest-part sorting. Actual mesh/texture export and Terrain unsupported. Ray distance default 10,000, configurable 100–50,000 studs. Glass transmission uses Fresnel/refraction and approximate tint; opaque shadow rays still block glass. Glossy GGX half-vector sampling is approximate, not full MIS or unbiased BRDF. F1 actual Dear ImGui, F2 capture, F6 smooth. Settings include SPP, bounces, GI, reflections, glass, exposure, sky, sun, ambient, tonemap, ray distance, orbit distance, FOV, sensitivity. Resolution still launch argument. Studio WebSocket support and GPU runtime not tested by author. Build downloads pinned ImGui v1.90.9 and gorilla/websocket v1.5.3. New binary protocol LGR3; update all files together.

V0.3.1: fixes suspected lighting regression from opaque proxy boxes enclosing the camera. Terrain is explicitly excluded because voxel geometry is unsupported. Native containment test handles rotated boxes and updates acceleration structure when enclosure membership changes; transmissive volumes are retained if glass enabled. Title 'skip' reports omitted proxies. Debug 4 shows direct sun visibility times cosine, debug 5 shows upward sky visibility. Debug 3 remains unoccluded procedural sky. No lighting intensity workaround. Some legitimate opaque geometry can be temporarily omitted if the camera clips into it. Runtime diagnosis remains unverified.

V0.4: original LumenPT material ideas ported (GGX Smith/Fresnel, Lambert, specular attributes, emission color, sky sampling/MIS, dielectric Fresnel, RR). Still not full parity: no emissive-area NEE/MIS, local lights, texture sampling, real arbitrary MeshPart/UGC triangle assets or Terrain. Balls and cylinders use actual tessellated triangle BLAS and smooth normals. Spatial guided denoise runs on GPU, not DLSS/AI. Default output 1280x720, internal scale .5 (640x360), adjustable live .25-1; output dimensions set via Launch.bat args. Moving physics or CFrame-promoted parts send with avatar packets, max 960 moving + 64 avatar and 15360 static. Larger scenes still limited; server-side movement replication and TLAS cost can reduce sync. Studio-only. Build and GPU runtime not verified at commit. Update all files including resolve.cso.

V0.5: authorized MeshPart.MeshContent and SpecialMesh FileMesh export using EditableMesh. Enable Allow Mesh / Image APIs in Studio if needed. MeshPart sizing follows Size/MeshSize; legacy FileMesh uses Scale/Offset. Cached triangle lists with flat face normals and shared DXR BLAS. Rigid UGC accessories and custom meshes work only if Roblox allows asset read; inaccessible/oversized meshes fall back to boxes. No layered clothing deformation, bone skinning, UVs or texture maps. Limits: 20k triangles per mesh, 256 meshes, 500k triangles total per bridge session. Mesh asset transfers paced and on a separate native worker; initial BLAS builds can briefly stall rendering. LGR4 scene record layout unchanged; shape IDs >=3 identify mesh assets. Replace both executables, shaders and Studio installer. Restart Studio Play if restarting the bridge to rebuild the mesh cache. GPU and Studio runtime unverified.

V0.6: Studio camera and geometry on independent persistent sockets. Camera pipeline has up to four outstanding requests; geometry acknowledgements do not block camera. Native renderer uses independent input, camera and geometry WebSockets; native mesh asset fetch remains HTTP. Camera and geometry binary packets retain LGR4 format, separate revision tracking. Geometry updates never overwrite camera state. TLAS uses ALLOW_UPDATE/PERFORM_UPDATE with reusable scratch and instance buffers, full rebuild on changed BLAS layout or after 120 refits. Camera smoothing off by default (F6 enables). Received camera Hz vs shown Hz, TLAS time and refit/rebuild counters in title. Studio capture still nominal 60 Hz and moving geometry ~30 Hz. Input polling worker sends at ~120 Hz, actual mouse/key sampling still on render/UI loop. Runtime unverified. Replace all files and reinstall Lua.

V0.7: camera and character are sampled together and atomically received in the native pose stream; static geometry and other moving objects use independent native streams. Pose includes up to 64 complete avatar part records (not a transform-only delta codec); world updates transmit whole static snapshots only on changes/reconnect and moving updates transmit only the moving subset. No full-world transfer due to avatar motion. Native still assembles the local instance list and refits TLAS. F6 optional matched camera/avatar smoothing (off by default, snaps on layout change/large jumps). Title shows camera received/shown Hz, changed pose Hz, moving and world snapshot Hz. Camera HTTP fallback still limited, but includes character. Source tests added for paired packets and isolated revisions. Replace EXEs, shaders and Lua together. Runtime unverified.

V0.8 preview: client lighting follows GetSunDirection, ClockTime, Brightness, Sky.SunAngularSize and Sky.CelestialBodiesShown. Approximate procedural day/night/twilight and visible sun on primary/delta paths. Default procedural sun disk; optional local sun.png (RGBA, rescaled 128x128) beside LumenGPU.exe loaded at startup. Roblox SunTextureId and custom skyboxes are not automatically extracted. A-trous wavelet denoiser is spatial, not NRD, adjustable 1-4 passes at internal render resolution; original filter available. NRD integration remains incomplete and requires correctly separated radiance, hit distances, normal/roughness, motion vectors and history resources. Replace all files (including wavelet.cso) and reinstall Lua. Runtime unverified.
