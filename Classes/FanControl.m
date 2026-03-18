/*
 *	FanControl
 *
 *	Copyright (c) 2006-2012 Hendrik Holtmann
 *  Portions Copyright (c) 2013 Michael Wilber
 *
 *	FanControl.m - MacBook(Pro) FanControl application
 *
 *	This program is free software; you can redistribute it and/or modify
 *	it under the terms of the GNU General Public License as published by
 *	the Free Software Foundation; either version 2 of the License, or
 *	(at your option) any later version.
 *
 *	This program is distributed in the hope that it will be useful,
 *	but WITHOUT ANY WARRANTY; without even the implied warranty of
 *	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *	GNU General Public License for more details.
 *
 *	You should have received a copy of the GNU General Public License
 *	along with this program; if not, write to the Free Software
 *	Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */
 

#import "FanControl.h"
#import "MachineDefaults.h"
#import "SleepWakeFix.h"
#import "OCLPHelper.h"
#import <Security/Authorization.h>
#import <Security/AuthorizationDB.h>
#import <Security/AuthorizationTags.h>
// Sparkle removed — dead update server (eidac.de), will add GitHub-based updates later

@interface FanControl ()
+ (void)copyMachinesIfNecessary;
+ (void)terminateIfNoFans;
@property (NS_NONATOMIC_IOSONLY, getter=isInAutoStart, readonly) BOOL inAutoStart;
- (void)setStartAtLogin:(BOOL)enabled;
+ (BOOL)smcBinaryHasCorrectPermissions;
+ (void)checkRightStatus:(OSStatus)status;
@end

@implementation FanControl

// Number of fans reported by the hardware.
int g_numFans = 0;


NSUserDefaults *defaults;

#pragma mark **Init-Methods**

+(void) initialize {
    
	//avoid Zombies when starting external app
	signal(SIGCHLD, SIG_IGN);

	//check owner and suid rights
	[FanControl setRights];

	//talk to smc
	[smcWrapper init];

	[FanControl terminateIfNoFans];

	[FanControl copyMachinesIfNecessary];

	//app in foreground for update notifications
	[[NSApplication sharedApplication] activateIgnoringOtherApps:YES];

}

+(void) terminateIfNoFans {
    int fan_num = [smcWrapper get_fan_num];
    if (fan_num <= 0) {
        NSLog(@"Exiting as %d fans were detected for Model Identifier: %@", fan_num, [MachineDefaults computerModel]);
        [[NSApplication sharedApplication] terminate:self];
    }
}

+(void)copyMachinesIfNecessary
{
    NSString *path = [[[NSFileManager defaultManager] applicationSupportDirectory] stringByAppendingPathComponent:@"Machines.plist"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] copyItemAtPath:[[NSBundle mainBundle] pathForResource:@"Machines" ofType:@"plist"] toPath:path error:nil];
    }
}

-(void)upgradeFavorites
{
	//upgrade favorites
	NSArray *rfavorites = [FavoritesController arrangedObjects];
	int j;
	int i;
	for (i=0;i<[rfavorites count];i++)
	{
		BOOL selected = NO;
		NSArray *fans = rfavorites[i][PREF_FAN_ARRAY];
		for (j=0;j<[fans count];j++) {
			if ([fans[j][PREF_FAN_SHOWMENU] boolValue] == YES ) {
				selected = YES;
			}
		}
		if (selected==NO) {
			rfavorites[i][PREF_FAN_ARRAY][0][PREF_FAN_SHOWMENU] = @YES;
		}
	}
	
}

