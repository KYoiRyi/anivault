public class VideoOutputConfiguration {
  public let width: Int64?
  public let height: Int64?
  public let enableHardwareAcceleration: Bool
  public let enableMetalFX: Bool
  public let metalFXScale: Double

  init(
    width: Int64?,
    height: Int64?,
    enableHardwareAcceleration: Bool,
    enableMetalFX: Bool,
    metalFXScale: Double
  ) {
    self.width = width
    self.height = height
    self.enableHardwareAcceleration = enableHardwareAcceleration
    self.enableMetalFX = enableMetalFX
    self.metalFXScale = metalFXScale
  }

  public static func fromDict(_ dict: [String: Any])
    -> VideoOutputConfiguration
  {
    let widthStr = dict["width"] as! String
    let heightStr = dict["height"] as! String
    let enableHardwareAcceleration =
      dict["enableHardwareAcceleration"] as! Bool
    let enableMetalFX =
      dict["enableMetalFX"] as? Bool ?? false
    let metalFXScale =
      dict["metalFXScale"] as? Double ?? 0.67

    let width: Int64? = Int64(widthStr)
    let height: Int64? = Int64(heightStr)

    return VideoOutputConfiguration(
      width: width,
      height: height,
      enableHardwareAcceleration: enableHardwareAcceleration,
      enableMetalFX: enableMetalFX,
      metalFXScale: metalFXScale
    )
  }
}
