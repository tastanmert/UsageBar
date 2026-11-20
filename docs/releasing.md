# Releasing UsageBar

One script builds, signs, notarizes and packages a universal (arm64 and x86_64) DMG on this Mac.
Nothing is sent anywhere except the app to Apple's notary service.

```sh
scripts/make-release.sh
```

The result is `build/release/UsageBar-<version>.dmg`, signed with Developer ID, notarized and
stapled. The version comes from `MARKETING_VERSION` in `project.yml`; change it there and commit
before releasing.

## Options

| Command | Result |
| --- | --- |
| `scripts/make-release.sh` | Signed, notarized, stapled `UsageBar-<version>.dmg` |
| `scripts/make-release.sh --skip-notarize` | Signed with Developer ID, not notarized |
| `scripts/make-release.sh --unsigned` | Ad-hoc signed `UsageBar-<version>-unsigned.dmg`, for local testing |
| `--allow-dirty` | Build with uncommitted changes (by default the script refuses) |

Environment variables:

- `USAGEBAR_SIGN_IDENTITY`: the signing identity, for example `Developer ID Application: Name (TEAMID)`. If it is unset, the script uses the only Developer ID Application identity in your keychain, and stops if there are several.
- `USAGEBAR_NOTARY_PROFILE`: the notarytool keychain profile. Default `usagebar-notary`.

An unsigned DMG opens on other Macs only after the user right-clicks the app and chooses Open, or
removes the quarantine flag. Use it for testing, not for distribution.

## One-time setup

1. Install the tools.

   ```sh
   xcode-select --install            # or install Xcode
   brew install xcodegen
   curl https://sh.rustup.rs -sSf | sh
   (cd rust && rustup target add aarch64-apple-darwin x86_64-apple-darwin)
   ```

   `rust/rust-toolchain.toml` pins the Rust version; rustup installs it on first use.

2. Get a Developer ID Application certificate. This needs a paid Apple Developer Program
   membership. In Xcode open Settings, Accounts, select your team, Manage Certificates, press `+`
   and choose Developer ID Application. Check it with:

   ```sh
   security find-identity -v -p codesigning
   ```

   The list must contain a `Developer ID Application: ...` line. An Apple Development or Apple
   Distribution certificate does not work for a DMG distributed outside the App Store.

3. Store notarization credentials in the keychain. Create an app-specific password at
   appleid.apple.com, then run:

   ```sh
   xcrun notarytool store-credentials usagebar-notary --apple-id <apple-id> --team-id <team-id>
   ```

   It prompts for the password and saves it in the login keychain. Check it with
   `xcrun notarytool history --keychain-profile usagebar-notary`.

4. The DMG builder, dmgbuild, installs itself into `build/dmgbuild-venv` on the first run. This
   needs Python 3.10 or newer on `PATH` and network access once. To prepare it ahead of time:

   ```sh
   python3 -m venv build/dmgbuild-venv
   build/dmgbuild-venv/bin/pip install dmgbuild==1.6.7
   echo dmgbuild==1.6.7 > build/dmgbuild-venv/.usagebar-pin
   ```

   If `dmgbuild` is already on your `PATH`, it is used instead.

## What the script does

1. Refuses to run with uncommitted changes, checks the Rust targets, the signing identity and the
   notary profile, and checks the committed UniFFI bindings are current.
2. Runs `xcodegen generate`, archives the `UsageBar` scheme and builds the `UsageBarCLI` scheme for
   both architectures, both ad-hoc signed. It builds the Rust `usagebar` entry for both
   architectures and joins them with `lipo`.
3. Embeds the CLI and the entry in `UsageBar.app/Contents/Helpers`, removes Sparkle's XPC services
   (the app is not sandboxed and notarization rejects them), then signs every Mach-O file and nested
   bundle from the inside out with `--options runtime --timestamp`, and last the app.
4. Notarizes the app and staples the ticket, so the copy inside the DMG works offline.
5. Builds the DMG with `scripts/dmg/make-dmg.sh`, signs it, notarizes it and staples it.
6. Verifies with `xcrun stapler validate` and `spctl -a -vv` on the app and the DMG.

Output, the archive and logs stay in `build/release/`, which git ignores.

## Publishing a version

```sh
scripts/publish-release.sh 0.86.0 "What changed"
```

This bumps the version and build number in `project.yml`, commits and tags `v<version>`, builds
the DMG with `make-release.sh` (signed and notarized when a Developer ID identity and the notary
profile exist, ad-hoc signed otherwise), writes a signed `appcast.xml`, copies the committed tree
to `tastanmert/UsageBar` as one commit and creates the GitHub release there with both files
attached.

## Updates (Sparkle)

Release builds read `https://github.com/tastanmert/UsageBar/releases/latest/download/appcast.xml`
(`SPARKLE_FEED_URL` in `Config/Overlay.xcconfig`) every 15 minutes and install a newer build in the
background. Users can turn that off or check by hand in Settings > About. Debug builds never poll.

The appcast is signed with an EdDSA key. The public half is `SPARKLE_PUBLIC_ED_KEY` in
`project.yml`; the private half is in the login keychain of the release Mac under the account
`usagebar`. Back it up once, because an app that already carries the public key accepts only
updates signed with this private key:

```sh
build/release/dd-app/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account usagebar -x usagebar-sparkle-private.key
```

Keep that file out of the repository. On another Mac, import it with `generate_keys --account usagebar -f <file>`.

## Troubleshooting

- `no 'Developer ID Application' identity`: step 2 above is not done on this Mac.
- `notarytool keychain profile ... is missing`: step 3 above is not done.
- Notarization rejected: run `xcrun notarytool log <submission-id> --keychain-profile usagebar-notary`. The submission ID is in `build/release/notary.log`.
