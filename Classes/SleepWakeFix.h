/*
 *  SleepWakeFix.h
 *
 *  Sleep/Wake Fix for older Intel Macs on modern macOS.
 *  Addresses "Sleep Wake Failure in EFI" panics by disabling
 *  hibernation, standby, autopoweroff, powernap, and proximitywake.
 *
 *  Copyright (c) 2026 smcFanControl Community Edition contributors.
 *  Licensed under the GNU General Public License v2.
 */

#import <Cocoa/Cocoa.h>

@interface SleepWakeFix : NSObject

/// Parse `pmset -g` output and return a dictionary of the five relevant keys.
/// Keys: hibernatemode, standby, autopoweroff, powernap, proximitywake
/// Values: NSNumber (integer) or NSNull if the key was not found.
+ (NSDictionary<NSString *, id> *)currentPmsetSettings;

/// Returns YES if any of the five sleep-related settings are non-zero.
+ (BOOL)needsFix;

/// Creates and shows the Sleep/Wake Fix window.  Intended as the action
/// for the "Sleep/Wake Fix..." menu item.
+ (void)showFixWindowFromMenu:(id)sender;

/// Returns YES if the fix is currently applied (all five settings are zero).
+ (BOOL)isFixApplied;

@end
