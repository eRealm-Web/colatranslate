import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supertonic_flutter/supertonic_flutter.dart';

import 'supertonic_tts_state.dart';

const _supertonicOnnxAssetDir = 'assets/onnx';
const _supertonicVoiceStyleAssetDir = 'assets/voice_styles';
const _supertonicCacheRootDirName = 'supertonic_models';
const _supertonicAssetVersion = 'supertone/supertonic-3-bundled-v1';
const _supertonicAssetVersionFile = '.cola-supertonic-bundled-version';
const _supertonicVoiceStyle = 'F2';

const _supertonicOnnxFiles = <String>[
  'duration_predictor.onnx',
  'text_encoder.onnx',
  'vector_estimator.onnx',
  'vocoder.onnx',
  'tts.json',
  'unicode_indexer.json',
];

const _supertonicVoiceStyleFiles = <String>[
  'F1.json',
  'F2.json',
  'F3.json',
  'F4.json',
  'F5.json',
  'M1.json',
  'M2.json',
  'M3.json',
  'M4.json',
  'M5.json',
];

class _BundledSupertonicAsset {
  const _BundledSupertonicAsset({
    required this.assetPath,
    required this.cacheRelativePath,
  });

  final String assetPath;
  final String cacheRelativePath;
}

final _supertonicBundledAssets = [
  ..._supertonicOnnxFiles.map(
    (fileName) => _BundledSupertonicAsset(
      assetPath: '$_supertonicOnnxAssetDir/$fileName',
      cacheRelativePath: 'onnx/$fileName',
    ),
  ),
  ..._supertonicVoiceStyleFiles.map(
    (fileName) => _BundledSupertonicAsset(
      assetPath: '$_supertonicVoiceStyleAssetDir/$fileName',
      cacheRelativePath: 'voice_styles/$fileName',
    ),
  ),
];

final supertonicTtsProvider =
    StateNotifierProvider<SupertonicTtsController, SupertonicTtsState>(
      (ref) => SupertonicTtsController(),
    );

class _SupertonicAudioPlayer {
  _SupertonicAudioPlayer();

  final AudioPlayer _player = AudioPlayer();
  File? _lastTempFile;
  var _isDisposed = false;

  Future<void> play(TTSResult result) async {
    _throwIfDisposed();
    await stop();

    final file = await _nextTempWavFile();
    await file.writeAsBytes(result.toWavBytes(), flush: true);
    _lastTempFile = file;

    await _player.play(
      DeviceFileSource(file.path, mimeType: 'audio/wav'),
      mode: PlayerMode.mediaPlayer,
    );
  }

  Future<void> stop() async {
    if (_isDisposed) {
      return;
    }
    await _player.stop();
    await _deleteLastTempFile();
  }

  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    unawaited(_player.stop());
    _player.dispose();
    unawaited(_deleteLastTempFile());
  }

  Future<File> _nextTempWavFile() async {
    final cacheDir = await getTemporaryDirectory();
    final fileName =
        'cola-supertonic-${DateTime.now().microsecondsSinceEpoch}.wav';
    return File('${cacheDir.path}/$fileName');
  }

  Future<void> _deleteLastTempFile() async {
    final file = _lastTempFile;
    _lastTempFile = null;
    if (file == null || !file.existsSync()) {
      return;
    }
    await file.delete();
  }

  void _throwIfDisposed() {
    if (_isDisposed) {
      throw StateError('Supertonic audio player has been disposed');
    }
  }
}

class SupertonicTtsController extends StateNotifier<SupertonicTtsState> {
  SupertonicTtsController() : super(const SupertonicTtsState());

  final SupertonicTTS _tts = SupertonicTTS();
  final _SupertonicAudioPlayer _player = _SupertonicAudioPlayer();

  bool _initialized = false;
  Future<bool>? _prepareTask;

  bool get _runtimeSupported =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isLinux;

  bool supportsLanguage(String language) {
    return _runtimeSupported &&
        supertonicTtsSupportedLanguages.contains(language);
  }

