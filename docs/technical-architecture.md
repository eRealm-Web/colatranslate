# 技术架构说明

## 1. 技术栈概览

- Flutter 3.x / Dart 3.11
- Riverpod 2.x
- `dart:ffi`
- `record`
- `sherpa_onnx`
- `supertonic_flutter`
- `audioplayers`
- `path_provider`
- 本地原生引擎：`llama.cpp` PR `pr-22836-stq_0`

## 2. Flutter 层架构

### 2.1 入口与导航

`lib/main.dart` 负责：

- 启动 `ProviderScope`
- 配置全局主题
- 构建三页 `IndexedStack`
- 提供统一 `NavigationBar`

这样做的好处是三页切换时状态不会因为简单的 tab 切换而全部销毁。

### 2.2 状态管理

当前核心 provider 如下：

- `translationProvider`
- `translationChannelProvider`
- `sttServiceProvider`
- `supertonicTtsProvider`

其中：

- 翻译主状态使用 `StateNotifier<TranslationState>`。
- STT 使用 `Provider<SttService>`，由服务自身管理会话对象。
- TTS 使用独立 `StateNotifier` 管理准备和合成状态。

## 3. 翻译状态与控制器

`lib/core/models/translation_state.dart` 定义了当前翻译层的主状态。

### 3.1 状态字段

- `sourceLang`
- `targetLang`
- `input`
- `output`
- `isLoading`
- `engineReady`
- `engineError`
- `history`

### 3.2 控制器职责

`TranslationController` 负责：

- 初始化引擎 `initEngine()`
- 设置语言与输入内容
- 文本翻译 `translate()`
- 语音页局部预翻译 `previewTranslate()`
- 兼容保留的对话翻译 `conversationTranslate()`

### 3.3 状态更新策略

- 文本翻译成功后写入 `output` 与 `history`。
- `previewTranslate()` 只返回译文，不修改全局历史。
- 这样可以把语音页的实时 partial 结果隔离在局部状态中。

## 4. FFI 翻译引擎

### 4.1 Dart 侧绑定

`lib/core/native/cola_ffi.dart` 绑定以下 C ABI：

- `cola_init`
- `cola_is_ready`
- `cola_translate`
- `cola_free_string`
- `cola_shutdown`

平台分流如下：

- Android：`DynamicLibrary.open('libcola_translate.so')`
- Linux：`DynamicLibrary.open('libcola_translate.so')`
- Windows：`DynamicLibrary.open('cola_translate.dll')`
- iOS / macOS：`DynamicLibrary.process()`

### 4.2 调用模型

翻译实际调用通过 `TranslationRequest` + `translateOffMainIsolate()` 进入后台 isolate。

这样做的原因：

- llama.cpp 推理是 CPU 密集操作。
- 如果直接跑在 UI isolate，会造成掉帧和卡顿。

### 4.3 原生引擎实现

`native/cola_translate.cpp` 是最小包装层，负责：

- 加载 GGUF 模型
- 初始化 llama context
- 创建 sampler 链
- 把输入文本拼成 Hy-MT prompt
- 逐 token 解码并拼接输出

当前关键参数：

- `n_gpu_layers = 0`
- `use_mmap = true`
- `n_ctx = 1024`
- `n_batch = 512`
- `n_threads = 4`
- `max_new = 256`

当前 sampler 链：

- `top_k(20)`
- `top_p(0.8)`
- `temp(0.7)`
- `dist(seed)`

### 4.4 Prompt 策略

当前 prompt 会构造成：

- `Translate the following segment into <TargetLanguage>, without additional explanation. <text>`

再套入 Hy-MT 模型要求的 chat 模板。

这意味着：

- 当前系统不是通用聊天型产品。
- 原生层是把模型明确约束在翻译任务上使用。

## 5. MethodChannel 职责边界

`lib/core/channel/translation_channel.dart` 当前最重要的职责不是翻译，而是模型路径和模型可见性。

真实主链路使用的方法：

- `getBundledModelPath()`
- `listModels()`
- `initEngine()`

兼容残留方法：

- `translate()`
- `downloadModel()`
- `deleteModel()`

注意事项：

- 当前 Flutter 主翻译路径并不依赖 MethodChannel `translate()`。
- Android 的 MethodChannel 实现仍保留了较多早期占位逻辑，例如 `mockTranslate()` 和旧的模型扩展名筛选；它们不是当前主业务链路的一部分。

## 6. STT 架构

`lib/core/stt/stt_service.dart` 是当前本地语音识别方案的核心。

### 6.1 组成部分

- 录音：`record`
- 模型执行：`sherpa_onnx`
- 识别模型：`SenseVoice-Small`
- 端点检测：`Silero VAD`

### 6.2 识别流程

