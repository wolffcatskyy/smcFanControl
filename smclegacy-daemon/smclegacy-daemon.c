/*
 * smcFanControl Community Edition - Boot Fan Daemon
 * Sets fan minimum RPMs at boot from a plist config file.
 *
 * Based on SMC access code from smcFanControl by Hendrik Holtmann,
 * original SMC tool by devnull, portions by Michael Wilber.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>

/* SMC constants */
#define KERNEL_INDEX_SMC      2
#define SMC_CMD_READ_BYTES    5
#define SMC_CMD_WRITE_BYTES   6
#define SMC_CMD_READ_KEYINFO  9

#define DEFAULT_CONFIG_PATH "/Library/Application Support/smcFanControl/fan-boot-profile.plist"

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

/* Convert 4-char key string to UInt32 */
static UInt32 key_to_uint32(const char *str)
{
    UInt32 total = 0;
    for (int i = 0; i < 4; i++)
        total += (unsigned char)str[i] << ((3 - i) * 8);
    return total;
}

/* Convert UInt32 back to 4-char string */
static void uint32_to_key(char *str, UInt32 val)
{
    str[0] = (val >> 24) & 0xFF;
    str[1] = (val >> 16) & 0xFF;
    str[2] = (val >> 8)  & 0xFF;
    str[3] = val & 0xFF;
    str[4] = '\0';
}

/* Low-level SMC call */
static kern_return_t smc_call(io_connect_t conn, int index,
                              SMCKeyData_t *in, SMCKeyData_t *out)
{
    size_t in_size = sizeof(SMCKeyData_t);
    size_t out_size = sizeof(SMCKeyData_t);
    return IOConnectCallStructMethod(conn, index, in, in_size, out, &out_size);
}

/* Open connection to AppleSMC */
static kern_return_t smc_open(io_connect_t *conn)
{
    kern_return_t result;
    io_iterator_t iterator;
    io_object_t device;

    CFMutableDictionaryRef matching = IOServiceMatching("AppleSMC");
    result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator);
    if (result != kIOReturnSuccess) {
        fprintf(stderr, "error: IOServiceGetMatchingServices() = 0x%08x\n", result);
        return result;
    }

    device = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    if (device == 0) {
        fprintf(stderr, "error: no AppleSMC device found\n");
        return kIOReturnNotFound;
    }

    result = IOServiceOpen(device, mach_task_self(), 0, conn);
    IOObjectRelease(device);
    if (result != kIOReturnSuccess) {
        fprintf(stderr, "error: IOServiceOpen() = 0x%08x\n", result);
    }
    return result;
}

/* Read an SMC key */
static kern_return_t smc_read(io_connect_t conn, const char *key_str, SMCVal_t *val)
{
    kern_return_t result;
    SMCKeyData_t in, out;

    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    memset(val, 0, sizeof(*val));

    in.key = key_to_uint32(key_str);
    snprintf(val->key, sizeof(val->key), "%s", key_str);

    /* Get key info first */
    in.data8 = SMC_CMD_READ_KEYINFO;
    result = smc_call(conn, KERNEL_INDEX_SMC, &in, &out);
    if (result != kIOReturnSuccess) return result;

    val->dataSize = out.keyInfo.dataSize;
    uint32_to_key(val->dataType, out.keyInfo.dataType);

    /* Now read the value */
    in.keyInfo.dataSize = val->dataSize;
    in.data8 = SMC_CMD_READ_BYTES;
    memset(&out, 0, sizeof(out));
    result = smc_call(conn, KERNEL_INDEX_SMC, &in, &out);
    if (result != kIOReturnSuccess) return result;

    memcpy(val->bytes, out.bytes, sizeof(out.bytes));
    return kIOReturnSuccess;
}

