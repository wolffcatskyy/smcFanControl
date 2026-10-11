/* Numeric release version parsing, shared by the app and portable tests. */
#ifndef SMC_RELEASE_VERSION_H
#define SMC_RELEASE_VERSION_H
#include <limits.h>
#include <stddef.h>
#include <string.h>

static int smc_parse_version(const char *text, unsigned long out[3]) {
    if (!text) return 0;
    if (*text == 'v') text++;
    for (int i = 0; i < 3; i++) {
        if (*text < '0' || *text > '9') return 0;
        unsigned long n = 0;
        do {
            unsigned long digit = (unsigned long)(*text - '0');
            if (n > (ULONG_MAX - digit) / 10) return 0;
            n = n * 10 + digit;
            text++;
        } while (*text >= '0' && *text <= '9');
        out[i] = n;
        if (i < 2 && *text++ != '.') return 0;
    }
    return *text == '\0' || strcmp(text, "-ce") == 0;
}

/* Return -1 for invalid input, 0 when not newer, 1 when newer. */
static int smc_release_is_newer(const char *candidate, const char *current) {
    unsigned long a[3], b[3];
    if (!smc_parse_version(candidate, a) || !smc_parse_version(current, b)) return -1;
    for (int i = 0; i < 3; i++) {
        if (a[i] > b[i]) return 1;
        if (a[i] < b[i]) return 0;
    }
    return 0;
}
#endif
