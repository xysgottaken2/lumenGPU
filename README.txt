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

V0.8.1 colored transparent shadows: sunlight and sky NEE use RGB visibility through up to 16 transparent boundaries; opaque surfaces block normally. Closed panes apply tint and transmission once, with approximate Fresnel losses. The Glass / refraction toggle disables transparent visibility too. This is straight-line tinted transmission, not focused/refracted caustics. Extra ray queries may cost performance in layered glass. Direct sun visibility debug view now shows tint. No Studio protocol or Lua changes needed from V0.8; NRD and full SVGF are not implemented.

V0.8.2: scroll up/down when F2 controls are captured; zoom in to first person, scroll out to third person. Game tab has first/third person buttons. Native zoom range .5-40 studs, clamped to Roblox player zoom limits; LockFirstPerson respected. Local avatar stays in TLAS with secondary-ray mask when first person (shadows/reflections/GI remain), not visible to primary rays. Camera collision can enter first person near walls. First-person character yaw follows view; default AutoRotate restored on exit. LGR6 optional first-person flag, LGR4/LGR5 still parsed. Replace EXEs and shaders and reinstall Lua. Runtime unverified.

V0.8.3 preview: F2 enables native controls, free mouse in third person (hold RMB and drag to orbit), center-locked in first person; scroll zoom unchanged. Left click in both modes and right click in first person forwarded to Studio via documented UserInputService:CreateVirtualInput(), when available. In first person pointer coordinates are centered. Third-person RMB is reserved for camera rotation. Game HUD draws basic ScreenGui backgrounds, text, borders, corners, layout and clipping from client snapshots (10 Hz max). HUD uses independent native stream and is rendered after tonemapping. It does not render ImageLabels/ImageButtons' images, custom fonts, rich text styling, gradients, rotation, ViewportFrames, CoreGui, or fully reproduce complex ZIndex/insets. Text input, keyboard actions and hover/drag movement not forwarded; clicks are best effort and require Studio VirtualInput support. Replace all native files and reinstall Lua. Runtime unverified.

V0.8.4: RMB locks the cursor to its original position during third-person camera rotation and restores it on release. RMB press/release forwarded in both camera modes; middle click supported. Common Windows keys forwarded to Roblox VirtualInput with press/release (number row, numpad, letters, punctuation, arrows, modifiers, function keys). F1/F2/F11/Esc remain native shortcuts; F3-F6 and other graphics hotkeys are game keys while captured. CoreGui and keys unavailable through Roblox VirtualInput are not supported. Held virtual inputs released on native disconnect/release. Replace all application files and reinstall Lua. Runtime not tested.

V0.8.5: native WedgePart, CornerWedgePart and Part.Shape Wedge/CornerWedge, plus approximate open TrussPart lattice (AlternatingSupports, BridgeStyleSupports, NoSupports). Primitive normals come from triangles, with existing material and ray masks. Truss meshes cached by style and length; up to 256 bays, with reduced detail on extreme cache usage. Wedge orientation uses a one-time local raycast calibration when queryable, default otherwise. Truss beam dimensions are approximate, not exact Roblox meshes. Negative shape IDs -1..-5 reserved; existing positive mesh IDs unchanged. Replace native files and reinstall Lua. Runtime unverified.


## V0.9 preview — Lumenus

Lumenus runs inside LumenBridge, off the camera and geometry update threads. The Studio exporter discovers referenced mesh and image asset IDs and uses external retrieval when an EditableMesh load fails. The existing native DXR renderer receives normalized rigid triangle meshes through its existing mesh endpoint. No browser cookie extraction, game injection, or alternate endpoint retry on access denial.

External delivery requires a locally configured Roblox Open Cloud API key with the appropriate Asset Delivery permission (legacy-asset:manage). It can be set as the LUMEN_ASSET_API_KEY environment variable before launching the bridge. Do not paste it into Studio, source code, GitHub, or chat. Roblox decides whether each asset can be delivered; public third-party assets may be available, restricted assets remain unavailable. Only use assets you have permission to render externally. Official documentation: https://create.roblox.com/docs/cloud/reference/features/assets

Alternatively, put a legitimately obtained raw mesh in AssetImports/<numeric-id>.mesh next to the executable, or an image as <numeric-id>.png or .jpg. Originals are not deleted. Without a key or local file, the fallback stays a box. Existing EditableMesh extraction still works normally.

The worker queues and deduplicates requests, prioritizes meshes, and caches downloaded bytes under TempAssets/session-*/. Limits: 16 MiB per asset, 128 MiB total session disk use, 384 tracked requests and the existing 256-mesh/1.5-million-vertex renderer cap. Ctrl+C in the bridge console closes the worker and removes its own session directory; force-kill or a system crash may leave an orphan folder (delete manually after closing the bridge). No persistent asset library is created automatically.

