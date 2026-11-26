# LUMEN GPU 0.8 — day/night and wavelet preview

[Windows builds](../../actions) | [Setup](README.txt)

Studio lighting direction, ClockTime, Brightness, and Sky sun size/visibility synchronized with camera. Procedural day/night and visible sun; optional local sun.png next to LumenGPU.exe. GPU A-trous spatial wavelet denoising (not NVIDIA NRD), original filter retained. NRD integration is not completed. Replace all files and reinstall Lua. Runtime not benchmarked.

V0.8.1: colored direct sun and sky transmission through glass, including tinted visibility debug output. Thin-glass approximation, no focused caustics. NRD still incomplete.

V0.8.2: scroll zoom with F2 capture, first-person at minimum zoom, Roblox camera lock respected. Local avatar stays in the TLAS but is masked from primary camera rays; shadows/reflections/GI still include it. Replace native files and reinstall Lua.

V0.8.3 preview: third-person free cursor, first-person lock, RMB orbit, simple ScreenGui HUD and Studio VirtualInput mouse clicks. See README.txt for unsupported UI features and runtime caveats.

V0.8.4: anchored RMB orbit and right/middle-click plus keyboard edge forwarding to Studio. Native F1/F2/F11/Esc reserved. See README.txt for limitations.

V0.8.5: native wedge/corner wedge triangle geometry and approximate open trusses in all three styles. No EditableMesh permission required for these shapes. See README.txt.


## V0.9 preview — Lumenus

Lumenus runs inside LumenBridge, off the camera and geometry update threads. The Studio exporter discovers referenced mesh and image asset IDs and uses external retrieval when an EditableMesh load fails. The existing native DXR renderer receives normalized rigid triangle meshes through its existing mesh endpoint. No browser cookie extraction, game injection, or alternate endpoint retry on access denial.

External delivery requires a locally configured Roblox Open Cloud API key with the appropriate Asset Delivery permission (legacy-asset:manage). It can be set as the LUMEN_ASSET_API_KEY environment variable before launching the bridge. Do not paste it into Studio, source code, GitHub, or chat. Roblox decides whether each asset can be delivered; public third-party assets may be available, restricted assets remain unavailable. Only use assets you have permission to render externally. Official documentation: https://create.roblox.com/docs/cloud/reference/features/assets

Alternatively, put a legitimately obtained raw mesh in AssetImports/<numeric-id>.mesh next to the executable, or an image as <numeric-id>.png or .jpg. Originals are not deleted. Without a key or local file, the fallback stays a box. Existing EditableMesh extraction still works normally.

The worker queues and deduplicates requests, prioritizes meshes, and caches downloaded bytes under TempAssets/session-*/. Limits: 16 MiB per asset, 128 MiB total session disk use, 384 tracked requests and the existing 256-mesh/1.5-million-vertex renderer cap. Ctrl+C in the bridge console closes the worker and removes its own session directory; force-kill or a system crash may leave an orphan folder (delete manually after closing the bridge). No persistent asset library is created automatically.

Mesh formats: FileMesh v2/v3 and rigid v4/v5, highest-detail LOD, up to 20,000 triangles per mesh. Unsupported formats, skinned geometry, failed downloads and malformed data fall back to boxes. UVs, texture GPU upload/sampling, normal maps, procedural studs and material texture mapping are NOT implemented in this preview. PNG/JPEG image references are collected and cached for future work, not displayed by the renderer. No support for live asset property changes on existing objects yet. External delivery and real GPU runtime are not verified by CI. Replace all binaries and reinstall the Lua script in Edit mode.
