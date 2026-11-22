#!/bin/bash
# Compile and unit-test the sky's Foundation-only Swift on Linux, where there is no Xcode.
#
#   scripts/sky-core-linux-test.sh [swift test arguments…]
#   scripts/sky-core-linux-test.sh --filter NightRuleTests
#   SKY_CORE_SCRATCH=/some/dir scripts/sky-core-linux-test.sh
#
# Builds a scratch SwiftPM package OUTSIDE the repository: a module named TwoOfUs made of
#   TwoOfUs/Sky/Core/*.swift + TwoOfUs/Store/SolarClock.swift + TwoOfUs/Store/MoonClock.swift
# and a test target made of TwoOfUsTests/<Core file>Tests.swift, TwoOfUsTests/SkyCore*.swift and
# SolarClockTests.swift, so the app's own XCTest files (@testable import TwoOfUs) build unchanged.
# Swift 5 language mode, as the app. It proves the pure layer only: `make test` on a Mac is the
# real check (docs/SKY_BUILD_PLAN.md).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
DIR="${SKY_CORE_SCRATCH:-${TMPDIR:-/tmp}/two-of-us-sky-core}"
[ -x /opt/swift/usr/bin/swift ] && export PATH=/opt/swift/usr/bin:$PATH
command -v swift >/dev/null || { echo "sky-core-linux-test: no swift on PATH (expected /opt/swift/usr/bin/swift)" >&2; exit 1; }
rm -rf "$DIR/Sources" "$DIR/Tests"; mkdir -p "$DIR/Sources/TwoOfUs" "$DIR/Tests/TwoOfUsTests"
for f in "$REPO"/TwoOfUs/Sky/Core/*.swift "$REPO/TwoOfUs/Store/SolarClock.swift" "$REPO/TwoOfUs/Store/MoonClock.swift"; do
  [ -e "$f" ] && ln -sf "$f" "$DIR/Sources/TwoOfUs/"
done
# Tests: for every Core file X.swift its XTests.swift (the house naming), every TwoOfUsTests/SkyCore*.swift
# (fixtures exported from the lab, and tests that span types), and SolarClockTests.swift.
for f in "$REPO"/TwoOfUs/Sky/Core/*.swift; do
  t="$REPO/TwoOfUsTests/$(basename "$f" .swift)Tests.swift"
  [ -e "$t" ] && ln -sf "$t" "$DIR/Tests/TwoOfUsTests/"
done
for f in "$REPO"/TwoOfUsTests/SkyCore*.swift "$REPO/TwoOfUsTests/SolarClockTests.swift"; do
  [ -e "$f" ] && ln -sf "$f" "$DIR/Tests/TwoOfUsTests/"
done
cat > "$DIR/Package.swift" <<'PKG'
// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "TwoOfUsPure",
    targets: [
        .target(name: "TwoOfUs", path: "Sources/TwoOfUs", swiftSettings: [.unsafeFlags(["-swift-version", "5"])]),
        .testTarget(name: "TwoOfUsTests", dependencies: ["TwoOfUs"], path: "Tests/TwoOfUsTests", swiftSettings: [.unsafeFlags(["-swift-version", "5"])]),
    ]
)
PKG
cd "$DIR" && swift test "$@"
