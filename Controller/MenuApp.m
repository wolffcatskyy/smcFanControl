/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "client.h"
#import <Cocoa/Cocoa.h>

@interface CoolingApp : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property(strong) NSStatusItem *item;
@property(strong) NSTimer *timer;
@property(strong) NSDictionary *snapshot;
@property unsigned long lastSequence;
@property int stalled;
@end
@implementation CoolingApp
- (NSDictionary *)queryStatus {
  char reply[8192];
  if (ce_request("STATUS", reply, sizeof reply))
    return nil;
  NSData *data = [[NSString stringWithUTF8String:reply]
      dataUsingEncoding:NSUTF8StringEncoding];
  id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
  return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  (void)notification;
  self.item = [[NSStatusBar systemStatusBar]
      statusItemWithLength:NSVariableStatusItemLength];
  NSMenu *menu = [NSMenu new];
  menu.delegate = self;
  self.item.menu = menu;
  [self refresh];
  self.timer = [NSTimer scheduledTimerWithTimeInterval:4
                                                target:self
                                              selector:@selector(refresh)
                                              userInfo:nil
                                               repeats:YES];
  self.timer.tolerance = 1;
}
- (void)refresh {
  self.snapshot = [self queryStatus];
  unsigned long seq = [self.snapshot[@"sequence"] unsignedLongValue];
  if (self.snapshot && seq == self.lastSequence)
    self.stalled++;
  else
    self.stalled = 0;
  self.lastSequence = seq;
  BOOL healthy = self.snapshot && ![self.snapshot[@"error"] boolValue] &&
                 self.stalled < 3 &&
                 [self.snapshot[@"watchdog_age"] doubleValue] >= 0 &&
                 [self.snapshot[@"watchdog_age"] doubleValue] < 15;
  self.item.button.title = healthy ? @"Fan" : @"Fan !";
  self.item.button.toolTip =
      healthy ? @"Fan controller running independently of user logins"
              : @"Fan controller unavailable, stalled, or reporting an error. "
                @"Open Diagnostics.";
}
- (void)add:(NSString *)title
    selector:(SEL)selector
         tag:(NSInteger)tag
          to:(NSMenu *)menu {
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                action:selector
                                         keyEquivalent:@""];
  item.target = self;
  item.tag = tag;
  [menu addItem:item];
}
- (void)menuNeedsUpdate:(NSMenu *)menu {
  [menu removeAllItems];
  self.snapshot = [self queryStatus];
  if (!self.snapshot)
    [self add:@"Controller unavailable" selector:NULL tag:0 to:menu];
  for (NSDictionary *fan in self.snapshot[@"fans"]) {
    NSInteger index = [fan[@"id"] integerValue];
    NSString *title =
        [NSString stringWithFormat:@"Fan %ld: %@ RPM · %@", (long)index + 1,
                                   fan[@"rpm"], fan[@"mode"]];
    NSMenuItem *parent = [[NSMenuItem alloc] initWithTitle:title
                                                    action:NULL
                                             keyEquivalent:@""];
    NSMenu *sub = [NSMenu new];
    [self add:@"System automatic"
        selector:@selector(automatic:)
             tag:index
              to:sub];
    [self add:@"Maximum cooling" selector:@selector(maximum:) tag:index to:sub];
    [self add:@"Minimum boost…" selector:@selector(minimum:) tag:index to:sub];
    [self add:@"Fixed RPM…" selector:@selector(manual:) tag:index to:sub];
    [self add:@"Temperature curve…"
        selector:@selector(curve:)
             tag:index
              to:sub];
    parent.submenu = sub;
    [menu addItem:parent];
  }
  [menu addItem:[NSMenuItem separatorItem]];
  [self add:@"Sensors…" selector:@selector(sensors:) tag:0 to:menu];
  [self add:@"Diagnostics…" selector:@selector(diagnostics:) tag:0 to:menu];
  [self add:@"Install / update system controller…"
      selector:@selector(install:)
           tag:0
            to:menu];
  [menu addItem:[NSMenuItem separatorItem]];
  [self add:@"Quit interface (keep cooling)"
      selector:@selector(quit:)
           tag:0
            to:menu];
}
- (void)message:(NSString *)title detail:(NSString *)detail {
  [NSApp activateIgnoringOtherApps:YES];
  NSAlert *alert = [NSAlert new];
  alert.messageText = title;
  alert.informativeText = detail;
  [alert addButtonWithTitle:@"OK"];
  [alert runModal];
}
- (void)send:(NSString *)command {
  char reply[8192];
  if (ce_request(command.UTF8String, reply, sizeof reply)) {
    [self message:@"Controller unavailable"
           detail:@"No new policy was confirmed. Check Diagnostics and the "
                  @"system service."];
    return;
  }
  if (strncmp(reply, "OK", 2))
    [self message:@"Cooling change failed"
           detail:[NSString stringWithUTF8String:reply]];
  [self refresh];
}
- (void)automatic:(NSMenuItem *)item {
  [self send:[NSString stringWithFormat:@"SET %ld auto", (long)item.tag]];
}
- (void)maximum:(NSMenuItem *)item {
  [self send:[NSString stringWithFormat:@"SET %ld maximum", (long)item.tag]];
}
- (void)askRPM:(NSMenuItem *)item mode:(NSString *)mode {
  [NSApp activateIgnoringOtherApps:YES];
  NSAlert *alert = [NSAlert new];
  alert.messageText =
      [mode isEqual:@"minimum"] ? @"Minimum fan boost" : @"Fixed fan RPM";
  alert.informativeText =
      @"The system controller validates the requested RPM against the detected "
      @"limits. Minimum boost allows firmware to increase cooling.";
  NSTextField *field =
      [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 220, 24)];
  field.placeholderString = @"RPM";
  alert.accessoryView = field;
  [alert addButtonWithTitle:@"Apply"];
  [alert addButtonWithTitle:@"Cancel"];
  if ([alert runModal] == NSAlertFirstButtonReturn)
    [self send:[NSString stringWithFormat:@"SET %ld %@ %@", (long)item.tag,
                                          mode, field.stringValue]];
}
- (void)minimum:(NSMenuItem *)item {
  [self askRPM:item mode:@"minimum"];
}
- (void)manual:(NSMenuItem *)item {
  [self askRPM:item mode:@"manual"];
}
- (void)curve:(NSMenuItem *)item {
  [NSApp activateIgnoringOtherApps:YES];
  NSAlert *alert = [NSAlert new];
  alert.messageText = @"Temperature curve";
  alert.informativeText =
      @"Choose a key shown in Sensors. The curve rises from minimum at the "
      @"lower temperature to maximum at the upper temperature. Missing sensor "
      @"readings request maximum cooling.";
  NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)];
  NSMutableArray *fields = [NSMutableArray new];
  NSArray *labels = @[ @"Sensor key", @"Minimum at °C", @"Maximum at °C" ];
  for (int i = 0; i < 3; i++) {
    NSTextField *label = [NSTextField labelWithString:labels[i]];
    label.frame = NSMakeRect(0, 70 - i * 32, 130, 24);
    [view addSubview:label];
    NSTextField *field = [[NSTextField alloc]
        initWithFrame:NSMakeRect(140, 70 - i * 32, 150, 24)];
    [view addSubview:field];
    [fields addObject:field];
  }
  alert.accessoryView = view;
  [alert addButtonWithTitle:@"Apply"];
  [alert addButtonWithTitle:@"Cancel"];
  if ([alert runModal] == NSAlertFirstButtonReturn)
    [self
        send:[NSString stringWithFormat:@"SET %ld curve %@ %@ %@",
                                        (long)item.tag, [fields[0] stringValue],
                                        [fields[1] stringValue],
                                        [fields[2] stringValue]]];
}
- (void)sensors:(id)sender {
  (void)sender;
  char reply[8192];
  [self message:@"Available temperature sensors (°C)"
         detail:ce_request("SENSORS", reply, sizeof reply)
                    ? @"Controller unavailable"
                    : [NSString stringWithUTF8String:reply]];
}
- (void)diagnostics:(id)sender {
  (void)sender;
  char reply[8192];
  NSString *detail =
      ce_request("STATUS", reply, sizeof reply)
          ? @"Controller unavailable. Cooling state is unverified."
          : [NSString stringWithUTF8String:reply];
  [self
      message:@"System controller diagnostics"
       detail:
           [detail
               stringByAppendingString:
                   @"\n\nThe controller runs at boot. The separate watchdog is "
                   @"installed by default; its failures are recorded in the "
                   @"macOS system log as smcfan-ce-watchdog. A GUI health "
                   @"indicator does not prove that the watchdog is running."]];
}
- (void)install:(id)sender {
  (void)sender;
  NSString *path = [NSBundle.mainBundle.resourcePath
      stringByAppendingPathComponent:@"Controller/install.sh"];
  NSString *escaped = [[path stringByReplacingOccurrencesOfString:@"\\"
                                                       withString:@"\\\\"]
      stringByReplacingOccurrencesOfString:@"\""
                                withString:@"\\\""];
  NSString *source = [NSString
      stringWithFormat:@"do shell script (\"/bin/bash \" & quoted form of "
                       @"\"%@\") with administrator privileges",
                       escaped];
  NSDictionary *error = nil;
  [[[NSAppleScript alloc] initWithSource:source] executeAndReturnError:&error];
  if (error)
    [self message:@"Installation did not complete" detail:error.description];
  else
    [self refresh];
}
- (void)quit:(id)sender {
  (void)sender;
  [NSApp terminate:nil];
}
@end
int main(void) {
  @autoreleasepool {
    NSApplication *app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
    CoolingApp *delegate = [CoolingApp new];
    app.delegate = delegate;
    [app run];
  }
  return 0;
}
