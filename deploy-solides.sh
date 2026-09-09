#!/bin/bash

set -Eeuo pipefail

VERSION="1.0"

PROJECT_NAME="${SOLIDES_PROJECT_NAME:-solides}"
WEB="/var/www/$PROJECT_NAME"
DB_NAME="${SOLIDES_DB_NAME:-spk_supplier}"
DB_APP_USER="${SOLIDES_DB_USER:-solides}"
DB_ADMIN_USER="${SOLIDES_DB_ADMIN_USER:-solides_admin}"
GIT_REPO="${SOLIDES_GIT_REPO:-https://github.com/hanafi0508/SPKSOLIDES.git}"
GIT_BRANCH="${SOLIDES_GIT_BRANCH:-main}"

export DEBIAN_FRONTEND=noninteractive

G='\033[0;32m'
BG='\033[1;32m'
DG='\033[2;32m'
Y='\033[1;33m'
R='\033[0;31m'
C='\033[0;36m'
NC='\033[0m'

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
    exit 1
}

if [ "$EUID" -ne 0 ]; then
    error_exit "Run this script as root (sudo)"
fi

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

gen_pass() {
    openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 20
}

clear
print_logo
print_line
echo -e "  ${C}SOLIDES DEPLOY  v$VERSION${NC}"
print_line
echo ""

echo -e "  ${DG}Target  : Fresh Ubuntu Server (Apache + PHP-FPM + MySQL)${NC}"
echo -e "  ${DG}Project : SOLIDES (AHP Supplier Selection)${NC}"
echo -e "  ${DG}App DB  : ${DB_NAME} | user: ${DB_APP_USER}${NC}"
echo -e "  ${DG}Repo    : ${GIT_REPO} @ ${GIT_BRANCH}${NC}"
echo ""
print_line

while true; do
    read -p "  Domain (di zona Cloudflare kamu): " DOMAIN </dev/tty
    DOMAIN=$(echo "$DOMAIN" | sed 's|^https\?://||; s|/.*$||' | tr '[:upper:]' '[:lower:]')
    if [[ "$DOMAIN" =~ ^[a-z0-9.-]+\.[a-z]{2,}$ ]]; then
        break
    fi
    echo -e "  ${R}Domain tidak valid. Contoh: solides.example.com${NC}"
done

echo ""
echo -e "  ${Y}Pastikan:${NC}"
echo -e "  - Domain $DOMAIN ada di zona Cloudflare kamu (orange cloud / tunnel)"
echo -e "  - Dashboard Cloudflare: buat tunnel lalu set public hostname $DOMAIN → http://localhost:80"
echo -e "  - Repository ${GIT_REPO} sudah di-push ke branch ${GIT_BRANCH}"
echo ""
read -p "  Lanjut? [y/n]: " GO </dev/tty
if [ "$GO" != "y" ] && [ "$GO" != "Y" ]; then
    error_exit "Dibatalkan"
fi

DB_APP_PASS=$(gen_pass)
DB_ADMIN_PASS=$(gen_pass)
APP_ADMIN_PASS=$(gen_pass)
APP_PIMPINAN_PASS=$(gen_pass)

CREDS_FILE="/root/${PROJECT_NAME}-credentials.txt"

log_progress() {
    echo ""
    print_line
    echo -e "  ${C}$1${NC}"
    print_line
}

echo ""
print_line
echo -e "  ${C}[1/14] Updating system${NC}"
print_line
apt update -y || error_exit "apt update failed"
apt upgrade -y || true

log_progress "  [2/14] Installing base packages"
apt install -y \
    software-properties-common apt-transport-https ca-certificates \
    curl wget git unzip gnupg lsb-release ufw fail2ban cron openssl \
    || error_exit "Base package install failed"
add-apt-repository -y universe || true

log_progress "  [3/14] Installing Apache"
apt install -y apache2 || error_exit "Apache install failed"
command -v apache2 || error_exit "Apache not found"
systemctl enable apache2
systemctl start apache2

log_progress "  [4/14] Installing PHP + extensions"
apt install -y \
    php php-cli php-common php-fpm php-mysql php-curl php-mbstring php-zip php-xml \
    || error_exit "PHP install failed (pastikan mysqli tersedia: php-mysql)"
PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
print_info "PHP Version: $PHP_VERSION"
systemctl enable php${PHP_VERSION}-fpm
systemctl start php${PHP_VERSION}-fpm || true

