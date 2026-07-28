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
echo "  Remove Project"
echo "====================================="
echo ""

while true; do
    read -p "Project Name: " PROJECT </dev/tty
    [ -n "$PROJECT" ] && break
    echo "Cannot be empty"
done

WEB="/var/www/$PROJECT"
CONF="/etc/apache2/sites-available/$PROJECT.conf"

if [ ! -d "$WEB" ] && [ ! -f "$CONF" ]; then
    error_exit "Project '$PROJECT' not found"
fi

echo ""
echo "This will remove:"
echo "  Project : $PROJECT"
echo "  Files   : $WEB"
echo "  Config  : $CONF"
echo ""
read -p "Continue? [y/n]: " CONFIRM </dev/tty

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Cancelled"
    exit 0
fi

# --- step 1: remove apache config ---

echo ""
echo "[1/3] Removing Apache config"
echo ""
a2dissite "$PROJECT.conf" || true
rm -f "$CONF"
systemctl reload apache2 || true

# --- step 2: remove files ---

echo ""
echo "[2/3] Removing project files"
echo ""

if [ -d "$WEB" ]; then
    rm -rf "$WEB"
    echo "Removed: $WEB"
else
    echo "Not found: $WEB"
fi

# --- step 3: remove database ---

echo ""
echo "[3/3] Database cleanup"
echo ""
read -p "Remove database? [y/n]: " REMOVE_DB </dev/tty

if [ "$REMOVE_DB" = "y" ] || [ "$REMOVE_DB" = "Y" ]; then
    while true; do
        read -p "Database Name: " DB_NAME </dev/tty
        [ -n "$DB_NAME" ] && break
        echo "Cannot be empty"
    done

    while true; do
        read -p "Database User: " DB_USER </dev/tty
        [ -n "$DB_USER" ] && break
        echo "Cannot be empty"
    done

    mysql -u root <<SQL
DROP DATABASE IF EXISTS \`$DB_NAME\`;
DROP USER IF EXISTS '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
SQL

    echo "Database '$DB_NAME' and user '$DB_USER' removed"
else
    echo "Skipped"
fi

echo ""
echo "============================================="
echo "  PROJECT REMOVED"
echo "============================================="
echo ""
echo "  Project: $PROJECT"
echo ""
echo "============================================="
echo "  Deploy by Mizyal"
echo "============================================="
