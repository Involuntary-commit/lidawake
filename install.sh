#!/bin/bash
# Install or remove the lidawake helper.
#   sudo bash install.sh            install (or reinstall)
#   sudo bash install.sh uninstall  remove and restore normal sleep
set -e
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo: sudo bash $0 $*"; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
PLIST=/Library/LaunchDaemons/com.local.lidawake.plist
SCRIPT=/usr/local/bin/lidawake.sh

launchctl bootout system "$PLIST" 2>/dev/null || true

if [ "$1" = "uninstall" ]; then
  rm -f "$PLIST" "$SCRIPT" /var/db/lidawake.build
  pmset -a disablesleep 0
  echo "Removed. Closing the lid puts the Mac to sleep again."
  exit 0
fi

mkdir -p /usr/local/bin
install -m 755 -o root -g wheel "$HERE/lidawake.sh" "$SCRIPT"
install -m 644 -o root -g wheel "$HERE/com.local.lidawake.plist" "$PLIST"
echo "Self-check:"
bash "$SCRIPT" selftest
launchctl bootstrap system "$PLIST"
sleep 3
echo "Installed. Recent log:"
tail -n 5 /var/log/lidawake.log
