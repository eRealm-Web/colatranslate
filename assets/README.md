# Assets

Large runtime assets are intentionally excluded from git history. This directory keeps only the tracked folder layout and README files needed for onboarding.

Use the root `Makefile` to restore the binaries after checkout:

- `make assets`
- `make assets-stt`
- `make assets-tts`
- `make assets-translation`
- `HF_TOKEN=<token> make assets`

The default bootstrap downloads:

- Hy-MT GGUF from the verified mirror used by this repo's current setup
- SenseVoice and Silero VAD from sherpa-onnx GitHub releases
- Supertone ONNX and voice-style assets from Hugging Face

If you need to override the translation model source, pass a custom URL:

- `make HY_MT_GGUF_URL=<direct-gguf-url> assets-translation`

Folder guide:

- `models/`: translation GGUF and SenseVoice STT assets
- `onnx/`: Supertone ONNX runtime files
- `voice_styles/`: Supertone voice-style JSON files
