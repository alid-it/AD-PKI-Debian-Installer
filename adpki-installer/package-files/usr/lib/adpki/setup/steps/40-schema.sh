#!/usr/bin/env bash
set -euo pipefail

. /usr/lib/adpki/setup/common.sh

require_root
require_runtime_installed
setup_logging "40-schema"
load_install_env
load_setup_env_if_exists

require_command psql
require_command php

# ---------------------------------------------------------------------------
# Voraussetzungen prüfen
# ---------------------------------------------------------------------------

check_prerequisites() {
    if [ "${ADPKI_DB_CONFIGURED:-false}" != "true" ]; then
        echo "Fehler: Datenbank wurde noch nicht konfiguriert (Step 30)."
        echo "  sudo adpki-setup"
        exit 1
    fi

    if [ "${ADPKI_APP_CONFIGURED:-false}" != "true" ]; then
        echo "Fehler: Anwendungskonfiguration fehlt (Step 20)."
        echo "  sudo adpki-setup"
        exit 1
    fi

    load_backend_env_if_exists

    if [ -z "${APP_KEY:-}" ]; then
        echo "Fehler: APP_KEY fehlt in ${ADPKI_BACKEND_ENV}."
        exit 1
    fi

    if [ ! -f "${BACKEND_DIR}/artisan" ]; then
        echo "Fehler: Laravel artisan fehlt: ${BACKEND_DIR}/artisan"
        exit 1
    fi

    if [ ! -d "${BACKEND_DIR}/vendor" ]; then
        echo "Fehler: vendor-Verzeichnis fehlt: ${BACKEND_DIR}/vendor"
        exit 1
    fi

    if [ ! -d "${BACKEND_DIR}/database/migrations" ]; then
        echo "Fehler: Migrations-Verzeichnis fehlt: ${BACKEND_DIR}/database/migrations"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# DB-Verbindung testen
# ---------------------------------------------------------------------------

test_db_connection() {
    load_backend_env_if_exists

    echo "Teste Datenbankverbindung..."

    if ! PGPASSWORD="${DB_PASSWORD:-}" psql \
        -h "${DB_HOST:-127.0.0.1}" \
        -p "${DB_PORT:-5432}" \
        -U "${DB_USERNAME:-}" \
        -d "${DB_DATABASE:-}" \
        -v ON_ERROR_STOP=1 \
        -c "SELECT version();" >/dev/null 2>&1; then
        echo
        echo "Fehler: Datenbankverbindung fehlgeschlagen."
        echo
        echo "  Host:     ${DB_HOST:-}"
        echo "  Port:     ${DB_PORT:-}"
        echo "  Database: ${DB_DATABASE:-}"
        echo "  Username: ${DB_USERNAME:-}"
        echo
        echo "Bitte Step 30 erneut ausführen."
        exit 1
    fi

    echo "✅ Datenbankverbindung erfolgreich."
}

# ---------------------------------------------------------------------------
# Laravel Artisan ausführen als www-data
# ---------------------------------------------------------------------------

run_artisan() {
    local description="$1"
    shift

    echo
    echo "${description}"

    cd "$BACKEND_DIR"
    runuser -u www-data -- /usr/bin/php artisan "$@"
}

# ---------------------------------------------------------------------------
# Migrationen
# ---------------------------------------------------------------------------

run_migrations() {
    echo
    echo "Prüfe Migrationsstatus..."

    load_backend_env_if_exists

    local migrated_count
    migrated_count="$(
        PGPASSWORD="${DB_PASSWORD:-}" psql \
            -h "${DB_HOST:-127.0.0.1}" \
            -p "${DB_PORT:-5432}" \
            -U "${DB_USERNAME:-}" \
            -d "${DB_DATABASE:-}" \
            -tAc "SELECT count(*) FROM migrations;" 2>/dev/null || echo "0"
    )"

    if [ "$migrated_count" != "0" ]; then
        echo
        echo "Es wurden bereits ${migrated_count} Migration(en) ausgeführt."
        echo
        echo "  1) Abbrechen"
        echo "  2) Datenbank zurücksetzen und neu migrieren (migrate:fresh)"
        echo "  3) Nur fehlende Migrationen ausführen (migrate)"
        echo
        read -rp "Auswahl [1/2/3]: " choice </dev/tty

        case "$choice" in
            1)
                echo "Abgebrochen."
                exit 1
                ;;
            2)
                echo
                echo "ACHTUNG: Alle Tabellen werden gelöscht und neu erstellt."
                read -rp "Wirklich fortfahren? [y/N]: " confirm </dev/tty
                case "$confirm" in
                    y|Y|yes|YES)
                        run_artisan "Setze Datenbank zurück..." migrate:fresh --force
                        ;;
                    *)
                        echo "Abgebrochen."
                        exit 1
                        ;;
                esac
                ;;
            3)
                run_artisan "Führe fehlende Migrationen aus..." migrate --force
                ;;
            *)
                echo "Ungültige Auswahl."
                exit 1
                ;;
        esac
    else
        run_artisan "Führe Migrationen aus..." migrate --force
    fi

    echo
    echo "✅ Migrationen abgeschlossen."
}

# ---------------------------------------------------------------------------
# Seeders
# ---------------------------------------------------------------------------

