#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcodebuild \
  -project Duet.xcodeproj \
  -scheme Duet \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "$PWD/build/Duet.xcarchive" \
  -resultBundlePath "$PWD/build/Build.xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  CURRENT_PROJECT_VERSION="${BUILD_NUMBER:-1}" \
  archive 2>&1 | tee build/xcodebuild.log

APP="$PWD/build/Duet.xcarchive/Products/Applications/Duet.app"
test -f "$APP/Duet"
test -f "$APP/Web/index.html"
test -f "$APP/Web/assets/lucide.js"
mkdir -p build/package/Payload
ditto "$APP" build/package/Payload/Duet.app
ditto -c -k --keepParent build/package/Payload build/Duet-Preview-unsigned.ipa
python3 scripts/validate.py --ipa build/Duet-Preview-unsigned.ipa
shasum -a 256 build/Duet-Preview-unsigned.ipa > build/SHA256SUMS.txt
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo '## Duet iPhone preview'
    echo 'Download **Duet-unsigned-ipa** below. The IPA requires your own signing before installation.'
    echo 'Includes local chat UI, native iOS 26+ Liquid Glass navigation and native camera entry.'
    echo 'AI account connections and real replies are not implemented in this preview.'
  } >> "$GITHUB_STEP_SUMMARY"
fi
