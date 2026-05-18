<!--
 * @Author: Beck Qin(enginebeck@gmail.com)
 * @Date: 2026-05-14 16:11:43
 * @LastEditors: Beck Qin(enginebeck@gmail.com)
 * @LastEditTime: 2026-05-18 11:31:05
 * @Description: desc
-->

# 可乐翻译

一个以设备侧离线翻译为核心的 Flutter 应用。当前版本聚焦三条主线能力：

- 文本翻译：语言切换、文本输入、语音填充、离线翻译、复制、TTS 发音
- 语音翻译：单按钮开始 / 停止、本地语音识别、实时原文、实时译文
- 设备状态：引擎状态、模型可见性、隐私说明

仓库默认不再提交大模型和 TTS 资源文件，新的开发机只需要按下面的 README 初始化一次，就可以直接运行。

## 适用平台

- macOS：完整支持开发、调试和本地运行
- iOS：支持模拟器、真机和 Xcode Release 运行
- Android：支持 arm64 真机运行

当前 Web / Windows / Linux 不是完整交付重点，尤其 TTS 和原生翻译链路没有做到与 Apple / Android 同等级别。

## 文档入口

- 文档总览：[docs/README.md](docs/README.md)
- 需求说明：[docs/requirements.md](docs/requirements.md)
- 系统总览：[docs/system-overview.md](docs/system-overview.md)
- 技术架构：[docs/technical-architecture.md](docs/technical-architecture.md)
- 平台与构建说明：[docs/platform-build-notes.md](docs/platform-build-notes.md)
- AI 共创复盘：[docs/ai-build-journey.md](docs/ai-build-journey.md)

## 当前实现摘要

- 翻译引擎：`llama.cpp` + `Hy-MT1.5-1.8B-1.25bit.gguf`
- 翻译调用：Flutter 通过 `dart:ffi` 直连 `cola_*` C ABI
- STT：`record + sherpa_onnx + SenseVoice-Small + Silero VAD`
- TTS：`supertonic_flutter + Supertonic 3 + ONNX Runtime`
- 状态管理：Riverpod
- 页面结构：翻译 / 语音 / 设备

## 环境要求

### 1. Flutter

- 使用 Flutter stable
- Flutter 自带的 Dart 版本需要满足 `pubspec.yaml` 中的 `sdk: ^3.11.3`
- 建议先跑一次 `flutter doctor`

### 2. 平台工具链

- macOS / iOS：Xcode、CocoaPods
- Android：Android Studio 或独立 Android SDK

如果你只打算在 macOS 桌面先跑通，最少准备 Flutter + Xcode Command Line Tools 即可。

## 首次初始化

从零开始推荐按这个顺序执行：

```bash
flutter doctor
flutter pub get
make assets
flutter analyze
```

说明：

- `make assets` 会下载翻译 GGUF、SenseVoice STT 资源、Supertonic TTS 资源
- 如果 Hugging Face 触发未登录限流，可以改用 `HF_TOKEN=<token> make assets`
- 如果后续 GGUF 镜像有变动，也可以手工覆盖：`make HY_MT_GGUF_URL=<direct-url> assets-translation`

## 运行方式

### macOS

```bash
flutter run -d macos
```

这是当前最省事的本地验证路径，适合先确认资源下载、引擎初始化、STT/TTS 基本链路都正常。

### iOS 模拟器

先列出可用模拟器：

```bash
xcrun simctl list devices
```

然后运行：

```bash
flutter run -d <simulator-id> --debug
```

### iPhone 真机

命令行方式：

```bash
flutter run -d <device-id> --release
```

Xcode 方式：

1. 打开 `ios/Runner.xcworkspace`
2. 选择 `Runner` scheme 和目标设备
3. 直接点击 Run

当前共享 `Runner` scheme 已经配置为 Release 启动，并且不附着 LLDB，目的是避免以前“Xcode 控制台断连后 app 卡死”的问题。

注意：

- 真机无线调试需要设备开启 Developer Mode
- 如果设备未信任当前 Mac，`flutter run` 会直接失败

### Android 真机

先确认设备：

```bash
flutter devices
```

然后运行：

```bash
flutter run -d <android-device-id>
```

当前 Android 重点支持 `arm64-v8a`。

## 资源管理

大文件资产都在 `assets/` 目录下，但二进制本体已经从 git 中移除，只保留目录结构和说明文档。

常用命令：

```bash
make assets
make assets-translation
make assets-stt
make assets-tts
make clean-assets
```

对应来源：

- 翻译模型：Hy-MT1.5-1.8B 1.25bit GGUF 镜像
- STT：sherpa-onnx SenseVoice-Small + Silero VAD
- TTS：Supertone ONNX + voice styles

更详细的目录说明见：

- [assets/README.md](assets/README.md)
- [assets/models/README.md](assets/models/README.md)
- [assets/onnx/README.md](assets/onnx/README.md)
- [assets/voice_styles/README.md](assets/voice_styles/README.md)

## 常用检查

```bash
flutter analyze
flutter test
```

如果你想单独验证翻译模型是否可被原生链路读取，可以看 [docs/platform-build-notes.md](docs/platform-build-notes.md) 里的 native smoke test。

## 常见问题

### 1. `make assets` 很慢或者被限流

- 优先重试一次
- 如果是 Hugging Face 限流，使用 `HF_TOKEN=<token> make assets`

### 2. iOS 真机无法启动

- 检查设备是否开启 Developer Mode
- 检查设备是否信任当前 Mac
- 无线连接不稳定时优先改为数据线

### 3. iOS Release 报 `dlsym(..., cola_init): symbol not found`

当前仓库已经通过 `-force_load` 和 `ColaSymbols.m` 处理了这个问题。如果再次出现，优先检查本地工程文件是否落后于仓库，具体背景见 [docs/platform-build-notes.md](docs/platform-build-notes.md)。

## 仓库结构

- `lib/`：Flutter 业务代码
- `native/`：本地翻译引擎封装和 CMake 构建
- `ios/`、`android/`、`macos/`：平台工程
- `assets/`：运行时模型目录和说明文件
- `docs/`：完整产品与技术文档

## 当前范围边界

- 翻译、语音识别、语音合成都在设备本地执行
- 历史记录当前只保存在内存中
- 语音翻译页不做自动连续对话、双区长按对讲或页面内自动播报
- 设备状态页只做检测，不做模型管理中心
- Web / Windows 不是当前完整交付重点
