#!/bin/zsh
# Build Upscroll for testers outside the App Store.
#   release.sh testflight   archive + upload to App Store Connect, for TestFlight *internal* testing
#                           (no review; testers must be users on your App Store Connect team, up to 100)
#   release.sh adhoc        archive + export an .ipa for registered iPhones (up to 100 devices/year);
#                           register each tester's device in the developer portal first
# Needs: Xcode ▸ Settings ▸ Accounts signed in to the paid Apple Developer team, and
#        DEVELOPMENT_TEAM = <Team ID> in ios/Secrets.xcconfig (or TEAM=XXXXXXXXXX).
# Don't add testers to an *external* TestFlight group: that triggers Beta App Review.
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-testflight}"
[[ "$MODE" == testflight || "$MODE" == adhoc ]] || { echo "usage: release.sh testflight|adhoc"; exit 1; }
TEAM="${TEAM:-$(grep -E '^DEVELOPMENT_TEAM' Secrets.xcconfig 2>/dev/null | sed -E 's/.*= *//')}"
[[ -n "$TEAM" ]] || { echo "Set DEVELOPMENT_TEAM in ios/Secrets.xcconfig or TEAM=…"; exit 1; }
# App Store Connect API key (optional; otherwise the Xcode account is used):
#   ASC_KEY_ID / ASC_ISSUER_ID in Secrets.xcconfig (or the environment),
#   key file at ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8 (or ASC_KEY_PATH).
cfg() { grep -E "^$1 *=" Secrets.xcconfig 2>/dev/null | sed -E 's/.*= *//'; }
ASC_KEY_ID="${ASC_KEY_ID:-$(cfg ASC_KEY_ID)}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-$(cfg ASC_ISSUER_ID)}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
AUTH=()
if [[ -n "$ASC_KEY_ID" && -n "$ASC_ISSUER_ID" ]]; then
  [[ -f "$ASC_KEY_PATH" ]] || { echo "API key file not found: $ASC_KEY_PATH"; exit 1; }
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
  echo "Using App Store Connect API key $ASC_KEY_ID"
fi
BUILD="$(date +%Y%m%d%H%M)"
OUT="build/release-$MODE"
rm -rf "$OUT"; mkdir -p "$OUT"
xcodegen generate --quiet
xcodebuild -project Upscroll.xcodeproj -scheme Upscroll -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/Upscroll.xcarchive" \
  DEVELOPMENT_TEAM="$TEAM" CURRENT_PROJECT_VERSION="$BUILD" -allowProvisioningUpdates "${AUTH[@]}" archive
xcodebuild -exportArchive -archivePath "$OUT/Upscroll.xcarchive" -exportPath "$OUT" \
  -exportOptionsPlist "scripts/ExportOptions-$MODE.plist" -allowProvisioningUpdates "${AUTH[@]}"
if [[ "$MODE" == testflight ]]; then
  echo "Uploaded build $BUILD. In App Store Connect ▸ TestFlight, add it to an INTERNAL group."
else
  echo "Ad hoc build $BUILD: $OUT/Upscroll.ipa (install with Apple Configurator, Xcode ▸ Devices, or an OTA link)."
fi
