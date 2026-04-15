#!/bin/sh

# Syncthing management script for KUAL
# Uses binaries and config files from /mnt/us/filemanagers/

FM_PATH="/mnt/us/filemanagers"
BIN_PATH="$FM_PATH/bin/syncthing"
DATA_PATH="$FM_PATH/settings"
LOG_PATH="$DATA_PATH/syncthing.log"
PID_FILE="/tmp/syncthing_kual.pid"

GUI_PORT=8384
SYNC_PORT=22000
DISCOVERY_PORT=21027

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

init_data() {
    if [ ! -d "$DATA_PATH" ]; then
        echo "Creating data directory: $DATA_PATH"
        mkdir -p "$DATA_PATH"
    fi
}

enable_remote_gui() {
    CONFIG_XML="$DATA_PATH/config.xml"
    if [ -f "$CONFIG_XML" ]; then
        echo "Updating config.xml to listen on 0.0.0.0:$GUI_PORT..."
        sed -i 's|<address>[^<]*:'"$GUI_PORT"'</address>|<address>0.0.0.0:'"$GUI_PORT"'</address>|' "$CONFIG_XML"
    else
        echo "Warning: config.xml not found yet. Syncthing may need to run once to generate it."
    fi
}

start_daemon() {
    if [ ! -f "$BIN_PATH" ]; then
        alert "Syncthing" "Error: Binary not found at $BIN_PATH"
        exit 1
    fi

    chmod +x "$BIN_PATH"

    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            alert "Syncthing" "Syncthing is already running (PID: $PID)"
            return 0
        else
            rm "$PID_FILE"
        fi
    fi

    init_data

    echo "Opening sync ports ($SYNC_PORT, $DISCOVERY_PORT)..."
    iptables -A INPUT -p tcp --dport $SYNC_PORT -j ACCEPT 2>/dev/null
    iptables -A INPUT -p udp --dport $SYNC_PORT -j ACCEPT 2>/dev/null
    iptables -A INPUT -p udp --dport $DISCOVERY_PORT -j ACCEPT 2>/dev/null

    echo "Starting Syncthing..."
    start-stop-daemon --make-pidfile --pidfile "$PID_FILE" -S --oknodo --background \
        --exec "$BIN_PATH" -- --no-browser --home="$DATA_PATH" \
        --logfile="$LOG_PATH" --log-max-size=1000 --log-max-old-files=1

    sleep 2
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        alert "Syncthing" "Syncthing started successfully."
        return 0
    else
        alert "Syncthing" "Failed to start Syncthing. Check log at $LOG_PATH"
        return 1
    fi
}

open_config_firewall() {
    echo "Opening port $GUI_PORT for configuration..."
    iptables -A INPUT -p tcp --dport $GUI_PORT -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT 2>/dev/null
    iptables -A OUTPUT -p tcp --sport $GUI_PORT -m conntrack --ctstate ESTABLISHED -j ACCEPT 2>/dev/null
}

close_firewall() {
    echo "Closing all Syncthing ports..."
    iptables -D INPUT -p tcp --dport $GUI_PORT -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT 2>/dev/null
    iptables -D OUTPUT -p tcp --sport $GUI_PORT -m conntrack --ctstate ESTABLISHED -j ACCEPT 2>/dev/null
    iptables -D INPUT -p tcp --dport $SYNC_PORT -j ACCEPT 2>/dev/null
    iptables -D INPUT -p udp --dport $SYNC_PORT -j ACCEPT 2>/dev/null
    iptables -D INPUT -p udp --dport $DISCOVERY_PORT -j ACCEPT 2>/dev/null
}

stop() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        echo "Stopping Syncthing (PID: $PID)..."
        start-stop-daemon --pidfile "$PID_FILE" --exec "$BIN_PATH" --oknodo -K
        rm "$PID_FILE"

        close_firewall
        alert "Syncthing" "Syncthing stopped."
    else
        alert "Syncthing" "Syncthing is not running."
    fi
}

status() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            if iptables -L INPUT -n | grep -q "dpt:$GUI_PORT"; then
                alert "Syncthing" "Syncthing is running in config mode. Web UI: http://$(get_ip):$GUI_PORT"
            else
                alert "Syncthing" "Syncthing is running (PID: $PID)."
            fi
        else
            alert "Syncthing" "Syncthing is not running (stale PID file found)."
        fi
    else
        alert "Syncthing" "Syncthing is not running."
    fi
}

case "$1" in
    start)
        start_daemon
        ;;
    config)
        if [ ! -f "$DATA_PATH/config.xml" ]; then
            echo "Generating initial configuration..."
            init_data
            "$BIN_PATH" generate --home="$DATA_PATH" > /dev/null 2>&1
        fi
        enable_remote_gui
        if start_daemon; then
            open_config_firewall
            alert "Syncthing" "Configuration Web UI: http://$(get_ip):$GUI_PORT"
        fi
        ;;
    stop)    stop ;;
    status)  status ;;
    restart) stop; sleep 1; start_daemon ;;
    *)
        echo "Usage: $0 {start|config|stop|status|restart}"
        exit 1
        ;;
esac
