/*
 * OCLPUpdateGuardian.h
 * smcFanControl Community Edition
 *
 * Protects OCLP-patched Macs from installing incompatible macOS updates.
 * Blocks update notifications and automatic downloads using multiple
 * enforcement methods for reliability.
 *
 * Copyright (c) 2026 wolffcatskyy. Licensed under GPL v2.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Update blocking modes
typedef NS_ENUM(NSInteger, OCLPUpdateMode) {
    /// Block ALL macOS updates (major + minor + security)
    OCLPUpdateModeBlockAll = 0,
    /// Block major version upgrades only (e.g. Sequoia -> Tahoe),
    /// allow minor/security updates within current version
    OCLPUpdateModeBlockMajor = 1,
    /// Allow all updates (passthrough, no blocking)
    OCLPUpdateModeAllow = 2
};

/// Describes the result of an OCLP compatibility check
typedef NS_ENUM(NSInteger, OCLPCompatibilityStatus) {
    /// OCLP has not been checked or check failed
    OCLPCompatibilityUnknown = 0,
    /// OCLP latest release mentions the pending update version
    OCLPCompatibilityConfirmed = 1,
    /// OCLP latest release does NOT mention the pending update version
    OCLPCompatibilityUnconfirmed = 2,
    /// No pending update to check
    OCLPCompatibilityNoPendingUpdate = 3
};

/// Information about a pending macOS update
@interface OCLPPendingUpdate : NSObject
@property (nonatomic, copy, nullable) NSString *productName;
@property (nonatomic, copy, nullable) NSString *productVersion;
@property (nonatomic, copy, nullable) NSString *buildVersion;
@property (nonatomic, assign) BOOL isMajorUpgrade;
@end

/// Main guardian class
@interface OCLPUpdateGuardian : NSObject

/// Shared singleton instance
+ (instancetype)sharedGuardian;

// MARK: - OCLP Detection

/// Returns YES if this Mac appears to be running OCLP
- (BOOL)isOCLPDetected;

/// Returns the path to the Dortania support directory, or nil if not found
- (nullable NSString *)dortaniaSupportPath;

/// Returns YES if OpenCore boot-args are present in NVRAM
- (BOOL)hasOpenCoreNVRAM;

// MARK: - macOS Version Info

/// Returns the current macOS version string (e.g. "15.4")
- (NSString *)currentMacOSVersion;

/// Returns the current macOS major version number (e.g. 15)
- (NSInteger)currentMacOSMajorVersion;

/// Returns the current macOS build string (e.g. "24E248")
- (NSString *)currentMacOSBuild;

// MARK: - Pending Update Detection

/// Returns info about any pending macOS update, or nil if none
- (nullable OCLPPendingUpdate *)pendingUpdate;

// MARK: - Update Blocking

/// The currently active blocking mode
@property (nonatomic, assign) OCLPUpdateMode currentMode;

/// Apply the given blocking mode. Returns YES on success.
/// Requires root privileges for full enforcement.
- (BOOL)applyMode:(OCLPUpdateMode)mode error:(NSError *_Nullable *_Nullable)error;

/// Re-apply the current mode (useful when macOS resets preferences)
- (BOOL)reapplyCurrentMode:(NSError *_Nullable *_Nullable)error;

/// Remove all blocking and restore defaults
- (BOOL)removeAllBlocking:(NSError *_Nullable *_Nullable)error;

// MARK: - OCLP Compatibility Check

/// Check if the latest OCLP release supports a given macOS version.
/// Calls the GitHub API asynchronously.
- (void)checkOCLPCompatibilityForVersion:(NSString *)macOSVersion
                              completion:(void (^)(OCLPCompatibilityStatus status,
                                                   NSString *_Nullable oclpVersion,
                                                   NSError *_Nullable error))completion;

/// Synchronous version (blocks current thread, for CLI use)
- (OCLPCompatibilityStatus)checkOCLPCompatibilitySyncForVersion:(NSString *)macOSVersion
                                                    oclpVersion:(NSString *_Nullable *_Nullable)outOCLPVersion
                                                          error:(NSError *_Nullable *_Nullable)error;

// MARK: - Status Reporting

/// Human-readable description of the current mode
- (NSString *)modeDescription;

/// Human-readable status summary
- (NSString *)statusSummary;

/// Path to the preferences plist used by the guardian
+ (NSString *)preferencesPlistPath;

/// Path to the log file
+ (NSString *)logFilePath;

// MARK: - Logging

/// Log a message to the guardian log file
- (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);

@end

NS_ASSUME_NONNULL_END
