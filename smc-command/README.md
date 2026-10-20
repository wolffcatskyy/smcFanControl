# Raw SMC developer CLI

This is the inherited low-level SMC tool, distinct from Cooling CE's typed `smcfanctl` protocol. It can read sensors and write raw keys. Arbitrary writes can disrupt cooling; prefer the controller's validated policy interface for fan control and never use concurrent writers.

## Read-only inspection

```sh
smc -h
smc -v
smc -f
smc -k FNum -r
smc -k F0Ac -r
```

Use the path to the binary you actually built/installed; this guide does not imply it is on PATH or bundled in every release. `-l` enumerates keys and may produce extensive output. `-t` lists temperatures in builds providing that option; consult the current executable's help.

## Common fan keys

| Key | Typical meaning |
| --- | --- |
| `FNum` | Fan count |
| `F0Ac` | Actual fan 0 RPM |
| `F0Mn` | Minimum RPM |
| `F0Mx` | Reported maximum RPM |
| `F0Sf` | Safe-speed value where available |
| `F0Tg` | Target RPM |
| `FS! ` | Global force mask, including the trailing space |

Other fans substitute their index. Availability, encoding and writable behavior vary. A reported maximum can disagree with physical operation; it is not permission to invent a higher target. Common fan speeds use `fpe2` fixed point (RPM multiplied by four), not `fp78`. Temperature keys may use signed `sp78`; interpreting raw bytes without their type can produce incorrect values.

`-k KEY -w HEX` is a raw write operation. Replacing the entire global mask can change other fans' ownership. On the pilot hardware, firmware overwrote target writes made before manual ownership was established. Therefore the old generic raw-write recipes have been removed; they did not preserve unrelated bits, verify transitions or provide rollback. The production candidate backend handles these operations and has regression fixtures, but its physical model coverage remains limited.

Known temperature names such as `TC0P`, `TG0D` or `TB0T` are model-dependent examples. A missing key does not prove a missing sensor. See [candidate validation](../Controller/VALIDATION.md) for measured evidence rather than historical cooling-performance claims.

Attribution and license notices in `smc.c`, `smc.h` and the repository LICENSE remain applicable.