  Future<String?> speak({
    required String text,
    required String language,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return '没有可发音的内容';
    }

    if (!_runtimeSupported) {
      final message = '当前平台暂未接入 Supertonic 3 发音';
      state = state.copyWith(error: message, clearCurrentFile: true);
      return message;
    }

    if (!supertonicTtsSupportedLanguages.contains(language)) {
      final message = _unsupportedMessage(language);
      state = state.copyWith(error: message, clearCurrentFile: true);
      return message;
    }

    if (state.isSynthesizing) {
      return '语音正在生成，请稍候';
    }

    final ready = await _ensureReady();
    if (!ready) {
      return state.error ?? 'Supertonic 3 初始化失败';
    }

    state = state.copyWith(
      isSynthesizing: true,
      clearError: true,
      clearCurrentFile: true,
    );

    try {
      await _player.stop();
      final result = await _tts.synthesize(
        trimmed,
        language: language,
        voiceStyle: _supertonicVoiceStyle,
        config: const TTSConfig(
          denoisingSteps: 5,
          speechSpeed: 1.0,
          silenceDuration: 0.24,
        ),
      );
      await _player.play(result);
      state = state.copyWith(
        ready: true,
        isSynthesizing: false,
        clearError: true,
      );
      return null;
    } catch (error) {
      final message = '语音播放失败：$error';
      debugPrint('[supertonic] $message');
      state = state.copyWith(
        ready: false,
        isSynthesizing: false,
        error: message,
      );
      return message;
    }
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<bool> _ensureReady() async {
    if (_initialized) {
      return true;
    }

    if (!_runtimeSupported) {
      state = state.copyWith(error: '当前平台暂未接入 Supertonic 3 发音');
      return false;
    }

    return _prepareTask ??= _prepare().whenComplete(() {
      _prepareTask = null;
    });
  }

  Future<bool> _prepare() async {
    state = state.copyWith(
      ready: false,
      isPreparing: true,
      isSynthesizing: false,
      downloadProgress: 0,
      downloadedFiles: 0,
      totalFiles: _supertonicBundledAssets.length,
      clearError: true,
      clearCurrentFile: true,
    );

    try {
      await _initializeEngine();
      _initialized = true;
      state = state.copyWith(
        ready: true,
        isPreparing: false,
        clearError: true,
        clearCurrentFile: true,
      );
      return true;
    } catch (error) {
      debugPrint('[supertonic] prepare failed: $error');
      _initialized = false;
      state = state.copyWith(
        ready: false,
        isPreparing: false,
        error: 'Supertonic 3 初始化失败：$error',
      );
      return false;
    }
  }

  Future<void> _initializeEngine() async {
    try {
      await _seedBundledAssetsToCache();
      await _tts.initialize(
        onnxDir: _supertonicOnnxAssetDir,
        voiceStylesDir: _supertonicVoiceStyleAssetDir,
      );
    } catch (_) {
      await _player.stop();
      _tts.dispose();
      _initialized = false;
      rethrow;
    }
  }

  Future<Directory> _cacheRootDir() async {
    final supportDir = await getApplicationSupportDirectory();
    final rootDir = Directory(
      '${supportDir.path}/$_supertonicCacheRootDirName',
    );
    if (!rootDir.existsSync()) {
      await rootDir.create(recursive: true);
    }
    return rootDir;
  }

  Future<void> _seedBundledAssetsToCache() async {
    final rootDir = await _cacheRootDir();
    if (await _isBundledCacheCurrent(rootDir)) {
      return;
    }

    var completedAssets = 0;
    for (final bundledAsset in _supertonicBundledAssets) {
      final bytes = await rootBundle.load(bundledAsset.assetPath);
      final outputFile = File(
        '${rootDir.path}/${bundledAsset.cacheRelativePath}',
      );
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
      completedAssets += 1;
      state = state.copyWith(
        isPreparing: true,
        downloadProgress: completedAssets / _supertonicBundledAssets.length,
        downloadedFiles: completedAssets,
        totalFiles: _supertonicBundledAssets.length,
        currentFile: bundledAsset.cacheRelativePath,
        clearError: true,
      );
    }

    await File(
      '${rootDir.path}/$_supertonicAssetVersionFile',
    ).writeAsString(_supertonicAssetVersion, flush: true);
  }

  Future<bool> _isBundledCacheCurrent(Directory rootDir) async {
    final versionFile = File('${rootDir.path}/$_supertonicAssetVersionFile');
    if (!versionFile.existsSync()) {
      return false;
    }

    if ((await versionFile.readAsString()).trim() != _supertonicAssetVersion) {
      return false;
    }

    for (final bundledAsset in _supertonicBundledAssets) {
      if (!File(
        '${rootDir.path}/${bundledAsset.cacheRelativePath}',
      ).existsSync()) {
        return false;
      }
    }
    return true;
  }

  String _unsupportedMessage(String language) {
    switch (language) {
      case 'auto':
        return '请先选择具体语言后再发音';
      default:
        return '当前语言暂未接入 Supertonic 3 发音';
    }
  }

  @override
  void dispose() {
    unawaited(_player.stop());
    _player.dispose();
    _tts.dispose();
    super.dispose();
  }
}
