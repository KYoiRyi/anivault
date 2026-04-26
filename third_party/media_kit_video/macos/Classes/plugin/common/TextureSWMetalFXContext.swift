import CoreVideo
import CoreGraphics

public class TextureSWMetalFXContext {
  public let inputPixelBuffer: CVPixelBuffer
  public let outputPixelBuffer: CVPixelBuffer
  public let renderSize: CGSize
  public let outputSize: CGSize

  init(renderSize: CGSize, outputSize: CGSize) {
    self.renderSize = renderSize
    self.outputSize = outputSize
    self.inputPixelBuffer = TextureSWMetalFXContext.createPixelBuffer(renderSize)
    self.outputPixelBuffer = TextureSWMetalFXContext.createPixelBuffer(outputSize)
  }

  private static func createPixelBuffer(_ size: CGSize) -> CVPixelBuffer {
    let attrs = [
      kCVPixelBufferMetalCompatibilityKey: true,
      kCVPixelBufferIOSurfacePropertiesKey: [:]
    ] as CFDictionary

    var pixelBuffer: CVPixelBuffer?
    let cvret = CVPixelBufferCreate(
      kCFAllocatorDefault,
      Int(size.width),
      Int(size.height),
      kCVPixelFormatType_32BGRA,
      attrs,
      &pixelBuffer
    )
    assert(cvret == kCVReturnSuccess, "CVPixelBufferCreate")
    return pixelBuffer!
  }
}
