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

    // IANA zone id (e.g. Africa/Kampala); Dart only sees the abbreviation.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HosspiTimeZone") {
      let channel = FlutterMethodChannel(
        name: "com.hosspi.app/time_zone",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        if call.method == "getTimeZoneId" {
          result(TimeZone.current.identifier)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
