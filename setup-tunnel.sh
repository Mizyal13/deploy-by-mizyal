#!/bin/bash

set -Eeuo pipefail

VERSION="2.2"

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
TUNNEL_AUTO="${TUNNEL_AUTO:-0}"
TUNNEL_DOMAIN="${TUNNEL_DOMAIN:-}"

if [ "$TUNNEL_AUTO" = "1" ]; then
    print_info "Mode otomatis (dipanggil deploy) — tanpa input, domain: ${TUNNEL_DOMAIN:-dari config}"
fi

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
    if [ "$TUNNEL_AUTO" = "1" ]; then
        error_exit "Belum login Cloudflare (cert.pem tidak ada) — jalankan menu 9 sekali untuk login browser, lalu publish lagi"
    fi
    mkdir -p "$HOME/.cloudflared"
    echo -e "  ${Y}Di layar akan muncul URL — buka di browser, login akun Cloudflare, lalu klik Allow/Authorize.${NC}"
    cloudflared tunnel login || error_exit "Login Cloudflare gagal"
    [ -f "$CERT_FILE" ] || error_exit "cert.pem tidak ditemukan setelah login"
    print_ok "Login berhasil"
fi

print_line
echo -e "  ${C}[3/5] Subdomain${NC}"
print_line
DOMAIN_RE='^[a-z0-9]([a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}$'
EXISTING_DOMAIN=""
if [ -f /etc/cloudflared/config.yml ]; then
    CANDIDATE=$(grep 'hostname:' /etc/cloudflared/config.yml 2>/dev/null | awk '/hostname:/{print $3}' | grep -v '^www\.' | head -1 | xargs || true)
    if [[ "$CANDIDATE" =~ $DOMAIN_RE ]]; then
        EXISTING_DOMAIN=$CANDIDATE
    fi
fi
if [ -z "$EXISTING_DOMAIN" ] && [ -f /etc/apache2/sites-available/solides.conf ]; then
    CANDIDATE=$(awk '/ServerName/{print $2; exit}' /etc/apache2/sites-available/solides.conf 2>/dev/null | xargs || true)
    if [[ "$CANDIDATE" =~ $DOMAIN_RE ]]; then
        EXISTING_DOMAIN=$CANDIDATE
    fi
fi
if [ "$TUNNEL_AUTO" = "1" ] && [ -n "$TUNNEL_DOMAIN" ]; then
    DOMAIN=$(echo "$TUNNEL_DOMAIN" | sed 's|^https\?://||; s|/.*$||' | tr '[:upper:]' '[:lower:]')
    if ! [[ "$DOMAIN" =~ ^[a-z0-9.-]+\.[a-z]{2,}$ ]]; then
        error_exit "TUNNEL_DOMAIN tidak valid: $DOMAIN"
    fi
    print_ok "Domain otomatis: $DOMAIN"
elif [ "$TUNNEL_AUTO" = "1" ] && [ -n "$EXISTING_DOMAIN" ]; then
    DOMAIN=$EXISTING_DOMAIN
    print_ok "Pakai domain dari config: $DOMAIN"
elif [ "$TUNNEL_AUTO" = "1" ]; then
    error_exit "Mode otomatis tanpa domain — jalankan dengan TUNNEL_DOMAIN=..."
elif [ -n "$EXISTING_DOMAIN" ]; then
    EXISTING_DOMAIN=$(echo "$EXISTING_DOMAIN" | sed 's|^https\?://||; s|/.*$||' | tr '[:upper:]' '[:lower:]')
    read -p "  Domain saat ini: $EXISTING_DOMAIN — Enter untuk pakai, atau ketik domain BARU: " NEW_DOMAIN </dev/tty
    NEW_DOMAIN=$(echo "$NEW_DOMAIN" | sed 's|^https\?://||; s|/.*$||' | tr '[:upper:]' '[:lower:]')
    if [ -n "$NEW_DOMAIN" ] && [[ "$NEW_DOMAIN" =~ ^[a-z0-9.-]+\.[a-z]{2,}$ ]]; then
        DOMAIN=$NEW_DOMAIN
        print_ok "Domain baru: $DOMAIN (route DNS lama $EXISTING_DOMAIN akan dihapus)"
    else
        DOMAIN=$EXISTING_DOMAIN
        print_ok "Pakai domain saat ini: $DOMAIN"
    fi
