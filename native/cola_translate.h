// C ABI for offline translation using Hy-MT1.5-1.8B-1.25bit (STQ1_0 GGUF)
// via llama.cpp. Thread-safety: NOT thread-safe; call from a single worker
// thread.
#ifndef COLA_TRANSLATE_H
#define COLA_TRANSLATE_H

#ifdef __cplusplus
extern "C" {
#endif

// Initialize the inference engine with the given GGUF model file.
// Returns 0 on success, non-zero on failure. If already initialized, this is
// a no-op and returns 0.
int cola_init(const char* gguf_path);

// Returns 1 if the engine has been initialized successfully, 0 otherwise.
int cola_is_ready(void);

// Translate `text` from `src_lang` (ISO code or language name in English) to
// `tgt_lang` (ditto). Returned string is heap-allocated UTF-8 owned by the
// engine; caller must free it via cola_free_string.
// On failure returns NULL.
char* cola_translate(const char* text,
                     const char* src_lang,
                     const char* tgt_lang);

// Free a string previously returned by cola_translate.
void cola_free_string(char* s);

// Release engine resources. After this call, cola_init must be called again
// before further translations.
void cola_shutdown(void);

#ifdef __cplusplus
}
#endif

#endif
