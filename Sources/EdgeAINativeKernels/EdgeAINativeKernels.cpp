#include "EdgeAINativeKernels.h"

#if __has_include("llama.h")
#define EDGEAI_HAS_LLAMA_CPP 1
#include "llama.h"
#else
#define EDGEAI_HAS_LLAMA_CPP 0
#endif

float edgeai_dot_product_f32(const float *left, const float *right, int32_t count) {
    float sum = 0.0f;
    int32_t index = 0;

    for (; index + 3 < count; index += 4) {
        sum += left[index] * right[index];
        sum += left[index + 1] * right[index + 1];
        sum += left[index + 2] * right[index + 2];
        sum += left[index + 3] * right[index + 3];
    }

    for (; index < count; index += 1) {
        sum += left[index] * right[index];
    }

    return sum;
}

int32_t edgeai_llamacpp_headers_available(void) {
    return EDGEAI_HAS_LLAMA_CPP;
}

const char *edgeai_llamacpp_integration_mode(void) {
#if EDGEAI_HAS_LLAMA_CPP
    return "native-c-api";
#else
    return "http-server";
#endif
}
