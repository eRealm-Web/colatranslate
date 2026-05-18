import Flutter
import UIKit

/// Bridges the cola.translate/engine MethodChannel onto the implicit Flutter
/// engine that backs the active scene. Registering inside the scene delegate
/// (rather than AppDelegate) is required ever since iOS 13 promoted scene
/// lifecycles — `application(_:didFinishLaunchingWithOptions:)` no longer has
/// access to the root view controller, so the previous registration silently
/// did nothing.
class SceneDelegate: FlutterSceneDelegate {

  private let channelName = "cola.translate/engine"
  private let modelPrefix = "Hy-MT1.5-1.8B-1.25bit"
  private var loadedModelPath: String?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    guard
      let windowScene = scene as? UIWindowScene,
      let controller = windowScene.windows.first?.rootViewController as? FlutterViewController
    else {
      return
    }
    registerEngineChannel(controller: controller)
  }

  private func registerEngineChannel(controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "engine_unavailable", message: "Engine is unavailable", details: nil))
        return
      }
      switch call.method {
      case "initEngine":
        result(self.initEngine())
      case "getBundledModelPath":
        result(self.bundledModelPath())
      case "listModels":
        result(self.listModels())
      case "downloadModel":
        result(self.bundledModelPath() != nil)
      case "deleteModel":
        let args = call.arguments as? [String: Any]
        let modelName = (args?["modelName"] as? String) ?? "\(self.modelPrefix).gguf"
        result(self.deleteModel(modelName: modelName))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func modelsDirectory() -> URL {
    let fm = FileManager.default
    let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = base.appendingPathComponent("models", isDirectory: true)
    if !fm.fileExists(atPath: dir.path) {
      try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    return dir
  }

  private func initEngine() -> Bool {
    return bundledModelPath() != nil
  }

  private func listModels() -> [String] {
    let dir = modelsDirectory()
    let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    return files.filter { $0.hasSuffix(".gguf") }.sorted()
  }

  private func bundledModelPath() -> String? {
    let fname = "\(modelPrefix).gguf"
    let assetPath = "assets/models/\(fname)"
    let key = FlutterDartProject.lookupKey(forAsset: assetPath)
    NSLog("[cola] lookupKey(\(assetPath)) = \(key)")
    NSLog("[cola] bundlePath = \(Bundle.main.bundlePath)")

    // Strategy 1: direct path concatenation against bundlePath.
    // In flutter-run debug builds, `key` is typically a relative path like
    // "Frameworks/App.framework/flutter_assets/assets/models/Hy-...gguf"
    // which Bundle.main.path(forResource:) won't always resolve.
    let direct = (Bundle.main.bundlePath as NSString).appendingPathComponent(key)
    if FileManager.default.fileExists(atPath: direct) {
      NSLog("[cola] resolved via direct concat: \(direct)")
      loadedModelPath = direct
      return direct
    }

    // Strategy 2: Bundle.main resource lookup (works for some build modes).
    if let p = Bundle.main.path(forResource: key, ofType: nil) {
      NSLog("[cola] resolved via Bundle.path: \(p)")
      loadedModelPath = p
      return p
    }

    // Strategy 3: split subdir + filename for inDirectory lookup.
    let bare = (key as NSString).lastPathComponent
    let subdir = (key as NSString).deletingLastPathComponent
    if let p = Bundle.main.path(forResource: bare, ofType: nil, inDirectory: subdir) {
      NSLog("[cola] resolved via Bundle.path(inDirectory:): \(p)")
      loadedModelPath = p
      return p
    }

    // Strategy 4: copy in Application Support (downloaded model).
    let copyPath = modelsDirectory().appendingPathComponent(fname).path
    if FileManager.default.fileExists(atPath: copyPath) {
      NSLog("[cola] resolved via app-support copy: \(copyPath)")
      loadedModelPath = copyPath
      return copyPath
    }

    NSLog("[cola] FAILED to resolve model path. key=\(key) direct=\(direct)")
    return nil
  }

  private func deleteModel(modelName: String) -> Bool {
    let target = modelsDirectory().appendingPathComponent(modelName)
    if FileManager.default.fileExists(atPath: target.path) {
      try? FileManager.default.removeItem(at: target)
      if loadedModelPath == target.path {
        loadedModelPath = nil
      }
      return true
    }
    return false
  }
}
