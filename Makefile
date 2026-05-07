APP = build/Build/Products/Debug/Volume\ Mixer.app

.PHONY: gen build run clean test

gen:
	xcodegen generate

build: gen
	xcodebuild -project VolumeMixer.xcodeproj -scheme VolumeMixer -configuration Debug -derivedDataPath build build

test: gen
	xcodebuild test -project VolumeMixer.xcodeproj -scheme VolumeMixer -destination 'platform=macOS'

run: build
	open $(APP)

clean:
	rm -rf build VolumeMixer.xcodeproj
