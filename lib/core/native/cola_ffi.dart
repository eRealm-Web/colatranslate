// Dart FFI bindings for the native ColaTranslate engine (libcola_translate /
// XCFramework on iOS, libcola_translate.so on Android).
//
// The native C ABI is defined in `native/cola_translate.h`:
//
//   int32_t cola_init(const char* model_path);
//   int32_t cola_is_ready(void);
//   char*   cola_translate(const char* text, const char* src_lang, const char* tgt_lang);
//   void    cola_free_string(char* s);
//   void    cola_shutdown(void);

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

typedef _CColaInit = Int32 Function(Pointer<Utf8>);
typedef _DartColaInit = int Function(Pointer<Utf8>);

typedef _CColaIsReady = Int32 Function();
typedef _DartColaIsReady = int Function();

typedef _CColaTranslate =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _DartColaTranslate =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);

typedef _CColaFreeString = Void Function(Pointer<Utf8>);
typedef _DartColaFreeString = void Function(Pointer<Utf8>);

typedef _CColaShutdown = Void Function();
typedef _DartColaShutdown = void Function();

class ColaFfi {
  ColaFfi._(DynamicLibrary lib)
    : _init = lib.lookupFunction<_CColaInit, _DartColaInit>('cola_init'),
      _isReady = lib.lookupFunction<_CColaIsReady, _DartColaIsReady>(
        'cola_is_ready',
      ),
      _translate = lib.lookupFunction<_CColaTranslate, _DartColaTranslate>(
        'cola_translate',
      ),
      _freeString = lib.lookupFunction<_CColaFreeString, _DartColaFreeString>(
        'cola_free_string',
      ),
      _shutdown = lib.lookupFunction<_CColaShutdown, _DartColaShutdown>(
        'cola_shutdown',
      );

  static ColaFfi? _instance;

  static ColaFfi get instance {
    _instance ??= ColaFfi._(_openLibrary());
    return _instance!;
  }

  final _DartColaInit _init;
  final _DartColaIsReady _isReady;
  final _DartColaTranslate _translate;
  final _DartColaFreeString _freeString;
  // ignore: unused_field
  final _DartColaShutdown _shutdown;

  static DynamicLibrary _openLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libcola_translate.so');
    }
    if (Platform.isIOS || Platform.isMacOS) {
      // Symbols are statically linked into the host executable on iOS via the
      // XCFramework + xcconfig integration.
      return DynamicLibrary.process();
    }
    if (Platform.isLinux) {
      return DynamicLibrary.open('libcola_translate.so');
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open('cola_translate.dll');
    }
    throw UnsupportedError('Unsupported platform for ColaFfi');
  }

  bool initEngine(String modelPath) {
    final p = modelPath.toNativeUtf8();
    try {
      return _init(p) == 0;
    } finally {
      malloc.free(p);
    }
  }

  bool get isReady => _isReady() != 0;

  String translate({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) {
    final t = text.toNativeUtf8();
    final s = sourceLang.toNativeUtf8();
    final g = targetLang.toNativeUtf8();
    try {
      final out = _translate(t, s, g);
      if (out == nullptr) {
        return '';
      }
      final result = out.toDartString();
      _freeString(out);
      return result;
    } finally {
      malloc.free(t);
      malloc.free(s);
      malloc.free(g);
    }
  }
}

/// Off-isolate translation helper. The native code is single-threaded and
/// CPU-bound; running it on the UI isolate would freeze the app. We hop to a
/// background isolate (one per call is fine — model is in shared mmap'd memory
/// so loading is cheap after the first time inside that isolate).
class TranslationRequest {
  const TranslationRequest({
    required this.modelPath,
    required this.text,
    required this.sourceLang,
    required this.targetLang,
  });

  final String modelPath;
  final String text;
  final String sourceLang;
  final String targetLang;
}

String runTranslationInIsolate(TranslationRequest req) {
  final ffi = ColaFfi.instance;
  if (!ffi.isReady) {
    if (!ffi.initEngine(req.modelPath)) {
      return '';
    }
  }
  return ffi.translate(
    text: req.text,
    sourceLang: req.sourceLang,
    targetLang: req.targetLang,
  );
}

Future<String> translateOffMainIsolate(TranslationRequest req) {
  return Isolate.run(() => runTranslationInIsolate(req));
}
