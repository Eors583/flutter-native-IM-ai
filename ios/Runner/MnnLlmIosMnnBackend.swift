import Foundation

/// 默认 iOS 端侧实现：Objective-C++ `AiimMnnLlmEngine` + 官方 `MNN.framework`（需先本地编译）。
final class MnnLlmIosMnnBackend: NSObject, MnnLlmFlutterBackend {
  static let shared = MnnLlmIosMnnBackend()

  private let engine = AiimMnnLlmEngine.shared()
  private let serial = DispatchQueue(label: "com.aiim.mnn.llm.engine")

  func mnnProbe() -> Bool {
    AiimMnnLlmEngine.probe()
  }

  func mnnLoadModel(configJsonPath: String) throws {
    try serial.sync {
      try engine.load(withConfigPath: configJsonPath)
    }
  }

  func mnnUnloadModel() {
    serial.sync {
      engine.unloadModel()
    }
  }

  func mnnResetSession() {
    serial.sync {
      engine.resetSession()
    }
  }

  func mnnGenerate(prompt: String, maxNewTokens: Int) throws -> String {
    try serial.sync {
      try engine.generate(withPrompt: prompt, maxNewTokens: maxNewTokens) ?? ""
    }
  }

  func mnnGenerateStream(
    prompt: String,
    maxNewTokens: Int,
    onChunk: @escaping (String) -> Void,
    onComplete: @escaping () -> Void,
    onError: @escaping (String) -> Void
  ) {
    serial.sync {
      engine.generateStream(
        withPrompt: prompt,
        maxNewTokens: maxNewTokens,
        onChunk: onChunk,
        onComplete: onComplete,
        onError: onError
      )
    }
  }
}
