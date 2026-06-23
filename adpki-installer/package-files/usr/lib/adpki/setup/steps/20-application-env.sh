#!/usr/bin/env bash
set -euo pipefail

. /usr/lib/adpki/setup/common.sh

require_root
require_runtime_installed
setup_logging "20-application-env"
load_install_env
load_setup_env_if_exists

require_command openssl
require_command shuf
require_command php

# ---------------------------------------------------------------------------
# Secrets generieren – vor jeglichem Output damit sie nicht im Log landen
# ---------------------------------------------------------------------------

CA_TOKEN="$(openssl rand -hex 32)"
REVERB_APP_ID="$(shuf -i 100000-999999 -n 1)"
REVERB_APP_KEY="$(openssl rand -hex 32 | head -c 20)"
REVERB_APP_SECRET="$(openssl rand -hex 32 | head -c 32)"
APP_KEY="base64:$(php -r 'echo base64_encode(random_bytes(32));')"

# ---------------------------------------------------------------------------
# Öffentliche URL abfragen
# ---------------------------------------------------------------------------

echo "AD-PKI Anwendungskonfiguration"
echo "=============================="
echo

DEFAULT_HOST="$(hostname -f 2>/dev/null || hostname)"
DEFAULT_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"

PUBLIC_HOST="$(prompt_default "Öffentliche Domain oder IP" "${DEFAULT_HOST:-${DEFAULT_IP:-localhost}}")"

if [[ ! "$PUBLIC_HOST" =~ ^[a-zA-Z0-9]([a-zA-Z0-9._-]*[a-zA-Z0-9])?(:[0-9]{1,5})?$ ]] && \
   [[ ! "$PUBLIC_HOST" =~ ^\[[0-9a-fA-F:]+\](:[0-9]{1,5})?$ ]]; then
    echo
    echo "Fehler: Ungültige Eingabe: '${PUBLIC_HOST}'"
    echo
    echo "Erlaubt:"
    echo "  Hostname:      adpki.example.com"
    echo "  IPv4:          192.168.1.100"
    echo "  IPv4+Port:     192.168.1.100:8443"
    echo "  IPv6:          [::1]"
    echo "  IPv6+Port:     [::1]:8443"
    exit 1
fi

PUBLIC_SCHEME="https"
APP_URL="${PUBLIC_SCHEME}://${PUBLIC_HOST}"
CA_URL="http://127.0.0.1:8080"
BACKEND_URL="$APP_URL"

echo
echo "APP_URL: ${APP_URL}"
echo

# ---------------------------------------------------------------------------
# Backend ENV schreiben
# ---------------------------------------------------------------------------

echo "Schreibe Backend-Konfiguration..."

set_backend_env_value "APP_NAME"             "AD-PKI"
set_backend_env_value "APP_ENV"              "production"
set_backend_env_value "APP_DEBUG"            "false"
set_backend_env_value "APP_URL"              "$APP_URL"
set_backend_env_value "APP_KEY"              "$APP_KEY"

set_backend_env_value "CA_URL"               "$CA_URL"
set_backend_env_value "CA_TOKEN"             "$CA_TOKEN"

set_backend_env_value "MAIL_MAILER"          "smtp"

set_backend_env_value "REVERB_APP_ID"        "$REVERB_APP_ID"
set_backend_env_value "REVERB_APP_KEY"       "$REVERB_APP_KEY"
set_backend_env_value "REVERB_APP_SECRET"    "$REVERB_APP_SECRET"
set_backend_env_value "REVERB_HOST"          "127.0.0.1"
set_backend_env_value "REVERB_PORT"          "6001"
set_backend_env_value "REVERB_SCHEME"        "http"
set_backend_env_value "REVERB_SERVER_HOST"   "0.0.0.0"
set_backend_env_value "REVERB_SERVER_PORT"   "6001"
set_backend_env_value "REVERB_PUBLIC_HOST"   "$PUBLIC_HOST"
set_backend_env_value "REVERB_PUBLIC_PORT"   "443"
set_backend_env_value "REVERB_PUBLIC_SCHEME" "$PUBLIC_SCHEME"

