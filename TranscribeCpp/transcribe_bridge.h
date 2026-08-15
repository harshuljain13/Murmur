// Umbrella header — imported by the Swift bridging header.
// When transcribe.cpp is compiled and libtranscribe.a is linked,
// these symbols will be available. Until then this header stubs them
// so Swift can compile without the library present.
#pragma once

#ifdef TRANSCRIBE_AVAILABLE
#include "include/transcribe.h"
#else
// Minimal stubs matching the real C API signatures so TranscribeEngine.swift
// compiles during development before the library is built.
#include <stdint.h>
#include <stdbool.h>

typedef struct transcribe_model   transcribe_model;
typedef struct transcribe_session transcribe_session;
typedef struct transcribe_result  transcribe_result;

typedef struct {
    uint64_t struct_size;
    int32_t  n_threads;
    bool     use_metal;
} transcribe_model_params;

typedef struct {
    uint64_t struct_size;
} transcribe_session_params;

typedef struct {
    uint64_t struct_size;
} transcribe_run_params;

static inline transcribe_model_params   transcribe_model_params_init(void)   { transcribe_model_params   p = {sizeof(p), 4, true}; return p; }
static inline transcribe_session_params transcribe_session_params_init(void) { transcribe_session_params p = {sizeof(p)}; return p; }
static inline transcribe_run_params     transcribe_run_params_init(void)     { transcribe_run_params     p = {sizeof(p)}; return p; }

static inline transcribe_model*   transcribe_model_load(const char* path, const transcribe_model_params* p)               { (void)path;(void)p; return 0; }
static inline void                transcribe_model_free(transcribe_model* m)                                               { (void)m; }
static inline transcribe_session* transcribe_session_create(transcribe_model* m, const transcribe_session_params* p)      { (void)m;(void)p; return 0; }
static inline void                transcribe_session_free(transcribe_session* s)                                           { (void)s; }
static inline transcribe_result*  transcribe_run(transcribe_session* s, const float* pcm, int32_t n, const transcribe_run_params* p) { (void)s;(void)pcm;(void)n;(void)p; return 0; }
static inline const char*         transcribe_result_text(const transcribe_result* r)                                       { (void)r; return 0; }
static inline void                transcribe_result_free(transcribe_result* r)                                             { (void)r; }
#endif
