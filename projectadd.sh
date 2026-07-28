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
echo -e "  ${C}ADD PROJECT  v$VERSION${NC}"
print_line
echo ""

command -v apache2 >/dev/null || error_exit "Apache2 not found. Run install.sh first."
command -v php >/dev/null || error_exit "PHP not found. Run install.sh first."
command -v mysql >/dev/null || error_exit "MySQL not found. Run install.sh first."
command -v composer >/dev/null || error_exit "Composer not found. Run install.sh first."

PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')

while true; do
    read -p "  Project Name: " PROJECT </dev/tty
    [ -n "$PROJECT" ] && break
    echo -e "  ${R}Cannot be empty${NC}"
done

WEB="/var/www/$PROJECT"
[ -d "$WEB" ] && error_exit "Project '$PROJECT' already exists"

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

echo ""
print_line
echo -e "  ${C}[1/8] Downloading project${NC}"
print_line
mkdir -p /var/www
git clone --branch "$BRANCH" "$REPO" "$WEB" || error_exit "Git clone failed"

echo ""
print_line
echo -e "  ${C}[2/8] Creating database${NC}"
print_line
mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
SQL

echo ""
print_line
echo -e "  ${C}[3/8] Configuring Apache${NC}"
print_line
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

echo ""
print_line
echo -e "  ${C}[4/8] Setting permissions${NC}"
print_line
chown -R www-data:www-data "$WEB"
find "$WEB" -type d -exec chmod 755 {} \;
find "$WEB" -type f -exec chmod 644 {} \;

echo ""
print_line
echo -e "  ${C}[5/8] Detecting framework${NC}"
print_line
cd "$WEB"
IS_LARAVEL=false
if [ -f artisan ]; then
    IS_LARAVEL=true
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
echo -e "  ${C}[6/8] Database migration${NC}"
print_line

if [ "$IS_LARAVEL" = true ]; then
    echo -e "  ${C}→${NC} Running artisan migrate..."
    php artisan migrate --force || {
        print_warn "artisan migrate failed"
        read -p "  Import .sql files instead? [y/n]: " IMPORT_SQL </dev/tty
        if [ "$IMPORT_SQL" = "y" ] || [ "$IMPORT_SQL" = "Y" ]; then
            IS_LARAVEL=false
        fi
    }
fi

if [ "$IS_LARAVEL" = false ]; then
    IMPORTED_COUNT=0
    for DIR in "$WEB" "$WEB/database" "$WEB/sql" "$WEB/db" "$WEB/storage"; do
        if [ -d "$DIR" ]; then
            for SQL_FILE in "$DIR"/*.sql; do
                [ -f "$SQL_FILE" ] || continue
                echo -e "  ${C}→${NC} Importing: $(basename "$SQL_FILE")"
                mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$SQL_FILE" || {
                    print_warn "Failed to import $(basename "$SQL_FILE"), skipping"
                    continue
                }
                IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
            done
        fi
    done

    if [ "$IMPORTED_COUNT" -eq 0 ]; then
        echo -e "  ${Y}No .sql files found${NC}"
        read -p "  Import .sql file manually? (enter path or leave empty): " MANUAL_SQL </dev/tty
        if [ -n "$MANUAL_SQL" ]; then
            [ -f "$MANUAL_SQL" ] || error_exit "File not found: $MANUAL_SQL"
            mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$MANUAL_SQL" || error_exit "SQL import failed"
            print_ok "Imported: $(basename "$MANUAL_SQL")"
        else
            print_warn "Skipped. Make sure DB is ready before creating admin."
        fi
    else
        print_ok "Imported $IMPORTED_COUNT SQL file(s)"
    fi
fi

echo ""
print_line
echo -e "  ${C}[7/8] Admin account${NC}"
print_line
read -p "  Create admin account? [y/n]: " CREATE_ADMIN </dev/tty

if [ "$CREATE_ADMIN" = "y" ] || [ "$CREATE_ADMIN" = "Y" ]; then
    while true; do
        read -p "  Table Name: " ADMIN_TABLE </dev/tty
        [ -n "$ADMIN_TABLE" ] && break
        echo -e "  ${R}Cannot be empty${NC}"
    done

    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" \
        -e "SELECT 1 FROM \`$ADMIN_TABLE\` LIMIT 0" 2>/dev/null \
        || error_exit "Table '$ADMIN_TABLE' does not exist. Check your .sql file or migration."

    while true; do
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
        if [ "$ADMIN_USER_COL" != "$ADMIN_PASS_COL" ]; then
            break
        fi
        echo -e "  ${R}Username and Password column cannot be the same${NC}"
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

echo ""
print_line
echo -e "  ${C}[8/8] SSL Setup${NC}"
print_line
if [ "$USE_SSL" = true ]; then
    apt install -y certbot python3-certbot-apache || true
    certbot --apache -d "$DOMAIN" --agree-tos --non-interactive -m admin@$DOMAIN || true
else
    echo -e "  ${DG}Skipped (IP mode)${NC}"
fi

IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "  ${BG}╔═════════════════════════════════════╗${NC}"
echo -e "  ${BG}║  ✓ PROJECT ADDED                   ║${NC}"
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
