# 平台集成与构建说明

## 1. 总体原则

可乐翻译的跨平台实现不是“Flutter 一套代码直接跑完”，而是 Flutter UI + 平台专项打包和符号管理共同完成。

当前平台重点是：

- Android
- iOS
- macOS

其中 Web / Windows / Linux 不是当前完整交付重点，尤其 TTS 和原生翻译集成没有做到与移动端同等级别。

## 2. 资产打包策略

### 2.1 翻译模型

- 文件：`assets/models/Hy-MT1.5-1.8B-1.25bit.gguf`
- 用途：本地翻译模型
- 特点：体积大，需要真实文件路径，适合 `mmap`

### 2.2 STT 资源

- 目录：`assets/models/sense-voice-zh-en-ja-ko-yue-int8-2024-07-17/`
- 内容：`model.int8.onnx`、`tokens.txt`、`silero_vad.onnx`
- 用途：SenseVoice-Small + Silero VAD

### 2.3 TTS 资源

- 目录：`assets/onnx/`
- 目录：`assets/voice_styles/`
- 用途：Supertonic 3 的 ONNX 模型和 voice style 文件

## 3. Android

### 3.1 当前配置

- 最低版本：`minSdk = 24`
- 目标 ABI：`arm64-v8a`
- 原生库：`android/app/src/main/jniLibs/arm64-v8a/libcola_translate.so`
- GGUF 资产：通过 `noCompress += listOf("gguf")` 避免 APK 内压缩

### 3.2 模型路径策略

Android 端不会直接把 GGUF 从 Flutter 资产虚拟路径交给引擎，而是在首次需要时把它拷贝到：

- `filesDir/models/<model>.gguf`

原因：

- llama.cpp 侧需要真实文件路径
- 同时希望后续使用 `mmap()` 而不是重复内存拷贝

### 3.3 原生构建注意事项

当前原生构建要点：

- `GGML_CPU_ARM_ARCH=armv8.2-a+dotprod`
- 不要提升到 `armv8.4-a`，否则旧设备可能 `SIGILL`
- Android 15 及更新设备必须保证 `.so` 满足 16 KB 页大小对齐要求
- 链接时使用 `-Wl,-z,max-page-size=16384`

### 3.4 当前 Android 残留说明

Android `MainActivity.kt` 中仍存在部分早期占位逻辑：

- `translate()` 对应 `mockTranslate()`
- `downloadModel()` / `deleteModel()` 仍保留
- `listModels()` 仍按旧的扩展名逻辑筛选

它们不是当前 Flutter 主翻译链路的关键路径，当前真实翻译主链路走的是 FFI。

## 4. iOS

### 4.1 当前配置

- 最低版本：`iOS 16.0`
- Podfile：`use_frameworks! :linkage => :static`
- 翻译引擎：`ios/Frameworks/ColaTranslate.xcframework`
- 链接配置：`ios/Flutter/ColaTranslate.xcconfig`

### 4.2 通道注册

`SceneDelegate.swift` 负责注册 MethodChannel，而不是 `AppDelegate.swift`。

原因：

- iOS 13 之后的 scene lifecycle 下，错误地把注册逻辑放在 `AppDelegate` 很容易导致通道没有绑定到实际 FlutterViewController。

### 4.3 模型路径解析

`SceneDelegate.swift` 当前做了多层 fallback：

1. `Bundle.main.bundlePath + lookupKey`
2. `Bundle.main.path(forResource:)`
3. `Bundle.main.path(..., inDirectory:)`
4. Application Support 目录中的副本

原因是：

- Flutter 在不同构建模式下的资源布局不完全一致
- debug / release / simulator / device 对 bundle 路径表现不同

### 4.4 静态库与 FFI 符号保活

iOS 当前使用的是静态 XCFramework 切片，而不是动态库。

这带来两个关键要求：

- 链接时需要 `-force_load`
- Release 下需要保证 `cola_*` FFI 入口不会被 dead-strip

当前处理方式：

- `ios/Flutter/ColaTranslate.xcconfig` 中使用 `-force_load $(COLA_SLICE_DIR)/libcola_combined.a`
- `ios/Runner/ColaSymbols.m` 中显式保活 `cola_init`、`cola_is_ready`、`cola_translate`、`cola_free_string`、`cola_shutdown`

如果没有这层保活，Dart 侧 `DynamicLibrary.process()` 会在 release 运行时触发：

- `dlsym(..., cola_init): symbol not found`

### 4.5 Xcode 运行模式