else
    while true; do
        read -p "  Subdomain (mis. solides.example.com): " DOMAIN </dev/tty
        DOMAIN=$(echo "$DOMAIN" | sed 's|^https\?://||; s|/.*$||' | tr '[:upper:]' '[:lower:]')
        if [[ "$DOMAIN" =~ ^[a-z0-9.-]+\.[a-z]{2,}$ ]]; then
            break
        fi
        print_warn "Subdomain tidak valid. Contoh: solides.example.com"
    done
fi
print_ok "Subdomain: $DOMAIN"

print_line
echo -e "  ${C}[4/5] Buat tunnel + DNS${NC}"
print_line
cloudflared service uninstall >/dev/null 2>&1 || true
rm -rf /etc/cloudflared
mkdir -p /etc/cloudflared
if cloudflared tunnel list | grep -qE "^[a-z0-9-]+[[:space:]]+$TUNNEL_NAME[[:space:]]"; then
    print_ok "Tunnel '$TUNNEL_NAME' sudah ada"
else
    cloudflared tunnel create "$TUNNEL_NAME" || error_exit "Gagal buat tunnel"
    print_ok "Tunnel '$TUNNEL_NAME' dibuat"
fi
UUID=$(cloudflared tunnel list | grep -E "^[a-z0-9-]+[[:space:]]+$TUNNEL_NAME[[:space:]]" | awk '{print $1}')
[ -n "$UUID" ] || error_exit "Gagal mengambil UUID tunnel"

if [ -n "${EXISTING_DOMAIN:-}" ] && [ "$EXISTING_DOMAIN" != "$DOMAIN" ]; then
    cloudflared tunnel route dns --delete "$TUNNEL_NAME" "$EXISTING_DOMAIN" >/dev/null 2>&1 || true
    print_warn "Route DNS lama $EXISTING_DOMAIN dihapus"
fi
DOMAIN_PARTS=$(echo "$DOMAIN" | tr '.' '\n' | grep -c '^[[:alnum:]-]\+$' || true)
if [ "${DOMAIN_PARTS:-0}" -le 3 ]; then
    cloudflared tunnel route dns "$TUNNEL_NAME" "www.$DOMAIN" >/dev/null 2>&1 \
        || print_warn "route dns www.$DOMAIN tidak dibutuhkan/ditemukan, diabaikan"
fi
cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN" >/dev/null 2>&1 || true
sleep 5
TARGET=$(dig +short CNAME "$DOMAIN" 2>/dev/null | head -1)
if [ "$TARGET" = "$UUID.cfargotunnel.com" ]; then
    print_ok "DNS $DOMAIN → $UUID.cfargotunnel.com (TERVERIFIKASI)"
else
    print_warn "CNAME belum menunjuk tunnel (sekarang: ${TARGET:-kosong}) — coba ulang route dns..."
    cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN" >/dev/null 2>&1 || true
    sleep 10
    TARGET=$(dig +short CNAME "$DOMAIN" 2>/dev/null | head -1)
    if [ "$TARGET" = "$UUID.cfargotunnel.com" ]; then
        print_ok "DNS $DOMAIN → $UUID.cfargotunnel.com (TERVERIFIKASI)"
    else
        print_warn "Route DNS belum terverifikasi (${TARGET:-kosong}) — login harus memakai akun pemilik zona, lalu:"
        echo -e "  ${DG}cloudflared tunnel route dns $TUNNEL_NAME $DOMAIN${NC}"
    fi
fi

print_line
echo -e "  ${C}[5/5] Pasang service tunnel${NC}"
print_line
cat > /etc/cloudflared/config.yml <<EOF
tunnel: $UUID
credentials-file: $HOME/.cloudflared/$UUID.json

ingress:
  - hostname: $DOMAIN
    service: http://localhost:80
EOF
if [ "${DOMAIN_PARTS:-0}" -le 3 ]; then
    cat >> /etc/cloudflared/config.yml <<EOF
  - hostname: www.$DOMAIN
    service: http://localhost:80
EOF
fi
cat >> /etc/cloudflared/config.yml <<EOF
  - service: http_status:404
EOF
print_ok "Konfigurasi /etc/cloudflared/config.yml ditulis"

SRV_NAME="_v2-origintunneld._tcp.argotunnel.com"
IFACE=$(ip -o -4 route show to default 2>/dev/null | awk '{print $5}')

