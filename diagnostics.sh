#!/bin/bash

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
print_info() { echo -e "  ${C}→${NC}  $1"; }

PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "?")

clear
print_logo
print_line
echo -e "  ${C}DIAGNOSTICS  v$VERSION${NC}"
print_line
echo ""

# Mode detection
if [ "$EUID" -ne 0 ]; then
    print_warn "Not root, some checks skipped"
fi

MODE=""
for arg in "$@"; do
    case "$arg" in
        --status) MODE="status" ;;
        --full)   MODE="full" ;;
    esac
done

if [ -z "$MODE" ]; then
    echo -e "  ${BG}Select mode:${NC}"
    echo -e "  ${BG}1${NC}. Quick Status"
    echo -e "  ${BG}2${NC}. Full Diagnostics"
    echo ""
    read -p "  Choose [1/2]: " CHOICE </dev/tty
    case "$CHOICE" in
        1) MODE="status" ;;
        2) MODE="full" ;;
        *) MODE="status" ;;
    esac
fi

check_apache() {
    echo ""
    print_line
    echo -e "  ${C}Apache2${NC}"
    print_line
    if systemctl is-active --quiet apache2; then
        print_ok "Running"
    else
        print_fail "Not running"
    fi
    if apache2ctl configtest 2>&1 | grep -q "Syntax OK"; then
        print_ok "Config syntax OK"
    else
        print_fail "Config has errors"
    fi
}

check_php() {
    echo ""
    print_line
    echo -e "  ${C}PHP${NC}"
    print_line
    if command -v php >/dev/null; then
        print_ok "PHP $PHP_VERSION"
    else
        print_fail "PHP not found"
        return
    fi
    if systemctl is-active --quiet php${PHP_VERSION}-fpm; then
        print_ok "PHP-FPM running"
    else
        print_fail "PHP-FPM not running"
    fi
}

