# LUMEN GPU 0.8 — day/night and wavelet preview

[Windows builds](../../actions) | [Setup](README.txt)

Studio lighting direction, ClockTime, Brightness, and Sky sun size/visibility synchronized with camera. Procedural day/night and visible sun; optional local sun.png next to LumenGPU.exe. GPU A-trous spatial wavelet denoising (not NVIDIA NRD), original filter retained. NRD integration is not completed. Replace all files and reinstall Lua. Runtime not benchmarked.

V0.8.1: colored direct sun and sky transmission through glass, including tinted visibility debug output. Thin-glass approximation, no focused caustics. NRD still incomplete.

V0.8.2: scroll zoom with F2 capture, first-person at minimum zoom, Roblox camera lock respected. Local avatar stays in the TLAS but is masked from primary camera rays; shadows/reflections/GI still include it. Replace native files and reinstall Lua.
