// Minimal C wrapper around llama.cpp for on-device text rewriting.
// ONLY these symbols are exported from the built library; all llama/ggml
// internals are hidden so they don't collide with transcribe.cpp's ggml.
#pragma once
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct handy_llm handy_llm;

/// Load a GGUF instruct model (CPU only). Returns NULL on failure.
handy_llm* handy_llm_load(const char* model_path, int n_threads);

/// Rewrite `user_text` under `system_prompt`. Greedy decoding for determinism.
/// Returns a malloc'd C string (free with handy_llm_free_string) or NULL.
char* handy_llm_rewrite(handy_llm* h, const char* system_prompt, const char* user_text, int max_tokens);

void handy_llm_free_string(char* s);
void handy_llm_free(handy_llm* h);

#ifdef __cplusplus
}
#endif
