#!/usr/bin/env bash
set -euo pipefail

. /usr/lib/adpki/installer/common.sh

require_root
load_env
detect_os
setup_logging "20-postgresql"


# Abwärtskompatibilität, falls alte install.env noch "external" enthält
if [ "${ADPKI_DB_MODE}" = "external" ]; then
    ADPKI_DB_MODE="existing"
    write_env
fi

echo "Richte offizielles PostgreSQL PGDG Repository ein..."

apt-get install -y curl ca-certificates gnupg

install -d -m 0755 /usr/share/keyrings

curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    | gpg --dearmor \
    > /usr/share/keyrings/postgresql-pgdg.gpg

cat > /etc/apt/sources.list.d/pgdg.sources <<EOF_PGDG
Types: deb
URIs: https://apt.postgresql.org/pub/repos/apt
Suites: ${OS_CODENAME}-pgdg
Components: main
Signed-By: /usr/share/keyrings/postgresql-pgdg.gpg
EOF_PGDG

apt-get update

echo
echo "Installiere PostgreSQL Client ${POSTGRES_VERSION_POLICY_LABEL}..."

apt-get install -y "postgresql-client-${POSTGRES_MAJOR}"

PSQL_TEXT="$(psql --version || true)"
PSQL_VERSION="$(echo "$PSQL_TEXT" | grep -oE '[0-9]+\.[0-9]+' | head -n1 || true)"

if [ -z "$PSQL_VERSION" ]; then
    echo "Fehler: PostgreSQL Client-Version konnte nicht erkannt werden."
    echo "Gefunden: ${PSQL_TEXT}"
    exit 1
fi

case "$PSQL_VERSION" in
    17.*)
        ;;
    *)
        echo "Fehler: PostgreSQL Client Major-Version passt nicht."
        echo "Erwartet: PostgreSQL 17.x"
        echo "Gefunden:  ${PSQL_VERSION}"
        exit 1
        ;;
esac

if ! dpkg --compare-versions "$PSQL_VERSION" ge "$POSTGRES_MIN_VERSION"; then
    echo "Fehler: PostgreSQL Client-Version ist zu alt."
    echo "Erwartet mindestens: ${POSTGRES_MIN_VERSION}"
    echo "Gefunden:            ${PSQL_VERSION}"
    exit 1
fi

echo "$PSQL_TEXT"

if [ -f "$ADPKI_ENV" ]; then
    sed -i '/^ADPKI_POSTGRES_INSTALLED_VERSION=/d' "$ADPKI_ENV"
    echo "ADPKI_POSTGRES_INSTALLED_VERSION=${PSQL_VERSION}" >> "$ADPKI_ENV"
fi

case "${ADPKI_DB_MODE}" in
    existing)
        echo
        echo "Vorhandener PostgreSQL-Server gewählt."
        echo "Es wird kein lokaler PostgreSQL Server installiert."
        echo "Die DB-Verbindungsdaten werden später über adpki-setup eingerichtet."
        ;;

    local)
        echo
        echo "Installiere neuen lokalen PostgreSQL-Server ${POSTGRES_VERSION_POLICY_LABEL}..."

        apt-get install -y "postgresql-${POSTGRES_MAJOR}" "postgresql-client-${POSTGRES_MAJOR}"

        service_enable_start postgresql

        if has_systemd && id postgres >/dev/null 2>&1; then
            PG_SERVER_VERSION="$(runuser -u postgres -- psql -tAc 'SHOW server_version;' | xargs || true)"
            PG_SERVER_SHORT="$(echo "$PG_SERVER_VERSION" | grep -oE '^[0-9]+\.[0-9]+' || true)"

            if [ -n "$PG_SERVER_SHORT" ]; then
                case "$PG_SERVER_SHORT" in
                    17.*)
                        ;;
                    *)
                        echo "Fehler: PostgreSQL Server Major-Version passt nicht."
                        echo "Erwartet: PostgreSQL 17.x"
                        echo "Gefunden:  ${PG_SERVER_VERSION}"
                        exit 1
                        ;;
                esac

                if ! dpkg --compare-versions "$PG_SERVER_SHORT" ge "$POSTGRES_MIN_VERSION"; then
                    echo "Fehler: PostgreSQL Server-Version ist zu alt."
                    echo "Erwartet mindestens: ${POSTGRES_MIN_VERSION}"
                    echo "Gefunden:            ${PG_SERVER_VERSION}"
                    exit 1
                fi

                echo "PostgreSQL Server: ${PG_SERVER_VERSION}"

                if [ -f "$ADPKI_ENV" ]; then
                    sed -i '/^ADPKI_POSTGRES_SERVER_VERSION=/d' "$ADPKI_ENV"
                    echo "ADPKI_POSTGRES_SERVER_VERSION=${PG_SERVER_SHORT}" >> "$ADPKI_ENV"
                fi
            else
                echo "Warnung: PostgreSQL Server-Version konnte nicht gelesen werden."
            fi
        else
            echo "Hinweis: PostgreSQL Server-Live-Prüfung übersprungen, da kein laufendes systemd erkannt wurde."
        fi
        ;;

    *)
        echo "Fehler: Ungültiger ADPKI_DB_MODE: ${ADPKI_DB_MODE}"
        echo "Erlaubt: existing, local"
        exit 1
        ;;
esac

echo "PostgreSQL-Step OK."