log_progress "  [5/14] Installing MySQL"
apt install -y mysql-server || error_exit "MySQL install failed"
systemctl enable mysql
systemctl start mysql
for i in $(seq 1 30); do
    mysqladmin ping >/dev/null 2>&1 && break
    sleep 1
done
mysqladmin ping >/dev/null 2>&1 || error_exit "MySQL tidak bisa dijalankan"

log_progress "  [6/14] Mengunduh project SOLIDES"
mkdir -p /var/www
rm -rf "$WEB"
git clone --branch "$GIT_BRANCH" --depth 1 "$GIT_REPO" "$WEB" || error_exit "Git clone failed"
print_ok "Project cloned to $WEB"

log_progress "  [7/14] Membuat database & user MySQL"
mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
CREATE USER IF NOT EXISTS '$DB_APP_USER'@'localhost' IDENTIFIED BY '$DB_APP_PASS';
ALTER USER '$DB_APP_USER'@'localhost' IDENTIFIED BY '$DB_APP_PASS';
CREATE USER IF NOT EXISTS '$DB_ADMIN_USER'@'localhost' IDENTIFIED BY '$DB_ADMIN_PASS';
ALTER USER '$DB_ADMIN_USER'@'localhost' IDENTIFIED BY '$DB_ADMIN_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_APP_USER'@'localhost';
GRANT ALL PRIVILEGES ON *.* TO '$DB_ADMIN_USER'@'localhost' WITH GRANT OPTION;
GRANT CREATE USER ON *.* TO '$DB_ADMIN_USER'@'localhost';
FLUSH PRIVILEGES;
SQL
print_ok "Database '$DB_NAME' siap"

log_progress "  [8/14] Import skema + data awal"
if [ -f "$WEB/database/init.sql" ]; then
    mysql -u root < "$WEB/database/init.sql" || error_exit "Import init.sql gagal"
    print_ok "init.sql imported"
else
    print_warn "database/init.sql tidak ditemukan, lewati import"
fi

log_progress "  [9/14] Menyiapkan kredensial database aplikasi"
if [ ! -f "$WEB/config/database.php" ]; then
    cat > "$WEB/config/database.php" <<'PHPEOF'
<?php

$DB_HOST = getenv('DB_HOST') ?: 'localhost';
$DB_USER = getenv('DB_USER') ?: 'root';
$DB_PASS = getenv('DB_PASS') ?: '';
$DB_NAME = getenv('DB_NAME') ?: 'spk_supplier';

if (file_exists(__DIR__ . '/database.local.php')) {
    require __DIR__ . '/database.local.php';
}

mysqli_report(MYSQLI_REPORT_OFF);
$conn = mysqli_connect($DB_HOST, $DB_USER, $DB_PASS, $DB_NAME);

if (!$conn) {
    error_log('Koneksi database gagal: ' . mysqli_connect_error());
    die('Koneksi database gagal. Periksa kembali konfigurasi database.');
}

mysqli_set_charset($conn, 'utf8mb4');
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
PHPEOF
fi

cat > "$WEB/config/database.local.php" <<PHPEOF
<?php

\$DB_HOST = 'localhost';
\$DB_USER = '$DB_APP_USER';
\$DB_PASS = '$DB_APP_PASS';
\$DB_NAME = '$DB_NAME';
PHPEOF
chown root:root "$WEB/config/database.local.php"
chmod 600 "$WEB/config/database.local.php"
print_ok "kredensial DB ditulis ke config/database.local.php"

cat > "$WEB/.env" <<EOF
DB_ADMIN_USER=$DB_ADMIN_USER
DB_ADMIN_PASS=$DB_ADMIN_PASS
EOF
chown root:root "$WEB/.env"
chmod 600 "$WEB/.env"
print_ok ".env berisi kredensial phpMyAdmin dibuat ($WEB/.env)"

log_progress "  [10/14] Mengatur akun login SOLIDES"
if mysql -u root -N -e "USE \`$DB_NAME\`; SELECT 1 FROM users LIMIT 1;" >/dev/null 2>&1; then
    APP_ADMIN_HASH=$(php -r "echo password_hash('$APP_ADMIN_PASS', PASSWORD_BCRYPT);")
    APP_PIMPINAN_HASH=$(php -r "echo password_hash('$APP_PIMPINAN_PASS', PASSWORD_BCRYPT);")
    mysql -u root "$DB_NAME" <<SQL
