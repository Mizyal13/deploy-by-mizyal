#!/bin/bash

set -Eeuo pipefail

VERSION="2.0"
SCRIPT_URL="https://raw.githubusercontent.com/mizyal13/deploy-by-mizyal/main"
INSTALL_DIR="/opt/deploy-by-mizyal"
GLOBAL_CMD="/usr/local/bin/deploybymizyal"
SCRIPTS="main.sh install.sh projectadd.sh projectremove.sh fullremove.sh diagnostics.sh"

error_exit() {
    echo ""
    echo "ERROR: $1"
    echo ""
    exit 1
}

if [ "$EUID" -ne 0 ]; then
    error_exit "Run as root"
fi

# detect if already installed locally
LOCAL_MODE=false
if [[ "$0" == "$INSTALL_DIR/main.sh" ]] || [[ "$0" == "./main.sh" && -d "$INSTALL_DIR" ]]; then
    LOCAL_MODE=true
fi

# first time? install everything
if [ "$LOCAL_MODE" = false ]; then
    clear
    echo "=========================================="
    echo "  DEPLOY BY MIZYAL v$VERSION"
    echo "  First Time Setup"
    echo "=========================================="
    echo ""
    echo "Installing to $INSTALL_DIR ..."
    mkdir -p "$INSTALL_DIR"

    for SCRIPT in $SCRIPTS; do
        curl -fsSL "$SCRIPT_URL/$SCRIPT" -o "$INSTALL_DIR/$SCRIPT" || error_exit "Download failed: $SCRIPT"
        chmod +x "$INSTALL_DIR/$SCRIPT"
        echo "  -> $SCRIPT"
    done

    cat > "$GLOBAL_CMD" << 'EOF'
#!/bin/bash
exec bash /opt/deploy-by-mizyal/main.sh "$@"
EOF
    chmod +x "$GLOBAL_CMD"

    echo ""
    echo "Done! You can now run: deploybymizyal"
    echo ""
    read -p "Press Enter to open menu..." </dev/tty
    exec bash "$INSTALL_DIR/main.sh" "$@"
fi

# main menu
clear
echo "=========================================="
echo "  DEPLOY BY MIZYAL v$VERSION"
echo "=========================================="
echo ""
echo "  1. Install Server"
echo "  2. Add Project"
echo "  3. Remove Project"
echo "  4. Server Status"
echo "  5. Diagnostics"
echo "  6. Full Reset"
echo "  7. Update Scripts"
echo ""
read -p "Choose [1-7]: " CHOICE </dev/tty

case "$CHOICE" in
    1) bash "$INSTALL_DIR/install.sh" ;;
    2) bash "$INSTALL_DIR/projectadd.sh" ;;
    3) bash "$INSTALL_DIR/projectremove.sh" ;;
    4) bash "$INSTALL_DIR/diagnostics.sh" --status ;;
    5) bash "$INSTALL_DIR/diagnostics.sh" --full ;;
    6) bash "$INSTALL_DIR/fullremove.sh" ;;
    7)
        echo ""
        echo "Updating..."
        for SCRIPT in $SCRIPTS; do
            curl -fsSL "$SCRIPT_URL/$SCRIPT" -o "$INSTALL_DIR/$SCRIPT" || error_exit "Update failed: $SCRIPT"
            chmod +x "$INSTALL_DIR/$SCRIPT"
            echo "  -> $SCRIPT"
        done
        echo "All updated!"
        read -p "Press Enter..." </dev/tty
        bash "$INSTALL_DIR/main.sh"
        ;;
    *) error_exit "Invalid choice" ;;
esac
