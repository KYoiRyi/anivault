import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Reference all Go torrent FFI symbols to prevent Xcode's linker from stripping them under -dead_strip.
    // We use a dynamic check that is always false at runtime to avoid executing them.
    if ProcessInfo.processInfo.arguments.contains("DUMMY_KEEPER_ARG") {
      _ = anivault_torrent_init(nil)
      _ = anivault_torrent_add_magnet(nil)
      _ = anivault_torrent_pause(nil)
      _ = anivault_torrent_resume(nil)
      _ = anivault_torrent_remove(nil, 0)
      _ = anivault_torrent_status()
    }
    // Always safe to call free(nil)
    anivault_torrent_free(nil)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