-(void) awakeFromNib {
    
	pw=[[Power alloc] init];
	[pw setDelegate:self];
	[pw registerForSleepWakeNotification];
	[pw registerForPowerChange];
	

    //load defaults

    [DefaultsController setAppliesImmediately:NO];

	mdefaults=[[MachineDefaults alloc] init:nil];

    self.machineDefaultsDict=[[NSMutableDictionary alloc] initWithDictionary:[mdefaults get_machine_defaults]];

    // Preferences window foreground handling is done via openPreferences: IBAction
    // wired from the menu item in init_statusitem (replaces notification approach).

    NSMutableArray *favorites = [[NSMutableArray alloc] init];
    
    NSMutableDictionary *defaultFav = [[NSMutableDictionary alloc] initWithObjectsAndKeys:@"Default", PREF_FAN_TITLE,
                                  [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:[[mdefaults get_machine_defaults] objectForKey:@"Fans"]]], PREF_FAN_ARRAY,nil];

    [favorites addObject:defaultFav];
    
    
	NSRange range=[[MachineDefaults computerModel] rangeOfString:@"MacBook"];
	if (range.length>0) {
		//for macbooks add a second default
		NSMutableDictionary *higherFav=[[NSMutableDictionary alloc] initWithObjectsAndKeys:@"Higher RPM", PREF_FAN_TITLE,
                                        [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:[[mdefaults get_machine_defaults] objectForKey:@"Fans"]]], PREF_FAN_ARRAY,nil];
		for (NSUInteger i=0;i<[_machineDefaultsDict[@"Fans"] count];i++) {
            
            int min_value=([[[[_machineDefaultsDict objectForKey:@"Fans"] objectAtIndex:i] objectForKey:PREF_FAN_MINSPEED] intValue])*2;
            [[[higherFav objectForKey:PREF_FAN_ARRAY] objectAtIndex:i] setObject:[NSNumber numberWithInt:min_value] forKey:PREF_FAN_SELSPEED];
		}
        [favorites addObject:higherFav];

	}

	//sync option for Macbook Pro's
	NSRange range_mbp=[[MachineDefaults computerModel] rangeOfString:@"MacBookPro"];
	if (range_mbp.length>0  && [_machineDefaultsDict[@"Fans"] count] == 2) {
		[sync setHidden:NO];
	}

	//load user defaults
	defaults = [NSUserDefaults standardUserDefaults];

	[defaults registerDefaults:
		[NSMutableDictionary dictionaryWithObjectsAndKeys:
			@0, PREF_SELECTION_DEFAULT,
			@NO,PREF_AUTOSTART_ENABLED,
			@NO,PREF_AUTOMATIC_CHANGE,
			@0, PREF_BATTERY_SELECTION,
			@0, PREF_AC_SELECTION,
			@0, PREF_CHARGING_SELECTION,
			@2, PREF_MENU_DISPLAYMODE,
            @"TC0D",PREF_TEMPERATURE_SENSOR,
            @0, PREF_NUMBEROF_LAUNCHES,
			[NSKeyedArchiver archivedDataWithRootObject:[NSColor blackColor] requiringSecureCoding:NO error:nil],PREF_MENU_TEXTCOLOR,
			favorites,PREF_FAVORITES_ARRAY,
	nil]];
	
	

	g_numFans = [smcWrapper get_fan_num];
	s_menus=[[NSMutableArray alloc] init];
	int i;
	for(i=0;i<g_numFans;i++){
		NSMenuItem *mitem=[[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Fan: %d",i] action:NULL keyEquivalent:@""];
		[mitem setTag:(i+1)*10];
		[s_menus insertObject:mitem atIndex:i];
	}
	
	[FavoritesController bind:@"content"
             toObject:[NSUserDefaultsController sharedUserDefaultsController]
          withKeyPath:[@"values." stringByAppendingString:PREF_FAVORITES_ARRAY]
              options:nil];
	[FavoritesController setEditable:YES];
	
	// set slider sync - only for MBP
	for (i=0;i<[[FavoritesController arrangedObjects] count];i++) {
		if([[FavoritesController arrangedObjects][i][PREF_FAN_SYNC] boolValue]==YES) {
			[FavoritesController setSelectionIndex:i];
			[self syncBinder:[[FavoritesController arrangedObjects][i][PREF_FAN_SYNC] boolValue]];
		}
	}

	//init statusitem
	[self init_statusitem];

	
	[programinfo setStringValue: [NSString stringWithFormat:@"%@ %@",[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"]
	,[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ]];
	//
	[copyright setStringValue:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSHumanReadableCopyright"]];

	
	//power controls only available on portables
	if (range.length>0) {
		[autochange setEnabled:true];
	} else {
		[autochange setEnabled:false];
	}
	[faqText replaceCharactersInRange:NSMakeRange(0,0) withRTF: [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"F.A.Q" ofType:@"rtf"]]];
	// Apply saved per-fan RPM settings (replaces old favorites-based apply)
	[self applyPerFanSettings];
	// Check for OCLP and prompt for boot daemon on first launch
	[OCLPHelper checkAndPromptForDaemonInstall];
	[[sliderCell dataCell] setControlSize:NSControlSizeSmall];
	[self changeMenu:nil];
	
	//seting toolbar image — prefer SF Symbol on macOS 11+, fall back to PNG
    if (@available(macOS 11.0, *)) {
        NSImage *fanIcon = [NSImage imageWithSystemSymbolName:@"fan.fill" accessibilityDescription:@"Fan Control"];
        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightRegular];
        fanIcon = [fanIcon imageWithSymbolConfiguration:config];
        [fanIcon setTemplate:YES];
        menu_image = fanIcon;
        menu_image_alt = fanIcon;
    } else {
        menu_image = [[NSImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"smc" ofType:@"png"]];
        menu_image_alt  = [[NSImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"smcover" ofType:@"png"]];
        if ([menu_image respondsToSelector:@selector(setTemplate:)]) {
            [menu_image setTemplate:YES];
            [menu_image_alt setTemplate:YES];
        }
    }

	//add timer for reading to RunLoop — use slow interval for icon-only mode
	{
		int initMode = [[defaults objectForKey:PREF_MENU_DISPLAYMODE] intValue];
		NSTimeInterval interval = (initMode == 2) ? 60.0 : 4.0;
		_readTimer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(readFanData:) userInfo:nil repeats:YES];
		if ([_readTimer respondsToSelector:@selector(setTolerance:)]) {
			[_readTimer setTolerance:(initMode == 2) ? 10.0 : 2.0];
		}
	}
	[_readTimer fire];
    
	//autoapply settings if valid
	[self upgradeFavorites];
    
    //autostart
    [[NSUserDefaults standardUserDefaults] setValue:@([self isInAutoStart]) forKey:PREF_AUTOSTART_ENABLED];
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(readFanData:) name:@"AppleInterfaceThemeChangedNotification" object:nil];

    // Modernize preferences window — transparent titlebar, follow system appearance
    if (mainwindow) {
        [(NSWindow *)mainwindow setTitlebarAppearsTransparent:YES];
        [(NSWindow *)mainwindow setTitleVisibility:NSWindowTitleHidden];
    }

    // Repurpose the old PayPal donate text field in the About window to show a Ko-fi link.
    // The About window (nib id 377) has a text field at y~59 that contained the old
    // PayPal/donation message.  Replace its content with a clickable Ko-fi link.
    for (NSWindow *win in [NSApp windows]) {
        if (win == (NSWindow *)mainwindow) continue;  // skip preferences window
        if (win == (NSWindow *)faqWindow) continue;    // skip FAQ window
        if (win == (NSWindow *)newfavoritewindow) continue;
        // The About window title varies by locale but always contains "smcFanControl".
        if (![[win title] containsString:@"smcFanControl"]) continue;
        for (NSView *subview in [[win contentView] subviews]) {
            if (![subview isKindOfClass:[NSTextField class]]) continue;
            NSTextField *tf = (NSTextField *)subview;
            NSString *text = [tf stringValue] ?: @"";
            NSString *lower = [text lowercaseString];
            BOOL hasDonateText = ([lower containsString:@"donat"] ||
                                  [lower containsString:@"paypal"] ||
                                  [lower containsString:@"spende"]);
            BOOL isEmptyDonateField = (text.length == 0 &&
                                       NSMinY(subview.frame) >= 50 &&
                                       NSMinY(subview.frame) <= 70 &&
                                       NSHeight(subview.frame) >= 40 &&
                                       NSHeight(subview.frame) <= 60);
            if (hasDonateText || isEmptyDonateField) {
                // Replace with clickable Ko-fi link
                [tf setAllowsEditingTextAttributes:YES];
                [tf setSelectable:YES];
                NSString *linkText = @"Support smcFanControl CE on Ko-fi";
                NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc]
                    initWithString:linkText];
                NSURL *kofiURL = [NSURL URLWithString:@"https://ko-fi.com/wolffcatskyy"];
                [attrStr addAttribute:NSLinkAttributeName value:kofiURL
                                range:NSMakeRange(0, linkText.length)];
                [attrStr addAttribute:NSFontAttributeName
                                value:[NSFont systemFontOfSize:11]
                                range:NSMakeRange(0, linkText.length)];
                NSMutableParagraphStyle *pstyle = [[NSMutableParagraphStyle alloc] init];
                [pstyle setAlignment:NSTextAlignmentCenter];
                [attrStr addAttribute:NSParagraphStyleAttributeName value:pstyle
                                range:NSMakeRange(0, linkText.length)];
                [tf setAttributedStringValue:attrStr];
                [tf setHidden:NO];
            }
        }
    }

    // Hide the temperature unit preference controls (C/F radio buttons and label).
    // Temperature unit now comes solely from the system locale — no user override.
    // The controls are in the preferences window: a label "Temperature unit:" (nib id 537)
    // and a radio matrix (nib id 538) bound to values.Unit.
    if (mainwindow) {
        // Walk the preferences window subview tree to find and hide the controls.
        NSView *contentView = [(NSWindow *)mainwindow contentView];
        NSMutableArray *stack = [NSMutableArray arrayWithObject:contentView];
        while (stack.count > 0) {
            NSView *v = stack.lastObject;
            [stack removeLastObject];
            [stack addObjectsFromArray:v.subviews];

            // Hide "Temperature unit:" label
            if ([v isKindOfClass:[NSTextField class]]) {
                NSTextField *tf = (NSTextField *)v;
                if ([[tf stringValue] containsString:@"Temperature unit"] ||
                    [[tf stringValue] containsString:@"Temperatur"]) {
                    [tf setHidden:YES];
                }
            }
            // Hide the C/F radio button matrix bound to values.Unit
            if ([v isKindOfClass:[NSMatrix class]]) {
                NSMatrix *matrix = (NSMatrix *)v;
                NSArray *cells = [matrix cells];
                if (cells.count == 2) {
                    NSString *t0 = [[cells objectAtIndex:0] title] ?: @"";
                    NSString *t1 = [[cells objectAtIndex:1] title] ?: @"";
                    if ([t0 containsString:@"°C"] && [t1 containsString:@"°F"]) {
                        [matrix setHidden:YES];
                    }
                }
            }
        }
    }

    // Hide favorites UI elements in preferences window (favorites are obsolete in CE).
    // Walk the view hierarchy and hide: "Favorite:" / "Default" labels, the favorites
    // popup button, and Add/Remove buttons near the favorites section.
    if (mainwindow) {
        NSView *prefContent = [(NSWindow *)mainwindow contentView];
        NSMutableArray *prefStack = [NSMutableArray arrayWithObject:prefContent];
        while (prefStack.count > 0) {
            NSView *v = prefStack.lastObject;
            [prefStack removeLastObject];
            [prefStack addObjectsFromArray:v.subviews];

            // Hide labels containing "Favorite" or showing "Default"
            if ([v isKindOfClass:[NSTextField class]]) {
                NSTextField *tf = (NSTextField *)v;
                NSString *text = [tf stringValue] ?: @"";
                NSString *lower = [text lowercaseString];
                if ([lower containsString:@"favorite"] ||
                    [lower containsString:@"favorit"] ||  // German: Favorit
                    [text isEqualToString:@"Default"] ||
                    [text isEqualToString:@"Standard"]) { // German localization
                    [tf setHidden:YES];
                }
            }

            // Hide NSPopUpButton (favorites dropdown) — the only popup in prefs is favorites
            if ([v isKindOfClass:[NSPopUpButton class]]) {
                NSPopUpButton *popup = (NSPopUpButton *)v;
                // Check if any item title matches favorites-related text
                BOOL isFavPopup = NO;
                for (NSMenuItem *item in [popup itemArray]) {
                    NSString *itemTitle = [[item title] lowercaseString];
                    if ([itemTitle containsString:@"default"] ||
                        [itemTitle containsString:@"favorite"] ||
                        [itemTitle containsString:@"higher rpm"]) {
                        isFavPopup = YES;
                        break;
                    }
                }
                if (isFavPopup) {
                    [popup setHidden:YES];
                }
            }

            // Hide NSComboBox if used for favorites
            if ([v isKindOfClass:[NSComboBox class]]) {
                [v setHidden:YES];
            }

            // Hide Add (+) / Remove (-) buttons near favorites
            if ([v isKindOfClass:[NSButton class]]) {
                NSButton *btn = (NSButton *)v;
                NSString *title = [[btn title] lowercaseString];
                // Match "+", "-", "Add", "Remove", or segmented add/remove controls
                if ([title isEqualToString:@"+"] ||
                    [title isEqualToString:@"-"] ||
                    [title isEqualToString:@"add"] ||
                    [title isEqualToString:@"remove"]) {
                    [btn setHidden:YES];
                }
            }

            // Hide NSSegmentedControl (often used for +/- buttons in nibs)
            if ([v isKindOfClass:[NSSegmentedControl class]]) {
                NSSegmentedControl *seg = (NSSegmentedControl *)v;
                if ([seg segmentCount] == 2) {
                    NSString *s0 = [seg labelForSegment:0] ?: @"";
                    NSString *s1 = [seg labelForSegment:1] ?: @"";
                    if (([s0 isEqualToString:@"+"] && [s1 isEqualToString:@"-"]) ||
                        ([s0 isEqualToString:@"-"] && [s1 isEqualToString:@"+"])) {
                        [seg setHidden:YES];
                    }
                }
            }
        }
    }

    // Hide advanced preferences that aren't needed in the simplified UI.
    // Keep: Start at login checkbox, menu bar display mode, OCLP toggle.
    // Hide: auto-change power settings, color selector, fan table, sync checkbox.
    if (mainwindow) {
        // Hide the auto-change checkbox and its associated power-source popups
        if (autochange) [(NSView *)autochange setHidden:YES];
        if (colorSelector) [(NSView *)colorSelector setHidden:YES];
        if (syncslider) [(NSView *)syncslider setHidden:YES];

        // Hide the fan table (old per-fan settings table from nib) — replaced by menu sliders
        NSView *prefContent2 = [(NSWindow *)mainwindow contentView];
        NSMutableArray *stack2 = [NSMutableArray arrayWithObject:prefContent2];
        while (stack2.count > 0) {
            NSView *v = stack2.lastObject;
            [stack2 removeLastObject];
            [stack2 addObjectsFromArray:v.subviews];

            // Hide the fan table scroll view
            if ([v isKindOfClass:[NSScrollView class]]) {
                NSScrollView *sv = (NSScrollView *)v;
                // Check if this scroll view contains a table (the fan table)
                if ([sv.documentView isKindOfClass:[NSTableView class]]) {
                    [sv setHidden:YES];
                }
            }

            // Hide labels related to auto-change power settings
            if ([v isKindOfClass:[NSTextField class]]) {
                NSTextField *tf = (NSTextField *)v;
                NSString *text = [tf stringValue] ?: @"";
                NSString *lower = [text lowercaseString];
                if ([lower containsString:@"battery"] ||
                    [lower containsString:@"batterie"] ||  // German
                    [lower containsString:@"power source"] ||
                    [lower containsString:@"charging"] ||
                    [lower containsString:@"laden"] ||     // German: charging
                    [lower containsString:@"stromquelle"] || // German: power source
                    [lower containsString:@"color"] ||
                    [lower containsString:@"farbe"] ||     // German: color
                    [lower containsString:@"couleur"]) {   // French: color
                    [tf setHidden:YES];
                }
            }

            // Hide power-source popup buttons (Battery/AC/Charging favorites selectors)
            if ([v isKindOfClass:[NSPopUpButton class]] && ![v isHidden]) {
                NSPopUpButton *popup = (NSPopUpButton *)v;
                // These popups are bound to battery/AC/charging selection prefs
                for (NSDictionary *binding in @[@{@"key": @"selectedIndex"}]) {
                    NSDictionary *info = [popup infoForBinding:@"selectedIndex"];
                    if (info) {
                        NSString *keyPath = info[NSObservedKeyPathKey] ?: @"";
                        if ([keyPath containsString:@"selbatt"] ||
                            [keyPath containsString:@"selac"] ||
                            [keyPath containsString:@"selload"]) {
                            [popup setHidden:YES];
                        }
                    }
                }
            }

            // Hide the "Autoapply favorite when powersource changes" checkbox
            if ([v isKindOfClass:[NSButton class]]) {
                NSButton *btn = (NSButton *)v;
                NSString *title = [[btn title] lowercaseString];
                if ([title containsString:@"autoapply"] ||
                    [title containsString:@"powersource"] ||
                    [title containsString:@"power source"] ||
                    [title containsString:@"automatisch"] ||  // German
                    [title containsString:@"stromquelle"]) {  // German
                    [btn setHidden:YES];
                }
            }
        }
    }

}


