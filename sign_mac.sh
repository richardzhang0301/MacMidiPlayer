#!/bin/bash
# Sign and notarize MacMidiPlayer macOS app bundle

set -e

echo "============================================"
echo "MacMidiPlayer - Sign & Notarize"
echo "============================================"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR" && pwd)"
cd "$PROJECT_ROOT"

APP_NAME="MacMidiPlayer"
ENTITLEMENTS="MacMidiPlayer.entitlements"
NOTARY_KEYCHAIN_PROFILE="${NOTARIZE_PROFILE:-notarytool-password}"

# Check entitlements file exists
if [ ! -f "$ENTITLEMENTS" ]; then
    echo "❌ Error: Entitlements file not found at $ENTITLEMENTS"
    exit 1
fi

# Find app bundle to sign (from build/ after build.sh)
APP_BUNDLE="build/${APP_NAME}.app"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ Error: App bundle not found at $APP_BUNDLE"
    echo "Please run ./build.sh first."
    exit 1
fi

echo "Found app bundle to sign:"
echo "  - $APP_BUNDLE"
echo ""

# Show available signing identities
echo "Available code signing identities:"
IDENTITIES_OUTPUT=$(security find-identity -v -p codesigning 2>/dev/null || echo "")
if [ -z "$IDENTITIES_OUTPUT" ]; then
    echo "  (No identities found)"
else
    echo "$IDENTITIES_OUTPUT"
fi
echo ""

# Get signing identity
IDENTITY_NUMBER="$1"
if [ -n "$IDENTITY_NUMBER" ]; then
    if [ "$IDENTITY_NUMBER" = "adhoc" ] || [ "$IDENTITY_NUMBER" = "-" ]; then
        SIGNING_IDENTITY="-"
        echo "Using ad-hoc signing (local testing only, cannot be notarized)."
    else
        SIGNING_IDENTITY=$(echo "$IDENTITIES_OUTPUT" | awk -v num="$IDENTITY_NUMBER" 'match($0, "^[[:space:]]*" num "\\)") {match($0, /"[^"]+"/); print substr($0, RSTART+1, RLENGTH-2); exit}')
        if [ -z "$SIGNING_IDENTITY" ]; then
            echo "❌ Error: Identity number $IDENTITY_NUMBER not found."
            exit 1
        fi
        echo "Using signing identity #${IDENTITY_NUMBER}: $SIGNING_IDENTITY"
    fi
else
    echo "Enter signing identity number from the list above,"
    echo "or type 'adhoc' for ad-hoc signing (local testing only):"
    read -r IDENTITY_INPUT

    if [ -z "$IDENTITY_INPUT" ]; then
        echo "❌ No signing identity supplied."
        exit 1
    fi

    if [ "$IDENTITY_INPUT" = "adhoc" ] || [ "$IDENTITY_INPUT" = "-" ]; then
        SIGNING_IDENTITY="-"
        echo "Using ad-hoc signing (local testing only, cannot be notarized)."
    else
        SIGNING_IDENTITY=$(echo "$IDENTITIES_OUTPUT" | awk -v num="$IDENTITY_INPUT" 'match($0, "^[[:space:]]*" num "\\)") {match($0, /"[^"]+"/); print substr($0, RSTART+1, RLENGTH-2); exit}')
        if [ -z "$SIGNING_IDENTITY" ]; then
            echo "❌ Error: Identity number $IDENTITY_INPUT not found."
            exit 1
        fi
        echo "Using signing identity #${IDENTITY_INPUT}: $SIGNING_IDENTITY"
    fi
fi
echo ""

