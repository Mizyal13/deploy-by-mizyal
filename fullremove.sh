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
echo -e "  ${C}FULL RESET  v$VERSION${NC}"
print_line
echo ""
echo -e "  ${Y}WARNING: This will remove EVERYTHING:${NC}"
echo -e "    - All websites in /var/www/"
echo -e "    - Apache2 and all configs"
echo -e "    - PHP and all extensions"
echo -e "    - MySQL and ALL databases"
echo -e "    - Composer, Certbot, UFW, fail2ban"
echo ""
echo -e "  ${BG}OpenSSH will be KEPT.${NC}"
echo ""
print_line

read -p "  Type 'RESET' to confirm: " CONFIRM </dev/tty

if [ "$CONFIRM" != "RESET" ]; then
    echo -e "  ${DG}Cancelled${NC}"
    exit 0
fi

echo ""
print_line
echo -e "  ${C}[1/6] Stopping services${NC}"
print_line
systemctl stop apache2 || true
systemctl stop mysql || true
systemctl stop php*-fpm || true
systemctl stop fail2ban || true

echo ""
print_line
echo -e "  ${C}[2/6] Disabling services${NC}"
print_line
systemctl disable apache2 || true
systemctl disable mysql || true
systemctl disable php*-fpm || true
systemctl disable fail2ban || true

echo ""
print_line
echo -e "  ${C}[3/6] Removing packages${NC}"
print_line
apt purge -y apache2 apache2-bin apache2-data apache2-utils ssl-cert || true
apt purge -y 'php*' || true
apt purge -y mysql-server mysql-client mysql-client-core mysql-server-core mysql-common || true
apt purge -y certbot python3-certbot-apache || true
apt purge -y fail2ban || true
apt autoremove -y || true
apt autoclean -y || true

echo ""
print_line
echo -e "  ${C}[4/6] Removing project files${NC}"
print_line
if [ -d "/var/www" ]; then
    rm -rf /var/www/*
    echo -e "  ${BG}→${NC} All project files removed"
else
    echo -e "  ${Y}→ /var/www not found${NC}"
fi

echo ""
print_line
echo -e "  ${C}[5/6] Removing databases${NC}"
print_line
if systemctl is-active --quiet mysql; then
    for DB in $(mysql -u root -N -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('mysql','information_schema','performance_schema','sys');"); do
        mysql -u root -e "DROP DATABASE \`$DB\`;"
        echo -e "  ${BG}→${NC} Dropped: $DB"
    done
    for USER in $(mysql -u root -N -e "SELECT user FROM mysql.user WHERE user NOT IN ('root','mysql.sys','mysql.session','mysql.infoschema');"); do
        mysql -u root -e "DROP USER IF EXISTS '$USER'@'localhost';"
        echo -e "  ${BG}→${NC} Dropped user: $USER"
    done
    mysql -u root -e "FLUSH PRIVILEGES;"
else
    echo -e "  ${Y}→ MySQL not running, skipping${NC}"
fi

echo ""
print_line
echo -e "  ${C}[6/6] Resetting firewall${NC}"
print_line
ufw --force reset || true
ufw allow OpenSSH || true
ufw --force enable || true
echo -e "  ${BG}→${NC} Only OpenSSH is allowed"

rm -f /usr/local/bin/composer || true
crontab -r || true

IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "  ${BG}╔═════════════════════════════════════╗${NC}"
echo -e "  ${BG}║  ✓ SERVER RESET SUCCESS            ║${NC}"
echo -e "  ${BG}╠═════════════════════════════════════╣${NC}"
echo -e "  ${BG}║${NC}  Server is now fresh."
echo -e "  ${BG}║${NC}  SSH is still active:"
echo -e "  ${BG}║${NC}"
echo -e "  ${BG}║${NC}    ${C}ssh root@$IP${NC}"
echo -e "  ${BG}║${NC}"
echo -e "  ${BG}╚═════════════════════════════════════╝${NC}"
echo ""
