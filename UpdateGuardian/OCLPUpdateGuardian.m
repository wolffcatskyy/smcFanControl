/*
 * OCLPUpdateGuardian.m
 * smcFanControl Community Edition
 *
 * Protects OCLP-patched Macs from installing incompatible macOS updates.
 *
 * Copyright (c) 2026 wolffcatskyy. Licensed under GPL v2.
 */

#import "OCLPUpdateGuardian.h"
#include <sys/sysctl.h>

// MARK: - Constants

static NSString *const kGuardianPrefsPath = @"/Library/Preferences/com.wolffcatskyy.updateguardian.plist";
static NSString *const kSoftwareUpdatePrefsPath = @"/Library/Preferences/com.apple.SoftwareUpdate";
static NSString *const kDortaniaPath = @"/Library/Application Support/Dortania";
static NSString *const kHostsFilePath = @"/etc/hosts";
static NSString *const kLogFilePath = @"/var/log/oclp-update-guardian.log";
static NSString *const kManagedPrefsDir = @"/Library/Managed Preferences";
static NSString *const kManagedSoftwareUpdatePlist = @"/Library/Managed Preferences/com.apple.SoftwareUpdate.plist";
static NSString *const kOCLPReleasesURL = @"https://api.github.com/repos/dortania/OpenCore-Legacy-Patcher/releases/latest";
static NSString *const kHostsBlockMarkerBegin = @"# BEGIN OCLP Update Guardian";
static NSString *const kHostsBlockMarkerEnd = @"# END OCLP Update Guardian";
static NSString *const kPrefsKeyMode = @"UpdateBlockingMode";
static NSString *const kStagedUpdatesPath = @"/Library/Updates";

// Apple update servers to block
static NSArray<NSString *> *AppleUpdateHosts(void) {
    return @[
        @"gdmf.apple.com",
        @"mesu.apple.com",
        @"swscan.apple.com",
        @"swdist.apple.com",
        @"swdownload.apple.com",
        @"updates.cdn-apple.com",
        @"xp.apple.com"
    ];
}

// MARK: - OCLPPendingUpdate

@implementation OCLPPendingUpdate
- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %@ %@ (%@) major=%@>",
            NSStringFromClass([self class]),
            self.productName ?: @"Unknown",
            self.productVersion ?: @"Unknown",
            self.buildVersion ?: @"Unknown",
            self.isMajorUpgrade ? @"YES" : @"NO"];
}
@end

// MARK: - OCLPUpdateGuardian

@interface OCLPUpdateGuardian ()
@property (nonatomic, strong) NSFileManager *fileManager;
@end

@implementation OCLPUpdateGuardian

+ (instancetype)sharedGuardian {
    static OCLPUpdateGuardian *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[OCLPUpdateGuardian alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _fileManager = [NSFileManager defaultManager];
        _currentMode = [self loadSavedMode];
    }
    return self;
}

// MARK: - Preferences Persistence

- (OCLPUpdateMode)loadSavedMode {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kGuardianPrefsPath];
    if (prefs && prefs[kPrefsKeyMode]) {
        NSInteger mode = [prefs[kPrefsKeyMode] integerValue];
        if (mode >= OCLPUpdateModeBlockAll && mode <= OCLPUpdateModeAllow) {
            return (OCLPUpdateMode)mode;
        }
    }
    return OCLPUpdateModeBlockMajor; // Safe default for OCLP Macs
}

- (BOOL)saveModePreference:(OCLPUpdateMode)mode {
    NSDictionary *prefs = @{ kPrefsKeyMode: @(mode) };
    return [prefs writeToFile:kGuardianPrefsPath atomically:YES];
}

// MARK: - OCLP Detection

- (BOOL)isOCLPDetected {
    return ([self dortaniaSupportPath] != nil) || [self hasOpenCoreNVRAM];
}

- (nullable NSString *)dortaniaSupportPath {
    BOOL isDir = NO;
    if ([self.fileManager fileExistsAtPath:kDortaniaPath isDirectory:&isDir] && isDir) {
        return kDortaniaPath;
    }
    return nil;
}

