#include "handyllm.h"
#include "llama.h"

#include <string>
#include <vector>
#include <cstring>
#include <cstdlib>

struct handy_llm {
    llama_model*        model = nullptr;
    const llama_vocab*  vocab = nullptr;
    int                 n_threads = 4;
};

static bool g_backend_ready = false;

handy_llm* handy_llm_load(const char* model_path, int n_threads) {
    if (!model_path) return nullptr;
    if (!g_backend_ready) { llama_backend_init(); g_backend_ready = true; }

    llama_model_params mp = llama_model_default_params();
    mp.n_gpu_layers = 0;               // CPU only — safe in the background

    llama_model* model = llama_model_load_from_file(model_path, mp);
    if (!model) return nullptr;

    handy_llm* h = new handy_llm();
    h->model = model;
    h->vocab = llama_model_get_vocab(model);
    h->n_threads = n_threads > 0 ? n_threads : 4;
    return h;
}

char* handy_llm_rewrite(handy_llm* h, const char* system_prompt, const char* user_text, int max_tokens) {
    if (!h || !h->model) return nullptr;
    if (max_tokens <= 0) max_tokens = 256;

    // Build the chat prompt with the model's own template.
    std::string sys = system_prompt ? system_prompt : "";
    std::string usr = user_text ? user_text : "";
    llama_chat_message msgs[2] = { {"system", sys.c_str()}, {"user", usr.c_str()} };
    const char* tmpl = llama_model_chat_template(h->model, nullptr);

    std::vector<char> buf(sys.size() + usr.size() + 4096);
    int32_t len = llama_chat_apply_template(tmpl, msgs, 2, true, buf.data(), (int32_t)buf.size());
    if (len > (int32_t)buf.size()) {
        buf.resize(len);
        len = llama_chat_apply_template(tmpl, msgs, 2, true, buf.data(), (int32_t)buf.size());
    }
    if (len < 0) return nullptr;
    std::string prompt(buf.data(), (size_t)len);

    // Context
    llama_context_params cp = llama_context_default_params();
    cp.n_ctx = 2048;
    cp.n_threads = h->n_threads;
    cp.n_threads_batch = h->n_threads;
    llama_context* ctx = llama_init_from_model(h->model, cp);
    if (!ctx) return nullptr;

    // Tokenize
    int32_t n_prompt = -llama_tokenize(h->vocab, prompt.c_str(), (int32_t)prompt.size(), nullptr, 0, true, true);
    std::vector<llama_token> tokens(n_prompt);
    if (llama_tokenize(h->vocab, prompt.c_str(), (int32_t)prompt.size(), tokens.data(), (int32_t)tokens.size(), true, true) < 0) {
        llama_free(ctx);
        return nullptr;
    }

    // Greedy sampler → deterministic reword
    llama_sampler* smpl = llama_sampler_chain_init(llama_sampler_chain_default_params());
    llama_sampler_chain_add(smpl, llama_sampler_init_greedy());

    std::string result;
    llama_batch batch = llama_batch_get_one(tokens.data(), (int32_t)tokens.size());
    int generated = 0;

    while (true) {
        if (llama_decode(ctx, batch) != 0) break;
        llama_token tok = llama_sampler_sample(smpl, ctx, -1);
        if (llama_vocab_is_eog(h->vocab, tok)) break;
        char piece[256];
        int32_t np = llama_token_to_piece(h->vocab, tok, piece, sizeof(piece), 0, true);
        if (np > 0) result.append(piece, (size_t)np);
        if (++generated >= max_tokens) break;
        batch = llama_batch_get_one(&tok, 1);
    }

    llama_sampler_free(smpl);
    llama_free(ctx);

    char* out = (char*)malloc(result.size() + 1);
    if (out) memcpy(out, result.c_str(), result.size() + 1);
    return out;
}

void handy_llm_free_string(char* s) { if (s) free(s); }

void handy_llm_free(handy_llm* h) {
    if (!h) return;
    if (h->model) llama_model_free(h->model);
    delete h;
}
