MODEL_DIR = assets/models
TRANSLATION_MODEL = ${MODEL_DIR}/Hy-MT1.5-1.8B-1.25bit.gguf
SENSEVOICE_DIR = ${MODEL_DIR}/sense-voice-zh-en-ja-ko-yue-int8-2024-07-17
ONNX_DIR = assets/onnx
VOICE_STYLE_DIR = assets/voice_styles
CACHE_DIR = .cache/assets

HY_MT_SOURCE_REPO = https://huggingface.co/tencent/HY-MT1.5-1.8B
HY_MT_GGUF_URL ?= https://huggingface.co/AngelSlim/Hy-MT1.5-1.8B-1.25bit-GGUF/resolve/main/Hy-MT1.5-1.8B-1.25bit.gguf?download=true
SENSEVOICE_ARCHIVE_URL = https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2
SILERO_VAD_URL = https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx
SUPERTONIC_BASE_URL = https://huggingface.co/Supertone/supertonic-2/resolve/main
SUPERTONIC_ONNX_FILES = duration_predictor.onnx text_encoder.onnx tts.json unicode_indexer.json vector_estimator.onnx vocoder.onnx
SUPERTONIC_VOICE_STYLE_FILES = F1.json F2.json F3.json F4.json F5.json M1.json M2.json M3.json M4.json M5.json
CURL = curl -L --fail --retry 3
HF_CURL = ${CURL}

ifdef HF_TOKEN
HF_CURL = ${CURL} -H "Authorization: Bearer ${HF_TOKEN}"
endif

.PHONY: help assets assets-translation assets-stt assets-tts clean-assets clean-assets-cache

help:
	@printf '%s\n' \
		'make assets                Download all externalized assets.' \
		'make assets-translation    Download Hy-MT GGUF (override with HY_MT_GGUF_URL=...).' \
		'make assets-stt            Download SenseVoice and Silero VAD.' \
		'make assets-tts            Download Supertone ONNX files and voice styles.' \
		'make clean-assets          Remove downloaded asset files.' \
		'' \
		'Example:' \
		'  make assets' \
		'  HF_TOKEN=<token> make assets' \
		'  make HY_MT_GGUF_URL=https://your-host/Hy-MT1.5-1.8B-1.25bit.gguf assets'

assets: assets-translation assets-stt assets-tts

assets-translation:
	@mkdir -p "${MODEL_DIR}"
	@if [ -f "${TRANSLATION_MODEL}" ]; then \
		echo "${TRANSLATION_MODEL} already exists"; \
	elif [ -n "${HY_MT_GGUF_URL}" ]; then \
		tmp_file="${TRANSLATION_MODEL}.part"; \
		rm -f "$$tmp_file"; \
		${HF_CURL} --output "$$tmp_file" "${HY_MT_GGUF_URL}"; \
		mv "$$tmp_file" "${TRANSLATION_MODEL}"; \
	else \
		echo "HY_MT_GGUF_URL is not set."; \
		echo "Confirmed upstream source repo: ${HY_MT_SOURCE_REPO}"; \
		echo "Provide a direct GGUF mirror URL, for example:"; \
		echo "  make HY_MT_GGUF_URL=https://your-host/Hy-MT1.5-1.8B-1.25bit.gguf assets-translation"; \
		exit 1; \
	fi

assets-stt:
	@mkdir -p "${SENSEVOICE_DIR}" "${CACHE_DIR}"
	@set -e; \
	archive="${CACHE_DIR}/sense-voice.tar.bz2"; \
	extract_dir="${CACHE_DIR}/sensevoice-extract"; \
	if [ ! -f "${SENSEVOICE_DIR}/model.int8.onnx" ] || [ ! -f "${SENSEVOICE_DIR}/tokens.txt" ]; then \
		tmp_archive="$$archive.part"; \
		rm -f "$$tmp_archive"; \
		${CURL} --output "$$tmp_archive" "${SENSEVOICE_ARCHIVE_URL}"; \
		mv "$$tmp_archive" "$$archive"; \
		rm -rf "$$extract_dir"; \
		mkdir -p "$$extract_dir"; \
		tar -xjf "$$archive" -C "$$extract_dir"; \
		src_dir=$$(find "$$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1); \
		model_file=$$(find "$$src_dir" -type f -name 'model*.onnx' | head -n 1); \
		if [ -z "$$model_file" ]; then \
			echo "Unable to locate a SenseVoice ONNX model in $$archive"; \
			exit 1; \
		fi; \
		cp "$$model_file" "${SENSEVOICE_DIR}/model.int8.onnx"; \
		cp "$$src_dir/tokens.txt" "${SENSEVOICE_DIR}/tokens.txt"; \
	fi; \
	if [ ! -f "${SENSEVOICE_DIR}/silero_vad.onnx" ]; then \
		tmp_vad="${SENSEVOICE_DIR}/silero_vad.onnx.part"; \
		rm -f "$$tmp_vad"; \
		${CURL} --output "$$tmp_vad" "${SILERO_VAD_URL}"; \
		mv "$$tmp_vad" "${SENSEVOICE_DIR}/silero_vad.onnx"; \
	fi

assets-tts:
	@mkdir -p "${ONNX_DIR}" "${VOICE_STYLE_DIR}"
	@set -e; \
	for file in ${SUPERTONIC_ONNX_FILES}; do \
		target="${ONNX_DIR}/$$file"; \
		if [ ! -f "$$target" ]; then \
			tmp_file="$$target.part"; \
			rm -f "$$tmp_file"; \
			${HF_CURL} --output "$$tmp_file" "${SUPERTONIC_BASE_URL}/onnx/$$file"; \
			mv "$$tmp_file" "$$target"; \
		fi; \
	done; \
	for file in ${SUPERTONIC_VOICE_STYLE_FILES}; do \
		target="${VOICE_STYLE_DIR}/$$file"; \
		if [ ! -f "$$target" ]; then \
			tmp_file="$$target.part"; \
			rm -f "$$tmp_file"; \
			${HF_CURL} --output "$$tmp_file" "${SUPERTONIC_BASE_URL}/voice_styles/$$file"; \
			mv "$$tmp_file" "$$target"; \
		fi; \
	done

clean-assets:
	@rm -f "${TRANSLATION_MODEL}" \
		"${SENSEVOICE_DIR}/model.int8.onnx" \
		"${SENSEVOICE_DIR}/tokens.txt" \
		"${SENSEVOICE_DIR}/silero_vad.onnx" \
		"${ONNX_DIR}/duration_predictor.onnx" \
		"${ONNX_DIR}/text_encoder.onnx" \
		"${ONNX_DIR}/tts.json" \
		"${ONNX_DIR}/unicode_indexer.json" \
		"${ONNX_DIR}/vector_estimator.onnx" \
		"${ONNX_DIR}/vocoder.onnx" \
		"${VOICE_STYLE_DIR}/F1.json" \
		"${VOICE_STYLE_DIR}/F2.json" \
		"${VOICE_STYLE_DIR}/F3.json" \
		"${VOICE_STYLE_DIR}/F4.json" \
		"${VOICE_STYLE_DIR}/F5.json" \
		"${VOICE_STYLE_DIR}/M1.json" \
		"${VOICE_STYLE_DIR}/M2.json" \
		"${VOICE_STYLE_DIR}/M3.json" \
		"${VOICE_STYLE_DIR}/M4.json" \
		"${VOICE_STYLE_DIR}/M5.json"
	@${MAKE} clean-assets-cache

clean-assets-cache:
	@rm -rf "${CACHE_DIR}"