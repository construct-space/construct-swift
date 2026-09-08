# Construct (Swift) — dev tasks.
# Pins the Xcode 27 toolchain without requiring `sudo xcode-select -s`.
# Override with: make build DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

DEVELOPER_DIR ?= /Applications/Xcode-beta.app/Contents/Developer
export DEVELOPER_DIR

PROJECT := Construct.xcodeproj
SCHEME := Construct
DEST := platform=macOS

.PHONY: gen build test run clean

gen:
	xcodegen generate

build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' build

test: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' test

run: build
	@APP=$$(find ~/Library/Developer/Xcode/DerivedData -name 'Construct.app' -path '*Debug*' | head -1); \
	echo "Launching $$APP"; open "$$APP"

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
