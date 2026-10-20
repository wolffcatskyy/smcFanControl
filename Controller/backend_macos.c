/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "../smc-command/smc.h"
#include "backend.h"
#include <IOKit/IOKitLib.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <sys/sysctl.h>
static io_connect_t connection;
static int count;
static int limit_override[CE_MAX_FANS];
static struct ce_value originals[CE_MAX_FANS];
static int have_original[CE_MAX_FANS];
int ce_hw_read(const char *key, struct ce_value *v) {
  if (strlen(key) != 4)
    return -1;
  char k[5];
  memcpy(k, key, 5);
  SMCVal_t raw;
  if (SMCReadKey2(k, &raw, connection) || raw.dataSize < 1 || raw.dataSize > 32)
    return -1;
  memset(v, 0, sizeof *v);
  memcpy(v->type, raw.dataType, 4);
  v->size = raw.dataSize;
  memcpy(v->bytes, raw.bytes, v->size);
  return 0;
}
static int write_value(const char *key, struct ce_value v) {
  struct ce_value current;
  if (!ce_hw_read(key, &current) && current.size == v.size &&
      !memcmp(current.bytes, v.bytes, v.size))
    return 0;
  SMCVal_t raw;
  memset(&raw, 0, sizeof raw);
  memcpy(raw.key, key, 4);
  raw.dataSize = v.size;
  memcpy(raw.bytes, v.bytes, v.size);
  if (SMCWriteKey2(raw, connection))
    return -1;
  struct ce_value check;
  return ce_hw_read(key, &check) || check.size != v.size ||
                 memcmp(check.bytes, v.bytes, v.size)
             ? -1
             : 0;
}
static void fan_key(char key[5], int fan, const char *suffix) {
  snprintf(key, 5, "F%c%s", "0123456789ABCDEF"[fan], suffix);
}
int ce_hw_open(void) {
  if (SMCOpen(&connection))
    return -1;
  struct ce_value v;
  if (ce_hw_read("FNum", &v) || !isfinite(ce_decode(&v))) {
    SMCClose(connection);
    return -1;
  }
  count = (int)ce_decode(&v);
  if (count < 1 || count > CE_MAX_FANS) {
    SMCClose(connection);
    return -1;
  }
  for (int i = 0; i < count; i++) {
    char k[5];
    fan_key(k, i, "Mn");
    if (ce_hw_read(k, &originals[i])) {
      SMCClose(connection);
      return -1;
    }
    have_original[i] = 1;
  }
  return 0;
}
void ce_hw_close(void) {
  SMCClose(connection);
  connection = 0;
}
int ce_hw_count(void) { return count; }
int ce_hw_limits(int fan, struct ce_limits *limits) {
  if (fan < 0 || fan >= count)
    return -1;
  char k[5];
  struct ce_value v;
  fan_key(k, fan, "Mx");
  if (ce_hw_read(k, &v))
    return -1;
  double min = ce_decode(&originals[fan]), max = ce_decode(&v);
  if (limit_override[fan])
    max = limit_override[fan];
  if (!isfinite(min) || !isfinite(max) || min <= 0 || max < min || max > 16000)
    return -1;
  limits->minimum = (int)ceil(min);
  limits->maximum = (int)floor(max);
  return 0;
}
static int force(int fan, int enabled) {
  char k[5];
  struct ce_value v;
  fan_key(k, fan, "Md");
  if (!ce_hw_read(k, &v) && v.size == 1 && !strcmp(v.type, "ui8 ")) {
    v.bytes[0] = enabled ? 1 : 0;
    return write_value(k, v);
  }
  if (ce_hw_read("FS! ", &v) || v.size != 2 || strcmp(v.type, "ui16"))
    return -1;
  uint16_t old = (uint16_t)(((unsigned)v.bytes[0] << 8) | v.bytes[1]);
  uint16_t next = ce_force_bit(old, (unsigned)fan, enabled);
  v.bytes[0] = (unsigned char)(next >> 8);
  v.bytes[1] = (unsigned char)next;
  return write_value("FS! ", v);
}
static int write_rpm(int fan, const char *suffix, int rpm) {
  char k[5];
  struct ce_value v;
  fan_key(k, fan, suffix);
  if (ce_hw_read(k, &v))
    return -1;
  if (v.size == 2 && !strcmp(v.type, "fpe2")) {
    unsigned n = (unsigned)rpm * 4;
    v.bytes[0] = (unsigned char)(n >> 8);
    v.bytes[1] = (unsigned char)n;
  } else if (v.size == 4 && !strcmp(v.type, "flt ")) {
    float f = (float)rpm;
    memcpy(v.bytes, &f, 4);
  } else
    return -1;
  return write_value(k, v);
}
int ce_hw_release(int fan) {
  if (fan < 0 || fan >= count || !have_original[fan])
    return -1;
  char k[5];
  fan_key(k, fan, "Mn");
  int a = write_value(k, originals[fan]);
  int b = force(fan, 0);
  return a || b ? -1 : 0;
}
int ce_hw_apply(int fan, enum ce_mode mode, int rpm) {
  if (mode == CE_AUTO)
    return ce_hw_release(fan);
  struct ce_limits limits;
  if (ce_hw_limits(fan, &limits) || rpm < limits.minimum ||
      rpm > limits.maximum)
    return -1;
  if (mode == CE_MINIMUM) {
    if (write_rpm(fan, "Mn", rpm))
      return -1;
    return force(fan, 0);
  }
  char k[5];
  fan_key(k, fan, "Mn");
  /* Establish manual ownership before verifying Tg: firmware can overwrite
   * targets while automatic mode is still active. This transition must work
   * from a cold/automatic state, not just when a previous helper left FS! set.
   */
  if (write_value(k, originals[fan]) || force(fan, 1) ||
      write_rpm(fan, "Tg", rpm))
    return -1;
  return 0;
}
int ce_hw_baseline(int fan, int replacement) {
  if (fan < 0 || fan >= count || !have_original[fan])
    return -1;
  if (replacement > 0) {
    char k[5];
    struct ce_value mx;
    fan_key(k, fan, "Mx");
    if (ce_hw_read(k, &mx) || replacement > ce_decode(&mx))
      return -1;
    struct ce_value *v = &originals[fan];
    if (v->size == 2 && !strcmp(v->type, "fpe2")) {
      unsigned n = (unsigned)replacement * 4;
      v->bytes[0] = (unsigned char)(n >> 8);
      v->bytes[1] = (unsigned char)n;
    } else if (v->size == 4 && !strcmp(v->type, "flt ")) {
      float n = (float)replacement;
      memcpy(v->bytes, &n, 4);
    } else
      return -1;
  }
  double n = ce_decode(&originals[fan]);
  return isfinite(n) && n > 0 ? (int)ceil(n) : -1;
}

int ce_hw_limit_override(int fan, int replacement) {
  if (fan < 0 || fan >= count)
    return -1;
  if (replacement > 0) {
    char model[64];
    size_t size = sizeof model;
    struct ce_value v;
    /* A deliberate exception for the measured existing mp6 profile, never a
     * generic ceiling guess. */
    if (sysctlbyname("hw.model", model, &size, NULL, 0) ||
        strcmp(model, "MacPro6,1") || fan != 0 || replacement != 2141 ||
        ce_hw_read("F0Mx", &v))
      return -1;
    double reported = ce_decode(&v);
    if (!isfinite(reported) || reported < 1700 || reported > 2200)
      return -1;
    limit_override[fan] = replacement;
  }
  return limit_override[fan];
}
