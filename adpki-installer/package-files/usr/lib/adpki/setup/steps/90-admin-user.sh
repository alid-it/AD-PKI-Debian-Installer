#!/usr/bin/env bash
set -euo pipefail

. /usr/lib/adpki/setup/common.sh

require_root
require_runtime_installed
setup_logging "90-admin-user"
load_install_env
load_setup_env_if_exists

require_command curl
require_command jq

# ---------------------------------------------------------------------------
# Voraussetzungen
# ---------------------------------------------------------------------------

if [ "${ADPKI_SCHEMA_INSTALLED:-false}" != "true" ]; then
    echo "Fehler: Datenbankschema wurde noch nicht installiert (Step 40)."
    exit 1
fi

load_backend_env_if_exists

if [ -z "${CA_TOKEN:-}" ]; then
    echo "Fehler: CA_TOKEN fehlt in ${ADPKI_BACKEND_ENV}."
    exit 1
fi

# ---------------------------------------------------------------------------
# Interne API-URL bestimmen
# ---------------------------------------------------------------------------

if [ "${ADPKI_TLS_CONFIGURED:-false}" = "true" ] && [ -n "${ADPKI_TLS_DOMAIN:-}" ]; then
    INTERNAL_API_URL="https://${ADPKI_TLS_DOMAIN}"
else
    INTERNAL_API_URL="http://127.0.0.1"
fi

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo "AD-PKI Admin-Account"
echo "===================="
echo
echo "Lege den ersten Administrator-Account an."
echo "Dieser Account hat vollen Zugriff auf AD-PKI."
echo

ADMIN_USERNAME="$(prompt_default "Benutzername" "admin")"
ADMIN_FIRSTNAME="$(prompt_required "Vorname")"
ADMIN_LASTNAME="$(prompt_required "Nachname")"
ADMIN_EMAIL="$(prompt_required "E-Mail")"

# ---------------------------------------------------------------------------
# Admin-Sprache
# ---------------------------------------------------------------------------

echo
echo "Sprache des Admin-Accounts auswählen:"
echo "1) Deutsch"
echo "2) English"
echo "3) Español"
echo "4) Français"
echo "5) Italiano"
echo "6) Türkçe"
echo

ADMIN_LOCALE_CHOICE="$(prompt_default "Auswahl" "1")"

case "${ADMIN_LOCALE_CHOICE}" in
    1|"") ADMIN_LOCALE="de" ;;
    2) ADMIN_LOCALE="en" ;;
    3) ADMIN_LOCALE="es" ;;
    4) ADMIN_LOCALE="fr" ;;
    5) ADMIN_LOCALE="it" ;;
    6) ADMIN_LOCALE="tr" ;;
    de|DE) ADMIN_LOCALE="de" ;;
    en|EN) ADMIN_LOCALE="en" ;;
    es|ES) ADMIN_LOCALE="es" ;;
    fr|FR) ADMIN_LOCALE="fr" ;;
    it|IT) ADMIN_LOCALE="it" ;;
    tr|TR) ADMIN_LOCALE="tr" ;;
    *)
        echo "Ungültige Auswahl. Verwende Deutsch (de)."
        ADMIN_LOCALE="de"
        ;;
esac

echo "Gewählte Sprache: ${ADMIN_LOCALE}"

# ---------------------------------------------------------------------------
# Passwort
# ---------------------------------------------------------------------------

ADMIN_PASSWORD=""
ADMIN_PASSWORD_CONFIRM=""

while true; do
    ADMIN_PASSWORD="$(prompt_secret_required "Passwort (min. 8 Zeichen)")"

    if [ "${#ADMIN_PASSWORD}" -lt 8 ]; then
        echo "Fehler: Passwort muss mindestens 8 Zeichen haben." >/dev/tty
        continue
    fi

    ADMIN_PASSWORD_CONFIRM="$(prompt_secret_required "Passwort bestätigen")"

    if [ "$ADMIN_PASSWORD" = "$ADMIN_PASSWORD_CONFIRM" ]; then
        break
    fi

    echo "Fehler: Passwörter stimmen nicht überein." >/dev/tty
done

# ---------------------------------------------------------------------------
# API-Call
# ---------------------------------------------------------------------------

echo
echo "Erstelle Admin-Account..."

RESPONSE_FILE="$(mktemp)"
trap 'rm -f "$RESPONSE_FILE"' EXIT

HTTP_STATUS="$(
    jq -n \
        --arg username  "$ADMIN_USERNAME" \
        --arg firstname "$ADMIN_FIRSTNAME" \
        --arg lastname  "$ADMIN_LASTNAME" \
        --arg email     "$ADMIN_EMAIL" \
        --arg password  "$ADMIN_PASSWORD" \
        --arg locale    "$ADMIN_LOCALE" \
        '{
            username: $username,
            firstname: $firstname,
            lastname: $lastname,
            email: $email,
            password: $password,
            locale: $locale
        }' \
    | curl -sS \
        -o "$RESPONSE_FILE" \
        -w "%{http_code}" \
        -X POST "${INTERNAL_API_URL}/api/internal/setup/create-admin" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -H "X-CA-Token: ${CA_TOKEN}" \
        --data-binary @-
)"

RESPONSE_BODY="$(cat "$RESPONSE_FILE")"

if [ "$HTTP_STATUS" = "200" ]; then
    echo "✅ Admin-Account existiert bereits – übersprungen."

elif [ "$HTTP_STATUS" = "201" ]; then
    echo "✅ Admin-Account erfolgreich angelegt."
    echo
    echo "  Benutzername: ${ADMIN_USERNAME}"
    echo "  E-Mail:       ${ADMIN_EMAIL}"
    echo "  Sprache:      ${ADMIN_LOCALE}"
    echo "  Rolle:        SuperAdmin"

else
    echo
    echo "Fehler: Admin-Account konnte nicht angelegt werden. HTTP ${HTTP_STATUS}"
    echo "$RESPONSE_BODY"
    echo
    exit 1
fi

# ---------------------------------------------------------------------------
# Abschluss
# ---------------------------------------------------------------------------

write_setup_env_value "ADPKI_ADMIN_CREATED" "true"
write_setup_env_value "ADPKI_ADMIN_LOCALE" "$ADMIN_LOCALE"
mark_step_done "90-admin-user"

echo
echo "Admin-User-Step OK."