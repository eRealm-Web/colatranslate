// Minimal offline translation wrapper around llama.cpp for the Hy-MT1.5 model.
// Uses the model's native chat template hard-coded as:
//   <｜hy_begin▁of▁sentence｜><｜hy_User｜>{prompt}<｜hy_Assistant｜>
// BOS is added by llama-tokenize via the GGUF metadata, so the wrapper only
// emits the User/Assistant tokens. Generation stops at EOS or at n_predict.

#include "cola_translate.h"

#include "llama.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

namespace {

struct Engine {
    llama_model*   model   = nullptr;
    llama_context* ctx     = nullptr;
    const llama_vocab* vocab = nullptr;
    llama_sampler* sampler = nullptr;
    std::mutex mu;
};

Engine g_engine;

void log_silent(ggml_log_level, const char*, void*) {}

bool load_engine(const char* gguf_path) {
    std::fprintf(stderr, "cola: load_engine start path=%s\n", gguf_path ? gguf_path : "(null)");
    ggml_backend_load_all();
    llama_log_set(log_silent, nullptr);

    llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers = 0;
    mparams.use_mmap     = true;
    mparams.use_mlock    = false;

    g_engine.model = llama_model_load_from_file(gguf_path, mparams);
    if (g_engine.model == nullptr) {
        std::fprintf(stderr, "cola: failed to load model: %s\n", gguf_path);
        return false;
    }

    g_engine.vocab = llama_model_get_vocab(g_engine.model);

    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx       = 1024;
    cparams.n_batch     = 512;
    cparams.n_ubatch    = 512;
    cparams.n_threads   = 4;
    cparams.n_threads_batch = 4;
    cparams.no_perf     = true;

    g_engine.ctx = llama_init_from_model(g_engine.model, cparams);
    if (g_engine.ctx == nullptr) {
        std::fprintf(stderr, "cola: failed to create context\n");
        llama_model_free(g_engine.model);
        g_engine.model = nullptr;
        return false;
    }

    // Greedy + small temperature sampler chain for deterministic translation.
    auto chain_params = llama_sampler_chain_default_params();
    chain_params.no_perf = true;
    g_engine.sampler = llama_sampler_chain_init(chain_params);
    llama_sampler_chain_add(g_engine.sampler, llama_sampler_init_top_k(20));
    llama_sampler_chain_add(g_engine.sampler, llama_sampler_init_top_p(0.8f, 1));
    llama_sampler_chain_add(g_engine.sampler, llama_sampler_init_temp(0.7f));
    llama_sampler_chain_add(g_engine.sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));

    std::fprintf(stderr, "cola: load_engine done\n");
    return true;
}

void free_engine() {
    if (g_engine.sampler) {
        llama_sampler_free(g_engine.sampler);
        g_engine.sampler = nullptr;
    }
    if (g_engine.ctx) {
        llama_free(g_engine.ctx);
        g_engine.ctx = nullptr;
    }
    if (g_engine.model) {
        llama_model_free(g_engine.model);
        g_engine.model = nullptr;
    }
    g_engine.vocab = nullptr;
}

// Map short codes to model-friendly language names used in prompts.
std::string lang_name(const std::string& code) {
    if (code == "zh") return "Chinese";
    if (code == "en") return "English";
    if (code == "ja") return "Japanese";
    if (code == "ko") return "Korean";
    if (code == "fr") return "French";
    if (code == "de") return "German";
    if (code == "es") return "Spanish";
    if (code == "ru") return "Russian";
    if (code == "auto") return "the source language";
    return code;
}

std::string build_prompt(const std::string& src_lang,
                         const std::string& tgt_lang,
                         const std::string& text) {
    const std::string tgt = lang_name(tgt_lang);
    std::string user;
    user.reserve(64 + text.size());
    user.append("Translate the following segment into ");
    user.append(tgt);
    user.append(", without additional explanation. ");
    user.append(text);

    // Chat template (Hy-MT). BOS will be auto-prepended by llama_tokenize.
    std::string prompt;
    prompt.append("<\xef\xbd\x9chy_User\xef\xbd\x9c>");
    prompt.append(user);
    prompt.append("<\xef\xbd\x9chy_Assistant\xef\xbd\x9c>");
    return prompt;
}

