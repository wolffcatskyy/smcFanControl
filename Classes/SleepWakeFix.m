/*
 *  SleepWakeFix.m
 *
 *  Sleep/Wake Fix for older Intel Macs on modern macOS.
 *  Addresses "Sleep Wake Failure in EFI" panics by disabling
 *  hibernation, standby, autopoweroff, powernap, and proximitywake.
 *
 *  Copyright (c) 2026 smcFanControl Community Edition contributors.
 *  Licensed under the GNU General Public License v2.
 */

#import "SleepWakeFix.h"

// The five pmset keys we care about.
static NSArray<NSString *> *SleepWakeKeys(void) {
    return @[@"hibernatemode", @"standby", @"autopoweroff", @"powernap", @"proximitywake"];
}

// Tags for the value labels so we can find them later when refreshing.
enum {
    kTagBase = 9000,  // value labels: 9000..9004
    kTagStatusLabel = 9010,
    kTagFixButton = 9011,
    kTagDeleteCheckbox = 9012,
    kTagUndoButton = 9013,
};

#pragma mark - pmset helpers

@implementation SleepWakeFix

+ (NSDictionary<NSString *, id> *)currentPmsetSettings {
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/pmset"];
    [task setArguments:@[@"-g"]];

    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task setStandardError:[NSPipe pipe]];

    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *e) {
        NSLog(@"SleepWakeFix: failed to run pmset: %@", e);
        NSMutableDictionary *empty = [NSMutableDictionary dictionary];
        for (NSString *key in SleepWakeKeys()) {
            empty[key] = [NSNull null];
        }
        return [empty copy];
    }

    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

    NSMutableDictionary *results = [NSMutableDictionary dictionary];
    for (NSString *key in SleepWakeKeys()) {
        results[key] = [NSNull null];
    }

    // pmset -g output looks like:  " hibernatemode        0\n"
    for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        for (NSString *key in SleepWakeKeys()) {
            if ([trimmed hasPrefix:key]) {
                // Extract the numeric value after the key name.
                NSString *rest = [[trimmed substringFromIndex:key.length]
                                  stringByTrimmingCharactersInSet:
                                  [NSCharacterSet whitespaceAndNewlineCharacterSet]];
                // Take only the first token (value may be followed by a comment).
                NSString *token = [[rest componentsSeparatedByString:@" "] firstObject];
                if (token.length > 0) {
                    results[key] = @([token integerValue]);
                }
            }
        }
    }

    return [results copy];
}

+ (BOOL)needsFix {
    NSDictionary *settings = [self currentPmsetSettings];
    for (NSString *key in SleepWakeKeys()) {
        id val = settings[key];
        if ([val isKindOfClass:[NSNumber class]] && [val integerValue] != 0) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)isFixApplied {
    return ![self needsFix];
}

#pragma mark - Fix application

+ (void)applyFixWithDeleteSleepImage:(BOOL)deleteSleepImage window:(NSWindow *)window {
    // Build the shell command.
    NSMutableString *cmd = [NSMutableString stringWithString:
        @"pmset -a hibernatemode 0"
        @" && pmset -a standby 0"
        @" && pmset -a autopoweroff 0"
        @" && pmset -a powernap 0"
        @" && pmset -a proximitywake 0"];

    if (deleteSleepImage) {
        [cmd appendString:@" && rm -f /var/vm/sleepimage"];
    }

    NSString *script = [NSString stringWithFormat:
        @"do shell script \"%@\" with administrator privileges", cmd];

    NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:script];
    NSDictionary *errorInfo = nil;
    [appleScript executeAndReturnError:&errorInfo];

    if (errorInfo) {
        NSString *errMsg = errorInfo[NSAppleScriptErrorMessage] ?: @"Unknown error";
        // User cancelled the auth dialog — not a real error.
        NSNumber *errNum = errorInfo[NSAppleScriptErrorNumber];
        if (errNum && [errNum integerValue] == -128) {
            return;  // user cancelled
        }
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Sleep/Wake Fix Failed"];
        [alert setInformativeText:errMsg];
        [alert addButtonWithTitle:@"OK"];
        [alert setAlertStyle:NSAlertStyleWarning];
        [alert beginSheetModalForWindow:window completionHandler:nil];
        return;
    }

    // Refresh the window contents.
    [self refreshWindowContents:window];
}

+ (void)undoFixWithWindow:(NSWindow *)window {
    NSString *cmd =
        @"pmset -a hibernatemode 3"
        @" && pmset -a standby 1"
        @" && pmset -a autopoweroff 1"
        @" && pmset -a powernap 1"
        @" && pmset -a proximitywake 1";

    NSString *script = [NSString stringWithFormat:
        @"do shell script \"%@\" with administrator privileges", cmd];

    NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:script];
    NSDictionary *errorInfo = nil;
    [appleScript executeAndReturnError:&errorInfo];

    if (errorInfo) {
        NSNumber *errNum = errorInfo[NSAppleScriptErrorNumber];
        if (errNum && [errNum integerValue] == -128) {
            return;  // user cancelled
        }
        NSString *errMsg = errorInfo[NSAppleScriptErrorMessage] ?: @"Unknown error";
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Restore Defaults Failed"];
        [alert setInformativeText:errMsg];
        [alert addButtonWithTitle:@"OK"];
        [alert setAlertStyle:NSAlertStyleWarning];
        [alert beginSheetModalForWindow:window completionHandler:nil];
        return;
    }

    [self refreshWindowContents:window];
}