set_backend_env_value "BROADCAST_CONNECTION" "reverb"
set_backend_env_value "QUEUE_CONNECTION"     "database"
set_backend_env_value "CACHE_STORE"          "database"
set_backend_env_value "SESSION_DRIVER"       "database"
set_backend_env_value "VITE_APP_NAME"        "AD-PKI"

echo "✅ Backend-Konfiguration geschrieben."

# ---------------------------------------------------------------------------
# CA-Core ENV schreiben
# ---------------------------------------------------------------------------

echo
echo "Schreibe CA-Core-Konfiguration..."

cat > "$ADPKI_CA_ENV" <<'EOF'
PKI_BASE_DIR=/var/lib/adpki
EOF

printf 'BACKEND_URL="%s"\n' "$BACKEND_URL" >> "$ADPKI_CA_ENV"
printf 'CA_TOKEN="%s"\n'    "$CA_TOKEN"    >> "$ADPKI_CA_ENV"

chown root:adpki "$ADPKI_CA_ENV"
chmod 640 "$ADPKI_CA_ENV"

echo "✅ CA-Core-Konfiguration geschrieben."

# ---------------------------------------------------------------------------
# Frontend Runtime-Konfiguration schreiben
# ---------------------------------------------------------------------------

echo
echo "Schreibe Frontend-Konfiguration..."

FRONTEND_CONFIG="/opt/adpki/frontend/dist/config.js"

install -d -o adpki -g www-data -m 750 /opt/adpki/frontend/dist

printf 'window.__ADPKI_CONFIG__ = {\n    apiBaseUrl: "%s/api",\n    defaultLocale: "en"\n};\n' \
    "$APP_URL" > "$FRONTEND_CONFIG"

chown adpki:www-data "$FRONTEND_CONFIG"
chmod 640 "$FRONTEND_CONFIG"

echo "✅ Frontend-Konfiguration geschrieben."

# ---------------------------------------------------------------------------
# Setup-State speichern
# ---------------------------------------------------------------------------

write_setup_env_value "ADPKI_APP_CONFIGURED" "true"
write_setup_env_value "ADPKI_PUBLIC_HOST"    "$PUBLIC_HOST"
write_setup_env_value "ADPKI_PUBLIC_SCHEME"  "$PUBLIC_SCHEME"
write_setup_env_value "ADPKI_APP_URL"        "$APP_URL"

# ---------------------------------------------------------------------------
# Dienste neu starten
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Symlink backend.env → .env sicherstellen
# ---------------------------------------------------------------------------

echo
echo "Stelle Backend .env Symlink sicher..."
ln -sf "$ADPKI_BACKEND_ENV" "${BACKEND_DIR}/.env"
echo "✅ Symlink gesetzt: ${BACKEND_DIR}/.env → ${ADPKI_BACKEND_ENV}"

# ---------------------------------------------------------------------------
# Laravel Cache leeren
# ---------------------------------------------------------------------------

echo
echo "Leere Laravel Cache..."
runuser -u www-data -- php "${BACKEND_DIR}/artisan" config:clear >/dev/null
echo "✅ Laravel Cache geleert."

# ---------------------------------------------------------------------------
# Dienste neu starten
# ---------------------------------------------------------------------------

echo
echo "Starte Dienste neu..."

systemctl restart adpki-ca
echo "✅ adpki-ca neugestartet."

systemctl restart php8.4-fpm
echo "✅ php8.4-fpm neugestartet."

systemctl reload nginx
echo "✅ nginx neu geladen."


mark_step_done "20-application-env"

echo
echo "=============================="
echo "Anwendungskonfiguration OK."
echo
echo "  APP_URL:  ${APP_URL}"
echo "  CA_URL:   ${CA_URL}"
echo "  APP_KEY:  (gesetzt)"
echo "  CA_TOKEN: (gesetzt)"
echo