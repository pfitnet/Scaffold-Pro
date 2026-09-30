#!/bin/bash
# Asks for the Mac password in a window, for Homebrew's installer (sudo -A),
# so Install ScaffoldPro never needs Terminal. Prints it for sudo; Cancel
# gives nothing, and sudo stops.
/usr/bin/osascript \
    -e 'text returned of (display dialog "Homebrew needs your Mac password to install. (It’s the password you use to log in to this Mac.)" with title "Install ScaffoldPro" default answer "" with hidden answer with icon caution buttons {"Cancel", "OK"} default button "OK")' \
    2>/dev/null
