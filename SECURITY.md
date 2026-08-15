# Security policy

## Supported versions

Security fixes are applied to the latest published release and the `main` branch.

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability. Use GitHub's **Report a vulnerability** button on the repository's Security tab to submit a private report. Include the affected version, reproduction steps, potential impact, and any suggested mitigation.

Please avoid accessing data that is not yours, running destructive demonstrations, or publishing details before a fix is available. A report will normally be acknowledged within seven days.

## Security model

Folder Terminal is intentionally unsandboxed and starts real login shells. Commands and child processes have the permissions of the logged-in user, as they do in Terminal.app. The application does not provide a security boundary around terminal processes.

Official release archives are ad-hoc signed until Apple Developer ID signing and notarisation are introduced. Verify the release checksum when provenance matters, and build from source if you require full inspection of the executable.
