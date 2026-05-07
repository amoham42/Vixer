APP = build/Build/Products/Debug/Vixer.app
DESTINATION = platform=macOS,arch=arm64
VIXER_BUNDLE_OWNER ?= $(shell basename "$$HOME" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]-')
export VIXER_BUNDLE_ID ?= app.$(VIXER_BUNDLE_OWNER).vixer
export VIXER_TEST_BUNDLE_ID ?= $(VIXER_BUNDLE_ID).tests

.PHONY: gen build run clean test print-bundle-id

print-bundle-id:
	@echo $(VIXER_BUNDLE_ID)

gen:
	xcodegen generate

build: gen
	xcodebuild -project Vixer.xcodeproj -scheme Vixer -configuration Debug -derivedDataPath build -destination '$(DESTINATION)' build

test: gen
	xcodebuild test -project Vixer.xcodeproj -scheme Vixer -destination '$(DESTINATION)'

run: build
	open $(APP)

clean:
	rm -rf build Vixer.xcodeproj