#pragma mark - Window UI (programmatic)

+ (void)showFixWindowFromMenu:(id)sender {
    // If the window is already open, just bring it forward.
    for (NSWindow *win in [NSApp windows]) {
        if ([[win title] isEqualToString:@"Sleep/Wake Fix"]) {
            [win makeKeyAndOrderFront:nil];
            [NSApp activateIgnoringOtherApps:YES];
            return;
        }
    }

    // ---- Create the window ----
    NSRect frame = NSMakeRect(0, 0, 460, 430);
    NSUInteger styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:styleMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:@"Sleep/Wake Fix"];
    [window center];
    [window setReleasedWhenClosed:NO];

    NSView *content = [window contentView];
    CGFloat y = frame.size.height - 30;
    CGFloat leftMargin = 20;
    CGFloat contentWidth = frame.size.width - 40;

    // ---- Title ----
    {
        NSTextField *title = [NSTextField labelWithString:@"Sleep/Wake Fix for Intel Macs"];
        [title setFont:[NSFont boldSystemFontOfSize:14]];
        [title setFrame:NSMakeRect(leftMargin, y, contentWidth, 20)];
        [content addSubview:title];
        y -= 28;
    }

    // ---- Explanation (plain English) ----
    {
        NSString *explanation =
            @"Older Intel Macs can crash when waking from sleep due to macOS "
            @"hibernation features designed for newer hardware. This fix disables "
            @"hibernation and related features so your Mac sleeps and wakes reliably.";
        NSTextField *desc = [NSTextField wrappingLabelWithString:explanation];
        [desc setFont:[NSFont systemFontOfSize:11]];
        [desc setFrame:NSMakeRect(leftMargin, y - 42, contentWidth, 48)];
        [content addSubview:desc];
        y -= 58;
    }

    // ---- Reboot info ----
    {
        NSTextField *rebootInfo = [NSTextField labelWithString:
            @"No reboot required. Changes take effect immediately."];
        [rebootInfo setFont:[NSFont systemFontOfSize:11 weight:NSFontWeightMedium]];
        [rebootInfo setTextColor:[NSColor secondaryLabelColor]];
        [rebootInfo setFrame:NSMakeRect(leftMargin, y, contentWidth, 16)];
        [content addSubview:rebootInfo];
        y -= 24;
    }

    // ---- Separator ----
    {
        NSBox *sep = [[NSBox alloc] initWithFrame:NSMakeRect(leftMargin, y, contentWidth, 1)];
        [sep setBoxType:NSBoxSeparator];
        [content addSubview:sep];
        y -= 14;
    }

    // ---- Settings list ----
    NSDictionary *settings = [self currentPmsetSettings];
    NSArray *keys = SleepWakeKeys();

    for (NSUInteger i = 0; i < keys.count; i++) {
        NSString *key = keys[i];
        id val = settings[key];
        NSString *valStr;
        if ([val isKindOfClass:[NSNumber class]]) {
            valStr = [val stringValue];
        } else {
            valStr = @"(not found)";
        }

        // Key label
        NSTextField *keyLabel = [NSTextField labelWithString:
                                 [NSString stringWithFormat:@"%@:", key]];
        [keyLabel setFont:[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]];
        [keyLabel setFrame:NSMakeRect(leftMargin + 10, y, 180, 18)];
        [content addSubview:keyLabel];

        // Value label (tagged for refresh)
        NSTextField *valLabel = [NSTextField labelWithString:valStr];
        [valLabel setFont:[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightMedium]];
        [valLabel setFrame:NSMakeRect(leftMargin + 200, y, 80, 18)];
        [valLabel setTag:kTagBase + (NSInteger)i];

        // Color: green if 0, red if non-zero
        if ([val isKindOfClass:[NSNumber class]] && [val integerValue] == 0) {
            [valLabel setTextColor:[NSColor colorWithCalibratedRed:0.2 green:0.7 blue:0.2 alpha:1.0]];
        } else {
            [valLabel setTextColor:[NSColor colorWithCalibratedRed:0.85 green:0.15 blue:0.15 alpha:1.0]];
        }
        [content addSubview:valLabel];

        y -= 20;
    }

    y -= 8;

    // ---- Status label ----
    {
        BOOL fixed = [self isFixApplied];
        NSString *statusText = fixed
            ? @"Status: Fix Applied  --  All settings are safe"
            : @"Status: Needs Fix  --  Some settings may cause sleep/wake crashes";
        NSTextField *statusLabel = [NSTextField labelWithString:statusText];
        [statusLabel setFont:[NSFont boldSystemFontOfSize:12]];
        [statusLabel setTextColor:fixed
            ? [NSColor colorWithCalibratedRed:0.2 green:0.7 blue:0.2 alpha:1.0]
            : [NSColor colorWithCalibratedRed:0.85 green:0.15 blue:0.15 alpha:1.0]];
        [statusLabel setFrame:NSMakeRect(leftMargin, y, contentWidth, 20)];
        [statusLabel setTag:kTagStatusLabel];
        [content addSubview:statusLabel];
        y -= 30;
    }

    // ---- Delete sleepimage checkbox ----
    {
        NSButton *checkbox = [NSButton checkboxWithTitle:@"Also delete /var/vm/sleepimage to reclaim disk space"
                                                 target:nil action:nil];
        [checkbox setFont:[NSFont systemFontOfSize:11]];
        [checkbox setFrame:NSMakeRect(leftMargin, y, contentWidth, 20)];
        [checkbox setState:NSOnState];
        [checkbox setTag:kTagDeleteCheckbox];
        [content addSubview:checkbox];
        y -= 34;
    }

    // ---- Buttons row: Restore Defaults | Fix Sleep ----
    {
        BOOL fixed = [self isFixApplied];

        // Restore Defaults button (undo)
        NSButton *undoButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin, y, 140, 32)];
        [undoButton setTitle:@"Restore Defaults"];
        [undoButton setBezelStyle:NSBezelStyleRounded];
        [undoButton setTag:kTagUndoButton];
        [undoButton setTarget:self];
        [undoButton setAction:@selector(undoButtonClicked:)];
        [undoButton setEnabled:fixed];  // Only enable if fix is applied
        [content addSubview:undoButton];

        // Fix Sleep button
        NSButton *fixButton = [[NSButton alloc] initWithFrame:NSMakeRect(frame.size.width - 130, y, 110, 32)];
        [fixButton setTitle:@"Fix Sleep"];
        [fixButton setBezelStyle:NSBezelStyleRounded];
        [fixButton setKeyEquivalent:@"\r"];
        [fixButton setTag:kTagFixButton];
        [fixButton setTarget:self];
        [fixButton setAction:@selector(fixButtonClicked:)];
        [fixButton setEnabled:!fixed];  // Only enable if fix is needed
        [content addSubview:fixButton];
    }

    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

