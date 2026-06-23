#!/usr/bin/env bash
set -euo pipefail

. /usr/lib/adpki/installer/common.sh

require_root
load_env
detect_os
ensure_adpki_user
setup_logging "00-preflight"


echo "Installiere Preflight-Pakete..."

apt update

apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    iproute2 \
    jq

echo
echo "Prüfe Webserver-Portstatus..."

if command -v ss >/dev/null 2>&1; then
    PORT_OUTPUT="$(ss -ltnp 2>/dev/null | grep -E ':80|:443' || true)"

    if [ -n "$PORT_OUTPUT" ]; then
        echo
        echo "Aktuell belegte Webports:"
        echo "$PORT_OUTPUT"
        echo
    fi

    if echo "$PORT_OUTPUT" | grep -qi "apache2"; then
        echo "Warnung: Apache2 belegt Port 80/443."
        echo "Bitte Apache2 stoppen/deaktivieren bevor AD-PKI installiert wird."
        exit 1
    fi
fi
echo
echo "Prüfe NTP-Synchronisierung..."

UNSUPPORTED_NTP_SERVICES=(
    ntp.service
    ntpd.service
    openntpd.service
)

for svc in "${UNSUPPORTED_NTP_SERVICES[@]}"; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo "Nicht unterstützter NTP-Dienst aktiv: ${svc} — wird gestoppt und deaktiviert..."
        systemctl stop "$svc" 2>/dev/null || true
        systemctl disable "$svc" 2>/dev/null || true
    fi
done

if systemctl is-active --quiet chrony 2>/dev/null; then
    echo "✅ chrony ist bereits aktiv — wird als NTP-Dienst verwendet."
elif systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
    echo "✅ systemd-timesyncd ist bereits aktiv."
else
    echo "Kein unterstützter NTP-Dienst aktiv — installiere systemd-timesyncd..."
    apt-get install -y systemd-timesyncd
    systemctl unmask systemd-timesyncd.service >/dev/null 2>&1 || true
    systemctl enable --now systemd-timesyncd
    echo "✅ systemd-timesyncd installiert und aktiviert."
fi

echo "Preflight OK."