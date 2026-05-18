# Models Assets

This directory keeps only the tracked folder structure for Flutter assets. Large runtime model files are intentionally excluded from git.

Expected runtime files:

- `Hy-MT1.5-1.8B-1.25bit.gguf`
- `sense-voice-zh-en-ja-ko-yue-int8-2024-07-17/model.int8.onnx`
- `sense-voice-zh-en-ja-ko-yue-int8-2024-07-17/tokens.txt`
- `sense-voice-zh-en-ja-ko-yue-int8-2024-07-17/silero_vad.onnx`

Bootstrap commands:

- `make assets-translation`
- `make assets-stt`
- `make assets`
- `HF_TOKEN=<token> make assets`

Confirmed upstream sources:

- Hy-MT upstream repo: `https://huggingface.co/tencent/HY-MT1.5-1.8B`
- Verified GGUF mirror used by default `Makefile`: `https://huggingface.co/AngelSlim/Hy-MT1.5-1.8B-1.25bit-GGUF`
- SenseVoice archive: `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2`
- Silero VAD: `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx`

You can still override the GGUF source if the default mirror changes:

- `make HY_MT_GGUF_URL=<direct-gguf-url> assets-translation`
