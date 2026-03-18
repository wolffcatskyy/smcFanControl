/*
 * smcFanControl Community Edition - Boot Fan Daemon (smcfancontrold)
 *
 * A short-lived daemon that runs at boot (via LaunchDaemon) to apply
 * saved fan minimum RPM settings before the user logs in. This is
 * critical for OCLP (OpenCore Legacy Patcher) Macs where the SMC fan
 * controller defaults to maximum speed until software intervenes.
 *
 * Operation:
 *   1. Checks if this is an OCLP Mac (optional — can be forced with -f)
 *   2. Reads fan settings from /Library/Application Support/smcFanControl/fan-settings.plist
 *   3. Applies fan minimum RPM via SMC writes
 *   4. Logs results to /var/log/smcfancontrold.log
 *   5. Exits immediately (not a long-running daemon)
 *
 * Based on SMC access code from smcFanControl by Hendrik Holtmann,
 * original SMC tool by devnull, portions by Michael Wilber.
 *
 * Copyright (c) 2024 wolffcatskyy
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include "OCLPDetect.h"

/* --- SMC constants and types --- */

#define KERNEL_INDEX_SMC      2
#define SMC_CMD_READ_BYTES    5
#define SMC_CMD_WRITE_BYTES   6
#define SMC_CMD_READ_KEYINFO  9

#define DEFAULT_CONFIG_PATH   "/Library/Application Support/smcFanControl/fan-settings.plist"
#define LOG_PATH              "/var/log/smcfancontrold.log"

#define MAX_FANS              20
#define MAX_RPM               10000

typedef unsigned char SMCBytes_t[32];
typedef char UInt32Char_t[5];

typedef struct {
    UInt32 dataSize;
    UInt32 dataType;
    char   dataAttributes;
} SMCKeyData_keyInfo_t;

typedef struct {
    UInt32                key;
    struct { char major; char minor; char build; char reserved[1]; UInt16 release; } vers;
    struct { UInt16 version; UInt16 length; UInt32 cpuPLimit; UInt32 gpuPLimit; UInt32 memPLimit; } pLimitData;
    SMCKeyData_keyInfo_t  keyInfo;
    char                  result;
    char                  status;
    char                  data8;
    UInt32                data32;
    SMCBytes_t            bytes;
} SMCKeyData_t;

typedef struct {
    UInt32Char_t key;
    UInt32       dataSize;
    UInt32Char_t dataType;
    SMCBytes_t   bytes;
} SMCVal_t;

/* --- Logging --- */

static FILE *g_logfile = NULL;

static void log_msg(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void log_msg(const char *fmt, ...)
{
    time_t now = time(NULL);
    struct tm *tm = localtime(&now);
    char timebuf[64];
    strftime(timebuf, sizeof(timebuf), "%Y-%m-%d %H:%M:%S", tm);

    va_list ap;
    va_start(ap, fmt);

    /* Write to log file */
    if (g_logfile) {
        fprintf(g_logfile, "[%s] ", timebuf);
        vfprintf(g_logfile, fmt, ap);
        fprintf(g_logfile, "\n");
        fflush(g_logfile);
    }

    va_end(ap);

    /* Also write to stderr (captured by launchd) */
    va_start(ap, fmt);
    fprintf(stderr, "smcfancontrold: ");
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    va_end(ap);
}

/* --- SMC access --- */

static UInt32 key_to_uint32(const char *str)
{
    UInt32 total = 0;
    for (int i = 0; i < 4; i++)
        total += (unsigned char)str[i] << ((3 - i) * 8);
    return total;
}

static void uint32_to_key(char *str, UInt32 val)
{
    str[0] = (val >> 24) & 0xFF;
    str[1] = (val >> 16) & 0xFF;
    str[2] = (val >> 8)  & 0xFF;
    str[3] = val & 0xFF;
    str[4] = '\0';
}

static kern_return_t smc_call(io_connect_t conn, int index,
                              SMCKeyData_t *in, SMCKeyData_t *out)
{
    size_t in_size = sizeof(SMCKeyData_t);
    size_t out_size = sizeof(SMCKeyData_t);
    return IOConnectCallStructMethod(conn, index, in, in_size, out, &out_size);
}

static kern_return_t smc_open(io_connect_t *conn)
{
    kern_return_t result;
    io_iterator_t iterator;
    io_object_t device;

    CFMutableDictionaryRef matching = IOServiceMatching("AppleSMC");
    result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator);
    if (result != kIOReturnSuccess) {
        log_msg("error: IOServiceGetMatchingServices() = 0x%08x", result);
        return result;
    }

    device = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    if (device == 0) {
        log_msg("error: no AppleSMC device found");
        return kIOReturnNotFound;
    }

    result = IOServiceOpen(device, mach_task_self(), 0, conn);
    IOObjectRelease(device);
    if (result != kIOReturnSuccess)
        log_msg("error: IOServiceOpen() = 0x%08x", result);
    return result;
}

