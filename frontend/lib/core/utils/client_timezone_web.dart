import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('Intl.DateTimeFormat')
extension type _JsDateTimeFormat._(JSObject _) implements JSObject {
  external factory _JsDateTimeFormat();
  external JSObject resolvedOptions();
}

/// Browser IANA timezone (e.g. `Africa/Kampala`).
String? readClientTimeZoneId() {
  try {
    final JSObject options = _JsDateTimeFormat().resolvedOptions();
    final JSAny? zone = options.getProperty('timeZone'.toJS);
    if (zone == null) {
      return null;
    }
    final String value = (zone as JSString).toDart.trim();
    return value.isEmpty ? null : value;
  } catch (_) {
    return null;
  }
}

/// The browser answers synchronously; nothing to prime.
Future<String?> loadClientTimeZoneId() async => readClientTimeZoneId();
