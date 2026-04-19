# Native Core Notes

This folder preserves the native playback experiments from the original
`D:\Program Files\Visual\vp` workspace.

The Flutter app currently uses `media_kit` for production playback. The native
core here is a reference layer for direct mpv integration:

- `anivault_core`: Rust prototype using `libmpv_sys` to create an mpv context,
  configure `gpu-next`, hardware decoding, logging, and an external GLSL shader,
  then play a local reference file.
- `mpv_smoke`: C++ prototype doing the same basic mpv setup through the C API.

Large runtime files from the original workspace are intentionally not committed:
mpv DLLs, import libraries, archives, and sample videos. Put them next to the
native projects locally when building these prototypes.
