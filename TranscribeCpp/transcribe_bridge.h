// Bridging header for HandyApp → transcribe.cpp C API
// HEADER_SEARCH_PATHS includes $(PROJECT_DIR)/TranscribeCpp/include
#pragma once
#include "transcribe.h"
#include "handyllm.h"   // on-device LLM rewriter (llama.cpp wrapper)
