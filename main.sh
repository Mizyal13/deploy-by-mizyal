#!/bin/bash

set -Eeuo pipefail

VERSION="2.0"
SCRIPT_URL="https://raw.githubusercontent.com/mizyal13/deploy-by-mizyal/main"
INSTALL_DIR="/opt/deploy-by-mizyal"
GLOBAL_CMD="/usr/local/bin/deploybymizyal"
SCRIPTS="main.sh install.sh projectadd.sh projectremove.sh fullremove.sh diagnostics.sh"

G='\033[0;32m'
BG='\033[1;32m'
DG='\033[2;32m'
LG='\033[92m'
Y='\033[1;33m'
R='\033[0;31m'
C='\033[0;36m'
NC='\033[0m'

print_logo() {
    local COLUMNS
    COLUMNS=$(tput cols 2>/dev/null || echo 80)
    echo -e "${BG}"
    if [ "$COLUMNS" -ge 90 ]; then
        echo "(           (    (        )      )             )     *     (        )      )          (     "
        echo " )\ )        )\ ) )\ )  ( /(   ( /(     (    ( /(   (  \`    )\ )  ( /(   ( /(   (      )\ )  "
        echo "(()/(   (   (()/((()/(  )\()\\  )\()\\  ( )\   )\()\\  )\))(  (()/(  \()\\  )\()\\  )\    (()/(  "
        echo " /(_))  )\   /(_))/(_))((_)\  ((_)\   )((_) ((_)\  ((_)()\\  /(_))((_)\  ((_)\((((_)(   /(_)) "
        echo "(_))_  ((_) (_)) (_))    ((_)__ ((_) ((_)_ __ ((_) (_()((_)(_))   _((_)__ ((_))\\ _ )\ (_))   "
        echo " |   \\ | __|| _ \\| |    / _ \\\\ \\/ /  | _ )\\ \\/ / |  \\/  ||_ _| |_  / \\ \\/ /(_)_\\(_)| |    "
        echo " | |) || _| |  _/| |__ | (_) |\\ V /   | _ \\ \\/ /  | |\\/| | | |   / /   \\ \\/ /  / _ \\  | |__  "
        echo " |___/ |___||_|  |____| \\___/  |_|    |___/  |_|   |_|  |_||___| /___|   |_|  /_/ \\_\\ |____|"
    else
        echo "  ____  _     ___ _   _ __  __ "
        echo " |  _ \\| |   |_ _| \\ | |  \\/  |"
        echo " | |_) | |    | ||  \\| | |\\/| |"
        echo " |  __/| |___ | || |\\  | |  | |"
        echo " |_|   |_____|___|_| \\_|_|  |_|"
        echo ""
        echo "  __  __                 "
        echo " |  \\/  | ___ _ __  ___ "
        echo " | |\\/| |/ _ \\ '_ \\/ __|"
        echo " | |  | |  __/ | | \\__ \\\\"
        echo " |_|  |_|\\___|_| |_|___/"
    fi
    echo -e "${NC}"
}

print_line() { echo -e "${DG}─────────────────────────────────────────${NC}"; }
print_ok()   { echo -e "  ${BG}[OK]${NC}    $1"; }
print_warn() { echo -e "  ${Y}[WARN]${NC}  $1"; }
print_fail() { echo -e "  ${R}[FAIL]${NC}  $1"; }
print_info() { echo -e "  ${C}[INFO]${NC}  $1"; }

error_exit() {
    echo ""
    echo -e "  ${R}╔═════════════════════════════════════╗${NC}"
    echo -e "  ${R}║  ✗ ERROR                           ║${NC}"
    echo -e "  ${R}║  $1${NC}"
    echo -e "  ${R}╚═════════════════════════════════════╝${NC}"
    echo ""
    exit 1
}

if [ "$EUID" -ne 0 ]; then
    error_exit "Run as root"
fi

LOCAL_MODE=false
if [[ "$0" == "$INSTALL_DIR/main.sh" ]] || [[ "$0" == "./main.sh" && -d "$INSTALL_DIR" ]]; then
    LOCAL_MODE=true
fi

if [ "$LOCAL_MODE" = false ]; then
    clear
    print_logo
    print_line
    echo -e "  ${C}First Time Setup${NC}"
    echo -e "  ${DG}Installing to $INSTALL_DIR${NC}"
    print_line
    echo ""

    mkdir -p "$INSTALL_DIR"
    for SCRIPT in $SCRIPTS; do
        curl -fsSL "$SCRIPT_URL/$SCRIPT" -o "$INSTALL_DIR/$SCRIPT" || error_exit "Download failed: $SCRIPT"
        chmod +x "$INSTALL_DIR/$SCRIPT"
        echo -e "  ${BG}→${NC} $SCRIPT"
    done

    cat > "$GLOBAL_CMD" << 'EOF'
#!/bin/bash
exec bash /opt/deploy-by-mizyal/main.sh "$@"
EOF
    chmod +x "$GLOBAL_CMD"

    echo ""
    echo -e "  ${BG}Done!${NC} Run ${C}deploybymizyal${NC} anytime."
    echo ""
    read -p "  Press Enter to continue..." </dev/tty
    exec bash "$INSTALL_DIR/main.sh" "$@"
fi

while true; do
    clear
    print_logo
    print_line
    echo -e "  ${C}Universal PHP Deployment System${NC}"
    print_line
    echo ""
    echo -e "  ${BG}1${NC}. Install Server"
    echo -e "  ${BG}2${NC}. Add Project"
    echo -e "  ${BG}3${NC}. Remove Project"
    echo -e "  ${BG}4${NC}. Server Status"
    echo -e "  ${BG}5${NC}. Diagnostics"
    echo -e "  ${BG}6${NC}. Full Reset"
    echo -e "  ${BG}7${NC}. Update Scripts"
    echo ""
    echo -e "  ${R}8${NC}. Exit"
    echo ""
    print_line
    read -p "  Choose [1-8]: " CHOICE </dev/tty

    case "$CHOICE" in
        1) bash "$INSTALL_DIR/install.sh" ;;
        2) bash "$INSTALL_DIR/projectadd.sh" ;;
        3) bash "$INSTALL_DIR/projectremove.sh" ;;
        4) bash "$INSTALL_DIR/diagnostics.sh" --status ;;
        5) bash "$INSTALL_DIR/diagnostics.sh" --full ;;
        6) bash "$INSTALL_DIR/fullremove.sh" ;;
        7)
            echo ""
            echo -e "  ${C}Updating scripts...${NC}"
            for SCRIPT in $SCRIPTS; do
                curl -fsSL "$SCRIPT_URL/$SCRIPT" -o "$INSTALL_DIR/$SCRIPT" || error_exit "Update failed: $SCRIPT"
                chmod +x "$INSTALL_DIR/$SCRIPT"
                echo -e "  ${BG}→${NC} $SCRIPT"
            done
            echo ""
            echo -e "  ${BG}All updated!${NC}"
            read -p "  Press Enter..." </dev/tty
            ;;
        8)
            clear
            echo -e "\n  ${BG}Goodbye!${NC}\n"
            break
            ;;
        *)
            echo -e "  ${Y}Invalid choice. Try again.${NC}"
            read -p "  Press Enter..." </dev/tty
            ;;
    esac
done
