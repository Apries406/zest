# Security

zest runs locally. It listens only on a Unix socket in `~/Library/Application Support/zest` that
only your user can open, and it connects to the internet only to check GitHub Releases for updates.
Updates are installed only if their SHA-256 checksum matches and they are signed with the project's
certificate.

If you find a security problem, please report it privately through
[GitHub security advisories](https://github.com/rostik32/zest/security/advisories/new) instead of
opening a public issue.