Mesh formats: FileMesh v2/v3 and rigid v4/v5, highest-detail LOD, up to 20,000 triangles per mesh. Unsupported formats, skinned geometry, failed downloads and malformed data fall back to boxes. UVs, texture GPU upload/sampling, normal maps, procedural studs and material texture mapping are NOT implemented in this preview. PNG/JPEG image references are collected and cached for future work, not displayed by the renderer. No support for live asset property changes on existing objects yet. External delivery and real GPU runtime are not verified by CI. Replace all binaries and reinstall the Lua script in Edit mode.


## V0.9.1 development: Roblox OAuth connection

For local development register your own OAuth application in the official Roblox Creator Dashboard (Creation & Productivity Tools, public/PKCE client where available). Enable only the Asset Delivery scope `legacy-asset:manage`; add `http://localhost:8766/oauth/callback` as an exact redirect URL. If the scope is unavailable or Roblox declines authorization, use permitted local imports; do not substitute browser cookies or unsupported endpoints. Run Connect-Roblox.bat and enter your public Client ID (or set LUMEN_OAUTH_CLIENT_ID in your own terminal). Review Roblox's consent screen. Tokens remain only in memory for the bridge session, and no client secret or password is needed by the PKCE client. Close the old bridge before starting. Launch.bat remains local/API-key mode. Authorization does not guarantee access to third-party assets. Private apps are for limited testing; public distribution requires review. See https://create.roblox.com/docs/cloud/auth/oauth2-registration and https://create.roblox.com/docs/cloud/auth/oauth2-develop.


## V0.9.1 — base-color texture preview

Adds session-local 256x256 RGBA texture slots, UV preservation for supported external rigid meshes and readable EditableMeshes, barycentric sampling at each path hit, and one face overlay on block Parts (Decal or tiled Texture). MeshPart TextureID and SurfaceAppearance ColorMap are supported, with base-color tinting. Asset arrivals trigger scene refresh and accumulation reset without restarting. A fixed-size atlas is bounded to 128 textures (32 MiB pixels); the bridge uses PNG/JPEG and existing disk limits. Texture alpha is blended with base color, not cutout geometry; face orientation, color tint and tiling are approximations and need Studio testing. Normal/roughness/metalness maps, built-in materials/studs, multiple overlays/faces and skinned meshes remain unsupported. No mipmaps or texture compression yet; large asset loads can cause a brief renderer stall. Authorization is opt-in, restricted assets remain fallback, and local imports are still supported. Reinstall the Lua installer and replace ALL native files together. CI is compile/CPU tests only, not live Roblox/OAuth/DXR runtime validation.


## V0.9.2 — terrain and avatar decoder preview

Session disk storage has no aggregate byte cap; per-file 16 MiB, 128 texture slots, 256 meshes, 1.5M triangle vertices and 384 request entries still bound resource use. Normal Ctrl+C still removes the session folder. Roblox OAuth is unchanged. V1 text and V6 COREMESH v1, plus V4/V5 skin-envelope skipping (bind pose) are implemented. V7 Draco, facial animation and animated skinning are not yet supported. Failures log format and byte size. Bridge allocates stable texture slots across Play restarts. Classic Shirt/Pants/ShirtGraphic/CharacterMesh references are discovered and cached; clothing compositing is not implemented. Mesh texture discovery refreshes for avatars every three seconds. Terrain is a static occupancy isosurface approximation, sampled around the starting camera (or Terrain Vector3 attribute LumenTerrainCenter), 5x5 64-stud columns by default, two vertical chunks, up to 64 material meshes; set Terrain numeric attribute LumenTerrainRadius (64–192 studs in 64-stud steps) or LumenTerrainEnabled=false. Not exact engine terrain geometry, no water, no dynamic updates or terrain material textures. No new Roblox parts are created. Meshes upload incrementally. Large terrain can use the shared mesh budget. CI does not run Studio or a physical GPU; live test required. Replace all files and reinstall Lua.


## V0.9.2a — Draco hotfix

Lumenus decodes V7 COREMESH v2 via the bundled LumenDraco.exe (Google Draco 1.5.7, Apache-2.0). The isolated decoder receives compressed data over stdin and returns bounded vertex/face records over stdout, including mapped UVs. It runs once per V7 mesh request; LOD selection and existing mesh limits still apply. OAuth unchanged. No Python required. Keep LumenDraco.exe alongside LumenBridge.exe. V7 geometry is bind pose only; no bone deformation, layered clothing fitting or classic clothing compositing. Synthetic compression/decompression and bridge integration tests run in CI, real avatar files need Studio testing.


