import 'package:flutter/foundation.dart';

import 'mnn_llm_platform.dart';
import 'mnn_model_store.dart';

/// 管理端侧 MNN 会话加载与生成（当前仅 Android JNI）。
class MnnLocalLlmController extends ChangeNotifier {
  bool? _nativeProbe;
  bool _sessionReady = false;
  bool _generating = false;
  String? _lastError;
  String? _loadedModelId;

  bool get nativeProbeComplete => _nativeProbe != null;
  bool get isNativeBackendAvailable => _nativeProbe == true;
  bool get isSessionReady => _sessionReady;
  bool get isGenerating => _generating;
  String? get lastError => _lastError;

  /// 检测 so 是否可加载（仅 Android）。
  Future<void> warmUpProbe() async {
    if (!MnnLlmPlatform.supported) {
      _nativeProbe = false;
      _lastError = '当前平台不支持端侧 MNN（仅 Android）。';
      notifyListeners();
      return;
    }
    try {
      _nativeProbe = await MnnLlmPlatform.probe();
      if (_nativeProbe == false) {
        _lastError =
            '未能加载 libaiim_mnn_jni.so。常见原因：① 使用 x86/x86_64 模拟器（本工程仅打包 arm64-v8a，请用 ARM64 真机或带 ARM 翻译的模拟器）；'
            '② 未完整构建（需 third_party/MNN 头文件 + Gradle 能下载 jniLibs 中的 MNN .so）；③ 安装包过旧，请 flutter clean 后重装。';
      } else {
        _lastError = null;
      }
    } catch (e) {
      _nativeProbe = false;
      _lastError = e.toString();
    }
    notifyListeners();
  }

  /// 与 [MnnModelStore] 对齐：模型就绪则加载 native，否则卸载。
  Future<void> syncSession(MnnModelStore store) async {
    if (!MnnLlmPlatform.supported) {
      _nativeProbe ??= false;
      notifyListeners();
      return;
    }
    // 首次为 null 要探测；曾为 false 也再探测一次（避免引擎/插件晚于首次 probe 就绪后永久卡住）
    if (_nativeProbe != true) {
      await warmUpProbe();
    }
    if (_nativeProbe != true) return;

    if (!store.isModelReady || store.isBusy) {
      if (_sessionReady) {
        await _unload();
      }
      return;
    }

    final id = store.selectedModelId;
    if (_loadedModelId == id && _sessionReady) return;

    final dir = await store.modelDirPath(id);
    await _load(dir, id);
  }

  Future<void> _load(String modelDir, String modelId) async {
    _lastError = null;
    notifyListeners();
    try {
      await MnnLlmPlatform.loadModel(modelDir);
      _loadedModelId = modelId;
      _sessionReady = true;
      _lastError = null;
    } catch (e) {
      _sessionReady = false;
      _loadedModelId = null;
      _lastError = e.toString();
    }
    notifyListeners();
  }

  Future<void> _unload() async {
    try {
      await MnnLlmPlatform.unloadModel();
    } catch (_) {}
    _sessionReady = false;
    _loadedModelId = null;
    notifyListeners();
  }

  Future<void> resetConversation() async {
    if (!MnnLlmPlatform.supported || !_sessionReady) return;
    try {
      await MnnLlmPlatform.resetSession();
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
    }
  }

  Future<String> generate(
    String prompt, {
    int maxNewTokens = 512,
  }) async {
    _generating = true;
    _lastError = null;
    notifyListeners();
    try {
      final out = await MnnLlmPlatform.generate(
        prompt,
        maxNewTokens: maxNewTokens,
      );
      return out;
    } catch (e) {
      _lastError = e.toString();
      rethrow;
    } finally {
      _generating = false;
      notifyListeners();
    }
  }

  /// 端侧流式生成；结束时自动 [notifyListeners]。
  Stream<String> generateStream(
    String prompt, {
    int maxNewTokens = 512,
  }) async* {
    _generating = true;
    _lastError = null;
    notifyListeners();
    try {
      await for (final chunk in MnnLlmPlatform.generateStream(
        prompt,
        maxNewTokens: maxNewTokens,
      )) {
        yield chunk;
      }
    } catch (e) {
      _lastError = e.toString();
      rethrow;
    } finally {
      _generating = false;
      notifyListeners();
    }
  }
}
