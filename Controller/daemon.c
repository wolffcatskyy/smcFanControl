/* SPDX-License-Identifier: GPL-2.0-or-later */
#define _DARWIN_C_SOURCE
#include "backend.h"
#include "client.h"
#include <fcntl.h>
#include <grp.h>
#include <math.h>
#include <poll.h>
#include <pwd.h>
#include <signal.h>
#include <stdarg.h>
#include <stdlib.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <time.h>
#ifdef __linux__
#include <sys/types.h>
#endif
#define STATE_DIR "/Library/Application Support/smcFanControlCE"
#define STATE_FILE STATE_DIR "/controller.conf"
#define LOCK_FILE "/var/run/smcfan-ce.lock"
static const char *socket_path = CE_SOCKET_PATH, *state_path = STATE_FILE,
                  *lock_path = LOCK_FILE;
static struct ce_policy policies[CE_MAX_FANS];
static int configured[CE_MAX_FANS], previous[CE_MAX_FANS], fan_count,
    last_error;
static unsigned long sequence;
static double watchdog_seen;
static int sensor_fault[CE_MAX_FANS];
static volatile sig_atomic_t running = 1;
static double now(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec + t.tv_nsec / 1e9;
}
static void stop(int sig) {
  (void)sig;
  running = 0;
}
static void policy_line(FILE *f, int fan, struct ce_policy p) {
  fprintf(f, "SET %d %s", fan, ce_mode_name(p.mode));
  if (p.mode == CE_MINIMUM || p.mode == CE_MANUAL)
    fprintf(f, " %d", p.rpm);
  if (p.mode == CE_CURVE)
    fprintf(f, " %s %.6g %.6g", p.sensor, p.low, p.high);
  fputc('\n', f);
}
static int save_state(void) {
  char temp[1024];
  if (snprintf(temp, sizeof temp, "%s.new", state_path) >= (int)sizeof temp)
    return -1;
  int fd = open(temp, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0600);
  if (fd < 0)
    return -1;
  FILE *f = fdopen(fd, "w");
  if (!f) {
    close(fd);
    unlink(temp);
    return -1;
  }
  for (int i = 0; i < fan_count; i++) {
    fprintf(f, "BASE %d %d\n", i, ce_hw_baseline(i, 0));
    if (ce_hw_limit_override(i, 0) > 0)
      fprintf(f, "MAX %d %d\n", i, ce_hw_limit_override(i, 0));
    if (configured[i])
      policy_line(f, i, policies[i]);
  }
  int failed = fflush(f) || fsync(fd);
  if (fclose(f))
    failed = 1;
  if (failed || rename(temp, state_path)) {
    unlink(temp);
    return -1;
  }
  return 0;
}
static int load_state(void) {
  struct stat st;
  if (lstat(state_path, &st))
    return errno == ENOENT ? save_state() : -1;
  if (!S_ISREG(st.st_mode) || st.st_uid != geteuid() || (st.st_mode & 0077))
    return -1;
  FILE *f = fopen(state_path, "r");
  if (!f)
    return -1;
  char line[CE_COMMAND_MAX];
  int result = 0, seen[CE_MAX_FANS] = {0};
  while (fgets(line, sizeof line, f)) {
    int fan, rpm;
    char extra;
    if (sscanf(line, "BASE %d %d %c", &fan, &rpm, &extra) == 2) {
      if (fan < 0 || fan >= fan_count || seen[fan] || rpm <= 0 ||
          ce_hw_baseline(fan, rpm) < 0) {
        result = -1;
        break;
      }
      seen[fan] = 1;
    } else if (sscanf(line, "MAX %d %d %c", &fan, &rpm, &extra) == 2) {
      if (fan < 0 || fan >= fan_count || !seen[fan] ||
          ce_hw_limit_override(fan, rpm) < 0) {
        result = -1;
        break;
      }
    } else {
      struct ce_policy p;
      if (ce_parse(line, &fan, &p) || fan >= fan_count || !seen[fan] ||
          configured[fan]) {
        result = -1;
        break;
      }
      policies[fan] = p;
      configured[fan] = 1;
    }
  }
  if (ferror(f))
    result = -1;
  fclose(f);
  for (int i = 0; i < fan_count; i++)
    if (!seen[i])
      result = -1;
  return result;
}
static int target_for(int fan, struct ce_policy p, double elapsed) {
  struct ce_limits limits;
  if (ce_hw_limits(fan, &limits))
    return -1;
  double temperature = NAN;
  struct ce_value v;
  if (p.mode == CE_CURVE && !ce_hw_read(p.sensor, &v))
    temperature = ce_decode(&v);
  sensor_fault[fan] =
      p.mode == CE_CURVE &&
      (!isfinite(temperature) || temperature < -20 || temperature > 150);
  return ce_target(&p, limits, temperature, previous[fan], elapsed);
}
static int safe_max(int fan) {
  struct ce_limits l;
  if (!ce_hw_limits(fan, &l) && !ce_hw_apply(fan, CE_MAXIMUM, l.maximum))
    return 0;
  return ce_hw_release(fan);
}
static void tick(double elapsed) {
  last_error = 0;
  for (int i = 0; i < fan_count; i++)
    if (configured[i] && policies[i].mode != CE_AUTO) {
      int target = target_for(i, policies[i], elapsed);
      if (target < 0 || ce_hw_apply(i, policies[i].mode, target)) {
        last_error = 1;
        safe_max(i);
      } else
        previous[i] = target;
      if (sensor_fault[i])
        last_error = 1;
    }
  sequence++;
}
static int admin_peer(int fd) {
#ifdef CE_TESTING
  (void)fd;
  return 1;
#else
  uid_t uid;
  gid_t gid;
  if (getpeereid(fd, &uid, &gid))
    return 0;
  if (uid == 0)
    return 1;
  struct passwd *pw = getpwuid(uid);
  struct group *admin = getgrnam("admin");
  if (!pw || !admin)
    return 0;
  int count = 0;
  getgrouplist(pw->pw_name, pw->pw_gid, NULL, &count);
  if (count < 1 || count > 256)
    return 0;
  int groups[256];
  if (getgrouplist(pw->pw_name, pw->pw_gid, groups, &count) < 0)
    return 0;
  for (int i = 0; i < count; i++)
    if ((gid_t)groups[i] == admin->gr_gid)
      return 1;
  return 0;
#endif
}
static int root_peer(int fd) {
#ifdef CE_TESTING
  (void)fd;
  return 1;
#else
  uid_t uid;
  gid_t gid;
  return !getpeereid(fd, &uid, &gid) && uid == 0;
#endif
}
static int hexkey(const char *command, char key[5]) {
  if (strlen(command) != 13 || strncmp(command, "READ ", 5))
    return -1;
  for (int i = 0; i < 4; i++) {
    char part[3] = {command[5 + 2 * i], command[6 + 2 * i], 0}, *end;
    long n = strtol(part, &end, 16);
    if (*end || n < 32 || n > 126)
      return -1;
    key[i] = (char)n;
  }
  key[4] = 0;
  return key[0] == 'F' || key[0] == 'T' || !strcmp(key, "#KEY") ? 0 : -1;
}
static void respond(int fd, const char *command) {
  char reply[8192];
  size_t used = 0;
  if (!strcmp(command, "STATUS") ||
      (!strcmp(command, "WATCHDOG") && root_peer(fd))) {
    if (!strcmp(command, "WATCHDOG"))
      watchdog_seen = now();
    used = (size_t)snprintf(
        reply, sizeof reply,
        "{\"sequence\":%lu,\"watchdog_age\":%.0f,\"error\":%d,\"fans\":[",
        sequence, watchdog_seen ? now() - watchdog_seen : -1.0, last_error);
    for (int i = 0; i < fan_count; i++) {
      char key[5];
      struct ce_value v;
      snprintf(key, sizeof key, "F%cAc", "0123456789ABCDEF"[i]);
      double actual = ce_hw_read(key, &v) ? NAN : ce_decode(&v);
      struct ce_limits limits = {0, 0};
      ce_hw_limits(i, &limits);
      used += (size_t)snprintf(reply + used, sizeof reply - used,
                               "%s{\"id\":%d,\"mode\":\"%s\",\"rpm\":%d,"
                               "\"target\":%d,\"min\":%d,\"max\":%d}",
                               i ? "," : "", i,
                               configured[i] ? ce_mode_name(policies[i].mode)
                                             : "unmanaged",
                               isfinite(actual) ? (int)actual : -1, previous[i],
                               limits.minimum, limits.maximum);
    }
    snprintf(reply + used, sizeof reply - used, "]}\n");
  } else if (!strncmp(command, "READ ", 5)) {
    char key[5];
    struct ce_value v;
    if (hexkey(command, key) || ce_hw_read(key, &v))
      snprintf(reply, sizeof reply, "ERR read unavailable\n");
    else {
      used =
          (size_t)snprintf(reply, sizeof reply, "OK %.4s %u ", v.type, v.size);
      for (unsigned i = 0; i < v.size; i++)
        used += (size_t)snprintf(reply + used, sizeof reply - used, "%02x",
                                 v.bytes[i]);
      snprintf(reply + used, sizeof reply - used, "\n");
    }
  } else if (!strcmp(command, "SENSORS")) {
    /* Independently named public SMC keys; no proprietary mapping tables. */
    static const char *keys[] = {"TC0P", "TC0D", "TC0H", "TCAH", "TCBH",
                                 "TG0D", "TG1D", "TG0P", "TG1P", "TN0P",
                                 "TM0P", "TA0P", "TB0T", NULL};
    strcpy(reply, "OK\n");
    used = 3;
    for (int i = 0; keys[i]; i++) {
      struct ce_value v;
      if (ce_hw_read(keys[i], &v))
        continue;
      double t = ce_decode(&v);
      if (isfinite(t) && t >= -20 && t <= 150)
        used += (size_t)snprintf(reply + used, sizeof reply - used, "%s %.2f\n",
                                 keys[i], t);
    }
  } else {
    int fan;
    struct ce_policy p;
    if (!admin_peer(fd))
      snprintf(reply, sizeof reply, "ERR administrator membership required\n");
    else if (ce_parse(command, &fan, &p) || fan >= fan_count)
      snprintf(reply, sizeof reply, "ERR invalid policy\n");
    else {
      int target = target_for(fan, p, 0);
      if (p.mode == CE_CURVE && sensor_fault[fan])
        snprintf(reply, sizeof reply,
                 "ERR sensor unavailable; hardware unchanged\n");
      else if (target < 0)
        snprintf(reply, sizeof reply,
                 "ERR outside validated hardware limits\n");
      else {
        struct ce_policy old = policies[fan];
        int old_configured = configured[fan];
        policies[fan] = p;
        configured[fan] = 1;
        if (save_state()) {
          policies[fan] = old;
          configured[fan] = old_configured;
          snprintf(reply, sizeof reply,
                   "ERR could not persist policy; hardware unchanged\n");
        } else if (ce_hw_apply(fan, p.mode, target)) {
          last_error = 1;
          safe_max(fan);
          snprintf(reply, sizeof reply,
                   "ERR hardware verification failed; emergency cooling "
                   "attempted\n");
        } else {
          previous[fan] = target;
          snprintf(reply, sizeof reply, "OK policy saved and verified\n");
        }
      }
    }
  }
#ifdef MSG_NOSIGNAL
  send(fd, reply, strlen(reply), MSG_NOSIGNAL);
#else
  send(fd, reply, strlen(reply), 0);
#endif
}
static int acquire_lock(void) {
  int fd = open(lock_path, O_RDWR | O_CREAT | O_NOFOLLOW, 0600);
  if (fd < 0)
    return -1;
  if (flock(fd, LOCK_EX | LOCK_NB)) {
    close(fd);
    return -1;
  }
  return fd;
}
int main(int argc, char **argv) {
  int rescue = argc == 2 && !strcmp(argv[1], "--rescue");
  int release_only = argc == 2 && !strcmp(argv[1], "--release");
  int check_only = argc == 2 && !strcmp(argv[1], "--check-config");
#ifdef CE_TESTING
  if (argc == 4) {
    socket_path = argv[1];
    state_path = argv[2];
    lock_path = argv[3];
  }
#else
  if (geteuid() != 0) {
    fprintf(stderr, "Root service installation required\n");
    return 1;
  }
  if (argc != 1 && !rescue && !release_only && !check_only)
    return 1;
  if (mkdir(STATE_DIR, 0700) && errno != EEXIST)
    return 1;
  struct stat dir;
  if (lstat(STATE_DIR, &dir) || !S_ISDIR(dir.st_mode) || dir.st_uid != 0 ||
      (dir.st_mode & 0022))
    return 1;
#endif
  int lock = acquire_lock();
  if (lock < 0) {
    fprintf(stderr, "Another controller owns this instance\n");
    return 1;
  }
  if (ce_hw_open())
    return 1;
  fan_count = ce_hw_count();
  if (rescue) {
    int failed = 0;
    for (int i = 0; i < fan_count; i++)
      if (safe_max(i))
        failed = 1;
    ce_hw_close();
    close(lock);
    return failed;
  }
  if (load_state()) {
    fprintf(stderr, "Invalid or inaccessible root policy; refusing startup\n");
    ce_hw_close();
    return 1;
  }
  if (check_only) {
    puts("Root policy and detected hardware are compatible");
    ce_hw_close();
    close(lock);
    return 0;
  }
  if (release_only) {
    int failed = 0;
    for (int i = 0; i < fan_count; i++)
      if (configured[i] && ce_hw_release(i))
        failed = 1;
    ce_hw_close();
    close(lock);
    return failed;
  }
  signal(SIGTERM, stop);
  signal(SIGINT, stop);
  signal(SIGPIPE, SIG_IGN);
  int server = socket(AF_UNIX, SOCK_STREAM, 0);
  if (server < 0)
    return 1;
  struct sockaddr_un address;
  memset(&address, 0, sizeof address);
  address.sun_family = AF_UNIX;
  if (strlen(socket_path) >= sizeof address.sun_path)
    return 1;
  strcpy(address.sun_path, socket_path);
  unlink(socket_path);
  mode_t mask = umask(0111);
  int bound = bind(server, (struct sockaddr *)&address, sizeof address);
  umask(mask);
  if (bound || listen(server, 16)) {
    ce_hw_close();
    return 1;
  }
  double last = now();
  tick(0);
  while (running) {
    double current = now();
    if (current - last >= 2) {
      tick(current - last);
      last = current;
    }
    int timeout = (int)ceil(fmax(0, 2 - (now() - last)) * 1000);
    struct pollfd event = {server, POLLIN, 0};
    int ready = poll(&event, 1, timeout);
    if (ready < 0) {
      if (errno == EINTR)
        continue;
      break;
    }
    if (!ready)
      continue;
    int fd = accept(server, NULL, NULL);
    if (fd < 0)
      continue;
    struct timeval wait = {0, 100000};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, sizeof wait);
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &wait, sizeof wait);
    char command[CE_COMMAND_MAX];
    size_t used = 0;
    int complete = 0;
    while (used < sizeof(command) - 1) {
      ssize_t n = recv(fd, command + used, sizeof(command) - 1 - used, 0);
      if (!n) {
        complete = 1;
        break;
      }
      if (n < 0)
        break;
      used += (size_t)n;
      if (memchr(command, '\n', used)) {
        complete = 1;
        break;
      }
    }
    command[used] = 0;
    if (complete && used && !memchr(command, 0, used)) {
      while (used && (command[used - 1] == '\n' || command[used - 1] == '\r'))
        command[--used] = 0;
      respond(fd, command);
    }
    close(fd);
  }
  /* GUI disconnects never release control. A service stop explicitly does. */
  for (int i = 0; i < fan_count; i++)
    if (configured[i])
      ce_hw_release(i);
  close(server);
  unlink(socket_path);
  ce_hw_close();
  close(lock);
  return 0;
}
