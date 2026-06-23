#!/usr/bin/env bash
set -euo pipefail

. /usr/lib/adpki/setup/common.sh

require_root
require_runtime_installed
setup_logging "30-database"
load_install_env
load_setup_env_if_exists

require_command psql

# ---------------------------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------------------------

validate_pg_identifier() {
    local value="$1"
    local label="$2"
    if [[ ! "$value" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        echo "Fehler: ${label} enthält ungültige Zeichen."
        echo "Erlaubt: Buchstaben, Zahlen, Unterstrich. Muss mit Buchstabe/Unterstrich beginnen."
        exit 1
    fi
}

escape_sql_string() {
    local value="$1"
    value="${value//\'/\'\'}"
    printf '%s' "$value"
}


test_db_connection() {
    local host="$1"
    local port="$2"
    local database="$3"
    local username="$4"
    local password="$5"

    echo
    echo "Teste PostgreSQL-Verbindung..."

    if ! PGPASSWORD="$password" psql \
        -h "$host" -p "$port" -U "$username" -d "$database" \
        -v ON_ERROR_STOP=1 \
        -c "SELECT version();" >/dev/null 2>&1; then
        echo
        echo "Fehler: Verbindung zur PostgreSQL-Datenbank fehlgeschlagen."
        echo
        echo "  Host:     ${host}"
        echo "  Port:     ${port}"
        echo "  Database: ${database}"
        echo "  Username: ${username}"
        echo
        exit 1
    fi

    echo "✅ Verbindung erfolgreich."
    echo
    echo "Teste Schreibrechte..."

    if ! PGPASSWORD="$password" psql \
        -h "$host" -p "$port" -U "$username" -d "$database" \
        -v ON_ERROR_STOP=1 \
        -c "CREATE TABLE IF NOT EXISTS _adpki_permission_check (id integer);" \
        -c "DROP TABLE _adpki_permission_check;" >/dev/null 2>&1; then
        echo
        echo "Fehler: Benutzer hat keine ausreichenden Rechte (CREATE/DROP benötigt)."
        echo
        exit 1
    fi

    echo "✅ Schreibrechte vorhanden."
}

# ---------------------------------------------------------------------------
# Existing PostgreSQL
# ---------------------------------------------------------------------------

configure_existing_database() {
    echo
    echo "Vorhandenen PostgreSQL-Server konfigurieren"
    echo "==========================================="
    echo
    echo "Zugangsdaten zur bestehenden Datenbank eingeben."
    echo "Datenbank und Benutzer müssen bereits existieren."
    echo

    DB_HOST="$(prompt_default "DB_HOST" "127.0.0.1")"
    DB_PORT="$(prompt_default "DB_PORT" "5432")"
    DB_DATABASE="$(prompt_default "DB_DATABASE" "adpki")"
    DB_USERNAME="$(prompt_default "DB_USERNAME" "adpki_user")"
    DB_PASSWORD="$(prompt_secret_required "DB_PASSWORD")"

    validate_pg_identifier "$DB_DATABASE" "DB_DATABASE"
    validate_pg_identifier "$DB_USERNAME" "DB_USERNAME"

    test_db_connection "$DB_HOST" "$DB_PORT" "$DB_DATABASE" "$DB_USERNAME" "$DB_PASSWORD"
}

# ---------------------------------------------------------------------------
# Lokaler PostgreSQL
# ---------------------------------------------------------------------------

configure_local_database() {
    echo
    echo "Lokale PostgreSQL-Datenbank konfigurieren"
    echo "========================================="
    echo
    echo "Host/Port/Datenbank werden automatisch gesetzt:"
    echo "  DB_HOST=127.0.0.1"
    echo "  DB_PORT=5432"
    echo "  DB_DATABASE=adpki"
    echo

    DB_HOST="127.0.0.1"
    DB_PORT="5432"
    DB_DATABASE="adpki"
    DB_USERNAME="$(prompt_default "DB_USERNAME" "adpki_user")"
    DB_PASSWORD="$(prompt_secret_required "DB_PASSWORD")"

    validate_pg_identifier "$DB_DATABASE" "DB_DATABASE"
    validate_pg_identifier "$DB_USERNAME" "DB_USERNAME"

    if ! id postgres >/dev/null 2>&1; then
        echo "Fehler: Systembenutzer 'postgres' nicht gefunden. Ist PostgreSQL installiert?"
        exit 1
    fi

    if ! command -v runuser >/dev/null 2>&1; then
        echo "Fehler: 'runuser' nicht gefunden."
        exit 1
    fi

    if ! runuser -u postgres -- psql -tAc "SELECT 1;" >/dev/null 2>&1; then
        echo
        echo "Fehler: Lokaler PostgreSQL-Server nicht erreichbar."
        echo "  sudo systemctl start postgresql"
        echo
        exit 1
    fi

    local sql_pw
    sql_pw="$(escape_sql_string "$DB_PASSWORD")"
    sql_pw="${sql_pw//$'\r'/}"
    sql_pw="${sql_pw//$'\n'/}"


    local role_exists
    role_exists="$(runuser -u postgres -- psql -tAc \
        "SELECT 1 FROM pg_roles WHERE rolname='${DB_USERNAME}'" | xargs || true)"

    if [ "$role_exists" = "1" ]; then
        echo "Benutzer existiert bereits, aktualisiere Passwort: ${DB_USERNAME}"
        runuser -u postgres -- psql -v ON_ERROR_STOP=1 \
            -c "ALTER ROLE ${DB_USERNAME} WITH LOGIN PASSWORD '${sql_pw}';" >/dev/null
    else
        echo "Erstelle Benutzer: ${DB_USERNAME}"
        runuser -u postgres -- psql -v ON_ERROR_STOP=1 \
            -c "CREATE ROLE ${DB_USERNAME} WITH LOGIN PASSWORD '${sql_pw}';" >/dev/null
    fi

    local db_exists
    db_exists="$(runuser -u postgres -- psql -tAc \
        "SELECT 1 FROM pg_database WHERE datname='${DB_DATABASE}'" | xargs || true)"

    if [ "$db_exists" = "1" ]; then
        echo "Datenbank existiert bereits: ${DB_DATABASE}"
    else
        echo "Erstelle Datenbank: ${DB_DATABASE}"
        runuser -u postgres -- createdb -O "$DB_USERNAME" "$DB_DATABASE"
    fi

    runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d "$DB_DATABASE" \
        -c "ALTER DATABASE ${DB_DATABASE} OWNER TO ${DB_USERNAME};" \
        -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_DATABASE} TO ${DB_USERNAME};" >/dev/null

    echo "✅ Lokale Datenbank vorbereitet."

    test_db_connection "$DB_HOST" "$DB_PORT" "$DB_DATABASE" "$DB_USERNAME" "$DB_PASSWORD"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo "AD-PKI Datenbankverbindung"
echo "=========================="
echo
echo "Modus: ${ADPKI_DB_MODE_LABEL:-${ADPKI_DB_MODE:-nicht gesetzt}}"

case "${ADPKI_DB_MODE:-}" in
    existing) configure_existing_database ;;
    local)    configure_local_database    ;;
    *)
        echo "Fehler: Ungültiger ADPKI_DB_MODE: '${ADPKI_DB_MODE:-nicht gesetzt}'"
        echo "Erlaubt: existing, local"
        exit 1
        ;;
