import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

final sttServiceProvider = Provider<SttService>((ref) {
  final service = SttService();
  ref.onDispose(service.dispose);
  return service;
});

class SttService {
  static const supportedLanguageCodes = <String>{'zh', 'en', 'ja', 'ko'};

  static const int _sampleRate = 16000;
  static const int _numThreads = 2;
  static const String _assetVersion = 'sensevoice-small-2024-07-17-int8-v1';
  static const String _cacheDirName = 'sense_voice_small';
  static const String _assetVersionFile = '.asset-version';

  final AudioRecorder _audioRecorder = AudioRecorder();

  bool _initialized = false;
  bool _bindingsReady = false;
  bool _listening = false;

  StreamSubscription<Uint8List>? _audioSubscription;
  sherpa_onnx.OfflineRecognizer? _recognizer;
  sherpa_onnx.VadModelConfig? _vadConfig;
  sherpa_onnx.VoiceActivityDetector? _vad;
  _SenseVoiceAssetPaths? _assetPaths;

  void Function(String status)? _onStatusChanged;
  void Function(String text, bool isFinal)? _onResult;

  Float32List _vadRemainder = Float32List(0);
  String _recognizedText = '';
  String _lastEmittedTranscript = '';

  bool get isListening => _listening;

  bool supportsLanguage(String langCode) {
    return supportedLanguageCodes.contains(langCode);
  }

  Future<bool> initialize() async {
    if (_initialized) return true;

    try {
      if (!_bindingsReady) {
        sherpa_onnx.initBindings();
        _bindingsReady = true;
      }

      _assetPaths = await _seedBundledAssetsToCache();
      _vadConfig = sherpa_onnx.VadModelConfig(
        sileroVad: sherpa_onnx.SileroVadModelConfig(
          model: _assetPaths!.vadPath,
          minSilenceDuration: 0.18,
          minSpeechDuration: 0.25,
          maxSpeechDuration: 3.0,
        ),
        numThreads: _numThreads,
        debug: kDebugMode,
      );

      _initialized = true;
      return true;
    } catch (error, stackTrace) {
      debugPrint('[stt] initialize failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _initialized = false;
      await _disposeSessionObjects();
      return false;
    }
  }

  /// Starts listening in the given language.
  /// Returns `false` if permission was denied or STT is unavailable.
  Future<bool> startListening({
    required String langCode,
    required void Function(String text, bool isFinal) onResult,
    void Function(String status)? onStatusChanged,
  }) async {
    if (!supportsLanguage(langCode)) {
      debugPrint('[stt] unsupported language: $langCode');
      return false;
    }

    if (!await _audioRecorder.hasPermission()) {
      debugPrint('[stt] microphone permission denied');
      return false;
    }

    if (!await _audioRecorder.isEncoderSupported(AudioEncoder.pcm16bits)) {
      debugPrint('[stt] pcm16bits encoder is not supported');
      return false;
    }

    final ok = await initialize();
    if (!ok || _assetPaths == null || _vadConfig == null) {
      return false;
    }

    await stopListening();

    _recognizer = _createRecognizer(langCode);
    _vad = sherpa_onnx.VoiceActivityDetector(
      config: _vadConfig!,
      bufferSizeInSeconds: 30,
    );

    _onStatusChanged = onStatusChanged;
    _onResult = onResult;
    _recognizedText = '';
    _lastEmittedTranscript = '';
    _vadRemainder = Float32List(0);

    try {
      final stream = await _audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
        ),
      );

      _audioSubscription = stream.listen(
        _handleAudioData,
        onError: (error, stackTrace) {
          debugPrint('[stt] audio stream error: $error');
          debugPrintStack(stackTrace: stackTrace);
          unawaited(_handleUnexpectedStop());
        },
        onDone: () {
          unawaited(_handleUnexpectedStop());
        },
        cancelOnError: true,
      );

      _listening = true;
      _onStatusChanged?.call('listening');
      return true;
    } catch (error, stackTrace) {
      debugPrint('[stt] start failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _listening = false;
      await _disposeSessionObjects();
      _onStatusChanged = null;
      _onResult = null;
      return false;
    }
  }