std::vector<llama_token> tokenize(const std::string& s, bool add_special) {
    int n_neg = -llama_tokenize(g_engine.vocab,
                                s.c_str(),
                                static_cast<int>(s.size()),
                                nullptr,
                                0,
                                add_special,
                                true);
    std::vector<llama_token> out(n_neg);
    int n = llama_tokenize(g_engine.vocab,
                           s.c_str(),
                           static_cast<int>(s.size()),
                           out.data(),
                           static_cast<int>(out.size()),
                           add_special,
                           true);
    if (n < 0) {
        out.clear();
    } else {
        out.resize(n);
    }
    return out;
}

std::string piece(llama_token tok) {
    char buf[256];
    int n = llama_token_to_piece(g_engine.vocab, tok, buf, sizeof(buf), 0, true);
    if (n < 0) return {};
    return std::string(buf, n);
}

} // namespace

extern "C" int cola_init(const char* gguf_path) {
    std::lock_guard<std::mutex> guard(g_engine.mu);
    if (g_engine.model != nullptr) {
        return 0;
    }
    if (gguf_path == nullptr || gguf_path[0] == '\0') {
        return 1;
    }
    return load_engine(gguf_path) ? 0 : 2;
}

extern "C" int cola_is_ready(void) {
    std::lock_guard<std::mutex> guard(g_engine.mu);
    return g_engine.model != nullptr ? 1 : 0;
}

extern "C" char* cola_translate(const char* text,
                                const char* src_lang,
                                const char* tgt_lang) {
    std::lock_guard<std::mutex> guard(g_engine.mu);
    if (g_engine.model == nullptr || text == nullptr) {
        return nullptr;
    }

    const std::string prompt = build_prompt(
        src_lang ? src_lang : "auto",
        tgt_lang ? tgt_lang : "en",
        text);

    auto tokens = tokenize(prompt, /*add_special=*/true);
    if (tokens.empty()) {
        return nullptr;
    }

    // Fresh KV cache for each request to make calls independent.
    llama_memory_clear(llama_get_memory(g_engine.ctx), true);

    const int n_ctx = static_cast<int>(llama_n_ctx(g_engine.ctx));
    const int max_new = 256;
    if (static_cast<int>(tokens.size()) + max_new > n_ctx) {
        return nullptr;
    }

    // Feed prompt.
    llama_batch batch = llama_batch_get_one(tokens.data(),
                                            static_cast<int>(tokens.size()));
    if (llama_decode(g_engine.ctx, batch) != 0) {
        return nullptr;
    }

    std::string out;
    out.reserve(text ? std::strlen(text) * 2 + 16 : 64);
    llama_token last = 0;
    for (int i = 0; i < max_new; ++i) {
        llama_token id = llama_sampler_sample(g_engine.sampler, g_engine.ctx, -1);
        if (llama_vocab_is_eog(g_engine.vocab, id)) {
            break;
        }
        out.append(piece(id));
        last = id;
        llama_batch one = llama_batch_get_one(&last, 1);
        if (llama_decode(g_engine.ctx, one) != 0) {
            break;
        }
    }

    // Trim leading whitespace some templates produce.
    size_t i = 0;
    while (i < out.size() && (out[i] == ' ' || out[i] == '\n' || out[i] == '\r' || out[i] == '\t')) {
        ++i;
    }
    if (i > 0) out.erase(0, i);

    char* buf = static_cast<char*>(std::malloc(out.size() + 1));
    if (buf == nullptr) return nullptr;
    std::memcpy(buf, out.data(), out.size());
    buf[out.size()] = '\0';
    return buf;
}

extern "C" void cola_free_string(char* s) {
    if (s) std::free(s);
}

extern "C" void cola_shutdown(void) {
    std::lock_guard<std::mutex> guard(g_engine.mu);
    free_engine();
}
