#!/bin/bash

set -Eeuo pipefail

VERSION="1.0"

PROJECT_NAME="${SOLIDES_PROJECT_NAME:-solides}"
WEB="/var/www/$PROJECT_NAME"
GIT_REPO="${SOLIDES_GIT_REPO:-https://github.com/hanafi0508/SPKSOLIDES.git}"
GIT_BRANCH="${SOLIDES_GIT_BRANCH:-main}"
DB_CONFIG="$WEB/config/database.php"
ENV_FILE="$WEB/.env"

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

[ -d "$WEB/.git" ] || error_exit "$WEB bukan repository git. Jalankan deploy-solides.sh dulu."

info_lines() {
    echo ""
    print_line
    echo -e "  ${C}$1${NC}"
    print_line
}

info_lines "  BACKUP KREDENSIAL"
LOCAL_DB_CONFIG="$WEB/config/database.local.php"
DB_HOST="localhost"
DB_USER=""
DB_PASS=""
DB_NAME=""
if [ -f "$LOCAL_DB_CONFIG" ]; then
    DB_HOST=$(grep -oP "(?<=\\\$DB_HOST = ')[^']*" "$LOCAL_DB_CONFIG")
    DB_USER=$(grep -oP "(?<=\\\$DB_USER = ')[^']*" "$LOCAL_DB_CONFIG")
    DB_PASS=$(grep -oP "(?<=\\\$DB_PASS = ')[^']*" "$LOCAL_DB_CONFIG")
    DB_NAME=$(grep -oP "(?<=\\\$DB_NAME = ')[^']*" "$LOCAL_DB_CONFIG")
elif [ -f "$DB_CONFIG" ]; then
    DB_USER=$(grep -oP "(?<=\\\$user = \")[^\"]*" "$DB_CONFIG" 2>/dev/null || echo "")
    DB_PASS=$(grep -oP "(?<=\\\$pass = \")[^\"]*" "$DB_CONFIG" 2>/dev/null || echo "")
    DB_NAME=$(grep -oP "(?<=\\\$db   = \")[^\"]*" "$DB_CONFIG" 2>/dev/null || echo "")
fi
[ -n "$DB_USER" ] || error_exit "Gagal membaca user dari $LOCAL_DB_CONFIG / $DB_CONFIG"
[ -n "$DB_PASS" ] || error_exit "Gagal membaca password dari $LOCAL_DB_CONFIG / $DB_CONFIG"
print_ok "Kredensial DB dibackup (user=$DB_USER, db=$DB_NAME)"

if [ -f "$ENV_FILE" ]; then
    cp "$ENV_FILE" /root/${PROJECT_NAME}-env.backup
    print_ok ".env dibackup ke /root/${PROJECT_NAME}-env.backup"
else
    print_warn ".env tidak ditemukan, akan dibuat ulang dari template"
fi

info_lines "  GIT FETCH + RESET KE $GIT_BRANCH"
cd "$WEB"
GIT_TERMINAL_PROMPT=0 git fetch origin || error_exit "git fetch gagal — cek koneksi/repo (tidak pakai username/password GitHub)"
git reset --hard "origin/$GIT_BRANCH" || error_exit "git reset gagal"
NEW_COMMIT=$(git rev-parse --short HEAD)
print_ok "Sekarang di commit $NEW_COMMIT ($GIT_BRANCH)"

info_lines "  RESTORE KREDENSIAL"
mkdir -p "$WEB/config"
if [ ! -f "$DB_CONFIG" ]; then
    cat > "$DB_CONFIG" <<'PHPEOF'
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
    print_ok "config/database.php dibuat dari template"
fi

cat > "$LOCAL_DB_CONFIG" <<PHPEOF
<?php

\$DB_HOST = '$DB_HOST';
\$DB_USER = '$DB_USER';
\$DB_PASS = '$DB_PASS';
\$DB_NAME = '$DB_NAME';
PHPEOF
print_ok "config/database.local.php dipulihkan"

if [ ! -f "$ENV_FILE" ] && [ -f "/root/${PROJECT_NAME}-env.backup" ]; then
    cp "/root/${PROJECT_NAME}-env.backup" "$ENV_FILE"
    print_ok ".env dipulihkan"
fi

info_lines "  PERMISSION"
chown -R www-data:www-data "$WEB"
find "$WEB" -type d -exec chmod 755 {} \;
find "$WEB" -type f -exec chmod 644 {} \;
chown root:root "$LOCAL_DB_CONFIG" "$DB_CONFIG" "$ENV_FILE" 2>/dev/null || true
chmod 600 "$LOCAL_DB_CONFIG" "$DB_CONFIG" "$ENV_FILE" 2>/dev/null || true
print_ok "Permission diterapkan"

if [ -f "$WEB/database/init.sql" ]; then
    info_lines "  UPDATE DATABASE (OPSIONAL)"
    echo -e "  ${Y}PERINGATAN: init.sql berisi DROP DATABASE IF EXISTS.${NC}"
    echo -e "  ${Y}Menjalankannya akan MENGHAPUS SEMUA DATA lalu buat ulang.${NC}"
    read -p "  Import init.sql (reset database)? [y/N]: " IMPORT_DB </dev/tty
    if [ "$IMPORT_DB" = "y" ] || [ "$IMPORT_DB" = "Y" ]; then
        mysql -u root < "$WEB/database/init.sql" || print_warn "Import init.sql gagal"
        print_ok "Database di-reset dari init.sql"
    else
        echo -e "  ${DG}→ Lewati. Kalau butuh ubah skema, import via phpMyAdmin.${NC}"
    fi
fi

info_lines "  VERIFIKASI"
APP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost 2>/dev/null || echo 000)
echo -e "  ${DG}Commit     : $NEW_COMMIT${NC}"
echo -e "  ${DG}HTTP status: $APP_CODE (200/302 = OK)${NC}"

echo ""
echo -e "  ${BG}╔═══════════════════════════════════════════╗${NC}"
echo -e "  ${BG}║  ✓ PROJECT UPDATED ke $NEW_COMMIT            ║${NC}"
echo -e "  ${BG}╚═══════════════════════════════════════════╝${NC}"
echo ""