/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Links the REAL production backend to fake SMC functions on the macOS SDK.
 * Models thermal firmware overwriting target writes while forced mode is off.
 */
#include "../../smc-command/smc.h"
#include "../backend.h"
#include <IOKit/IOKitLib.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>
static int minimum = 790, target = 790, forced, fail_target;
static unsigned other_bits = 0x8002;
static void number(SMCVal_t *v, const char *type, unsigned size, unsigned n) {
  strcpy(v->dataType, type);
  v->dataSize = size;
  if (size == 1)
    v->bytes[0] = (unsigned char)n;
  else {
    v->bytes[0] = (unsigned char)(n >> 8);
    v->bytes[1] = (unsigned char)n;
  }
}
kern_return_t SMCOpen(io_connect_t *conn) {
  *conn = 1;
  return 0;
}
kern_return_t SMCClose(io_connect_t conn) {
  (void)conn;
  return 0;
}
kern_return_t SMCReadKey2(UInt32Char_t key, SMCVal_t *v, io_connect_t conn) {
  (void)conn;
  memset(v, 0, sizeof *v);
  strcpy(v->key, key);
  if (!strcmp(key, "FNum"))
    number(v, "ui8 ", 1, 1);
  else if (!strcmp(key, "F0Mn"))
    number(v, "fpe2", 2, (unsigned)minimum * 4);
  else if (!strcmp(key, "F0Mx"))
    number(v, "fpe2", 2, 1900 * 4);
  else if (!strcmp(key, "F0Tg") || !strcmp(key, "F0Ac"))
    number(v, "fpe2", 2, (unsigned)(forced ? target : minimum) * 4);
  else if (!strcmp(key, "FS! "))
    number(v, "ui16", 2, other_bits | (forced ? 1u : 0));
  else
    return kIOReturnNotFound;
  return 0;
}
kern_return_t SMCWriteKey2(SMCVal_t v, io_connect_t conn) {
  (void)conn;
  int n = ((unsigned)v.bytes[0] * 256 + v.bytes[1]);
  if (!strcmp(v.key, "FS! ")) {
    forced = n & 1;
    other_bits = (unsigned)n & ~1u;
  } else if (!strcmp(v.key, "F0Mn"))
    minimum = n / 4;
  else if (!strcmp(v.key, "F0Tg")) {
    if (fail_target)
      return kIOReturnError;
    target = forced
                 ? n / 4
                 : minimum; /* Firmware immediately overwrites auto-mode Tg. */
  } else
    return kIOReturnNotFound;
  return 0;
}
int main(void) {
  assert(!ce_hw_open());
  assert(!ce_hw_apply(0, CE_MAXIMUM, 1900));
  assert(forced && target == 1900 && other_bits == 0x8002);
  assert(!ce_hw_release(0));
  assert(!forced && minimum == 790);
  assert(!ce_hw_apply(0, CE_MANUAL, 1500));
  assert(forced && target == 1500);
  assert(!ce_hw_release(0));
  assert(!ce_hw_apply(0, CE_MINIMUM, 1200));
  assert(!forced && minimum == 1200);
  assert(!ce_hw_apply(0, CE_MAXIMUM, 1900));
  assert(forced && target == 1900 && minimum == 790);
  fail_target = 1;
  assert(ce_hw_apply(0, CE_MANUAL, 1600));
  assert(!ce_hw_apply(0, CE_MINIMUM, 1900));
  assert(!forced && minimum == 1900);
  assert(!ce_hw_release(0));
  assert(!forced && minimum == 790);
  ce_hw_close();
  puts("Production backend: auto-to-manual ownership order, transitions, "
       "readback, fallback floor and unrelated force bits pass");
}