- (BOOL)hasOpenCoreNVRAM {
    // Check NVRAM for OpenCore boot-args or csr-active-config
    NSString *output = [self runTask:@"/usr/sbin/nvram" arguments:@[@"-p"]];
    if (!output) return NO;

    // OpenCore sets various NVRAM variables
    if ([output containsString:@"4D1FDA02-38C7-4A6A-9CC6"]) return YES; // OpenCore GUID
    if ([output containsString:@"revpatch="]) return YES;
    if ([output containsString:@"revblock="]) return YES;
    if ([output containsString:@"amfi_get_out_of_my_way"]) return YES;

    // Check for Dortania-specific boot-args
    if ([output containsString:@"-lilubetaall"]) return YES;

    return NO;
}

// MARK: - macOS Version Info

- (NSString *)currentMacOSVersion {
    NSProcessInfo *info = [NSProcessInfo processInfo];
    NSOperatingSystemVersion ver = info.operatingSystemVersion;
    return [NSString stringWithFormat:@"%ld.%ld.%ld",
            (long)ver.majorVersion, (long)ver.minorVersion, (long)ver.patchVersion];
}

- (NSInteger)currentMacOSMajorVersion {
    return [NSProcessInfo processInfo].operatingSystemVersion.majorVersion;
}

- (NSString *)currentMacOSBuild {
    char buf[64] = {0};
    size_t len = sizeof(buf);
    if (sysctlbyname("kern.osversion", buf, &len, NULL, 0) == 0) {
        return [NSString stringWithUTF8String:buf];
    }
    return @"Unknown";
}

// MARK: - Pending Update Detection

- (nullable OCLPPendingUpdate *)pendingUpdate {
    // Method 1: Check SoftwareUpdate preferences for recommended updates
    NSDictionary *suPrefs = [self readSoftwareUpdatePrefs];
    NSArray *recommended = suPrefs[@"RecommendedUpdates"];
    if ([recommended isKindOfClass:[NSArray class]] && recommended.count > 0) {
        NSDictionary *update = recommended.firstObject;
        OCLPPendingUpdate *pending = [[OCLPPendingUpdate alloc] init];
        pending.productName = update[@"Display Name"] ?: update[@"Product Key"];
        pending.productVersion = update[@"Display Version"];
        pending.buildVersion = update[@"Build Version"];
        pending.isMajorUpgrade = [self isMajorUpgradeVersion:pending.productVersion];
        return pending;
    }

    // Method 2: Run softwareupdate --list and parse output
    NSString *output = [self runTask:@"/usr/sbin/softwareupdate" arguments:@[@"--list"]];
    if (output) {
        return [self parseUpdateListOutput:output];
    }

    return nil;
}

- (nullable OCLPPendingUpdate *)parseUpdateListOutput:(NSString *)output {
    // Parse lines like: "* Label: macOS Sequoia 15.5"
    // or "* Label: macOS Tahoe 16.0"
    NSArray<NSString *> *lines = [output componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed hasPrefix:@"* Label: macOS"] || [trimmed hasPrefix:@"Label: macOS"]) {
            OCLPPendingUpdate *pending = [[OCLPPendingUpdate alloc] init];

            // Extract version from label like "macOS Sequoia 15.5"
            NSRegularExpression *regex = [NSRegularExpression
                regularExpressionWithPattern:@"macOS\\s+(\\S+)\\s+([\\d.]+)"
                options:0 error:nil];
            NSTextCheckingResult *match = [regex firstMatchInString:trimmed
                options:0 range:NSMakeRange(0, trimmed.length)];
            if (match && match.numberOfRanges >= 3) {
                pending.productName = [NSString stringWithFormat:@"macOS %@",
                    [trimmed substringWithRange:[match rangeAtIndex:1]]];
                pending.productVersion = [trimmed substringWithRange:[match rangeAtIndex:2]];
                pending.isMajorUpgrade = [self isMajorUpgradeVersion:pending.productVersion];
                return pending;
            }
        }
    }
    return nil;
}

- (BOOL)isMajorUpgradeVersion:(nullable NSString *)version {
    if (!version) return NO;
    NSArray<NSString *> *components = [version componentsSeparatedByString:@"."];
    if (components.count == 0) return NO;
    NSInteger majorVersion = [components[0] integerValue];
    return majorVersion > [self currentMacOSMajorVersion];
}

