#!/bin/zsh
# update-appcast.sh — Append a new release to appcast.xml.
#
# Required env:
#   X_NOISE_VERSION        — semantic version
#   X_NOISE_BUILD_NUMBER   — integer build number
#   X_NOISE_ZIP_PATH       — path to the signed/notarised .zip
#   SPARKLE_EDDSA_KEY      — base64 EdDSA private key
#
# Optional:
#   GITHUB_REPO            — owner/repo (default: bluedusk/x-noise)
#   X_NOISE_RELEASE_NOTES  — markdown release notes (rendered as HTML)
#   X_NOISE_BETA           — if "true", marks as beta channel

set -euo pipefail

: "${X_NOISE_VERSION:?Missing X_NOISE_VERSION}"
: "${X_NOISE_BUILD_NUMBER:?Missing X_NOISE_BUILD_NUMBER}"
: "${X_NOISE_ZIP_PATH:?Missing X_NOISE_ZIP_PATH}"
: "${SPARKLE_EDDSA_KEY:?Missing SPARKLE_EDDSA_KEY}"

REPO="${GITHUB_REPO:-bluedusk/x-noise}"
APPCAST="appcast.xml"
SIGN_UPDATE=$(find .build -name "sign_update" -type f | head -1)

if [[ -z "$SIGN_UPDATE" ]]; then
    echo "Error: sign_update not found. Run 'swift build' first to resolve Sparkle."
    exit 1
fi
if [[ ! -f "$X_NOISE_ZIP_PATH" ]]; then
    echo "Error: ZIP not found at $X_NOISE_ZIP_PATH"; exit 1
fi
if [[ ! -f "$APPCAST" ]]; then
    echo "Error: $APPCAST not found in working directory"; exit 1
fi

# Compute EdDSA signature
echo "Signing $X_NOISE_ZIP_PATH..."
SIGNATURE=$(echo "$SPARKLE_EDDSA_KEY" | "$SIGN_UPDATE" "$X_NOISE_ZIP_PATH" --ed-key-file /dev/stdin 2>/dev/null)
ED_SIGNATURE=$(echo "$SIGNATURE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
FILE_LENGTH=$(stat -f%z "$X_NOISE_ZIP_PATH")

if [[ -z "$ED_SIGNATURE" ]]; then
    echo "Error: failed to extract EdDSA signature"
    echo "sign_update output: $SIGNATURE"
    exit 1
fi

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v${X_NOISE_VERSION}/Shuuchuu.zip"
PUB_DATE=$(LC_ALL=C date +"%a, %d %b %Y %H:%M:%S %z")

# Build description block — wrap each line in <li>
DESC_HTML=""
if [[ -n "${X_NOISE_RELEASE_NOTES:-}" ]]; then
    LIS=$(echo "$X_NOISE_RELEASE_NOTES" | sed 's/^- /<li>/; s/$/<\/li>/' | tr -d '\n')
    DESC_HTML="<![CDATA[<ul>${LIS}</ul>]]>"
fi

CHANNEL_TAG=""
if [[ "${X_NOISE_BETA:-false}" == "true" ]]; then
    CHANNEL_TAG="            <sparkle:channel>beta</sparkle:channel>"
fi

# Build new <item>
NEW_ITEM=$(cat <<EOF
        <item>
            <title>Version ${X_NOISE_VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
${CHANNEL_TAG}
            <description>${DESC_HTML}</description>
            <enclosure
                url="${DOWNLOAD_URL}"
                sparkle:version="${X_NOISE_BUILD_NUMBER}"
                sparkle:shortVersionString="${X_NOISE_VERSION}"
                sparkle:edSignature="${ED_SIGNATURE}"
                length="${FILE_LENGTH}"
                type="application/octet-stream"
            />
        </item>
EOF
)

# Insert after <language>en</language>
TMP=$(mktemp)
awk -v item="$NEW_ITEM" '
    /<language>en<\/language>/ { print; print item; next }
    { print }
' "$APPCAST" > "$TMP"
mv "$TMP" "$APPCAST"

git add "$APPCAST"
git commit -m "release: appcast v${X_NOISE_VERSION}"
git push

echo "appcast.xml updated and pushed."
