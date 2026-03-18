/*
 * OCLPUpdateGuardian.m
 * smcFanControl Community Edition
 *
 * Blocks macOS updates that aren't yet supported by OpenCore Legacy Patcher.
 * One toggle: ON or OFF. Queries OCLP GitHub releases to determine compatibility.
 *
 * Copyright (c) 2026 wolffcatskyy. Licensed under GPL v2.
 */

#import "OCLPUpdateGuardian.h"

// MARK: - Constants

static NSString *const kDortaniaPath = @"/Library/Application Support/Dortania";
static NSString *const kSoftwareUpdateDomain = @"/Library/Preferences/com.apple.SoftwareUpdate";
static NSString *const kOCLPReleasesURL = @"https://api.github.com/repos/dortania/OpenCore-Legacy-Patcher/releases/latest";
static NSString *const kLogFilePath = @"/var/log/oclp-update-guardian.log";
static NSString *const kPrefsKey = @"UpdateGuardianEnabled";
static NSString *const kStagedUpdatesPath = @"/Library/Updates";

// MARK: - Private Interface

@interface OCLPUpdateGuardian ()
@property (nonatomic, strong) NSFileManager *fileManager;
@property (nonatomic, copy) NSString *cachedPendingUpdateVersion;
@property (nonatomic, assign) BOOL cachedPendingUpdateIsOCLPCompatible;
@property (nonatomic, copy) NSString *cachedOCLPVersion;
@end

@implementation OCLPUpdateGuardian

// MARK: - Singleton

+ (instancetype)sharedInstance {
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
    }
    return self;
}

// MARK: - OCLP Detection

- (BOOL)isOCLPMac {
    BOOL isDir = NO;
    return [self.fileManager fileExistsAtPath:kDortaniaPath isDirectory:&isDir] && isDir;
}

// MARK: - Toggle (enabled)

- (BOOL)enabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kPrefsKey];
}

- (void)setEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kPrefsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self log:@"Update Guardian %@", enabled ? @"enabled" : @"disabled"];
}

// MARK: - Current macOS Version

- (NSString *)currentMacOSVersion {
    NSOperatingSystemVersion ver = [NSProcessInfo processInfo].operatingSystemVersion;
    if (ver.patchVersion == 0) {
        return [NSString stringWithFormat:@"%ld.%ld",
                (long)ver.majorVersion, (long)ver.minorVersion];
    }
    return [NSString stringWithFormat:@"%ld.%ld.%ld",
            (long)ver.majorVersion, (long)ver.minorVersion, (long)ver.patchVersion];
}

// MARK: - Pending Update Detection

- (NSString *)pendingUpdateVersion {
    return self.cachedPendingUpdateVersion;
}

- (BOOL)pendingUpdateIsOCLPCompatible {
    return self.cachedPendingUpdateIsOCLPCompatible;
}

- (NSString *)oclpVersion {
    return self.cachedOCLPVersion;
}

- (NSString *)detectPendingUpdate {
    // Method 1: Read SoftwareUpdate preferences for recommended updates
    NSString *plistPath = [NSString stringWithFormat:@"%@.plist", kSoftwareUpdateDomain];
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    NSArray *recommended = prefs[@"RecommendedUpdates"];
    if ([recommended isKindOfClass:[NSArray class]] && recommended.count > 0) {
        NSDictionary *update = recommended.firstObject;
        NSString *version = update[@"Display Version"];
        if (version.length > 0) {
            return version;
        }
    }

    // Method 2: Parse softwareupdate --list output
    NSString *output = [self runTask:@"/usr/sbin/softwareupdate" arguments:@[@"--list"]];
    if (output) {
        NSRegularExpression *regex = [NSRegularExpression
            regularExpressionWithPattern:@"macOS\\s+\\S+\\s+([\\d.]+)"
            options:0 error:nil];
        NSTextCheckingResult *match = [regex firstMatchInString:output
            options:0 range:NSMakeRange(0, output.length)];
        if (match && match.numberOfRanges >= 2) {
            return [output substringWithRange:[match rangeAtIndex:1]];
        }
    }

    return nil;
}

// MARK: - OCLP Compatibility Check

