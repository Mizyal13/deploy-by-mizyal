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

clear
print_logo
print_line
echo -e "  ${C}INSTALL SERVER  v$VERSION${NC}"
print_line
echo ""

OS=$(lsb_release -is 2>/dev/null || echo Ubuntu)
VID=$(lsb_release -rs 2>/dev/null || echo unknown)
ARCH=$(dpkg --print-architecture)
echo -e "  ${DG}OS: $OS | Version: $VID | Arch: $ARCH${NC}"
echo ""
print_line

echo ""
while true; do
    read -p "  Project Name: " PROJECT </dev/tty
    [ -n "$PROJECT" ] && break
    echo -e "  ${R}Cannot be empty${NC}"
done

while true; do
    read -p "  Git Repository: " REPO </dev/tty
    [ -n "$REPO" ] && break
    echo -e "  ${R}Cannot be empty${NC}"
done

read -p "  Branch [main]: " BRANCH </dev/tty
BRANCH=${BRANCH:-main}

echo ""
echo -e "  ${BG}Deployment Type:${NC}"
echo -e "  ${BG}1${NC}. Domain (with SSL)"
echo -e "  ${BG}2${NC}. IP Address (without SSL)"
echo ""
read -p "  Choose [1/2]: " MODE </dev/tty

if [ "$MODE" = "1" ]; then
    while true; do
        read -p "  Domain: " DOMAIN </dev/tty
        [ -n "$DOMAIN" ] && break
        echo -e "  ${R}Cannot be empty${NC}"
    done
    USE_SSL=true
else
    DOMAIN="_"
    USE_SSL=false
fi

echo ""
echo -e "  ${BG}Database${NC}"
echo ""

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

while true; do
    read -s -p "  Database Password: " DB_PASS </dev/tty
    echo
    [ -n "$DB_PASS" ] && break
    echo -e "  ${R}Cannot be empty${NC}"
done

WEB="/var/www/$PROJECT"

echo ""
print_line
echo -e "  ${C}[1/13] Updating system${NC}"
print_line
apt update -y || error_exit "apt update failed"
apt upgrade -y || true

echo ""
print_line
echo -e "  ${C}[2/13] Installing base packages${NC}"
print_line
apt install -y \
    software-properties-common apt-transport-https ca-certificates \
    curl wget git unzip gnupg lsb-release ufw fail2ban cron \
    || error_exit "Base package install failed"

echo ""
print_line
echo -e "  ${C}[3/13] Installing Apache${NC}"
print_line
apt install -y apache2 || error_exit "Apache install failed"
command -v apache2 || error_exit "Apache not found"
systemctl enable apache2

echo ""
print_line
echo -e "  ${C}[4/13] Installing PHP${NC}"
print_line
apt install -y \
    php php-cli php-common php-fpm php-mysql php-curl \
    php-gd php-mbstring php-xml php-zip php-intl php-bcmath \
    || error_exit "PHP install failed"
PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
echo -e "  ${BG}PHP Version: $PHP_VERSION${NC}"
systemctl enable php${PHP_VERSION}-fpm || true

echo ""
print_line
echo -e "  ${C}[5/13] Installing MySQL${NC}"
print_line
apt install -y mysql-server || error_exit "MySQL install failed"
systemctl enable mysql
systemctl start mysql

echo ""
print_line
echo -e "  ${C}[6/13] Installing Composer${NC}"
print_line
if ! command -v composer >/dev/null; then
    php -r "copy('https://getcomposer.org/installer','composer-setup.php');"
    php composer-setup.php --install-dir=/usr/local/bin --filename=composer
    rm composer-setup.php
fi

echo ""
print_line
echo -e "  ${C}[7/13] Downloading project${NC}"
print_line
mkdir -p /var/www
[ -d "$WEB" ] && rm -rf "$WEB"
git clone --branch "$BRANCH" "$REPO" "$WEB" || error_exit "Git clone failed"

echo ""
print_line
echo -e "  ${C}[8/13] Creating database${NC}"
print_line
mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
SQL

echo ""
print_line
echo -e "  ${C}[9/13] Configuring Apache${NC}"
print_line
a2enmod rewrite proxy_fcgi setenvif

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

a2dissite 000-default.conf || true
a2ensite $PROJECT.conf
systemctl reload apache2

