const supertonicTtsSupportedLanguages = <String>{'zh', 'en', 'ja', 'ko', 'fr'};

class SupertonicTtsState {
  const SupertonicTtsState({
    this.ready = false,
    this.isPreparing = false,
    this.isSynthesizing = false,
    this.downloadProgress = 0,
    this.downloadedFiles = 0,
    this.totalFiles = 0,
    this.currentFile,
    this.error,
  });

  final bool ready;
  final bool isPreparing;
  final bool isSynthesizing;
  final double downloadProgress;
  final int downloadedFiles;
  final int totalFiles;
  final String? currentFile;
  final String? error;

  bool get isBusy => isPreparing || isSynthesizing;

  String? get statusLabel {
    if (error != null && error!.isNotEmpty) {
      return error;
    }

    if (isPreparing) {
      final safeDownloaded = totalFiles == 0 || downloadedFiles <= totalFiles
          ? downloadedFiles
          : totalFiles;
      final fileLabel = currentFile == null
          ? ''
          : ' · ${currentFile!.split('/').last}';
      return totalFiles > 0
          ? '正在准备 Supertonic 3 $safeDownloaded/$totalFiles$fileLabel'
          : '正在准备 Supertonic 3';
    }

    if (isSynthesizing) {
      return '正在生成语音…';
    }

    return null;
  }

  SupertonicTtsState copyWith({
    bool? ready,
    bool? isPreparing,
    bool? isSynthesizing,
    double? downloadProgress,
    int? downloadedFiles,
    int? totalFiles,
    String? currentFile,
    bool clearCurrentFile = false,
    String? error,
    bool clearError = false,
  }) {
    return SupertonicTtsState(
      ready: ready ?? this.ready,
      isPreparing: isPreparing ?? this.isPreparing,
      isSynthesizing: isSynthesizing ?? this.isSynthesizing,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadedFiles: downloadedFiles ?? this.downloadedFiles,
      totalFiles: totalFiles ?? this.totalFiles,
      currentFile: clearCurrentFile ? null : (currentFile ?? this.currentFile),
      error: clearError ? null : (error ?? this.error),
    );
  }
}
