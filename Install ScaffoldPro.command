#!/bin/bash
# Double-click to build ScaffoldPro and install it into /Applications
# (runs ScaffoldPro-native/install.sh, then opens the app).
#
# Copy this file anywhere you like, e.g. your Desktop. The first time it
# finds the ScaffoldPro-native folder by itself (or asks you to drag it
# into the window) and remembers where it is. If that folder is a git
# copy of Scaffold-Pro, it fetches the latest version first.

CONFIG="$HOME/.scaffoldpro-install-path"

finish() {
    echo ""
    read -r -p "Press Return to close this window." _
    exit "${1:-0}"
}

# A folder with install.sh and main.swift in it.
is_app_dir() { [ -n "$1" ] && [ -f "$1/install.sh" ] && [ -f "$1/main.swift" ]; }

# The folder itself, or the ScaffoldPro-native folder inside it.
app_dir_in() {
    if is_app_dir "$1"; then echo "$1"; return 0; fi
    if is_app_dir "$1/ScaffoldPro-native"; then echo "$1/ScaffoldPro-native"; return 0; fi
    return 1
}

find_app_dir() {
    # 1. Where it was last time.
    if [ -f "$CONFIG" ]; then
        app_dir_in "$(cat "$CONFIG")" && return 0
    fi
    # 2. Next to this file (when it's run from inside the Scaffold-Pro folder).
    app_dir_in "$(cd "$(dirname "$0")" && pwd)" && return 0
    # 3. The usual places.
    local base name
    for base in "$HOME" "$HOME/Desktop" "$HOME/Documents" "$HOME/Downloads" "$HOME/Developer" \
                "$HOME/Projects" "$HOME/GitHub" "$HOME/Documents/GitHub" "$HOME/Code"; do
        for name in "Scaffold-Pro" "Scaffold-Pro-main" "ScaffoldPro" "ScaffoldPro-native" "ScaffoldPro-native-updated"; do
            app_dir_in "$base/$name" && return 0
        done
    done
    # 4. Spotlight.
    local found
    while IFS= read -r found; do
        case "$found" in */build/*|*/.Trash/*) continue ;; esac
        app_dir_in "$(dirname "$found")" && return 0
    done < <(mdfind -name "install.sh" 2>/dev/null | grep '/ScaffoldPro-native/install\.sh$')
    return 1
}

echo "ScaffoldPro installer"
echo "====================="
echo ""

APP_DIR="$(find_app_dir)"
while ! is_app_dir "$APP_DIR"; do
    echo "Where is the ScaffoldPro-native folder?"
    echo "Drag it (or the Scaffold-Pro folder it's in) from Finder into this window, then press Return."
    read -r -p "> " typed
    # Dragging in gives e.g.  /Users/me/My\ Folder/ScaffoldPro-native   (maybe quoted, with a space after)
    typed="$(printf '%s' "$typed" | sed -e 's/[[:space:]]*$//' -e "s/^['\"]//" -e "s/['\"]$//" -e 's/\\\(.\)/\1/g' -e 's:/*$::')"
    [ -z "$typed" ] && finish 1
    APP_DIR="$(app_dir_in "$typed")" || { echo "That folder doesn't contain install.sh and main.swift. Try again."; echo ""; }
done
echo "$APP_DIR" > "$CONFIG"
echo "📁 $APP_DIR"
echo ""

# The Swift compiler comes with Apple's Command Line Tools.
if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "❌ The Swift compiler isn't installed."
    echo "   A window will open to install Apple's Command Line Tools. When that's finished,"
    echo "   double-click this file again."
    xcode-select --install 2>/dev/null
    finish 1
fi

# --- Homebrew and GitHub's "gh" tool, and signing in to GitHub ------------
# With gh signed in (through the browser, so a Google-linked GitHub
# account works), git can get the latest version by itself — here and in
# ScaffoldPro's own "Update Now" — without GitHub Desktop.

# Homebrew lives in /opt/homebrew (Apple silicon) or /usr/local (Intel).
use_brew() {
    local b
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$b" ]; then eval "$("$b" shellenv)"; return 0; fi
    done
    command -v brew >/dev/null 2>&1
}

if ! use_brew; then
    echo "🍺 Installing Homebrew (the Mac's standard installer for tools like gh)..."
    echo "   It asks for your Mac password (nothing shows while you type it) and to press Return."
    echo ""
    if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" && use_brew; then
        # So Terminal finds brew (and gh) from now on, too.
        BREW_PATH="$(command -v brew)"
        if [ -n "$BREW_PATH" ] && ! grep -qs "brew shellenv" "$HOME/.zprofile"; then
            printf '\neval "$(%s shellenv)"\n' "$BREW_PATH" >> "$HOME/.zprofile"
        fi
        echo "✅ Homebrew installed."
    else
        echo "⚠️  Homebrew couldn't be installed. Carrying on without it."
    fi
    echo ""
fi

if ! command -v gh >/dev/null 2>&1 && command -v brew >/dev/null 2>&1; then
    echo "🐙 Installing gh (GitHub's command-line tool)..."
    if brew install gh; then
        echo "✅ gh installed."
    else
        echo "⚠️  gh couldn't be installed. Carrying on without it."
    fi
    echo ""
fi

if command -v gh >/dev/null 2>&1; then
    if ! gh auth status --hostname github.com >/dev/null 2>&1; then
        echo "🔑 Sign in to GitHub"
        echo "   gh shows a one-time code. Press Return to open github.com in your browser,"
        echo "   sign in there (Continue with Google works), enter the code and authorise."
        echo ""
        if gh auth login --hostname github.com --git-protocol https --web --skip-ssh-key; then
            echo "✅ Signed in to GitHub."
        else
            echo "⚠️  Not signed in. You can double-click this file again to try once more."
        fi
        echo ""
    fi
    # git (here and in ScaffoldPro's Update Now) uses gh's sign-in.
    gh auth status --hostname github.com >/dev/null 2>&1 && gh auth setup-git --hostname github.com >/dev/null 2>&1
fi

# Latest version, if this is a git copy. Terminal pulls it by itself (signed
# in through gh, above); if it still can't, GitHub Desktop is opened on the
# folder to pull it there.
REPO_DIR="$(git -C "$APP_DIR" rev-parse --show-toplevel 2>/dev/null)"

# How many changes GitHub has that this copy hasn't pulled yet (as far as
# the last fetch knows).
behind_count() { git -C "$REPO_DIR" rev-list --count "HEAD..@{u}" 2>/dev/null || echo 0; }

pull_with_github_desktop() {
    open -a "GitHub Desktop" "$REPO_DIR" 2>/dev/null || return 1
    echo "GitHub Desktop is now open on Scaffold-Pro. In it:"
    echo "  1. Press “Fetch origin” (in the bar along the top)."
    echo "  2. If the button then says “Pull origin”, press it."
    echo "Then come back to this window."
    echo ""
    while true; do
        read -r -p "Press Return when that's done (or type S then Return to skip): " answer
        case "$answer" in [sS]*) echo ""; return 0 ;; esac
        local n
        n="$(behind_count)"
        if [ "${n:-0}" -gt 0 ]; then
            echo "There's still a newer version waiting ($n change(s)): press “Pull origin” in GitHub Desktop."
        else
            echo "✅ Up to date."
            echo ""
            return 0
        fi
    done
}

if [ -n "$REPO_DIR" ]; then
    echo "⬇️  Getting the latest version..."
    if GIT_TERMINAL_PROMPT=0 git -C "$REPO_DIR" -c credential.interactive=never pull --ff-only --quiet 2>/dev/null; then
        echo "✅ Up to date."
        echo ""
    elif open -Ra "GitHub Desktop" 2>/dev/null; then
        echo "Terminal couldn't get it from GitHub by itself, so let's use GitHub Desktop."
        echo ""
        pull_with_github_desktop
    else
        echo "⚠️  Couldn't update (no internet, or files changed on this Mac). Installing the version you have."
        echo ""
    fi

    # A copy of this file kept elsewhere (e.g. on the Desktop) updates
    # itself from the one in Scaffold-Pro. Moved into place, not written
    # over, so this run carries on unaffected; the new one runs next time.
    REPO_COPY="$REPO_DIR/Install ScaffoldPro.command"
    SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    if [ -f "$REPO_COPY" ] && [ "$SELF" != "$REPO_COPY" ] && ! cmp -s "$REPO_COPY" "$SELF"; then
        if cp "$REPO_COPY" "$SELF.new.$$" && chmod +x "$SELF.new.$$" && mv -f "$SELF.new.$$" "$SELF"; then
            echo "🔄 This installer file was updated too (the new one runs next time)."
            echo ""
        else
            rm -f "$SELF.new.$$"
        fi
    fi
fi

cd "$APP_DIR" || finish 1
if bash ./install.sh; then
    finish 0
else
    echo ""
    echo "❌ The install didn't finish. The messages above say what went wrong."
    finish 1
fi
