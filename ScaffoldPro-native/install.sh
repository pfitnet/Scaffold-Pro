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
for d in Sources css js resources; do
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

# Kept between builds (not in build/, which is cleared each time): the SDK
# that worked, the compiled pieces, and the last compiled ScaffoldPro with
# the fingerprint of what it was built from. In this Mac's Caches, not the
# project folder: that may be in iCloud, which would upload them all (or
# take them off the Mac to save space).
CACHE="$HOME/Library/Caches/ScaffoldPro Build"
mkdir -p "$CACHE" 2>/dev/null || { CACHE="$SCRIPT_DIR/.build-cache"; mkdir -p "$CACHE"; }

echo "🔎 Checking the Swift compiler and macOS SDK..."
SWIFT_VERSION="$(swiftc --version 2>/dev/null | head -n 1)"
# The SDK that worked last time, while the compiler is the same one:
# checking every SDK again takes a while.
SDK_FROM_CACHE=""
if [ -f "$CACHE/sdk" ] && [ "$(sed -n 2p "$CACHE/sdk")" = "$SWIFT_VERSION" ] && [ -d "$(sed -n 1p "$CACHE/sdk")" ]; then
    SDK_PATH="$(sed -n 1p "$CACHE/sdk")"
    SDK_FROM_CACHE=1
else
    SDK_PATH="$(pick_sdk)" || exit 1
    printf '%s\n%s\n' "$SDK_PATH" "$SWIFT_VERSION" > "$CACHE/sdk"
fi
export SDKROOT="$SDK_PATH"
echo "   $SWIFT_VERSION"
echo "   SDK: $(basename "$SDK_PATH")"

