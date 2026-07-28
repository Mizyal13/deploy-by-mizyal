#!/bin/bash

set -Eeuo pipefail

VERSION="2.0"

error_exit() {
    echo ""
    echo "ERROR: $1"
    echo ""
    exit 1
}

if [ "$EUID" -ne 0 ]; then
    error_exit "Run as root"
fi

clear
echo "====================================="
echo "  DEPLOY BY MIZYAL"
echo "  Full Reset"
echo "====================================="
echo ""
echo "WARNING: This will remove EVERYTHING:"
echo "  - All websites in /var/www/"
echo "  - Apache2 and all configs"
echo "  - PHP and all extensions"
echo "  - MySQL and ALL databases"
echo "  - Composer"
echo "  - Certbot / SSL certificates"
echo "  - UFW firewall rules"
echo "  - fail2ban"
echo ""
echo "OpenSSH will be KEPT for remote access."
echo ""

read -p "Type 'RESET' to confirm: " CONFIRM </dev/tty

if [ "$CONFIRM" != "RESET" ]; then
    echo "Cancelled"
    exit 0
fi

# --- step 1: stop services ---

echo ""
echo "[1/6] Stopping services"
echo ""
systemctl stop apache2 || true
systemctl stop mysql || true
systemctl stop php*-fpm || true
systemctl stop fail2ban || true

# --- step 2: disable services ---

echo ""
echo "[2/6] Disabling services"
echo ""
systemctl disable apache2 || true
systemctl disable mysql || true
systemctl disable php*-fpm || true
systemctl disable fail2ban || true

# --- step 3: purge packages ---

echo ""
echo "[3/6] Removing packages"
echo ""
apt purge -y apache2 apache2-bin apache2-data apache2-utils ssl-cert || true
apt purge -y 'php*' || true
apt purge -y mysql-server mysql-client mysql-client-core mysql-server-core mysql-common || true
apt purge -y certbot python3-certbot-apache || true
apt purge -y fail2ban || true
apt autoremove -y || true
apt autoclean -y || true

# --- step 4: remove files ---

echo ""
echo "[4/6] Removing project files"
echo ""

if [ -d "/var/www" ]; then
    rm -rf /var/www/*
    echo "All project files removed"
else
    echo "/var/www not found"
fi

# --- step 5: remove databases ---

echo ""
echo "[5/6] Removing databases"
echo ""

if systemctl is-active --quiet mysql; then
    for DB in $(mysql -u root -N -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('mysql','information_schema','performance_schema','sys');"); do
        mysql -u root -e "DROP DATABASE \`$DB\`;"
        echo "Dropped: $DB"
    done

    for USER in $(mysql -u root -N -e "SELECT user FROM mysql.user WHERE user NOT IN ('root','mysql.sys','mysql.session','mysql.infoschema');"); do
        mysql -u root -e "DROP USER IF EXISTS '$USER'@'localhost';"
        echo "Dropped user: $USER"
    done

    mysql -u root -e "FLUSH PRIVILEGES;"
else
    echo "MySQL not running, skipping"
fi

# --- step 6: reset firewall ---

echo ""
echo "[6/6] Resetting firewall"
echo ""
ufw --force reset || true
ufw allow OpenSSH || true
ufw --force enable || true
echo "Only OpenSSH is allowed"

# --- cleanup ---

rm -f /usr/local/bin/composer || true
crontab -r || true

IP=$(hostname -I | awk '{print $1}')

echo ""
echo "============================================="
echo "  SERVER RESET SUCCESS"
echo "============================================="
echo ""
echo "  Server is now fresh."
echo "  SSH is still active:"
echo ""
echo "    ssh root@$IP"
echo ""
echo "============================================="
echo "  Deploy by Mizyal"
echo "============================================="
