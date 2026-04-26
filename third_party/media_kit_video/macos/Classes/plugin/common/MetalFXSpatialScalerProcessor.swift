#if canImport(MetalFX)
  import Metal
  import MetalFX
  import CoreVideo

  @available(iOS 16.0, macOS 13.0, *)
  public final class MetalFXSpatialScalerProcessor {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let textureCache: CVMetalTextureCache
    private var scaler: MTLFXSpatialScaler?
    private var inputWidth: Int = 0
    private var inputHeight: Int = 0
    private var outputWidth: Int = 0
    private var outputHeight: Int = 0

    public init?() {
      guard let device = MTLCreateSystemDefaultDevice(),
            let commandQueue = device.makeCommandQueue()
      else {
        return nil
      }

      var textureCache: CVMetalTextureCache?
      let result = CVMetalTextureCacheCreate(
        kCFAllocatorDefault,
        nil,
        device,
        nil,
        &textureCache
      )
      guard result == kCVReturnSuccess, let textureCache else {
        return nil
      }

      self.device = device
      self.commandQueue = commandQueue
      self.textureCache = textureCache
    }

    public func upscale(
      inputPixelBuffer: CVPixelBuffer,
      outputPixelBuffer: CVPixelBuffer
    ) {
      let inputWidth = CVPixelBufferGetWidth(inputPixelBuffer)
      let inputHeight = CVPixelBufferGetHeight(inputPixelBuffer)
      let outputWidth = CVPixelBufferGetWidth(outputPixelBuffer)
      let outputHeight = CVPixelBufferGetHeight(outputPixelBuffer)

      guard ensureScaler(
        inputWidth: inputWidth,
        inputHeight: inputHeight,
        outputWidth: outputWidth,
        outputHeight: outputHeight
      ),
      let inputTexture = makeTexture(
        pixelBuffer: inputPixelBuffer,
        width: inputWidth,
        height: inputHeight
      ),
      let outputTexture = makeTexture(
        pixelBuffer: outputPixelBuffer,
        width: outputWidth,
        height: outputHeight
      ),
      let scaler,
      let commandBuffer = commandQueue.makeCommandBuffer()
      else {
        return
      }

      scaler.colorTexture = inputTexture
      scaler.outputTexture = outputTexture
      scaler.inputContentWidth = inputWidth
      scaler.inputContentHeight = inputHeight
      scaler.encode(commandBuffer: commandBuffer)
      commandBuffer.commit()
      commandBuffer.waitUntilCompleted()
    }

    private func ensureScaler(
      inputWidth: Int,
      inputHeight: Int,
      outputWidth: Int,
      outputHeight: Int
    ) -> Bool {
      if self.inputWidth == inputWidth &&
        self.inputHeight == inputHeight &&
        self.outputWidth == outputWidth &&
        self.outputHeight == outputHeight &&
        scaler != nil {
        return true
      }

      let descriptor = MTLFXSpatialScalerDescriptor()
      descriptor.inputWidth = inputWidth
      descriptor.inputHeight = inputHeight
      descriptor.outputWidth = outputWidth
      descriptor.outputHeight = outputHeight
      descriptor.colorTextureFormat = .bgra8Unorm
      descriptor.outputTextureFormat = .bgra8Unorm
      descriptor.colorProcessingMode = .perceptual

      let newScaler = descriptor.makeSpatialScaler(device: device)
      guard let newScaler else {
        return false
      }

      scaler = newScaler
      self.inputWidth = inputWidth
      self.inputHeight = inputHeight
      self.outputWidth = outputWidth
      self.outputHeight = outputHeight
      return true
    }

    private func makeTexture(
      pixelBuffer: CVPixelBuffer,
      width: Int,
      height: Int
    ) -> MTLTexture? {
      var cvTexture: CVMetalTexture?
      let result = CVMetalTextureCacheCreateTextureFromImage(
        kCFAllocatorDefault,
        textureCache,
        pixelBuffer,
        nil,
        .bgra8Unorm,
        width,
        height,
        0,
        &cvTexture
      )
      guard result == kCVReturnSuccess, let cvTexture else {
        return nil
      }
      return CVMetalTextureGetTexture(cvTexture)
    }
  }
#endif