- (NSDictionary *)readSoftwareUpdatePrefs {
    NSString *output = [self runTask:@"/usr/bin/defaults"
                           arguments:@[@"read", kSoftwareUpdatePrefsPath]];
    if (!output) return @{};

    // Parse the defaults output - for structured data, read the plist directly
    NSString *plistPath = [NSString stringWithFormat:@"%@.plist", kSoftwareUpdatePrefsPath];
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    return prefs ?: @{};
}

// MARK: - Update Blocking

- (BOOL)applyMode:(OCLPUpdateMode)mode error:(NSError *_Nullable *_Nullable)error {
    [self log:@"Applying update blocking mode: %@", [self descriptionForMode:mode]];

    BOOL success = YES;
    NSMutableArray<NSString *> *errors = [NSMutableArray array];

    // Step 1: Apply managed software update preferences
    if (![self applySoftwareUpdatePreferences:mode]) {
        [errors addObject:@"Failed to set SoftwareUpdate preferences"];
        success = NO;
    }

    // Step 2: Apply managed preferences profile (for major version blocking)
    if (![self applyManagedPreferences:mode]) {
        [errors addObject:@"Failed to set managed preferences"];
        // Non-fatal: other methods provide backup
    }

    // Step 3: Manage /etc/hosts entries
    if (![self applyHostsBlocking:mode]) {
        [errors addObject:@"Failed to update /etc/hosts"];
        // Non-fatal: other methods provide backup
    }

    // Step 4: Dismiss pending updates if blocking
    if (mode != OCLPUpdateModeAllow) {
        [self dismissPendingUpdates];
    }

    // Save the mode preference
    self.currentMode = mode;
    [self saveModePreference:mode];

    if (errors.count > 0 && error) {
        *error = [NSError errorWithDomain:@"com.wolffcatskyy.updateguardian"
                                     code:1
                                 userInfo:@{
            NSLocalizedDescriptionKey: [errors componentsJoinedByString:@"; "]
        }];
    }

    [self log:@"Mode applied: %@ (issues: %lu)",
     [self descriptionForMode:mode], (unsigned long)errors.count];
    return success;
}

- (BOOL)reapplyCurrentMode:(NSError *_Nullable *_Nullable)error {
    [self log:@"Re-applying current mode: %@", [self descriptionForMode:self.currentMode]];
    return [self applyMode:self.currentMode error:error];
}

- (BOOL)removeAllBlocking:(NSError *_Nullable *_Nullable)error {
    [self log:@"Removing all update blocking"];

    // Restore SoftwareUpdate preferences to defaults
    [self runTask:@"/usr/bin/defaults" arguments:@[
        @"write", kSoftwareUpdatePrefsPath,
        @"AutomaticCheckEnabled", @"-bool", @"true"
    ]];
    [self runTask:@"/usr/bin/defaults" arguments:@[
        @"write", kSoftwareUpdatePrefsPath,
        @"AutomaticDownload", @"-bool", @"true"
    ]];
    [self runTask:@"/usr/bin/defaults" arguments:@[
        @"write", kSoftwareUpdatePrefsPath,
        @"AutomaticallyInstallMacOSUpdates", @"-bool", @"true"
    ]];
    [self runTask:@"/usr/bin/defaults" arguments:@[
        @"write", kSoftwareUpdatePrefsPath,
        @"CriticalUpdateInstall", @"-bool", @"true"
    ]];

    // Remove managed preferences
    [self removeManagedPreferences];

    // Remove hosts entries
    [self removeHostsBlocking];

    // Update stored mode
    self.currentMode = OCLPUpdateModeAllow;
    [self saveModePreference:OCLPUpdateModeAllow];

    [self log:@"All blocking removed"];
    return YES;
}

// MARK: - Software Update Preferences

