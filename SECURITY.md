# Security Policy

At **Stasis**, we take the security of your MacBook and its hardware controls seriously. Because Stasis interacts with the Apple Silicon System Management Controller (SMC) via a root-privileged helper daemon, we maintain strict security guidelines.

---

## 1. Supported Versions

We provide security updates and fixes for the latest release of Stasis.

| Version | Supported |
| :--- | :--- |
| **0.29.x (Latest)** | :white_check_mark: Yes |
| < 0.29.0 | :x: No |

---

## 2. Privileged Helper Daemon Security

The Stasis Privileged Helper Daemon (`com.dinanathdash.stasis.charging-helper`) runs with root privileges to modify SMC registers. To protect against unauthorized XPC access:
- **XPC Service Verification**: The helper daemon checks each incoming connection's process and applies the app's own designated code-signing requirement to it (pinned to the app's signature), before executing any command. Builds are ad-hoc signed, so the helper only accepts the exact build it shipped with.
- **Install**: The helper is installed through a single administrator prompt into a root-owned folder under `/Library/PrivilegedHelperTools`. Its code signature and its framework's are checked after the copy, and the app build allowed to connect is recorded in a root-owned file that the helper only trusts if no one else can write it.
- **Minimal Privilege Scope**: The daemon only exposes commands necessary for reading battery sensors, writing charging state thresholds (`CHWA`), and controlling MagSafe LEDs.
- **No Arbitrary Execution**: The daemon does not accept arbitrary shell commands or unvalidated input strings.

---

## 3. Reporting a Vulnerability

If you discover a potential security vulnerability in Stasis or its helper daemon:
1. **Do not open a public GitHub issue.**
2. Email the project maintainer directly at `dashdinanath056@gmail.com` with the subject line `[SECURITY] Stasis Vulnerability Report`.
3. Provide steps to reproduce the issue and any relevant logs or Proof of Concept (PoC) code.
4. We will acknowledge your report within 48 hours and work with you on a patch and advisory release.
