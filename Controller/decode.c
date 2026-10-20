/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "backend.h"
#include <math.h>
#include <stdint.h>
#include <string.h>
double ce_decode(const struct ce_value *v) {
  if (v->size == 2 && !strcmp(v->type, "fpe2"))
    return ((unsigned)v->bytes[0] * 256 + v->bytes[1]) / 4.0;
  if (v->size == 2 && !strcmp(v->type, "sp78"))
    return (int16_t)((unsigned)v->bytes[0] * 256 + v->bytes[1]) / 256.0;
  if (v->size == 1 && !strcmp(v->type, "ui8 "))
    return v->bytes[0];
  if (v->size == 2 && !strcmp(v->type, "ui16"))
    return (unsigned)v->bytes[0] * 256 + v->bytes[1];
  if (v->size == 4 && !strcmp(v->type, "flt ")) {
    float f;
    memcpy(&f, v->bytes, 4);
    return isfinite(f) ? f : NAN;
  }
  return NAN;
}
