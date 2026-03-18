/*
 * OCLPUpdateGuardianCLI.m
 * smcFanControl Community Edition
 *
 * Command-line interface for the OCLP Update Guardian.
 * Simple: --enable, --disable, --status, --check, --abort.
 *
 * Copyright (c) 2026 wolffcatskyy. Licensed under GPL v2.
 */

#import <Foundation/Foundation.h>
#import "OCLPUpdateGuardian.h"

// MARK: - Output Helpers

static void printUsage(void) {
    fprintf(stderr,
        "OCLP Update Guardian - Blocks incompatible macOS updates on OCLP Macs\n"
        "\n"
        "Usage:\n"
        "  updateguardian --status     Show current state\n"
        "  updateguardian --enable     Turn on update protection\n"
        "  updateguardian --disable    Turn off update protection\n"
        "  updateguardian --check      Check OCLP compatibility and enforce now\n"
        "  updateguardian --abort      Abort a staged update (emergency)\n"
        "  updateguardian --help       Show this help message\n"
        "\n"
        "Run with sudo for full enforcement.\n"
        "\n"
        "Part of smcFanControl Community Edition\n"
        "https://github.com/wolffcatskyy/smcFanControl\n"
    );
}

static void printStatus(void) {
    OCLPUpdateGuardian *g = [OCLPUpdateGuardian sharedInstance];

    printf("=== OCLP Update Guardian ===\n\n");
    printf("OCLP Mac:          %s\n", g.isOCLPMac ? "Yes" : "No");
    printf("Guardian:          %s\n", g.enabled ? "ON" : "OFF");
    printf("macOS Version:     %s\n", [g.currentMacOSVersion UTF8String]);

    // Run a check to populate pending update info
    [g checkAndEnforce];

    NSString *pending = g.pendingUpdateVersion;
    if (pending) {
        printf("Pending Update:    macOS %s\n", [pending UTF8String]);
        if (g.oclpVersion) {
            printf("OCLP Version:      %s\n", [g.oclpVersion UTF8String]);
        }
        printf("OCLP Compatible:   %s\n", g.pendingUpdateIsOCLPCompatible ? "Yes" : "No");
    } else {
        printf("Pending Update:    None\n");
    }

    if (!g.isOCLPMac) {
        printf("\nNote: OCLP not detected. The guardian is designed for OCLP-patched Macs.\n");
    }
}

static int doEnable(void) {
    OCLPUpdateGuardian *g = [OCLPUpdateGuardian sharedInstance];

    if (geteuid() != 0) {
        fprintf(stderr, "Warning: Not running as root. Run with: sudo updateguardian --enable\n");
    }

    g.enabled = YES;
    [g checkAndEnforce];
    printf("Update Guardian enabled.\n");

    NSString *pending = g.pendingUpdateVersion;
    if (pending) {
        if (g.pendingUpdateIsOCLPCompatible) {
            printf("Pending update macOS %s is OCLP-compatible — allowed through.\n",
                   [pending UTF8String]);
        } else {
            printf("Pending update macOS %s is NOT OCLP-compatible — blocked.\n",
                   [pending UTF8String]);
        }
    }

    return 0;
}

static int doDisable(void) {
    OCLPUpdateGuardian *g = [OCLPUpdateGuardian sharedInstance];

    if (geteuid() != 0) {
        fprintf(stderr, "Warning: Not running as root. Run with: sudo updateguardian --disable\n");
    }

    g.enabled = NO;
    [g checkAndEnforce];
    printf("Update Guardian disabled. Standard macOS update behavior restored.\n");
    return 0;
}

static int doCheck(void) {
    OCLPUpdateGuardian *g = [OCLPUpdateGuardian sharedInstance];

    if (geteuid() != 0) {
        fprintf(stderr, "Warning: Not running as root. Run with: sudo updateguardian --check\n");
    }

    printf("Checking...\n");
    [g checkAndEnforce];

    NSString *pending = g.pendingUpdateVersion;
    if (!pending) {
        printf("No pending macOS update detected.\n");
        return 0;
    }

    printf("Pending update: macOS %s\n", [pending UTF8String]);
    if (g.oclpVersion) {
        printf("OCLP version:   %s\n", [g.oclpVersion UTF8String]);
    }

    if (g.pendingUpdateIsOCLPCompatible) {
        printf("Status: OCLP-compatible — update allowed.\n");
    } else {
        printf("Status: NOT OCLP-compatible — %s.\n",
               g.enabled ? "update blocked" : "guardian is OFF, not blocking");
    }

    return 0;
}

static int doAbort(void) {
    OCLPUpdateGuardian *g = [OCLPUpdateGuardian sharedInstance];

    if (geteuid() != 0) {
        fprintf(stderr, "Error: --abort requires root. Run with: sudo updateguardian --abort\n");
        return 1;
    }

    printf("Aborting staged update...\n");
    [g abortStagedUpdate];
    printf("Done. Staged update files purged and update daemons killed.\n");
    return 0;
}

// MARK: - Main

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSArray<NSString *> *args = [[NSProcessInfo processInfo] arguments];

        if (args.count < 2) {
            printUsage();
            return 1;
        }

        NSString *command = args[1];

        if ([command isEqualToString:@"--help"] || [command isEqualToString:@"-h"]) {
            printUsage();
            return 0;
        }

        if ([command isEqualToString:@"--status"] || [command isEqualToString:@"-s"]) {
            printStatus();
            return 0;
        }

        if ([command isEqualToString:@"--enable"]) {
            return doEnable();
        }

        if ([command isEqualToString:@"--disable"]) {
            return doDisable();
        }

        if ([command isEqualToString:@"--check"] || [command isEqualToString:@"-c"]) {
            return doCheck();
        }

        if ([command isEqualToString:@"--abort"]) {
            return doAbort();
        }

        fprintf(stderr, "Unknown command: %s\n\n", [command UTF8String]);
        printUsage();
        return 1;
    }
}
