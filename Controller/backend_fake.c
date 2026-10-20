/* SPDX-License-Identifier: GPL-2.0-or-later. Test backend; never a production
 * build. */
#include "backend.h"
#include <math.h>
#include <stdio.h>
#include <string.h>
static int target[2] = {1000, 1000}, minimum[2] = {1000, 1000},
           baseline[2] = {1000, 1000};
static unsigned forced;
int ce_hw_open(void) { return 0; }
void ce_hw_close(void) {}
int ce_hw_count(void) { return 2; }
int ce_hw_baseline(int fan, int replacement) {
  if (fan < 0 || fan >= 2)
    return -1;
  if (replacement > 0)
    baseline[fan] = replacement;
  return baseline[fan];
}
int ce_hw_limits(int fan, struct ce_limits *l) {
  if (fan < 0 || fan >= 2)
    return -1;
  l->minimum = baseline[fan];
  l->maximum = 6000;
  return 0;
}
int ce_hw_release(int fan) {
  minimum[fan] = baseline[fan];
  forced = ce_force_bit((uint16_t)forced, (unsigned)fan, 0);
  return 0;
}
int ce_hw_apply(int fan, enum ce_mode mode, int rpm) {
  if (fan < 0 || fan >= 2)
    return -1;
  if (mode == CE_AUTO)
    return ce_hw_release(fan);
  if (rpm < baseline[fan] || rpm > 6000)
    return -1;
  target[fan] = rpm;
  if (mode == CE_MINIMUM)
    minimum[fan] = rpm;
  forced = ce_force_bit((uint16_t)forced, (unsigned)fan, mode != CE_MINIMUM);
  return 0;
}
int ce_hw_read(const char *key, struct ce_value *v) {
  memset(v, 0, sizeof *v);
  if (!strcmp(key, "FNum")) {
    strcpy(v->type, "ui8 ");
    v->size = 1;
    v->bytes[0] = 2;
    return 0;
  }
  if (!strcmp(key, "FS! ")) {
    strcpy(v->type, "ui16");
    v->size = 2;
    v->bytes[1] = (unsigned char)forced;
    return 0;
  }
  if (!strcmp(key, "TC0P")) {
    strcpy(v->type, "sp78");
    v->size = 2;
    v->bytes[0] = 65;
    return 0;
  }
  if (key[0] == 'F' && (key[1] == '0' || key[1] == '1')) {
    int fan = key[1] - '0', n = target[fan];
    if (!strcmp(key + 2, "Mn"))
      n = minimum[fan];
    else if (!strcmp(key + 2, "Mx"))
      n = 6000;
    else if (strcmp(key + 2, "Tg") && strcmp(key + 2, "Ac"))
      return -1;
    strcpy(v->type, "fpe2");
    v->size = 2;
    n *= 4;
    v->bytes[0] = (unsigned char)(n >> 8);
    v->bytes[1] = (unsigned char)n;
    return 0;
  }
  return -1;
}

int ce_hw_limit_override(int fan, int replacement) {
  if (fan < 0 || fan >= 2 || replacement > 0)
    return -1;
  return 0;
}