## V0.9.2b — scene validation hotfix

All 24-bit mesh IDs are now accepted by scene validation, matching the mesh endpoint. Coordinate/material bounds are unchanged. Rejection messages identify the offending group, row and validation category. Repeated geometry rejection retries are paced; warnings are rate limited. Reinstall the Lua exporter and replace binaries. OAuth, terrain, Draco and disk-cache behavior are unchanged. This fixes a concrete packet rejection bug; actual user scene testing is still necessary.


## V0.9.3 — visual materials and local lighting preview

SpawnLocation numeric decals are accepted; a procedural top spawn emblem approximates the built-in icon when no numeric decal is loaded. Studs/inlets/universal surfaces use per-face procedural shading (not physical geometry). SurfaceAppearance normal/roughness/metalness maps share the bounded 128-slot atlas; generated PBR uses albedo luminance gradients and roughness heuristics, not real measured material properties or AI. Generated PBR and procedural studs toggles are in Lighting; per-part LumenPBRStrength 0–1. Original Draco, binary and EditableMesh corner normals are streamed using LGM3; missing normals use geometric fallback. Tangent-space maps use per-triangle UV tangents. R6 CharacterMesh geometry and base/overlay texture references supported; classic clothing templates are still not composited, skinning/layered clothing not implemented. PointLight, SpotLight, SurfaceLight export nearest 64 enabled lights and sample one randomly per surface bounce with finite shadow rays; surface lights are center-point approximations, moving lights refresh with static snapshot, attenuation is approximate, emissive geometry not sampled explicitly. Lighting tab has Local light NEE toggle. Draco helper is hidden on Windows. Terrain behavior unchanged. Reinstall Lua and replace every binary/shader. CI checks synthetic protocol, mesh and shader compilation; no physical GPU or Studio runtime validation.

For PointLights inside opaque geometry, the parent can occlude the light; use a non-occluding fixture/attachment placement. Generated metalness is not inferred from albedo; material defaults remain unless a real MetalnessMap is supplied. Normal/roughness map-only SurfaceAppearance works with mesh UVs.


## V0.9.4 — avatar and image stability

Camera/control streaming no longer depends on avatar extraction succeeding. Avatar capture runs at 30 Hz, with per-part diagnostic/fallback. MeshContent and MeshSize access guarded; asset-ID fallback uses existing authorized Lumenus route. R6 CharacterMesh uses original mesh extents scaled relative to standard limb dimensions; standard R6 remains blocky. Classic shirt/pants/T-shirt layers project the 585x559 atlas onto body regions, alpha-composited in shader; R15 segmented mapping and non-box body projection are approximations, not Roblox's native UVs. CharacterMesh overlay is separate. No animated skinning, layered clothing, or guaranteed modern body-package conversion to R6. Texture mip chain generated once per texture (about 43 MiB at maximum slots), bilinear nearest mip with approximate ray-distance footprint. Materials tab adds normal/roughness strength, mip filtering, studs, and adjustable firefly luminance clamp (biased; 0 disables). Local light NEE uses up to four inexpensive importance candidates and a single visibility ray per bounce. Existing authentication, terrain and cache behavior retained. Replace all binaries/shaders and reinstall Lua. Automated CI does not verify live Studio or GPU output.


## V0.9.4a — experimental Lumen display pipeline

Includes V0.9.4 avatar/clothing and image stability work. Display tab: Lumen edge-aware spatial upscaler (default), bilinear and nearest, adjustable edge-aware sharpness and optional 2x frame generation (off by default). The upscaler uses depth/normal/albedo guidance with wavelet denoising or denoiser off; legacy spatial denoising retains its original resolve. Frame generation estimates bidirectional block motion on the GPU between consecutive full-output real frames, warps both toward their midpoint and blends with error rejection. It presents the intermediate before the newer real frame; HUD/UI are composited separately on both. This is not DLSS/FSR, no optical-flow hardware required, moving/disoccluded objects can ghost, and it adds latency. VSync limits output to display refresh; no guaranteed FPS gain, especially at low base FPS or on a saturated GPU. Separate real, generated and presented FPS counters; simulation/camera rates unchanged. Launch Connect-Roblox.bat 1920 1080 for 1080p output, then select render scale (0.5 = 960x540) and optional frame generation. Render scale 1.0 is native path tracing. New estimateMotion.cso and interpolateFrame.cso must be beside LumenGPU.exe. Frame generation disables itself if initialization fails or debug mode is selected; other features remain available. Replace all files, reinstall Lua. CI checks compilation, not runtime GPU quality or performance.


