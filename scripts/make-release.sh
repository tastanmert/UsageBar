#!/bin/bash
# Builds UsageBar.app (universal: arm64 + x86_64) and packages it as a DMG, on this Mac only.
#
#   scripts/make-release.sh                    signed with Developer ID, notarized, stapled
#   scripts/make-release.sh --skip-notarize    signed with Developer ID, not notarized
#   scripts/make-release.sh --unsigned         ad-hoc signed, not notarized (local testing only)
#
# Other flags: --allow-dirty (build with uncommitted changes), -h / --help.
# Environment:
#   USAGEBAR_SIGN_IDENTITY   "Developer ID Application: Name (TEAMID)". Default: the only
#                            Developer ID Application identity in the login keychain.
#   USAGEBAR_NOTARY_PROFILE  notarytool keychain profile name. Default: usagebar-notary.
#
# Output goes to build/release/: UsageBar-<version>.dmg (or UsageBar-<version>-unsigned.dmg).
# One-time setup is in docs/releasing.md.
set -Eeuo pipefail

cd "$(dirname "$0")/.."

MODE=signed
NOTARIZE=1
ALLOW_DIRTY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --unsigned) MODE=unsigned; NOTARIZE=0 ;;
    --skip-notarize) NOTARIZE=0 ;;
    --allow-dirty) ALLOW_DIRTY=1 ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done

STEP_NAME=""
step() { STEP_NAME="$1"; echo "[$(date +%T)] ==> $1"; }
trap 'echo "[$(date +%T)] FAILED during: $STEP_NAME" >&2' ERR
die() { echo "error: $*" >&2; exit 1; }

OUT=build/release
ARCHIVE="$OUT/UsageBar.xcarchive"
APP="$OUT/UsageBar.app"
NOTARY_PROFILE="${USAGEBAR_NOTARY_PROFILE:-usagebar-notary}"
export PATH="$HOME/.cargo/bin:$PATH"

# ---------------------------------------------------------------- preflight
step "preflight"
if [ "$ALLOW_DIRTY" != 1 ] && [ -n "$(git status --porcelain)" ]; then
  die "the working tree has uncommitted changes. Commit or stash them, or pass --allow-dirty."
fi
[ ! -e overlay ] || die "./overlay exists. A release is built from the public tree only; unlink it first."
for tool in xcodegen xcodebuild lipo codesign hdiutil ditto; do
  command -v "$tool" > /dev/null || die "$tool not found (xcodegen: brew install xcodegen)"
done
command -v cargo > /dev/null || die "cargo not found. Install Rust from https://rustup.rs"
for target in aarch64-apple-darwin x86_64-apple-darwin; do
  (cd rust && rustup target list --installed) | grep -qx "$target" \
    || die "Rust target $target is missing. Run: (cd rust && rustup target add aarch64-apple-darwin x86_64-apple-darwin)"
done

SIGN_IDENTITY=""
if [ "$MODE" = signed ]; then
  SIGN_IDENTITY="${USAGEBAR_SIGN_IDENTITY:-}"
  if [ -z "$SIGN_IDENTITY" ]; then
    found=$(security find-identity -v -p codesigning | grep '"Developer ID Application' | sed 's/^[^"]*"\(.*\)"$/\1/' || true)
    count=$(printf '%s' "$found" | grep -c . || true)
    case "$count" in
      0) die "no 'Developer ID Application' identity in the keychain. Create one in Xcode (Settings > Accounts > your team > Manage Certificates > + > Developer ID Application), or at developer.apple.com/account. An 'Apple Distribution' or 'Apple Development' certificate cannot be used. For a local test build run: scripts/make-release.sh --unsigned" ;;
      1) SIGN_IDENTITY="$found" ;;
      *) die "several Developer ID Application identities found; set USAGEBAR_SIGN_IDENTITY to one of:
$found" ;;
    esac
  fi
  echo "    signing identity: $SIGN_IDENTITY"
  if [ "$NOTARIZE" = 1 ]; then
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" > /dev/null 2>&1 \
      || die "notarytool keychain profile '$NOTARY_PROFILE' is missing or not working. Create it once with:
  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <apple-id> --team-id <team-id>
(it asks for an app-specific password from appleid.apple.com). To skip notarization: --skip-notarize."
  fi
fi

step "check the UniFFI bindings are current"
scripts/gen-uniffi.sh --check

