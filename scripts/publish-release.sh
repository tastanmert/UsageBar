#!/bin/bash
# Publishes a new UsageBar version in one go. Installed copies pick it up on their own.
#
#   scripts/publish-release.sh 0.86.0 "What changed in this version"
#
# 1. Sets MARKETING_VERSION to the given version and raises CURRENT_PROJECT_VERSION by one
#    (Sparkle ranks releases by the build number), commits and tags v<version>.
# 2. Builds the DMG with scripts/make-release.sh: signed and notarized when a Developer ID
#    identity and the notary profile exist on this Mac, ad-hoc signed otherwise.
# 3. Writes appcast.xml for that DMG, signed with the Sparkle EdDSA key in the login keychain
#    (account "usagebar", created once with Sparkle's generate_keys).
# 4. Copies the committed tree to the public repository as one commit, without internal files.
# 5. Creates the GitHub release there with the DMG and appcast.xml attached. The app reads
#    releases/latest/download/appcast.xml, so the new release is what every copy sees next.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?version, e.g. 0.86.0}"
NOTES="${2:-}"
REPO="tastanmert/UsageBar"
REMOTE="https://github.com/$REPO.git"
KEY_ACCOUNT="usagebar"
# Kept out of the public copy: assistant and review tooling of this Mac.
EXCLUDE=(.prompt-surface .claude CLAUDE.md overlay)

die() { echo "error: $*" >&2; exit 1; }
step() { echo "[$(date +%T)] ==> $1"; }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like 1.2.3"
[ -z "$(git status --porcelain)" ] || die "the working tree has uncommitted changes; commit them first."
command -v gh > /dev/null || die "gh not found (brew install gh)"
gh auth status > /dev/null 2>&1 || die "gh is not signed in (gh auth login)"
git rev-parse -q --verify "refs/tags/v$VERSION" > /dev/null && die "tag v$VERSION already exists"
gh release view "v$VERSION" --repo "$REPO" > /dev/null 2>&1 && die "release v$VERSION already exists on $REPO"

# ---------------------------------------------------------------- version
step "version $VERSION"
# The app and the widget carry the same two numbers; the first is read, every one is rewritten.
CURRENT_BUILD=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\([0-9]*\)"$/\1/p' project.yml | head -n 1)
[ -n "$CURRENT_BUILD" ] || die "CURRENT_PROJECT_VERSION not found in project.yml"
BUILD=$((CURRENT_BUILD + 1))
sed -i '' -E "s/^( *MARKETING_VERSION: )\"[^\"]*\"$/\1\"$VERSION\"/; s/^( *CURRENT_PROJECT_VERSION: )\"[0-9]*\"$/\1\"$BUILD\"/" project.yml
git commit -q -m "UsageBar $VERSION" project.yml
echo "    build $BUILD"

# ---------------------------------------------------------------- build
MODE_FLAG=(--unsigned)
if security find-identity -v -p codesigning | grep -q '"Developer ID Application' \
   && xcrun notarytool history --keychain-profile "${USAGEBAR_NOTARY_PROFILE:-usagebar-notary}" > /dev/null 2>&1; then
  MODE_FLAG=()
else
  echo "    no Developer ID identity or notary profile: building ad-hoc signed (first launch needs Open Anyway)"
fi
step "build the DMG"
scripts/make-release.sh "${MODE_FLAG[@]}"

BUILT=$(ls build/release/UsageBar-"$VERSION"*.dmg | head -n 1)
[ -f "$BUILT" ] || die "no DMG for $VERSION in build/release"

# ---------------------------------------------------------------- appcast
step "appcast"
PUB=build/publish/$VERSION
rm -rf "$PUB"; mkdir -p "$PUB"
DMG="$PUB/UsageBar-$VERSION.dmg"
cp "$BUILT" "$DMG"
if [ -n "$NOTES" ]; then
  # Sparkle shows a same-named .html next to the archive as the release notes.
  python3 -c 'import html,sys; print("<ul>" + "".join("<li>%s</li>" % html.escape(l.lstrip("-* ").strip()) for l in sys.argv[1].splitlines() if l.strip()) + "</ul>")' "$NOTES" > "$PUB/UsageBar-$VERSION.html"
