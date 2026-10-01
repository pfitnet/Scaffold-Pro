#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD="$SCRIPT_DIR/build/ScaffoldPro.app"
DEST="/Applications/ScaffoldPro.app"

# --- sanity check: all sources present -------------------------------
for f in main.swift index.html Info.plist; do
    if [ ! -f "$SCRIPT_DIR/$f" ]; then
        echo "❌ Missing $f in $SCRIPT_DIR"
        exit 1
    fi
done
for d in css js resources; do
    if [ ! -d "$SCRIPT_DIR/$d" ]; then
        echo "❌ Missing $d/ folder in $SCRIPT_DIR"
        exit 1
    fi
done

echo "🧹 Cleaning previous build..."
rm -rf "$SCRIPT_DIR/build"
mkdir -p "$BUILD/Contents/MacOS"
mkdir -p "$BUILD/Contents/Resources"

# --- pick a macOS SDK this Swift compiler can build with ---------------
# A Mac can have an SDK made by a newer Swift than its compiler (after a
# partial Command Line Tools / Xcode update), which stops the build with
# "this SDK is not supported by the compiler". So: try the SDK already
# chosen (SDKROOT), then the default one, then every other installed SDK,
# and build with the first that works — no need to set SDKROOT by hand.
pick_sdk() {
    local probe_dir probe sdk dir name
    probe_dir="$(mktemp -d)"
    probe="$probe_dir/probe.swift"
    printf 'import Cocoa\nimport WebKit\nimport PDFKit\nimport UniformTypeIdentifiers\n' > "$probe"
    local candidates=()
    [ -n "$SDKROOT" ] && candidates+=("$SDKROOT")
    sdk="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
    [ -n "$sdk" ] && candidates+=("$sdk")
    for dir in /Library/Developer/CommandLineTools/SDKs \
               "$(xcode-select -p 2>/dev/null)/Platforms/MacOSX.platform/Developer/SDKs" \
               /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs; do
        [ -d "$dir" ] || continue
        for name in $(ls "$dir" | grep -E '^MacOSX[0-9.]*\.sdk$' | sort -r); do
            candidates+=("$dir/$name")
        done
    done
    for sdk in "${candidates[@]}"; do
        [ -d "$sdk" ] || continue
        if swiftc -sdk "$sdk" -target "$(uname -m)-apple-macosx12.0" -typecheck "$probe" > "$probe_dir/log" 2>&1; then
            rm -rf "$probe_dir"
            echo "$sdk"
            return 0
        fi
    done
    echo "❌ The Swift compiler can't build with any macOS SDK on this Mac:" >&2
    tail -n 5 "$probe_dir/log" >&2 || true
    echo "   Update the Command Line Tools (System Settings › General › Software Update," >&2
    echo "   or run: xcode-select --install), then run the installer again." >&2
    rm -rf "$probe_dir"
    return 1
}

echo "🔎 Checking the Swift compiler and macOS SDK..."
SDK_PATH="$(pick_sdk)" || exit 1
export SDKROOT="$SDK_PATH"
echo "   $(swiftc --version 2>/dev/null | head -n 1)"
echo "   SDK: $(basename "$SDK_PATH")"

echo "⚙️  Compiling ScaffoldPro for $(uname -m)..."
swiftc "$SCRIPT_DIR/main.swift" \
    -sdk "$SDK_PATH" \
    -target "$(uname -m)-apple-macosx12.0" \
    -framework Cocoa \
    -framework WebKit \
    -framework PDFKit \
    -framework UniformTypeIdentifiers \
    -O \
    -o "$BUILD/Contents/MacOS/ScaffoldPro"

chmod +x "$BUILD/Contents/MacOS/ScaffoldPro"

echo "📄 Assembling bundle..."
cp "$SCRIPT_DIR/Info.plist"  "$BUILD/Contents/Info.plist"