# ---------------------------------------------------------------- build
rm -rf "$ARCHIVE" "$APP" "$OUT"/*.dmg "$OUT"/*.zip
mkdir -p "$OUT"

step "xcodegen"
xcodegen generate

# The archive and the CLI are built ad-hoc signed; every Mach-O is signed here afterwards, so the
# build never needs a team ID or a signing identity.
ADHOC=(CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="")

step "archive UsageBar (arm64 + x86_64)"
xcodebuild archive \
  -project UsageBar.xcodeproj -scheme UsageBar -configuration Release \
  -archivePath "$ARCHIVE" -derivedDataPath "$OUT/dd-app" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO "${ADHOC[@]}" -quiet
ditto "$ARCHIVE/Products/Applications/UsageBar.app" "$APP"

step "build the usagebar CLI (arm64 + x86_64)"
xcodebuild build \
  -project UsageBar.xcodeproj -scheme UsageBarCLI -configuration Release \
  -derivedDataPath "$OUT/dd-cli" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO "${ADHOC[@]}" -quiet
CLI_BIN="$OUT/dd-cli/Build/Products/Release/usagebar"

has_both_archs() { lipo -archs "$1" | grep -qw arm64 && lipo -archs "$1" | grep -qw x86_64; }
has_both_archs "$CLI_BIN" || die "the CLI is not universal"
has_both_archs "$APP/Contents/MacOS/UsageBar" || die "the app binary is not universal"
for arch in arm64 x86_64; do
  lipo "$CLI_BIN" -thin "$arch" -output "$OUT/cli-$arch.thin"
  strings "$OUT/cli-$arch.thin" | grep -c 'usagebar_core ctx-v1' > /dev/null || die "Rust core missing from the $arch CLI slice"
  rm -f "$OUT/cli-$arch.thin"
done

step "build the Rust usagebar entry (arm64 + x86_64)"
ENTRY_BIN="$OUT/usagebar-entry"
slices=()
for triple in aarch64-apple-darwin x86_64-apple-darwin; do
  (cd rust && MACOSX_DEPLOYMENT_TARGET=14.0 cargo build --release --locked -p usagebar --target "$triple")
  slices+=("rust/target/$triple/release/usagebar")
done
lipo -create "${slices[@]}" -output "$ENTRY_BIN"
for arch in arm64 x86_64; do
  lipo "$ENTRY_BIN" -thin "$arch" -output "$OUT/entry-$arch.thin"
  strings "$OUT/entry-$arch.thin" | grep -c 'usagebar_entry forward-v1' > /dev/null || die "entry marker missing from the $arch slice"
  rm -f "$OUT/entry-$arch.thin"
done

step "embed the entry and the Swift CLI (Contents/Helpers)"
mkdir -p "$APP/Contents/Helpers/swift"
ditto "$CLI_BIN" "$APP/Contents/Helpers/swift/usagebar"
ditto "$ENTRY_BIN" "$APP/Contents/Helpers/usagebar"

# ---------------------------------------------------------------- sign
# The app is not sandboxed, so Sparkle's XPC services are unused; leaving them in fails notarization.
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"

sign_all() {  # sign_all <identity> [extra codesign flags...]: inside-out, deepest first
  local id="$1"; shift
  local f
  # 1. loose Mach-O files, except the app's own executable (the app seal covers it)
  find "$APP" -type f ! -path "$APP/Contents/MacOS/UsageBar" -print0 \
    | while IFS= read -r -d '' f; do
        if file -b "$f" | grep -c '^Mach-O' > /dev/null; then printf '%s\n' "$f"; fi
      done \
    | awk -F/ '{print NF "\t" $0}' | sort -rn | cut -f2- \
    | while IFS= read -r f; do codesign --force "$@" --sign "$id" "$f"; done
  # 2. nested bundles
  find "$APP" -mindepth 2 -type d \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' \) -print \
    | awk -F/ '{print NF "\t" $0}' | sort -rn | cut -f2- \
    | while IFS= read -r f; do codesign --force "$@" --sign "$id" "$f"; done
  # 3. the app itself
  codesign --force "$@" --sign "$id" "$APP"
}

smoke() {
  codesign --verify --strict --deep "$APP"
  "$APP/Contents/Helpers/usagebar" help > /dev/null || die "the embedded usagebar entry does not run"
}

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")

if [ "$MODE" = unsigned ]; then
  step "ad-hoc sign"
  sign_all "-"
  smoke
  DMG="$OUT/UsageBar-$VERSION-unsigned.dmg"
  step "dmg"
  scripts/dmg/make-dmg.sh "$APP" "$DMG"
  echo "==> done: $DMG (ad-hoc signed, not notarized: macOS will warn on first open)"
  exit 0
fi

step "sign with Developer ID (hardened runtime, secure timestamp)"
sign_all "$SIGN_IDENTITY" --options runtime --timestamp
smoke

notarize() {  # notarize <file>
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait \
    | tee "$OUT/notary.log" | tail -n 8
  grep -q 'status: Accepted' "$OUT/notary.log" \
    || die "notarization was not accepted. Fetch the log with: xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE"
}

if [ "$NOTARIZE" = 1 ]; then
  # The app is notarized and stapled first so the copy inside the DMG carries its own ticket and
  # still opens when it is dragged out and launched offline.
  step "notarize the app"
  ditto -c -k --keepParent "$APP" "$OUT/UsageBar-app.zip"
  notarize "$OUT/UsageBar-app.zip"
  rm -f "$OUT/UsageBar-app.zip"
  xcrun stapler staple "$APP"
fi

DMG="$OUT/UsageBar-$VERSION.dmg"
step "dmg"
scripts/dmg/make-dmg.sh "$APP" "$DMG"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

if [ "$NOTARIZE" = 1 ]; then
  step "notarize the dmg"
  notarize "$DMG"
  xcrun stapler staple "$DMG"

  step "verify"
  xcrun stapler validate "$APP"
  xcrun stapler validate "$DMG"
  spctl -a -vv -t exec "$APP"
  spctl -a -vv -t install "$DMG"
  echo "==> done: $DMG (signed, notarized, stapled)"
else
  echo "==> done: $DMG (signed, NOT notarized: Gatekeeper will reject it on other Macs)"
fi
