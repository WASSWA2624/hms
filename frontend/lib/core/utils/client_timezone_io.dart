import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';

/// Native host channel answering `getTimeZoneId` with the device's IANA zone
/// (`MainActivity.kt`, iOS `AppDelegate.swift`, macOS `MainFlutterWindow.swift`).
const MethodChannel _timeZoneChannel = MethodChannel(
  'com.hosspi.app/time_zone',
);

// IANA names: `Africa/Kampala`, `America/Argentina/Buenos_Aires`, `Etc/GMT+3`, `UTC`.
final RegExp _ianaZonePattern = RegExp(
  r'^[A-Za-z][A-Za-z0-9_+\-]*(/[A-Za-z0-9_+\-]+)*$',
);

String? _cachedZone;
bool _readSystemZone = false;

/// Device IANA time zone (e.g. `Africa/Kampala`), or null when the platform
/// has not reported one.
///
/// Android, iOS, and macOS answer over a platform channel, so they report a
/// zone only after [loadClientTimeZoneId] has run. Windows reads it from the
/// system ICU library and Linux from `/etc`, on first use.
String? readClientTimeZoneId() {
  if (!_readSystemZone) {
    _readSystemZone = true;
    _cachedZone ??= _readSystemTimeZoneId();
  }
  return _cachedZone;
}

/// Asks the platform for its current zone and caches it for
/// [readClientTimeZoneId]. Keeps the last known zone when the platform cannot
/// answer.
Future<String?> loadClientTimeZoneId() async {
  final String? zone = _usesPlatformChannel
      ? await _readChannelTimeZoneId()
      : _readSystemTimeZoneId();
  if (zone != null) {
    _cachedZone = zone;
  }
  return readClientTimeZoneId();
}

bool get _usesPlatformChannel =>
    Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

Future<String?> _readChannelTimeZoneId() async {
  try {
    return _validZone(
      await _timeZoneChannel.invokeMethod<String>('getTimeZoneId'),
    );
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

String? _readSystemTimeZoneId() {
  try {
    if (Platform.isWindows) {
      return _readWindowsTimeZoneId();
    }
    if (Platform.isLinux) {
      return _readLinuxTimeZoneId();
    }
  } on Object {
    return null;
  }
  return null;
}

String? _validZone(String? value) {
  final String zone = value?.trim() ?? '';
  return zone.isNotEmpty && _ianaZonePattern.hasMatch(zone) ? zone : null;
}

/// `TZ`, then Debian's `/etc/timezone`, then the `/etc/localtime` symlink
/// into the zoneinfo database.
String? _readLinuxTimeZoneId() {
  final String? tz = Platform.environment['TZ'];
  if (tz != null) {
    final String? zone = _validZone(tz.startsWith(':') ? tz.substring(1) : tz);
    if (zone != null) {
      return zone;
    }
  }

  final File timezoneFile = File('/etc/timezone');
  if (timezoneFile.existsSync()) {
    final String? zone = _validZone(timezoneFile.readAsStringSync());
    if (zone != null) {
      return zone;
    }
  }

  final Link localtime = Link('/etc/localtime');
  if (localtime.existsSync()) {
    const String marker = 'zoneinfo/';
    final String target = localtime.targetSync();
    final int index = target.indexOf(marker);
    if (index >= 0) {
      return _validZone(target.substring(index + marker.length));
    }
  }
  return null;
}

/// Windows names zones its own way (`E. Africa Standard Time`); the ICU
/// library shipped with Windows 10 1903+ maps the system zone to IANA.
String? _readWindowsTimeZoneId() {
  const int capacity = 128;
  const int zeroInit = 0x40;

  final DynamicLibrary icu = DynamicLibrary.open('icu.dll');
  final int Function(Pointer<Uint16>, int, Pointer<Int32>) getDefaultZone = icu
      .lookupFunction<
        Int32 Function(Pointer<Uint16>, Int32, Pointer<Int32>),
        int Function(Pointer<Uint16>, int, Pointer<Int32>)
      >('ucal_getDefaultTimeZone');
  final DynamicLibrary kernel32 = DynamicLibrary.open('kernel32.dll');
  final Pointer<Void> Function(int, int) localAlloc = kernel32
      .lookupFunction<
        Pointer<Void> Function(Uint32, IntPtr),
        Pointer<Void> Function(int, int)
      >('LocalAlloc');
  final Pointer<Void> Function(Pointer<Void>) localFree = kernel32
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('LocalFree');

  // One zeroed block: the UTF-16 name buffer, then the ICU status code.
  final Pointer<Void> memory = localAlloc(zeroInit, capacity * 2 + 4);
  if (memory == nullptr) {
    return null;
  }
  try {
    final Pointer<Uint16> name = memory.cast<Uint16>();
    final Pointer<Int32> status = Pointer<Int32>.fromAddress(
      memory.address + capacity * 2,
    );
    final int length = getDefaultZone(name, capacity, status);
    // ICU failures are positive; negative codes are warnings.
    if (status.value > 0 || length <= 0 || length > capacity) {
      return null;
    }
    return _validZone(String.fromCharCodes(name.asTypedList(length)));
  } finally {
    localFree(memory);
  }
}