check_mysql() {
    echo ""
    print_line
    echo -e "  ${C}MySQL${NC}"
    print_line
    if systemctl is-active --quiet mysql; then
        print_ok "Running"
    else
        print_fail "Not running"
    fi
    DB_COUNT=$(mysql -u root -N -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name NOT IN ('mysql','information_schema','performance_schema','sys');" 2>/dev/null || echo "?")
    print_info "Databases: $DB_COUNT"
}

check_projects() {
    echo ""
    print_line
    echo -e "  ${C}Projects${NC}"
    print_line
    FOUND=0
    for CONF in /etc/apache2/sites-available/*.conf; do
        [ -f "$CONF" ] || continue
        SITE=$(basename "$CONF" .conf)
        [ "$SITE" = "000-default" ] && continue
        ROOT=$(grep "DocumentRoot" "$CONF" | awk '{print $2}')
        FOUND=1
        if [ -d "$ROOT" ]; then
            echo -e "  ${BG}[OK]${NC}    $SITE  ${DG}→${NC}  $ROOT"
        else
            echo -e "  ${R}[WARN]${NC}  $SITE  ${DG}→${NC}  $ROOT ${R}(dir missing)${NC}"
        fi
    done
    [ "$FOUND" -eq 0 ] && echo -e "  ${DG}No projects found${NC}"
}

check_disk() {
    echo ""
    print_line
    echo -e "  ${C}Disk Usage${NC}"
    print_line
    DISK_PCT=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "$DISK_PCT" -ge 90 ]; then
        print_fail "Root disk: ${DISK_PCT}%"
    elif [ "$DISK_PCT" -ge 80 ]; then
        print_warn "Root disk: ${DISK_PCT}%"
    else
        print_ok "Root disk: ${DISK_PCT}%"
    fi
}

check_apache_errors() {
    echo ""
    print_line
    echo -e "  ${C}Recent Apache Errors${NC}"
    print_line
    ERR_LOG="/var/log/apache2/error.log"
    if [ -f "$ERR_LOG" ]; then
        COUNT=$(tail -100 "$ERR_LOG" 2>/dev/null | grep -c "error\|crit\|alert\|emerg" || echo "0")
        if [ "$COUNT" -gt 20 ]; then
            print_fail "$COUNT errors in last 100 lines"
            echo -e "  ${DG}── Last 5 ──${NC}"
            tail -100 "$ERR_LOG" | grep -i "error\|crit\|alert\|emerg" | tail -5 | while IFS= read -r LINE; do
                echo -e "  ${R}$LINE${NC}"
            done
        elif [ "$COUNT" -gt 0 ]; then
            print_warn "$COUNT errors in last 100 lines"
        else
            print_ok "No recent errors"
        fi
    else
        echo -e "  ${DG}Error log not found${NC}"
    fi
}

check_php_errors() {
    echo ""
    print_line
    echo -e "  ${C}PHP Errors${NC}"
    print_line
    PHP_LOG="/var/log/php${PHP_VERSION}-fpm.log"
    if [ -f "$PHP_LOG" ]; then
        COUNT=$(tail -50 "$PHP_LOG" 2>/dev/null | grep -c "error\|crit\|alert\|emerg" || echo "0")
        if [ "$COUNT" -gt 0 ]; then
            print_warn "$COUNT errors in PHP-FPM log"
        else
            print_ok "No recent PHP-FPM errors"
        fi
    else
        echo -e "  ${DG}PHP-FPM log not found${NC}"
    fi
}

check_mysql_errors() {
    echo ""
    print_line
    echo -e "  ${C}MySQL Errors${NC}"
    print_line
    MYSQL_LOG=$(ls /var/log/mysql/error.log 2>/dev/null || ls /var/log/mysql/error.err 2>/dev/null || echo "")
    if [ -n "$MYSQL_LOG" ]; then
        COUNT=$(tail -50 "$MYSQL_LOG" 2>/dev/null | grep -ic "error\|warning\|fatal" || echo "0")
        if [ "$COUNT" -gt 0 ]; then
            print_warn "$COUNT errors in MySQL log"
        else
            print_ok "No recent MySQL errors"
        fi
    else
        echo -e "  ${DG}MySQL error log not found${NC}"
    fi
}

check_ssl_expiry() {
    echo ""
    print_line
    echo -e "  ${C}SSL Certificates${NC}"
    print_line
    FOUND=0
    for CONF in /etc/apache2/sites-available/*.conf; do
        [ -f "$CONF" ] || continue
        SITE=$(basename "$CONF" .conf)
        [ "$SITE" = "000-default" ] && continue
        DOMAIN=$(grep "ServerName" "$CONF" | awk '{print $2}' | head -1)
        [ -z "$DOMAIN" ] || [ "$DOMAIN" = "_" ] && continue

        CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
        if [ -f "$CERT" ]; then
            EXPIRY=$(openssl x509 -enddate -noout -in "$CERT" 2>/dev/null | cut -d= -f2)
            EXPIRY_EPOCH=$(date -j -f "%b %d %T %Y %Z" "$EXPIRY" +%s 2>/dev/null || echo "0")
            NOW_EPOCH=$(date +%s)
            DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

            if [ "$DAYS_LEFT" -le 7 ]; then
                echo -e "  ${R}[EXPIRED/EXPIRING]${NC}  $DOMAIN  ${DG}→${NC}  $DAYS_LEFT days left"
            elif [ "$DAYS_LEFT" -le 30 ]; then
                echo -e "  ${Y}[WARNING]${NC}         $DOMAIN  ${DG}→${NC}  $DAYS_LEFT days left"
            else
                echo -e "  ${BG}[OK]${NC}              $DOMAIN  ${DG}→${NC}  $DAYS_LEFT days left"
            fi
            FOUND=1
        fi
    done
    [ "$FOUND" -eq 0 ] && echo -e "  ${DG}No SSL certificates found${NC}"
}

check_firewall() {
    echo ""
    print_line
    echo -e "  ${C}Firewall${NC}"
    print_line
    if command -v ufw >/dev/null; then
        STATUS=$(ufw status 2>/dev/null | head -1)
        if echo "$STATUS" | grep -q "active"; then
            print_ok "UFW active"
            RULES=$(ufw status numbered 2>/dev/null | grep "\[" | wc -l | tr -d ' ')
            echo -e "  ${DG}→${NC}  Rules: $RULES"
        else
            print_fail "UFW inactive"
        fi
    else
        echo -e "  ${DG}UFW not installed${NC}"
    fi
}

# Run based on mode
case "$MODE" in
    status)
        check_apache
        check_php
        check_mysql
        ;;
    full)
        check_apache
        check_php
        check_mysql
        check_projects
        check_disk
        check_apache_errors
        check_php_errors
        check_mysql_errors
        check_ssl_expiry
        check_firewall
        ;;
esac

echo ""
print_line
echo -e "  ${C}Diagnostics complete${NC}"
print_line
echo ""
