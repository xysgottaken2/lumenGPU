# LUMEN GPU 0.7 — synchronized camera and avatar

[Windows builds](../../actions) | [Setup](README.txt)

Camera and local character are captured in the same Studio render step and sent in a single pose packet (target 60 Hz). Static world, other moving objects, and pose have independent native WebSocket channels and revisions. No full map transfer on avatar movement. Optional F6 paired smoothing is off by default. Previous mesh, denoise, material and input fixes retained. Replace all files and reinstall Lua. Runtime not yet benchmarked.