static kern_return_t smc_read(io_connect_t conn, const char *key_str, SMCVal_t *val)
{
    kern_return_t result;
    SMCKeyData_t in, out;

    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    memset(val, 0, sizeof(*val));

    in.key = key_to_uint32(key_str);
    snprintf(val->key, sizeof(val->key), "%s", key_str);

    in.data8 = SMC_CMD_READ_KEYINFO;
    result = smc_call(conn, KERNEL_INDEX_SMC, &in, &out);
    if (result != kIOReturnSuccess) return result;

    val->dataSize = out.keyInfo.dataSize;
    uint32_to_key(val->dataType, out.keyInfo.dataType);

    in.keyInfo.dataSize = val->dataSize;
    in.data8 = SMC_CMD_READ_BYTES;
    memset(&out, 0, sizeof(out));
    result = smc_call(conn, KERNEL_INDEX_SMC, &in, &out);
    if (result != kIOReturnSuccess) return result;

    memcpy(val->bytes, out.bytes, sizeof(out.bytes));
    return kIOReturnSuccess;
}

static kern_return_t smc_write(io_connect_t conn, const char *key_str,
                               const unsigned char *data, UInt32 data_size)
{
    kern_return_t result;
    SMCVal_t read_val;
    SMCKeyData_t in, out;

    result = smc_read(conn, key_str, &read_val);
    if (result != kIOReturnSuccess) return result;

    if (read_val.dataSize != data_size) {
        log_msg("error: key %s size mismatch (expected %u, got %u)",
                key_str, read_val.dataSize, data_size);
        return kIOReturnBadArgument;
    }

    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = key_to_uint32(key_str);
    in.data8 = SMC_CMD_WRITE_BYTES;
    in.keyInfo.dataSize = data_size;
    memcpy(in.bytes, data, data_size);

    return smc_call(conn, KERNEL_INDEX_SMC, &in, &out);
}

/* Encode RPM as fpe2: value * 4, big-endian 2 bytes */
static void encode_fpe2(int rpm, unsigned char out[2])
{
    UInt16 encoded = (UInt16)(rpm * 4);
    out[0] = (encoded >> 8) & 0xFF;
    out[1] = encoded & 0xFF;
}

/* Decode fpe2 to RPM */
static float decode_fpe2(const unsigned char bytes[2])
{
    UInt16 raw = ((UInt16)bytes[0] << 8) | bytes[1];
    return raw / 4.0f;
}

/* --- Plist config loading --- */

static CFDictionaryRef load_config(const char *path)
{
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(
        kCFAllocatorDefault, (const UInt8 *)path, strlen(path), false);
    if (!url) {
        log_msg("error: invalid config path: %s", path);
        return NULL;
    }

    CFReadStreamRef stream = CFReadStreamCreateWithFile(kCFAllocatorDefault, url);
    CFRelease(url);
    if (!stream || !CFReadStreamOpen(stream)) {
        log_msg("error: cannot open config file: %s", path);
        if (stream) CFRelease(stream);
        return NULL;
    }

    CFErrorRef error = NULL;
    CFPropertyListRef plist = CFPropertyListCreateWithStream(
        kCFAllocatorDefault, stream, 0, kCFPropertyListImmutable, NULL, &error);
    CFReadStreamClose(stream);
    CFRelease(stream);

    if (!plist || CFGetTypeID(plist) != CFDictionaryGetTypeID()) {
        log_msg("error: failed to parse plist config: %s", path);
        if (error) {
            CFStringRef desc = CFErrorCopyDescription(error);
            if (desc) {
                char buf[256];
                CFStringGetCString(desc, buf, sizeof(buf), kCFStringEncodingUTF8);
                log_msg("  detail: %s", buf);
                CFRelease(desc);
            }
            CFRelease(error);
        }
        if (plist) CFRelease(plist);
        return NULL;
    }

    return (CFDictionaryRef)plist;
}

