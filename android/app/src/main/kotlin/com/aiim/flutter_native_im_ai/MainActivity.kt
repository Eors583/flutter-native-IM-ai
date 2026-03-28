package com.aiim.flutter_native_im_ai

import com.aiim.flutter_native_im_ai.mnn.MnnLlmPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(MnnLlmPlugin())
    }
}
