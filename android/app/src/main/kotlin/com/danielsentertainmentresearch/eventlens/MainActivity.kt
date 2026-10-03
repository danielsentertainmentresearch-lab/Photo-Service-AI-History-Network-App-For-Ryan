package com.danielsentertainmentresearch.eventlens

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity is required by local_auth (biometric unlock).
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Hides the app's content in the recent-apps switcher (and blocks
        // screenshots) while the "Hide in recent apps" setting is on.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "eventlens/privacy")
            .setMethodCallHandler { call, result ->
                if (call.method == "setSecure") {
                    val on = call.argument<Boolean>("on") ?: true
                    if (on) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