# This app is multiple HTML pages (not a single index.html), plus shared
# css/js and the bundled real price-list JSON, so — unlike the original
# single-page template — everything the app references at runtime via
# Bundle.main.resourceURL has to be copied in, preserving the same
# relative layout main.swift expects (Resources/index.html,
# Resources/css/..., Resources/js/..., Resources/resources/...).
cp "$SCRIPT_DIR/index.html" "$BUILD/Contents/Resources/index.html"
for page in price-lists.html clients.html sites.html projects.html project-detail.html stock.html accounts.html boq-editor.html quotation-editor.html invoice-editor.html delivery-note-editor.html letters.html letter-editor.html user.html marketing.html calendar.html tasks.html chat.html team.html admin.html settings.html launch.html; do
    if [ -f "$SCRIPT_DIR/$page" ]; then
        cp "$SCRIPT_DIR/$page" "$BUILD/Contents/Resources/$page"
    fi
done
cp -R "$SCRIPT_DIR/css"       "$BUILD/Contents/Resources/css"
cp -R "$SCRIPT_DIR/js"        "$BUILD/Contents/Resources/js"
cp -R "$SCRIPT_DIR/resources" "$BUILD/Contents/Resources/resources"
# Which version this is (the date of its latest change). Macs sharing a
# folder compare it, so a copy that needs updating can be spotted.
git -C "$SCRIPT_DIR" log -1 --format=%cI 2>/dev/null > "$BUILD/Contents/Resources/version.txt" || true
# The exact version and where its source is, so the app can check GitHub
# for a newer one when it opens (and run Install ScaffoldPro to update).
git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null > "$BUILD/Contents/Resources/commit.txt" || true
printf '%s\n' "$SCRIPT_DIR" > "$BUILD/Contents/Resources/source.txt"

printf 'APPL????' > "$BUILD/Contents/PkgInfo"

# App icon: built with Apple's iconutil from the hand-tuned sizes in
# icon/AppIcon.iconset (the 16/32 px versions are simplified to stay
# crisp). Falls back to the prebuilt icon/AppIcon.icns.
echo "🎨 Adding app icon..."
if command -v iconutil >/dev/null 2>&1 && [ -d "$SCRIPT_DIR/icon/AppIcon.iconset" ]; then
    iconutil -c icns "$SCRIPT_DIR/icon/AppIcon.iconset" -o "$BUILD/Contents/Resources/AppIcon.icns" \
        || cp "$SCRIPT_DIR/icon/AppIcon.icns" "$BUILD/Contents/Resources/AppIcon.icns"
elif [ -f "$SCRIPT_DIR/icon/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/icon/AppIcon.icns" "$BUILD/Contents/Resources/AppIcon.icns"
fi

echo "🔍 Validating Info.plist..."
plutil -lint "$BUILD/Contents/Info.plist"

echo "🔓 Removing quarantine..."
xattr -cr "$BUILD"

echo "🔏 Ad-hoc signing..."
codesign --force --deep --sign - "$BUILD"

# When ScaffoldPro updates itself it only needs the build: it then closes
# itself and a small helper puts the new copy in place and opens it.
if [ -n "$SCAFFOLDPRO_BUILD_ONLY" ]; then
    echo "✅ Built."
    exit 0
fi

# A copy that's still open would otherwise stay open (and `open` below
# would just bring it to the front instead of starting the new one).
# (A signal, not AppleScript: no "allow control of ScaffoldPro" prompt.)
if pgrep -xq ScaffoldPro; then
    echo "👋 Closing the open ScaffoldPro..."
    pkill -x ScaffoldPro 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq ScaffoldPro || break; sleep 0.5; done
    pkill -9 -x ScaffoldPro 2>/dev/null || true
fi

echo "📦 Installing to /Applications..."
rm -rf "$DEST"
cp -R "$BUILD" "$DEST"
xattr -cr "$DEST"

echo "🔄 Refreshing LaunchServices..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$DEST" 2>/dev/null || true

echo ""
echo "✅ Done! Launching ScaffoldPro..."
open "$DEST"
