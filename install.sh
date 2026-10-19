#!/bin/bash
# Install ProxyRouter for macOS from https://proxyrouter.app
#
#   curl -fsSL https://raw.githubusercontent.com/kogodm/proxyrouter-macos/main/install.sh | bash
#
# Options (when running a downloaded copy): ./install.sh [--dir DIR] [--dmg FILE] [--no-open] [--force]
set -euo pipefail

DMG_URL="https://proxyrouter.app/downloads/ProxyRouter.dmg"
TEAM_ID="MLBB37VST8"
APP_NAME="ProxyRouter.app"
BUNDLE_ID="com.proxyrouter.app"

DEST_DIR="/Applications"
LOCAL_DMG=""
OPEN_AFTER=1
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)     DEST_DIR="${2:?--dir needs a path}"; shift 2 ;;
    --dmg)     LOCAL_DMG="${2:?--dmg needs a file}"; shift 2 ;;
    --no-open) OPEN_AFTER=0; shift ;;
    --force)   FORCE=1; shift ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

say() { printf '==> %s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "ProxyRouter is a macOS app."
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 13 ] || die "macOS 13 or later is required (this Mac runs $(sw_vers -productVersion))."
[ -d "$DEST_DIR" ] || die "Install folder does not exist: $DEST_DIR"

TARGET="$DEST_DIR/$APP_NAME"

if [ -e "$TARGET" ] && pgrep -x ProxyRouter >/dev/null 2>&1 && [ "$FORCE" -ne 1 ]; then
  die "ProxyRouter is running. Quit it first (or use the in-app updater), then run this again. --force skips this check."
fi

WORK="$(mktemp -d)"
MOUNT="$WORK/mnt"
mounted=0
cleanup() {
  if [ "$mounted" -eq 1 ]; then hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

if [ -n "$LOCAL_DMG" ]; then
  [ -f "$LOCAL_DMG" ] || die "No such file: $LOCAL_DMG"
  DMG="$LOCAL_DMG"
else
  DMG="$WORK/ProxyRouter.dmg"
  say "Downloading $DMG_URL"
  curl -fL --proto '=https' --tlsv1.2 --retry 3 -o "$DMG" "$DMG_URL"
fi

say "Mounting disk image"
mkdir -p "$MOUNT"
hdiutil attach "$DMG" -nobrowse -readonly -noautoopen -mountpoint "$MOUNT" -quiet
mounted=1

SRC="$MOUNT/$APP_NAME"
[ -d "$SRC" ] || die "$APP_NAME not found in the disk image."

say "Verifying signature"
codesign --verify --deep --strict "$SRC" || die "Code signature is invalid."
sig="$(codesign -dv --verbose=2 "$SRC" 2>&1)"
echo "$sig" | grep -q "^Identifier=$BUNDLE_ID\$" || die "Unexpected bundle identifier."
echo "$sig" | grep -q "^TeamIdentifier=$TEAM_ID\$" || die "Unexpected signing team. Refusing to install."
spctl -a -t exec "$SRC" 2>/dev/null || die "Gatekeeper rejected the app (not notarized)."

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SRC/Contents/Info.plist" 2>/dev/null || echo '?')"
say "Installing ProxyRouter $version to $DEST_DIR"
if [ -e "$TARGET" ]; then
  rm -rf "$TARGET" || die "Cannot replace the existing $TARGET. Try again with sudo."
fi
ditto "$SRC" "$TARGET" || die "Cannot write to $DEST_DIR. Try again with sudo, or use --dir ~/Applications."

say "Installed: $TARGET"
if [ "$OPEN_AFTER" -eq 1 ]; then
  say "Opening ProxyRouter. Approve the system extension when macOS asks."
  open "$TARGET"
fi
