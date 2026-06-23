#!/usr/bin/env bash
set -euo pipefail

. /usr/lib/adpki/setup/common.sh

require_root
require_runtime_installed
setup_logging "80-webui-tls"
load_install_env
load_setup_env_if_exists

require_command curl
require_command nslookup
require_command ip

CERTBOT_DIR="/etc/letsencrypt/live"
WEB_CONF="/etc/nginx/sites-available/adpki.conf"
WEB_HTTPS_TEMPLATE="/etc/nginx/sites-available/adpki-https.conf"

if [ ! -f "$WEB_HTTPS_TEMPLATE" ]; then
    echo "Fehler: HTTPS-Template nicht gefunden: ${WEB_HTTPS_TEMPLATE}"
    exit 1
fi

# ---------------------------------------------------------------------------
# Domain und E-Mail abfragen
# ---------------------------------------------------------------------------

echo "AD-PKI WebUI TLS-Konfiguration"
echo "=============================="
echo

DEFAULT_DOMAIN="${ADPKI_PUBLIC_HOST:-$(hostname -f)}"

DOMAIN="$(prompt_default "Domain für TLS-Zertifikat" "$DEFAULT_DOMAIN")"
EMAIL="$(prompt_required "E-Mail für Certbot")"

# ---------------------------------------------------------------------------
# DNS-Server abfragen
# ---------------------------------------------------------------------------

echo
echo "DNS-Prüfung"
echo "==========="
echo
echo "Über welchen DNS-Server soll die Domain geprüft werden?"
echo "Beispiele: 8.8.8.8 (Google), 1.1.1.1 (Cloudflare), eigener DNS"
echo

DNS_SERVER="$(prompt_default "DNS-Server" "8.8.8.8")"

# ---------------------------------------------------------------------------
# DNS-Check
# ---------------------------------------------------------------------------

echo
echo "Löse ${DOMAIN} über ${DNS_SERVER} auf..."

RESOLVED_IP="$(nslookup "$DOMAIN" "$DNS_SERVER" 2>/dev/null \
    | awk '/^Address:/ && !/#/ {print $2}' \
    | head -n1 || true)"

if [ -z "$RESOLVED_IP" ]; then
    echo
    echo "⚠️  Warnung: Domain ${DOMAIN} konnte über ${DNS_SERVER} nicht aufgelöst werden."
    echo "   Certbot wird möglicherweise fehlschlagen."
    echo
else
    echo "Aufgelöste IP: ${RESOLVED_IP}"

    LOCAL_IPS="$(ip -4 addr show | awk '/inet / {print $2}' | cut -d/ -f1)"
    IP_MATCH=false

    while IFS= read -r local_ip; do
        if [ "$local_ip" = "$RESOLVED_IP" ]; then
            IP_MATCH=true
            break
        fi
    done <<< "$LOCAL_IPS"

    if [ "$IP_MATCH" = true ]; then
        echo "✅ IP stimmt überein – Domain zeigt auf diesen Server."
    else
        echo
        echo "⚠️  Warnung: ${DOMAIN} zeigt auf ${RESOLVED_IP}, aber dieser Server hat:"
        echo "$LOCAL_IPS" | sed 's/^/  /'
        echo
        echo "   Die Domain zeigt möglicherweise nicht auf diesen Server."
        echo "   Certbot wird möglicherweise fehlschlagen."
        echo
    fi
fi

echo

# ---------------------------------------------------------------------------
# Port 80 Check
# ---------------------------------------------------------------------------

echo "Prüfe ob Port 80 von außen erreichbar ist..."

HTTP_CHECK="$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 5 \
    "http://${DOMAIN}/" 2>/dev/null || true)"

if [ "$HTTP_CHECK" = "000" ]; then
    echo
    echo "Fehler: Port 80 ist nicht erreichbar für ${DOMAIN}."
    echo
    echo "Mögliche Ursachen:"
    echo "  - Firewall blockiert Port 80"
    echo "  - Domain zeigt nicht auf diesen Server"
    echo "  - Router-Portweiterleitung fehlt"
    echo
    echo "Bitte beheben und Setup erneut ausführen."
    exit 1
fi

echo "✅ Port 80 ist erreichbar (HTTP ${HTTP_CHECK})."
echo

# ---------------------------------------------------------------------------
# Certbot installieren
# ---------------------------------------------------------------------------

if ! command -v certbot >/dev/null 2>&1; then
    echo "Certbot nicht gefunden – installiere..."
    apt-get install -y certbot
    echo "✅ Certbot installiert."
else
    echo "✅ Certbot bereits installiert: $(certbot --version 2>&1)"
fi

echo

# ---------------------------------------------------------------------------
# Certbot ausführen – nginx kurz stoppen
# ---------------------------------------------------------------------------

echo "Fordere TLS-Zertifikat an..."
echo "  Domain:  ${DOMAIN}"
echo "  E-Mail:  ${EMAIL}"
echo "  CA:      http://127.0.0.1:8080/acme/directory"
echo
echo "nginx wird kurz gestoppt für die Challenge-Validierung..."

