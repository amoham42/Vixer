APP = build/Build/Products/Debug/Vixer.app
DESTINATION = platform=macOS,arch=arm64

.PHONY: gen build run clean test

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
