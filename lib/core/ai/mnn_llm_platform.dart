import 'dart:io';

import 'package:flutter/services.dart';

/// Android 端 MethodChannel + EventChannel，对接 `MnnLlmPlugin` / JNI / MNN 3.4.1。
class MnnLlmPlatform {
  MnnLlmPlatform._();
  static const MethodChannel _channel = MethodChannel('aiim/mnn_llm');
  static const EventChannel _eventChannel = EventChannel('aiim/mnn_llm_stream');

  static bool get supported => Platform.isAndroid;

  static Future<bool> probe() async {
    if (!supported) return false;
    try {
      final v = await _channel.invokeMethod<bool>('probe');
      return v == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> loadModel(String modelDir) async {
    await _channel.invokeMethod<void>('loadModel', {'modelDir': modelDir});
  }

  static Future<void> unloadModel() async {
    await _channel.invokeMethod<void>('unloadModel');
  }

  static Future<void> resetSession() async {
    await _channel.invokeMethod<void>('resetSession');
  }

  /// 非流式（保留兼容）。
  static Future<String> generate(
    String prompt, {
    int maxNewTokens = 512,
  }) async {
    final r = await _channel.invokeMethod<String>('generate', {
      'prompt': prompt,
      'maxNewTokens': maxNewTokens,
    });
    return r ?? '';
  }

  /// 流式：每个事件为一段 UTF-8 文本；结束时流关闭。
  static Stream<String> generateStream(
    String prompt, {
    int maxNewTokens = 512,
  }) {
    if (!supported) {
      return const Stream.empty();
    }
    return _eventChannel
        .receiveBroadcastStream({
          'prompt': prompt,
          'maxNewTokens': maxNewTokens,
        })
        .map((event) => event is String ? event : '')
        .where((s) => s.isNotEmpty);
  }
}