- (BOOL)applySoftwareUpdatePreferences:(OCLPUpdateMode)mode {
    switch (mode) {
        case OCLPUpdateModeBlockAll: {
            // Disable all automatic update behavior
            BOOL ok = YES;
            ok &= [self writeDefaultsBool:NO forKey:@"AutomaticCheckEnabled"];
            ok &= [self writeDefaultsBool:NO forKey:@"AutomaticDownload"];
            ok &= [self writeDefaultsBool:NO forKey:@"AutomaticallyInstallMacOSUpdates"];
            ok &= [self writeDefaultsBool:NO forKey:@"CriticalUpdateInstall"];
            ok &= [self writeDefaultsBool:NO forKey:@"ConfigDataInstall"];
            return ok;
        }
        case OCLPUpdateModeBlockMajor: {
            // Allow automatic checks and security updates, but block auto-install of macOS upgrades
            BOOL ok = YES;
            ok &= [self writeDefaultsBool:YES forKey:@"AutomaticCheckEnabled"];
            ok &= [self writeDefaultsBool:NO forKey:@"AutomaticDownload"];
            ok &= [self writeDefaultsBool:NO forKey:@"AutomaticallyInstallMacOSUpdates"];
            ok &= [self writeDefaultsBool:YES forKey:@"CriticalUpdateInstall"];
            ok &= [self writeDefaultsBool:YES forKey:@"ConfigDataInstall"];
            return ok;
        }
        case OCLPUpdateModeAllow: {
            // Restore normal update behavior
            BOOL ok = YES;
            ok &= [self writeDefaultsBool:YES forKey:@"AutomaticCheckEnabled"];
            ok &= [self writeDefaultsBool:YES forKey:@"AutomaticDownload"];
            ok &= [self writeDefaultsBool:YES forKey:@"AutomaticallyInstallMacOSUpdates"];
            ok &= [self writeDefaultsBool:YES forKey:@"CriticalUpdateInstall"];
            ok &= [self writeDefaultsBool:YES forKey:@"ConfigDataInstall"];
            return ok;
        }
    }
    return NO;
}

- (BOOL)writeDefaultsBool:(BOOL)value forKey:(NSString *)key {
    NSString *boolStr = value ? @"true" : @"false";
    NSString *output = [self runTask:@"/usr/bin/defaults"
                           arguments:@[@"write", kSoftwareUpdatePrefsPath, key,
                                       @"-bool", boolStr]];
    // defaults returns empty string on success, nil on failure
    return output != nil;
}

// MARK: - Managed Preferences (Configuration Profile Approach)

- (BOOL)applyManagedPreferences:(OCLPUpdateMode)mode {
    switch (mode) {
        case OCLPUpdateModeBlockAll: {
            // Write managed preference that blocks all updates
            return [self writeManagedPreferenceBlockingAboveVersion:@"0"];
        }
        case OCLPUpdateModeBlockMajor: {
            // Block anything above current major version
            NSString *currentMajor = [NSString stringWithFormat:@"%ld",
                                      (long)[self currentMacOSMajorVersion]];
            return [self writeManagedPreferenceBlockingAboveVersion:currentMajor];
        }
        case OCLPUpdateModeAllow: {
            // Remove managed preference restrictions
            return [self removeManagedPreferences];
        }
    }
    return NO;
}

- (BOOL)writeManagedPreferenceBlockingAboveVersion:(NSString *)maxMajorVersion {
    // Ensure the managed preferences directory exists
    NSError *dirError = nil;
    if (![self.fileManager fileExistsAtPath:kManagedPrefsDir]) {
        [self.fileManager createDirectoryAtPath:kManagedPrefsDir
                    withIntermediateDirectories:YES
                                     attributes:@{
            NSFilePosixPermissions: @0755,
            NSFileOwnerAccountID: @0,
            NSFileGroupOwnerAccountID: @0
        } error:&dirError];
        if (dirError) {
            [self log:@"Failed to create managed prefs dir: %@", dirError];
            return NO;
        }
    }

    // Build the managed preferences dictionary
    // MajorOSUserVisibleVersion restricts the maximum macOS version shown in Software Update
    NSDictionary *managedPrefs;

    if ([maxMajorVersion isEqualToString:@"0"]) {
        // Block all: disable automatic checking entirely at the managed level
        managedPrefs = @{
            @"AutomaticCheckEnabled": @NO,
            @"AutomaticDownload": @NO,
            @"AutomaticallyInstallMacOSUpdates": @NO,
            @"CriticalUpdateInstall": @NO
        };
    } else {
        // Block major: restrict max visible version
        managedPrefs = @{
            @"MajorOSUserVisibleVersion": maxMajorVersion,
            @"AutomaticallyInstallMacOSUpdates": @NO,
            @"AutomaticDownload": @NO
        };
    }

    BOOL written = [managedPrefs writeToFile:kManagedSoftwareUpdatePlist atomically:YES];
    if (written) {
        // Set proper ownership (root:wheel) and permissions
        NSDictionary *attrs = @{
            NSFilePosixPermissions: @0644
        };
        [self.fileManager setAttributes:attrs ofItemAtPath:kManagedSoftwareUpdatePlist error:nil];
        [self runTask:@"/usr/sbin/chown" arguments:@[@"root:wheel", kManagedSoftwareUpdatePlist]];
        [self log:@"Wrote managed preferences (max version: %@)", maxMajorVersion];
    }
    return written;
}

