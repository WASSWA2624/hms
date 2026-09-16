package com.hosspi.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // IANA zone id (e.g. Africa/Kampala); Dart only sees the abbreviation.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TIME_ZONE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "getTimeZoneId") {
                    result.success(TimeZone.getDefault().id)
                } else {
                    result.notImplemented()
                }
            }
    }

    private companion object {
        const val TIME_ZONE_CHANNEL = "com.hosspi.app/time_zone"
    }
}
