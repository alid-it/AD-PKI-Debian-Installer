#!/usr/bin/env bash
set -euo pipefail

. /usr/lib/adpki/setup/common.sh

require_root
require_runtime_installed
setup_logging "60-import-intermediate"
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

if [ "${ADPKI_ROOT_IMPORTED:-false}" != "true" ]; then
    echo "Fehler: Root CA wurde noch nicht importiert (Step 50)."
    echo "  sudo adpki-setup"
    exit 1
fi

# CA_TOKEN aus backend.env laden
load_backend_env_if_exists

if [ -z "${CA_TOKEN:-}" ]; then
    echo "Fehler: CA_TOKEN fehlt in ${ADPKI_BACKEND_ENV}."
    exit 1
fi

echo "AD-PKI Intermediate CA Import"
echo "============================="
echo
echo "Bitte vollständige Pfade zur Intermediate-CA und zum Private Key angeben."
echo

INTERMEDIATE_CRT="$(prompt_existing_file "Intermediate CA Zertifikat (.crt/.pem)")"
INTERMEDIATE_KEY="$(prompt_existing_file "Intermediate CA Private Key (.key/.pem)")"

# Prüfe, ob der Private Key mit einer Passphrase verschlüsselt ist.
KEY_PASSPHRASE=""
if head -5 "$INTERMEDIATE_KEY" | grep -qE "ENCRYPTED|DEK-Info"; then
    echo
    echo "Der Private Key ist mit einer Passphrase verschlüsselt."
    read -rs -p "Passphrase eingeben: " KEY_PASSPHRASE 2>/dev/tty </dev/tty
    echo
    if [ -z "$KEY_PASSPHRASE" ]; then
        echo "Fehler: Passphrase darf nicht leer sein für einen verschlüsselten Key."
        exit 1
    fi
fi

RESPONSE_FILE="$(mktemp)"
trap 'rm -f "$RESPONSE_FILE"' EXIT

echo
echo "Importiere Intermediate CA..."

CURL_ARGS=(
    -sS -o "$RESPONSE_FILE" -w "%{http_code}"
    -X POST "http://127.0.0.1/api/internal/import-intermediate"
    -H "Accept: application/json"
    -H "X-CA-Token: ${CA_TOKEN}"
    -F "intermediate=@${INTERMEDIATE_CRT}"
    -F "key=@${INTERMEDIATE_KEY}"
)

if [ -n "$KEY_PASSPHRASE" ]; then
    CURL_ARGS+=(-F "passphrase=${KEY_PASSPHRASE}")
fi

HTTP_STATUS="$(curl "${CURL_ARGS[@]}")"

if [ "$HTTP_STATUS" -lt 200 ] || [ "$HTTP_STATUS" -ge 300 ]; then
    echo
    echo "Fehler: Intermediate CA Import fehlgeschlagen. HTTP Status: ${HTTP_STATUS}"
    cat "$RESPONSE_FILE" || true
    echo
    exit 1
fi

echo "✅ Intermediate CA wurde erfolgreich importiert."

write_setup_env_value "ADPKI_INTERMEDIATE_IMPORTED"   "true"
write_setup_env_value "ADPKI_INTERMEDIATE_CERT_PATH"  "$INTERMEDIATE_CRT"
write_setup_env_value "ADPKI_INTERMEDIATE_KEY_PATH"   "$INTERMEDIATE_KEY"

mark_step_done "60-import-intermediate"

echo
echo "Intermediate-Import-Step OK."