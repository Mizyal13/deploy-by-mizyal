#!/bin/bash

set -Eeuo pipefail

VERSION="2.0"
MODE="${1:---status}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}[OK]${NC}    $1"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC}  $1"; }
fail() { echo -e "  ${RED}[FAIL]${NC}  $1"; }
info() { echo -e "  [INFO]   $1"; }

section() {
    echo ""
    echo -e "${BLUE}--- $1 ---${NC}"
    echo ""
}

if [ "$EUID" -ne 0 ]; then
    echo "Run as root"
    exit 1
fi

clear
echo "=========================================="
echo "  DEPLOY BY MIZYAL - Diagnostics v$VERSION"
echo "=========================================="

IP=$(hostname -I | awk '{print $1}')
info "Server IP : $IP"
info "Date      : $(date)"
info "Mode      : $MODE"

# --- services ---

section "Services Status"

if systemctl is-active --quiet apache2 2>/dev/null; then ok "Apache2"; else fail "Apache2 is down"; fi
if systemctl is-active --quiet mysql 2>/dev/null; then ok "MySQL"; else fail "MySQL is down"; fi

PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "")
if [ -n "$PHP_VER" ] && systemctl is-active --quiet "php${PHP_VER}-fpm" 2>/dev/null; then
    ok "PHP ${PHP_VER}-FPM"
elif [ -n "$PHP_VER" ]; then
    fail "PHP ${PHP_VER}-FPM is down"
else
    fail "PHP not installed"
fi

if systemctl is-active --quiet fail2ban 2>/dev/null; then ok "fail2ban"; else warn "fail2ban is down"; fi
if systemctl is-active --quiet cron 2>/dev/null; then ok "Cron"; else warn "Cron is down"; fi
if ufw status | grep -q "active"; then ok "UFW firewall"; else warn "UFW is inactive"; fi

# --- projects ---

section "Projects"

if [ -d "/var/www" ]; then
    PROJECTS=$(ls -1 /var/www 2>/dev/null || true)
    if [ -n "$PROJECTS" ]; then
        printf "  %-25s %-12s %s\n" "NAME" "FRAMEWORK" "STATUS"
        printf "  %-25s %-12s %s\n" "----" "---------" "------"

        while IFS= read -r P; do
            FW="Unknown"
            ST="Unknown"

            [ -f "/var/www/$P/artisan" ] && FW="Laravel"
            [ -f "/var/www/$P/composer.json" ] && FW="Composer"
            [ "$FW" = "Unknown" ] && FW="PHP Native"

            if [ -f "/etc/apache2/sites-available/$P.conf" ]; then
                if a2query -s -d "$P" 2>/dev/null | grep -q "enabled"; then
                    ST="${GREEN}Active${NC}"
                else
                    ST="${YELLOW}Disabled${NC}"
                fi
            else
                ST="${RED}No Config${NC}"
            fi

            printf "  %-25s %-12s %b\n" "$P" "$FW" "$ST"
        done <<< "$PROJECTS"
    else
        warn "No projects in /var/www"
    fi
else
    warn "/var/www does not exist"
fi

# --- disk ---

section "Disk Usage"

df -h / | tail -1 | awk '{printf "  Total: %s | Used: %s (%s) | Free: %s\n", $2, $3, $5, $4}'

