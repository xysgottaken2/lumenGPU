# LUMEN GPU 0.4 — material and denoise update

[Windows builds](../../actions) | [Setup](README.txt)

GGX/Lambert BSDF, sky MIS, soft sun, exact Fresnel dielectric branch, GPU normal/depth/albedo-guided spatial denoiser, live render scale, sphere/cylinder primitive BLAS, fast moving-part snapshots. No DLSS or arbitrary asset meshes yet. Use matching LGR4 Lua, bridge, executable and both shaders.

## Scene-sync hotfix (Lua only)
Client-authoritative geometry capture for local Studio play, including client-created parts. Static snapshots are sent in ordered chunks, moving objects alongside camera updates. Full static refresh every five seconds; rejected WebSocket updates trigger resend. StreamingEnabled can limit the geometry visible to the Studio client. Existing 0.4 binaries and shader files are compatible. Run the updated installer in Edit mode and restart Play.

## Low-latency Lua hotfix
Camera Heartbeat no longer walks the entire map. Static snapshots build in a yielding task, chunks are paced; moving objects cached in a separate task, avatar/geometry updates target 30 Hz while camera targets 60 Hz. WebSocket uses one outstanding update and latest camera state rather than queuing old frames; unchanged world/fast snapshots are omitted and upload errors retry. Compatible with existing 0.4 binaries. Large static updates still share the transport, so brief spikes are possible. Studio runtime unverified.
