# Building and releasing BetterScroll

## Local builds

Run `make build check` to build and test. The default signer is an Apple Development identity from your keychain. To compile a local copy without a developer certificate, use `make build SIGN_IDENTITY=-` for ad-hoc signing. Keep the signing identity consistent between builds when testing macOS input permissions.

Run `make dmg` to create `build/BetterScroll.dmg`. With the app closed, use the read-only Bluetooth probe to check device discovery and wheel capabilities.

```sh
build/BetterScroll.app/Contents/MacOS/BetterScroll --probe
```

For hardware verification, test slow detents and fast wheel flicks, the reverse direction switch, all three wheel modes, a remapped side button, and thumb gestures. Quit the app and check native scrolling resumes.

## GitHub releases

The [release workflow](../.github/workflows/release.yml) builds merged pull requests targeting `master`. The patch version is the first-parent commit count from `v1.0.0` to the merge. A rerun uses the same version.

GitHub Actions ad-hoc signs the app and uses Sparkle to sign the DMG and update feed. Publishing requires a GitHub repository and a Sparkle key pair. Set these values in the repository’s Actions settings.

| Kind | Name | Value |
| --- | --- | --- |
| Variable | `SPARKLE_PUBLIC_KEY` | Base64 public key from Sparkle’s `generate_keys` |
| Secret | `SPARKLE_PRIVATE_KEY` | Private key exported by Sparkle’s `generate_keys -x` |

Run `make sparkle` to fetch the pinned, checksum-verified Sparkle tools. Run `build/sparkle-*/bin/generate_keys --account BetterScroll` to create the key pair once. Use that same account with `-x <file>` to export the private key. Submit that file to GitHub as the secret, then keep a secure backup outside the repository. Reuse the same key pair for every release. If the private key is lost, users will need to install a new build manually to establish trust in a new key.

The workflow builds the Apple silicon DMG and attaches it and its signed appcast to a GitHub release. The app reads `releases/latest/download/appcast.xml` and verifies each download before extraction. Updates begin with **Check for Updates…**. Only builds made with `SPARKLE_PUBLIC_KEY` embed the updater.

The published `v1.0.0` release includes the updater. Anyone who installed an earlier build with the same version number needs to replace it manually with the current DMG. Gatekeeper may require approval, and macOS may prompt for Accessibility and Input Monitoring after an ad-hoc-signed update.

[Sparkle publishing documentation](https://sparkle-project.org/documentation/publishing/) · [Apple’s Gatekeeper guidance](https://support.apple.com/en-us/102445)