-(void)init_statusitem{
	statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength: NSVariableStatusItemLength];

    // Build the menu entirely in code — ignore the nib menu items for the dropdown.
    // We keep theMenu as the IBOutlet but clear it and rebuild.
    [theMenu removeAllItems];
    [theMenu setDelegate:self];
    [statusItem setMenu:theMenu];

    if ([statusItem respondsToSelector:@selector(button)]) {
        [statusItem.button setTitle:@"smc..."];
    } else {
        [statusItem setEnabled: YES];
        [statusItem setHighlightMode:YES];
        [statusItem setTitle:@"smc..."];
    }

    // --- Fan slider items ---
    _fanSliderViews = [[NSMutableArray alloc] init];
    _fanSliders = [[NSMutableArray alloc] init];
    _fanRPMLabels = [[NSMutableArray alloc] init];
    _fanMenuItems = [[NSMutableArray alloc] init];

    for (int i = 0; i < g_numFans; i++) {
        int hwMin = [smcWrapper get_min_speed:i];
        int hwMax = [smcWrapper get_max_speed:i];
        if (hwMin <= 0) hwMin = 800;
        if (hwMax <= hwMin) hwMax = hwMin + 4000;

        NSString *descr = [smcWrapper get_fan_descr:i];

        // Read saved value (or default to hardware minimum)
        NSString *prefKey = [NSString stringWithFormat:@"fan_%d_min_rpm", i];
        int savedRPM = (int)[[NSUserDefaults standardUserDefaults] integerForKey:prefKey];
        if (savedRPM < hwMin || savedRPM > hwMax) savedRPM = hwMin;

        // --- Build the custom view for this fan ---
        CGFloat viewWidth = 260.0;
        CGFloat viewHeight = 44.0;

        NSView *rowView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, viewWidth, viewHeight)];

        // Fan description label (top-left)
        NSTextField *nameLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(14, 24, 160, 16)];
        [nameLabel setStringValue:descr];
        [nameLabel setBezeled:NO];
        [nameLabel setDrawsBackground:NO];
        [nameLabel setEditable:NO];
        [nameLabel setSelectable:NO];
        [nameLabel setFont:[NSFont systemFontOfSize:11 weight:NSFontWeightMedium]];
        [nameLabel setTextColor:[NSColor secondaryLabelColor]];
        [rowView addSubview:nameLabel];

        // RPM label (top-right)
        NSTextField *rpmLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(viewWidth - 80, 24, 66, 16)];
        [rpmLabel setStringValue:[NSString stringWithFormat:@"%d rpm", savedRPM]];
        [rpmLabel setBezeled:NO];
        [rpmLabel setDrawsBackground:NO];
        [rpmLabel setEditable:NO];
        [rpmLabel setSelectable:NO];
        [rpmLabel setAlignment:NSTextAlignmentRight];
        [rpmLabel setFont:[NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular]];
        [rpmLabel setTextColor:[NSColor labelColor]];
        [rowView addSubview:rpmLabel];

        // Slider (bottom row)
        NSSlider *slider = [[NSSlider alloc] initWithFrame:NSMakeRect(14, 4, viewWidth - 28, 18)];
        [slider setMinValue:(double)hwMin];
        [slider setMaxValue:(double)hwMax];
        [slider setIntegerValue:savedRPM];
        [slider setContinuous:YES];
        [slider setTarget:self];
        [slider setAction:@selector(fanSliderChanged:)];
        [slider setTag:i]; // tag = fan index
        if (@available(macOS 10.12, *)) {
            [slider setControlSize:NSControlSizeSmall];
        }
        [rowView addSubview:slider];

        // Create menu item with embedded view
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
        [item setView:rowView];

        [_fanSliderViews addObject:rowView];
        [_fanSliders addObject:slider];
        [_fanRPMLabels addObject:rpmLabel];
        [_fanMenuItems addObject:item];

        [theMenu addItem:item];
    }

    // --- Separator ---
    [theMenu addItem:[NSMenuItem separatorItem]];

    // --- OCLP Boot Fan Control toggle (only shown on OCLP Macs) ---
    if ([OCLPHelper isOCLPMac]) {
        NSString *oclpTitle = [OCLPHelper isDaemonInstalled]
            ? @"Boot Fan Control: On"
            : @"Boot Fan Control: Off";
        NSMenuItem *oclpItem = [[NSMenuItem alloc]
            initWithTitle:oclpTitle
                   action:@selector(toggleOCLPDaemon:)
            keyEquivalent:@""];
        [oclpItem setTarget:self];
        [oclpItem setTag:9999]; // unique tag to find it later
        if ([OCLPHelper isDaemonInstalled]) {
            [oclpItem setState:NSOnState];
        }
        [theMenu addItem:oclpItem];
    }

    // --- Sleep/Wake Fix... ---
    NSMenuItem *sleepWakeItem = [[NSMenuItem alloc]
        initWithTitle:@"Sleep/Wake Fix..."
               action:@selector(showFixWindowFromMenu:)
        keyEquivalent:@""];
    [sleepWakeItem setTarget:[SleepWakeFix class]];
    [theMenu addItem:sleepWakeItem];

    // --- Preferences... ---
    NSMenuItem *prefsItem = [[NSMenuItem alloc]
        initWithTitle:@"Preferences..."
               action:@selector(openPreferences:)
        keyEquivalent:@""];
    [prefsItem setTarget:self];
    [theMenu addItem:prefsItem];

    // --- Separator ---
    [theMenu addItem:[NSMenuItem separatorItem]];

    // --- Quit ---
    NSMenuItem *quitItem = [[NSMenuItem alloc]
        initWithTitle:@"Quit smcFanControl CE"
               action:@selector(terminate:)
        keyEquivalent:@""];
    [quitItem setTarget:self];
    [theMenu addItem:quitItem];
}