1. 检查麦克风权限和 `pcm16bits` 编码支持。
2. 初始化 sherpa bindings。
3. 把打包资产拷贝到应用支持目录 `sense_voice_small/`。
4. 创建 `OfflineRecognizer` 和 `VoiceActivityDetector`。
5. 通过 `AudioRecorder.startStream()` 获取 16 kHz 单声道 PCM16 数据。
6. 把 PCM16 转成 `Float32List`。
7. 数据送入 Silero VAD。
8. 检测到语音段后送入 SenseVoice 解码。
9. 把解码文本通过回调返回给 UI。

### 6.3 STT 关键实现点

- 当前 STT 支持语言：`zh / en / ja / ko`
- 使用 `_assetVersion` 标记缓存资源版本，避免旧缓存误用。
- 识别结果按行拼接到 `_recognizedText`。
- 通过 `_lastEmittedTranscript` 去掉重复 partial 输出。
- `onStatusChanged` 用于处理自然结束，保证收尾翻译不会丢失。

## 7. TTS 架构

`lib/core/tts/supertonic_tts_controller_io.dart` 封装了本地 TTS 链路。

### 7.1 资源策略

- `assets/onnx/` 存放 ONNX 模型资源。
- `assets/voice_styles/` 存放 voice style 资源。
- 首次准备时，这些资源会被拷贝到应用支持目录 `supertonic_models/`。
- 通过 `.cola-supertonic-bundled-version` 标记当前缓存版本。

### 7.2 发音流程

1. 校验平台支持和语言支持。
2. 准备本地资源并初始化 `SupertonicTTS`。
3. 调用 `synthesize()` 生成语音结果。
4. 将结果导出为 wav bytes。
5. 写入临时文件。
6. 通过 `audioplayers` 的 `DeviceFileSource(..., mimeType: 'audio/wav')` 播放。

### 7.3 Darwin 平台特殊处理

在 iOS / macOS 上，没有直接采用内存字节播放，而是走临时 wav 文件播放。

原因：

- `audioplayers_darwin` 当前不适合依赖直接字节源作为稳定主路径。
- 使用临时文件更稳定，也更容易和平台播放器兼容。

## 8. 页面实现策略

### 8.1 HomePage

- 首帧后尝试 `initEngine()`。
- 语音输入按钮只是把 STT 结果灌进文本框，不直接触发翻译。
- 发音按钮受 `ttsState.isBusy` 控制。
- 错误通过 `SnackBar` 和结果区下方提示展示。

### 8.2 ConversationPage

- 独立维护 `_liveTranscript` 和 `_liveTranslation`。
- 使用 `Timer` 做去抖调度。
- `_queuedTranscript` 与 `_lastTranslatedTranscript` 用于处理识别结果快速变化时的并发顺序问题。
- `_translating` 标记用于保证同一时刻只处理一个翻译 drain 过程。

### 8.3 SettingsPage

- 进入页面自动刷新。
- 通过 `translationProvider` 和 `translationChannelProvider` 组合得到状态与模型列表。

## 9. 平台原生桥接

### 9.1 Android

- `MainActivity.kt` 注册 `cola.translate/engine`。
- `getBundledModelPath()` 会把 APK 中的 GGUF 拷贝到 `filesDir/models`。
- 原因是原生引擎依赖真实文件路径做 `mmap()`。

### 9.2 iOS

- `SceneDelegate.swift` 而不是 `AppDelegate.swift` 负责注册通道。
- 模型路径通过 `FlutterDartProject.lookupKey(forAsset:)` 与 bundle 路径组合解析。

### 9.3 macOS

- `EngineChannel.swift` 是 iOS `SceneDelegate` 的桌面对应物。
- 因为 macOS 的 Flutter 资源布局不同，增加了 fallback 路径拼接策略和容器日志输出。

## 10. 兼容与容错

- `TranslationController.translate()` 在异常时会回退到 `"[离线降级] <text>"`。
- STT 在音频流异常结束时会主动 flush VAD 并发出最终结果。
- TTS 初始化失败会把错误写入状态，避免 UI 静默失败。
- iOS / macOS 的 FFI 链路依赖链接阶段把静态符号保留下来，否则运行时 `dlsym` 会失败。

## 11. 模型替换注意事项

如果未来要替换翻译模型，当前至少需要同步检查以下位置：

- Flutter 资产清单
- Android `MainActivity.modelPrefix`
- iOS `SceneDelegate.modelPrefix`
- macOS `EngineChannel.modelPrefix`
- 原生 `native/cola_translate.cpp` 中针对模型的 prompt 模板和行为假设

如果只替换文件、不改这些协同点，最容易出现的问题是：

- 模型路径解析失败
- 能加载模型但 prompt 与模板不匹配
- 设置页模型检测与真实引擎模型不一致