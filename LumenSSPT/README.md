# LumenSSPT v0.1 — experimental DXR screen-space renderer

Separate visible-frame renderer. No Roblox plugin, HTTP relay, injection, process-memory access, or game modification. Output is a separate preview, not an overlay. Capture and game policies may vary.

## Prebuilt Windows x64 artifact

1. Open the LumenSSPT Windows x64 workflow on GitHub Actions, select a successful run and download the LumenSSPT-v0.1-Windows-x64 artifact.
2. Extract the whole archive; keep build/LumenSSPT.exe and build/trace.cso.
3. Install 64-bit Python 3.11 including the py launcher if necessary.
4. In PowerShell in the extracted folder run: powershell -NoProfile -File .\Setup.ps1
5. Run Demo.bat, then Launch.bat while Roblox is open. Setup.ps1 -DemoOnly skips model download. The precompiled files skip DXC, CMake and MSVC entirely.

For source builds, Build.ps1 requires VS2022 C++, CMake, Windows SDK and DXC. Setup.ps1 -Rebuild rebuilds from source. Use normal approved script-running procedures; do not disable security settings.

Requires DXR 1.1 and SM 6.5 support, current GPU drivers, Windows 10/11 x64. RTX 2060 is the intended test GPU. Python dependencies and Depth Anything V2 Small ONNX weights are downloaded once; runtime is local.

Demo.bat --width 160 --height 90 --spp 2
Launch.bat --width 256 --height 144 --spp 1 --bounces 2 --reflection 0.12
Launch.bat --help

Q/Esc: quit; B: original/enhanced; D: depth; F: effect; T: temporal toggle. Preview reports processed frame FPS and depth, DXR and mesh times, not original game FPS.

RGB-only reconstruction is approximate, with no actual game depth or material data. CPU copies, mesh generation, synchronous GPU dispatch and preview can limit FPS. GPU runtime, WGC capture, DirectML and the model download need real Windows hardware testing; CI only compiles and runs CPU-side tests. No guarantee of game compatibility or account safety.

External dependencies: Microsoft DXR 1.1, ONNX Runtime DirectML, Windows Capture, Depth Anything V2 Small (https://huggingface.co/onnx-community/depth-anything-v2-small).
