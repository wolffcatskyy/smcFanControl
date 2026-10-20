/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "client.h"
#include <stdlib.h>
int main(int argc, char **argv) {
  char command[256] = "", reply[16384];
  const char *path = CE_SOCKET_PATH;
  int first = 1;
  if (argc > 2 && !strcmp(argv[1], "--socket")) {
    path = argv[2];
    first = 3;
  }
  if (argc <= first) {
    fprintf(stderr, "usage: smcfanctl [--socket PATH] STATUS | SENSORS | SET "
                    "FAN auto|maximum | SET FAN manual|minimum RPM | SET FAN "
                    "curve SENSOR LOW HIGH\n");
    return 1;
  }
  size_t used = 0;
  for (int i = first; i < argc; i++) {
    int n = snprintf(command + used, sizeof(command) - used, "%s%s",
                     i > first ? " " : "", argv[i]);
    if (n < 0 || (size_t)n >= sizeof(command) - used)
      return 1;
    used += (size_t)n;
  }
  if (ce_request_at(path, command, reply, sizeof reply)) {
    fprintf(stderr, "Controller unavailable or timed out; no settings changed "
                    "by this client.\n");
    return 1;
  }
  puts(reply);
  return strncmp(reply, "ERR", 3) ? 0 : 1;
}
