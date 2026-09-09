#!/bin/bash

set -Eeuo pipefail

VERSION="1.0"

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

print_line
echo -e "  ${C}CLOUDFLARE TUNNEL SETUP  v$VERSION${NC}"
print_line
echo ""
print_info "Verifikasi akses origin: pastikan dashboard Cloudflare sudah"
print_info "men-set public hostname kamu → http://localhost:80"
echo ""

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

valid_token() {
    case "$1" in
        *[!A-Za-z0-9+/=_-]*) return 1 ;;
    esac
    [ "${#1}" -ge 20 ] || return 1
    return 0
}

CF_TOKEN=$(trim "${1:-}")
while [ -z "$CF_TOKEN" ]; do
    read -s -p "  Paste tunnel token (dari Cloudflare dashboard): " CF_TOKEN </dev/tty
    echo
    CF_TOKEN=$(trim "$CF_TOKEN")
    [ -n "$CF_TOKEN" ] || print_warn "Token tidak boleh kosong — coba lagi"
done

if ! valid_token "$CF_TOKEN"; then
    print_warn "Token tampaknya tidak valid (harus string base64 dari Dashboard → Zero Trust → Networks → Tunnels)."
    read -p "  Tetap lanjut? [y/N]: " CONT </dev/tty
    [ "$CONT" = "y" ] || [ "$CONT" = "Y" ] || error_exit "Dibatalkan"
fi

print_line
echo -e "  ${C}[1/4] Bersihkan repo apt Cloudflare yang rusak${NC}"
print_line
rm -f /etc/apt/sources.list.d/cloudflare-main.list /etc/apt/sources.list.d/cloudflare.list
apt update -y || error_exit "apt update gagal"
print_ok "apt siap"

print_line
echo -e "  ${C}[2/4] Install cloudflared${NC}"
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
echo -e "  ${C}[3/4] Install service tunnel${NC}"
print_line
if systemctl is-active --quiet cloudflared 2>/dev/null; then
    print_ok "Cloudflare Tunnel sudah aktif"
else
    cloudflared service uninstall >/dev/null 2>&1 || true
    systemctl daemon-reload || true
    cloudflared service install "$CF_TOKEN" \
        || print_warn "service install gagal — jalankan manual: cloudflared service install <token>"
    sleep 3
fi

print_line
echo -e "  ${C}[4/4] Status${NC}"
print_line
if systemctl is-active --quiet cloudflared; then
    print_ok "Cloudflare Tunnel AKTIF"
else
    print_warn "Tunnel belum aktif — cek: sudo journalctl -u cloudflared -n 50"
fi
echo ""
print_info "Buka https://DOMAIN_KAMU di browser untuk verifikasi."
echo ""