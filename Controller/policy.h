/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef CE_POLICY_H
#define CE_POLICY_H
#include <stddef.h>
#include <stdint.h>
#define CE_MAX_FANS 16
#define CE_COMMAND_MAX 256

enum ce_mode { CE_AUTO, CE_MINIMUM, CE_MANUAL, CE_MAXIMUM, CE_CURVE };
struct ce_policy {
  enum ce_mode mode;
  int rpm;
  char sensor[5];
  double low, high;
};
struct ce_limits {
  int minimum, maximum;
};
const char *ce_mode_name(enum ce_mode mode);
int ce_parse(const char *request, int *fan, struct ce_policy *policy);
int ce_target(const struct ce_policy *p, struct ce_limits limits,
              double temperature, int previous, double elapsed);
uint16_t ce_force_bit(uint16_t existing, unsigned fan, int forced);
#endif
