#!/bin/sh

# Filemanagers information script for KUAL

alert() {
    TITLE="$1"
    TEXT="$2"

    TITLE_ESC=$(printf '%s' "$TITLE" | sed 's/"/\\"/g')
    TEXT_ESC=$(printf '%s' "$TEXT" | sed 's/"/\\"/g')

    JSON='{ "clientParams":{ "alertId":"appAlert1", "show":true, "customStrings":[ { "matchStr":"alertTitle", "replaceStr":"'"$TITLE_ESC"'" }, { "matchStr":"alertText", "replaceStr":"'"$TEXT_ESC"'" } ] } }'

    lipc-set-prop com.lab126.pillow pillowAlert "$JSON" 2>/dev/null || true
}

alert "File managers" "Use Filebrowser to browse, upload, download files on your Kindle through a simple web interface. Useful to transfer books or documents from any device on the same wifi network. Use Syncthing to continuouly synchronize folders between your device and other computers running Syncthing. Files are kept up to date automatically in the background, with no cloud server between."
