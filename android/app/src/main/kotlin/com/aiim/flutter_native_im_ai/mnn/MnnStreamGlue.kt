package com.aiim.flutter_native_im_ai.mnn

import android.os.Handler
import io.flutter.plugin.common.EventChannel

/**
 * 由 JNI 在同一线程回调；内部 post 到主线程写 EventSink（Flutter 要求）。
 * 方法名/签名须与 aiim_mnn_jni.cpp 中 GetMethodID 一致。
 */
class MnnStreamGlue(
    private val mainHandler: Handler,
    private val sink: EventChannel.EventSink,
) {
    fun onChunk(s: String) {
        if (s.isEmpty()) return
        mainHandler.post { sink.success(s) }
    }

    fun onComplete() {
        mainHandler.post { sink.endOfStream() }
    }

    fun onError(msg: String) {
        mainHandler.post { sink.error("GEN", msg, null) }
    }
}