## V0.9.4b — HD clothing and head fallback

Adaptive image slots use 256, 512 or 1024 square pixels depending on source dimensions and remaining budget. A 585x559 classic clothing atlas fits in a 1024 slot when budget permits; this preserves source detail, not invented HD detail. Clothing uses a lower mip bias to keep detail close up. Base texture pixels limited to 96 MiB with reserve for all 128 slots; mip chains add about one third. Disk cache remains uncapped. Atlas offsets align to four dwords for exact float indexing. Heads use actual available meshes first; missing/built-in head geometry renders a rounded-cylinder approximation, with projected face decals. Draco meshes without UVs are accepted with zero UV coordinates. R6 body packages use live CharacterMesh or an asynchronous temporary model built from the actual HumanoidDescription via Roblox's supported API; this is not a conversion of R15-only bundles into R6 geometry. Diagnostic logs show the number of resolved R6 meshes. Actual body compatibility and clothing mapping still require Studio tests. Frame generation and upscaling unchanged. Replace all files and reinstall Lua.


## V0.9.5 — auto-start, smooth R6 bodies and particle preview

R6 Humanoid body parts no longer export studs/inlets; map parts retain their original surfaces. Studio streaming starts automatically on Play, P still toggles, and Workspace boolean attribute LumenAutoStart=false disables autostart. Bridge and renderer must still be launched normally. ParticleEmitter preview recreates continuous emission from public properties (not actual Roblox internal particles), max 24 nearby emitters, 64 sprites, 30 Hz simulation, 200-stud emitter selection. Supports numeric texture asset IDs via Lumenus, alpha/color/size sequences, rate, lifetime, speed, spread, rotation, acceleration, drag, LockedToPart, velocity inheritance and approximate brightness/additive blending. Built-in/unavailable particle textures use a soft radial fallback. No manual Emit/Clear observation, flipbooks, advanced orientation or emitter shapes. A shared DXR quad and camera-only ray mask composite sprites after denoising using the primary depth guide, without lighting/shadow/reflection participation; up to eight overlapping layers per output pixel. No particle rays in empty scenes. Materials tab Textured particles toggle; Workspace LumenParticlesEnabled=false stops simulation. Moving packets retain 1024-row cap. Existing camera target 60 Hz is unchanged; future transport improvements should isolate camera data from avatar/material payloads and avoid serializing unchanged data, not reduce render resolution or bounces. CI verifies compilation, not Studio runtime/performance. Replace all files and reinstall Lua.


## V0.9.6 — split pose transport and custom skyboxes

Camera packets retain the 60 Hz target but no longer contain character or moving-world rows. A dedicated pose WebSocket coalesces 30 Hz character snapshots independently from large geometry uploads; HTTP fallback remains. The native view stream sends character records only when pose revision changes, and accepts pose-only revisions without counting them as new camera packets. Moving objects still use their existing independent geometry stream; no reduction in SPP, bounces, texture resolution or lighting quality. Native receive limit matches full-size extended scene packets. Actual receive Hz depends on Roblox frame scheduling and machine load; this is not a guarantee of 60 or 120 Hz. Skyboxes use the six numeric Sky properties and SkyboxOrientation via authorized Lumenus image slots. When all six faces are available, sample the cubemap in the existing sky function for primary rays, indirect rays, reflections and sky NEE; the procedural sky is the fallback. Lighting tab Custom Roblox skybox toggle and Sky strength. Cubemap is LDR, not HDRI; no atmosphere/cloud rendering, no seam-aware filtering, exact face orientation requires live verification. Directional sun stays tied to Roblox Lighting. No new GPU descriptors. Existing OAuth, particles, HD textures, Draco, terrain, frame generation and upscaling retained. Reinstall Lua and replace all files. CI is compilation/protocol validation, not Studio runtime performance.


## V0.9.6a — paired avatar transport restored and skybox diagnostics

Restores V0.9.5 camera/character pairing and moving-object transport exactly, including the original 60 Hz camera send target, 30 Hz cached avatar capture, native pose revision handling and existing F6 smoothing. Removes the separate Studio pose socket. Retains the larger native packet capacity and sky environment protocol. Custom sky faces now use independent bounded asset-status polling via the existing authorized image endpoint, not one-shot image queue acknowledgments; Studio prints the asset IDs and ready/failed reasons. Native renderer shows loaded face count, and missing faces individually fall back to procedural sky. No guarantee all assets are available; built-in rbxasset paths remain unsupported and are reported. Exact face orientation and runtime receive rates require testing. No render-quality reductions. Reinstall Lua and replace binaries/shaders.