fi
APPCAST_TOOL=build/release/dd-app/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast
[ -x "$APPCAST_TOOL" ] || die "generate_appcast not found at $APPCAST_TOOL"
"$APPCAST_TOOL" --account "$KEY_ACCOUNT" \
  --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
  --link "https://github.com/$REPO/releases/tag/v$VERSION" \
  --embed-release-notes \
  -o "$PUB/appcast.xml" "$PUB"
grep -q "sparkle:edSignature" "$PUB/appcast.xml" || die "appcast.xml carries no EdDSA signature"
grep -q "<sparkle:version>$BUILD</sparkle:version>" "$PUB/appcast.xml" || die "appcast.xml does not name build $BUILD"

git tag "v$VERSION"

# ---------------------------------------------------------------- public tree
step "public repository"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
if git ls-remote --exit-code "$REMOTE" main > /dev/null 2>&1; then
  git clone --quiet --depth 1 "$REMOTE" "$WORK/repo"
else
  git init --quiet -b main "$WORK/repo"
  git -C "$WORK/repo" remote add origin "$REMOTE"
fi
git -C "$WORK/repo" rm -rq --ignore-unmatch . > /dev/null
git archive HEAD | tar -x -C "$WORK/repo"
for item in "${EXCLUDE[@]}"; do rm -rf "${WORK:?}/repo/$item"; done
git -C "$WORK/repo" add -A
if git -C "$WORK/repo" diff --cached --quiet; then
  echo "    public tree already current"
else
  git -C "$WORK/repo" -c user.name="$(git config user.name)" -c user.email="$(git config user.email)" \
    commit --quiet -m "UsageBar $VERSION"
  git -C "$WORK/repo" push --quiet origin main
fi

# ---------------------------------------------------------------- release
step "GitHub release"
BODY="${NOTES:+$NOTES

}Universal (Apple Silicon + Intel), macOS 14 or later.

Installed copies update themselves. New install: open the DMG and drag UsageBar into Applications. If macOS blocks the first launch, open System Settings > Privacy & Security and choose Open Anyway."
gh release create "v$VERSION" "$DMG" "$PUB/appcast.xml" --repo "$REPO" --target main \
  --title "UsageBar $VERSION" --notes "$BODY"
echo "==> published: https://github.com/$REPO/releases/tag/v$VERSION"

# ---------------------------------------------------------------- homebrew
# The tap's cask names this version and the DMG's checksum, so `brew install --cask usagebar`
# hands out what the release page does. A failure here leaves the release published; the cask
# then still points at the previous version, which installs and updates itself through Sparkle.
step "homebrew tap"
TAP_REMOTE="https://github.com/tastanmert/homebrew-tap.git"
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
if git clone --quiet --depth 1 "$TAP_REMOTE" "$WORK/tap"; then
  sed -i '' -E "s/^( *version )\"[^\"]*\"/\1\"$VERSION\"/; s/^( *sha256 )\"[0-9a-f]*\"/\1\"$SHA\"/" "$WORK/tap/Casks/usagebar.rb"
  if git -C "$WORK/tap" diff --quiet; then
    echo "    cask already current"
  else
    git -C "$WORK/tap" -c user.name="$(git config user.name)" -c user.email="$(git config user.email)" \
      commit --quiet -am "UsageBar $VERSION" && git -C "$WORK/tap" push --quiet origin main \
      && echo "    cask: $VERSION" || echo "    cask update failed; update Casks/usagebar.rb by hand"
  fi
else
  echo "    could not clone $TAP_REMOTE; update Casks/usagebar.rb by hand"
fi
