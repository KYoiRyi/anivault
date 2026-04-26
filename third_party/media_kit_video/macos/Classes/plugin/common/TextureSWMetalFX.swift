#if canImport(Flutter)
  import Flutter
#elseif canImport(FlutterMacOS)
  import FlutterMacOS
#endif

#if canImport(MetalFX)
  import MetalFX
#endif

public class TextureSWMetalFX: NSObject, FlutterTexture, ResizableTextureProtocol {
  public typealias UpdateCallback = () -> Void

  public static var supported: Bool {
    #if canImport(MetalFX)
      if #available(iOS 16.0, macOS 13.0, *) {
        return MetalFXSpatialScalerProcessor() != nil
      }
    #endif
    return false
  }

  private let handle: OpaquePointer
  private let updateCallback: UpdateCallback
  private var renderContext: OpaquePointer?
  private var textureContexts = SwappableObjectManager<TextureSWMetalFXContext>(
    objects: [],
    skipCheckArgs: true
  )
  private let scale: Double
  #if canImport(MetalFX)
    @available(iOS 16.0, macOS 13.0, *)
    private lazy var processor = MetalFXSpatialScalerProcessor()
  #endif

  init(
    handle: OpaquePointer,
    scale: Double,
    updateCallback: @escaping UpdateCallback
  ) {
    self.handle = handle
    self.scale = max(0.3, min(scale, 1.0))
    self.updateCallback = updateCallback

    super.init()

    DispatchQueue.main.async {
      self.initMPV()
    }
  }

  deinit {
    disposePixelBuffer()
    disposeMPV()
  }

  public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    let textureContext = textureContexts.current
    if textureContext == nil {
      return nil
    }
    return Unmanaged.passRetained(textureContext!.outputPixelBuffer)
  }

  private func initMPV() {
    let api = UnsafeMutableRawPointer(
      mutating: (MPV_RENDER_API_TYPE_SW as NSString).utf8String
    )
    var params: [mpv_render_param] = [
      mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: api),
      mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
    ]

    MPVHelpers.checkError(
      mpv_render_context_create(&renderContext, handle, &params)
    )

    mpv_render_context_set_update_callback(
      renderContext,
      { (ctx) in
        let that = unsafeBitCast(ctx, to: TextureSWMetalFX.self)
        DispatchQueue.main.async {
          that.updateCallback()
        }
      },
      UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    )
  }

  private func disposeMPV() {
    mpv_render_context_set_update_callback(renderContext, nil, nil)
    mpv_render_context_free(renderContext)
  }

  public func resize(_ size: CGSize) {
    if size.width == 0 || size.height == 0 {
      return
    }

    NSLog("TextureSWMetalFX: resize: \(size.width)x\(size.height)")
    createPixelBuffer(size)
  }

  private func createPixelBuffer(_ size: CGSize) {
    disposePixelBuffer()
    let renderSize = scaledSize(for: size)
    textureContexts.reinit(
      objects: [
        TextureSWMetalFXContext(renderSize: renderSize, outputSize: size),
        TextureSWMetalFXContext(renderSize: renderSize, outputSize: size),
        TextureSWMetalFXContext(renderSize: renderSize, outputSize: size),
      ],
      skipCheckArgs: true
    )
  }

  private func scaledSize(for size: CGSize) -> CGSize {
    let width = max(64, Int((size.width * scale).rounded()))
    let height = max(64, Int((size.height * scale).rounded()))
    return CGSize(width: width, height: height)
  }

  private func disposePixelBuffer() {
    textureContexts.reinit(objects: [], skipCheckArgs: true)
  }

  public func render(_ size: CGSize) {
    let textureContext = textureContexts.nextAvailable()
    if textureContext == nil {
      return
    }

    CVPixelBufferLockBaseAddress(
      textureContext!.inputPixelBuffer,
      CVPixelBufferLockFlags(rawValue: 0)
    )
    defer {
      CVPixelBufferUnlockBaseAddress(
        textureContext!.inputPixelBuffer,
        CVPixelBufferLockFlags(rawValue: 0)
      )
    }

    var ssize: [Int32] = [
      Int32(textureContext!.renderSize.width),
      Int32(textureContext!.renderSize.height),
    ]
    let format: String = "bgr0"
    var pitch: Int = CVPixelBufferGetBytesPerRow(textureContext!.inputPixelBuffer)
    let buffer = CVPixelBufferGetBaseAddress(textureContext!.inputPixelBuffer)

    let ssizePtr = ssize.withUnsafeMutableBytes {
      $0.baseAddress?.assumingMemoryBound(to: Int32.self)
    }
    let formatPtr = UnsafeMutablePointer(
      mutating: (format as NSString).utf8String
    )
    let pitchPtr = withUnsafeMutablePointer(to: &pitch) { $0 }
    let bufferPtr = buffer!.assumingMemoryBound(to: UInt8.self)

    var params: [mpv_render_param] = [
      mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: ssizePtr),
      mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT, data: formatPtr),
      mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: pitchPtr),
      mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: bufferPtr),
      mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
    ]

    mpv_render_context_render(renderContext, &params)

    #if canImport(MetalFX)
      if #available(iOS 16.0, macOS 13.0, *) {
        processor?.upscale(
          inputPixelBuffer: textureContext!.inputPixelBuffer,
          outputPixelBuffer: textureContext!.outputPixelBuffer
        )
      }
    #endif

    textureContexts.pushAsReady(textureContext!)
  }
}
