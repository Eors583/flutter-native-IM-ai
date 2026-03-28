import Flutter

/// 与 Android `MnnLlmPlugin` 相同通道名：`aiim/mnn_llm`、`aiim/mnn_llm_stream`。
final class MnnLlmPlugin: NSObject, FlutterPlugin {
  private let workQueue = DispatchQueue(label: "com.aiim.mnn_llm", qos: .userInitiated)

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = MnnLlmPlugin()

    let method = FlutterMethodChannel(
      name: "aiim/mnn_llm",
      binaryMessenger: registrar.messenger()
    )
    method.setMethodCallHandler { call, result in
      instance.handleCall(call, result: result)
    }

    let events = FlutterEventChannel(
      name: "aiim/mnn_llm_stream",
      binaryMessenger: registrar.messenger()
    )
    events.setStreamHandler(MnnLlmStreamHandler())
  }

  private func handleCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "probe":
      result(MnnLlmEngineBridge.effectiveProbe())

    case "loadModel":
      guard let dir = call.arguments as? [String: Any],
        let modelDir = dir["modelDir"] as? String,
        !modelDir.isEmpty
      else {
        result(
          FlutterError(code: "ARG", message: "modelDir required", details: nil))
        return
      }
      let cfgUrl = URL(fileURLWithPath: modelDir).appendingPathComponent("config.json")
      if !FileManager.default.fileExists(atPath: cfgUrl.path) {
        result(
          FlutterError(
            code: "NO_CFG", message: "config.json not found under \(modelDir)",
            details: nil))
        return
      }
      workQueue.async {
        do {
          let backend = MnnLlmEngineBridge.resolvedBackend()
          try backend.mnnLoadModel(configJsonPath: cfgUrl.path)
          DispatchQueue.main.async { result(true) }
        } catch {
          DispatchQueue.main.async {
            result(
              FlutterError(
                code: "LOAD", message: error.localizedDescription, details: nil))
          }
        }
      }

    case "unloadModel":
      workQueue.async {
        MnnLlmEngineBridge.resolvedBackend().mnnUnloadModel()
        DispatchQueue.main.async { result(nil) }
      }

    case "resetSession":
      workQueue.async {
        MnnLlmEngineBridge.resolvedBackend().mnnResetSession()
        DispatchQueue.main.async { result(nil) }
      }

    case "generate":
      guard let args = call.arguments as? [String: Any],
        let prompt = args["prompt"] as? String
      else {
        result(FlutterError(code: "ARG", message: "prompt required", details: nil))
        return
      }
      let maxNew = (args["maxNewTokens"] as? NSNumber)?.intValue ?? 512
      let backend = MnnLlmEngineBridge.resolvedBackend()
      workQueue.async {
        do {
          let out = try backend.mnnGenerate(prompt: prompt, maxNewTokens: maxNew)
          DispatchQueue.main.async { result(out) }
        } catch {
          DispatchQueue.main.async {
            result(
              FlutterError(
                code: "GEN", message: error.localizedDescription, details: nil))
          }
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

private final class MnnLlmStreamHandler: NSObject, FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    guard let map = arguments as? [String: Any],
      let prompt = map["prompt"] as? String
    else {
      return FlutterError(code: "ARG", message: "expected argument map", details: nil)
    }
    let maxNew = (map["maxNewTokens"] as? NSNumber)?.intValue ?? 512
    let backend = MnnLlmEngineBridge.resolvedBackend()
    if !backend.mnnProbe() {
      return FlutterError(
        code: "STATE", message: "Native MNN not available (probe false)", details: nil)
    }

    let work = DispatchQueue(label: "com.aiim.mnn_llm.stream", qos: .userInitiated)
    work.async {
      backend.mnnGenerateStream(
        prompt: prompt,
        maxNewTokens: maxNew,
        onChunk: { chunk in
          if chunk.isEmpty { return }
          DispatchQueue.main.async { events(chunk) }
        },
        onComplete: {
          DispatchQueue.main.async {
            events(FlutterEndOfEventStream)
          }
        },
        onError: { msg in
          DispatchQueue.main.async {
            events(FlutterError(code: "GEN", message: msg, details: nil))
          }
        }
      )
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    nil
  }
}
