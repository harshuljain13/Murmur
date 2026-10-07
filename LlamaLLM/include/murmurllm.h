// Minimal C wrapper around llama.cpp for on-device text rewriting.
// ONLY these symbols are exported from the built library; all llama/ggml
// internals are hidden so they don't collide with transcribe.cpp's ggml.
#pragma once
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct murmur_llm murmur_llm;

/// Load a GGUF instruct model (CPU only). Returns NULL on failure.
murmur_llm* murmur_llm_load(const char* model_path, int n_threads);

/// Rewrite `user_text` under `system_prompt`. Greedy decoding for determinism.
/// Returns a malloc'd C string (free with murmur_llm_free_string) or NULL.
char* murmur_llm_rewrite(murmur_llm* h, const char* system_prompt, const char* user_text, int max_tokens);

void murmur_llm_free_string(char* s);
void murmur_llm_free(murmur_llm* h);

#ifdef __cplusplus
}
#endif
