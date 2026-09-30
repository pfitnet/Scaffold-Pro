#!/bin/bash
# The steps of Install ScaffoldPro, run by its window (InstallerUI.swift).
#
#   install-steps.sh <ScaffoldPro-native folder> [<Install ScaffoldPro.app to keep up to date>]
#
# Lines starting "@@" tell the window what's happening; everything else is
# shown under "Show Details":
#   @@STEP <n> <wait|run|done|skip|fail> <text>    one of the six steps
#   @@PROGRESS <0-100>                             the progress bar
#   @@CREEP <0-100>                                move slowly towards this (while compiling)
#   @@STATUS <text>                                the line under the bar
#   @@CODE <XXXX-XXXX> / @@CODEDONE                GitHub's one-time sign-in code
#   @@FINISHED <ok|fail> <text>                    the end
#
# Steps: 1 Homebrew · 2 gh · 3 sign in to GitHub · 4 latest version ·
# 5 build · 6 install and open. Steps 1–4 never stop the install: if one
# can't be done, the version already on this Mac is installed.

APP_DIR="$1"
LAUNCHER_APP="$2"
HERE="$(cd "$(dirname "$0")" && pwd)"
# Opened from Finder, the PATH is short: add Homebrew's and the system's.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

step() { echo "@@STEP $1 $2 $3"; }
progress() { echo "@@PROGRESS $1"; }
status() { echo "@@STATUS $*"; }
finished() { echo "@@FINISHED $1 $2"; exit "$([ "$1" = ok ] && echo 0 || echo 1)"; }

if [ ! -f "$APP_DIR/install.sh" ]; then
    finished fail "The ScaffoldPro-native folder wasn't found ($APP_DIR)."
fi
REPO_DIR="$(git -C "$APP_DIR" rev-parse --show-toplevel 2>/dev/null)"

# ---------------------------------------------------------------- 1 Homebrew
use_brew() {
    local b
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$b" ]; then eval "$("$b" shellenv)"; return 0; fi
    done
    command -v brew >/dev/null 2>&1
}

step 1 run "Homebrew"
progress 2
if use_brew; then
    step 1 done "Homebrew is installed"
else
    status "Installing Homebrew (it asks for your Mac password)…"
    # NONINTERACTIVE: no "press Return"; SUDO_ASKPASS: the password is asked
    # for in a window (askpass.sh) rather than in Terminal.
    if NONINTERACTIVE=1 SUDO_ASKPASS="$HERE/askpass.sh" \
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/null 2>&1 \
        && use_brew; then
        BREW_PATH="$(command -v brew)"
        # So Terminal finds brew (and gh) from now on, too.
        if [ -n "$BREW_PATH" ] && ! grep -qs "brew shellenv" "$HOME/.zprofile"; then
            printf '\neval "$(%s shellenv)"\n' "$BREW_PATH" >> "$HOME/.zprofile"
        fi
        step 1 done "Homebrew installed"
    else
        step 1 fail "Homebrew couldn't be installed (see Show Details)"
    fi
fi
progress 10

# ---------------------------------------------------------------------- 2 gh
step 2 run "GitHub tool (gh)"
if command -v gh >/dev/null 2>&1; then
    step 2 done "gh is installed"
elif command -v brew >/dev/null 2>&1; then
    status "Installing gh…"
    if HOMEBREW_NO_ENV_HINTS=1 brew install gh < /dev/null 2>&1; then
        step 2 done "gh installed"
    else
        step 2 fail "gh couldn't be installed (see Show Details)"
    fi
else
    step 2 skip "gh needs Homebrew"
fi
progress 20

# --------------------------------------------------------- 3 sign in to GitHub
step 3 run "Sign in to GitHub"
if ! command -v gh >/dev/null 2>&1; then
    step 3 skip "Needs gh"
elif gh auth status --hostname github.com >/dev/null 2>&1; then
    gh auth setup-git --hostname github.com >/dev/null 2>&1
    step 3 done "Signed in to GitHub"
else
    status "Sign in to GitHub in your browser, and enter the code shown here."
    # gh prints a one-time code and opens github.com/login/device in the
    # browser (with no keyboard attached it doesn't wait for Return), then
    # waits until the code has been entered there.
    gh auth login --hostname github.com --git-protocol https --web < /dev/null 2>&1 |
        while IFS= read -r line; do
            echo "$line"
            code="$(printf '%s' "$line" | grep -oE '[A-Z0-9]{4}-[A-Z0-9]{4}' | head -1)"
            [ -n "$code" ] && echo "@@CODE $code"
        done
    echo "@@CODEDONE"
    if gh auth status --hostname github.com >/dev/null 2>&1; then
        gh auth setup-git --hostname github.com >/dev/null 2>&1
        step 3 done "Signed in to GitHub"
    else
        step 3 fail "Not signed in to GitHub"
    fi
fi
progress 30

# ------------------------------------------------------- 4 the latest version
step 4 run "Get the latest version"
if [ -z "$REPO_DIR" ]; then
    step 4 skip "This copy isn't linked to GitHub"
else
    status "Getting the latest version from GitHub…"
    if GIT_TERMINAL_PROMPT=0 git -C "$REPO_DIR" -c credential.interactive=never pull --ff-only 2>&1 < /dev/null; then
        step 4 done "Up to date"
    else
        step 4 fail "Couldn't get it — installing the version on this Mac"
    fi
    # A copy of Install ScaffoldPro kept elsewhere (e.g. on the Desktop)
    # stays up to date with the one in the folder. (Its compiled window is
    # left alone; it's rebuilt when its source changes.)
    SOURCE_APP="$REPO_DIR/Install ScaffoldPro.app"
    if [ -n "$LAUNCHER_APP" ] && [ -d "$SOURCE_APP" ] && [ -d "$LAUNCHER_APP" ] \
        && [ "$(cd "$LAUNCHER_APP" && pwd -P)" != "$(cd "$SOURCE_APP" && pwd -P)" ]; then
        # ditto merges into the copy: its compiled window (not in the folder's
        # copy) stays.
        ditto "$SOURCE_APP" "$LAUNCHER_APP" 2>/dev/null
    fi
fi
progress 40

# -------------------------------------------------- 5 build · 6 install, open
step 5 run "Build ScaffoldPro"
status "Building ScaffoldPro — this takes about a minute…"
cd "$APP_DIR" || finished fail "The ScaffoldPro-native folder couldn't be opened."
LAST_ERROR=""
bash ./install.sh 2>&1 < /dev/null |
    while IFS= read -r line; do
        echo "$line"
        case "$line" in
            *"Cleaning previous build"*) progress 42 ;;
            *"Compiling ScaffoldPro"*) progress 45; echo "@@CREEP 84" ;;
            *"Assembling bundle"*) progress 86 ;;
            *"Adding app icon"*) progress 88 ;;
            *"Validating Info.plist"*) progress 90 ;;
            *"Ad-hoc signing"*) progress 92 ;;
            *"Installing to /Applications"*)
                step 5 done "Built"; step 6 run "Install and open"; status "Installing into Applications…"; progress 95 ;;
            *"Refreshing LaunchServices"*) progress 98 ;;
        esac
    done
RESULT=${PIPESTATUS[0]}
if [ "$RESULT" -ne 0 ]; then
    step 5 fail "It couldn't be built"
    finished fail "ScaffoldPro couldn't be built or installed. Show Details has the reason."
fi
step 6 done "Installed — ScaffoldPro is opening"
progress 100
finished ok "ScaffoldPro is installed and up to date."
