import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../channel/translation_channel.dart';
import '../native/cola_ffi.dart';

const supportedLanguages = <String, String>{
  'auto': '自动检测',
  'zh': '中文',
  'en': 'English',
  'ja': '日本語',
  'ko': '한국어',
  'fr': 'Français',
};

class TranslationRecord {
  const TranslationRecord({
    required this.source,
    required this.translated,
    required this.sourceLang,
    required this.targetLang,
    required this.time,
  });

  final String source;
  final String translated;
  final String sourceLang;
  final String targetLang;
  final DateTime time;
}

class TranslationState {
  const TranslationState({
    this.sourceLang = 'auto',
    this.targetLang = 'en',
    this.input = '',
    this.output = '',
    this.isLoading = false,
    this.engineReady = false,
    this.engineError,
    this.history = const [],
  });

  final String sourceLang;
  final String targetLang;
  final String input;
  final String output;
  final bool isLoading;
  final bool engineReady;
  final String? engineError;
  final List<TranslationRecord> history;

  TranslationState copyWith({
    String? sourceLang,
    String? targetLang,
    String? input,
    String? output,
    bool? isLoading,
    bool? engineReady,
    String? engineError,
    bool clearEngineError = false,
    List<TranslationRecord>? history,
  }) {
    return TranslationState(
      sourceLang: sourceLang ?? this.sourceLang,
      targetLang: targetLang ?? this.targetLang,
      input: input ?? this.input,
      output: output ?? this.output,
      isLoading: isLoading ?? this.isLoading,
      engineReady: engineReady ?? this.engineReady,
      engineError: clearEngineError ? null : (engineError ?? this.engineError),
      history: history ?? this.history,
    );
  }
}

class TranslationController extends StateNotifier<TranslationState> {
  TranslationController(this._channel) : super(const TranslationState());

  final TranslationChannel _channel;
  String? _modelPath;

  Future<bool> _ensureEngineReady() async {
    if (!state.engineReady) {
      await initEngine();
    }
    return state.engineReady;
  }

  Future<String> _translateWithModel({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    final modelPath = _modelPath;
    if (modelPath == null) {
      throw StateError('model path not resolved');
    }
    return translateOffMainIsolate(
      TranslationRequest(
        modelPath: modelPath,
        text: text,
        sourceLang: sourceLang,
        targetLang: targetLang,
      ),
    );
  }

  Future<void> initEngine() async {
    state = state.copyWith(clearEngineError: true);
    try {
      debugPrint('[cola] initEngine: calling getBundledModelPath');
      final path = await _channel.getBundledModelPath();
      debugPrint('[cola] bundled model path = $path');
      if (path == null || path.isEmpty) {
        state = state.copyWith(engineReady: false, engineError: '找不到模型文件');
        return;
      }
      _modelPath = path;
      debugPrint('[cola] initEngine: launching Isolate.run');
      final ready = await Isolate.run(() {
        final ffi = ColaFfi.instance;
        if (ffi.isReady) return true;
        return ffi.initEngine(path);
      });
      debugPrint('[cola] engine ready = $ready');
      state = state.copyWith(
        engineReady: ready,
        engineError: ready ? null : '模型加载失败，请重试',
        clearEngineError: ready,
      );
    } catch (e) {
      debugPrint('[cola] initEngine error: $e');
      state = state.copyWith(engineReady: false, engineError: '引擎初始化出错: $e');
    }
  }

  void setSourceLang(String lang) {
    if (lang == state.targetLang && lang != 'auto') {
      return;
    }
    state = state.copyWith(sourceLang: lang);
  }

  void setTargetLang(String lang) {
    if (lang == state.sourceLang) {
      return;
    }
    state = state.copyWith(targetLang: lang);
  }

  void swapLanguages() {
    if (state.sourceLang == 'auto') {
      return;
    }
    state = state.copyWith(
      sourceLang: state.targetLang,
      targetLang: state.sourceLang,
    );
  }

  void setInput(String value) {
    if (value.length > 256) {
      state = state.copyWith(input: value.substring(0, 256));
      return;
    }
    state = state.copyWith(input: value);
  }

  void clearInput() {
    state = state.copyWith(input: '', output: '');
  }

  Future<void> translate() async {
    final text = state.input.trim();
    if (text.isEmpty) {
      return;
    }

    if (!await _ensureEngineReady()) {
      state = state.copyWith(output: '[离线引擎未就绪] 请先下载并加载模型');
      return;
    }

    state = state.copyWith(isLoading: true);
    try {
      final output = await _translateWithModel(
        text: text,
        sourceLang: state.sourceLang,
        targetLang: state.targetLang,
      );
      final record = TranslationRecord(
        source: text,
        translated: output,
        sourceLang: state.sourceLang,
        targetLang: state.targetLang,
        time: DateTime.now(),
      );
      state = state.copyWith(
        isLoading: false,
        output: output,
        history: [record, ...state.history].take(20).toList(growable: false),
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        output: _fallbackLocalTranslate(text),
      );
    }
  }

  Future<String?> conversationTranslate({
    required String speechText,
    required String sourceLang,
    required String targetLang,
  }) async {
    final text = speechText.trim();
    if (text.isEmpty) {
      return null;
    }

    if (!await _ensureEngineReady()) {
      return null;
    }

    state = state.copyWith(isLoading: true);
    try {
      final translated = await _translateWithModel(
        text: text,
        sourceLang: sourceLang,
        targetLang: targetLang,
      );
      final record = TranslationRecord(
        source: text,
        translated: translated,
        sourceLang: sourceLang,
        targetLang: targetLang,
        time: DateTime.now(),
      );

      state = state.copyWith(
        isLoading: false,
        output: translated,
        history: [record, ...state.history].take(30).toList(growable: false),
      );
      return translated;
    } catch (_) {
      state = state.copyWith(isLoading: false);
      return null;
    }
  }

  Future<String?> previewTranslate({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    if (!await _ensureEngineReady()) {
      return null;
    }

    try {
      return await _translateWithModel(
        text: trimmed,
        sourceLang: sourceLang,
        targetLang: targetLang,
      );
    } catch (_) {
      return null;
    }
  }

  String _fallbackLocalTranslate(String text) {
    return '[离线降级] $text';
  }
}

final translationChannelProvider = Provider((_) => TranslationChannel());

final translationProvider =
    StateNotifierProvider<TranslationController, TranslationState>(
      (ref) => TranslationController(ref.read(translationChannelProvider)),
    );
