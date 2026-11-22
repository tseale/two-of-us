#!/bin/sh
# Xcode Cloud post-clone hook. Runs after the repo is cloned, before Xcode Cloud
# resolves the project — which is essential here because TwoOfUs.xcodeproj is
# gitignored and generated from project.yml by XcodeGen.
set -e

cd "$CI_PRIMARY_REPOSITORY_PATH"

# Stamp Xcode Cloud's monotonically increasing build number into the project so
# every TestFlight upload gets a unique CFBundleVersion without manual bumps.
# (project.yml keeps CURRENT_PROJECT_VERSION: "1" as the local-dev default.)
if [ -n "$CI_BUILD_NUMBER" ]; then
    sed -i '' "s/^\([[:space:]]*\)CURRENT_PROJECT_VERSION:.*/\1CURRENT_PROJECT_VERSION: \"$CI_BUILD_NUMBER\"/" project.yml
fi

# Xcode no longer ships the Metal compiler: without the toolchain component the
# build of TwoOfUs/Sky/SkyField.metal fails ("missing Metal Toolchain"). Fetch
# it only where the runner's image does not already have it.
if ! xcrun metal --version >/dev/null 2>&1; then
    xcodebuild -downloadComponent MetalToolchain
fi

brew install xcodegen
xcodegen generate
