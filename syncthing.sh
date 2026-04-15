#!/bin/sh
#
# Syncthing management script (filemanagers WAF companion)
#
# Expects syncthing installed at /mnt/us/filemanagers/syncthing/

BASE_PATH="/mnt/us/filemanagers"
BIN_PATH="$BASE_PATH/bin/syncthing"
DATA_PATH="$BASE_PATH/settings"
LOG_PATH="$DATA_PATH/syncthing.log"
PID_FILE="/tmp/syncthing_filemanagers.pid"
MODE_FILE="/tmp/syncthing_filemanagers.mode"
STATUS_FILE="/tmp/filemanagers.status"

GUI_PORT=8384
SYNC_PORT=22000
DISCOVERY_PORT=21027

get_ip() {
    IP=$(ip addr show wlan0 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n1)
    if [ -z "$IP" ]; then
        IP=$(ifconfig 2>/dev/null | grep 'inet addr:' | grep -v '127.0.0.1' | cut -d: -f2 | awk '{print $1}' | head -n1)
    fi
    [ -z "$IP" ] && IP="unknown"
    echo "$IP"
}

alert() {
    TITLE="$1"; TEXT="$2"
    TITLE_ESC=$(printf '%s' "$TITLE" | sed 's/"/\\"/g')
    TEXT_ESC=$(printf '%s' "$TEXT" | sed 's/"/\\"/g')
    JSON='{ "clientParams":{ "alertId":"appAlert1", "show":true, "customStrings":[ { "matchStr":"alertTitle", "replaceStr":"'"$TITLE_ESC"'" }, { "matchStr":"alertText", "replaceStr":"'"$TEXT_ESC"'" } ] } }'
    lipc-set-prop com.lab126.pillow pillowAlert "$JSON" 2>/dev/null || true
}

# Rewrite the st line, preserving the fb line.
write_status() {
    NEW_ST="$1"
    TMP="${STATUS_FILE}.tmp"
    FB_LINE=""
    if [ -f "$STATUS_FILE" ]; then
        FB_LINE=$(grep '^fb|' "$STATUS_FILE" 2>/dev/null)
    fi
    {
        [ -n "$FB_LINE" ] && echo "$FB_LINE"
        echo "$NEW_ST"
    } > "$TMP"
    mv "$TMP" "$STATUS_FILE"
}

init_data() {
    [ -d "$DATA_PATH" ] || mkdir -p "$DATA_PATH"
}

enable_remote_gui() {
    CONFIG_XML="$DATA_PATH/config.xml"
    if [ -f "$CONFIG_XML" ]; then
        sed -i 's|<address>[^<]*:'"$GUI_PORT"'</address>|<address>0.0.0.0:'"$GUI_PORT"'</address>|' "$CONFIG_XML"
    fi
}

is_running() {
    [ -f "$PID_FILE" ] || return 1
    PID=$(cat "$PID_FILE")
    kill -0 "$PID" 2>/dev/null
}

start_daemon() {
    if [ ! -f "$BIN_PATH" ]; then
        alert "Syncthing" "Binary missing: $BIN_PATH"
        write_status "st|stopped"
        exit 1
    fi

    if is_running; then
        PID=$(cat "$PID_FILE")
        alert "Syncthing" "Already running (PID $PID)"
        return 0
    fi
    [ -f "$PID_FILE" ] && rm "$PID_FILE"

    init_data

    iptables -A INPUT -p tcp --dport $SYNC_PORT      -j ACCEPT 2>/dev/null
    iptables -A INPUT -p udp --dport $SYNC_PORT      -j ACCEPT 2>/dev/null
    iptables -A INPUT -p udp --dport $DISCOVERY_PORT -j ACCEPT 2>/dev/null

    start-stop-daemon --make-pidfile --pidfile "$PID_FILE" -S --oknodo --background \
        --exec "$BIN_PATH" -- --no-browser --home="$DATA_PATH" \
        --logfile="$LOG_PATH" --log-max-size=1000 --log-max-old-files=1

    sleep 2
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        return 0
    fi
    alert "Syncthing" "Failed to start. Check $LOG_PATH"
    return 1
}

open_config_firewall() {
    iptables -A INPUT  -p tcp --dport $GUI_PORT -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT 2>/dev/null
    iptables -A OUTPUT -p tcp --sport $GUI_PORT -m conntrack --ctstate ESTABLISHED     -j ACCEPT 2>/dev/null
}

close_firewall() {
    iptables -D INPUT  -p tcp --dport $GUI_PORT      -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT 2>/dev/null
    iptables -D OUTPUT -p tcp --sport $GUI_PORT      -m conntrack --ctstate ESTABLISHED     -j ACCEPT 2>/dev/null
    iptables -D INPUT  -p tcp --dport $SYNC_PORT      -j ACCEPT 2>/dev/null
    iptables -D INPUT  -p udp --dport $SYNC_PORT      -j ACCEPT 2>/dev/null
    iptables -D INPUT  -p udp --dport $DISCOVERY_PORT -j ACCEPT 2>/dev/null
}

start_plain() {
    echo "daemon" > "$MODE_FILE"
    start_daemon && {
        #alert "Syncthing" "Started (daemon only)."
        write_status "st|running|daemon|"
    }
}

start_config() {
    echo "config" > "$MODE_FILE"
    if [ ! -f "$DATA_PATH/config.xml" ]; then
        init_data
        "$BIN_PATH" generate --home="$DATA_PATH" > /dev/null 2>&1
    fi
    enable_remote_gui
    if start_daemon; then
        open_config_firewall
        URL="$(get_ip):$GUI_PORT"
        #alert "Syncthing" "Config UI: http://$URL"
        write_status "st|running|config|$URL"
    fi
}

stop() {
    if [ -f "$PID_FILE" ]; then
        start-stop-daemon --pidfile "$PID_FILE" --exec "$BIN_PATH" --oknodo -K 2>/dev/null
        rm "$PID_FILE"
        close_firewall
        #alert "Syncthing" "Stopped."
    fi
    [ -f "$MODE_FILE" ] && rm "$MODE_FILE"
    write_status "st|stopped"
}

status() {
    if is_running; then
        MODE="daemon"
        [ -f "$MODE_FILE" ] && MODE=$(cat "$MODE_FILE")
        if [ "$MODE" = "config" ]; then
            write_status "st|running|config|$(get_ip):$GUI_PORT"
        else
            write_status "st|running|daemon|"
        fi
    else
        write_status "st|stopped"
    fi
}

case "$1" in
    start)   start_plain ;;
    config)  start_config ;;
    stop)    stop ;;
    status)  status ;;
    restart) stop; sleep 1; start_plain ;;
    *) echo "Usage: $0 {start|config|stop|status|restart}"; exit 1 ;;
esac
