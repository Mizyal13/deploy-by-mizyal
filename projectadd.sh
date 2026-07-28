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
echo "  Add New Project"
echo "====================================="
echo ""

command -v apache2 >/dev/null || error_exit "Apache2 not found. Run install.sh first."
command -v php >/dev/null || error_exit "PHP not found. Run install.sh first."
command -v mysql >/dev/null || error_exit "MySQL not found. Run install.sh first."
command -v composer >/dev/null || error_exit "Composer not found. Run install.sh first."

PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')

# --- input ---

while true; do
    read -p "Project Name: " PROJECT </dev/tty
    [ -n "$PROJECT" ] && break
    echo "Cannot be empty"
done

WEB="/var/www/$PROJECT"
[ -d "$WEB" ] && error_exit "Project '$PROJECT' already exists"

while true; do
    read -p "Git Repository: " REPO </dev/tty
    [ -n "$REPO" ] && break
    echo "Cannot be empty"
done

read -p "Branch [main]: " BRANCH </dev/tty
BRANCH=${BRANCH:-main}

echo ""
echo "Deployment Type:"
echo "  1. Domain (with SSL)"
echo "  2. IP Address (without SSL)"
echo ""
read -p "Choose [1/2]: " MODE </dev/tty

if [ "$MODE" = "1" ]; then
    while true; do
        read -p "Domain: " DOMAIN </dev/tty
        [ -n "$DOMAIN" ] && break
        echo "Cannot be empty"
    done
    USE_SSL=true
else
    DOMAIN="_"
    USE_SSL=false
fi

echo ""
echo "Database"
echo ""

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

while true; do
    read -s -p "Database Password: " DB_PASS </dev/tty
    echo
    [ -n "$DB_PASS" ] && break
    echo "Cannot be empty"
done

# --- step 1: clone ---

echo ""
echo "[1/7] Downloading project"
echo ""
mkdir -p /var/www
git clone --branch "$BRANCH" "$REPO" "$WEB" || error_exit "Git clone failed"

# --- step 2: database ---

echo ""
echo "[2/7] Creating database"
echo ""
mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
SQL

# --- step 3: apache config ---

echo ""
echo "[3/7] Configuring Apache"
echo ""
a2enmod rewrite proxy_fcgi setenvif || true

cat > /etc/apache2/sites-available/$PROJECT.conf <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    DocumentRoot $WEB

    <Directory $WEB>
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch "\.php$">
        SetHandler "proxy:unix:/run/php/php${PHP_VERSION}-fpm.sock|fcgi://localhost/"
    </FilesMatch>

    ErrorLog \${APACHE_LOG_DIR}/$PROJECT-error.log
    CustomLog \${APACHE_LOG_DIR}/$PROJECT-access.log combined
</VirtualHost>
EOF

a2ensite "$PROJECT.conf"
systemctl reload apache2

# --- step 4: permissions ---

echo ""
echo "[4/7] Setting permissions"
echo ""
chown -R www-data:www-data "$WEB"
find "$WEB" -type d -exec chmod 755 {} \;
find "$WEB" -type f -exec chmod 644 {} \;

# --- step 5: framework detect ---

echo ""
echo "[5/7] Detecting framework"
echo ""
cd "$WEB"

if [ -f artisan ]; then
    echo "Laravel detected"
    composer install --no-dev --optimize-autoloader || true
    php artisan key:generate || true
    php artisan storage:link || true
    php artisan config:cache || true
elif [ -f composer.json ]; then
    echo "Composer project"
    composer install || true
else
    echo "PHP Native"
fi

# --- step 6: admin account ---

echo ""
echo "[6/7] Admin account"
echo ""
read -p "Create admin account? [y/n]: " CREATE_ADMIN </dev/tty

if [ "$CREATE_ADMIN" = "y" ] || [ "$CREATE_ADMIN" = "Y" ]; then

    IS_LARAVEL=false
    [ -f "$WEB/artisan" ] && IS_LARAVEL=true

    while true; do
        read -p "Table Name: " ADMIN_TABLE </dev/tty
        [ -n "$ADMIN_TABLE" ] && break
        echo "Cannot be empty"
    done

    while true; do
        read -p "Username/Email Column: " ADMIN_USER_COL </dev/tty
        [ -n "$ADMIN_USER_COL" ] && break
        echo "Cannot be empty"
    done

    while true; do
        read -p "Password Column: " ADMIN_PASS_COL </dev/tty
        [ -n "$ADMIN_PASS_COL" ] && break
        echo "Cannot be empty"
    done

    while true; do
        read -p "Admin Email/Username: " ADMIN_EMAIL </dev/tty
        [ -n "$ADMIN_EMAIL" ] && break
        echo "Cannot be empty"
    done

    while true; do
        read -s -p "Admin Password: " ADMIN_PASS </dev/tty
        echo
        [ -n "$ADMIN_PASS" ] && break
        echo "Cannot be empty"
    done

    if [ "$IS_LARAVEL" = true ]; then
        HASH_TYPE="bcrypt"
    else
        echo ""
        echo "Password Hash Type:"
        echo "  1. bcrypt (recommended)"
        echo "  2. md5"
        echo "  3. plain (no hash)"
        echo ""
        read -p "Choose [1/2/3]: " HASH_CHOICE </dev/tty
        case "$HASH_CHOICE" in
            1) HASH_TYPE="bcrypt" ;;
            2) HASH_TYPE="md5" ;;
            3) HASH_TYPE="plain" ;;
            *) HASH_TYPE="bcrypt" ;;
        esac
    fi

    case "$HASH_TYPE" in
        bcrypt) HASHED_PASS=$(php -r "echo password_hash('$ADMIN_PASS', PASSWORD_BCRYPT);") ;;
        md5)    HASHED_PASS=$(php -r "echo md5('$ADMIN_PASS');") ;;
        plain)  HASHED_PASS="$ADMIN_PASS" ;;
    esac

    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" \
        -e "INSERT INTO \`$ADMIN_TABLE\` (\`$ADMIN_USER_COL\`, \`$ADMIN_PASS_COL\`) VALUES ('$ADMIN_EMAIL', '$HASHED_PASS');" \
        || error_exit "Failed to create admin account"

    echo "Admin account created!"
fi

# --- step 7: ssl ---

echo ""
echo "[7/7] SSL Setup"
echo ""

if [ "$USE_SSL" = true ]; then
    apt install -y certbot python3-certbot-apache || true
    certbot --apache -d "$DOMAIN" --agree-tos --non-interactive -m admin@$DOMAIN || true
else
    echo "Skipped (IP mode)"
fi

# --- done ---

IP=$(hostname -I | awk '{print $1}')

echo ""
echo "============================================="
echo "  PROJECT ADDED"
echo "============================================="
echo ""
echo "  Project  : $PROJECT"
echo "  Location : $WEB"
echo "  Database : $DB_NAME"
echo ""

if [ "$USE_SSL" = true ]; then
    echo "  URL      : https://$DOMAIN"
else
    echo "  URL      : http://$IP"
fi

if [ "$CREATE_ADMIN" = "y" ] || [ "$CREATE_ADMIN" = "Y" ]; then
    echo "  Admin    : $ADMIN_EMAIL"
fi

echo ""
echo "============================================="
echo "  Deploy by Mizyal"
echo "============================================="
