# Releasing

Releases are built and published by GitHub Actions ([`release.yml`](../.github/workflows/release.yml))
when a version tag is pushed.

## Steps

1. Update `ZestVersion.current` in [`Sources/ZestCore/Version.swift`](../Sources/ZestCore/Version.swift)
   and add a `## <version> — <date>` section to [`CHANGELOG.md`](../CHANGELOG.md). That section becomes
   the release notes, and the update dialog shows the first sentence of up to four of its items,
   without links, issue numbers or thanks. So write each item for users: start with what changed
   for them in one short sentence, then add details or credits after it.
2. Commit, then tag and push:
   ```bash
   git tag v0.2.0
   git push origin main v0.2.0
   ```
3. The workflow checks that the tag matches `Version.swift` and that the changelog has a section
   for it, runs the tests, builds and signs
   `Zest.app`, and publishes `Zest.zip` and `Zest.zip.sha256` as a GitHub release. Installed apps
   find it within a day, or right away with **Check for Updates**.

## Signing

zest is free and not signed by Apple (that needs a paid Apple Developer account). Instead it is
signed with the project's own certificate. This matters because macOS remembers the Accessibility
permission per signing certificate: as long as every release uses the same certificate, users never
have to grant it again after an update. The updater also refuses updates signed with another
certificate.

The certificate and its private key live in two repository secrets:

| Secret | Value |
| --- | --- |
| `ZEST_SIGNING_P12` | `base64 -i ~/.zest-signing/zest-signing.p12` |
| `ZEST_SIGNING_PASSWORD` | the contents of `~/.zest-signing/p12-password` |

They were created once with [`scripts/create-signing-identity.sh`](../scripts/create-signing-identity.sh).
**Keep a backup of `~/.zest-signing`.** If the certificate is lost, a new one works for new installs,
but existing users must download the new version by hand and grant Accessibility again.

To set the secrets:

```bash
base64 -i ~/.zest-signing/zest-signing.p12 | gh secret set ZEST_SIGNING_P12
gh secret set ZEST_SIGNING_PASSWORD < ~/.zest-signing/p12-password
```

## Local builds

`scripts/build-app.sh` signs ad hoc by default. With an ad hoc signature macOS asks for
Accessibility again after every rebuild. Maintainers with the certificate can run
[`scripts/setup-local-signing.sh`](../scripts/setup-local-signing.sh) once: it imports the certificate
into a separate keychain (your login keychain is not touched), and `build-app.sh` then uses it.

## Why users don't see a Gatekeeper warning

macOS checks apps downloaded by browsers (they get a "quarantine" flag). `install.sh` downloads with
`curl`, which sets no such flag, and the updater downloads with `URLSession` in the app, which doesn't
either. Users who download `Zest.zip` in a browser need to click **Open Anyway** once in
System Settings → Privacy & Security.
