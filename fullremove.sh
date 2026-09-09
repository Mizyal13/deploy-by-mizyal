#!/bin/bash

set -Eeuo pipefail

VERSION="3.0"

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
echo -e "  ${C}FULL RESET  v$VERSION${NC}"
print_line
echo ""
echo -e "  ${Y}WARNING: This will remove EVERYTHING:${NC}"
echo -e "    - All websites in /var/www/"
echo -e "    - Apache2, PHP, MySQL + ALL databases & users"
echo -e "    - phpMyAdmin, fail2ban, certbot"
echo -e "    - Cloudflare Tunnel (cloudflared, service, cert, config)"
echo -e "    - All backup files in /root/ (credentials, backups DB)"
echo -e "    - UFW (reset, hanya OpenSSH yang diizinkan)"
echo ""
echo -e "  ${BG}Yang DI-PERTAHANKAN: OpenSSH + deploy-by-mizyal (menu ini).${NC}"
echo ""
print_line

read -p "  Type 'RESET' to confirm: " CONFIRM </dev/tty

if [ "$CONFIRM" != "RESET" ]; then
    echo -e "  ${DG}Cancelled${NC}"
    exit 0
fi

echo ""
print_line
echo -e "  ${C}[1/6] Stop & disable semua service${NC}"
print_line
systemctl stop apache2 2>/dev/null || true
systemctl stop mysql 2>/dev/null || true
systemctl stop php*-fpm 2>/dev/null || true
systemctl stop fail2ban 2>/dev/null || true
systemctl stop cloudflared 2>/dev/null || true
systemctl disable apache2 2>/dev/null || true
systemctl disable mysql 2>/dev/null || true
systemctl disable php*-fpm 2>/dev/null || true
systemctl disable fail2ban 2>/dev/null || true
systemctl disable cloudflared 2>/dev/null || true
echo -e "  ${BG}→${NC} Service dihentikan & di-disable"

echo ""
print_line
echo -e "  ${C}[2/6] Hapus Cloudflare Tunnel & cloudflared${NC}"
print_line
if command -v cloudflared >/dev/null 2>&1; then
    cloudflared service uninstall >/dev/null 2>&1 || true
    if [ -f "$HOME/.cloudflared/cert.pem" ]; then
        cloudflared tunnel cleanup solides >/dev/null 2>&1 || true
        cloudflared tunnel delete -f solides >/dev/null 2>&1 || true
    fi
    apt purge -y cloudflared >/dev/null 2>&1 || true
    echo -e "  ${BG}→${NC} cloudflared & tunnel solides dihapus"
else
    echo -e "  ${Y}→ cloudflared tidak terpasang${NC}"
fi
rm -rf /etc/cloudflared "$HOME/.cloudflared"
rm -f /etc/systemd/system/cloudflared.service /lib/systemd/system/cloudflared.service
systemctl daemon-reload 2>/dev/null || true

echo ""
print_line
echo -e "  ${C}[3/6] Purge semua paket aplikasi${NC}"
print_line
apt purge -y apache2 apache2-bin apache2-data apache2-utils apache2-config ssl-cert >/dev/null 2>&1 || true
apt purge -y 'php*' >/dev/null 2>&1 || true
apt purge -y mysql-server mysql-client mysql-client-core mysql-server-core mysql-server-core-8.0 mysql-common >/dev/null 2>&1 || true
apt purge -y phpmyadmin >/dev/null 2>&1 || true
apt purge -y fail2ban >/dev/null 2>&1 || true
apt purge -y certbot python3-certbot-apache >/dev/null 2>&1 || true
rm -f /usr/local/bin/composer || true
apt autoremove -y >/dev/null 2>&1 || true
apt autoclean -y >/dev/null 2>&1 || true
echo -e "  ${BG}→${NC} Paket aplikasi di-purge"

echo ""
print_line
echo -e "  ${C}[4/6] Hapus semua file & konfigurasi sisa${NC}"
print_line
rm -rf /var/www
mkdir -p /var/www
rm -rf /etc/apache2 /etc/phpmyadmin /etc/fail2ban /var/lib/mysql /var/log/mysql
rm -rf /root/solides-credentials.txt /root/solides-env.backup /root/backups
echo -e "  ${BG}→${NC} /var/www, config apache/phpmyadmin/fail2ban, data MySQL, backup /root dihapus"

echo ""
print_line
echo -e "  ${C}[5/6] Hapus database & user tersisa${NC}"
print_line
if command -v mysql >/dev/null 2>&1 && systemctl is-active --quiet mysql 2>/dev/null; then
    for DB in $(mysql -u root -N -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('mysql','information_schema','performance_schema','sys');" 2>/dev/null || true); do
        mysql -u root -e "DROP DATABASE \`$DB\`;"
        echo -e "  ${BG}→${NC} Dropped: $DB"
    done
    for USER in $(mysql -u root -N -e "SELECT user FROM mysql.user WHERE user NOT IN ('root','mysql.sys','mysql.session','mysql.infoschema');" 2>/dev/null || true); do
        mysql -u root -e "DROP USER IF EXISTS '$USER'@'localhost';"
        echo -e "  ${BG}→${NC} Dropped user: $USER"
    done
    mysql -u root -e "FLUSH PRIVILEGES;"
else
    echo -e "  ${Y}→ MySQL tidak tersedia, data sudah bersih dari langkah 4${NC}"
fi

echo ""
print_line
echo -e "  ${C}[6/6] Reset firewall + bersihkan config git${NC}"
print_line
ufw --force reset >/dev/null 2>&1 || true
ufw allow OpenSSH >/dev/null 2>&1 || true
ufw --force enable >/dev/null 2>&1 || true
git config --global --unset-all safe.directory >/dev/null 2>&1 || true
crontab -r 2>/dev/null || true
echo -e "  ${BG}→${NC} Hanya OpenSSH yang diizinkan"

IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "  ${BG}╔═════════════════════════════════════╗${NC}"
echo -e "  ${BG}║  ✓ SERVER RESET SUCCESS            ║${NC}"
echo -e "  ${BG}╠═════════════════════════════════════╣${NC}"
echo -e "  ${BG}║${NC}  Server is now fresh & bersih."
echo -e "  ${BG}║${NC}  Tersisa: OpenSSH + deploy-by-mizyal"
echo -e "  ${BG}║${NC}"
echo -e "  ${BG}║${NC}    ${C}ssh root@$IP${NC}"
echo -e "  ${BG}║${NC}"
echo -e "  ${BG}╚═════════════════════════════════════╝${NC}"
echo ""