#include "cola_translate.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

int main(int argc, char** argv) {
    if (argc < 4) {
        std::fprintf(stderr,
            "usage: %s <model.gguf> <src_lang> <tgt_lang> [text...]\n",
            argv[0]);
        return 1;
    }
    if (cola_init(argv[1]) != 0) {
        std::fprintf(stderr, "init failed\n");
        return 2;
    }
    std::string text;
    for (int i = 4; i < argc; ++i) {
        if (i > 4) text += ' ';
        text += argv[i];
    }
    if (text.empty()) text = "Hello, how are you today?";

    char* out = cola_translate(text.c_str(), argv[2], argv[3]);
    if (!out) {
        std::fprintf(stderr, "translate returned NULL\n");
        cola_shutdown();
        return 3;
    }
    std::printf("%s\n", out);
    cola_free_string(out);
    cola_shutdown();
    return 0;
}