- (BOOL)removeManagedPreferences {
    if ([self.fileManager fileExistsAtPath:kManagedSoftwareUpdatePlist]) {
        NSError *removeError = nil;
        [self.fileManager removeItemAtPath:kManagedSoftwareUpdatePlist error:&removeError];
        if (removeError) {
            [self log:@"Failed to remove managed prefs: %@", removeError];
            return NO;
        }
        [self log:@"Removed managed preferences"];
    }
    return YES;
}

// MARK: - /etc/hosts Blocking

- (BOOL)applyHostsBlocking:(OCLPUpdateMode)mode {
    // First remove any existing guardian entries
    [self removeHostsBlocking];

    if (mode != OCLPUpdateModeBlockAll) {
        // Only block hosts in BlockAll mode
        return YES;
    }

    // Read current hosts file
    NSError *readError = nil;
    NSString *hosts = [NSString stringWithContentsOfFile:kHostsFilePath
                                               encoding:NSUTF8StringEncoding
                                                  error:&readError];
    if (!hosts) {
        [self log:@"Failed to read /etc/hosts: %@", readError];
        return NO;
    }

    // Build the block entries
    NSMutableString *blockEntries = [NSMutableString string];
    [blockEntries appendFormat:@"\n%@\n", kHostsBlockMarkerBegin];
    [blockEntries appendString:@"# Blocks Apple update servers to prevent automatic macOS updates\n"];
    [blockEntries appendString:@"# Managed by OCLP Update Guardian - do not edit manually\n"];
    for (NSString *host in AppleUpdateHosts()) {
        [blockEntries appendFormat:@"0.0.0.0 %@\n", host];
    }
    [blockEntries appendFormat:@"%@\n", kHostsBlockMarkerEnd];

    // Append to hosts file
    NSString *newHosts = [hosts stringByAppendingString:blockEntries];
    NSError *writeError = nil;
    BOOL written = [newHosts writeToFile:kHostsFilePath
                              atomically:YES
                                encoding:NSUTF8StringEncoding
                                   error:&writeError];
    if (!written) {
        [self log:@"Failed to write /etc/hosts: %@", writeError];
        return NO;
    }

    // Flush DNS cache
    [self runTask:@"/usr/bin/dscacheutil" arguments:@[@"-flushcache"]];
    [self runTask:@"/usr/bin/killall" arguments:@[@"-HUP", @"mDNSResponder"]];

    [self log:@"Applied hosts blocking for %lu servers", (unsigned long)AppleUpdateHosts().count];
    return YES;
}

- (BOOL)removeHostsBlocking {
    NSError *readError = nil;
    NSString *hosts = [NSString stringWithContentsOfFile:kHostsFilePath
                                               encoding:NSUTF8StringEncoding
                                                  error:&readError];
    if (!hosts) return NO;

    // Remove everything between our markers (inclusive)
    NSRange beginRange = [hosts rangeOfString:kHostsBlockMarkerBegin];
    NSRange endRange = [hosts rangeOfString:kHostsBlockMarkerEnd];

    if (beginRange.location == NSNotFound || endRange.location == NSNotFound) {
        return YES; // Nothing to remove
    }

    NSRange fullRange = NSMakeRange(beginRange.location,
                                    NSMaxRange(endRange) - beginRange.location);

    // Also remove trailing newline if present
    if (NSMaxRange(fullRange) < hosts.length &&
        [hosts characterAtIndex:NSMaxRange(fullRange)] == '\n') {
        fullRange.length += 1;
    }

    NSString *cleanedHosts = [hosts stringByReplacingCharactersInRange:fullRange withString:@""];

    NSError *writeError = nil;
    BOOL written = [cleanedHosts writeToFile:kHostsFilePath
                                  atomically:YES
                                    encoding:NSUTF8StringEncoding
                                       error:&writeError];
    if (written) {
        // Flush DNS cache after removing blocks
        [self runTask:@"/usr/bin/dscacheutil" arguments:@[@"-flushcache"]];
        [self runTask:@"/usr/bin/killall" arguments:@[@"-HUP", @"mDNSResponder"]];
    }
    return written;
}

