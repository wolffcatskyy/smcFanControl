/*
 * OCLPUpdateGuardianCLI.m
 * smcFanControl Community Edition
 *
 * Command-line interface for the OCLP Update Guardian.
 * Run with root privileges for full enforcement.
 *
 * Usage:
 *   updateguardian --status
 *   updateguardian --mode block-all|block-major|allow
 *   updateguardian --check-oclp
 *   updateguardian --reapply
 *
 * Copyright (c) 2026 wolffcatskyy. Licensed under GPL v2.
 */

#import <Foundation/Foundation.h>
#import "OCLPUpdateGuardian.h"

// MARK: - Output Helpers

static void printUsage(void) {
    fprintf(stderr,
        "OCLP Update Guardian - Protects OCLP Macs from incompatible updates\n"
        "\n"
        "Usage:\n"
        "  updateguardian --status          Show current status and pending updates\n"
        "  updateguardian --mode MODE       Set blocking mode:\n"
        "                                     block-all   - Block ALL macOS updates\n"
        "                                     block-major - Block major upgrades only\n"
        "                                     allow       - Allow all updates\n"
        "  updateguardian --check-oclp      Check OCLP compatibility for pending update\n"
        "  updateguardian --reapply         Re-apply current blocking mode\n"
        "  updateguardian --help            Show this help message\n"
        "\n"
        "Run with sudo for full enforcement (manages system preferences,\n"
        "/etc/hosts, and managed configuration profiles).\n"
        "\n"
        "Part of smcFanControl Community Edition\n"
        "https://github.com/wolffcatskyy/smcFanControl\n"
    );
}

static void printStatus(void) {
    OCLPUpdateGuardian *guardian = [OCLPUpdateGuardian sharedGuardian];

    printf("=== OCLP Update Guardian Status ===\n\n");
    printf("%s", [[guardian statusSummary] UTF8String]);

    if (![guardian isOCLPDetected]) {
        printf("\n⚠️  OCLP not detected on this Mac.\n");
        printf("   The guardian works best on OCLP-patched systems.\n");
        printf("   If you believe this is incorrect, check for:\n");
        printf("   - /Library/Application Support/Dortania/\n");
        printf("   - OpenCore variables in NVRAM (nvram -p)\n");
    }
}

static int setMode(NSString *modeStr) {
    OCLPUpdateGuardian *guardian = [OCLPUpdateGuardian sharedGuardian];
    OCLPUpdateMode mode;

    if ([modeStr isEqualToString:@"block-all"]) {
        mode = OCLPUpdateModeBlockAll;
    } else if ([modeStr isEqualToString:@"block-major"]) {
        mode = OCLPUpdateModeBlockMajor;
    } else if ([modeStr isEqualToString:@"allow"]) {
        mode = OCLPUpdateModeAllow;
    } else {
        fprintf(stderr, "Error: Unknown mode '%s'\n", [modeStr UTF8String]);
        fprintf(stderr, "Valid modes: block-all, block-major, allow\n");
        return 1;
    }

    // Warn if not root
    if (geteuid() != 0) {
        fprintf(stderr, "Warning: Not running as root. Some enforcement methods may fail.\n");
        fprintf(stderr, "Run with: sudo updateguardian --mode %s\n\n", [modeStr UTF8String]);
    }

    printf("Setting mode: %s\n", [[guardian descriptionForMode:mode] UTF8String]);

    NSError *error = nil;
    BOOL success = [guardian applyMode:mode error:&error];

    if (success) {
        printf("✅ Mode set successfully: %s\n", [[guardian modeDescription] UTF8String]);
    } else {
        printf("⚠️  Mode set with issues: %s\n", [[error localizedDescription] UTF8String]);
        printf("   Some enforcement methods may not have been applied.\n");
    }

    return success ? 0 : 1;
}

