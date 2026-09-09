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
ENV_FILE="$WEB/.env"

# Ambil nilai DB dari .env; fallback ke database.local.php (server lama) untuk transisi.
read_env() {
    grep -oP "(?<=\b$1=)[^[:space:]]*" "$ENV_FILE" 2>/dev/null | head -1
}
DB_HOST=$(read_env DB_HOST)
DB_USER=$(read_env DB_USER)
DB_PASS=$(read_env DB_PASS)
DB_NAME=$(read_env DB_NAME)
DB_ADMIN_USER=$(read_env DB_ADMIN_USER)
DB_ADMIN_PASS=$(read_env DB_ADMIN_PASS)

if [ -z "$DB_USER" ] && [ -f "$LOCAL_DB_CONFIG" ]; then
    echo -e "  ${Y}[WARN]${NC} .env belum berisi DB_* — ambil dari database.local.php (server lama)"
    DB_HOST="${DB_HOST:-$(grep -oP "(?<=\\\$DB_HOST = ')[^']*" "$LOCAL_DB_CONFIG")}"
    DB_USER=$(grep -oP "(?<=\\\$DB_USER = ')[^']*" "$LOCAL_DB_CONFIG")
    DB_PASS=$(grep -oP "(?<=\\\$DB_PASS = ')[^']*" "$LOCAL_DB_CONFIG")
    DB_NAME=$(grep -oP "(?<=\\\$DB_NAME = ')[^']*" "$LOCAL_DB_CONFIG")
fi
[ -n "$DB_USER" ] || error_exit "Gagal membaca DB_USER dari $ENV_FILE / $LOCAL_DB_CONFIG"
[ -n "$DB_PASS" ] || print_warn "DB_PASS kosong — cek isi .env"
DB_NAME="${DB_NAME:-spk_supplier}"
print_ok "Kredensial DB dibackup (user=$DB_USER, db=$DB_NAME)"

if [ -f "$ENV_FILE" ]; then
    cp "$ENV_FILE" "/root/${PROJECT_NAME}-env.backup"
    print_ok ".env dibackup ke /root/${PROJECT_NAME}-env.backup"
else
    print_warn ".env tidak ditemukan, akan dibuat dari nilai terbaca"
fi

info_lines "  BACKUP DATABASE (otomatis)"
mkdir -p /root/backups
DB_NAME="${DB_NAME:-spk_supplier}"
BK_FILE="/root/backups/${PROJECT_NAME}-db-$(date +%Y%m%d-%H%M%S).sql.gz"
if mysqldump -u root "$DB_NAME" 2>/dev/null | gzip -c > "$BK_FILE"; then
    print_ok "Backup DB $DB_NAME → $BK_FILE"
else
    print_warn "Backup DB gagal (mysqldump?) — lanjut tanpa backup"
fi
ls -1t /root/backups/${PROJECT_NAME}-db-*.sql.gz 2>/dev/null | tail -n +6 | xargs -r rm -f
print_info "Backup lama dibersihkan (hanya 5 backup terbaru disimpan)"

info_lines "  GIT FETCH + RESET KE $GIT_BRANCH"
git config --global --get-all safe.directory 2>/dev/null | grep -qx "$WEB" || git config --global --add safe.directory "$WEB"
cd "$WEB"
GIT_TERMINAL_PROMPT=0 git fetch origin || error_exit "git fetch gagal — cek koneksi/repo (tidak pakai username/password GitHub)"
git reset --hard "origin/$GIT_BRANCH" || error_exit "git reset gagal"
NEW_COMMIT=$(git rev-parse --short HEAD)
print_ok "Sekarang di commit $NEW_COMMIT ($GIT_BRANCH)"

