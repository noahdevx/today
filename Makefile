# Make targets that wrap the XcodeGen + xcodebuild workflow, so common tasks run
# with a single short command (e.g. `make test`). Local and CI use the same
# entry points.

# --- Configuration ---
PROJECT      := Today.xcodeproj
SCHEME       := Today
CONFIG       := Debug
DERIVED_DATA := build
DESTINATION  := platform=macOS
APP          := $(DERIVED_DATA)/Build/Products/$(CONFIG)/Today.app

# All targets are commands, not files.
.PHONY: help generate build test run clean lint lint-fix

# Default target: list the available commands.
help:
	@echo "Available targets:"
	@echo "  make generate  - Regenerate $(PROJECT) from project.yml"
	@echo "  make build     - Build the app ($(CONFIG)) into ./$(DERIVED_DATA)"
	@echo "  make test      - Run the unit tests"
	@echo "  make run       - Build then launch the app"
	@echo "  make lint      - Run SwiftLint (static analysis)"
	@echo "  make lint-fix  - Auto-fix the violations SwiftLint can correct"
	@echo "  make clean     - Remove the build directory"

# Regenerate the Xcode project from project.yml. Depended on by build/test so a
# fresh checkout works (Today.xcodeproj is git-ignored).
generate:
	xcodegen generate

# Build the app in the Debug configuration into ./build.
build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -derivedDataPath $(DERIVED_DATA) build

# Build and run the unit tests on this Mac.
test: generate
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA)

# Build, then launch the (menu bar) app from the build output.
run: build
	open $(APP)

# Run SwiftLint (static analysis) using .swiftlint.yml.
lint:
	swiftlint

# Auto-correct the violations SwiftLint can fix.
lint-fix:
	swiftlint --fix

# Remove build artifacts.
clean:
	rm -rf $(DERIVED_DATA)
