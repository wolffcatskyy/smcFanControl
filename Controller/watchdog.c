/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "client.h"
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdlib.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <syslog.h>
extern char **environ;
static volatile sig_atomic_t running = 1;
static void stop(int sig) {
  (void)sig;
  running = 0;
}
static int run(char *const args[]) {
  pid_t pid;
  int status;
  if (posix_spawn(&pid, args[0], NULL, NULL, args, environ))
    return -1;
  int finished = 0;
  for (int i = 0; i < 50; i++) {
    pid_t result = waitpid(pid, &status, WNOHANG);
    if (result == pid) {
      finished = 1;
      break;
    }
    if (result < 0 && errno != EINTR)
      return -1;
    usleep(100000);
  }
  if (!finished) {
    kill(pid, SIGKILL);
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
    }
    return -1;
  }
  return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}
int main(void) {
  if (geteuid() != 0)
    return 1;
  int fd = open("/var/run/smcfan-ce-watchdog.lock",
                O_CREAT | O_RDWR | O_NOFOLLOW, 0600);
  if (fd < 0 || flock(fd, LOCK_EX | LOCK_NB))
    return 1;
  signal(SIGTERM, stop);
  signal(SIGINT, stop);
  signal(SIGPIPE, SIG_IGN);
  openlog("smcfan-ce-watchdog", LOG_PID, LOG_DAEMON);
  unsigned long previous = 0;
  int failures = 0, started = 0;
  while (running) {
    sleep(5);
    if (!running)
      break;
    char reply[8192];
    int ok = !ce_request("WATCHDOG", reply, sizeof reply);
    unsigned long sequence = 0;
    if (ok) {
      char *s = strstr(reply, "\"sequence\":");
      if (!s)
        ok = 0;
      else
        sequence = strtoul(s + 11, NULL, 10);
      if (!strstr(reply, "\"error\":0"))
        ok = 0;
    }
    if (ok && (!started || sequence != previous)) {
      failures = 0;
      previous = sequence;
      started = 1;
      continue;
    }
    if (++failures < 2)
      continue;
    syslog(LOG_ERR, "Control loop unavailable, stalled or reporting hardware "
                    "errors; restarting controller");
    char *restart[] = {"/bin/launchctl", "kickstart", "-k",
                       "system/dev.wolffcatskyy.smcfan-ce", NULL};
    if (run(restart))
      syslog(LOG_ERR, "Controller restart failed");
    sleep(5);
    if (ce_request("WATCHDOG", reply, sizeof reply) ||
        !strstr(reply, "\"error\":0")) {
      /* Rescue acquires the SAME controller lock. It cannot race a live owner.
       */
      char *rescue[] = {
          "/Library/Application Support/smcFanControlCE/smcfan-ce-daemon",
          "--rescue", NULL};
      if (run(rescue))
        syslog(LOG_CRIT, "Emergency maximum-speed takeover unavailable; "
                         "hardware state unverified");
      else
        syslog(
            LOG_ERR,
            "Emergency maximum speed applied while controller was unavailable");
    }
    failures = 0;
    started = 0;
  }
  close(fd);
  closelog();
  return 0;
}