echo ""
print_line
echo -e "  ${C}[10/13] Setting permissions${NC}"
print_line
chown -R www-data:www-data "$WEB"
find "$WEB" -type d -exec chmod 755 {} \;
find "$WEB" -type f -exec chmod 644 {} \;

echo ""
print_line
echo -e "  ${C}[11/13] Detecting framework${NC}"
print_line
cd "$WEB"
if [ -f artisan ]; then
    print_ok "Laravel detected"
    composer install --no-dev --optimize-autoloader || true
    php artisan key:generate || true
    php artisan storage:link || true
    php artisan config:cache || true
elif [ -f composer.json ]; then
    print_ok "Composer project"
    composer install || true
else
    print_ok "PHP Native"
fi

echo ""
print_line
echo -e "  ${C}[12/13] Security setup${NC}"
print_line
ufw allow OpenSSH
ufw allow "Apache Full"
ufw --force enable
systemctl enable fail2ban

if [ "$USE_SSL" = true ]; then
    echo ""
    echo -e "  ${C}Installing SSL${NC}"
    apt install -y certbot python3-certbot-apache
    certbot --apache -d "$DOMAIN" --agree-tos --non-interactive -m admin@$DOMAIN || true
fi

echo ""
print_line
echo -e "  ${C}[13/13] Admin account${NC}"
print_line
read -p "  Create admin account? [y/n]: " CREATE_ADMIN </dev/tty

if [ "$CREATE_ADMIN" = "y" ] || [ "$CREATE_ADMIN" = "Y" ]; then
    IS_LARAVEL=false
    [ -f "$WEB/artisan" ] && IS_LARAVEL=true

    while true; do
        read -p "  Table Name: " ADMIN_TABLE </dev/tty
        [ -n "$ADMIN_TABLE" ] && break
        echo -e "  ${R}Cannot be empty${NC}"
    done
    while true; do
        read -p "  Username/Email Column: " ADMIN_USER_COL </dev/tty
        [ -n "$ADMIN_USER_COL" ] && break
        echo -e "  ${R}Cannot be empty${NC}"
    done
    while true; do
        read -p "  Password Column: " ADMIN_PASS_COL </dev/tty
        [ -n "$ADMIN_PASS_COL" ] && break
        echo -e "  ${R}Cannot be empty${NC}"
    done
    while true; do
        read -p "  Admin Email/Username: " ADMIN_EMAIL </dev/tty
        [ -n "$ADMIN_EMAIL" ] && break
        echo -e "  ${R}Cannot be empty${NC}"
    done
    while true; do
        read -s -p "  Admin Password: " ADMIN_PASS </dev/tty
        echo
        [ -n "$ADMIN_PASS" ] && break
        echo -e "  ${R}Cannot be empty${NC}"
    done

    if [ "$IS_LARAVEL" = true ]; then
        HASH_TYPE="bcrypt"
    else
        echo ""
        echo -e "  ${BG}Password Hash:${NC}"
        echo -e "  ${BG}1${NC}. bcrypt (recommended)"
        echo -e "  ${BG}2${NC}. md5"
        echo -e "  ${BG}3${NC}. plain (no hash)"
        echo ""
        read -p "  Choose [1/2/3]: " HASH_CHOICE </dev/tty
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

    print_ok "Admin account created!"
fi

IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "  ${BG}╔═════════════════════════════════════╗${NC}"
echo -e "  ${BG}║  ✓ DEPLOYMENT SUCCESS              ║${NC}"
echo -e "  ${BG}╠═════════════════════════════════════╣${NC}"
echo -e "  ${BG}║${NC}  Project  : $PROJECT"
echo -e "  ${BG}║${NC}  Location : $WEB"
echo -e "  ${BG}║${NC}  Database : $DB_NAME"
if [ "$USE_SSL" = true ]; then
    echo -e "  ${BG}║${NC}  URL      : https://$DOMAIN"
else
    echo -e "  ${BG}║${NC}  URL      : http://$IP"
fi
if [ "$CREATE_ADMIN" = "y" ] || [ "$CREATE_ADMIN" = "Y" ]; then
    echo -e "  ${BG}║${NC}  Admin    : $ADMIN_EMAIL"
fi
echo -e "  ${BG}╚═════════════════════════════════════╝${NC}"
echo ""
