package com.aiim.flutter_native_im_ai.mnn

import android.os.Handler
import android.os.Looper
import com.aiim.flutter_native_im_ai.mnn.MnnNativeBridge.ensureLoaded
import com.aiim.flutter_native_im_ai.mnn.MnnNativeBridge.nativeCreate
import com.aiim.flutter_native_im_ai.mnn.MnnNativeBridge.nativeGenerate
import com.aiim.flutter_native_im_ai.mnn.MnnNativeBridge.nativeGenerateStream
import com.aiim.flutter_native_im_ai.mnn.MnnNativeBridge.nativeRelease
import com.aiim.flutter_native_im_ai.mnn.MnnNativeBridge.nativeReset
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.util.concurrent.Executors

class MnnLlmPlugin : FlutterPlugin, MethodCallHandler {
    private var channel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var nativeHandle: Long = 0

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val ch = MethodChannel(binding.binaryMessenger, "aiim/mnn_llm")
        ch.setMethodCallHandler(this)
        channel = ch

        val ec = EventChannel(binding.binaryMessenger, "aiim/mnn_llm_stream")
        ec.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    val map = arguments as? Map<*, *>
                    if (map == null) {
                        events.error("ARG", "expected argument map", null)
                        return
                    }
                    val prompt = map["prompt"] as? String
                    if (prompt == null) {
                        events.error("ARG", "prompt required", null)
                        return
                    }
                    val maxNew = (map["maxNewTokens"] as? Number)?.toInt() ?: 512
                    if (nativeHandle == 0L) {
                        events.error("STATE", "Model not loaded", null)
                        return
                    }
                    val h = nativeHandle
                    val glue = MnnStreamGlue(mainHandler, events)
                    executor.execute {
                        try {
                            ensureLoaded()
                            nativeGenerateStream(h, prompt, maxNew, glue)
                        } catch (e: Throwable) {
                            mainHandler.post {
                                events.error("GEN", e.message ?: e.toString(), null)
                            }
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    // TODO: 与 MNN USER_CANCEL 对接
                }
            },
        )
        eventChannel = ec
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        executor.execute {
            if (nativeHandle != 0L) {
                try {
                    nativeRelease(nativeHandle)
                } catch (_: Throwable) {
                }
                nativeHandle = 0
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "probe" -> {
                val ok =
                    try {
                        System.loadLibrary("aiim_mnn_jni")
                        true
                    } catch (_: UnsatisfiedLinkError) {
                        false
                    }
                result.success(ok)
            }
            "loadModel" -> {
                val dir = call.argument<String>("modelDir")
                if (dir.isNullOrBlank()) {
                    result.error("ARG", "modelDir required", null)
                    return
                }
                val cfg = File(dir, "config.json")
                if (!cfg.exists()) {
                    result.error("NO_CFG", "config.json not found under $dir", null)
                    return
                }
                executor.execute {
                    try {
                        ensureLoaded()
                        if (nativeHandle != 0L) {
                            nativeRelease(nativeHandle)
                            nativeHandle = 0
                        }
                        val h = nativeCreate(cfg.absolutePath)
                        if (h == 0L) {
                            mainHandler.post {
                                result.error("LOAD", "nativeCreate/load failed", null)
                            }
                        } else {
                            nativeHandle = h
                            mainHandler.post { result.success(true) }
                        }
                    } catch (e: Throwable) {
                        mainHandler.post {
                            result.error("LOAD", e.message ?: e.toString(), null)
                        }
                    }
                }
            }
            "unloadModel" -> {
                executor.execute {
                    try {
                        if (nativeHandle != 0L) {
                            nativeRelease(nativeHandle)
                            nativeHandle = 0
                        }
                    } catch (_: Throwable) {
                    }
                    mainHandler.post { result.success(null) }
                }
            }
            "resetSession" -> {
                executor.execute {
                    try {
                        if (nativeHandle != 0L) {
                            nativeReset(nativeHandle)
                        }
                    } catch (_: Throwable) {
                    }
                    mainHandler.post { result.success(null) }
                }
            }
            "generate" -> {
                val prompt = call.argument<String>("prompt")
                if (prompt == null) {
                    result.error("ARG", "prompt required", null)
                    return
                }
                val maxNew = call.argument<Int>("maxNewTokens") ?: 512
                if (nativeHandle == 0L) {
                    result.error("STATE", "Model not loaded", null)
                    return
                }
                val h = nativeHandle
                executor.execute {
                    try {
                        ensureLoaded()
                        val out = nativeGenerate(h, prompt, maxNew)
                        mainHandler.post { result.success(out) }
                    } catch (e: Throwable) {
                        mainHandler.post {
                            result.error("GEN", e.message ?: e.toString(), null)
                        }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }
}