force_dns_cloudflare() {
    systemctl enable --now systemd-resolved >/dev/null 2>&1 || true
    grep -q '^\[Resolve\]' /etc/systemd/resolved.conf || printf '\n[Resolve]\n' >> /etc/systemd/resolved.conf
    sed -i 's/^#\?DNS=.*/DNS=1.1.1.1 1.0.0.1/' /etc/systemd/resolved.conf
    sed -i 's/^#\?FallbackDNS=.*/FallbackDNS=8.8.8.8 8.8.4.4/' /etc/systemd/resolved.conf
    sed -i 's/^#\?Domains=.*/Domains=~./' /etc/systemd/resolved.conf
    grep -q '^DNS=' /etc/systemd/resolved.conf || echo 'DNS=1.1.1.1 1.0.0.1' >> /etc/systemd/resolved.conf
    grep -q '^FallbackDNS=' /etc/systemd/resolved.conf || echo 'FallbackDNS=8.8.8.8 8.8.4.4' >> /etc/systemd/resolved.conf
    grep -q '^Domains=' /etc/systemd/resolved.conf || echo 'Domains=~.' >> /etc/systemd/resolved.conf
    systemctl restart systemd-resolved 2>/dev/null || true
    ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf 2>/dev/null || true
    if [ -n "$IFACE" ]; then
        resolvectl dns "$IFACE" 1.1.1.1 1.0.0.1 2>/dev/null || true
        resolvectl domain "$IFACE" '~.' 2>/dev/null || true
        resolvectl default-route "$IFACE" true 2>/dev/null || true
    fi
    resolvectl flush-caches 2>/dev/null || true
    if ! command -v resolvectl >/dev/null 2>&1 || [ ! -S /run/systemd/resolve/io.systemd.Resolve ]; then
        printf 'nameserver 1.1.1.1\nnameserver 1.0.0.1\n' > /etc/resolv.conf
    fi
}

count_srv() {
    command -v dig >/dev/null 2>&1 || apt install -y dnsutils >/dev/null 2>&1 || true
    local COUNT
    COUNT=$(dig +short +tries=2 +time=3 SRV "$SRV_NAME" 2>/dev/null | grep -c '^' || true)
    echo "${COUNT:-0}"
}

print_warn "Samakan resolver sistem dengan 1.1.1.1 (dipakai cloudflared) — permanen"
force_dns_cloudflare

SRV_COUNT=$(count_srv)
if [ "${SRV_COUNT:-0}" -ge 2 ]; then
    print_ok "DNS SRV Cloudflare OK ($SRV_COUNT record via 1.1.1.1)"
else
    print_warn "SRV Cloudflare cuma $SRV_COUNT record dari 1.1.1.1 — diagnosa:"
    echo -e "  ${DG}cat /etc/resolv.conf${NC}"
    echo -e "  ${DG}resolvectl status | grep -A4 'Current DNS'${NC}"
    echo -e "  ${DG}dig +short SRV $SRV_NAME${NC}"
    print_warn "Cloudflare butuh >=2 record SRV. Cek: router/modem balik NAT sering menyaring SRV — set DNS 1.1.1.1 di panel router, atau coba lagi beberapa kali."
fi

if cloudflared --config /etc/cloudflared/config.yml service install; then
    print_ok "Service terpasang"
else
    print_warn "Service gagal start — retry otomatis..."
    systemctl restart cloudflared 2>/dev/null || true
    sleep 3
    if systemctl is-active --quiet cloudflared; then
        print_ok "cloudflared AKTIF setelah retry"
    else
        print_warn "Diagnosa:"
        echo -e "  ${DG}SRV : $(dig +short SRV _v2-origintunneld._tcp.argotunnel.com 2>/dev/null | tr '\n' ' ')${NC}"
        echo -e "  ${DG}DNS : $(resolvectl status 2>/dev/null | grep -m4 'DNS Servers' | tr '\n' ' ')${NC}"
        journalctl -u cloudflared --no-pager -n 30 2>/dev/null || true
        error_exit "Lihat log di atas, atau: sudo journalctl -u cloudflared -n 50"
    fi
fi
systemctl enable cloudflared >/dev/null 2>&1 || true
systemctl restart cloudflared
for i in 1 2 3 4 5; do
    systemctl is-active --quiet cloudflared && break
    sleep 3
done

if systemctl is-active --quiet cloudflared; then
    print_ok "Cloudflare Tunnel AKTIF (service systemd)"
else
    print_warn "Tunnel belum aktif — cek: sudo journalctl -u cloudflared -n 50"
fi
echo ""
print_info "Verifikasi di browser: https://$DOMAIN"
echo ""