#pragma mark **OCLP Toggle**

/// Toggle the OCLP boot fan control daemon on/off from the menu.
-(void)toggleOCLPDaemon:(id)sender {
    NSMenuItem *item = (NSMenuItem *)sender;
    if ([OCLPHelper isDaemonInstalled]) {
        // Uninstall
        BOOL ok = [OCLPHelper uninstallDaemon];
        if (ok) {
            [item setTitle:@"Boot Fan Control: Off"];
            [item setState:NSOffState];
        }
    } else {
        // Install
        BOOL ok = [OCLPHelper installDaemon];
        if (ok) {
            [item setTitle:@"Boot Fan Control: On"];
            [item setState:NSOnState];
        } else {
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Installation Failed"];
            [alert setInformativeText:@"Could not install the boot fan control daemon. Admin access may be required."];
            [alert addButtonWithTitle:@"OK"];
            [alert runModal];
        }
    }
}

#pragma mark **Slider Menu Actions**

/// Called when user drags a fan slider in the menu.
-(void)fanSliderChanged:(id)sender {
    NSSlider *slider = (NSSlider *)sender;
    int fanIndex = (int)[slider tag];
    int newRPM = (int)[slider integerValue];

    // Update the RPM label next to the slider
    if (fanIndex < (int)[_fanRPMLabels count]) {
        NSTextField *label = _fanRPMLabels[fanIndex];
        [label setStringValue:[NSString stringWithFormat:@"%d rpm", newRPM]];
    }

    [FanControl setRights];

    // Determine hardware minimum to decide auto vs forced mode
    int hwMin = [smcWrapper get_min_speed:fanIndex];
    if (hwMin <= 0) hwMin = 800;

    if (newRPM <= hwMin) {
        // Return this fan to automatic mode — clear its force bit in FS!
        [self setForcedMode:NO forFan:fanIndex];
    } else {
        // Force this fan to the requested speed
        [self setForcedMode:YES forFan:fanIndex];
        // Set target speed (fpe2 encoded)
        [smcWrapper setKey_external:[NSString stringWithFormat:@"F%dTg", fanIndex]
                              value:[@(newRPM) tohex]];
    }

    // Also set the minimum as a floor
    [smcWrapper setKey_external:[NSString stringWithFormat:@"F%dMn", fanIndex]
                          value:[@(newRPM) tohex]];

    // Persist to NSUserDefaults
    NSString *prefKey = [NSString stringWithFormat:@"fan_%d_min_rpm", fanIndex];
    [[NSUserDefaults standardUserDefaults] setInteger:newRPM forKey:prefKey];

    // Sync to boot daemon plist so next boot uses updated settings
    [OCLPHelper syncFanSettingsWithDaemon];
}

/// Set or clear forced mode for a specific fan by manipulating the FS!  bitmask.
-(void)setForcedMode:(BOOL)forced forFan:(int)fanIndex {
    // Read current FS!  value (ui16 — 2 bytes, big-endian bitmask)
    // Bit 0 = fan 0, bit 1 = fan 1, etc.
    // We try the F{n}Md key first (older Macs), fall back to FS!  (newer Macs).
    int fanMode = [smcWrapper get_mode:fanIndex];
    if (fanMode >= 0) {
        // This Mac has per-fan mode keys (F0Md, F1Md, ...)
        [smcWrapper setKey_external:[NSString stringWithFormat:@"F%dMd", fanIndex]
                              value:forced ? @"01" : @"00"];
    } else {
        // Use the global FS!  bitmask (ui16)
        // Read current bitmask — we encode it as a 4-hex-digit string
        // Unfortunately we can't read FS!  easily through smcWrapper (no API for it),
        // so we maintain a local cache of which fans are forced.
        static UInt16 sForceBitmask = 0;
        if (forced) {
            sForceBitmask |= (1 << fanIndex);
        } else {
            sForceBitmask &= ~(1 << fanIndex);
        }
        NSString *hexVal = [NSString stringWithFormat:@"%04x", sForceBitmask];
        [smcWrapper setKey_external:@"FS! " value:hexVal];
    }
}

