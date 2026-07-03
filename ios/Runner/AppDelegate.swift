import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func dummyTorrentLinkerKeeper() {
    // This function is never called but prevents Xcode linker from stripping Go symbols.
    _ = anivault_torrent_init(nil)
    _ = anivault_torrent_add_magnet(nil)
    _ = anivault_torrent_pause(nil)
    _ = anivault_torrent_resume(nil)
    _ = anivault_torrent_remove(nil, 0)
    _ = anivault_torrent_status()
    anivault_torrent_free(nil)
  }
}
