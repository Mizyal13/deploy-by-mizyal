#!/bin/bash

set -Eeuo pipefail

VERSION="2.0"

G='\033[0;32m'
BG='\033[1;32m'
DG='\033[2;32m'
LG='\033[92m'
Y='\033[1;33m'
R='\033[0;31m'
C='\033[0;36m'
NC='\033[0m'

print_logo() {
    echo -e "${BG}"
    echo "(           (    (        )      )             )     *     (        )      )          (     "
    echo " )\ )        )\ ) )\ )  ( /(   ( /(     (    ( /(   (  \`    )\ )  ( /(   ( /(   (      )\ )  "
    echo "(()/(   (   (()/((()/(  )\()\\  )\()\\  ( )\   )\()\\  )\))(  (()/(  \()\\  )\()\\  )\    (()/(  "
    echo " /(_))  )\   /(_))/(_))((_)\  ((_)\   )((_) ((_)\  ((_)()\\  /(_))((_)\  ((_)\((((_)(   /(_)) "
    echo "(_))_  ((_) (_)) (_))    ((_)__ ((_) ((_)_ __ ((_) (_()((_)(_))   _((_)__ ((_))\\ _ )\ (_))   "
    echo " |   \\ | __|| _ \\| |    / _ \\\\ \\/ /  | _ )\\ \\/ / |  \\/  ||_ _| |_  / \\ \\/ /(_)_\\(_)| |    "
    echo " | |) || _| |  _/| |__ | (_) |\\ V /   | _ \\ \\/ /  | |\\/| | | |   / /   \\ \\/ /  / _ \\  | |__  "
    echo " |___/ |___||_|  |____| \\___/  |_|    |___/  |_|   |_|  |_||___| /___|   |_|  /_/ \\_\\ |____|"
    echo -e "${NC}"
}

print_line() { echo -e "${DG}─────────────────────────────────────────${NC}"; }

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

clear
print_logo
print_line
echo -e "  ${C}REMOVE PROJECT  v$VERSION${NC}"
print_line
echo ""

while true; do
    read -p "  Project Name: " PROJECT </dev/tty
    [ -n "$PROJECT" ] && break
    echo -e "  ${R}Cannot be empty${NC}"
done

WEB="/var/www/$PROJECT"
CONF="/etc/apache2/sites-available/$PROJECT.conf"

if [ ! -d "$WEB" ] && [ ! -f "$CONF" ]; then
    error_exit "Project '$PROJECT' not found"
fi

echo ""
echo -e "  ${Y}This will remove:${NC}"
echo -e "  Project : $PROJECT"
echo -e "  Files   : $WEB"
echo -e "  Config  : $CONF"
echo ""
read -p "  Continue? [y/n]: " CONFIRM </dev/tty

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo -e "  ${DG}Cancelled${NC}"
    exit 0
fi

echo ""
print_line
echo -e "  ${C}[1/3] Removing Apache config${NC}"
print_line
a2dissite "$PROJECT.conf" || true
rm -f "$CONF"
systemctl reload apache2 || true

echo ""
print_line
echo -e "  ${C}[2/3] Removing project files${NC}"
print_line
if [ -d "$WEB" ]; then
    rm -rf "$WEB"
    echo -e "  ${BG}→${NC} Removed: $WEB"
else
    echo -e "  ${Y}→ Not found: $WEB${NC}"
fi

echo ""
print_line
echo -e "  ${C}[3/3] Database cleanup${NC}"
print_line
read -p "  Remove database? [y/n]: " REMOVE_DB </dev/tty

if [ "$REMOVE_DB" = "y" ] || [ "$REMOVE_DB" = "Y" ]; then
    while true; do
        read -p "  Database Name: " DB_NAME </dev/tty
        [ -n "$DB_NAME" ] && break
        echo -e "  ${R}Cannot be empty${NC}"
    done
    while true; do
        read -p "  Database User: " DB_USER </dev/tty
        [ -n "$DB_USER" ] && break
        echo -e "  ${R}Cannot be empty${NC}"
    done

    mysql -u root <<SQL
DROP DATABASE IF EXISTS \`$DB_NAME\`;
DROP USER IF EXISTS '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
SQL

    echo -e "  ${BG}→${NC} Database '$DB_NAME' and user '$DB_USER' removed"
else
    echo -e "  ${DG}→ Skipped${NC}"
fi

echo ""
echo -e "  ${BG}╔═════════════════════════════════════╗${NC}"
echo -e "  ${BG}║  ✓ PROJECT REMOVED                 ║${NC}"
echo -e "  ${BG}║  Project: $PROJECT${NC}"
echo -e "  ${BG}╚═════════════════════════════════════╝${NC}"
echo ""
