#!/usr/bin/env bash
# macOS LaunchAgent Management Helper
set -e

PLIST_NAME="com.local.mac-trigger-service.plist"
USER_AGENTS_DIR="$HOME/Library/LaunchAgents"
TARGET_PLIST="$USER_AGENTS_DIR/$PLIST_NAME"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UID_NUM="$(id -u)"

function show_help() {
    echo "Usage: $0 {install|uninstall|start|stop|restart|status|logs}"
    echo ""
    echo "Commands:"
    echo "  install    - Render paths, copy plist to ~/Library/LaunchAgents, and register service"
    echo "  uninstall  - Unload and remove plist from ~/Library/LaunchAgents"
    echo "  start      - Start the registered service"
    echo "  stop       - Stop the running service"
    echo "  restart    - Restart the service"
    echo "  status     - Check current launchd status"
    echo "  logs       - Tail stdout and stderr service logs"
    exit 1
}

function install_agent() {
    echo "==> Configuring LaunchAgent plist with current paths..."
    mkdir -p "$USER_AGENTS_DIR"

    PYTHON_BIN="$SCRIPT_DIR/.venv/bin/python"
    if [ ! -f "$PYTHON_BIN" ]; then
        PYTHON_BIN="$(which python3)"
    fi

    # Generate personalized plist with absolute paths
    sed -e "s|/Users/nikhilbahalkar/Documents/antigravity/CMF-DIY/.venv/bin/python|$PYTHON_BIN|g" \
        -e "s|/Users/nikhilbahalkar/Documents/antigravity/CMF-DIY|$SCRIPT_DIR|g" \
        "$SCRIPT_DIR/com.local.mac-trigger-service.plist" > "$TARGET_PLIST"

    chmod 644 "$TARGET_PLIST"
    echo "==> Installed plist to: $TARGET_PLIST"

    # Unload if already loaded
    launchctl bootout "gui/$UID_NUM/$PLIST_NAME" 2>/dev/null || true

    # Bootstrap
    echo "==> Registering with launchd (GUI user session: $UID_NUM)..."
    launchctl bootstrap "gui/$UID_NUM" "$TARGET_PLIST"
    echo "✅ Service successfully installed and loaded!"
    echo "   Verify running status with: $0 status"
}

function uninstall_agent() {
    echo "==> Unloading service from launchd..."
    launchctl bootout "gui/$UID_NUM/$PLIST_NAME" 2>/dev/null || true
    if [ -f "$TARGET_PLIST" ]; then
        rm -f "$TARGET_PLIST"
        echo "==> Removed $TARGET_PLIST"
    fi
    echo "✅ Service completely uninstalled."
}

function start_agent() {
    echo "==> Starting service..."
    launchctl kickstart -k "gui/$UID_NUM/$PLIST_NAME"
    echo "✅ Service started."
}

function stop_agent() {
    echo "==> Stopping service..."
    launchctl kill SIGTERM "gui/$UID_NUM/$PLIST_NAME" 2>/dev/null || true
    echo "✅ Service stopped."
}

function restart_agent() {
    stop_agent
    sleep 1
    start_agent
}

function status_agent() {
    echo "==> Checking launchctl status for $PLIST_NAME:"
    launchctl print "gui/$UID_NUM/$PLIST_NAME" 2>/dev/null || launchctl list | grep "mac-trigger" || echo "Service not currently loaded in gui/$UID_NUM."
}

function tail_logs() {
    echo "==> Streaming logs (Ctrl+C to quit)..."
    tail -f "$SCRIPT_DIR/trigger.log" "$SCRIPT_DIR/service.stdout.log" "$SCRIPT_DIR/service.stderr.log" 2>/dev/null
}

case "$1" in
    install)
        install_agent
        ;;
    uninstall)
        uninstall_agent
        ;;
    start)
        start_agent
        ;;
    stop)
        stop_agent
        ;;
    restart)
        restart_agent
        ;;
    status)
        status_agent
        ;;
    logs)
        tail_logs
        ;;
    *)
        show_help
        ;;
esac