info_lines "  RESTORE KREDENSIAL"
# config/database.php sekarang ikut di-git (sumber dari .env), jadi database.local.php
# TIDAK digunakan lagi. Kredensial disimpan penuh di .env.
DB_HOST="${DB_HOST:-localhost}"
DB_NAME="${DB_NAME:-spk_supplier}"
# DB_ADMIN_* fallback dari backup .env bila .env lama tak punya.
if [ -z "$DB_ADMIN_USER" ] && [ -f "/root/${PROJECT_NAME}-env.backup" ]; then
    DB_ADMIN_USER=$(grep -oP "(?<=\bDB_ADMIN_USER=)[^[:space:]]*" "/root/${PROJECT_NAME}-env.backup" | head -1)
    DB_ADMIN_PASS=$(grep -oP "(?<=\bDB_ADMIN_PASS=)[^[:space:]]*" "/root/${PROJECT_NAME}-env.backup" | head -1)
fi

cat > "$ENV_FILE" <<EOF
APP_ENV=prod
DB_HOST=$DB_HOST
DB_USER=$DB_USER
DB_PASS=$DB_PASS
DB_NAME=$DB_NAME
DB_ADMIN_USER=${DB_ADMIN_USER:-}
DB_ADMIN_PASS=${DB_ADMIN_PASS:-}
EOF
rm -f "$LOCAL_DB_CONFIG"
print_ok ".env dibangun ulang dengan kredensial ($DB_NAME / $DB_USER)"

info_lines "  MIGRASI DATABASE (OTOMATIS, TANPA RESET)"
mysql -u root "$DB_NAME" -e "CREATE TABLE IF NOT EXISTS schema_migrations (id INT AUTO_INCREMENT PRIMARY KEY, filename VARCHAR(255) UNIQUE, applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);" 2>/dev/null || print_warn "Tabel schema_migrations gagal dibuat, tetap lanjut"
for MIG in "$WEB"/database/migration_*.sql; do
    [ -f "$MIG" ] || continue
    BASE=$(basename "$MIG")
    if mysql -u root "$DB_NAME" -N -e "SELECT 1 FROM schema_migrations WHERE filename='$BASE';" 2>/dev/null | grep -q '^1$'; then
        print_ok "Migrasi $BASE sudah pernah dijalankan (skip)"
    else
        if mysql -u root "$DB_NAME" < "$MIG"; then
            mysql -u root "$DB_NAME" -e "INSERT INTO schema_migrations (filename) VALUES ('$BASE');" >/dev/null 2>&1 || true
            print_ok "Migrasi $BASE dijalankan (data aman, tanpa drop)"
        else
            print_warn "Migrasi $BASE gagal — cek SQL-nya lalu import manual via phpMyAdmin"
        fi
    fi
done

info_lines "  PERMISSION"
chown -R www-data:www-data "$WEB"
find "$WEB" -type d -exec chmod 755 {} \;
find "$WEB" -type f -exec chmod 644 {} \;
# .env berisi kredensial → pemilik www-data (terbaca PHP-FPM), mode 640 (privasi).
chown www-data:www-data "$ENV_FILE" 2>/dev/null || true
chmod 640 "$ENV_FILE" 2>/dev/null || true
print_ok "Permission diterapkan (.env mode 640, pemilik www-data)"

if [ -f "$WEB/database/init.sql" ]; then
    info_lines "  UPDATE DATABASE (OPSIONAL)"
    echo -e "  ${Y}PERINGATAN: init.sql berisi DROP DATABASE IF EXISTS.${NC}"
    echo -e "  ${Y}Menjalankannya akan MENGHAPUS SEMUA DATA lalu buat ulang.${NC}"
    read -p "  Reset database sekarang? [y/N]: " RESET_DB </dev/tty
    if [ "$RESET_DB" = "y" ] || [ "$RESET_DB" = "Y" ]; then
        read -p "  Ketik RESET (huruf besar) untuk konfirmasi: " CONFIRM </dev/tty
        if [ "$CONFIRM" = "RESET" ]; then
            mysql -u root < "$WEB/database/init.sql" || print_warn "Import init.sql gagal"
            print_ok "Database di-reset dari init.sql"
        else
            print_warn "Konfirmasi tidak cocok — database TIDAK direset"
        fi
    else
        echo -e "  ${DG}→ Lewati. Database aman, tidak disentuh.${NC}"
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