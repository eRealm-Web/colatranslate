import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/translation_state.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  List<String> _models = const [];
  bool _refreshing = false;

  Future<void> _refreshModels() async {
    if (mounted) {
      setState(() => _refreshing = true);
    }
    await ref.read(translationProvider.notifier).initEngine();
    final channel = ref.read(translationChannelProvider);
    final models = await channel.listModels();
    if (mounted) {
      setState(() {
        _models = models;
        _refreshing = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refreshModels();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(translationProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设备状态')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF102A35), Color(0xFF355468)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '本地引擎状态',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  state.engineReady ? '引擎已完成加载，可以直接使用。' : '引擎尚未就绪，可手动重新检测。',
                  style: const TextStyle(
                    color: Color(0xD9FFFFFF),
                    height: 1.45,
                  ),
                ),
                if (state.engineError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    state.engineError!,
                    style: const TextStyle(
                      color: Color(0xFFFFD0D0),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: _refreshing ? null : _refreshModels,
                  icon: _refreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: Text(_refreshing ? '检测中…' : '重新检测设备状态'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFE1E8ED)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '本机模型',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (_models.isEmpty)
                  const Text(
                    '当前没有检测到可用模型。',
                    style: TextStyle(color: Color(0xFF7B8791)),
                  )
                else
                  ..._models.map(
                    (model) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(model),
                      subtitle: const Text('状态：本地可用'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFE1E8ED)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('隐私', style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(height: 8),
                Text(
                  '所有翻译与语音识别流程都在设备侧完成，不上传用户内容。',
                  style: TextStyle(height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
