import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/translation_state.dart';
import '../../core/stt/stt_service.dart';

class ConversationPage extends ConsumerStatefulWidget {
  const ConversationPage({super.key});

  @override
  ConsumerState<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends ConsumerState<ConversationPage> {
  late String _sourceLang;
  late String _targetLang;

  bool _listening = false;
  bool _starting = false;
  bool _translating = false;
  String _liveTranscript = '';
  String _liveTranslation = '';
  String? _translationError;
  Timer? _translateDebounce;
  String _queuedTranscript = '';
  String _lastTranslatedTranscript = '';

  @override
  void initState() {
    super.initState();
    final state = ref.read(translationProvider);
    _sourceLang = state.sourceLang == 'auto' ? 'zh' : state.sourceLang;
    if (!SttService.supportedLanguageCodes.contains(_sourceLang)) {
      _sourceLang = 'zh';
    }
    _targetLang = state.targetLang == _sourceLang ? 'en' : state.targetLang;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(translationProvider.notifier).initEngine();
    });
  }

  @override
  void dispose() {
    _translateDebounce?.cancel();
    ref.read(sttServiceProvider).stopListening();
    super.dispose();
  }

  Future<void> _startRealtimeTranslation() async {
    FocusScope.of(context).unfocus();
    if (_listening || _starting) {
      return;
    }

    if (!SttService.supportedLanguageCodes.contains(_sourceLang)) {
      _showMessage('SenseVoice-Small 当前仅支持中文、英语、日语、韩语语音输入');
      return;
    }

    final sttService = ref.read(sttServiceProvider);
    _translateDebounce?.cancel();

    setState(() {
      _starting = true;
      _translationError = null;
      _liveTranscript = '';
      _liveTranslation = '';
      _queuedTranscript = '';
      _lastTranslatedTranscript = '';
    });

    final started = await sttService.startListening(
      langCode: _sourceLang,
      onResult: _handleSpeechResult,
      onStatusChanged: _handleSpeechStatus,
    );

    if (!mounted) return;
    setState(() {
      _starting = false;
      _listening = started;
    });

    if (!started) {
      _showMessage('无法启用 SenseVoice-Small，请检查麦克风权限和模型资源');
    }
  }

  Future<void> _stopRealtimeTranslation() async {
    _translateDebounce?.cancel();
    await ref.read(sttServiceProvider).stopListening();

    final finalTranscript = _liveTranscript.trim();
    if (finalTranscript.isNotEmpty) {
      _queuedTranscript = finalTranscript;
      if (!_translating) {
        await _drainTranslationQueue();
      }
    }

    if (!mounted) return;
    setState(() {
      _starting = false;
      _listening = false;
    });
  }

  void _handleSpeechStatus(String status) {
    if (!mounted) return;
    if (status == 'done' || status == 'notListening') {
      _translateDebounce?.cancel();
      final finalTranscript = _liveTranscript.trim();
      if (finalTranscript.isNotEmpty) {
        _queuedTranscript = finalTranscript;
        if (!_translating) {
          unawaited(_drainTranslationQueue());
        }
      }
      setState(() {
        _starting = false;
        _listening = false;
      });
    }
  }

  void _handleSpeechResult(String text, bool isFinal) {
    if (!mounted) return;
    final transcript = text.trim();

    setState(() {
      _liveTranscript = transcript;
      _translationError = null;
      if (transcript.isEmpty) {
        _liveTranslation = '';
      }
    });

    if (transcript.isEmpty) {
      _translateDebounce?.cancel();
      _queuedTranscript = '';
      _lastTranslatedTranscript = '';
      return;
    }

    _scheduleLiveTranslation(transcript, immediate: isFinal);
  }

  void _scheduleLiveTranslation(String transcript, {required bool immediate}) {
    _translateDebounce?.cancel();
    _queuedTranscript = transcript;
    _translateDebounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 420),
      () {
        if (!_translating) {
          unawaited(_drainTranslationQueue());
        }
      },
    );
  }

  Future<void> _drainTranslationQueue() async {
    if (_translating) {
      return;
    }

    final ctrl = ref.read(translationProvider.notifier);
    setState(() {
      _translating = true;
    });

    while (mounted) {
      final transcript = _queuedTranscript.trim();
      if (transcript.isEmpty || transcript == _lastTranslatedTranscript) {
        break;
      }

      final translated = await ctrl.previewTranslate(
        text: transcript,
        sourceLang: _sourceLang,
        targetLang: _targetLang,
      );

      if (!mounted) {
        return;
      }

      if (transcript != _queuedTranscript.trim()) {
        continue;
      }

      if (translated == null || translated.isEmpty) {
        setState(() {
          _translationError = '翻译失败，请继续讲话或重新开始';
        });
        break;
      }

      setState(() {
        _liveTranslation = translated;
        _translationError = null;
        _lastTranslatedTranscript = transcript;
      });
    }

    if (!mounted) return;
    setState(() {
      _translating = false;
    });
  }

  void _swapLanguages() {
    if (!SttService.supportedLanguageCodes.contains(_targetLang)) {
      _showMessage('SenseVoice-Small 暂不支持把当前目标语言作为语音输入语言');
      return;
    }

    setState(() {
      final next = _sourceLang;
      _sourceLang = _targetLang;
      _targetLang = next;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final languageControlsEnabled = !_listening && !_starting && !_translating;
    final actionBusy = _starting || (_translating && !_listening);
    final actionListening = _listening || _starting;
    final actionLabel = actionBusy
        ? (_starting ? '正在启动语音识别…' : '正在整理最后一段译文…')
        : actionListening
        ? '停止语音识别翻译'
        : '开始语音识别翻译';
    final actionIcon = actionBusy
        ? null
        : actionListening
        ? Icons.stop_rounded
        : Icons.mic_none_rounded;
    final actionPressed = actionBusy
        ? null
        : actionListening
        ? _stopRealtimeTranslation
        : _startRealtimeTranslation;

    return Scaffold(
      appBar: AppBar(title: const Text('语音翻译')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              _ConversationPanel(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '语言设置',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${supportedLanguages[_sourceLang]} → ${supportedLanguages[_targetLang]}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF5E6A74),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('conv-source-$_sourceLang'),
                            initialValue: _sourceLang,
                            isDense: true,
                            decoration: _languageDecoration('源语言'),
                            items: supportedLanguages.entries
                                .where(
                                  (entry) =>
                                      entry.key != 'auto' &&
                                      SttService.supportedLanguageCodes
                                          .contains(entry.key),
                                )
                                .map(
                                  (entry) => DropdownMenuItem(
                                    value: entry.key,
                                    child: Text(entry.value),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: languageControlsEnabled
                                ? (value) {
                                    if (value != null && value != _targetLang) {
                                      setState(() => _sourceLang = value);
                                    }
                                  }
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton.filledTonal(
                          tooltip: '交换语言',
                          onPressed: languageControlsEnabled
                              ? _swapLanguages
                              : null,
                          icon: const Icon(Icons.swap_horiz_rounded),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('conv-target-$_targetLang'),
                            initialValue: _targetLang,
                            isDense: true,
                            decoration: _languageDecoration('目标语言'),
                            items: supportedLanguages.entries
                                .where((entry) => entry.key != 'auto')
                                .map(
                                  (entry) => DropdownMenuItem(
                                    value: entry.key,
                                    child: Text(entry.value),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: languageControlsEnabled
                                ? (value) {
                                    if (value != null && value != _sourceLang) {
                                      setState(() => _targetLang = value);
                                    }
                                  }
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: _ConversationPanel(
                        padding: const EdgeInsets.all(14),
                        child: _RealtimePanel(
                          title: '实时翻译',
                          badge: _translating
                              ? '翻译中'
                              : _listening
                              ? '实时更新'
                              : null,
                          helper:
                              '${supportedLanguages[_sourceLang]} → ${supportedLanguages[_targetLang]}',
                          text: _liveTranslation,
                          placeholder: _listening
                              ? '识别到语音后，译文会实时显示在这里。'
                              : '点击底部按钮开始实时语音翻译。',
                          textStyle: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF16202A),
                            height: 1.35,
                          ),
                          error: _translationError,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _ConversationPanel(
                        padding: const EdgeInsets.all(14),
                        child: _RealtimePanel(
                          title: '语音输入',
                          badge: _listening ? '识别中' : null,
                          helper: '当前识别语言：${supportedLanguages[_sourceLang]}',
                          text: _liveTranscript,
                          placeholder: _listening
                              ? '请开始说话，识别内容会实时显示在这里。'
                              : '开始识别后，原始语音文本会显示在这里。',
                          textStyle: theme.textTheme.bodyLarge?.copyWith(
                            color: const Color(0xFF21313D),
                            height: 1.6,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: actionPressed,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: actionListening
                      ? const Color(0xFF16202A)
                      : const Color(0xFF0A7C86),
                ),
                icon: actionBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(actionIcon),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationPanel extends StatelessWidget {
  const _ConversationPanel({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE1E8ED)),
      ),
      child: child,
    );
  }
}

class _RealtimePanel extends StatelessWidget {
  const _RealtimePanel({
    required this.title,
    required this.helper,
    required this.text,
    required this.placeholder,
    required this.textStyle,
    this.badge,
    this.error,
  });

  final String title;
  final String helper;
  final String text;
  final String placeholder;
  final TextStyle? textStyle;
  final String? badge;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasText = text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F7FA),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    color: Color(0xFF0A7C86),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          helper,
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF5E6A74),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF7FAFC),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE1E8ED)),
            ),
            child: SingleChildScrollView(
              child: Text(
                hasText ? text : placeholder,
                style:
                    (hasText
                        ? textStyle
                        : textStyle?.copyWith(
                            color: const Color(0xFF7B8791),
                            fontWeight: FontWeight.w500,
                          )) ??
                    TextStyle(
                      color: hasText
                          ? const Color(0xFF16202A)
                          : const Color(0xFF7B8791),
                      height: 1.6,
                    ),
              ),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(
            error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

InputDecoration _languageDecoration(String label) {
  return InputDecoration(
    labelText: label,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: const OutlineInputBorder(),
  );
}
