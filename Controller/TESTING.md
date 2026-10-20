# Development and physical testing

Run portable checks from `Controller/`:

```sh
cc -std=c11 -D_GNU_SOURCE -Wall -Wextra -Werror -O2 tests/test_policy.c policy.c decode.c -lm -o /tmp/ce-policy-test
/tmp/ce-policy-test
python3 -m unittest discover -s tests -v
```

The 12 integration tests compile a fake SMC backend and use isolated temporary sockets/configuration. They cover persistence, multiple readers, invalid commands, private configuration, duplicate locks, bit preservation, baseline restoration, curves and slow clients. They do not touch physical SMC or launchd. Test-mode authorization is intentionally different from production and cannot establish administrator isolation.

On a macOS SDK host, build `make`. Native regression fixtures `tests/test_backend_macos.c` exercise the real production backend against fake SMC functions, including firmware overwriting targets in automatic mode. `tests/test_auth_macos.c` exercises the real membership helper and expects execution from an administrator account. Run these fixture binaries from `Controller/` on macOS:

```sh
clang -std=c11 -Wall -Wextra tests/test_backend_macos.c backend_macos.c policy.c decode.c -framework IOKit -framework CoreFoundation -o /tmp/ce-backend-test
/tmp/ce-backend-test
clang -std=c11 -Wall -Wextra tests/test_auth_macos.c auth_macos.c -o /tmp/ce-auth-test
/tmp/ce-auth-test
```

These fixtures do not replace real socket/account or fan tests.

Use sanitizers for portable policy/decoder assertions when supported. Run `bash -n` and ShellCheck on installation/recovery scripts. A full legacy Xcode build is a separate check and has not been performed by this candidate validation.

## Physical release gates

Record commit/build, hardware model, OS, policy, actual RPM, target, errors and watchdog age. Keep sensitive identifiers out of public reports.

1. Read-only probe and explicit limits; establish rollback before changing ownership.
2. Install immediately and verify actual RPM independently of requested target.
3. Test automatic-to-maximum from a truly released automatic state, plus manual/minimum/curve transitions.
4. Verify real administrator socket writes and non-administrator refusal.
5. Deliberately suspend the controller with the bounded pilot watchdog script; require PID replacement, resumed sequence/heartbeat and sustained measured RPM. Test crash behavior separately.
6. Verify cold boot before login, lock/switch users, GUI exit/relaunch and sleep/wake.
7. Exercise failed writes/missing sensors, multiple fans and additional Intel/T2 models.

The root-only `test-watchdog-mp6.sh` is specific to the 2141 RPM maximum pilot and attempts resume/restart on failure. `update-verified-mp6.sh` adds corrected transition, account and repeat stall checks with pilot rollback. Do not use those profiles on an unvalidated machine. Read [RECOVERY.md](RECOVERY.md) and maintain local access throughout hardware testing.

Only [VALIDATION.md](VALIDATION.md) records which gates have actually passed. Passing fixture tests, a process launch or launchd configuration does not pass the corresponding physical gate.