当前共享 `Runner.xcscheme` 已将 `LaunchAction` 切到：

- `buildConfiguration = Release`
- 不附着 LLDB 调试器

这样做是为了避免之前“从 Xcode 直接运行，一旦与控制台断连 app 就卡死”的问题复现。

## 5. macOS

### 5.1 当前配置

- 最低版本：`macOS 14.0`
- Podfile：`use_frameworks! :linkage => :static`
- 需要在 pods project 和 project config 中打开 `ALLOW_STATIC_FRAMEWORK_TRANSITIVE_DEPENDENCIES = YES`

### 5.2 通道注册与模型路径

- 通道注册在 `macos/Runner/EngineChannel.swift`
- 资源解析使用 `lookupKey + Bundle.main.bundlePath`，并补了 Flutter 桌面固定布局 fallback

### 5.3 FFI 符号策略

macOS 除了 `-force_load` 外，还在 `macos/Runner/Configs/ColaTranslate.xcconfig` 中对 `cola_*` 使用 `-Wl,-u,_symbol`。

原因：

- macOS 链接器即使 force-load 了静态库，也可能继续把看似未引用的外部符号 strip 掉
- Dart FFI 的 `dlsym` 是运行时解析，不会在链接期自然形成静态引用

### 5.4 架构限制

当前 macOS 原生归档按 Apple Silicon 主路径配置，因此配置中将：

- `ARCHS = arm64`
- `VALID_ARCHS = arm64`

## 6. Native CMake 构建

`native/CMakeLists.txt` 当前采用最小嵌入式配置：

- 关闭 tests / examples / tools / server / curl / common
- 关闭 Metal / CUDA / Vulkan / BLAS / OpenMP
- 默认构建静态 `cola_translate`
- Android 场景可通过 `COLA_SHARED=ON` 构建共享库

设计目标是：

- 让移动端和桌面端只携带翻译所需的最小依赖集合
- 避免把 llama.cpp 示例程序和无关后端一起带进产物

## 7. 常用构建命令

### 7.1 Flutter

```bash
flutter pub get
flutter analyze
flutter run -d <device-id>
flutter build ios --release --no-codesign
```

### 7.2 macOS 原生 smoke test

```bash
cd native
cmake -S . -B build_mac -G Ninja -DCMAKE_BUILD_TYPE=Release -DGGML_CCACHE=OFF -DCOLA_BUILD_TEST=ON
cmake --build build_mac -j 8
./build_mac/cola_test ../assets/models/Hy-MT1.5-1.8B-1.25bit.gguf en zh "Hello, how are you today?"
```

### 7.3 Android arm64 原生库

```bash
cd native
rm -rf build_android_arm64
cmake -S . -B build_android_arm64 -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24 \
  -DCOLA_SHARED=ON -DGGML_NATIVE=OFF \
  -DGGML_CPU_ARM_ARCH=armv8.2-a+dotprod \
  -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384"
cmake --build build_android_arm64 --target cola_translate -j 8
```

## 8. 已确认的重要坑

### 8.1 Android 15 新设备加载失败

根因：共享库页大小对齐不满足新系统要求。

处理：

- 链接时加 `-Wl,-z,max-page-size=16384`

### 8.2 旧 arm64 设备 SIGILL

根因：CPU baseline 设得过高。

处理：

- 降到 `armv8.2-a+dotprod`

### 8.3 iOS 通道未注册

根因：错误放在 `AppDelegate`。

处理：

- 改到 `SceneDelegate`。

### 8.4 iOS Release FFI 符号找不到

根因：静态库入口在 Release dead-strip 中被裁掉。

处理：

- `-force_load`
- `ColaSymbols.m` 保活 FFI 入口

### 8.5 macOS 静态 Framework 依赖问题

根因：Pods 默认不接受静态 framework 传递依赖。

处理：

- `use_frameworks! :linkage => :static`
- `ALLOW_STATIC_FRAMEWORK_TRANSITIVE_DEPENDENCIES = YES`

## 9. 发布前检查建议

1. 确认 GGUF、SenseVoice、Supertonic 资源都在 Flutter assets 中声明。
2. 确认 Android 的 `.so` 与 Flutter 资产版本一致。
3. 确认 iOS release 产物里能看到 `cola_*` 全局符号。
4. 确认 macOS 产物使用 arm64 目标并保留 `cola_*` 符号。
5. 真机验证首启引擎初始化、STT、TTS 和语音翻译收尾逻辑。
