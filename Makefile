# GlossyBar — build & app-bundle helpers.
#
# `swift build` produces a plain mach-o executable. macOS apps need a
# `.app` bundle (Info.plist, menu bar). This Makefile wraps `swift build`
# and assembles a minimal bundle in `dist/`.
#
# Two flows:
#   make app       — dev build, ad-hoc signed, fast iteration
#   make release   — Developer ID signed + notarized + stapled + DMG

CONFIG ?= debug
BIN_NAME = GlossyBar
APP_NAME = GlossyBar.app
BUILD_DIR = .build/$(CONFIG)
DIST_DIR = dist
APP_BUNDLE = $(DIST_DIR)/$(APP_NAME)

# Bypass the user's global git config for SPM (https:// → ssh:// rewrites
# break version resolution in SPM's subprocess).
SWIFT = GIT_CONFIG_GLOBAL=/dev/null swift

# Release configuration. Override via env in CI.
DEVELOPER_ID   ?= Developer ID Application: MARTIN JOHANNES RYBERG LAUDE (X67GNG6U35)
NOTARY_PROFILE ?= glossybar-notary
ENTITLEMENTS   := BundleResources/GlossyBar.entitlements
VERSION         = $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" BundleResources/Info.plist)
DMG_NAME        = GlossyBar-$(VERSION).dmg

.PHONY: all build app run release-app sign dmg notarize release clean test resolve

all: app

resolve:
	$(SWIFT) package resolve

build: resolve
	$(SWIFT) build -c $(CONFIG)

app: build
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(BUILD_DIR)/$(BIN_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(BIN_NAME)"
	@cp "BundleResources/Info.plist" "$(APP_BUNDLE)/Contents/Info.plist"
	@printf "APPL????" > "$(APP_BUNDLE)/Contents/PkgInfo"
	@# Embed Sparkle.framework. SPM links against the dylib but doesn't copy
	@# the xcframework into the bundle for executable products — we have to.
	@# Drop Downloader.xpc (only needed by sandboxed apps; we download directly).
	@FW=$$(find .build/artifacts -type d -name "Sparkle.framework" -path "*macos*" | head -1); \
	if [ -z "$$FW" ]; then echo "Sparkle.framework not found — run 'swift package resolve'"; exit 1; fi; \
	mkdir -p "$(APP_BUNDLE)/Contents/Frameworks"; \
	rm -rf "$(APP_BUNDLE)/Contents/Frameworks/Sparkle.framework"; \
	cp -R "$$FW" "$(APP_BUNDLE)/Contents/Frameworks/Sparkle.framework"; \
	rm -rf "$(APP_BUNDLE)/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"; \
	xattr -cr "$(APP_BUNDLE)/Contents/Frameworks/Sparkle.framework"
	@# Ensure the binary can find embedded frameworks via @executable_path.
	@otool -l "$(APP_BUNDLE)/Contents/MacOS/$(BIN_NAME)" | grep -q "path @executable_path/../Frameworks" \
		|| install_name_tool -add_rpath "@executable_path/../Frameworks" "$(APP_BUNDLE)/Contents/MacOS/$(BIN_NAME)"
	@# Ad-hoc re-sign the whole bundle (install_name_tool invalidated the
	@# signature). --deep is fine for dev; release uses scripts/sign.sh.
	@codesign --force --deep --sign - "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"

run: app
	@# `open` on a .app just foregrounds the existing instance; kill the
	@# running copy first so we always launch the freshly built binary.
	@pkill -x $(BIN_NAME) 2>/dev/null; true
	@sleep 0.2
	open "$(APP_BUNDLE)"

# --- Release pipeline ----------------------------------------------------

release-app:
	$(MAKE) app CONFIG=release

sign: release-app
	./scripts/sign.sh "$(APP_BUNDLE)" "$(DEVELOPER_ID)" "$(ENTITLEMENTS)"

dmg: sign
	./scripts/build-dmg.sh "$(APP_BUNDLE)" "$(DIST_DIR)/$(DMG_NAME)" "$(DEVELOPER_ID)"

notarize: dmg
	xcrun notarytool submit "$(DIST_DIR)/$(DMG_NAME)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(APP_BUNDLE)"
	xcrun stapler staple "$(DIST_DIR)/$(DMG_NAME)"

release: notarize
	@echo "Release ready: $(DIST_DIR)/$(DMG_NAME)"

# Cut a new release: bump CFBundleShortVersionString, commit only the
# Info.plist change, tag vX.Y.Z, push branch + tag. CI handles the actual
# build/sign/notarize/publish. Default kind is patch.
.PHONY: ship ship-patch ship-minor ship-major

ship: ship-patch

ship-patch: KIND=patch
ship-minor: KIND=minor
ship-major: KIND=major

ship-patch ship-minor ship-major:
	@./scripts/bump-version.sh $(KIND)
	@NEW=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" BundleResources/Info.plist); \
		git add BundleResources/Info.plist && \
		git commit -m "Release $$NEW" && \
		git tag "v$$NEW" && \
		git push origin HEAD "v$$NEW" && \
		echo "Pushed v$$NEW — CI: https://github.com/MartinRybergLaude/glossybar/actions"

# -------------------------------------------------------------------------

clean:
	rm -rf .build dist

test: resolve
	$(SWIFT) test