if [ -d "/var/www" ]; then
    echo ""
    echo "  Project sizes:"
    du -sh /var/www/* 2>/dev/null | sort -rh | head -10 | while read -r SIZE DIR; do
        printf "    %-25s %s\n" "$(basename "$DIR")" "$SIZE"
    done
fi

# --- full mode ---

if [ "$MODE" = "--full" ]; then

    # apache errors

    section "Apache Errors"

    if apache2ctl configtest 2>&1 | grep -q "Syntax OK"; then
        ok "Config syntax OK"
    else
        fail "Config syntax error"
        apache2ctl configtest 2>&1 | head -5
    fi

    if [ -f "/var/log/apache2/error.log" ]; then
        ERRORS=$(tail -100 /var/log/apache2/error.log 2>/dev/null | grep -c "\[error\]" || echo "0")
        if [ "$ERRORS" -gt 0 ]; then
            warn "$ERRORS errors in last 100 lines"
            echo ""
            tail -5 /var/log/apache2/error.log
        else
            ok "Error log clean"
        fi
    fi

    # php errors

    section "PHP"

    if [ -n "$PHP_VER" ]; then
        if systemctl is-active --quiet "php${PHP_VER}-fpm" 2>/dev/null; then
            ok "PHP ${PHP_VER}-FPM running"
        else
            fail "PHP ${PHP_VER}-FPM down"
        fi

        PHP_LOG="/var/log/php${PHP_VER}-fpm.log"
        if [ -f "$PHP_LOG" ]; then
            PHP_ERR=$(tail -50 "$PHP_LOG" 2>/dev/null | grep -c -i "error\|fatal\|warning" || echo "0")
            if [ "$PHP_ERR" -gt 0 ]; then
                warn "$PHP_ERR issues in PHP log"
                tail -5 "$PHP_LOG"
            else
                ok "PHP log clean"
            fi
        fi

        echo ""
        echo "  PHP Config:"
        echo "    Memory Limit  : $(php -r 'echo ini_get("memory_limit");' 2>/dev/null || echo "?")"
        echo "    Upload Max    : $(php -r 'echo ini_get("upload_max_filesize");' 2>/dev/null || echo "?")"
        echo "    Post Max      : $(php -r 'echo ini_get("post_max_size");' 2>/dev/null || echo "?")"
        echo "    Exec Time     : $(php -r 'echo ini_get("max_execution_time");' 2>/dev/null || echo "?")s"
    fi

    # mysql

    section "MySQL"

    if systemctl is-active --quiet mysql 2>/dev/null; then
        ok "MySQL running"
        echo ""
        echo "  Databases:"
        mysql -u root -N -e "SELECT table_schema, ROUND(SUM(data_length+index_length)/1024/1024,2) FROM information_schema.tables GROUP BY table_schema;" 2>/dev/null | while read -r DB SIZE; do
            printf "    %-25s %s MB\n" "$DB" "$SIZE"
        done
        echo ""
        CONN=$(mysql -u root -N -e "SELECT COUNT(*) FROM information_schema.processlist;" 2>/dev/null || echo "?")
        info "Active connections: $CONN"
    else
        fail "MySQL is down"
    fi

    # ssl

    section "SSL Certificates"

    if command -v certbot >/dev/null 2>/dev/null; then
        CERTS=$(certbot certificates 2>/dev/null | grep "Domains:" | awk '{print $2}' || true)
        if [ -n "$CERTS" ]; then
            for DOM in $CERTS; do
                EXPIRY=$(echo | openssl s_client -servername "$DOM" -connect "$DOM":443 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || echo "")
                if [ -n "$EXPIRY" ]; then
                    EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || echo 0)
                    NOW=$(date +%s)
                    DAYS=$(( (EPOCH - NOW) / 86400 ))
                    if [ "$DAYS" -lt 0 ]; then
                        fail "$DOM: EXPIRED"
                    elif [ "$DAYS" -lt 30 ]; then
                        warn "$DOM: expires in $DAYS days"
                    else
                        ok "$DOM: expires in $DAYS days"
                    fi
                else
                    warn "$DOM: cannot check"
                fi
            done
        else
            info "No certificates found"
        fi
    else
        info "Certbot not installed"
    fi

    # firewall

    section "Firewall"

    if ufw status | grep -q "active"; then
        ok "UFW active"
        echo ""
        ufw status numbered 2>/dev/null | grep "\[" | while read -r LINE; do
            echo "    $LINE"
        done
    else
        warn "UFW inactive"
    fi

fi

# --- summary ---

ISSUES=0
systemctl is-active --quiet apache2 2>/dev/null || ISSUES=$((ISSUES + 1))
systemctl is-active --quiet mysql 2>/dev/null || ISSUES=$((ISSUES + 1))
[ -n "$PHP_VER" ] && ! systemctl is-active --quiet "php${PHP_VER}-fpm" 2>/dev/null && ISSUES=$((ISSUES + 1))

echo ""
echo "=========================================="
if [ "$ISSUES" -eq 0 ]; then
    echo -e "  ${GREEN}All services OK. Server is healthy.${NC}"
else
    echo -e "  ${RED}Found $ISSUES issue(s).${NC}"
fi
echo "=========================================="
echo ""