NGINX_STOPPED=false

cleanup_nginx() {
    if [ "$NGINX_STOPPED" = true ]; then
        echo
        echo "Starte nginx wieder..."
        systemctl start nginx || true
        NGINX_STOPPED=false
    fi
}

trap cleanup_nginx EXIT

systemctl stop nginx
NGINX_STOPPED=true

if ! certbot certonly \
    --standalone \
    --preferred-challenges http \
    --pre-hook "true" \
    --post-hook "systemctl start nginx" \
    --server "http://127.0.0.1:8080/acme/directory" \
    --domain "$DOMAIN" \
    --email "$EMAIL" \
    --agree-tos \
    --non-interactive \
    2>&1; then

    echo
    echo "Fehler: Certbot konnte kein Zertifikat ausstellen."
    echo
    echo "Mögliche Ursachen:"
    echo "  - Domain nicht erreichbar auf Port 80"
    echo "  - CA-Core nicht erreichbar"
    echo "  - DNS zeigt nicht auf diesen Server"
    echo
    echo "Logs prüfen:"
    echo "  /var/log/letsencrypt/letsencrypt.log"
    echo
    exit 1
fi

NGINX_STOPPED=false
trap - EXIT

echo "✅ TLS-Zertifikat erfolgreich ausgestellt."
echo

CERT_PATH="${CERTBOT_DIR}/${DOMAIN}/fullchain.pem"
KEY_PATH="${CERTBOT_DIR}/${DOMAIN}/privkey.pem"

# ---------------------------------------------------------------------------
# nginx Konfiguration aus Template schreiben
# ---------------------------------------------------------------------------

echo "Schreibe nginx HTTPS-Konfiguration aus Template..."

sed \
    -e "s|__DOMAIN__|${DOMAIN}|g" \
    -e "s|__CERT_PATH__|${CERT_PATH}|g" \
    -e "s|__KEY_PATH__|${KEY_PATH}|g" \
    "$WEB_HTTPS_TEMPLATE" \
    > "$WEB_CONF"

echo "✅ Konfiguration geschrieben: ${WEB_CONF}"

if nginx -t; then
    systemctl restart nginx
else
    echo "Fehler: nginx-Konfiguration ungültig."
    exit 1
fi
echo "✅ nginx auf HTTPS umgestellt."
echo

# ---------------------------------------------------------------------------
# Certbot renew Hooks einrichten
# ---------------------------------------------------------------------------

echo "Richte Certbot Auto-Renew Hooks ein..."

install -d -m 755 /etc/letsencrypt/renewal-hooks/pre
install -d -m 755 /etc/letsencrypt/renewal-hooks/post

cat > /etc/letsencrypt/renewal-hooks/pre/adpki-stop-nginx.sh <<'HOOK'
#!/usr/bin/env bash
systemctl stop nginx
HOOK
chmod 755 /etc/letsencrypt/renewal-hooks/pre/adpki-stop-nginx.sh

cat > /etc/letsencrypt/renewal-hooks/post/adpki-start-nginx.sh <<'HOOK'
#!/usr/bin/env bash
systemctl start nginx
HOOK
chmod 755 /etc/letsencrypt/renewal-hooks/post/adpki-start-nginx.sh

echo "✅ Renewal-Hooks gesetzt."
echo

# ---------------------------------------------------------------------------
# Certbot Timer aktivieren
# ---------------------------------------------------------------------------

echo "Aktiviere Certbot Auto-Renew Timer..."

if systemctl is-enabled certbot.timer >/dev/null 2>&1; then
    echo "✅ Certbot Timer bereits aktiv."
else
    systemctl enable certbot.timer >/dev/null 2>&1 || true
    systemctl start certbot.timer >/dev/null 2>&1 || true
    echo "✅ Certbot Timer aktiviert."
fi

echo

# ---------------------------------------------------------------------------
# APP_URL aktualisieren
# ---------------------------------------------------------------------------

echo "Aktualisiere APP_URL..."
set_backend_env_value "APP_URL" "https://${DOMAIN}"
runuser -u www-data -- php /opt/adpki/backend/artisan config:clear >/dev/null
echo "✅ APP_URL auf https://${DOMAIN} gesetzt."
echo

# ---------------------------------------------------------------------------
# Abschluss
# ---------------------------------------------------------------------------

write_setup_env_value "ADPKI_TLS_CONFIGURED" "true"
write_setup_env_value "ADPKI_TLS_DOMAIN"     "$DOMAIN"
write_setup_env_value "ADPKI_TLS_CERT_PATH"  "$CERT_PATH"
write_setup_env_value "ADPKI_TLS_KEY_PATH"   "$KEY_PATH"

mark_step_done "80-webui-tls"

echo "=============================="
echo "WebUI TLS-Konfiguration OK."
echo
echo "  Domain:     ${DOMAIN}"
echo "  Zertifikat: ${CERT_PATH}"
echo "  Key:        ${KEY_PATH}"
echo "  WebUI:      https://${DOMAIN}"
echo
echo "Auto-Renew läuft via certbot.timer."
echo