- (BOOL)fetchOCLPSupportsVersion:(NSString *)macOSVersion oclpVersion:(NSString **)outVersion {
    if (!macOSVersion || macOSVersion.length == 0) {
        return NO;
    }

    NSURL *url = [NSURL URLWithString:kOCLPReleasesURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"application/vnd.github.v3+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"smcFanControl-UpdateGuardian/2.0" forHTTPHeaderField:@"User-Agent"];
    request.timeoutInterval = 30;

    __block NSData *responseData = nil;
    __block NSError *responseError = nil;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            responseData = data;
            responseError = error;
            dispatch_semaphore_signal(semaphore);
        }];
    [task resume];
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));

    if (responseError || !responseData) {
        [self log:@"OCLP API request failed: %@", responseError.localizedDescription ?: @"timeout"];
        return NO;
    }

    NSError *jsonError = nil;
    NSDictionary *release = [NSJSONSerialization JSONObjectWithData:responseData
                                                            options:0
                                                              error:&jsonError];
    if (jsonError || ![release isKindOfClass:[NSDictionary class]]) {
        [self log:@"OCLP API returned invalid JSON"];
        return NO;
    }

    NSString *tagName = release[@"tag_name"] ?: release[@"name"] ?: @"Unknown";
    if (outVersion) {
        *outVersion = tagName;
    }

    NSString *body = release[@"body"] ?: @"";
    NSString *name = release[@"name"] ?: @"";
    NSString *combined = [NSString stringWithFormat:@"%@ %@", name, body];

    // Check if the release mentions the macOS version directly (e.g. "15.5")
    if ([combined containsString:macOSVersion]) {
        return YES;
    }

    // Check for "macOS 15.5" pattern
    NSString *macOSPattern = [NSString stringWithFormat:@"macOS %@", macOSVersion];
    if ([combined containsString:macOSPattern]) {
        return YES;
    }

    // Check for support/compatible mentions (case-insensitive)
    NSString *lowerCombined = combined.lowercaseString;
    NSString *supportPattern = [NSString stringWithFormat:@"%@ support", macOSVersion];
    if ([lowerCombined containsString:supportPattern.lowercaseString]) {
        return YES;
    }

    // Check for the major version: if we're on 15.x and update is 15.y,
    // and OCLP mentions "15." anywhere, that's a strong signal
    NSArray<NSString *> *pendingParts = [macOSVersion componentsSeparatedByString:@"."];
    NSArray<NSString *> *currentParts = [self.currentMacOSVersion componentsSeparatedByString:@"."];
    if (pendingParts.count > 0 && currentParts.count > 0 &&
        [pendingParts[0] isEqualToString:currentParts[0]]) {
        // Same major version — minor update. Check if OCLP supports this major at all
        NSString *majorPrefix = [NSString stringWithFormat:@"macOS %@.", pendingParts[0]];
        if ([combined containsString:majorPrefix]) {
            return YES;
        }
    }

    return NO;
}

// MARK: - Core Logic: Check and Enforce

- (void)checkAndEnforce {
    [self log:@"Running check (enabled: %@)", self.enabled ? @"YES" : @"NO"];

    // Detect pending update
    NSString *pending = [self detectPendingUpdate];
    self.cachedPendingUpdateVersion = pending;

    if (!pending) {
        [self log:@"No pending macOS update detected"];
        self.cachedPendingUpdateIsOCLPCompatible = NO;
        self.cachedOCLPVersion = nil;

        // If enabled, still enforce suppression in case macOS re-enabled auto-updates
        if (self.enabled) {
            [self suppressUpdates];
        }
        return;
    }

    [self log:@"Pending update: macOS %@", pending];

    // Check OCLP compatibility
    NSString *oclpVer = nil;
    BOOL compatible = [self fetchOCLPSupportsVersion:pending oclpVersion:&oclpVer];
    self.cachedPendingUpdateIsOCLPCompatible = compatible;
    self.cachedOCLPVersion = oclpVer;

    [self log:@"OCLP %@ — macOS %@ compatibility: %@",
     oclpVer ?: @"(unknown)", pending, compatible ? @"CONFIRMED" : @"NOT CONFIRMED"];

    if (!self.enabled) {
        // Not enabled — remove any overrides we may have set before
        [self restoreDefaults];
        [self log:@"Guardian disabled, restoring default update behavior"];
        return;
    }

    if (compatible) {
        // OCLP supports this update — let it through
        [self restoreDefaults];
        [self log:@"Update is OCLP-compatible, allowing through"];
    } else {
        // OCLP does NOT support this update — block it
        [self suppressUpdates];
        [self log:@"Update is NOT OCLP-compatible, suppressing notifications and downloads"];
    }
}

