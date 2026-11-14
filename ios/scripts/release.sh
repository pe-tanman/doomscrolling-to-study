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
BUILD="$(date +%Y%m%d%H%M)"
OUT="build/release-$MODE"
rm -rf "$OUT"; mkdir -p "$OUT"
xcodegen generate --quiet
xcodebuild -project Upscroll.xcodeproj -scheme Upscroll -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/Upscroll.xcarchive" \
  DEVELOPMENT_TEAM="$TEAM" CURRENT_PROJECT_VERSION="$BUILD" -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath "$OUT/Upscroll.xcarchive" -exportPath "$OUT" \
  -exportOptionsPlist "scripts/ExportOptions-$MODE.plist" -allowProvisioningUpdates
if [[ "$MODE" == testflight ]]; then
  echo "Uploaded build $BUILD. In App Store Connect ▸ TestFlight, add it to an INTERNAL group."
else
  echo "Ad hoc build $BUILD: $OUT/Upscroll.ipa (install with Apple Configurator, Xcode ▸ Devices, or an OTA link)."
fi
