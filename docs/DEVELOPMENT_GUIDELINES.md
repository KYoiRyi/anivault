# AniVault 核心架构与开发准则 (Development Guidelines)

这套文档定义了 AniVault 跨端多媒体引擎的严苛技术标准与开发禁忌，旨在维持项目的极速零延迟与跨平台一致性。

## 1. 原生零拷贝硬件加速 (Zero-Copy Hardware Decoding)

AniVault 将极速与资源的高效利用置于首位。

- **禁止引入中间层转译**：我们采用了 `media_kit` 内核，在 Windows 开发与生产生态中，直接让 `libmpv` 与底层系统 `d3d11va` (Direct3D 11 Video Acceleration) 或者 `Vulkan` API 通信完成视频解码。必须避免将视频流通过低效的 ANGLE 引擎向下翻译回 OpenGL ES 进行渲染！
- **原生纹理直传**：任何视频帧都必须作为原始 `ID3D11Texture2D` （在 Windows 上）通过原生的 Texture Registry 指针抛给 Flutter 层。严禁任何对视频缓冲帧（Buffer）的 CPU 层二次读取或深拷贝传输。
- **iOS生态对齐**：当转用 Apple 生态编译时，必须保证引擎正确接管 `VideoToolbox`，保持类似的纯硬件层管线架构。

## 2. 操作系统的原生接口接入 (Native OS Bridges)

- **坚决弃用残次插件**：必须使用第一方的底层稳定库（如 `file_selector`）代替各种缺乏系统异常处理的第三方拾取器（如曾经的 `file_picker`）。必须确保文件探查不会引发 COM 挂起或线程锁死。
- **严格的文件类型映射**：无论是 macOS 还是 Windows，针对媒体格式选取必须编写包含具体扩展名（如 `.mkv`, `.mp4`）或 MIME Type 的精准 `XTypeGroup`，保障极速文件唤起且不出现静默崩溃。

## 3. Shader 着色器与神经放大接入 (ArtCNN / Post-Processing)

- 对于非标分辨率的影视资源，必须遵循绝对路径直接调用预先下载或随应用分发的编译期着色器程序（如 `ArtCNN_C4F32.glsl`）。
- **着色器路径绝对化**：不论处于什么操作系统中封装或打包，所有的 `media_kit` 的自定义着色调用都必须转换为对设备原生的绝对物理路径读取，避免因为各种 `Asset` 沙盒映射造成的内部加载失败。

## 4. CMake 与原生级构建

- 在应对构建错误或者拉取不相关的组件导致哈希失败时，应始终依赖原生的 `flutter clean` 以及完全的重构流 `flutter build windows -v` 排查诊断，避免在系统架构之上附加非必要的补丁脚本。
