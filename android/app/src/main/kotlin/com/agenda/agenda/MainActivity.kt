package com.agenda.agenda

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    /** Página pedida por um widget ao abrir a app (ex.: "tasks"). */
    private var pendingTab: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingTab = intent?.getStringExtra(EXTRA_TAB)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // A app já estava aberta: avisar o Flutter.
        intent.getStringExtra(EXTRA_TAB)?.let { channel?.invokeMethod("openTab", it) }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wolfcal/widget").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    // A app avisa os widgets quando os dados mudam.
                    "refresh" -> {
                        WolfCalWidget.refreshAll(this)
                        WolfCalTasksWidget.refreshAll(this)
                        result.success(null)
                    }
                    "launchTab" -> {
                        result.success(pendingTab)
                        pendingTab = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    companion object {
        const val EXTRA_TAB = "open_tab"
    }
}