ARCH="$(uname -m)"
CORES="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
base_flags() {
    FLAGS=(-sdk "$SDK_PATH" -target "$ARCH-apple-macosx12.0"
           -framework Cocoa -framework WebKit -framework PDFKit -framework Vision -framework UniformTypeIdentifiers
           -O)
}
base_flags
# The program's code: main.swift (starting the app) and Sources/*.swift.
SOURCES=("$SCRIPT_DIR/main.swift")
for f in "$SCRIPT_DIR"/Sources/*.swift; do SOURCES+=("$f"); done
# What the program is built from: its code, the compiler, the SDK and the
# settings. When none of these changed (an update to the pages only), the
# last build is used as it is — no compiling.
fingerprint() {
    { cat "${SOURCES[@]}" | shasum -a 256 | cut -d' ' -f1; echo "$SWIFT_VERSION|$SDK_PATH|${FLAGS[*]}"; } | shasum -a 256 | cut -c1-20
}
# The files are compiled side by side, one per core, and only those that
# changed (and what depends on them) since the last build: the compiled
# pieces are kept in the cache's objects folder. If that ever fails, it's
# compiled again from nothing. Code that's slow to type-check is noted.
OBJECTS="$CACHE/objects"
BUILD_LOG="$HOME/Library/Logs/ScaffoldPro Build.log"
mkdir -p "$HOME/Library/Logs" 2>/dev/null || true
output_file_map() {
    mkdir -p "$OBJECTS"
    local n=0 f base sep
    {
        echo '{'
        printf '  "": { "swift-dependencies": "%s/module.swiftdeps" },\n' "$OBJECTS"
        for f in "${SOURCES[@]}"; do
            n=$((n + 1)); base="$(basename "$f" .swift)"
            sep=","; [ "$n" -eq "${#SOURCES[@]}" ] && sep=""
            printf '  "%s": { "object": "%s/%s.o", "swift-dependencies": "%s/%s.swiftdeps" }%s\n' "$f" "$OBJECTS" "$base" "$OBJECTS" "$base" "$sep"
        done
        echo '}'
    } > "$OBJECTS/output-file-map.json"
}
swift_build() {
    swiftc "${SOURCES[@]}" "${FLAGS[@]}" -module-name ScaffoldPro -j "$CORES" "$@" \
        -Xfrontend -warn-long-function-bodies=400 \
        -Xfrontend -warn-long-expression-type-checking=200 2>&1 | tee -a "$BUILD_LOG"
    return "${PIPESTATUS[0]}"
}
compile() {
    output_file_map
    if swift_build -incremental -output-file-map "$OBJECTS/output-file-map.json" -o "$1"; then return 0; fi
    # A mistake in the code fails the same way from nothing: don't wait twice.
    grep -Eq '\.swift:[0-9]+:[0-9]+: error:' "$BUILD_LOG" 2>/dev/null && return 1
    echo "   Compiling everything again..."
    rm -rf "$OBJECTS"
    swift_build -o "$1"
}

CACHED="$CACHE/ScaffoldPro-$(fingerprint)"
if [ -s "$CACHED" ]; then
    echo "⚙️  Compiling ScaffoldPro for $ARCH... no need: the app's code hasn't changed since the last build, so that build is used."
    cp "$CACHED" "$BUILD/Contents/MacOS/ScaffoldPro"
else
    echo "⚙️  Compiling ScaffoldPro for $ARCH (on $CORES cores)..."
    echo "ScaffoldPro build, $(date)" > "$BUILD_LOG" 2>/dev/null || BUILD_LOG=/dev/null
    STARTED=$(date +%s)
    if ! compile "$BUILD/Contents/MacOS/ScaffoldPro"; then
        # The remembered SDK may not suit any more: choose again, once.
        [ -n "$SDK_FROM_CACHE" ] || exit 1
        grep -Eq '\.swift:[0-9]+:[0-9]+: error:' "$BUILD_LOG" 2>/dev/null && exit 1
        echo "   Trying the other macOS SDKs..."
        rm -f "$CACHE/sdk"
        rm -rf "$OBJECTS"
        unset SDKROOT
        SDK_PATH="$(pick_sdk)" || exit 1
        export SDKROOT="$SDK_PATH"
        printf '%s\n%s\n' "$SDK_PATH" "$SWIFT_VERSION" > "$CACHE/sdk"
        base_flags
        CACHED="$CACHE/ScaffoldPro-$(fingerprint)"
        compile "$BUILD/Contents/MacOS/ScaffoldPro"
    fi
    echo "   Compiled in $(( $(date +%s) - STARTED ))s." | tee -a "$BUILD_LOG"
    # Only the newest build is kept.
    rm -f "$CACHE"/ScaffoldPro-*
    cp "$BUILD/Contents/MacOS/ScaffoldPro" "$CACHED"
fi

chmod +x "$BUILD/Contents/MacOS/ScaffoldPro"

echo "📄 Assembling bundle..."
cp "$SCRIPT_DIR/Info.plist"  "$BUILD/Contents/Info.plist"

# This app is multiple HTML pages (not a single index.html), plus shared
# css/js and the bundled real price-list JSON, so — unlike the original
# single-page template — everything the app references at runtime via
# Bundle.main.resourceURL has to be copied in, preserving the same
# relative layout main.swift expects (Resources/index.html,
# Resources/css/..., Resources/js/..., Resources/resources/...).
# Every page, so a new one is never left out.
for page in "$SCRIPT_DIR"/*.html; do
    cp "$page" "$BUILD/Contents/Resources/$(basename "$page")"
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
xattr -cr "$BUILD" 2>/dev/null || true

echo "🔏 Ad-hoc signing..."
# Signed as a clean copy in a temporary folder: when the project is in a
# folder kept in iCloud (Desktop & Documents), macOS puts Finder
# information back on the files as fast as it's removed, and codesign
# refuses to sign with it there ("resource fork, Finder information, or
# similar detritus not allowed"). ditto copies without it.
SIGN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/scaffoldpro-sign.XXXXXX")"
trap 'rm -rf "$SIGN_DIR"' EXIT
SIGNED="$SIGN_DIR/ScaffoldPro.app"
ditto --norsrc --noextattr --noacl "$BUILD" "$SIGNED"
xattr -cr "$SIGNED" 2>/dev/null || true

# Signed with the same certificate every time, so macOS knows each update
# is the same app and keeps the permissions already given (files and
# folders, App Management…). An ad-hoc signature ("-") is new with every
# build, so macOS would ask again after each update. The certificate is
# made once, on this Mac, and kept in the login keychain; it never leaves
# this Mac.
IDENTITY="ScaffoldPro Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
has_identity() { security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; }
make_identity() {
    local dir; dir="$(mktemp -d "${TMPDIR:-/tmp}/scaffoldpro-cert.XXXXXX")"
    cat > "$dir/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
    # macOS's own openssl (LibreSSL) writes a .p12 the keychain can read.
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$dir/cert.cnf" \
        -keyout "$dir/key.pem" -out "$dir/cert.pem" >/dev/null 2>&1 &&
    /usr/bin/openssl pkcs12 -export -inkey "$dir/key.pem" -in "$dir/cert.pem" -name "$IDENTITY" \
        -out "$dir/id.p12" -passout pass:scaffoldpro >/dev/null 2>&1 &&
    security import "$dir/id.p12" -k "$KEYCHAIN" -P scaffoldpro -T /usr/bin/codesign >/dev/null 2>&1
    local ok=$?
    rm -rf "$dir"
    return $ok
}
SIGN_AS="-"
if has_identity || { echo "   Making this Mac's signing certificate (once)..."; make_identity && has_identity; }; then
    SIGN_AS="$IDENTITY"
fi
sign_with_identity() { codesign --force --deep --sign "$SIGN_AS" "$SIGNED" 2>"$SIGN_DIR/sign.log"; }
# If macOS won't sign with it until it's trusted for code signing, trust it
# (asks for your password once), then try again.
trust_identity() {
    security find-certificate -c "$IDENTITY" -p "$KEYCHAIN" > "$SIGN_DIR/cert.pem" 2>/dev/null &&
    security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$SIGN_DIR/cert.pem" >/dev/null 2>&1
}
if [ "$SIGN_AS" != "-" ] && { sign_with_identity || { trust_identity && sign_with_identity; }; }; then
    echo "   Signed as “$IDENTITY” — permissions carry over to updates."
else
    [ "$SIGN_AS" != "-" ] && { echo "   ⚠️  Couldn't sign with “$IDENTITY” (macOS may ask once to let codesign use it — choose Always Allow):"; sed 's/^/      /' "$SIGN_DIR/sign.log"; }
    echo "   Signing ad hoc instead (macOS may ask for permissions again after updates)."
    codesign --force --deep --sign - "$SIGNED"
fi
# The signed copy goes back into build/ (the in-app updater installs from
# there); extended attributes aren't part of the signature.
rm -rf "$BUILD"
ditto --norsrc --noextattr --noacl "$SIGNED" "$BUILD"

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
ditto --norsrc --noextattr --noacl "$SIGNED" "$DEST"
xattr -cr "$DEST" 2>/dev/null || true

echo "🔄 Refreshing LaunchServices..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$DEST" 2>/dev/null || true

echo ""
echo "✅ Done! Launching ScaffoldPro..."
open "$DEST"
