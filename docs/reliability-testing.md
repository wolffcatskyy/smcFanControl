# Reliability work and test coverage

The Check for Updates action is explicit opt-in each time. It asks before
contacting GitHub, uses an ephemeral session without stored cookies or
credentials, compares numeric stable release versions, and opens only the
fixed project releases page. It never downloads or installs an update.

The diagnostic redaction script is an unwired format prototype. It does not
collect diagnostics. It keeps validated model/version fields, daemon status,
and numeric fan RPMs only. Raw helper logs, serial numbers, account names,
paths and arbitrary nested fields are excluded instead of pattern-masked.

Portable checks:

```
cc -std=c99 -Wall -Wextra -Werror tests/test_release_version.c -o /tmp/smc-version-test
/tmp/smc-version-test
python3 -m unittest discover -s tests -p 'test_*.py'
```

These checks do not build or exercise the Cocoa UI. A macOS Xcode build and
visual checks of the consent, error, no-update and available-update dialogs
are required before merging the native update-check change. Test cancellation,
GitHub HTTP errors, invalid JSON/version tags, and repeated checks on macOS.

Before a reliability release, test an Intel Mac running macOS for boot daemon
settings sync, sleep/wake, fan limits and AC/battery transitions where relevant.
No Apple Silicon fan-control support is implied. No new hardware compatibility
claim or release version is assigned by this work.