esac

echo
echo "Speichere Datenbankkonfiguration..."

set_backend_env_value "DB_CONNECTION" "pgsql"
set_backend_env_value "DB_HOST"       "$DB_HOST"
set_backend_env_value "DB_PORT"       "$DB_PORT"
set_backend_env_value "DB_DATABASE"   "$DB_DATABASE"
set_backend_env_value "DB_USERNAME"   "$DB_USERNAME"
set_backend_env_value "DB_PASSWORD"   "$DB_PASSWORD"

write_setup_env_value "ADPKI_DB_CONFIGURED" "true"
write_setup_env_value "ADPKI_DB_MODE"       "${ADPKI_DB_MODE:-}"
write_setup_env_value "ADPKI_DB_MODE_LABEL" "${ADPKI_DB_MODE_LABEL:-}"
write_setup_env_value "ADPKI_DB_HOST"       "$DB_HOST"
write_setup_env_value "ADPKI_DB_PORT"       "$DB_PORT"
write_setup_env_value "ADPKI_DB_DATABASE"   "$DB_DATABASE"
write_setup_env_value "ADPKI_DB_USERNAME"   "$DB_USERNAME"

mark_step_done "30-database"

echo
echo "Datenbankverbindung OK."
echo
echo "  DB_HOST:     ${DB_HOST}"
echo "  DB_PORT:     ${DB_PORT}"
echo "  DB_DATABASE: ${DB_DATABASE}"
echo "  DB_USERNAME: ${DB_USERNAME}"
echo "  DB_PASSWORD: ********"
echo
