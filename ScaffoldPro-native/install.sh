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

echo "⚙️  Compiling ScaffoldPro for $(uname -m)..."
swiftc "$SCRIPT_DIR/main.swift" \
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
for page in price-lists.html clients.html sites.html projects.html project-detail.html stock.html accounts.html boq-editor.html quotation-editor.html invoice-editor.html delivery-note-editor.html admin.html settings.html; do
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

# A copy that's still open would otherwise stay open (and `open` below
# would just bring it to the front instead of starting the new one).
if pgrep -xq ScaffoldPro; then
    echo "👋 Closing the open ScaffoldPro..."
    osascript -e 'tell application "ScaffoldPro" to quit' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq ScaffoldPro || break; sleep 0.5; done
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