/* Write an SMC key (reads first to validate size) */
static kern_return_t smc_write(io_connect_t conn, const char *key_str,
                               const unsigned char *data, UInt32 data_size)
{
    kern_return_t result;
    SMCVal_t read_val;
    SMCKeyData_t in, out;

    /* Read to confirm key exists and get expected size */
    result = smc_read(conn, key_str, &read_val);
    if (result != kIOReturnSuccess) return result;

    if (read_val.dataSize != data_size) {
        fprintf(stderr, "error: key %s size mismatch (expected %u, got %u)\n",
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

int main(int argc, char *argv[])
{
    const char *config_path = (argc > 1) ? argv[1] : DEFAULT_CONFIG_PATH;
    io_connect_t conn = 0;
    kern_return_t kr;
    int exit_code = 0;

    fprintf(stderr, "smcfancontrol-daemon: reading config from %s\n", config_path);

    /* Load plist config */
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(
        kCFAllocatorDefault, (const UInt8 *)config_path, strlen(config_path), false);
    if (!url) {
        fprintf(stderr, "error: invalid config path\n");
        return 1;
    }

    CFReadStreamRef stream = CFReadStreamCreateWithFile(kCFAllocatorDefault, url);
    CFRelease(url);
    if (!stream || !CFReadStreamOpen(stream)) {
        fprintf(stderr, "error: cannot open config file: %s\n", config_path);
        if (stream) CFRelease(stream);
        return 1;
    }

    CFErrorRef error = NULL;
    CFPropertyListRef plist = CFPropertyListCreateWithStream(
        kCFAllocatorDefault, stream, 0, kCFPropertyListImmutable, NULL, &error);
    CFReadStreamClose(stream);
    CFRelease(stream);

    if (!plist || CFGetTypeID(plist) != CFDictionaryGetTypeID()) {
        fprintf(stderr, "error: failed to parse plist config\n");
        if (error) {
            CFStringRef desc = CFErrorCopyDescription(error);
            if (desc) {
                char buf[256];
                CFStringGetCString(desc, buf, sizeof(buf), kCFStringEncodingUTF8);
                fprintf(stderr, "  detail: %s\n", buf);
                CFRelease(desc);
            }
            CFRelease(error);
        }
        if (plist) CFRelease(plist);
        return 1;
    }

    CFArrayRef fans = CFDictionaryGetValue((CFDictionaryRef)plist, CFSTR("fans"));
    if (!fans || CFGetTypeID(fans) != CFArrayGetTypeID()) {
        fprintf(stderr, "error: config missing 'fans' array\n");
        CFRelease(plist);
        return 1;
    }

    /* Open SMC connection */
    kr = smc_open(&conn);
    if (kr != kIOReturnSuccess) {
        CFRelease(plist);
        return 1;
    }

    /* Process each fan entry */
    CFIndex count = CFArrayGetCount(fans);
    fprintf(stderr, "smcfancontrol-daemon: found %ld fan(s) in config\n", (long)count);

    for (CFIndex i = 0; i < count; i++) {
        CFDictionaryRef fan = CFArrayGetValueAtIndex(fans, i);
        if (!fan || CFGetTypeID(fan) != CFDictionaryGetTypeID()) {
            fprintf(stderr, "warning: skipping invalid fan entry at index %ld\n", (long)i);
            continue;
        }

        CFNumberRef id_num = CFDictionaryGetValue(fan, CFSTR("id"));
        CFNumberRef rpm_num = CFDictionaryGetValue(fan, CFSTR("min_rpm"));
        if (!id_num || !rpm_num) {
            fprintf(stderr, "warning: fan entry %ld missing id or min_rpm\n", (long)i);
            continue;
        }

        int fan_id = 0, min_rpm = 0;
        CFNumberGetValue(id_num, kCFNumberIntType, &fan_id);
        CFNumberGetValue(rpm_num, kCFNumberIntType, &min_rpm);

        if (fan_id < 0 || fan_id > 19) {
            fprintf(stderr, "warning: fan id %d out of range (0-19)\n", fan_id);
            continue;
        }
        if (min_rpm < 0 || min_rpm > 10000) {
            fprintf(stderr, "warning: min_rpm %d out of range (0-10000)\n", min_rpm);
            continue;
        }

        /* Build the F{n}Mn key */
        static const char fannum[] = "0123456789ABCDEFGHIJ";
        char key[5];
        snprintf(key, sizeof(key), "F%cMn", fannum[fan_id]);

        /* Read current minimum for logging */
        SMCVal_t cur_val;
        kr = smc_read(conn, key, &cur_val);
        if (kr != kIOReturnSuccess) {
            fprintf(stderr, "error: cannot read key %s (0x%08x)\n", key, kr);
            exit_code = 1;
            continue;
        }

        float current_min = decode_fpe2(cur_val.bytes);

        /* Write new minimum */
        unsigned char fpe2_bytes[2];
        encode_fpe2(min_rpm, fpe2_bytes);

        kr = smc_write(conn, key, fpe2_bytes, 2);
        if (kr != kIOReturnSuccess) {
            fprintf(stderr, "error: cannot write key %s (0x%08x)\n", key, kr);
            exit_code = 1;
            continue;
        }

        fprintf(stderr, "smcfancontrol-daemon: fan %d (%s): min RPM %.0f -> %d\n",
                fan_id, key, current_min, min_rpm);
    }

    IOServiceClose(conn);
    CFRelease(plist);

    if (exit_code == 0)
        fprintf(stderr, "smcfancontrol-daemon: done, all fans configured\n");
    else
        fprintf(stderr, "smcfancontrol-daemon: completed with errors\n");

    return exit_code;
}
