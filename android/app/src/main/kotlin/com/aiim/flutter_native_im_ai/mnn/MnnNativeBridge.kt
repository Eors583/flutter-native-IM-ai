package com.aiim.flutter_native_im_ai.mnn

/**
 * JNI 入口；实现见 src/main/cpp/aiim_mnn_jni.cpp。
 * configPath 为 model 目录下 config.json 的绝对路径。
 */
internal object MnnNativeBridge {
    @Volatile
    private var loaded = false

    @Synchronized
    fun ensureLoaded() {
        if (loaded) return
        System.loadLibrary("aiim_mnn_jni")
        loaded = true
    }

    external fun nativeCreate(configPath: String): Long
    external fun nativeReset(handle: Long)
    external fun nativeGenerate(handle: Long, userText: String, maxNewTokens: Int): String

    @JvmStatic
    external fun nativeGenerateStream(
        handle: Long,
        userText: String,
        maxNewTokens: Int,
        glue: MnnStreamGlue,
    )

    external fun nativeRelease(handle: Long)
}
