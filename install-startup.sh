#!/bin/sh
#
# Install filebrowser and syncthing upstart jobs so they start on boot.
# Copies upstart scripts to /etc/upstart/ (requires remounting root rw).
#
# Called from the filemanagers WAF via Utild.

FM_PATH="/mnt/us/filemanagers"

alert() {
    TITLE="$1"; TEXT="$2"
    TITLE_ESC=$(printf '%s' "$TITLE" | sed 's/"/\\"/g')
    TEXT_ESC=$(printf '%s' "$TEXT" | sed 's/"/\\"/g')
    JSON='{ "clientParams":{ "alertId":"appAlert1", "show":true, "customStrings":[ { "matchStr":"alertTitle", "replaceStr":"'"$TITLE_ESC"'" }, { "matchStr":"alertText", "replaceStr":"'"$TEXT_ESC"'" } ] } }'
    lipc-set-prop com.lab126.pillow pillowAlert "$JSON" 2>/dev/null || true
}

mntroot rw
if [ $? -ne 0 ]; then
    alert "Install startup" "Failed to remount root filesystem as writable."
    exit 1
fi

cp "$FM_PATH/upstart/filebrowser.upstart" /etc/upstart/filebrowser.conf
cp "$FM_PATH/upstart/syncthing.upstart"   /etc/upstart/syncthing.conf

mntroot ro

alert "Install startup" "Done. Filebrowser and Syncthing will start automatically on next boot."
