import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'supertonic_tts_state.dart';

final supertonicTtsProvider =
    StateNotifierProvider<SupertonicTtsController, SupertonicTtsState>(
      (ref) => SupertonicTtsController(),
    );

class SupertonicTtsController extends StateNotifier<SupertonicTtsState> {
  SupertonicTtsController() : super(const SupertonicTtsState());

  bool supportsLanguage(String language) => false;

  Future<String?> speak({
    required String text,
    required String language,
  }) async {
    final message = '当前平台暂未接入 Supertonic 3 发音';
    state = state.copyWith(error: message);
    return message;
  }

  Future<void> stop() async {}
}
