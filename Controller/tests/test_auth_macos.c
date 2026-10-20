/* SPDX-License-Identifier: GPL-2.0-or-later. Run on the administrator test
 * account. */
#include "../auth.h"
#include <assert.h>
#include <pwd.h>
#include <stdio.h>
#include <unistd.h>
int main(void) {
  assert(ce_authorized_uid(0));
  printf("current uid %u authorized=%d\n", (unsigned)getuid(),
         ce_authorized_uid(getuid()));
  assert(ce_authorized_uid(getuid()));
  struct passwd *nobody = getpwnam("nobody");
  assert(nobody);
  assert(!ce_authorized_uid(nobody->pw_uid));
  puts("Root/admin accepted; nobody rejected via production membership API");
}
