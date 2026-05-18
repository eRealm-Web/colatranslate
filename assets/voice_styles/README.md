# Voice Style Assets

This directory stores the TTS voice-style JSON files used by the Supertone runtime. They are excluded from git and restored with the root `Makefile`.

Expected files:

- `F1.json`
- `F2.json`
- `F3.json`
- `F4.json`
- `F5.json`
- `M1.json`
- `M2.json`
- `M3.json`
- `M4.json`
- `M5.json`

Bootstrap command:

- `make assets-tts`

Source:

- `https://huggingface.co/Supertone/supertonic-2/tree/main/voice_styles`
