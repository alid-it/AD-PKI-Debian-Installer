#!/usr/bin/env bash
set -euo pipefail

. /usr/lib/adpki/setup/common.sh

require_root
setup_logging "00-welcome"
require_runtime_installed
load_install_env

HOSTNAME_FQDN="$(hostname -f 2>/dev/null || hostname)"
SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"

echo "Willkommen bei AD-PKI"
echo "====================="
echo
echo "Dieser Assistent führt dich durch die Erstkonfiguration deiner internen PKI."
echo
echo "Systeminformationen:"
echo
echo "Hostname:        ${HOSTNAME_FQDN}"
echo "Server-IP:       ${SERVER_IP:-unbekannt}"
echo "Install-Modus:"
echo "  Webserver:     ${ADPKI_WEB_SERVER:-unbekannt}"
echo "  Datenbank:     ${ADPKI_DB_MODE:-unbekannt}"
echo
echo "Installationspfade:"
echo "  Backend:       /opt/adpki/backend"
echo "  Frontend:      /opt/adpki/frontend"
echo "  CA-Core:       /opt/adpki/ca-core"
echo "  PKI-Daten:     /var/lib/adpki"
echo "  Logs:          /var/log/adpki"
echo

mark_step_done "00-welcome"

echo "Willkommen-Step OK."