/* --- Usage --- */

static void usage(const char *prog)
{
    fprintf(stderr, "Usage: %s [options]\n", prog);
    fprintf(stderr, "  -c <path>   Config plist path (default: %s)\n", DEFAULT_CONFIG_PATH);
    fprintf(stderr, "  -f          Force apply even if OCLP is not detected\n");
    fprintf(stderr, "  -n          Dry run (detect OCLP and read config, but don't write SMC)\n");
    fprintf(stderr, "  -q          Quiet mode (no log file, stderr only)\n");
    fprintf(stderr, "  -h          Show this help\n");
}

/* --- Main --- */

int main(int argc, char *argv[])
{
    const char *config_path = DEFAULT_CONFIG_PATH;
    bool force_apply = false;
    bool dry_run = false;
    bool quiet = false;
    int opt;

    while ((opt = getopt(argc, argv, "c:fnqh")) != -1) {
        switch (opt) {
            case 'c': config_path = optarg; break;
            case 'f': force_apply = true; break;
            case 'n': dry_run = true; break;
            case 'q': quiet = true; break;
            case 'h':
            default:
                usage(argv[0]);
                return (opt == 'h') ? 0 : 1;
        }
    }

    /* Open log file */
    if (!quiet) {
        g_logfile = fopen(LOG_PATH, "a");
        if (!g_logfile) {
            fprintf(stderr, "smcfancontrold: warning: cannot open %s for writing\n", LOG_PATH);
        }
    }

    log_msg("=== smcfancontrold starting (pid %d) ===", getpid());

    /* Step 1: OCLP detection */
    int oclp_flags = oclp_detect();
    char desc_buf[512];
    oclp_describe(oclp_flags, desc_buf, sizeof(desc_buf));
    log_msg("%s", desc_buf);

    if (oclp_flags == 0 && !force_apply) {
        log_msg("Not an OCLP Mac and -f not specified. Exiting without changes.");
        if (g_logfile) fclose(g_logfile);
        return 0;
    }

    if (force_apply && oclp_flags == 0) {
        log_msg("Force mode: applying fan settings despite no OCLP detection");
    }

    /* Step 2: Load config */
    CFDictionaryRef config = load_config(config_path);
    if (!config) {
        log_msg("error: no valid config at %s — exiting", config_path);
        if (g_logfile) fclose(g_logfile);
        return 1;
    }

    CFArrayRef fans = CFDictionaryGetValue(config, CFSTR("fans"));
    if (!fans || CFGetTypeID(fans) != CFArrayGetTypeID()) {
        log_msg("error: config missing 'fans' array");
        CFRelease(config);
        if (g_logfile) fclose(g_logfile);
        return 1;
    }

    CFIndex fan_count = CFArrayGetCount(fans);
    log_msg("config: %ld fan(s) defined", (long)fan_count);

    if (dry_run) {
        log_msg("dry run mode: skipping SMC writes");
        for (CFIndex i = 0; i < fan_count; i++) {
            CFDictionaryRef fan = CFArrayGetValueAtIndex(fans, i);
            if (!fan || CFGetTypeID(fan) != CFDictionaryGetTypeID()) continue;

            CFNumberRef id_num = CFDictionaryGetValue(fan, CFSTR("id"));
            CFNumberRef rpm_num = CFDictionaryGetValue(fan, CFSTR("min_rpm"));
            int fan_id = 0, min_rpm = 0;
            if (id_num) CFNumberGetValue(id_num, kCFNumberIntType, &fan_id);
            if (rpm_num) CFNumberGetValue(rpm_num, kCFNumberIntType, &min_rpm);
            log_msg("  fan %d: would set min RPM to %d", fan_id, min_rpm);
        }
        CFRelease(config);
        log_msg("=== dry run complete ===");
        if (g_logfile) fclose(g_logfile);
        return 0;
    }

    /* Step 3: Open SMC */
    io_connect_t conn = 0;
    kern_return_t kr = smc_open(&conn);
    if (kr != kIOReturnSuccess) {
        log_msg("error: cannot open SMC connection");
        CFRelease(config);
        if (g_logfile) fclose(g_logfile);
        return 1;
    }

    /* Step 4: Apply fan settings */
    static const char fannum[] = "0123456789ABCDEFGHIJ";
    int errors = 0;

    /* Read the hardware minimum speeds first, to know which fans need forced mode.
     * Build a bitmask for the FS!  key (forced fans). */
    UInt16 force_bitmask = 0;

    for (CFIndex i = 0; i < fan_count; i++) {
        CFDictionaryRef fan = CFArrayGetValueAtIndex(fans, i);
        if (!fan || CFGetTypeID(fan) != CFDictionaryGetTypeID()) {
            log_msg("warning: skipping invalid fan entry at index %ld", (long)i);
            continue;
        }

        CFNumberRef id_num = CFDictionaryGetValue(fan, CFSTR("id"));
        CFNumberRef rpm_num = CFDictionaryGetValue(fan, CFSTR("min_rpm"));
        if (!id_num || !rpm_num) {
            log_msg("warning: fan entry %ld missing id or min_rpm", (long)i);
            continue;
        }

        int fan_id = 0, min_rpm = 0;
        CFNumberGetValue(id_num, kCFNumberIntType, &fan_id);
        CFNumberGetValue(rpm_num, kCFNumberIntType, &min_rpm);

        if (fan_id < 0 || fan_id >= MAX_FANS) {
            log_msg("warning: fan id %d out of range (0-%d)", fan_id, MAX_FANS - 1);
            continue;
        }
        if (min_rpm < 0 || min_rpm > MAX_RPM) {
            log_msg("warning: min_rpm %d out of range (0-%d)", min_rpm, MAX_RPM);
            continue;
        }

        /* Read hardware minimum to determine if forced mode is needed */
        char mn_key[5];
        snprintf(mn_key, sizeof(mn_key), "F%cMn", fannum[fan_id]);
        SMCVal_t cur_val;
        kr = smc_read(conn, mn_key, &cur_val);
        if (kr != kIOReturnSuccess) {
            log_msg("error: cannot read %s (0x%08x)", mn_key, kr);
            errors++;
            continue;
        }
        float hw_min = decode_fpe2(cur_val.bytes);

        /* Write the minimum speed floor */
        unsigned char fpe2_bytes[2];
        encode_fpe2(min_rpm, fpe2_bytes);

        kr = smc_write(conn, mn_key, fpe2_bytes, 2);
        if (kr != kIOReturnSuccess) {
            log_msg("error: cannot write %s (0x%08x)", mn_key, kr);
            errors++;
            continue;
        }

        log_msg("fan %d (%s): min RPM %.0f -> %d", fan_id, mn_key, hw_min, min_rpm);

        /* If the requested speed is above hardware minimum, also set forced mode + target */
        if (min_rpm > (int)hw_min) {
            force_bitmask |= (1 << fan_id);

            /* Try per-fan mode key first (older Macs: F{n}Md) */
            char md_key[5];
            snprintf(md_key, sizeof(md_key), "F%dMd", fan_id);
            SMCVal_t md_val;
            kern_return_t md_kr = smc_read(conn, md_key, &md_val);
            if (md_kr == kIOReturnSuccess) {
                unsigned char md_byte = 0x01;  /* forced mode */
                smc_write(conn, md_key, &md_byte, 1);
            }

            /* Set target speed */
            char tg_key[5];
            snprintf(tg_key, sizeof(tg_key), "F%cTg", fannum[fan_id]);
            kr = smc_write(conn, tg_key, fpe2_bytes, 2);
            if (kr == kIOReturnSuccess) {
                log_msg("fan %d (%s): target RPM set to %d (forced)", fan_id, tg_key, min_rpm);
            } else {
                log_msg("warning: cannot write %s (0x%08x)", tg_key, kr);
            }
        }
    }

    /* Write the global force bitmask (FS! ) if any fan is forced */
    if (force_bitmask != 0) {
        unsigned char fs_bytes[2];
        fs_bytes[0] = (force_bitmask >> 8) & 0xFF;
        fs_bytes[1] = force_bitmask & 0xFF;
        kr = smc_write(conn, "FS! ", fs_bytes, 2);
        if (kr == kIOReturnSuccess) {
            log_msg("FS!  bitmask set to 0x%04x", force_bitmask);
        } else {
            log_msg("warning: cannot write FS!  (0x%08x) — per-fan Md keys used as fallback", kr);
        }
    }

    /* Cleanup */
    IOServiceClose(conn);
    CFRelease(config);

    if (errors == 0)
        log_msg("=== all fans configured successfully ===");
    else
        log_msg("=== completed with %d error(s) ===", errors);

    if (g_logfile) fclose(g_logfile);
    return (errors > 0) ? 1 : 0;
}
