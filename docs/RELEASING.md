# Releasing XClose

Releases are built and published by GitHub Actions when a version tag is pushed.

## One-time setup

### 1. Back up the release keys

These were generated on the maintainer's Mac in `~/.xclose-release/`:

| File | What it is | If lost |
|---|---|---|
| `sparkle_ed25519.key` | Private key that signs updates. Its public half is `SUPublicEDKey` in `Resources/Info.plist`. | Installed copies can **never** be updated again; users must reinstall manually. |
| `signing.p12` + `signing.p12.password` | The self-signed code-signing certificate | The next release gets a new identity, and every user must re-grant Accessibility. |
| `sparkle_ed25519.pub` | Public key, for reference | Can be recomputed with `swift scripts/sparkle-keys.swift public <keyfile>` |

Store copies in a password manager or other secure backup. **Never commit them**; `.gitignore` excludes these file types.

### 2. Add repository secrets

In GitHub, go to **Settings › Secrets and variables › Actions › New repository secret**:

| Secret | Value |
|---|---|
| `SPARKLE_PRIVATE_KEY` | `cat ~/.xclose-release/sparkle_ed25519.key` |
| `SIGNING_P12_BASE64` | `base64 -i ~/.xclose-release/signing.p12` |
| `SIGNING_P12_PASSWORD` | `cat ~/.xclose-release/signing.p12.password` |

Later, for Developer ID and notarization, add `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` and `NOTARY_KEY_P8_BASE64`, and replace the signing secrets. See [DISTRIBUTION.md](DISTRIBUTION.md#moving-to-developer-id-later).

### 3. Enable GitHub Pages and workflow permissions

- **Settings › Pages › Build and deployment › Source: GitHub Actions.** This publishes `site/`, the landing page and the Sparkle appcast.
- **Settings › Actions › General › Workflow permissions: Read and write.** The release workflow commits the new appcast entry to `main`. If `main` is protected, allow GitHub Actions to push to it.

After enabling Pages, run the **Website** workflow once (**Actions › Website › Run workflow**). The site and an empty appcast then go live before the first release.

## Cutting a release

1. Add a section to `CHANGELOG.md`. Users see it in the update window.
   ```markdown
   ## 1.1.0

   - What changed, written for users.
   ```
2. Set the version. This also bumps the build number, which Sparkle uses to compare versions:
   ```sh
   scripts/set-version.sh 1.1.0
   ```
3. Run the tests and try the build locally:
   ```sh
   swift test && scripts/build-app.sh && scripts/package-release.sh
   ```
4. Commit, tag and push:
   ```sh
   git commit -am "Release 1.1.0"
   git tag v1.1.0
   git push origin main v1.1.0
   ```

The **Release** workflow then:
1. checks that the tag matches `Info.plist`
2. runs the tests
3. builds the universal app and signs it
4. notarizes it, if Developer ID secrets exist
5. creates `XClose.dmg` and `XClose-1.1.0.zip`
6. signs the zip for Sparkle
7. publishes the GitHub Release with the changelog section as notes
8. adds the release to `site/appcast.xml` on `main`
9. redeploys the website

Installed copies see the update within a day.

The download button always points at `releases/latest/download/XClose.dmg`, so the website needs no change per release.

## After publishing

- Download the DMG from the website on a clean Mac (or a new user account) and run the first-launch checklist in [TESTING.md](TESTING.md#release-checklist).
- With the previous version installed, choose **Check for Updates…**. Confirm the update installs and XClose is still **Active** afterwards, which shows the Accessibility grant survived.

## Fixing a bad release

- **Update not yet published:** delete the GitHub Release and the tag, fix the problem, and tag again.
- **Already in the appcast:** publish a new version with a higher build number. Don't edit or remove a published appcast item; clients may already be installing it.