# Function to sign a single app bundle
sign_app_bundle() {
    local APP_BUNDLE="$1"
    local BUNDLE_NAME=$(basename "$APP_BUNDLE")

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Signing: $BUNDLE_NAME"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Sign native libraries first (dylibs in Frameworks, MacOS, or any subfolder)
    echo "🔐 Signing native libraries..."
    find "$APP_BUNDLE/Contents" \( -name "*.dylib" -o -name "*.so" \) -print0 2>/dev/null | while IFS= read -r -d '' lib; do
        echo "  $(basename "$lib") ($(dirname "$lib" | sed "s|.*Contents/||"))"
        codesign --force --options runtime \
            --entitlements "$ENTITLEMENTS" \
            --sign "$SIGNING_IDENTITY" \
            --timestamp \
            "$lib" || echo "    ⚠️  Warning: Could not sign $(basename "$lib")"
    done

    # Sign any embedded frameworks
    echo ""
    echo "🔐 Signing embedded frameworks..."
    find "$APP_BUNDLE/Contents/Frameworks" -name "*.framework" -maxdepth 1 -print0 2>/dev/null | while IFS= read -r -d '' fw; do
        echo "  $(basename "$fw")"
        codesign --force --options runtime \
            --entitlements "$ENTITLEMENTS" \
            --sign "$SIGNING_IDENTITY" \
            --timestamp \
            "$fw" || echo "    ⚠️  Warning: Could not sign $(basename "$fw")"
    done

    # Sign the app bundle
    echo ""
    echo "🔐 Signing app bundle..."
    codesign --force --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGNING_IDENTITY" \
        --timestamp \
        "$APP_BUNDLE"

    # Verify signature
    echo ""
    echo "✅ Verifying signature..."
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

    echo ""
    echo "✅ $BUNDLE_NAME signed successfully!"
}

# Function to notarize a single app bundle
notarize_app_bundle() {
    local APP_BUNDLE="$1"
    local BUNDLE_NAME=$(basename "$APP_BUNDLE")
    local ZIP_PATH="${APP_BUNDLE}.zip"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Notarizing: $BUNDLE_NAME"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Create ZIP for notarization
    echo "📦 Creating ZIP for notarization..."
    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

    # Submit for notarization and capture output
    echo ""
    echo "📤 Submitting for notarization..."
    local NOTARY_OUTPUT
    NOTARY_OUTPUT=$(xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait 2>&1)
    echo "$NOTARY_OUTPUT"

    # Check if notarization was accepted
    if echo "$NOTARY_OUTPUT" | grep -q "status: Accepted"; then
        echo ""
        echo "✅ Notarization accepted!"
    else
        echo ""
        echo "❌ Notarization may have failed. Check the output above."
        echo "You can check the log with: xcrun notarytool log <submission-id> --keychain-profile $NOTARY_KEYCHAIN_PROFILE"
        return 1
    fi

    # Staple the notarization ticket with retry
    echo ""
    echo "📎 Stapling notarization ticket..."
    local MAX_RETRIES=5
    local RETRY_DELAY=10
    local attempt=1

    while [ $attempt -le $MAX_RETRIES ]; do
        if xcrun stapler staple "$APP_BUNDLE" 2>&1; then
            echo ""
            echo "✅ Stapling successful!"
            xcrun stapler validate "$APP_BUNDLE"
            echo ""
            echo "✅ $BUNDLE_NAME notarized and stapled successfully!"
            return 0
        else
            if [ $attempt -lt $MAX_RETRIES ]; then
                echo "⏳ Stapling failed, waiting ${RETRY_DELAY}s before retry ($attempt/$MAX_RETRIES)..."
                sleep $RETRY_DELAY
                attempt=$((attempt + 1))
            else
                echo ""
                echo "⚠️  Stapling failed after $MAX_RETRIES attempts."
                echo "The app is notarized but not stapled. You can try stapling manually later:"
                echo "  xcrun stapler staple \"$APP_BUNDLE\""
                return 0
            fi
        fi
    done
}

# Sign the app bundle
sign_app_bundle "$APP_BUNDLE"

# Notarize if not ad-hoc signing
if [ "$SIGNING_IDENTITY" != "-" ]; then
    echo ""
    echo "============================================"
    echo "📤 Starting Notarization"
    echo "============================================"

    notarize_app_bundle "$APP_BUNDLE"
else
    echo ""
    echo "⚠️  Skipping notarization (ad-hoc signed apps cannot be notarized)"
fi

echo ""
echo "============================================"
echo "✅ All operations complete!"
echo "============================================"
echo ""
echo "Signed app bundle:"
echo "  - $APP_BUNDLE"
if [ "$SIGNING_IDENTITY" != "-" ]; then
    echo "  ZIP: ${APP_BUNDLE}.zip"
fi
echo ""
if [ "$SIGNING_IDENTITY" = "-" ]; then
    echo "Note: Ad-hoc signed apps are for local testing only."
    echo "For distribution, sign with a Developer ID certificate."
else
    echo "App is signed and notarized for distribution."
fi
echo ""
