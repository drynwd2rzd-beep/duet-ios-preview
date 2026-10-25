#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export_screenshots() {
  mkdir -p build/native-ui-screenshots
  xcrun xcresulttool export attachments --path build/NativeUITests.xcresult --output-path build/native-ui-screenshots || true
}
trap export_screenshots EXIT
xcrun simctl list devices available --json > build/simulators.json
DEVICE=$(python3 -c 'import json; d=json.load(open("build/simulators.json")); phones=[x for group in d["devices"].values() for x in group if "iPhone" in x["name"] and x.get("isAvailable")]; assert phones,"No iPhone simulator installed"; print(phones[0]["udid"])')
echo "Booting iPhone simulator: $DEVICE"
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcodebuild -project Duet.xcodeproj -scheme Duet -configuration Debug -destination "platform=iOS Simulator,id=$DEVICE" -parallel-testing-enabled NO -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120 -resultBundlePath "$PWD/build/NativeUITests.xcresult" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test 2>&1 | tee build/native-tests.log
