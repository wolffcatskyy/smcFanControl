# Legacy Update Guardian utility

This optional Objective-C utility is separate from fan control and is not installed by Cooling CE. Its source queries the latest OCLP GitHub release, examines available updates, and attempts to alter macOS update preferences. A scheduled plist is included. These mechanisms do not prove that an update is compatible, that every update path is blocked, or that the packaged integration works on a particular OS.

The CLI source provides `--status`, `--check`, `--enable`, `--disable` and `--abort`. Review the implementation and installed identity before use. A status/check is not a hardware compatibility certification. Enable/disable changes update-related preferences; disabling sets the utility's chosen defaults rather than restoring a complete captured pre-install state.

`--abort` is destructive maintenance: it attempts to kill update-related daemons and remove staged update files. It is not a routine fan-control step or a guarantee that an OS update can be safely cancelled. Do not run it as a generic troubleshooting command.

This documentation review did not build or exercise Update Guardian or its scheduling. Its external-service dependency, privilege behavior, preference scope, failure handling and compatibility inference require a separate review before presenting it as update protection. Refer to the installed launch plist and source for exact paths; no root installation recipe is endorsed here.
