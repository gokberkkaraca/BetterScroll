APP := build/BetterScroll.app
SIGN_IDENTITY ?= Apple Development
VERSION ?= $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
SWIFTC := xcrun swiftc -swift-version 5 -module-cache-path build/module-cache -target $(shell uname -m)-apple-macosx12.0
SPARKLE_VERSION := 2.10.1
SPARKLE_DIR := build/sparkle-$(SPARKLE_VERSION)
SPARKLE_FEED_URL ?= https://github.com/gokberkkaraca/BetterScroll/releases/latest/download/appcast.xml
export SPARKLE_PUBLIC_KEY SPARKLE_FEED_URL
ifdef SPARKLE_PUBLIC_KEY
build: sparkle
UPDATE_FLAGS := -D SPARKLE_UPDATES -F $(SPARKLE_DIR) -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks
endif

.PHONY: build check dmg sparkle
build: build/BetterScroll.icns build/MenuMouse.png
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp build/BetterScroll.icns build/MenuMouse.png "$(APP)/Contents/Resources/"
	cp Info.plist "$(APP)/Contents/"
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" "$(APP)/Contents/Info.plist"
	plutil -replace CFBundleVersion -string "$(VERSION)" "$(APP)/Contents/Info.plist"
	rm -rf "$(APP)/Contents/Frameworks/Sparkle.framework"
ifdef SPARKLE_PUBLIC_KEY
	printf '%s\n' "$$SPARKLE_PUBLIC_KEY" | grep -Eq '^[A-Za-z0-9+/]{43}=$$'
	ditto "$(SPARKLE_DIR)/Sparkle.framework" "$(APP)/Contents/Frameworks/Sparkle.framework"
	plutil -insert SUPublicEDKey -string "$$SPARKLE_PUBLIC_KEY" "$(APP)/Contents/Info.plist"
	plutil -insert SUFeedURL -string "$$SPARKLE_FEED_URL" "$(APP)/Contents/Info.plist"
	plutil -insert SUEnableAutomaticChecks -bool NO "$(APP)/Contents/Info.plist"
	plutil -insert SUAllowsAutomaticUpdates -bool NO "$(APP)/Contents/Info.plist"
	plutil -insert SUVerifyUpdateBeforeExtraction -bool YES "$(APP)/Contents/Info.plist"
	plutil -insert SURequireSignedFeed -bool YES "$(APP)/Contents/Info.plist"
	@set -e; framework="$(APP)/Contents/Frameworks/Sparkle.framework"; \
		for component in Autoupdate Updater.app XPCServices/Installer.xpc; do \
			codesign --force $(SIGN_FLAGS) --sign "$(SIGN_IDENTITY)" "$$framework/Versions/B/$$component"; \
		done; \
		codesign --force $(SIGN_FLAGS) --preserve-metadata=entitlements --sign "$(SIGN_IDENTITY)" "$$framework/Versions/B/XPCServices/Downloader.xpc"; \
		codesign --force $(SIGN_FLAGS) --sign "$(SIGN_IDENTITY)" "$$framework"
endif
	$(SWIFTC) $(UPDATE_FLAGS) -O Sources/*.swift -o "$(APP)/Contents/MacOS/BetterScroll"
	codesign --force $(SIGN_FLAGS) --sign "$(SIGN_IDENTITY)" "$(APP)"

sparkle: $(SPARKLE_DIR)/Sparkle.framework

$(SPARKLE_DIR)/Sparkle.framework:
	@set -e; mkdir -p build; stage=$$(mktemp -d build/sparkle.XXXXXX); trap 'rm -rf "$$stage"' EXIT; \
		curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$(SPARKLE_VERSION)/Sparkle-$(SPARKLE_VERSION).tar.xz" -o "$$stage/Sparkle.tar.xz"; \
		printf '%s  %s\n' 1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27 "$$stage/Sparkle.tar.xz" | shasum -a 256 -c -; \
		mkdir "$$stage/package"; tar -xJf "$$stage/Sparkle.tar.xz" -C "$$stage/package"; \
		mv "$$stage/package" "$(SPARKLE_DIR)"
check:
	mkdir -p build
	$(SWIFTC) Sources/HID.swift Sources/Scroll.swift Sources/ThumbGesture.swift Sources/Updates.swift Tests/ScrollCheck.swift -o build/scroll-check
	build/scroll-check

build/MenuMouse.png: Assets/MenuMouse.svg
	mkdir -p build
	sips -s format png "$<" --out "$@" >/dev/null

build/BetterScroll.icns: Assets/BetterScroll.svg
	mkdir -p build/BetterScroll.iconset
	sips -s format png "$<" --out build/icon-master.png >/dev/null
	set -e; for size in 16 32 128 256 512; do \
		sips -z $$size $$size build/icon-master.png --out build/BetterScroll.iconset/icon_$${size}x$${size}.png >/dev/null; \
		double=$$((size * 2)); sips -z $$double $$double build/icon-master.png --out build/BetterScroll.iconset/icon_$${size}x$${size}@2x.png >/dev/null; \
	done
	iconutil -c icns build/BetterScroll.iconset -o "$@"

dmg: build
	@set -e; stage=$$(mktemp -d build/dmg.XXXXXX); trap 'rm -rf "$$stage"' EXIT; \
		ditto "$(APP)" "$$stage/BetterScroll.app"; \
		ln -s /Applications "$$stage/Applications"; \
		hdiutil create -ov -format UDZO -fs HFS+ -volname "BetterScroll" -srcfolder "$$stage" "build/BetterScroll.dmg"
