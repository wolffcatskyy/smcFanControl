/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef CE_BACKEND_H
#define CE_BACKEND_H
#include "policy.h"
struct ce_value {
  char type[5];
  unsigned size;
  unsigned char bytes[32];
};
int ce_hw_open(void);
void ce_hw_close(void);
int ce_hw_count(void);
int ce_hw_read(const char *key, struct ce_value *value);
double ce_decode(const struct ce_value *value);
int ce_hw_limits(int fan, struct ce_limits *limits);
int ce_hw_apply(int fan, enum ce_mode mode, int rpm);
int ce_hw_release(int fan);
/* Capture/restore the daemon's durable original minimum, independent of policy.
 */
int ce_hw_baseline(int fan, int replacement);

/* Explicit, root-configured ceiling override for the verified mp6 test profile.
 */
int ce_hw_limit_override(int fan, int replacement);

#endif /* CE_BACKEND_H */
