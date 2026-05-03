#!/bin/zsh
# release.sh — One-command local release for Shuuchuu.
#
# Usage:
#   ./scripts/release.sh <version> [changelog message]
#   ./scripts/release.sh 0.2.0 "Fix soundtrack autocomplete"
#   ./scripts/release.sh 0.2.0                              # auto-generate from git log
#
# Flags:
#   -y, --yes    Skip confirmation prompts
#   --beta       Beta channel + GitHub pre-release; appcast item gets sparkle:channel=beta
#
# Requires .env with: SPARKLE_EDDSA_KEY, X_NOISE_SIGN_IDENTITY, X_NOISE_NOTARY_PROFILE

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_REPO="bluedusk/x-noise"
APP_NAME="Shuuchuu"
PLIST="Sources/${APP_NAME}/Resources/Info.plist"

AUTO_YES=false
BETA=false
VERSION=""
CHANGELOG_MSG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes) AUTO_YES=true; shift ;;
        --beta) BETA=true; shift ;;
        -*) echo "Unknown option: $1"; exit 1 ;;
        *)
            if [[ -z "$VERSION" ]]; then VERSION="$1"
            else CHANGELOG_MSG="$1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 [-y|--yes] [--beta] <version> [changelog message]"
    exit 1
fi

if [[ "$BETA" == true ]]; then
    [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$ ]] || {
        echo "Error: beta version must be semver or semver-beta.N (got: $VERSION)"; exit 1
    }
else
    [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
        echo "Error: version must be semver (got: $VERSION)"; exit 1
    }
fi

cd "$REPO_ROOT"

# Load env
if [[ ! -f ".env" ]]; then
    echo "Error: .env file required with SPARKLE_EDDSA_KEY, X_NOISE_SIGN_IDENTITY, X_NOISE_NOTARY_PROFILE"
    exit 1
fi
set -a; source .env; set +a

: "${SPARKLE_EDDSA_KEY:?Missing SPARKLE_EDDSA_KEY in .env}"
: "${X_NOISE_SIGN_IDENTITY:?Missing X_NOISE_SIGN_IDENTITY in .env}"
: "${X_NOISE_NOTARY_PROFILE:?Missing X_NOISE_NOTARY_PROFILE in .env}"

# Verify clean tree
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Error: working tree has uncommitted changes"; exit 1
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$BRANCH" != "main" && "$AUTO_YES" != true ]]; then
    echo -n "Current branch is '$BRANCH', not 'main'. Continue? [y/N] "
    read -r ans
    [[ "$ans" == "y" || "$ans" == "Y" ]] || exit 1
fi

# Compute build number = monotonically-increasing integer
PREV_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
BUILD_NUMBER=$((PREV_BUILD + 1))
echo "Bumping version: $(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST") -> $VERSION"
echo "Bumping build:   $PREV_BUILD -> $BUILD_NUMBER"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"

# Generate changelog message if not provided
if [[ -z "$CHANGELOG_MSG" ]]; then
    PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    if [[ -n "$PREV_TAG" ]]; then
        CHANGELOG_MSG=$(git log --oneline "${PREV_TAG}..HEAD" | sed 's/^[0-9a-f]* /- /')
    else
        CHANGELOG_MSG=$(git log --oneline | head -10 | sed 's/^[0-9a-f]* /- /')
    fi
fi

# Prepend to CHANGELOG
DATE=$(date +%Y-%m-%d)
TMP_CHANGELOG=$(mktemp)
{
    echo "## [$VERSION] - $DATE"
    echo ""
    echo "$CHANGELOG_MSG"
    echo ""
    cat CHANGELOG.md
} > "$TMP_CHANGELOG"
mv "$TMP_CHANGELOG" CHANGELOG.md

# Build release binary
echo "Building release binary..."
swift build -c release

# Wrap into .app bundle
OUT_DIR="output"
APP_DIR="$OUT_DIR/${APP_NAME}.app"
rm -rf "$OUT_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"

cp ".build/release/${APP_NAME}" "$APP_DIR/Contents/MacOS/${APP_NAME}"
cp "$PLIST" "$APP_DIR/Contents/Info.plist"

# Copy resource bundle (catalog, sounds, etc.)
RESOURCE_BUNDLE=".build/release/${APP_NAME}_${APP_NAME}.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
fi

# Embed Sparkle.framework
SPARKLE_FRAMEWORK=$(find .build -name "Sparkle.framework" -type d -path "*/Sparkle/Sparkle.framework" | head -1)
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
    echo "Error: Sparkle.framework not found in .build/"
    exit 1
fi
cp -R "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/"

# Sign (deep, hardened, with entitlements)
echo "Signing..."
codesign --deep --force --options runtime \
    --entitlements config/packaging/Shuuchuu.entitlements \
    --sign "$X_NOISE_SIGN_IDENTITY" \
    "$APP_DIR"

# Zip
ZIP_PATH="$OUT_DIR/${APP_NAME}.zip"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

# Notarise
echo "Notarising..."
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$X_NOISE_NOTARY_PROFILE" \
    --wait

# Staple + re-zip
xcrun stapler staple "$APP_DIR"
rm "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

# Commit version bump + changelog
git add "$PLIST" CHANGELOG.md
git commit -m "release: v$VERSION"
git tag "v$VERSION"
git push --follow-tags

# GitHub release
PRERELEASE_FLAG=""
[[ "$BETA" == true ]] && PRERELEASE_FLAG="--prerelease"
gh release create "v$VERSION" "$ZIP_PATH" \
    --repo "$RELEASE_REPO" \
    --title "v$VERSION" \
    --notes "$CHANGELOG_MSG" \
    $PRERELEASE_FLAG

# Update appcast
export X_NOISE_VERSION="$VERSION"
export X_NOISE_BUILD_NUMBER="$BUILD_NUMBER"
export X_NOISE_ZIP_PATH="$REPO_ROOT/$ZIP_PATH"
export X_NOISE_RELEASE_NOTES="$CHANGELOG_MSG"
[[ "$BETA" == true ]] && export X_NOISE_BETA=true
./scripts/update-appcast.sh

echo "Done. v$VERSION published."
