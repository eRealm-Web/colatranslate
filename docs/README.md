# 可乐翻译文档总览

这套文档统一收敛了当前仓库里与产品、业务、技术实现、平台构建有关的最新信息，目标是替代根目录下零散且已经过时的说明。

## 文档索引

### 1. [requirements.md](requirements.md)

产品定位、功能范围、页面需求、交互要求、验收标准、非目标、平台约束和后续候选方向。

### 2. [system-overview.md](system-overview.md)

系统全景、模块关系、仓库结构、核心业务流程、状态边界、运行时数据流。

### 3. [technical-architecture.md](technical-architecture.md)

Flutter 层、Riverpod 状态层、FFI 翻译引擎、STT、TTS、MethodChannel、原生推理封装、并发与容错设计。

### 4. [platform-build-notes.md](platform-build-notes.md)

Android / iOS / macOS 的平台集成差异、资产打包策略、部署目标、构建命令、已踩坑与发布注意事项。

### 5. [ai-build-journey.md](ai-build-journey.md)

一篇完整复盘，记录这个项目是如何在用户持续抬高标准、AI 持续读代码与验证的过程中，一步一步从半成品变成现在这个离线翻译工程的。

## 当前系统快照

- 产品目标：提供以设备侧离线翻译为核心的轻量翻译应用。
- 端侧能力：翻译、语音识别、语音合成都在本地设备执行，不依赖云端翻译或云端语音服务。
- 页面结构：翻译页、语音翻译页、设备状态页。
- 翻译引擎：Flutter 通过 `dart:ffi` 调用本地 `cola_*` C ABI，底层是 `llama.cpp` + `Hy-MT1.5-1.8B-1.25bit.gguf`。
- STT：`record + sherpa_onnx + SenseVoice-Small + Silero VAD`。
- TTS：`supertonic_flutter + Supertonic 3 + ONNX Runtime`。
- 状态管理：Riverpod `StateNotifier` 为主，语音翻译页对实时转写与实时译文保留页面局部状态。

## 建议阅读顺序

1. 先读 [requirements.md](requirements.md)，了解产品范围和边界。
2. 再读 [system-overview.md](system-overview.md)，建立全局结构认知。
3. 实施开发或排查问题时，重点看 [technical-architecture.md](technical-architecture.md) 与 [platform-build-notes.md](platform-build-notes.md)。

## 维护原则

- 文档只记录仓库里真实存在的实现，不为历史方案保留描述。
- 如果代码与文档不一致，以代码为准，并应尽快回写文档。
- 平台专项约束必须写进文档，而不是只留在提交记录或口头背景里。