  Future<void> stopListening() async {
    final callback = _onResult;

    _listening = false;
    await _cancelAudioSubscription();
    await _stopRecorder();

    _flushVad(includeRemainder: true);
    final transcript = _recognizedText.trim();
    if (transcript.isNotEmpty) {
      callback?.call(transcript, true);
    }

    await _disposeSessionObjects();
    _onStatusChanged = null;
    _onResult = null;
  }

  void dispose() {
    _listening = false;
    _onStatusChanged = null;
    _onResult = null;
    unawaited(_cancelAudioSubscription());
    unawaited(_audioRecorder.dispose());
    _disposeSessionObjects();
  }

  sherpa_onnx.OfflineRecognizer _createRecognizer(String langCode) {
    final senseVoice = sherpa_onnx.OfflineSenseVoiceModelConfig(
      model: _assetPaths!.modelPath,
      language: langCode,
      useInverseTextNormalization: true,
    );

    final config = sherpa_onnx.OfflineRecognizerConfig(
      model: sherpa_onnx.OfflineModelConfig(
        senseVoice: senseVoice,
        tokens: _assetPaths!.tokensPath,
        debug: kDebugMode,
        numThreads: _numThreads,
      ),
    );

    return sherpa_onnx.OfflineRecognizer(config);
  }

  void _handleAudioData(Uint8List bytes) {
    if (!_listening || _vad == null || _recognizer == null) {
      return;
    }

    final samples = _pcm16ToFloat32(bytes);
    if (samples.isEmpty) {
      return;
    }

    final merged = Float32List(_vadRemainder.length + samples.length);
    merged.setAll(0, _vadRemainder);
    merged.setAll(_vadRemainder.length, samples);

    final windowSize = _vadConfig!.sileroVad.windowSize.toInt();
    var offset = 0;
    while (offset + windowSize <= merged.length) {
      _vad!.acceptWaveform(
        Float32List.sublistView(merged, offset, offset + windowSize),
      );
      _drainVadSegments();
      offset += windowSize;
    }

    _vadRemainder = offset == merged.length
        ? Float32List(0)
        : Float32List.fromList(merged.sublist(offset));
  }

  void _drainVadSegments() {
    if (_vad == null || _recognizer == null) {
      return;
    }

    while (!_vad!.isEmpty()) {
      final speechSegment = _vad!.front();
      final stream = _recognizer!.createStream();
      stream.acceptWaveform(
        samples: speechSegment.samples,
        sampleRate: _sampleRate,
      );
      _recognizer!.decode(stream);

      final text = _recognizer!.getResult(stream).text.trim();
      stream.free();
      _vad!.pop();

      if (text.isEmpty) {
        continue;
      }

      if (_recognizedText.isEmpty) {
        _recognizedText = text;
      } else {
        _recognizedText = '$_recognizedText\n$text';
      }

      _emitTranscript(isFinal: false);
    }
  }

  void _flushVad({required bool includeRemainder}) {
    if (_vad == null) {
      return;
    }

    if (includeRemainder && _vadRemainder.isNotEmpty) {
      final windowSize = _vadConfig!.sileroVad.windowSize.toInt();
      final padded = Float32List(windowSize);
      padded.setRange(0, _vadRemainder.length, _vadRemainder);
      _vad!.acceptWaveform(padded);
      _vadRemainder = Float32List(0);
    }

    _vad!.flush();
    _drainVadSegments();
  }

  void _emitTranscript({required bool isFinal}) {
    final transcript = _recognizedText.trim();
    if (transcript.isEmpty) {
      return;
    }

    if (!isFinal && transcript == _lastEmittedTranscript) {
      return;
    }

    _lastEmittedTranscript = transcript;
    _onResult?.call(transcript, isFinal);
  }

