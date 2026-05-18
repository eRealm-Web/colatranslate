import 'package:flutter/services.dart';

class TranslationChannel {
  static const MethodChannel _channel = MethodChannel('cola.translate/engine');

  Future<bool> initEngine() async {
    final ready = await _channel.invokeMethod<bool>('initEngine');
    return ready ?? false;
  }

  /// Resolves the absolute filesystem path of the bundled GGUF model. On
  /// Android this triggers a one-time copy from APK assets to internal
  /// storage; on iOS it points directly inside the read-only app bundle.
  Future<String?> getBundledModelPath() async {
    return await _channel.invokeMethod<String>('getBundledModelPath');
  }

  Future<String> translate({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    final result = await _channel.invokeMethod<String>('translate', {
      'text': text,
      'sourceLang': sourceLang,
      'targetLang': targetLang,
    });
    return result ?? '';
  }

  Future<List<String>> listModels() async {
    final models = await _channel.invokeMethod<List<dynamic>>('listModels');
    if (models == null) {
      return const [];
    }
    return models.map((e) => e.toString()).toList(growable: false);
  }

  Future<bool> downloadModel({required String modelName}) async {
    final ok = await _channel.invokeMethod<bool>('downloadModel', {
      'modelName': modelName,
    });
    return ok ?? false;
  }

  Future<bool> deleteModel({required String modelName}) async {
    final ok = await _channel.invokeMethod<bool>('deleteModel', {
      'modelName': modelName,
    });
    return ok ?? false;
  }
}
