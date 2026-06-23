#!/usr/bin/env bash
set -euo pipefail

. /usr/lib/adpki/setup/common.sh

require_root
setup_logging "10-system-check"
load_install_env

ERRORS=0
WARNINGS=0

ok() {
    echo "✅ $1"
}

warn() {
    echo "⚠️  $1"
    WARNINGS=$((WARNINGS + 1))
}

fail() {
    echo "❌ $1"
    ERRORS=$((ERRORS + 1))
}

echo "AD-PKI Systemprüfung"
echo "===================="
echo

# ------------------------------------------------------------
# Basisbefehle
# ------------------------------------------------------------
if command -v php >/dev/null 2>&1; then
    ok "PHP vorhanden: $(php -r 'echo PHP_VERSION;' 2>/dev/null || php -v | head -n1)"
else
    fail "PHP fehlt"
fi

if command -v openssl >/dev/null 2>&1; then
    ok "OpenSSL vorhanden: $(openssl version | head -n1)"
else
    fail "OpenSSL fehlt"
fi

if command -v psql >/dev/null 2>&1; then
    ok "PostgreSQL Client vorhanden: $(psql --version)"
else
    fail "PostgreSQL Client fehlt"
fi

if command -v node >/dev/null 2>&1; then
    ok "Node.js vorhanden: $(node -v)"
else
    warn "Node.js nicht gefunden"
fi

if command -v go >/dev/null 2>&1; then
    ok "Go vorhanden: $(go version)"
else
    warn "Go nicht gefunden"
fi

echo

# ------------------------------------------------------------
# AD-PKI Verzeichnisse
# ------------------------------------------------------------
for dir in \
    /opt/adpki \
    /opt/adpki/backend \
    /opt/adpki/frontend \
    /opt/adpki/ca-core \
    /var/lib/adpki \
    /var/lib/adpki/root \
    /var/lib/adpki/intermediates \
    /var/lib/adpki/issued \
    /var/lib/adpki/private \
    /var/lib/adpki/crl \
    /var/lib/adpki/csrs \
    /var/lib/adpki/setup \
    /var/log/adpki
do
    if [ -d "$dir" ]; then
        ok "Verzeichnis vorhanden: ${dir}"
    else
        fail "Verzeichnis fehlt: ${dir}"
    fi
done

echo

# ------------------------------------------------------------
# Schreibrechte
# ------------------------------------------------------------
if id adpki >/dev/null 2>&1; then
    ok "Systembenutzer vorhanden: adpki"
else
    fail "Systembenutzer fehlt: adpki"
fi

if sudo -u adpki test -w /var/lib/adpki 2>/dev/null; then
    ok "/var/lib/adpki ist für adpki beschreibbar"
else
    fail "/var/lib/adpki ist für adpki nicht beschreibbar"
fi

if sudo -u adpki test -w /var/log/adpki 2>/dev/null; then
    ok "/var/log/adpki ist für adpki beschreibbar"
else
    warn "/var/log/adpki ist für adpki nicht direkt beschreibbar"
fi

echo

# ------------------------------------------------------------
# App Payload
# ------------------------------------------------------------
if [ -f /opt/adpki/backend/artisan ]; then
    ok "Laravel Backend gefunden: /opt/adpki/backend/artisan"
else
    fail "Laravel Backend fehlt: /opt/adpki/backend/artisan"
fi

if [ -d /opt/adpki/frontend/dist ]; then
    ok "Frontend Build gefunden: /opt/adpki/frontend/dist"
else
    warn "Frontend Build fehlt: /opt/adpki/frontend/dist"
fi

if [ -x /opt/adpki/ca-core/adpki-ca ]; then
    ok "CA-Core Binary gefunden: /opt/adpki/ca-core/adpki-ca"
else
    fail "CA-Core Binary fehlt: /opt/adpki/ca-core/adpki-ca"
fi

echo

# ------------------------------------------------------------
# Webserver
# ------------------------------------------------------------
case "${ADPKI_WEB_SERVER:-}" in
    nginx)
        if command -v nginx >/dev/null 2>&1; then
            if nginx -t >/dev/null 2>&1; then
                ok "Nginx Konfiguration gültig"
            else
                fail "Nginx Konfiguration fehlerhaft"
            fi
        else
            fail "Nginx wurde gewählt, ist aber nicht installiert"
        fi
        ;;
    apache)
        if command -v apache2 >/dev/null 2>&1; then
            if apache2ctl configtest >/dev/null 2>&1; then
                ok "Apache2 Konfiguration gültig"
            else
                fail "Apache2 Konfiguration fehlerhaft"
            fi
        else
            fail "Apache2 wurde gewählt, ist aber nicht installiert"
        fi
        ;;
    *)
        warn "Kein bekannter Webserver-Modus in /etc/adpki/install.env"
        ;;
esac

echo

# ------------------------------------------------------------
# Ergebnis
# ------------------------------------------------------------
echo "Systemprüfung Ergebnis"
echo "======================"
echo "Fehler:    ${ERRORS}"
echo "Warnungen: ${WARNINGS}"
echo

if [ "$ERRORS" -gt 0 ]; then
    echo "Systemprüfung fehlgeschlagen."
    echo
    echo "Blockierende Fehler müssen behoben werden, bevor das Setup weiterlaufen kann."
    exit 1
fi

mark_step_done "10-system-check"

echo "Systemprüfung OK."
