package com.agenda.agenda

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // A app avisa o widget quando os dados mudam.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wolfcal/widget")
            .setMethodCallHandler { call, result ->
                if (call.method == "refresh") {
                    WolfCalWidget.refreshAll(this)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
