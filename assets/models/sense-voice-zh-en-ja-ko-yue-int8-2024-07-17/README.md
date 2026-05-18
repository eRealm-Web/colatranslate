# SenseVoice Assets

This folder is kept in git only as an empty asset mount point. The actual runtime files are downloaded on demand.

Expected files:

- `model.int8.onnx`
- `tokens.txt`
- `silero_vad.onnx`

Bootstrap command:

- `make assets-stt`

Source mapping:

- `model.int8.onnx` and `tokens.txt` are extracted from `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2`
- `silero_vad.onnx` is downloaded separately from `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx`
