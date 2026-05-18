# 系统总览

## 1. 系统目标

可乐翻译的系统设计目标很明确：

- 以本地翻译为核心，不依赖外部翻译服务。
- 用最少的页面承载文本翻译、语音翻译和设备状态。
- 通过 Flutter 统一 UI，通过 FFI、ONNX Runtime 和原生平台代码接入端侧能力。
- 在保证产品可用的前提下，把平台差异压缩在 MethodChannel、FFI 和平台构建配置层。

## 2. 总体结构

```text
┌──────────────────────────────────────────────────────────────┐
│ Flutter UI                                                   │
│  - HomePage              文本翻译                            │
│  - ConversationPage      语音翻译                            │
│  - SettingsPage          设备状态                            │
└──────────────────────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────────────────┐
│ 应用状态与业务控制层                                          │
│  - TranslationController / TranslationState                  │
│  - SttService                                                │
│  - SupertonicTtsController                                   │
└──────────────────────────────────────────────────────────────┘
          │                         │                        │
          ▼                         ▼                        ▼
┌─────────────────────┐   ┌──────────────────────┐   ┌──────────────────────┐
│ dart:ffi            │   │ MethodChannel        │   │ supertonic_flutter   │
│ cola_ffi.dart       │   │ translation_channel  │   │ ONNX Runtime         │
└─────────────────────┘   └──────────────────────┘   └──────────────────────┘
          │                         │                        │
          ▼                         ▼                        ▼
┌─────────────────────┐   ┌──────────────────────┐   ┌──────────────────────┐
│ native/cola_*       │   │ Android / iOS / macOS│   │ Supertonic 3 assets  │
│ llama.cpp wrapper   │   │ model path resolve   │   │ + temp wav playback   │
└─────────────────────┘   └──────────────────────┘   └──────────────────────┘
          │
          ▼
┌──────────────────────────────────────────────────────────────┐
│ Hy-MT1.5-1.8B-1.25bit.gguf + llama.cpp PR #22836 STQ1_0      │
└──────────────────────────────────────────────────────────────┘
```

## 3. 仓库结构

```text
lib/
├── main.dart
├── core/
│   ├── channel/translation_channel.dart
│   ├── models/translation_state.dart
│   ├── native/cola_ffi.dart
│   ├── stt/stt_service.dart
│   └── tts/
└── features/
    ├── home/home_page.dart
    ├── conversation/conversation_page.dart
    └── settings/settings_page.dart

native/
├── cola_translate.h
├── cola_translate.cpp
└── CMakeLists.txt

android/
ios/
macos/
assets/
└── models / onnx / voice_styles
```

## 4. 主要模块职责

### 4.1 UI 层

- `HomePage`：文本输入、语言切换、翻译触发、复制、TTS 发音。
- `ConversationPage`：实时语音识别、实时译文展示、语言方向控制。
- `SettingsPage`：引擎状态、模型列表、隐私说明。

### 4.2 状态控制层

- `TranslationController`：统一管理源语言、目标语言、输入、输出、引擎状态、内存历史，并负责触发翻译。
- `SttService`：封装本地 STT 会话生命周期，包括录音、VAD、识别、结果回调、状态回调。
- `SupertonicTtsController`：封装 TTS 资源准备、引擎初始化、语音合成、音频播放。

### 4.3 计算与平台桥接层

- `cola_ffi.dart`：把 Dart 侧的翻译请求转成原生 FFI 调用。
- `translation_channel.dart`：负责模型路径解析、模型列表查询以及少量兼容接口。
- iOS / macOS / Android 原生代码：处理模型资产路径、应用支持目录与平台差异。

## 5. 核心业务流程

### 5.1 应用启动与引擎预热

1. `main.dart` 启动 `ProviderScope` 和三页导航壳。
2. `HomePage` 与 `ConversationPage` 在首帧后会尝试触发 `initEngine()`。
3. `TranslationController` 通过 `TranslationChannel.getBundledModelPath()` 获取模型路径。
4. 引擎初始化放到后台 isolate 中执行，避免阻塞 UI。
5. 成功后全局状态中的 `engineReady` 置为 `true`。

### 5.2 文本翻译流程

```text
用户输入文本
  -> TranslationController.setInput
  -> 点击开始离线翻译
  -> ensureEngineReady
  -> translateOffMainIsolate
  -> ColaFfi.instance.translate
  -> native cola_translate
  -> 译文返回
  -> 更新 output 与 history
```

特征：

- 文本翻译是全局状态主链路。
- 译文写回 `TranslationState.output`。
- 成功翻译会写入内存历史。

### 5.3 语音翻译流程

```text
点击开始语音识别翻译
  -> SttService.startListening
  -> AudioRecorder.startStream
  -> PCM16 流进入 Silero VAD
  -> SenseVoice-Small 解码
  -> 页面收到 partial / final transcript
  -> ConversationPage 本地去抖调度 previewTranslate
  -> TranslationController.previewTranslate
  -> FFI 翻译
  -> 页面更新 liveTranslation
```

特征：

- 语音翻译页不直接依赖 `TranslationState.output` 作为实时展示源。
- 实时转写和实时译文都放在页面局部状态中。
- 这样可以避免 partial 结果持续污染全局输出和全局历史。

### 5.4 TTS 发音流程

```text
用户点击发音
  -> SupertonicTtsController.speak
  -> 检查语言与平台支持
  -> 准备 bunded Supertonic 3 资源
  -> SupertonicTTS.synthesize
  -> 生成 wav
  -> audioplayers 播放临时文件
```

特征：

- 当前只接入文本翻译页结果区。
- 语音翻译页不接入自动播报，优先保证实时链路简洁稳定。

### 5.5 设备状态流程

1. `SettingsPage` 首次进入自动刷新。
2. 调用 `TranslationController.initEngine()` 重新检测引擎状态。
3. 再通过 `TranslationChannel.listModels()` 读取模型列表。
4. 页面展示引擎就绪、错误信息和模型名。

## 6. 状态边界设计

### 6.1 全局状态

由 `TranslationState` 持有：

- `sourceLang`
- `targetLang`
- `input`
- `output`
- `isLoading`
- `engineReady`
- `engineError`
- `history`

这些状态代表应用级可复用的翻译上下文。

### 6.2 页面局部状态

`ConversationPage` 单独持有：

- `_liveTranscript`
- `_liveTranslation`
- `_translationError`
- `_queuedTranscript`
- `_lastTranslatedTranscript`
- `_listening / _starting / _translating`

原因：实时语音识别结果变化非常频繁，不适合全部提升到全局状态。

## 7. 并发与性能策略

- 翻译调用通过 `Isolate.run` 转移到后台 isolate。
- 原生翻译引擎内部使用单例和互斥锁，避免并发访问模型上下文。
- STT 采用音频流 + VAD 分段处理，减少无意义解码。
- 语音翻译页通过 `420ms` 去抖，避免 partial 结果触发过多翻译调用。
- TTS 和 STT 的模型资产都会先落到应用支持目录，后续复用缓存。

## 8. 当前系统边界

- 当前历史记录只存在于内存，不写磁盘。
- 当前设置页只展示状态，不承担资源管理中心职责。
- 当前 Web / Windows 未接入完整的 TTS 链路。
- 当前语音翻译页不做页面内 TTS、对话记忆、自动发言人切换。
