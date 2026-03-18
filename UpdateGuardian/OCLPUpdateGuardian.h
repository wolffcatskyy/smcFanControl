/*
 * OCLPUpdateGuardian.h
 * smcFanControl Community Edition
 *
 * Blocks macOS updates that aren't yet supported by OpenCore Legacy Patcher.
 * One toggle: ON or OFF.
 *
 * Copyright (c) 2026 wolffcatskyy. Licensed under GPL v2.
 */

#import <Foundation/Foundation.h>

@interface OCLPUpdateGuardian : NSObject

+ (instancetype)sharedInstance;

// Is this an OCLP Mac?
@property (nonatomic, readonly) BOOL isOCLPMac;

// The one toggle
@property (nonatomic, assign) BOOL enabled;

// Current state
@property (nonatomic, readonly) NSString *currentMacOSVersion;
@property (nonatomic, readonly) NSString *pendingUpdateVersion;
@property (nonatomic, readonly) BOOL pendingUpdateIsOCLPCompatible;
@property (nonatomic, readonly) NSString *oclpVersion;

// Actions
- (void)checkAndEnforce;
- (void)abortStagedUpdate;

@end
