#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

float edgeai_dot_product_f32(const float *left, const float *right, int32_t count);
int32_t edgeai_llamacpp_headers_available(void);
const char *edgeai_llamacpp_integration_mode(void);

#ifdef __cplusplus
}
#endif