/// Apply saved per-fan RPM values to SMC (used on launch and wake).
/// Sets both forced mode + target speed (for real control) and minimum floor.
-(void)applyPerFanSettings {
    [FanControl setRights];
    for (int i = 0; i < g_numFans; i++) {
        int hwMin = [smcWrapper get_min_speed:i];
        int hwMax = [smcWrapper get_max_speed:i];
        if (hwMin <= 0) hwMin = 800;
        if (hwMax <= hwMin) hwMax = hwMin + 4000;

        NSString *prefKey = [NSString stringWithFormat:@"fan_%d_min_rpm", i];
        int savedRPM = (int)[[NSUserDefaults standardUserDefaults] integerForKey:prefKey];
        if (savedRPM < hwMin || savedRPM > hwMax) savedRPM = hwMin;

        // Set the minimum floor
        [smcWrapper setKey_external:[NSString stringWithFormat:@"F%dMn", i]
                              value:[@(savedRPM) tohex]];

        // If user has set a speed above the hardware minimum, force the fan
        if (savedRPM > hwMin) {
            [self setForcedMode:YES forFan:i];
            [smcWrapper setKey_external:[NSString stringWithFormat:@"F%dTg", i]
                                  value:[@(savedRPM) tohex]];
        } else {
            [self setForcedMode:NO forFan:i];
        }

        // Also update slider position if sliders exist
        if (i < (int)[_fanSliders count]) {
            [(NSSlider *)_fanSliders[i] setIntegerValue:savedRPM];
        }
        if (i < (int)[_fanRPMLabels count]) {
            [(NSTextField *)_fanRPMLabels[i] setStringValue:
                [NSString stringWithFormat:@"%d rpm", savedRPM]];
        }
    }
}

/// Update slider RPM labels with actual current fan speeds from SMC.
-(void)updateSliderRPMLabels {
    for (int i = 0; i < g_numFans && i < (int)[_fanRPMLabels count]; i++) {
        int actualRPM = [smcWrapper get_fan_rpm:i];
        NSTextField *label = _fanRPMLabels[i];
        [label setStringValue:[NSString stringWithFormat:@"%d rpm", actualRPM]];
    }
}


