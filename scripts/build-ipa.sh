#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcodebuild -project Duet.xcodeproj -scheme Duet -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$PWD/build/DerivedData" -resultBundlePath "$PWD/build/Build.xcresult" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= CURRENT_PROJECT_VERSION="${BUILD_NUMBER:-1}" build 2>&1 | tee build/xcodebuild.log
APP="$PWD/build/DerivedData/Build/Products/Release-iphoneos/Duet.app"
test -f "$APP/Duet"
mkdir -p build/package/Payload
ditto "$APP" build/package/Payload/Duet.app
ditto -c -k --keepParent build/package/Payload build/Duet-Native-unsigned.ipa
python3 scripts/validate.py --ipa build/Duet-Native-unsigned.ipa
shasum -a 256 build/Duet-Native-unsigned.ipa > build/SHA256SUMS.txt