// MARK: - Dismiss Pending Updates

- (void)dismissPendingUpdates {
    // Reset ignored updates list
    [self runTask:@"/usr/sbin/softwareupdate" arguments:@[@"--reset-ignored"]];

    // Remove staged update downloads
    if ([self.fileManager fileExistsAtPath:kStagedUpdatesPath]) {
        NSError *error = nil;
        NSArray<NSString *> *contents = [self.fileManager contentsOfDirectoryAtPath:kStagedUpdatesPath
                                                                              error:&error];
        for (NSString *item in contents) {
            NSString *fullPath = [kStagedUpdatesPath stringByAppendingPathComponent:item];
            [self.fileManager removeItemAtPath:fullPath error:nil];
            [self log:@"Removed staged update: %@", item];
        }
    }

    // Clear the Software Update notification badge
    [self runTask:@"/usr/bin/defaults" arguments:@[
        @"write", @"com.apple.systempreferences",
        @"AttentionPrefBundleIDs", @""
    ]];

    [self log:@"Dismissed pending updates"];
}

// MARK: - OCLP Compatibility Check

- (void)checkOCLPCompatibilityForVersion:(NSString *)macOSVersion
                              completion:(void (^)(OCLPCompatibilityStatus status,
                                                   NSString *_Nullable oclpVersion,
                                                   NSError *_Nullable error))completion {
    if (!macOSVersion || macOSVersion.length == 0) {
        completion(OCLPCompatibilityNoPendingUpdate, nil, nil);
        return;
    }

    NSURL *url = [NSURL URLWithString:kOCLPReleasesURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"application/vnd.github.v3+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"smcFanControl-UpdateGuardian/1.0" forHTTPHeaderField:@"User-Agent"];
    request.timeoutInterval = 30;

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                completion(OCLPCompatibilityUnknown, nil, error);
                return;
            }

            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode != 200) {
                NSError *httpError = [NSError errorWithDomain:@"com.wolffcatskyy.updateguardian"
                    code:httpResponse.statusCode
                    userInfo:@{
                        NSLocalizedDescriptionKey:
                            [NSString stringWithFormat:@"GitHub API returned HTTP %ld",
                             (long)httpResponse.statusCode]
                    }];
                completion(OCLPCompatibilityUnknown, nil, httpError);
                return;
            }

            NSError *jsonError = nil;
            NSDictionary *release = [NSJSONSerialization JSONObjectWithData:data
                                                                   options:0
                                                                     error:&jsonError];
            if (jsonError || ![release isKindOfClass:[NSDictionary class]]) {
                completion(OCLPCompatibilityUnknown, nil,
                           jsonError ?: [NSError errorWithDomain:@"com.wolffcatskyy.updateguardian"
                                                            code:2
                                                        userInfo:@{
                    NSLocalizedDescriptionKey: @"Invalid JSON from GitHub API"
                }]);
                return;
            }

            NSString *oclpVersion = release[@"tag_name"] ?: release[@"name"] ?: @"Unknown";
            NSString *body = release[@"body"] ?: @"";
            NSString *name = release[@"name"] ?: @"";

            // Check if the release notes mention the macOS version
            // Look for the version number (e.g. "15.5", "16.0")
            BOOL versionMentioned = NO;
            if ([body containsString:macOSVersion] || [name containsString:macOSVersion]) {
                versionMentioned = YES;
            }

            // Also check for the macOS major version name mapping
            // e.g., "Sequoia 15.5" or just "15.5 support"
            NSString *searchTerm = [NSString stringWithFormat:@"%@ support", macOSVersion];
            if ([body.lowercaseString containsString:searchTerm.lowercaseString]) {
                versionMentioned = YES;
            }

            // Check for "compatible with" or "tested on" patterns
            NSString *compatPattern = [NSString stringWithFormat:@"macOS %@", macOSVersion];
            if ([body containsString:compatPattern]) {
                versionMentioned = YES;
            }

            OCLPCompatibilityStatus status = versionMentioned
                ? OCLPCompatibilityConfirmed
                : OCLPCompatibilityUnconfirmed;

            completion(status, oclpVersion, nil);
        }];
    [task resume];
}

