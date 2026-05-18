# Supertone ONNX Assets

This directory stores the ONNX runtime files used by the TTS pipeline. They are excluded from git and restored with the root `Makefile`.

Expected files:

- `duration_predictor.onnx`
- `text_encoder.onnx`
- `tts.json`
- `unicode_indexer.json`
- `vector_estimator.onnx`
- `vocoder.onnx`

Bootstrap command:

- `make assets-tts`

Source:

- `https://huggingface.co/Supertone/supertonic-2/tree/main/onnx`