/// Open preferences window and force it to front.  LSUIElement apps need
/// explicit activation since they have no Dock icon to click.
- (void)openPreferences:(id)sender {
    [NSApp activateIgnoringOtherApps:YES];
    [(NSWindow *)mainwindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

#pragma mark **Action-Methods**
- (IBAction)loginItem:(id)sender{
	if ([sender state]==NSOnState) {
		[self setStartAtLogin:YES];
	} else {
        [self setStartAtLogin:NO];
	}
}

- (IBAction)add_favorite:(id)sender{
	[[NSApplication sharedApplication] beginSheet:newfavoritewindow
								   modalForWindow: mainwindow
									modalDelegate: nil
								   didEndSelector: nil
									  contextInfo: nil];
}

- (IBAction)close_favorite:(id)sender{
	[newfavoritewindow close];
	[[NSApplication sharedApplication] endSheet:newfavoritewindow];
}

- (IBAction)save_favorite:(id)sender{
	MachineDefaults *msdefaults=[[MachineDefaults alloc] init:nil];
	if ([[newfavorite_title stringValue] length]>0) {
		NSMutableDictionary *toinsert=[[NSMutableDictionary alloc] initWithObjectsAndKeys:[newfavorite_title stringValue],@"Title",[msdefaults get_machine_defaults][@"Fans"],PREF_FAN_ARRAY,nil]; //default as template
		[toinsert setValue:@0 forKey:@"Standard"];
		[FavoritesController addObject:toinsert];
		[newfavoritewindow close];
		[[NSApplication sharedApplication] endSheet:newfavoritewindow];
	}
	[self upgradeFavorites];
}


-(void) check_deletion:(id)combo{
 if ([FavoritesController selectionIndex]==[[defaults objectForKey:combo] intValue]) {
	 [defaults setObject:@0 forKey:combo];
 }
}



- (void) deleteAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;
{
    if (returnCode==NSAlertSecondButtonReturn) {
		//delete favorite, but resets presets before
		[self check_deletion:PREF_BATTERY_SELECTION];
		[self check_deletion:PREF_AC_SELECTION];
		[self check_deletion:PREF_CHARGING_SELECTION];
        [FavoritesController removeObjects:[FavoritesController selectedObjects]];
	}
}

- (IBAction)delete_favorite:(id)sender{
	
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:NSLocalizedString(@"Delete favorite",nil)];
    [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Do you really want to delete the favorite %@?",nil), [FavoritesController arrangedObjects][[FavoritesController selectionIndex]][@"Title"]]];
    [alert addButtonWithTitle:NSLocalizedString(@"No",nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Yes",nil)];
    
    [alert beginSheetModalForWindow:mainwindow modalDelegate:self didEndSelector:@selector(deleteAlertDidEnd:returnCode:contextInfo:) contextInfo:NULL];
}


// Called via a timer mechanism. This is where all the temp / RPM reading is done.
//reads fan data and updates the gui
-(void) readFanData:(id)caller{
	
    int i = 0;
	
	//on init handling
	if (_machineDefaultsDict==nil) {
		return;
	}
    
    // Determine what data is actually needed to keep the energy impact
    // as low as possible.
    bool bNeedTemp = false;
    bool bNeedRpm = false;
    const int menuBarSetting = [[defaults objectForKey:PREF_MENU_DISPLAYMODE] intValue];
    switch (menuBarSetting) {
        default:
        case 1:
            bNeedTemp = true;
            bNeedRpm = true;
            break;

        case 2:
            // Icon only — no SMC reads needed for display.
            bNeedTemp = false;
            bNeedRpm = false;
            break;

        case 3:
            bNeedTemp = true;
            bNeedRpm = false;
            break;

        case 4:
            bNeedTemp = false;
            bNeedRpm = true;
            break;
    }

    NSString *temp = nil;
	NSString *fan = nil;
    float c_temp = 0.0f;
    int selectedRpm = 0;
    
    if (bNeedRpm == true) {
        // Read the current fan speed for fan 0 (primary) for display in the menubar.
        if (g_numFans > 0) {
            selectedRpm = [smcWrapper get_fan_rpm:0];
        }
        
        NSNumberFormatter *nc=[[NSNumberFormatter alloc] init];
        //avoid jumping in menu bar
        [nc setFormat:@"000;000;-000"];
        
        fan = [NSString stringWithFormat:@"%@rpm",[nc stringForObjectValue:[NSNumber numberWithFloat:selectedRpm]]];
    }
    
    if (bNeedTemp == true) {
        // Read current temperature and format text for the menubar.
        c_temp = [smcWrapper get_maintemp];
        
        // Detect temperature unit from system locale (no user preference).
        BOOL useFahrenheit;
        {
            NSString *tempUnit = [[NSLocale currentLocale] objectForKey:@"kCFLocaleTemperatureUnitKey"];
            if (tempUnit) {
                useFahrenheit = [tempUnit isEqualToString:@"Fahrenheit"];
            } else {
                useFahrenheit = ![[[NSLocale currentLocale] objectForKey:NSLocaleUsesMetricSystem] boolValue];
            }
        }
        if (!useFahrenheit) {
            temp = [NSString stringWithFormat:@"%@%CC",@(c_temp),(unsigned short)0xb0];
        } else {
            NSNumberFormatter *ncf=[[NSNumberFormatter alloc] init];
            [ncf setFormat:@"00;00;-00"];
            temp = [NSString stringWithFormat:@"%@%CF",[ncf stringForObjectValue:[@(c_temp) celsius_fahrenheit]],(unsigned short)0xb0];
        }
    }
    
    // Update the temp and/or fan speed text in the menubar.
    NSMutableAttributedString *s_status = nil;
    NSMutableParagraphStyle *paragraphStyle = nil;
    
    NSColor *menuColor = nil;
    BOOL setColor = NO;
    if (@available(macOS 10.14, *)) {
        // Use system label color that automatically adapts to dark/light mode
        menuColor = [NSColor labelColor];
        setColor = YES;
    } else {
        menuColor = (NSColor*)[NSKeyedUnarchiver unarchivedObjectOfClass:[NSColor class] fromData:[defaults objectForKey:PREF_MENU_TEXTCOLOR] error:nil];
        if (!([[menuColor colorUsingColorSpaceName:
                  NSCalibratedWhiteColorSpace] whiteComponent] == 0.0) || ![statusItem respondsToSelector:@selector(button)]) setColor = YES;

        NSString *osxMode = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppleInterfaceStyle"];
        if (osxMode && !setColor) {
            menuColor = [NSColor whiteColor];
            setColor = YES;
        }
    }
    
    switch (menuBarSetting) {
        default:
        case 1: {
            int fsize = 0;
            NSString *add = nil;
            if (menuBarSetting==0) {
                add=@"\n";
                fsize=9;
                [statusItem setLength:73];
            } else {
                add=@" ";
                fsize=11;
                [statusItem setLength:116];
            }

            s_status=[[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@%@%@",temp,add,fan]];
            paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
            [paragraphStyle setAlignment:NSLeftTextAlignment];
            NSFont *menuFont;
            if (@available(macOS 10.15, *)) {
                menuFont = [NSFont monospacedSystemFontOfSize:fsize weight:NSFontWeightMedium];
            } else {
                menuFont = [NSFont systemFontOfSize:fsize];
            }
            [s_status addAttribute:NSFontAttributeName value:menuFont range:NSMakeRange(0,[s_status length])];
            [s_status addAttribute:NSParagraphStyleAttributeName value:paragraphStyle range:NSMakeRange(0,[s_status length])];

            if (setColor) [s_status addAttribute:NSForegroundColorAttributeName value:menuColor  range:NSMakeRange(0,[s_status length])];


            if ([statusItem respondsToSelector:@selector(button)]) {
                [statusItem.button setAttributedTitle:s_status];
                [statusItem.button setImage:menu_image];
                [statusItem.button setImagePosition:NSImageLeft];
            } else {
                [statusItem setAttributedTitle:s_status];
                [statusItem setImage:menu_image];
            }
            break;
        }

        case 2:
            // Icon only — show the icon with no text and no tooltip.
            // No SMC reads are performed in this mode to minimize energy impact.
            [statusItem setLength:26];
            if ([statusItem respondsToSelector:@selector(button)]) {
                [statusItem.button setTitle:nil];
                [statusItem.button setToolTip:nil];
                [statusItem.button setImage:menu_image];
                [statusItem.button setAlternateImage:menu_image_alt];
            } else {
                [statusItem setTitle:nil];
                [statusItem setToolTip:nil];
                [statusItem setImage:menu_image];
                [statusItem setAlternateImage:menu_image_alt];
            }
            break;

        case 3:
            [statusItem setLength:66];
            s_status=[[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@",temp]];
            {
                NSFont *tempFont;
                if (@available(macOS 10.15, *)) {
                    tempFont = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightMedium];
                } else {
                    tempFont = [NSFont systemFontOfSize:12];
                }
                [s_status addAttribute:NSFontAttributeName value:tempFont range:NSMakeRange(0,[s_status length])];
            }
            if (setColor) [s_status addAttribute:NSForegroundColorAttributeName value:menuColor  range:NSMakeRange(0,[s_status length])];
            if ([statusItem respondsToSelector:@selector(button)]) {
                [statusItem.button setAttributedTitle:s_status];
                [statusItem.button setImage:menu_image];
                [statusItem.button setImagePosition:NSImageLeft];
            } else {
                [statusItem setAttributedTitle:s_status];
                [statusItem setImage:menu_image];
            }
            break;

        case 4:
            [statusItem setLength:85];
            s_status=[[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@",fan]];
            {
                NSFont *rpmFont;
                if (@available(macOS 10.15, *)) {
                    rpmFont = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightMedium];
                } else {
                    rpmFont = [NSFont systemFontOfSize:12];
                }
                [s_status addAttribute:NSFontAttributeName value:rpmFont range:NSMakeRange(0,[s_status length])];
            }
            if (setColor) [s_status addAttribute:NSForegroundColorAttributeName value:menuColor  range:NSMakeRange(0,[s_status length])];
            if ([statusItem respondsToSelector:@selector(button)]) {
                [statusItem.button setAttributedTitle:s_status];
                [statusItem.button setImage:menu_image];
                [statusItem.button setImagePosition:NSImageLeft];
            } else {
                [statusItem setAttributedTitle:s_status];
                [statusItem setImage:menu_image];
            }
            break;
    }
    
}


- (IBAction)savePreferences:(id)sender{
	[(NSUserDefaultsController *)DefaultsController save:sender];
	[defaults synchronize];
	[mainwindow close];
	[self applyPerFanSettings];
	[OCLPHelper syncFanSettingsWithDaemon];
	undo_dic=[NSDictionary dictionaryWithDictionary:[defaults dictionaryRepresentation]];
}



- (IBAction)closePreferences:(id)sender{
	[mainwindow close];
	[DefaultsController revert:sender];
	// Restore timer interval in case user changed display mode then cancelled.
	[self updateTimerForDisplayMode:[[defaults objectForKey:PREF_MENU_DISPLAYMODE] intValue]];
}

//set the new fan settings

-(void)apply_settings:(id)sender controllerindex:(int)cIndex{
	int i;
	[FanControl setRights];
	[FavoritesController setSelectionIndex:cIndex];
    
    for (i=0;i<[[FavoritesController arrangedObjects][cIndex][PREF_FAN_ARRAY] count];i++) {
        int fan_mode = [smcWrapper get_mode:i];
        // Auto/forced mode is not available
        if (fan_mode < 0) {
            [smcWrapper setKey_external:[NSString stringWithFormat:@"F%dMn",i] value:[[FanController arrangedObjects][i][PREF_FAN_SELSPEED] tohex]];
        } else {
            bool is_auto = [[FanController arrangedObjects][i][PREF_FAN_AUTO] boolValue];
            [smcWrapper setKey_external:[NSString stringWithFormat:@"F%dMd",i] value:is_auto ? @"00" : @"01"];
            float f_val = [[FanController arrangedObjects][i][PREF_FAN_SELSPEED] floatValue];
            uint8 *vals = (uint8*)&f_val;
            //NSString str_val = ;
            [smcWrapper setKey_external:[NSString stringWithFormat:@"F%dTg",i] value:[NSString stringWithFormat:@"%02x%02x%02x%02x",vals[0],vals[1],vals[2],vals[3]]];
        }
    }
    
	NSMenu *submenu = [[NSMenu alloc] init];
	
	for(i=0;i<[[FavoritesController arrangedObjects] count];i++){
		NSMenuItem *submenuItem = [[NSMenuItem alloc] initWithTitle:[FavoritesController arrangedObjects][i][@"Title"] action:@selector(apply_quickselect:) keyEquivalent:@""];
		[submenuItem setTag:i*100]; //for later manipulation
		[submenuItem setEnabled:YES];
		[submenuItem setTarget:self];
		[submenuItem setRepresentedObject:[FavoritesController arrangedObjects][i]];
		[submenu addItem:submenuItem];
	}
	
	[[theMenu itemWithTag:1] setSubmenu:submenu];
	for (i=0;i<[[[theMenu itemWithTag:1] submenu] numberOfItems];i++) {
		[[[[theMenu itemWithTag:1] submenu] itemAtIndex:i] setState:NSOffState];
	}
	[[[[theMenu itemWithTag:1] submenu] itemAtIndex:cIndex] setState:NSOnState];
	[defaults setObject:@(cIndex) forKey:PREF_SELECTION_DEFAULT];
	//change active setting display
	[[theMenu itemWithTag:1] setTitle:[NSString stringWithFormat:@"%@: %@",NSLocalizedString(@"Active Setting",nil),[FavoritesController arrangedObjects][[FavoritesController selectionIndex]][PREF_FAN_TITLE] ]];
}



-(void)apply_quickselect:(id)sender{
	int i;
	[FanControl setRights];
	//set all others items to off
	for (i=0;i<[[[theMenu itemWithTag:1] submenu] numberOfItems];i++) {
		[[[[theMenu itemWithTag:1] submenu] itemAtIndex:i] setState:NSOffState];
	}
	[sender setState:NSOnState];
	[[theMenu itemWithTag:1] setTitle:[NSString stringWithFormat:@"%@: %@",NSLocalizedString(@"Active Setting",nil),[sender title]]];
	[self apply_settings:sender controllerindex:[[[theMenu itemWithTag:1] submenu] indexOfItem:sender]];
}


-(void)terminate:(id)sender{
	//get last active selection
	[defaults synchronize];
	// Return all fans to automatic mode on quit (unless OCLP daemon will manage them)
	if (![OCLPHelper isDaemonInstalled]) {
		[FanControl setRights];
		for (int i = 0; i < g_numFans; i++) {
			[self setForcedMode:NO forFan:i];
		}
	}
	[smcWrapper cleanUp];
	[_readTimer invalidate];
	[pw deregisterForSleepWakeNotification];
	[pw deregisterForPowerChange];
	[[NSApplication sharedApplication] terminate:self];
}



- (IBAction)syncSliders:(id)sender{
	if ([sender state]) {
		[self syncBinder:YES];
	} else {
		[self syncBinder:NO];
	}
}


- (IBAction) changeMenu:(id)sender{
	int mode = [[[[NSUserDefaultsController sharedUserDefaultsController] values] valueForKey:PREF_MENU_DISPLAYMODE] intValue];
	if (mode == 2) {
		// Icon only — disable color selector and slow the polling timer to 60s.
		[colorSelector setEnabled:NO];
		[self updateTimerForDisplayMode:2];
	} else {
		[colorSelector setEnabled:YES];
		[self updateTimerForDisplayMode:mode];
	}

}

/// Adjust the polling timer interval based on the display mode.
/// Icon-only mode (2) uses a 60-second interval since no data is displayed.
/// All other modes use a 4-second interval to keep the menubar current.
- (void)updateTimerForDisplayMode:(int)mode {
	NSTimeInterval desired = (mode == 2) ? 60.0 : 4.0;
	if (_readTimer && [_readTimer timeInterval] == desired) return;
	[_readTimer invalidate];
	_readTimer = [NSTimer scheduledTimerWithTimeInterval:desired target:self selector:@selector(readFanData:) userInfo:nil repeats:YES];
	if ([_readTimer respondsToSelector:@selector(setTolerance:)]) {
		[_readTimer setTolerance:(mode == 2) ? 10.0 : 2.0];
	}
	[_readTimer fire];
}

- (IBAction)menuSelect:(id)sender{
	//deactivate all other radio buttons
	int i;
	for (i=0;i<[[FanController arrangedObjects] count];i++) {
		if (i!=[sender selectedRow]) {
			[[FanController arrangedObjects][i] setValue:@NO forKey:PREF_FAN_SHOWMENU];
		}	
	}
}

// Called when user clicks on smcFanControl status bar item.
// Update the RPM labels in the slider views with actual fan speeds.
- (void)menuNeedsUpdate:(NSMenu*)menu {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (theMenu == menu) {
            [self updateSliderRPMLabels];
        }
    });
}



#pragma mark **Helper-Methods**

//just a helper to bringt update-info-window to the front
-(IBAction)visitHomepage:(id)sender{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://wolffcatskyy.dev/smcfancontrol"]];
}

- (IBAction)updateCheck:(id)sender{
    // TODO: Implement GitHub Releases-based update check
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Check for Updates"];
    [alert setInformativeText:@"Visit the GitHub releases page to check for updates."];
    [alert addButtonWithTitle:@"Open GitHub"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/wolffcatskyy/smcFanControl/releases"]];
    }
}


-(void)performReset
{
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSError *error;
    NSString *machinesPath = [[fileManager applicationSupportDirectory] stringByAppendingPathComponent:@"Machines.plist"];
    [fileManager removeItemAtPath:machinesPath error:&error];
    if (error) {
        NSLog(@"Error deleting %@",machinesPath);
    }
    error = nil;
    // Return all fans to automatic mode on reset
    for (int i=0; i<g_numFans; i++) {
        [self setForcedMode:NO forFan:i];
    }

    NSString *domainName = [[NSBundle mainBundle] bundleIdentifier];
    [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:domainName];
    
    
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:NSLocalizedString(@"Shutdown required",nil)];
    [alert setInformativeText:NSLocalizedString(@"Please shutdown your computer now to return to default fan settings.",nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"OK",nil)];
    NSModalResponse code=[alert runModal];
    if (code == NSAlertFirstButtonReturn) {
        [[NSApplication sharedApplication] terminate:self];
    }
}

- (IBAction)resetSettings:(id)sender
{
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:NSLocalizedString(@"Reset Settings",nil)];
    [alert setInformativeText:NSLocalizedString(@"Do you want to reset smcFanControl to default settings? Favorites will be deleted and fans will return to default speed.",nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Yes",nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"No",nil)];
    NSModalResponse code=[alert runModal];
    if (code == NSAlertFirstButtonReturn) {
        [self performReset];
    }

}

-(void) syncBinder:(Boolean)bind{
	//in case plist is corrupt, don't bind
	if ([[FanController arrangedObjects] count]>1 ) {
		if (bind==YES) {
			[[FanController arrangedObjects][1] bind:PREF_FAN_SELSPEED toObject:[FanController arrangedObjects][0] withKeyPath:PREF_FAN_SELSPEED options:nil];
			[[FanController arrangedObjects][0] bind:PREF_FAN_SELSPEED toObject:[FanController arrangedObjects][1] withKeyPath:PREF_FAN_SELSPEED options:nil];
		} else {
			[[FanController arrangedObjects][1] unbind:PREF_FAN_SELSPEED];
			[[FanController arrangedObjects][0] unbind:PREF_FAN_SELSPEED];
		}
	}	
}


#pragma mark **Power Watchdog-Methods**

- (void)systemWillSleep:(id)sender{
}

- (void)systemDidWakeFromSleep:(id)sender{
	[self applyPerFanSettings];
}


- (void)powerChangeToBattery:(id)sender{
	// With simplified slider UI, just re-apply the saved per-fan settings.
	[self applyPerFanSettings];
}

- (void)powerChangeToAC:(id)sender{
	[self applyPerFanSettings];
}

- (void)powerChangeToACLoading:(id)sender{
	[self applyPerFanSettings];
}


#pragma mark -
#pragma mark Start-at-login control

- (BOOL)isInAutoStart
{
	BOOL found = NO;
	LSSharedFileListRef loginItems = LSSharedFileListCreate(kCFAllocatorDefault, kLSSharedFileListSessionLoginItems, /*options*/ NULL);
	NSString *path = [[NSBundle mainBundle] bundlePath];
	CFURLRef URLToToggle = (__bridge CFURLRef)[NSURL fileURLWithPath:path];
	//LSSharedFileListItemRef existingItem = NULL;
	
	UInt32 seed = 0U;
    NSArray *currentLoginItems = CFBridgingRelease(LSSharedFileListCopySnapshot(loginItems, &seed));
	
	for (id itemObject in currentLoginItems) {
		LSSharedFileListItemRef item = (__bridge LSSharedFileListItemRef)itemObject;
		
		UInt32 resolutionFlags = kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes;
		CFURLRef URL = NULL;
		OSStatus err = LSSharedFileListItemResolve(item, resolutionFlags, &URL, /*outRef*/ NULL);
		if (err == noErr) {
			Boolean foundIt = CFEqual(URL, URLToToggle);
			CFRelease(URL);
			
			if (foundIt) {
				//existingItem = item;
				found = YES;
				break;
			}
		}
	}
	return found;
}

- (void) setStartAtLogin:(BOOL)enabled {
    
	LSSharedFileListRef loginItems = LSSharedFileListCreate(kCFAllocatorDefault, kLSSharedFileListSessionLoginItems, /*options*/ NULL);
    
	
	NSString *path = [[NSBundle mainBundle] bundlePath];
	
	OSStatus status;
	CFURLRef URLToToggle = (__bridge CFURLRef)[NSURL fileURLWithPath:path];
	LSSharedFileListItemRef existingItem = NULL;
	
	UInt32 seed = 0U;
    NSArray *currentLoginItems = CFBridgingRelease(LSSharedFileListCopySnapshot(loginItems, &seed));
	
	for (id itemObject in currentLoginItems) {
		LSSharedFileListItemRef item = (__bridge LSSharedFileListItemRef)itemObject;
		
		UInt32 resolutionFlags = kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes;
		CFURLRef URL = NULL;
		OSStatus err = LSSharedFileListItemResolve(item, resolutionFlags, &URL, /*outRef*/ NULL);
		if (err == noErr) {
			Boolean foundIt = CFEqual(URL, URLToToggle);
			CFRelease(URL);
			
			if (foundIt) {
				existingItem = item;
				break;
			}
		}
	}
	
	if (enabled && (existingItem == NULL)) {
		NSString *displayName = [[NSFileManager defaultManager] displayNameAtPath:path];
		IconRef icon = NULL;
		FSRef ref;
		Boolean gotRef = CFURLGetFSRef(URLToToggle, &ref);
		if (gotRef) {
			status = GetIconRefFromFileInfo(&ref,
											/*fileNameLength*/ 0, /*fileName*/ NULL,
											kFSCatInfoNone, /*catalogInfo*/ NULL,
											kIconServicesNormalUsageFlag,
											&icon,
											/*outLabel*/ NULL);
			if (status != noErr)
				icon = NULL;
		}
		
		LSSharedFileListInsertItemURL(loginItems, kLSSharedFileListItemBeforeFirst, (__bridge CFStringRef)displayName, icon, URLToToggle, /*propertiesToSet*/ NULL, /*propertiesToClear*/ NULL);
	} else if (!enabled && (existingItem != NULL))
		LSSharedFileListItemRemove(loginItems, existingItem);
}


/// Check if the smc binary already has correct owner (root), group (admin), and
/// setuid/setgid permissions (octal 6555 = decimal 3437).
+(BOOL)smcBinaryHasCorrectPermissions {
	NSString *smcpath = [[NSBundle mainBundle] pathForResource:@"smc" ofType:@""];
	if (!smcpath) return NO;

	NSFileManager *fmanage = [NSFileManager defaultManager];
	NSDictionary *fdic = [fmanage attributesOfItemAtPath:smcpath error:nil];
	if (!fdic) return NO;

	BOOL ownerIsRoot = [[fdic valueForKey:@"NSFileOwnerAccountName"] isEqualToString:@"root"];
	BOOL groupIsAdmin = [[fdic valueForKey:@"NSFileGroupOwnerAccountName"] isEqualToString:@"admin"];
	BOOL permsCorrect = ([[fdic valueForKey:@"NSFilePosixPermissions"] intValue] == 3437);

	return (ownerIsRoot && groupIsAdmin && permsCorrect);
}

+(void) checkRightStatus:(OSStatus) status
{
    if (status != errAuthorizationSuccess) {
        // If authorization failed but the binary already has correct permissions
        // (e.g. pre-set during build/install), skip the fatal error.
        // AuthorizationExecuteWithPrivileges is deprecated and fails with
        // errAuthorizationDenied (-60007) on modern macOS even with lowered SIP.
        if ([self smcBinaryHasCorrectPermissions]) {
            NSLog(@"smcFanControl: Authorization returned %d but smc binary already has correct permissions — continuing.", (int)status);
            return;
        }

        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Authorization failed"];
        [alert setInformativeText:[NSString stringWithFormat:@"Authorization failed with code %d. The smc binary needs to be owned by root:admin with setuid permissions (6555). You can fix this manually:\n\nsudo chown root:admin <path-to-smc>\nsudo chmod 6555 <path-to-smc>",status]];
        [alert addButtonWithTitle:@"Quit"];
        [alert setAlertStyle:NSAlertStyleCritical];
        NSInteger result = [alert runModal];

        if (result == NSAlertFirstButtonReturn) {
            [[NSApplication sharedApplication] terminate:self];
        }
    }
}

#pragma mark **SMC-Binary Owner/Right Check**
//call smc binary with sudo rights and apply
+(void)setRights{
	// First check: if the binary already has correct permissions, skip authorization entirely.
	// This avoids calling the deprecated AuthorizationExecuteWithPrivileges, which fails
	// with errAuthorizationDenied (-60007) on modern macOS.
	if ([self smcBinaryHasCorrectPermissions]) {
		return;
	}

	NSString *smcpath = [[NSBundle mainBundle] pathForResource:@"smc" ofType:@""];
	if (!smcpath) {
		NSLog(@"smcFanControl: Could not find smc binary in bundle Resources.");
		return;
	}

	NSLog(@"smcFanControl: smc binary does not have correct permissions, attempting to fix...");

	// Try AuthorizationExecuteWithPrivileges (deprecated but may work on older macOS / lowered SIP).
	FILE *commPipe;
	AuthorizationRef authorizationRef;
	AuthorizationItem gencitem = { "system.privilege.admin", 0, NULL, 0 };
	AuthorizationRights gencright = { 1, &gencitem };
	int flags = kAuthorizationFlagExtendRights | kAuthorizationFlagInteractionAllowed;
	OSStatus status = AuthorizationCreate(&gencright, kAuthorizationEmptyEnvironment, flags, &authorizationRef);

	[self checkRightStatus:status];

	NSString *tool = @"/usr/sbin/chown";
	NSArray *argsArray = @[@"root:admin", smcpath];
	int i;
	char *args[255];
	for(i = 0; i < [argsArray count]; i++){
		args[i] = (char *)[argsArray[i] UTF8String];
	}
	args[i] = NULL;
	status = AuthorizationExecuteWithPrivileges(authorizationRef, [tool UTF8String], 0, args, &commPipe);

	[self checkRightStatus:status];

	// Second call for suid-bit
	tool = @"/bin/chmod";
	argsArray = @[@"6555", smcpath];
	for(i = 0; i < [argsArray count]; i++){
		args[i] = (char *)[argsArray[i] UTF8String];
	}
	args[i] = NULL;
	status = AuthorizationExecuteWithPrivileges(authorizationRef, [tool UTF8String], 0, args, &commPipe);

	[self checkRightStatus:status];
}


-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
}

@end




@implementation NSNumber (NumberAdditions)

- (NSString*) tohex{
	return [NSString stringWithFormat:@"%0.4x",[self intValue]<<2];
}


- (NSNumber*) celsius_fahrenheit{
	float celsius=[self floatValue];
	float fahrenheit=(celsius*9)/5+32;
	return @(fahrenheit);
}

@end



