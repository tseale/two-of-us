# MillerTime — common build tasks.
# The .xcodeproj is generated from project.yml by XcodeGen and is gitignored,
# so `make project` is the canonical way to (re)create it.

SCHEME      := MillerTime
SIMULATOR   := iPhone 17
DESTINATION := platform=iOS Simulator,name=$(SIMULATOR)
PROJECT     := MillerTime.xcodeproj

.PHONY: help project build clean hooks bootstrap

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

project: ## Regenerate MillerTime.xcodeproj from project.yml
	xcodegen generate

build: project ## Regenerate, then build for the simulator
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)'

clean: ## Remove the generated project and Xcode's build output
	rm -rf $(PROJECT) build DerivedData

hooks: ## Point git at the tracked .githooks/ directory (run once per clone)
	git config core.hooksPath .githooks
	@echo "✅ git hooks enabled — project.yml changes will auto-regenerate the .xcodeproj."

bootstrap: hooks project ## First-time setup: enable hooks + generate the project
	@echo "✅ Ready. Open $(PROJECT) in Xcode."
