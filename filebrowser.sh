#!/bin/sh
#
# Filebrowser management script (filemanagers WAF companion)
#
# Expects filebrowser installed at /mnt/us/filemanagers/filebrowser/
#   /mnt/us/filemanagers/filebrowser/bin/filebrowser  (the binary)

BASE_PATH="/mnt/us/filemanagers"
BIN_PATH="$BASE_PATH/bin/filebrowser"
DB_PATH="$BASE_PATH/filebrowser.db"
CONFIG_PATH="$BASE_PATH/config.json"
LOG_PATH="$BASE_PATH/filebrowser.log"
PID_FILE="/tmp/filebrowser_filemanagers.pid"
STATUS_FILE="/tmp/filemanagers.status"

PORT=80
DATA_PATH="/mnt/us"

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

# Rewrite the fb line in the shared status file, preserving the st line.
write_status() {
    NEW_FB="$1"   # e.g. "fb|running|1.2.3.4:80" or "fb|stopped"
    TMP="${STATUS_FILE}.tmp"
    ST_LINE=""
    if [ -f "$STATUS_FILE" ]; then
        ST_LINE=$(grep '^st|' "$STATUS_FILE" 2>/dev/null)
    fi
    {
        echo "$NEW_FB"
        [ -n "$ST_LINE" ] && echo "$ST_LINE"
    } > "$TMP"
    mv "$TMP" "$STATUS_FILE"
}

init_config() {
    if [ ! -f "$DB_PATH" ]; then
        "$BIN_PATH" -d "$DB_PATH" -c "$CONFIG_PATH" config init > /dev/null 2>&1
        "$BIN_PATH" -d "$DB_PATH" -c "$CONFIG_PATH" users add admin admin12345678 --perm.admin > /dev/null 2>&1
    fi
}

is_running() {
    [ -f "$PID_FILE" ] || return 1
    PID=$(cat "$PID_FILE")
    kill -0 "$PID" 2>/dev/null
}

start() {
    if [ ! -f "$BIN_PATH" ]; then
        alert "Filebrowser" "Binary missing: $BIN_PATH"
        write_status "fb|stopped"
        exit 1
    fi
    chmod +x "$BIN_PATH"

    if is_running; then
        PID=$(cat "$PID_FILE")
        #alert "Filebrowser" "Already running (PID $PID)"
        write_status "fb|running|$(get_ip):$PORT"
        return
    fi
    [ -f "$PID_FILE" ] && rm "$PID_FILE"

    init_config

    iptables -A INPUT  -p tcp --dport $PORT -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT 2>/dev/null
    iptables -A OUTPUT -p tcp --sport $PORT -m conntrack --ctstate ESTABLISHED     -j ACCEPT 2>/dev/null

    cd "$BASE_PATH" || exit 1
    nohup "$BIN_PATH" -a 0.0.0.0 -r "$DATA_PATH" -p "$PORT" \
        -l "$LOG_PATH" -d "$DB_PATH" -c "$CONFIG_PATH" > /dev/null 2>&1 &
    PID=$!
    echo $PID > "$PID_FILE"

    sleep 2
    if kill -0 $PID 2>/dev/null; then
        URL="$(get_ip):$PORT"
        #alert "Filebrowser" "Started. URL: http://$URL"
        write_status "fb|running|$URL"
    else
        alert "Filebrowser" "Failed to start. Check $LOG_PATH"
        [ -f "$PID_FILE" ] && rm "$PID_FILE"
        write_status "fb|stopped"
    fi
}

stop() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        kill "$PID" 2>/dev/null
        rm "$PID_FILE"
        iptables -D INPUT  -p tcp --dport $PORT -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT 2>/dev/null
        iptables -D OUTPUT -p tcp --sport $PORT -m conntrack --ctstate ESTABLISHED     -j ACCEPT 2>/dev/null
        #alert "Filebrowser" "Stopped."
    fi
    write_status "fb|stopped"
}

status() {
    if is_running; then
        write_status "fb|running|$(get_ip):$PORT"
    else
        write_status "fb|stopped"
    fi
}

case "$1" in
    start)   start ;;
    stop)    stop ;;
    status)  status ;;
    restart) stop; sleep 1; start ;;
    *) echo "Usage: $0 {start|stop|status|restart}"; exit 1 ;;
esac