run_seeders() {
    echo
    echo "Führe Seeders aus..."

    run_artisan "Cache leeren..." optimize:clear

    local seeders=(
        "PermissionSeeder"
        "RoleSeeder"
        "RolePermissionSeeder"
        "NotificationEventSeeder"
        "NotificationEventRecipientSeeder"
    )

    for seeder in "${seeders[@]}"; do
        local seeder_file="${BACKEND_DIR}/database/seeders/${seeder}.php"
        if [ -f "$seeder_file" ]; then
            run_artisan "Seeder: ${seeder}" db:seed --class="$seeder" --force
        else
            echo "Seeder nicht gefunden, überspringe: ${seeder}"
        fi
    done

    run_artisan "Cache neu aufbauen..." optimize:clear

    echo
    echo "✅ Seeders abgeschlossen."
}

# ---------------------------------------------------------------------------
# Initiale Settings setzen
# ---------------------------------------------------------------------------

set_initial_settings() {
    load_setup_env_if_exists
    load_backend_env_if_exists

    local app_url="${ADPKI_APP_URL:-}"

    if [ -z "$app_url" ]; then
        echo "Warnung: ADPKI_APP_URL nicht gesetzt – Settings werden übersprungen."
        return 0
    fi

    # Slash am Ende entfernen
    app_url="${app_url%/}"

    echo
    echo "Setze initiale Settings..."

    PGPASSWORD="${DB_PASSWORD:-}" psql \
        -h "${DB_HOST:-127.0.0.1}" \
        -p "${DB_PORT:-5432}" \
        -U "${DB_USERNAME:-}" \
        -d "${DB_DATABASE:-}" \
        -v ON_ERROR_STOP=1 \
        -c "
INSERT INTO settings (key, value, created_at, updated_at) VALUES
    ('base_url',      '${app_url}',                       NOW(), NOW()),
    ('crl_base_url',  '${app_url}/crl',                   NOW(), NOW()),
    ('ocsp_base_url', '${app_url}/ocsp',                  NOW(), NOW()),
    ('acme_url',      '${app_url}/acme/directory',        NOW(), NOW()),
    ('tsa_url',       '${app_url}/timestamp',             NOW(), NOW())
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();
        " >/dev/null

    echo "✅ Initiale Settings gesetzt."
}

# ---------------------------------------------------------------------------
# Laravel Scheduler einrichten
# ---------------------------------------------------------------------------

setup_scheduler() {
    echo
    echo "Richte Laravel Scheduler ein..."

    local cron_line="* * * * * cd ${BACKEND_DIR} && php artisan schedule:run >> /dev/null 2>&1"

    ( crontab -u www-data -l 2>/dev/null | grep -v "schedule:run" || true; echo "$cron_line" ) \
        | crontab -u www-data -

    echo "✅ Scheduler eingerichtet."
}

# ---------------------------------------------------------------------------
# Zusammenfassung
# ---------------------------------------------------------------------------

print_summary() {
    load_backend_env_if_exists

    echo
    echo "Datenbankzustand"
    echo "================"

    PGPASSWORD="${DB_PASSWORD:-}" psql \
        -h "${DB_HOST:-}" -p "${DB_PORT:-5432}" \
        -U "${DB_USERNAME:-}" -d "${DB_DATABASE:-}" \
        -tAc "SELECT 'Tabellen:    ' || count(*) FROM information_schema.tables
              WHERE table_schema='public' AND table_type='BASE TABLE';" 2>/dev/null || true

    PGPASSWORD="${DB_PASSWORD:-}" psql \
        -h "${DB_HOST:-}" -p "${DB_PORT:-5432}" \
        -U "${DB_USERNAME:-}" -d "${DB_DATABASE:-}" \
        -tAc "SELECT 'Migrationen: ' || count(*) FROM migrations;" 2>/dev/null || true

    PGPASSWORD="${DB_PASSWORD:-}" psql \
        -h "${DB_HOST:-}" -p "${DB_PORT:-5432}" \
        -U "${DB_USERNAME:-}" -d "${DB_DATABASE:-}" \
        -tAc "SELECT 'Rollen:      ' || count(*) FROM roles;" 2>/dev/null || true

    PGPASSWORD="${DB_PASSWORD:-}" psql \
        -h "${DB_HOST:-}" -p "${DB_PORT:-5432}" \
        -U "${DB_USERNAME:-}" -d "${DB_DATABASE:-}" \
        -tAc "SELECT 'Rechte:      ' || count(*) FROM permissions;" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo "AD-PKI Datenbankschema"
echo "======================"

check_prerequisites
test_db_connection

echo
echo "Prüfe Laravel-Konfiguration..."

cd "$BACKEND_DIR"
if runuser -u www-data -- php artisan about >/dev/null 2>&1; then
    echo "✅ Laravel Konfiguration OK."
else
    echo "Fehler: Laravel konnte nicht gestartet werden."
    echo "Bitte ${ADPKI_BACKEND_ENV} und Dateirechte prüfen."
    exit 1
fi

run_migrations
run_seeders
set_initial_settings
setup_scheduler
print_summary

write_setup_env_value "ADPKI_SCHEMA_INSTALLED" "true"
mark_step_done "40-schema"

echo
echo "Schema-Step OK."