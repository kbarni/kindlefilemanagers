#!/bin/sh
# Phase 2 placeholder: download + install the Filebrowser binary into
# /mnt/us/filemanagers/filebrowser/bin/filebrowser
# For now, just alert that this is not yet implemented.

lipc-set-prop com.lab126.pillow pillowAlert '{ "clientParams":{ "alertId":"appAlert1", "show":true, "customStrings":[ { "matchStr":"alertTitle", "replaceStr":"Install Filebrowser" }, { "matchStr":"alertText", "replaceStr":"Not yet implemented. Place the binary at /mnt/us/filemanagers/filebrowser/bin/filebrowser." } ] } }' 2>/dev/null
