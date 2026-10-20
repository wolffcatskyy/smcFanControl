CC = clang
CFLAGS = -std=c11 -Os -Wall -Wextra -mmacosx-version-min=10.13 -arch x86_64
LDFLAGS = -Wl,-dead_strip
OUT = build
BACKEND = backend_macos.c ../smc-command/smc.c
CORE = policy.c decode.c
all: $(OUT)/probe $(OUT)/smcfan-ce-daemon $(OUT)/smcfanctl $(OUT)/smcfan-ce-watchdog $(OUT)/Cooling\ CE.app/Contents/MacOS/CoolingCE
$(OUT):
	mkdir -p $(OUT)
$(OUT)/smcfan-ce-daemon: daemon.c auth_macos.c auth.h $(BACKEND) $(CORE) backend.h policy.h client.h | $(OUT)
	$(CC) $(CFLAGS) $(LDFLAGS) daemon.c auth_macos.c $(BACKEND) $(CORE) -framework IOKit -framework CoreFoundation -o $@
$(OUT)/probe: probe.c $(BACKEND) $(CORE) backend.h policy.h | $(OUT)
	$(CC) $(CFLAGS) $(LDFLAGS) probe.c $(BACKEND) $(CORE) -framework IOKit -framework CoreFoundation -o $@
$(OUT)/smcfanctl: cli.c client.h | $(OUT)
	$(CC) $(CFLAGS) $(LDFLAGS) cli.c -o $@
$(OUT)/smcfan-ce-watchdog: watchdog.c client.h | $(OUT)
	$(CC) $(CFLAGS) $(LDFLAGS) watchdog.c -o $@
$(OUT)/Cooling\ CE.app/Contents/MacOS/CoolingCE: MenuApp.m client.h $(OUT)/smcfan-ce-daemon $(OUT)/smcfanctl $(OUT)/smcfan-ce-watchdog install.sh uninstall.sh dev.wolffcatskyy.smcfan-ce.plist dev.wolffcatskyy.smcfan-ce-watchdog.plist
	mkdir -p "$(OUT)/Cooling CE.app/Contents/MacOS" "$(OUT)/Cooling CE.app/Contents/Resources/Controller"
	$(CC) $(CFLAGS) -fobjc-arc $(LDFLAGS) -framework Cocoa MenuApp.m -o "$@"
	cp Info.plist "$(OUT)/Cooling CE.app/Contents/Info.plist"
	cp ../LICENSE "$(OUT)/Cooling CE.app/Contents/Resources/LICENSE"
	cp $(OUT)/smcfan-ce-daemon $(OUT)/smcfanctl $(OUT)/smcfan-ce-watchdog install.sh uninstall.sh *.plist "$(OUT)/Cooling CE.app/Contents/Resources/Controller/"
clean:
	rm -rf $(OUT)
.PHONY: all clean

# Explicit pilot rollback helper; not part of the normal application bundle.
recovery: $(OUT)/recovery-max
$(OUT)/recovery-max: RecoveryMax.c ../smc-command/smc.c ../smc-command/smc.h | $(OUT)
	$(CC) $(CFLAGS) $(LDFLAGS) RecoveryMax.c -framework IOKit -framework CoreFoundation -o $@
.PHONY: recovery
