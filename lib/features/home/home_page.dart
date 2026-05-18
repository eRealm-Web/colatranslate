import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/translation_state.dart';
import '../../core/stt/stt_service.dart';
import '../../core/tts/supertonic_tts_controller.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  late final TextEditingController _controller;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(translationProvider.notifier).initEngine();
    });
  }

  @override
  void dispose() {
    ref.read(sttServiceProvider).stopListening();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    FocusScope.of(context).unfocus();
    final state = ref.read(translationProvider);
    final ctrl = ref.read(translationProvider.notifier);
    final sttService = ref.read(sttServiceProvider);

    if (_listening) {
      await sttService.stopListening();
      if (!mounted) return;
      setState(() => _listening = false);
      return;
    }

    if (state.sourceLang == 'auto') {
      _showMessage('语音输入前，请先把源语言改成具体语言');
      return;
    }

    if (!sttService.supportsLanguage(state.sourceLang)) {
      _showMessage('SenseVoice-Small 当前仅支持中文、英语、日语、韩语语音输入');
      return;
    }

    final started = await sttService.startListening(
      langCode: state.sourceLang,
      onResult: (text, isFinal) {
        ctrl.setInput(text);
        if (isFinal && mounted) {
          setState(() => _listening = false);
        }
      },
    );

    if (!mounted) return;
    setState(() => _listening = started);
    if (!started) {
      _showMessage('无法启用 SenseVoice-Small，请检查麦克风权限和模型资源');
    }
  }

  Future<void> _copyOutput(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _showMessage('已复制译文');
  }

  Future<void> _speakOutput({
    required String text,
    required String language,
  }) async {
    FocusScope.of(context).unfocus();
    final message = await ref
        .read(supertonicTtsProvider.notifier)
        .speak(text: text, language: language);
    if (!mounted || message == null) return;
    _showMessage(message);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(translationProvider);
    final ttsState = ref.watch(supertonicTtsProvider);
    final ctrl = ref.read(translationProvider.notifier);

    if (_controller.text != state.input) {
      _controller.value = TextEditingValue(
        text: state.input,
        selection: TextSelection.collapsed(offset: state.input.length),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('可乐翻译'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _EngineBadge(
              ready: state.engineReady,
              error: state.engineError,
              onRetry: ctrl.initEngine,
            ),
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverList.list(
                children: [
                  const SizedBox(height: 16),
                  _SurfacePanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                key: ValueKey('source-${state.sourceLang}'),
                                initialValue: state.sourceLang,
                                decoration: const InputDecoration(
                                  labelText: '源语言',
                                ),
                                items: supportedLanguages.entries
                                    .map(
                                      (entry) => DropdownMenuItem(
                                        value: entry.key,
                                        child: Text(entry.value),
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: (value) {
                                  if (value != null) {
                                    ctrl.setSourceLang(value);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton.filledTonal(
                              tooltip: '交换语言',
                              onPressed: ctrl.swapLanguages,
                              icon: const Icon(Icons.swap_horiz_rounded),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                key: ValueKey('target-${state.targetLang}'),
                                initialValue: state.targetLang,
                                decoration: const InputDecoration(
                                  labelText: '目标语言',
                                ),
                                items: supportedLanguages.entries
                                    .where((entry) => entry.key != 'auto')
                                    .map(
                                      (entry) => DropdownMenuItem(
                                        value: entry.key,
                                        child: Text(entry.value),
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: (value) {
                                  if (value != null) {
                                    ctrl.setTargetLang(value);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _controller,
                          minLines: 6,
                          maxLines: 8,
                          maxLength: 256,
                          onChanged: ctrl.setInput,
                          decoration: const InputDecoration(
                            hintText: '输入要翻译的文本，或使用下方语音识别直接填入内容',
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _toggleListening,
                                icon: Icon(
                                  _listening
                                      ? Icons.stop_circle_outlined
                                      : Icons.mic_none_rounded,
                                ),
                                label: Text(_listening ? '停止识别' : '语音输入'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              tooltip: '清空',
                              onPressed: state.input.isEmpty
                                  ? null
                                  : ctrl.clearInput,
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: state.isLoading ? null : ctrl.translate,
                          icon: state.isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : const Icon(Icons.auto_awesome_rounded),
                          label: Text(state.isLoading ? '翻译中…' : '开始离线翻译'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SurfacePanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '结果',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            if (state.output.isNotEmpty) ...[
                              OutlinedButton.icon(
                                onPressed: ttsState.isBusy
                                    ? null
                                    : () => _speakOutput(
                                        text: state.output,
                                        language: state.targetLang,
                                      ),
                                icon: ttsState.isBusy
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                        ),
                                      )
                                    : const Icon(Icons.volume_up_rounded),
                                label: Text(
                                  ttsState.isPreparing
                                      ? '准备语音…'
                                      : ttsState.isSynthesizing
                                      ? '合成中…'
                                      : '发音',
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: () => _copyOutput(state.output),
                                icon: const Icon(Icons.content_copy_rounded),
                                label: const Text('复制'),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 14),
                        SelectableText(
                          state.output.isEmpty ? '翻译结果会显示在这里。' : state.output,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            height: 1.6,
                            color: state.output.isEmpty
                                ? const Color(0xFF7B8791)
                                : const Color(0xFF16202A),
                          ),
                        ),
                        if (state.output.isNotEmpty &&
                            ttsState.statusLabel != null &&
                            (ttsState.isBusy || ttsState.error != null)) ...[
                          const SizedBox(height: 14),
                          Text(
                            ttsState.statusLabel!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: ttsState.error != null
                                  ? theme.colorScheme.error
                                  : const Color(0xFF0A7C86),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (state.engineError != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            state.engineError!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EngineBadge extends StatelessWidget {
  const _EngineBadge({
    required this.ready,
    required this.error,
    required this.onRetry,
  });

  final bool ready;
  final String? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return ActionChip(
        avatar: const Icon(Icons.error_outline_rounded, size: 18),
        label: const Text('引擎异常'),
        onPressed: onRetry,
      );
    }

    return Chip(
      avatar: Icon(
        ready ? Icons.memory_rounded : Icons.hourglass_bottom_rounded,
        size: 18,
      ),
      label: Text(ready ? '引擎就绪' : '引擎加载中'),
    );
  }
}

class _SurfacePanel extends StatelessWidget {
  const _SurfacePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE1E8ED)),
      ),
      child: child,
    );
  }
}
