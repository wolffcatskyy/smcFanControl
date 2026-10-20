/* GPL-2.0-or-later. Uses the smcFanControl SMC backend in smc.c. */
#include <errno.h>
#include <math.h>
#include <signal.h>
#include <sys/sysctl.h>
#define CMD_TOOL_BUILD
#define main smc_backend_cli_main
#include "../smc-command/smc.c"
#undef main
static volatile sig_atomic_t running = 1;
static void stop(int sig) {
  (void)sig;
  running = 0;
}
static int readkey(io_connect_t c, const char *key, SMCVal_t *v) {
  char k[5];
  snprintf(k, sizeof k, "%s", key);
  kern_return_t r = SMCReadKey2(k, v, c);
  if (r || !v->dataSize || v->dataSize > 32) {
    fprintf(stderr, "read %s failed: 0x%x\n", key, r);
    return -1;
  }
  return 0;
}
static int rpm(SMCVal_t *v) {
  if (v->dataSize != 2 || strcmp(v->dataType, "fpe2"))
    return -1;
  return ((unsigned)v->bytes[0] * 256 + v->bytes[1]) / 4;
}
static int put(io_connect_t c, SMCVal_t v) {
  kern_return_t r = SMCWriteKey2(v, c);
  SMCVal_t back;
  if (r || readkey(c, v.key, &back) || back.dataSize != v.dataSize ||
      memcmp(back.bytes, v.bytes, v.dataSize)) {
    fprintf(stderr, "write/readback %s failed: 0x%x\n", v.key, r);
    return -1;
  }
  return 0;
}
int main(int argc, char **argv) {
  char model[64];
  size_t len = sizeof model;
  if (sysctlbyname("hw.model", model, &len, NULL, 0) ||
      strcmp(model, "MacPro6,1")) {
    fprintf(stderr, "MacPro6,1 required\n");
    return 1;
  }
  int status = argc == 2 && !strcmp(argv[1], "--status");
  int once = argc == 3 && !strcmp(argv[1], "--once");
  int daemon = argc == 3 && !strcmp(argv[1], "--daemon");
  int automatic = argc == 2 && !strcmp(argv[1], "--restore-auto");
  if (!status && !once && !daemon && !automatic) {
    fprintf(stderr,
            "usage: %s --status | --once RPM | --daemon RPM | --restore-auto\n",
            argv[0]);
    return 1;
  }
  int target = 0;
  if (once || daemon) {
    char *end;
    errno = 0;
    long n = strtol(argv[2], &end, 10);
    if (errno || *end || n < 1900 || n > 2500)
      return 1;
    target = (int)n;
  }
  signal(SIGTERM, stop);
  signal(SIGINT, stop);
  setvbuf(stdout, NULL, _IOLBF, 0);
  do {
    io_connect_t c = 0;
    SMCVal_t count, mx, mn, tg, fs, ac;
    if (SMCOpen(&c))
      return 1;
    if (readkey(c, "FNum", &count) || count.dataSize != 1 ||
        count.bytes[0] != 1 || readkey(c, "F0Mx", &mx) ||
        readkey(c, "F0Mn", &mn) || readkey(c, "F0Tg", &tg) ||
        readkey(c, "FS! ", &fs) || readkey(c, "F0Ac", &ac) || rpm(&mx) < 0 ||
        rpm(&mn) < 0 || rpm(&tg) < 0 || fs.dataSize != 2) {
      SMCClose(c);
      return 1;
    }
    if (status)
      printf("model=%s fans=1 current=%d min=%d max=%d target=%d forced=%u\n",
             model, rpm(&ac), rpm(&mn), rpm(&mx), rpm(&tg),
             ((unsigned)fs.bytes[0] << 8) | fs.bytes[1]);
    else if (automatic) {
      /* 790 was recorded from this physical mp6 before installation. */
      mn.bytes[0] = (790 * 4) >> 8;
      mn.bytes[1] = (790 * 4) & 255;
      fs.bytes[1] &= ~1;
      if (put(c, mn) || put(c, fs)) {
        SMCClose(c);
        return 1;
      }
    } else {
      if (target < rpm(&mx)) {
        fprintf(stderr, "target below reported maximum\n");
        SMCClose(c);
        return 1;
      }
      tg.bytes[0] = (target * 4) >> 8;
      tg.bytes[1] = (target * 4) & 255;
      fs.bytes[1] |= 1;
      if (put(c, fs) || put(c, tg)) {
        SMCClose(c);
        return 1;
      }
    }
    SMCClose(c);
    if (!daemon)
      break;
    sleep(2);
  } while (running);
  return 0;
}
