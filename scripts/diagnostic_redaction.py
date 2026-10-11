"""Allowlist a diagnostic snapshot. No collection, logging or upload occurs.

Raw helper logs, paths, identifiers, user names and arbitrary nested values are
not exported. This is a report-format primitive, not a wired app exporter yet.
"""
import re

VERSION = re.compile(r"[0-9]+(?:\.[0-9]+){1,3}(?:-ce)?\Z")
MODEL = re.compile(r"(?:MacPro|MacBookPro|MacBookAir|Macmini|iMac|iMacPro|MacBook)[0-9]+,[0-9]+\Z")


def redact_snapshot(snapshot):
    result = {}
    for field, pattern in [("model", MODEL), ("macos_version", VERSION),
                           ("oclp_version", VERSION), ("app_version", VERSION)]:
        value = snapshot.get(field)
        if isinstance(value, str) and pattern.fullmatch(value):
            result[field] = value
    if snapshot.get("daemon_status") in ("running", "stopped", "not_installed", "unknown"):
        result["daemon_status"] = snapshot["daemon_status"]
    fans = []
    source = snapshot.get("fans")
    if isinstance(source, list):
        for fan in source[:32]:
            if not isinstance(fan, dict):
                continue
            clean = {k: v for k, v in fan.items() if k in ("current_rpm", "min_rpm", "max_rpm")
                     and type(v) is int and 0 <= v <= 100000}
            if clean:
                fans.append(clean)
    result["fans"] = fans
    return result
