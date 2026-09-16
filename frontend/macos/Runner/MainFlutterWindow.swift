import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // IANA zone id (e.g. Africa/Kampala); Dart only sees the abbreviation.
    let timeZoneChannel = FlutterMethodChannel(
      name: "com.hosspi.app/time_zone",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    timeZoneChannel.setMethodCallHandler { call, result in
      if call.method == "getTimeZoneId" {
        result(TimeZone.current.identifier)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
