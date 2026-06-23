#!/usr/bin/env bash
set -euo pipefail

. /usr/lib/adpki/setup/common.sh

require_root
require_runtime_installed
setup_logging "50-import-root"
load_install_env
load_setup_env_if_exists

require_command curl

prompt_existing_file() {
    local label="$1"
    local file=""

    while true; do
        read -rp "${label}: " file 2>/dev/tty </dev/tty

        if [ -f "$file" ]; then
            printf '%s' "$file"
            return 0
        fi

        echo "Fehler: Datei nicht gefunden: ${file}" >/dev/tty
    done
}

if [ "${ADPKI_SCHEMA_INSTALLED:-false}" != "true" ]; then
    echo "Fehler: Datenbankschema wurde noch nicht installiert (Step 40)."
    echo "  sudo adpki-setup"
    exit 1
fi

load_backend_env_if_exists

if [ -z "${CA_TOKEN:-}" ]; then
    echo "Fehler: CA_TOKEN fehlt in ${ADPKI_BACKEND_ENV}."
    exit 1
fi

echo "AD-PKI Root CA Import"
echo "====================="
echo
echo "Bitte vollständigen Pfad zur Root-CA Zertifikatsdatei angeben."
echo "Beispiel: /home/ali/root.crt"
echo

ROOT_CRT="$(prompt_existing_file "Root CA Zertifikat (.crt/.pem)")"

RESPONSE_FILE="$(mktemp)"
trap 'rm -f "$RESPONSE_FILE"' EXIT

echo
echo "Importiere Root CA..."

HTTP_STATUS="$(
    curl -sS -o "$RESPONSE_FILE" -w "%{http_code}" \
        -X POST "http://127.0.0.1/api/internal/import-root" \
        -H "Accept: application/json" \
        -H "X-CA-Token: ${CA_TOKEN}" \
        -F "root=@${ROOT_CRT}"
)"

if [ "$HTTP_STATUS" -lt 200 ] || [ "$HTTP_STATUS" -ge 300 ]; then
    echo
    echo "Fehler: Root CA Import fehlgeschlagen. HTTP Status: ${HTTP_STATUS}"
    cat "$RESPONSE_FILE" || true
    echo
    exit 1
fi

echo "✅ Root CA wurde erfolgreich importiert."

write_setup_env_value "ADPKI_ROOT_IMPORTED"  "true"
write_setup_env_value "ADPKI_ROOT_CERT_PATH" "$ROOT_CRT"

mark_step_done "50-import-root"

echo
echo "Root-Import-Step OK."