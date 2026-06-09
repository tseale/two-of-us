# MillerTime — common build tasks.
# The .xcodeproj is generated from project.yml by XcodeGen and is gitignored,
# so `make project` is the canonical way to (re)create it.

SCHEME      := MillerTime
SIMULATOR   := iPhone 17
DESTINATION := platform=iOS Simulator,name=$(SIMULATOR)
PROJECT     := MillerTime.xcodeproj
BUNDLE_ID   := com.taylorseale.millertime

# This repo lives under ~/Documents, which is iCloud Drive-synced. The File
# Provider attaches com.apple.FinderInfo / com.apple.provenance xattrs to build
# products, and codesign rejects them ("resource fork ... detritus not allowed").
# Keeping DerivedData OUTSIDE the synced folder avoids that entirely.
DERIVED_DATA := $(HOME)/Library/Developer/Xcode/DerivedData/MillerTime-local

.PHONY: help project build run clean hooks ensure-hooks bootstrap

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

# Quietly enable the tracked hooks if they aren't already. Depended on by
# `project`, so the unavoidable first `make project` on any clone also wires
# up auto-regeneration — no separate bootstrap step to remember.
ensure-hooks:
	@[ "$$(git config --get core.hooksPath)" = ".githooks" ] || { \
		git config core.hooksPath .githooks; \
		echo "✅ git hooks enabled — project.yml changes now auto-regenerate the .xcodeproj."; \
	}

project: ensure-hooks ## Regenerate MillerTime.xcodeproj from project.yml (and enable hooks)
	xcodegen generate

build: project ## Regenerate, then build for the simulator
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' -derivedDataPath '$(DERIVED_DATA)'

run: build ## Build, then install and launch on the simulator
	# Shut every simulator down first, then boot ONLY the target. With more than
	# one device booted, Simulator may foreground a different one than we install
	# to — so a fresh build lands on an off-screen device and "nothing changed".
	# Booting exactly one device guarantees the window you see is the one we use.
	xcrun simctl shutdown all 2>/dev/null || true
	xcrun simctl boot '$(SIMULATOR)'
	open -a Simulator
	xcrun simctl install '$(SIMULATOR)' \
		'$(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/MillerTime.app'
	# --terminate-running-process so a relaunch always loads the binary we just
	# installed, not the copy already running from a previous build.
	xcrun simctl launch --terminate-running-process '$(SIMULATOR)' '$(BUNDLE_ID)'

clean: ## Remove the generated project and Xcode's build output
	rm -rf $(PROJECT) build DerivedData '$(DERIVED_DATA)'

hooks: ## Point git at the tracked .githooks/ directory (run once per clone)
	git config core.hooksPath .githooks
	@echo "✅ git hooks enabled — project.yml changes will auto-regenerate the .xcodeproj."

bootstrap: hooks project ## First-time setup: enable hooks + generate the project
	@echo "✅ Ready. Open $(PROJECT) in Xcode."
