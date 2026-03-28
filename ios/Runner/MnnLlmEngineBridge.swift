import Foundation

/// 将 Flutter `MethodChannel` / `EventChannel` 与 **你已实现的 iOS 端侧 MNN** 对齐。
///
/// 在 `AppDelegate.application(_:didFinishLaunchingWithOptions:)` 里（`return super` 之前）
/// 设置 `MnnLlmEngineBridge.backend = yourSingleton`，并保证 `yourSingleton` 在 App 生命周期内常驻。
///
/// 约定与 Android `MnnLlmPlugin` / JNI 一致：
/// - `loadModel` 传入 **模型目录**；原生侧应使用 `modelDir/config.json` 的绝对路径加载。
/// - `generate` / 流式：在同一会话上推理；`unload` / `reset` 语义与 Android 相同。
public protocol MnnLlmFlutterBackend: AnyObject {
  /// 是否已链接 MNN / 资源就绪（对应 Android `probe` 成功加载 so）。
  func mnnProbe() -> Bool

  /// `configJsonPath` 为 `…/config.json` 的绝对路径。
  func mnnLoadModel(configJsonPath: String) throws

  func mnnUnloadModel()

  func mnnResetSession()

  func mnnGenerate(prompt: String, maxNewTokens: Int) throws -> String

  /// 在 **后台线程** 调用 `onChunk`；完成后须调用 `onComplete()` 或 `onError`。
  func mnnGenerateStream(
    prompt: String,
    maxNewTokens: Int,
    onChunk: @escaping (String) -> Void,
    onComplete: @escaping () -> Void,
    onError: @escaping (String) -> Void
  )
}

public enum MnnLlmEngineBridge {
  /// 可选覆盖默认实现（例如自定义 MNN 封装）。未设置时 iOS 使用 `MnnLlmIosMnnBackend` + `AiimMnnLlmEngine`。
  public static weak var backend: MnnLlmFlutterBackend?

  /// iOS：默认同 Android 一样走内置 MNN；若设置了 `backend` 则优先用自定义实现。
  public static func resolvedBackend() -> MnnLlmFlutterBackend {
    if let b = backend { return b }
    return MnnLlmIosMnnBackend.shared
  }

  static func effectiveProbe() -> Bool {
    resolvedBackend().mnnProbe()
  }
}
