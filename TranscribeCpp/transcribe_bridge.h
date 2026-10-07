// Bridging header for MurmurApp → transcribe.cpp C API
// HEADER_SEARCH_PATHS includes $(PROJECT_DIR)/TranscribeCpp/include
#pragma once
#include "transcribe.h"
#include "murmurllm.h"   // on-device LLM rewriter (llama.cpp wrapper)
