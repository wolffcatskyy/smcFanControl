# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| v2.7.0 | Yes |
| v2.6.2-ce | Yes |
| < v2.6.2 | No |

## Reporting a Vulnerability

If you discover a security vulnerability in smcFanControl, please report it through one of the following channels:

- **GitHub Issues:** Open an issue at [github.com/wolffcatskyy/smcFanControl/issues](https://github.com/wolffcatskyy/smcFanControl/issues)
- **Email:** Reach the maintainer via the email listed on the [GitHub profile](https://github.com/wolffcatskyy)

Please include as much detail as possible:

- Description of the vulnerability
- Steps to reproduce
- macOS version and hardware
- Potential impact

## Response Timeline

- **Acknowledgment:** Within 72 hours of report
- **Initial assessment:** Within 1 week
- **Fix or mitigation:** Dependent on severity, but typically within 2-4 weeks for confirmed vulnerabilities

## Elevated Privileges & SMC Access

smcFanControl requires direct access to the System Management Controller (SMC) to read sensor data and adjust fan speeds. This necessarily involves elevated privileges:

- The app uses a privileged helper tool to communicate with the SMC hardware interface
- Installation may prompt for administrator credentials to install this helper
- The helper runs with root-level access scoped to SMC read/write operations only

Users should be aware that any application with SMC access operates at a level that could theoretically affect hardware behavior. We recommend:

- Only installing smcFanControl from official releases on this repository
- Verifying release checksums when available
- Keeping the app updated to a supported version listed above

## Scope

This policy covers the smcFanControl application and its bundled privileged helper. Third-party forks or unofficial builds are not covered.
