#!/bin/sh

# Filebrowser management script for KUAL
# Uses binaries and config files from /mnt/us/filemanagers/

FM_PATH="/mnt/us/filemanagers"
BIN_PATH="$FM_PATH/bin/filebrowser"
DB_PATH="$FM_PATH/filebrowser.db"
CONFIG_PATH="$FM_PATH/config.json"
LOG_PATH="$FM_PATH/filebrowser.log"
PID_FILE="/tmp/filebrowser_kual.pid"

PORT=80
DATA_PATH="/mnt/us"

get_ip() {
    IP=$(ip addr show wlan0 | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n1)
    if [ -z "$IP" ]; then
        IP=$(ifconfig | grep 'inet addr:' | grep -v '127.0.0.1' | cut -d: -f2 | awk '{print $1}' | head -n1)
    fi
    [ -z "$IP" ] && IP="unknown"
    echo "$IP"
}

alert() {
    TITLE="$1"
    TEXT="$2"

    TITLE_ESC=$(printf '%s' "$TITLE" | sed 's/"/\\"/g')
    TEXT_ESC=$(printf '%s' "$TEXT" | sed 's/"/\\"/g')

    JSON='{ "clientParams":{ "alertId":"appAlert1", "show":true, "customStrings":[ { "matchStr":"alertTitle", "replaceStr":"'"$TITLE_ESC"'" }, { "matchStr":"alertText", "replaceStr":"'"$TEXT_ESC"'" } ] } }'

    lipc-set-prop com.lab126.pillow pillowAlert "$JSON" 2>/dev/null || true
}

init_config() {
    if [ ! -f "$DB_PATH" ]; then
        echo "Initializing Filebrowser configuration..."
        "$BIN_PATH" -d "$DB_PATH" -c "$CONFIG_PATH" config init > /dev/null 2>&1
        "$BIN_PATH" -d "$DB_PATH" -c "$CONFIG_PATH" users add admin admin12345678 --perm.admin > /dev/null 2>&1
        echo "Default credentials created: admin / admin12345678"
    fi
}

start() {
    if [ ! -f "$BIN_PATH" ]; then
        alert "Filebrowser" "Error: Binary not found at $BIN_PATH"
        exit 1
    fi

    chmod +x "$BIN_PATH"

    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            alert "Filebrowser" "Filebrowser is already running (PID: $PID)"
            return
        else
            rm "$PID_FILE"
        fi
    fi

    init_config

    iptables -A INPUT -p tcp --dport $PORT -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT 2>/dev/null
    iptables -A OUTPUT -p tcp --sport $PORT -m conntrack --ctstate ESTABLISHED -j ACCEPT 2>/dev/null

    echo "Starting Filebrowser on port $PORT..."
    nohup "$BIN_PATH" -a 0.0.0.0 -r "$DATA_PATH" -p "$PORT" -l "$LOG_PATH" -d "$DB_PATH" -c "$CONFIG_PATH" > /dev/null 2>&1 &

    PID=$!
    echo $PID > "$PID_FILE"

    sleep 2
    if kill -0 $PID 2>/dev/null; then
        alert "Filebrowser" "Filebrowser started. URL: http://$(get_ip):$PORT"
    else
        alert "Filebrowser" "Failed to start Filebrowser. Check log at $LOG_PATH"
        [ -f "$PID_FILE" ] && rm "$PID_FILE"
    fi
}

stop() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        echo "Stopping Filebrowser (PID: $PID)..."
        kill "$PID" 2>/dev/null
        rm "$PID_FILE"

        iptables -D INPUT -p tcp --dport $PORT -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT 2>/dev/null
        iptables -D OUTPUT -p tcp --sport $PORT -m conntrack --ctstate ESTABLISHED -j ACCEPT 2>/dev/null

        alert "Filebrowser" "Filebrowser stopped."
    else
        alert "Filebrowser" "Filebrowser is not running."
    fi
}

status() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            alert "Filebrowser" "Filebrowser is running (PID: $PID). URL: http://$(get_ip):$PORT"
        else
            alert "Filebrowser" "Filebrowser is not running (stale PID file found)."
        fi
    else
        alert "Filebrowser" "Filebrowser is not running."
    fi
}

case "$1" in
    start)   start ;;
    stop)    stop ;;
    status)  status ;;
    restart) stop; sleep 1; start ;;
    *)
        echo "Usage: $0 {start|stop|status|restart}"
        exit 1
        ;;
esac