- (OCLPCompatibilityStatus)checkOCLPCompatibilitySyncForVersion:(NSString *)macOSVersion
                                                    oclpVersion:(NSString *_Nullable *_Nullable)outOCLPVersion
                                                          error:(NSError *_Nullable *_Nullable)outError {
    __block OCLPCompatibilityStatus result = OCLPCompatibilityUnknown;
    __block NSString *version = nil;
    __block NSError *err = nil;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    [self checkOCLPCompatibilityForVersion:macOSVersion
                                completion:^(OCLPCompatibilityStatus status,
                                             NSString *oclpVersion,
                                             NSError *error) {
        result = status;
        version = oclpVersion;
        err = error;
        dispatch_semaphore_signal(semaphore);
    }];

    // Wait up to 30 seconds
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));

    if (outOCLPVersion) *outOCLPVersion = version;
    if (outError) *outError = err;
    return result;
}

// MARK: - Status Reporting

- (NSString *)modeDescription {
    return [self descriptionForMode:self.currentMode];
}

- (NSString *)descriptionForMode:(OCLPUpdateMode)mode {
    switch (mode) {
        case OCLPUpdateModeBlockAll:   return @"Block All Updates";
        case OCLPUpdateModeBlockMajor: return @"Block Major Upgrades Only";
        case OCLPUpdateModeAllow:      return @"Allow All Updates";
    }
    return @"Unknown";
}

- (NSString *)statusSummary {
    NSMutableString *summary = [NSMutableString string];

    // OCLP status
    BOOL isOCLP = [self isOCLPDetected];
    [summary appendFormat:@"OCLP Detected: %@\n", isOCLP ? @"Yes" : @"No"];

    // Current macOS
    [summary appendFormat:@"macOS Version: %@ (%@)\n",
     [self currentMacOSVersion], [self currentMacOSBuild]];

    // Current mode
    [summary appendFormat:@"Blocking Mode: %@\n", [self modeDescription]];

    // Pending update
    OCLPPendingUpdate *pending = [self pendingUpdate];
    if (pending) {
        [summary appendFormat:@"Pending Update: %@ %@%@\n",
         pending.productName ?: @"Unknown",
         pending.productVersion ?: @"Unknown",
         pending.isMajorUpgrade ? @" (MAJOR UPGRADE)" : @""];
    } else {
        [summary appendString:@"Pending Update: None detected\n"];
    }

    // Hosts blocking
    NSString *hosts = [NSString stringWithContentsOfFile:kHostsFilePath
                                               encoding:NSUTF8StringEncoding
                                                  error:nil];
    BOOL hostsBlocking = hosts && [hosts containsString:kHostsBlockMarkerBegin];
    [summary appendFormat:@"Hosts Blocking: %@\n", hostsBlocking ? @"Active" : @"Inactive"];

    // Managed preferences
    BOOL managedPrefs = [self.fileManager fileExistsAtPath:kManagedSoftwareUpdatePlist];
    [summary appendFormat:@"Managed Preferences: %@\n", managedPrefs ? @"Active" : @"Inactive"];

    return summary;
}

+ (NSString *)preferencesPlistPath {
    return kGuardianPrefsPath;
}

+ (NSString *)logFilePath {
    return kLogFilePath;
}

// MARK: - Shell Task Execution

- (nullable NSString *)runTask:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments {
    @try {
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = launchPath;
        task.arguments = arguments;

        NSPipe *stdoutPipe = [NSPipe pipe];
        NSPipe *stderrPipe = [NSPipe pipe];
        task.standardOutput = stdoutPipe;
        task.standardError = stderrPipe;

        [task launch];
        [task waitUntilExit];

        NSData *outputData = [stdoutPipe.fileHandleForReading readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
        return output;
    } @catch (NSException *exception) {
        [self log:@"Task exception (%@): %@", launchPath, exception.reason];
        return nil;
    }
}

// MARK: - Logging

- (void)log:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *timestamp = [fmt stringFromDate:[NSDate date]];

    NSString *logLine = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];

    // Append to log file
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:kLogFilePath];
    if (handle) {
        [handle seekToEndOfFile];
        [handle writeData:[logLine dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    } else {
        // Create the log file
        [logLine writeToFile:kLogFilePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

@end