UPDATE \`users\` SET \`password\` = '$APP_ADMIN_HASH' WHERE \`username\` = 'admin';
UPDATE \`users\` SET \`password\` = '$APP_PIMPINAN_HASH' WHERE \`username\` = 'pimpinan';
SQL
    print_ok "Password akun admin/pimpinan diperbarui (dijamin bisa login)"
else
    print_warn "Tabel users belum ada — buat akun manual via phpMyAdmin nanti"
fi

log_progress "  [11/14] Konfigurasi Apache VirtualHost"
a2enmod rewrite proxy_fcgi setenvif headers ssl
cat > /etc/apache2/sites-available/$PROJECT_NAME.conf <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    DocumentRoot $WEB

    <Directory $WEB>
        AllowOverride All
        Require all granted
    </Directory>

    <DirectoryMatch "^/var/www/.*/\.git/">
        Require all denied
    </DirectoryMatch>

    <FilesMatch "^\.">
        Require all denied
    </FilesMatch>

    <FilesMatch "\.php$">
        SetHandler "proxy:unix:/run/php/php${PHP_VERSION}-fpm.sock|fcgi://localhost/"
    </FilesMatch>

    ErrorLog \${APACHE_LOG_DIR}/$PROJECT_NAME-error.log
    CustomLog \${APACHE_LOG_DIR}/$PROJECT_NAME-access.log combined
</VirtualHost>
EOF
a2dissite 000-default.conf || true
a2ensite "$PROJECT_NAME.conf"
systemctl reload apache2
print_ok "VirtualHost $DOMAIN aktif"

log_progress "  [12/14] Mengatur permission"
chown -R www-data:www-data "$WEB"
find "$WEB" -type d -exec chmod 755 {} \;
find "$WEB" -type f -exec chmod 644 {} \;
chown root:root "$WEB/.env"
chmod 600 "$WEB/.env"
chown root:root "$WEB/config/database.local.php"
chmod 600 "$WEB/config/database.local.php"
print_ok "Permission www-data diterapkan"

log_progress "  [13/14] Menginstall phpMyAdmin"
echo "phpmyadmin phpmyadmin/dbconfig-install boolean false" | debconf-set-selections
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
apt install -y phpmyadmin || {
    print_warn "paket phpmyadmin gagal (coba universe)"
    add-apt-repository -y universe
    apt update -y
    apt install -y phpmyadmin || error_exit "phpMyAdmin install failed"
}
if grep -rsq "Alias /phpmyadmin" /etc/apache2/ 2>/dev/null; then
    print_ok "phpMyAdmin terpasang di /phpmyadmin"
    systemctl reload apache2 || true
else
    print_warn "phpMyAdmin alias belum aktif, buat manual"
    cat > /etc/apache2/conf-available/phpmyadmin.conf <<EOF
Alias /phpmyadmin /usr/share/phpmyadmin

<Directory /usr/share/phpmyadmin>
    Options SymLinksIfOwnerMatch
    DirectoryIndex index.php
    Require all granted
</Directory>
EOF
    a2enconf phpmyadmin
    systemctl reload apache2
fi

log_progress "  [14/14] Setup firewall, fail2ban, Cloudflare Tunnel"
ufw allow OpenSSH
ufw --force enable
apt install -y fail2ban || true

cat > /etc/fail2ban/filter.d/solides.conf <<'EOF'
[Definition]
failregex = ^<HOST> .*"POST /phpmyadmin.* 200
            ^<HOST> .*"POST /phpmyadmin.* 302
            ^<HOST> .*"POST /auth/proses_login.*
ignoreregex =
EOF

cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true

[solides-phpmyadmin]
enabled = true
filter  = solides
logpath = /var/log/apache2/*access.log
action  = ufw
EOF

systemctl enable fail2ban
systemctl restart fail2ban || print_warn "fail2ban gagal restart (cek log /var/log/fail2ban.log)"

echo ""
print_info "Memasang Cloudflare Tunnel (token)..."
if command -v cloudflared >/dev/null 2>&1; then
    print_ok "cloudflared sudah terpasang"
else
    apt install -y curl gpg || true
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
        | gpg --dearmor --yes -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg 2>/dev/null || true
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflare.com/cloudflare main" \
        > /etc/apt/sources.list.d/cloudflare-main.list
    apt update -y || true
    apt install -y cloudflared || error_exit "Gagal install cloudflared"
fi

echo ""
echo -e "  ${Y}Masukkan TOKEN tunnel kamu (Dashboard Cloudflare: Zero Trust → Networks → Tunnels → cloudflared).${NC}"
echo -e "  ${Y}Pastikan public hostname $DOMAIN sudah di-set → http://localhost:80${NC}"
while true; do
    read -s -p "  Tunnel token: " CF_TOKEN </dev/tty
    echo
    [ -n "$CF_TOKEN" ] && break
    print_warn "Token tidak boleh kosong"
done

cloudflared service install "$CF_TOKEN" \
    || print_warn "cloudflared service install gagal — jalankan manual: cloudflared service install <token>"
sleep 3
if systemctl is-active --quiet cloudflared; then
    TUNNEL_OK=true
    print_ok "Cloudflare Tunnel aktif"
else
    TUNNEL_OK=false
    print_warn "Tunnel belum aktif — cek: sudo journalctl -u cloudflared -n 50"
fi

IP=$(hostname -I | awk '{print $1}')
SITE_URL="https://$DOMAIN"
PMA_URL="https://$DOMAIN/phpmyadmin"

cat > "$CREDS_FILE" <<EOF
========================================
 SOLIDES DEPLOYMENT — SIMPAN KREDENSIAL
 Generated at: $(date)
========================================

 Aplikasi SOLIDES
   URL App     : $SITE_URL
   Login admin : admin / $APP_ADMIN_PASS
   Login pimp  : pimpinan / $APP_PIMPINAN_PASS

 Database Aplikasi (ter-set di config/database.local.php)
   Nama DB     : $DB_NAME
   User App    : $DB_APP_USER
   Password App: $DB_APP_PASS

 phpMyAdmin (kelola DB & user via browser)
   URL pma     : $PMA_URL
   User Admin  : $DB_ADMIN_USER
   Password    : $DB_ADMIN_PASS
   (user ini punya hak penuh + CREATE USER)

 Server
   IP          : $IP
   Domain      : $DOMAIN
   SSL         : Cloudflare Tunnel (Universal SSL/edge)
   Tunnel      : $( [ "$TUNNEL_OK" = true ] && echo aktif || echo belum aktif )
========================================
EOF
chmod 600 "$CREDS_FILE"

echo ""
echo -e "  ${BG}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "  ${BG}║  ✓ DEPLOYMENT SOLIDES SELESAI                            ║${NC}"
echo -e "  ${BG}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "  ${BG}║${NC}  App      : $SITE_URL"
echo -e "  ${BG}║${NC}  Admin    : admin / $APP_ADMIN_PASS"
echo -e "  ${BG}║${NC}  Pimpinan : pimpinan / $APP_PIMPINAN_PASS"
echo -e "  ${BG}║${NC}"
echo -e "  ${BG}║${NC}  phpMyAdmin: $PMA_URL"
echo -e "  ${BG}║${NC}  User     : $DB_ADMIN_USER"
echo -e "  ${BG}║${NC}  Password : $DB_ADMIN_PASS"
echo -e "  ${BG}║${NC}"
echo -e "  ${BG}║${NC}  DB App   : ${DB_NAME} (${DB_APP_USER})"
echo -e "  ${BG}║${NC}  Tunnel   : $( [ "$TUNNEL_OK" = true ] && echo "${G}AKTIF${NC}" || echo "${Y}belum aktif${NC}")"
echo -e "  ${BG}║${NC}  .env     : $WEB/.env (phpMyAdmin creds)"
echo -e "  ${BG}║${NC}  Kredensial tersimpan di: $CREDS_FILE"
echo -e "  ${BG}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

print_info "Verifikasi akhir..."
APP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost 2>/dev/null || echo 000)
TABLE_COUNT=$(mysql -u root -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME';" 2>/dev/null || echo 0)
echo -e "  ${DG}App HTTP status : $APP_CODE (200/302 = OK)${NC}"
echo -e "  ${DG}Tabel DB       : $TABLE_COUNT (9 = OK)${NC}"
echo -e "  ${DG}Tunnel         : $( systemctl is-active cloudflared 2>/dev/null || echo tidak-ada )"
echo -e "  ${DG}Cek dari browser: $SITE_URL dan $PMA_URL (via Cloudflare)${NC}"
if [ -s "$WEB/.env" ]; then
    echo -e "  ${DG}.env           : OK ($(grep -c '=' "$WEB/.env") keys)${NC}"
else
    print_warn ".env tidak ditemukan"
fi
echo ""