/* SPDX-License-Identifier: GPL-2.0-or-later. Read-only hardware diagnostic. */
#include "backend.h"
#include <math.h>
#include <stdio.h>
int main(int argc, char **argv) {
  (void)argv;
  if (ce_hw_open()) {
    fprintf(stderr, "AppleSMC open/read failed\n");
    return 1;
  }
  int failed = 0;
  if (argc == 2 && ce_hw_limit_override(0, 2141) < 0) {
    ce_hw_close();
    return 1;
  }
  for (int fan = 0; fan < ce_hw_count(); fan++) {
    struct ce_limits limits;
    if (ce_hw_limits(fan, &limits)) {
      failed = 1;
      continue;
    }
    char key[5];
    struct ce_value v;
    snprintf(key, sizeof key, "F%cAc", "0123456789ABCDEF"[fan]);
    if (ce_hw_read(key, &v)) {
      failed = 1;
      continue;
    }
    printf("fan=%d actual=%.2f minimum=%d reported_maximum=%d\n", fan,
           ce_decode(&v), limits.minimum, limits.maximum);
  }
  ce_hw_close();
  return failed;
}
