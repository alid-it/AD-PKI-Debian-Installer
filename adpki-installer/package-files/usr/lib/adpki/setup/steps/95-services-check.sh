#!/usr/bin/env bash
set -euo pipefail

echo
echo "AD-PKI Dienste aktivieren und starten"
echo "====================================="

systemctl daemon-reload

# ------------------------------------------------------------
# Vorhandene Dienste stoppen (sauberer Neustart)
# ------------------------------------------------------------

echo "Stoppe vorhandene AD-PKI Dienste..."

systemctl stop adpki-reverb.service 2>/dev/null || true
systemctl stop adpki-worker.service 2>/dev/null || true
systemctl stop adpki-ca.service 2>/dev/null || true

# ------------------------------------------------------------
# Basisdienste starten
# ------------------------------------------------------------

echo
echo "Aktiviere und starte PHP-FPM..."
systemctl enable --now php8.4-fpm.service

echo "Aktiviere und starte nginx..."
systemctl enable --now nginx.service

# ------------------------------------------------------------
# Warten bis nginx wirklich bereit ist
# ------------------------------------------------------------

echo
echo "Warte auf nginx HTTPS-Erreichbarkeit..."

NGINX_READY=false

for i in {1..30}; do
    if curl -kfsS https://127.0.0.1 >/dev/null 2>&1; then
        NGINX_READY=true
        break
    fi

    sleep 1
done

if [ "$NGINX_READY" != "true" ]; then
    echo
    echo "❌ nginx wurde nicht rechtzeitig bereit."
    exit 1
fi

echo "✅ nginx ist erreichbar."

# ------------------------------------------------------------
# AD-PKI Dienste starten
# ------------------------------------------------------------

for service in \
    adpki-ca.service \
    adpki-worker.service \
    adpki-reverb.service
do
    echo "Aktiviere und starte: $service"
    systemctl enable --now "$service"
done

echo "Aktiviere Scheduler Timer..."
systemctl enable --now adpki-scheduler.timer

# ------------------------------------------------------------
# Erreichbarkeit prüfen
# ------------------------------------------------------------

echo
echo "Erreichbarkeit prüfen..."

if curl -kfsS https://127.0.0.1 >/dev/null 2>&1; then
    echo "✅ WebUI über nginx erreichbar"
else
    echo "⚠️ WebUI über nginx nicht erreichbar"
fi

if curl -fsS http://127.0.0.1:8080/acme/directory >/dev/null 2>&1; then
    echo "✅ CA-Core lokal erreichbar"
else
    echo "❌ CA-Core lokal nicht erreichbar"
fi


echo
echo "Korrigiere Laravel-Log-Permissions..."

if [ -f /opt/adpki/backend/storage/logs/laravel.log ]; then
    chown www-data:www-data /opt/adpki/backend/storage/logs/laravel.log
    chmod 664 /opt/adpki/backend/storage/logs/laravel.log
    echo "✅ laravel.log Permissions korrigiert."
else
    echo "Hinweis: laravel.log noch nicht vorhanden — wird beim ersten Request angelegt."
fi

echo
echo "Führe initiale AD-PKI Setup-Jobs aus..."
runuser -u www-data -- php /opt/adpki/backend/artisan setup:install --no-interaction

# ------------------------------------------------------------
# Dienststatus anzeigen
# ------------------------------------------------------------

echo
echo "Dienststatus:"

systemctl --no-pager --full status nginx || true
systemctl --no-pager --full status php8.4-fpm.service || true
systemctl --no-pager --full status adpki-ca.service || true
systemctl --no-pager --full status adpki-worker.service || true
systemctl --no-pager --full status adpki-reverb.service || true
systemctl --no-pager --full status adpki-scheduler.timer || true

echo
echo "✅ AD-PKI Dienste wurden erfolgreich aktiviert und geprüft."