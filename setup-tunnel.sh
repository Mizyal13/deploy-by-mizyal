#!/bin/bash

set -Eeuo pipefail

VERSION="2.0"

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
    echo ""
    exit 1
}

if [ "$EUID" -ne 0 ]; then
    error_exit "Run as root (sudo)"
fi

TUNNEL_NAME="solides"

print_line
echo -e "  ${C}CLOUDFLARE TUNNEL SETUP (LOGIN)  v$VERSION${NC}"
print_line
echo ""
print_info "Alur: install cloudflared → login Cloudflare → buat tunnel →"
print_info "buat subdomain otomatis → pasang service systemd."
echo ""

print_line
echo -e "  ${C}[1/5] Install cloudflared${NC}"
print_line
if command -v cloudflared >/dev/null 2>&1; then
    print_ok "cloudflared sudah terpasang"
else
    CF_DEB="cloudflared-linux-arm64.deb"
    [ "$(dpkg --print-architecture)" = "amd64" ] && CF_DEB="cloudflared-linux-amd64.deb"
    curl -fsSL -o /tmp/cloudflared.deb "https://github.com/cloudflare/cloudflared/releases/latest/download/$CF_DEB" \
        || error_exit "Download cloudflared gagal"
    apt install -y /tmp/cloudflared.deb >/dev/null 2>&1 \
        || error_exit "Install cloudflared gagal"
    rm -f /tmp/cloudflared.deb
    print_ok "cloudflared terinstall"
fi

print_line
echo -e "  ${C}[2/5] Login Cloudflare${NC}"
print_line
CERT_FILE="$HOME/.cloudflared/cert.pem"
if [ -f "$CERT_FILE" ]; then
    print_ok "Sudah login Cloudflare ($CERT_FILE)"
else
    mkdir -p "$HOME/.cloudflared"
    echo -e "  ${Y}Di layar akan muncul URL — buka di browser, login akun Cloudflare, lalu klik Allow/Authorize.${NC}"
    cloudflared tunnel login || error_exit "Login Cloudflare gagal"
    [ -f "$CERT_FILE" ] || error_exit "cert.pem tidak ditemukan setelah login"
    print_ok "Login berhasil"
fi

print_line
echo -e "  ${C}[3/5] Subdomain${NC}"
print_line
while true; do
    read -p "  Subdomain (mis. solides.example.com): " DOMAIN </dev/tty
    DOMAIN=$(echo "$DOMAIN" | sed 's|^https\?://||; s|/.*$||' | tr '[:upper:]' '[:lower:]')
    if [[ "$DOMAIN" =~ ^[a-z0-9.-]+\.[a-z]{2,}$ ]]; then
        break
    fi
    print_warn "Subdomain tidak valid. Contoh: solides.example.com"
done
print_ok "Subdomain: $DOMAIN"

print_line
echo -e "  ${C}[4/5] Buat tunnel + DNS${NC}"
print_line
if cloudflared tunnel list | grep -qE "^[a-z0-9-]+[[:space:]]+$TUNNEL_NAME[[:space:]]"; then
    print_ok "Tunnel '$TUNNEL_NAME' sudah ada"
else
    cloudflared tunnel create "$TUNNEL_NAME" || error_exit "Gagal buat tunnel"
    print_ok "Tunnel '$TUNNEL_NAME' dibuat"
fi
UUID=$(cloudflared tunnel list | grep -E "^[a-z0-9-]+[[:space:]]+$TUNNEL_NAME[[:space:]]" | awk '{print $1}')
[ -n "$UUID" ] || error_exit "Gagal mengambil UUID tunnel"

cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN" 2>/dev/null \
    || print_warn "route dns gagal — pastikan $DOMAIN ada di zona Cloudflare yang sama"
print_ok "DNS $DOMAIN → tunnel ($UUID.cfargotunnel.com)"

print_line
echo -e "  ${C}[5/5] Pasang service tunnel${NC}"
print_line
cloudflared service uninstall >/dev/null 2>&1 || true
rm -rf /etc/cloudflared
mkdir -p /etc/cloudflared
cat > /etc/cloudflared/config.yml <<EOF
tunnel: $TUNNEL_NAME
credentials-file: $HOME/.cloudflared/$UUID.json

ingress:
  - hostname: $DOMAIN
    service: http://localhost:80
  - hostname: www.$DOMAIN
    service: http://localhost:80
  - service: http_status:404
EOF
print_ok "Konfigurasi /etc/cloudflared/config.yml ditulis"

cloudflared --config /etc/cloudflared/config.yml service install \
    || error_exit "service install gagal"
systemctl enable cloudflared >/dev/null 2>&1 || true
systemctl restart cloudflared
sleep 3

if systemctl is-active --quiet cloudflared; then
    print_ok "Cloudflare Tunnel AKTIF (service systemd)"
else
    print_warn "Tunnel belum aktif — cek: sudo journalctl -u cloudflared -n 50"
fi
echo ""
print_info "Verifikasi di browser: https://$DOMAIN"
echo ""