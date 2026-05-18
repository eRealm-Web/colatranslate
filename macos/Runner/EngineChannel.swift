import Cocoa
import FlutterMacOS

/// macOS counterpart of `SceneDelegate` on iOS. Bridges
/// `cola.translate/engine` MethodChannel onto the Flutter engine that backs
/// `MainFlutterWindow`. Without this the Dart side throws
/// `MissingPluginException` on `getBundledModelPath`.
enum EngineChannel {

  private static let channelName = "cola.translate/engine"
  private static let modelPrefix = "Hy-MT1.5-1.8B-1.25bit"
  private static var loadedModelPath: String?

  /// macOS sandbox swallows stderr/stdout from `open`-launched apps and the
  /// unified log mutes `NSLog` in Release builds, so route a few lines into
  /// the app container's `Documents/cola-debug.log` for forensic use.
  private static func dbg(_ msg: String) {
    NSLog("cola[swift]: %@", msg)
    guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
      .appendingPathComponent("cola-debug.log"),
      let data = "[\(Date())] \(msg)\n".data(using: .utf8) else { return }
    if let handle = try? FileHandle(forWritingTo: url) {
      handle.seekToEndOfFile()
      handle.write(data)
      try? handle.close()
    } else {
      try? data.write(to: url)
    }
  }

  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "initEngine":
        result(bundledModelPath() != nil)
      case "getBundledModelPath":
        result(bundledModelPath())
      case "listModels":
        result(listModels())
      case "downloadModel":
        result(bundledModelPath() != nil)
      case "deleteModel":
        let args = call.arguments as? [String: Any]
        let modelName = (args?["modelName"] as? String) ?? "\(modelPrefix).gguf"
        result(deleteModel(modelName: modelName))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func modelsDirectory() -> URL {
    let fm = FileManager.default
    let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = base.appendingPathComponent("models", isDirectory: true)
    if !fm.fileExists(atPath: dir.path) {
      try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    return dir
  }

  private static func listModels() -> [String] {
    let dir = modelsDirectory()
    let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    return files.filter { $0.hasSuffix(".gguf") }.sorted()
  }

  private static func bundledModelPath() -> String? {
    let fname = "\(modelPrefix).gguf"
    dbg("bundledModelPath called")
    // On macOS `FlutterDartProject.lookupKey(forAsset:)` returns a path that
    // is relative to `Bundle.main.bundlePath` itself (e.g. starts with
    // `Contents/Frameworks/App.framework/Resources/flutter_assets/...`), not
    // a Bundle resource key. So we just concatenate and check.
    let key = FlutterDartProject.lookupKey(forAsset: "assets/models/\(fname)")
    dbg("lookup key=\(key)")
    let direct = (Bundle.main.bundlePath as NSString).appendingPathComponent(key)
    if FileManager.default.fileExists(atPath: direct) {
      dbg("resolved (main bundle)=\(direct)")
      loadedModelPath = direct
      return direct
    }
    // Fallback: hardcoded layout used by Flutter's macOS embedder.
    let fallback = (Bundle.main.bundlePath as NSString).appendingPathComponent(
      "Contents/Frameworks/App.framework/Resources/flutter_assets/assets/models/\(fname)"
    )
    if FileManager.default.fileExists(atPath: fallback) {
      dbg("resolved (fallback layout)=\(fallback)")
      loadedModelPath = fallback
      return fallback
    }
    let copyPath = modelsDirectory().appendingPathComponent(fname).path
    if FileManager.default.fileExists(atPath: copyPath) {
      dbg("resolved (copy)=\(copyPath)")
      loadedModelPath = copyPath
      return copyPath
    }
    dbg("bundledModelPath NOT FOUND (key=\(key), direct=\(direct))")
    return nil
  }

  private static func deleteModel(modelName: String) -> Bool {
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