static int checkOCLP(void) {
    OCLPUpdateGuardian *guardian = [OCLPUpdateGuardian sharedGuardian];

    OCLPPendingUpdate *pending = [guardian pendingUpdate];
    if (!pending || !pending.productVersion) {
        printf("No pending macOS update detected.\n");
        printf("Run 'softwareupdate --list' to check for updates manually.\n");
        return 0;
    }

    printf("Pending update: %s %s\n",
           [pending.productName ?: @"macOS" UTF8String],
           [pending.productVersion UTF8String]);

    if (pending.isMajorUpgrade) {
        printf("⚠️  This is a MAJOR version upgrade!\n");
    }

    printf("Checking OCLP compatibility...\n");

    NSString *oclpVersion = nil;
    NSError *error = nil;
    OCLPCompatibilityStatus status = [guardian checkOCLPCompatibilitySyncForVersion:pending.productVersion
                                                                       oclpVersion:&oclpVersion
                                                                             error:&error];

    switch (status) {
        case OCLPCompatibilityConfirmed:
            printf("✅ OCLP %s mentions macOS %s\n",
                   [oclpVersion UTF8String], [pending.productVersion UTF8String]);
            printf("   This update appears to be OCLP-compatible.\n");
            printf("   You may safely update after verifying on https://dortania.github.io\n");
            break;

        case OCLPCompatibilityUnconfirmed:
            printf("❌ OCLP %s does NOT mention macOS %s\n",
                   [oclpVersion UTF8String], [pending.productVersion UTF8String]);
            printf("   This update has NOT been confirmed compatible with OCLP.\n");
            printf("   DO NOT UPDATE until OCLP confirms support.\n");
            if (pending.isMajorUpgrade) {
                printf("   ⚠️  Major upgrades are especially risky for OCLP Macs.\n");
            }
            break;

        case OCLPCompatibilityUnknown:
            printf("⚠️  Could not check OCLP compatibility.\n");
            if (error) {
                printf("   Error: %s\n", [[error localizedDescription] UTF8String]);
            }
            printf("   Check manually at: https://github.com/dortania/OpenCore-Legacy-Patcher/releases\n");
            break;

        case OCLPCompatibilityNoPendingUpdate:
            printf("No pending update to check.\n");
            break;
    }

    return 0;
}

static int reapplyMode(void) {
    OCLPUpdateGuardian *guardian = [OCLPUpdateGuardian sharedGuardian];

    if (geteuid() != 0) {
        fprintf(stderr, "Warning: Not running as root. Some enforcement methods may fail.\n");
        fprintf(stderr, "Run with: sudo updateguardian --reapply\n\n");
    }

    printf("Re-applying current mode: %s\n", [[guardian modeDescription] UTF8String]);

    NSError *error = nil;
    BOOL success = [guardian reapplyCurrentMode:&error];

    if (success) {
        printf("✅ Mode re-applied successfully.\n");
    } else {
        printf("⚠️  Re-apply completed with issues: %s\n",
               [[error localizedDescription] UTF8String]);
    }

    // Also check OCLP compatibility if there's a pending update
    OCLPPendingUpdate *pending = [guardian pendingUpdate];
    if (pending && pending.productVersion) {
        printf("\nChecking OCLP compatibility for pending update %s...\n",
               [pending.productVersion UTF8String]);

        NSString *oclpVersion = nil;
        NSError *oclpError = nil;
        OCLPCompatibilityStatus status = [guardian checkOCLPCompatibilitySyncForVersion:pending.productVersion
                                                                           oclpVersion:&oclpVersion
                                                                                 error:&oclpError];
        if (status == OCLPCompatibilityConfirmed) {
            printf("✅ macOS %s is OCLP-compatible (OCLP %s).\n",
                   [pending.productVersion UTF8String], [oclpVersion UTF8String]);
        } else if (status == OCLPCompatibilityUnconfirmed) {
            printf("❌ macOS %s is NOT yet confirmed OCLP-compatible.\n",
                   [pending.productVersion UTF8String]);
        }
    }

    return success ? 0 : 1;
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

        if ([command isEqualToString:@"--mode"] || [command isEqualToString:@"-m"]) {
            if (args.count < 3) {
                fprintf(stderr, "Error: --mode requires an argument (block-all, block-major, allow)\n");
                return 1;
            }
            return setMode(args[2]);
        }

        if ([command isEqualToString:@"--check-oclp"] || [command isEqualToString:@"-c"]) {
            return checkOCLP();
        }

        if ([command isEqualToString:@"--reapply"] || [command isEqualToString:@"-r"]) {
            return reapplyMode();
        }

        fprintf(stderr, "Unknown command: %s\n", [command UTF8String]);
        printUsage();
        return 1;
    }
}