#pragma mark - Button action

+ (void)fixButtonClicked:(id)sender {
    NSWindow *window = [(NSView *)sender window];

    // Find the checkbox.
    BOOL deleteSleepImage = NO;
    NSView *checkbox = [[window contentView] viewWithTag:kTagDeleteCheckbox];
    if ([checkbox isKindOfClass:[NSButton class]]) {
        deleteSleepImage = ([(NSButton *)checkbox state] == NSOnState);
    }

    [self applyFixWithDeleteSleepImage:deleteSleepImage window:window];
}

+ (void)undoButtonClicked:(id)sender {
    NSWindow *window = [(NSView *)sender window];
    [self undoFixWithWindow:window];
}

#pragma mark - Refresh after fix

+ (void)refreshWindowContents:(NSWindow *)window {
    NSDictionary *settings = [self currentPmsetSettings];
    NSArray *keys = SleepWakeKeys();
    NSView *content = [window contentView];

    for (NSUInteger i = 0; i < keys.count; i++) {
        NSTextField *valLabel = [content viewWithTag:kTagBase + (NSInteger)i];
        if (!valLabel) continue;

        id val = settings[keys[i]];
        if ([val isKindOfClass:[NSNumber class]]) {
            [valLabel setStringValue:[val stringValue]];
            if ([val integerValue] == 0) {
                [valLabel setTextColor:[NSColor colorWithCalibratedRed:0.2 green:0.7 blue:0.2 alpha:1.0]];
            } else {
                [valLabel setTextColor:[NSColor colorWithCalibratedRed:0.85 green:0.15 blue:0.15 alpha:1.0]];
            }
        } else {
            [valLabel setStringValue:@"(not found)"];
        }
    }

    // Update status label.
    NSTextField *statusLabel = [content viewWithTag:kTagStatusLabel];
    if (statusLabel) {
        BOOL fixed = [self isFixApplied];
        NSString *statusText = fixed
            ? @"Status: Fix Applied  --  All settings are safe"
            : @"Status: Needs Fix  --  Some settings may cause sleep/wake crashes";
        [statusLabel setStringValue:statusText];
        [statusLabel setTextColor:fixed
            ? [NSColor colorWithCalibratedRed:0.2 green:0.7 blue:0.2 alpha:1.0]
            : [NSColor colorWithCalibratedRed:0.85 green:0.15 blue:0.15 alpha:1.0]];

        // Toggle button states: fix enabled when needed, undo enabled when applied.
        NSButton *fixButton = [content viewWithTag:kTagFixButton];
        if ([fixButton isKindOfClass:[NSButton class]]) {
            [fixButton setEnabled:!fixed];
        }
        NSButton *undoButton = [content viewWithTag:kTagUndoButton];
        if ([undoButton isKindOfClass:[NSButton class]]) {
            [undoButton setEnabled:fixed];
        }
    }
}

@end
