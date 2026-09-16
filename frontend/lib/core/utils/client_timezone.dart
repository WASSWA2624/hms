export 'client_timezone_stub.dart'
    if (dart.library.js_interop) 'client_timezone_web.dart'
    if (dart.library.io) 'client_timezone_io.dart';

/// `UTC`, or the offset as `UTC+03:00` / `UTC-05:30`.
String formatUtcOffsetLabel(Duration offset) {
  final int minutes = offset.inMinutes;
  if (minutes == 0) {
    return 'UTC';
  }
  final String sign = minutes < 0 ? '-' : '+';
  final int absolute = minutes.abs();
  final String hours = (absolute ~/ 60).toString().padLeft(2, '0');
  final String remainder = (absolute % 60).toString().padLeft(2, '0');
  return 'UTC$sign$hours:$remainder';
}