// MARK: - Suppress / Restore

- (void)suppressUpdates {
    // Disable automatic check and download
    [self runTask:@"/usr/bin/defaults" arguments:@[
        @"write", kSoftwareUpdateDomain,
        @"AutomaticDownload", @"-bool", @"false"
    ]];
    [self runTask:@"/usr/bin/defaults" arguments:@[
        @"write", kSoftwareUpdateDomain,
        @"AutomaticCheckEnabled", @"-bool", @"false"
    ]];

    // Push the notification date far into the future so the badge disappears
    [self runTask:@"/usr/bin/defaults" arguments:@[
        @"write", @"com.apple.SoftwareUpdate",
        @"MajorOSUserNotificationDate", @"-date",
        @"2030-01-01 00:00:00 +0000"
    ]];

    // Clear the System Preferences notification badge
    [self runTask:@"/usr/bin/defaults" arguments:@[
        @"write", @"com.apple.systempreferences",
        @"AttentionPrefBundleIDs", @""
    ]];

    [self log:@"Update notifications suppressed, automatic downloads disabled"];
}

- (void)restoreDefaults {
    // Re-enable automatic check and download
    [self runTask:@"/usr/bin/defaults" arguments:@[
        @"write", kSoftwareUpdateDomain,
        @"AutomaticDownload", @"-bool", @"true"
    ]];
    [self runTask:@"/usr/bin/defaults" arguments:@[
        @"write", kSoftwareUpdateDomain,
        @"AutomaticCheckEnabled", @"-bool", @"true"
    ]];

    // Remove our notification date override
    [self runTask:@"/usr/bin/defaults" arguments:@[
        @"delete", @"com.apple.SoftwareUpdate",
        @"MajorOSUserNotificationDate"
    ]];

    [self log:@"Default update behavior restored"];
}

// MARK: - Abort Staged Update

- (void)abortStagedUpdate {
    [self log:@"Aborting staged update"];

    // Kill the update daemons
    [self runTask:@"/usr/bin/killall" arguments:@[@"softwareupdated"]];
    [self runTask:@"/usr/bin/killall" arguments:@[@"mobileassetd"]];

    // Remove staged update files
    NSInteger removedCount = 0;
    if ([self.fileManager fileExistsAtPath:kStagedUpdatesPath]) {
        NSError *error = nil;
        NSArray<NSString *> *contents = [self.fileManager contentsOfDirectoryAtPath:kStagedUpdatesPath
                                                                              error:&error];
        for (NSString *item in contents) {
            NSString *fullPath = [kStagedUpdatesPath stringByAppendingPathComponent:item];
            NSError *removeError = nil;
            if ([self.fileManager removeItemAtPath:fullPath error:&removeError]) {
                [self log:@"Removed staged file: %@", item];
                removedCount++;
            } else {
                [self log:@"Failed to remove %@: %@", item, removeError.localizedDescription];
            }
        }
    }

    // Also reset the ignored updates list
    [self runTask:@"/usr/sbin/softwareupdate" arguments:@[@"--reset-ignored"]];

    // Suppress notifications again in case they re-appeared
    if (self.enabled) {
        [self suppressUpdates];
    }

    [self log:@"Abort complete — killed daemons, removed %ld staged files", (long)removedCount];
}

// MARK: - Shell Task Execution

- (NSString *)runTask:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments {
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
        return [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
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

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:kLogFilePath];
    if (handle) {
        [handle seekToEndOfFile];
        [handle writeData:[logLine dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    } else {
        [logLine writeToFile:kLogFilePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

@end