  Future<void> _handleUnexpectedStop() async {
    if (!_listening) {
      return;
    }

    _listening = false;
    await _cancelAudioSubscription();
    await _stopRecorder();

    _flushVad(includeRemainder: true);
    _emitTranscript(isFinal: true);
    _onStatusChanged?.call('notListening');

    await _disposeSessionObjects();
    _onStatusChanged = null;
    _onResult = null;
  }

  Future<void> _cancelAudioSubscription() async {
    await _audioSubscription?.cancel();
    _audioSubscription = null;
  }

  Future<void> _stopRecorder() async {
    try {
      await _audioRecorder.stop();
    } catch (_) {
      // Ignore stop errors during teardown.
    }
  }

  Future<void> _disposeSessionObjects() async {
    _vad?.free();
    _vad = null;

    _recognizer?.free();
    _recognizer = null;

    _vadRemainder = Float32List(0);
  }

  Future<_SenseVoiceAssetPaths> _seedBundledAssetsToCache() async {
    final supportDir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${supportDir.path}/$_cacheDirName');
    if (!cacheDir.existsSync()) {
      await cacheDir.create(recursive: true);
    }

    if (!await _isBundledCacheCurrent(cacheDir)) {
      for (final bundledAsset in _bundledAssets) {
        final bytes = await rootBundle.load(bundledAsset.assetPath);
        final outputFile = File(
          '${cacheDir.path}/${bundledAsset.cacheRelativePath}',
        );
        await outputFile.parent.create(recursive: true);
        await outputFile.writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          flush: true,
        );
      }

      await File(
        '${cacheDir.path}/$_assetVersionFile',
      ).writeAsString(_assetVersion, flush: true);
    }

    return _SenseVoiceAssetPaths(
      modelPath: '${cacheDir.path}/model.int8.onnx',
      tokensPath: '${cacheDir.path}/tokens.txt',
      vadPath: '${cacheDir.path}/silero_vad.onnx',
    );
  }

  Future<bool> _isBundledCacheCurrent(Directory cacheDir) async {
    final versionFile = File('${cacheDir.path}/$_assetVersionFile');
    if (!versionFile.existsSync()) {
      return false;
    }

    if ((await versionFile.readAsString()).trim() != _assetVersion) {
      return false;
    }

    for (final bundledAsset in _bundledAssets) {
      if (!File(
        '${cacheDir.path}/${bundledAsset.cacheRelativePath}',
      ).existsSync()) {
        return false;
      }
    }

    return true;
  }

  Float32List _pcm16ToFloat32(Uint8List bytes) {
    final sampleCount = bytes.lengthInBytes ~/ 2;
    final output = Float32List(sampleCount);
    final data = ByteData.sublistView(bytes);

    for (var i = 0; i < sampleCount; i += 1) {
      output[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }

    return output;
  }
}

const _bundledAssets = <_BundledAsset>[
  _BundledAsset(
    assetPath:
        'assets/models/sense-voice-zh-en-ja-ko-yue-int8-2024-07-17/model.int8.onnx',
    cacheRelativePath: 'model.int8.onnx',
  ),
  _BundledAsset(
    assetPath:
        'assets/models/sense-voice-zh-en-ja-ko-yue-int8-2024-07-17/tokens.txt',
    cacheRelativePath: 'tokens.txt',
  ),
  _BundledAsset(
    assetPath:
        'assets/models/sense-voice-zh-en-ja-ko-yue-int8-2024-07-17/silero_vad.onnx',
    cacheRelativePath: 'silero_vad.onnx',
  ),
];

class _BundledAsset {
  const _BundledAsset({
    required this.assetPath,
    required this.cacheRelativePath,
  });

  final String assetPath;
  final String cacheRelativePath;
}

class _SenseVoiceAssetPaths {
  const _SenseVoiceAssetPaths({
    required this.modelPath,
    required this.tokensPath,
    required this.vadPath,
  });

  final String modelPath;
  final String tokensPath;
  final String vadPath;
}
