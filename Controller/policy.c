/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "policy.h"
#include <errno.h>
#include <limits.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

const char *ce_mode_name(enum ce_mode mode) {
  static const char *names[] = {"auto", "minimum", "manual", "maximum",
                                "curve"};
  return mode >= CE_AUTO && mode <= CE_CURVE ? names[mode] : "invalid";
}
static int integer(const char *s, int *out) {
  if (!s || !*s)
    return -1;
  char *end;
  errno = 0;
  long n = strtol(s, &end, 10);
  if (errno || *end || n < 0 || n > INT_MAX)
    return -1;
  *out = (int)n;
  return 0;
}
static int real(const char *s, double *out) {
  if (!s || !*s)
    return -1;
  char *end;
  errno = 0;
  double v = strtod(s, &end);
  if (errno || *end || !isfinite(v))
    return -1;
  *out = v;
  return 0;
}
int ce_parse(const char *request, int *fan, struct ce_policy *p) {
  if (!request || strlen(request) >= CE_COMMAND_MAX)
    return -1;
  char buf[CE_COMMAND_MAX], *save = NULL, *tokens[9];
  int n = 0;
  strcpy(buf, request);
  for (char *t = strtok_r(buf, " \t\r\n", &save); t;
       t = strtok_r(NULL, " \t\r\n", &save)) {
    if (n == 9)
      return -1;
    tokens[n++] = t;
  }
  if (n < 3 || strcmp(tokens[0], "SET") || integer(tokens[1], fan) ||
      *fan >= CE_MAX_FANS)
    return -1;
  memset(p, 0, sizeof *p);
  for (p->mode = CE_AUTO; p->mode <= CE_CURVE; p->mode++)
    if (!strcmp(tokens[2], ce_mode_name(p->mode)))
      break;
  if (p->mode > CE_CURVE)
    return -1;
  if (p->mode == CE_AUTO || p->mode == CE_MAXIMUM)
    return n == 3 ? 0 : -1;
  if (p->mode == CE_MINIMUM || p->mode == CE_MANUAL)
    return n == 4 && !integer(tokens[3], &p->rpm) ? 0 : -1;
  if (n != 6 || strlen(tokens[3]) != 4 || tokens[3][0] != 'T' ||
      real(tokens[4], &p->low) || real(tokens[5], &p->high))
    return -1;
  for (int i = 0; i < 4; i++)
    if (!((tokens[3][i] >= 'A' && tokens[3][i] <= 'Z') ||
          (tokens[3][i] >= 'a' && tokens[3][i] <= 'z') ||
          (tokens[3][i] >= '0' && tokens[3][i] <= '9')))
      return -1;
  if (p->low < 0 || p->high > 120 || p->high - p->low < 5)
    return -1;
  memcpy(p->sensor, tokens[3], 4);
  return 0;
}
int ce_target(const struct ce_policy *p, struct ce_limits l, double temp,
              int prev, double elapsed) {
  if (l.minimum <= 0 || l.maximum < l.minimum || l.maximum > 16000 ||
      p->mode < CE_AUTO || p->mode > CE_CURVE)
    return -1;
  if (p->mode == CE_AUTO)
    return 0;
  if (p->mode == CE_MAXIMUM)
    return l.maximum;
  if (p->mode != CE_CURVE)
    return p->rpm >= l.minimum && p->rpm <= l.maximum ? p->rpm : -1;
  if (!isfinite(p->low) || !isfinite(p->high) || p->low < 0 || p->high > 120 ||
      p->high - p->low < 5)
    return -1;
  /* Missing/invalid sensors demand full cooling, not a stale low-speed target.
   */
  if (!isfinite(temp) || temp < -20 || temp > 150 || temp >= p->high)
    return l.maximum;
  double fraction = (temp - p->low) / (p->high - p->low);
  if (fraction < 0)
    fraction = 0;
  if (fraction > 1)
    fraction = 1;
  int wanted = l.minimum + (int)ceil((l.maximum - l.minimum) * fraction);
  /* Increase immediately. Reduce gradually to avoid fan oscillation. */
  if (prev >= l.minimum && prev <= l.maximum && wanted < prev) {
    if (!isfinite(elapsed) || elapsed < 0)
      elapsed = 0;
    if (elapsed > 5)
      elapsed = 5;
    int floor = prev - (int)(100 * elapsed);
    if (wanted < floor)
      wanted = floor;
  }
  return wanted;
}
uint16_t ce_force_bit(uint16_t existing, unsigned fan, int forced) {
  if (fan >= CE_MAX_FANS)
    return existing;
  uint16_t bit = (uint16_t)(1u << fan);
  return forced ? (uint16_t)(existing | bit) : (uint16_t)(existing & ~bit);
}
