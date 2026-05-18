#include "cola_translate.h"

// Keep the native FFI entrypoints strongly referenced so Release dead-strip
// does not drop them from the final app binary.
__attribute__((used)) static void *const cola_keepalive_symbols[] = {
    (void *)&cola_init,
    (void *)&cola_is_ready,
    (void *)&cola_translate,
    (void *)&cola_free_string,
    (void *)&cola_shutdown,
};