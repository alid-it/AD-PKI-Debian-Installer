#!/usr/bin/env bash
set -euo pipefail

. /usr/lib/adpki/installer/common.sh

require_root
load_env
setup_logging "90-configure-adpki"

# ============================================================
# FUNKTIONEN
# ============================================================

download_verified_release_asset() {
    local name="$1"
    local repo="$2"
    local asset_name="$3"
    local extract_dest="$4"

    local api_url asset_url sha_url tmp_dir archive_path sums_path

    api_url="https://api.github.com/repos/alid-it/${repo}/releases/latest"
    tmp_dir="$(mktemp -d)"
    archive_path="${tmp_dir}/${asset_name}"
    sums_path="${tmp_dir}/SHA256SUMS"

    echo
    echo "Suche Release für ${name}..."

    asset_url=$(curl -fsSL "$api_url" \
        | grep "browser_download_url.*${asset_name}\"" \
        | cut -d'"' -f4)

    sha_url=$(curl -fsSL "$api_url" \
        | grep "browser_download_url.*SHA256SUMS\"" \
        | cut -d'"' -f4)

    if [ -z "$asset_url" ]; then
        echo "Fehler: Release-Asset ${asset_name} für ${name} nicht gefunden."
        rm -rf "$tmp_dir"
        exit 1
    fi

    if [ -z "$sha_url" ]; then
        echo "Fehler: SHA256SUMS für ${name} nicht gefunden."
        rm -rf "$tmp_dir"
        exit 1
    fi

    echo "Lade ${name}: ${asset_url}"
    curl -fL --progress-bar -o "$archive_path" "$asset_url"

    echo "Lade Prüfsummen für ${name}: ${sha_url}"
    curl -fsSL -o "$sums_path" "$sha_url"

    echo "Prüfe SHA256 für ${name}..."
    (
        cd "$tmp_dir"
        sha256sum -c SHA256SUMS --ignore-missing
    ) || {
        echo "Fehler: SHA256-Prüfung für ${name} fehlgeschlagen."
        rm -rf "$tmp_dir"
        exit 1
    }

    if ! grep -qE "[[:space:]]${asset_name}$" "$sums_path"; then
        echo "Fehler: ${asset_name} ist nicht in SHA256SUMS enthalten."
        rm -rf "$tmp_dir"
        exit 1
    fi

    echo "Entpacke ${name}..."
    mkdir -p "$extract_dest"
    tar -xzf "$archive_path" -C "$extract_dest"

    rm -rf "$tmp_dir"
}

download_adpki_components() {
    echo
    echo "Lade AD-PKI Komponenten von GitHub mit SHA256-Prüfung..."

    # Version aus GitHub holen
    local CA_VERSION BACKEND_VERSION FRONTEND_VERSION
    CA_VERSION="$(curl -fsSL https://api.github.com/repos/alid-it/AD-PKI-CA/releases/latest | grep '"tag_name"' | cut -d'"' -f4)"
    BACKEND_VERSION="$(curl -fsSL https://api.github.com/repos/alid-it/AD-PKI-Backend/releases/latest | grep '"tag_name"' | cut -d'"' -f4)"
    FRONTEND_VERSION="$(curl -fsSL https://api.github.com/repos/alid-it/AD-PKI-Frontend/releases/latest | grep '"tag_name"' | cut -d'"' -f4)"


    # ------------------------------------------------------------
    # CA Binary
    # ------------------------------------------------------------
    mkdir -p /opt/adpki/ca-core

    download_verified_release_asset \
        "AD-PKI CA" \
        "AD-PKI-CA" \
        "ad-pki-ca.tar.gz" \
        "/opt/adpki/ca-core"

    chmod 0755 /opt/adpki/ca-core/adpki-ca
    chown adpki:adpki /opt/adpki/ca-core/adpki-ca
    echo "$CA_VERSION" > /opt/adpki/ca-core/VERSION
    chown adpki:adpki /opt/adpki/ca-core/VERSION
    chmod 640 /opt/adpki/ca-core/VERSION
    echo "✅ CA-Binary installiert. (${CA_VERSION})"


    # ------------------------------------------------------------
    # Backend
    # ------------------------------------------------------------
    mkdir -p /opt/adpki/backend

    download_verified_release_asset \
        "AD-PKI Backend" \
        "AD-PKI-Backend" \
        "ad-pki-backend.tar.gz" \
        "/opt/adpki/backend"

    echo "Installiere PHP-Abhängigkeiten..."
    chown -R www-data:www-data /opt/adpki/backend

    mkdir -p /var/lib/adpki/.composer-cache
    chown -R www-data:www-data /var/lib/adpki/.composer-cache

    runuser -u www-data -- env COMPOSER_HOME=/var/lib/adpki/.composer-cache composer install \
        --no-dev \
        --optimize-autoloader \
        --no-interaction \
        --working-dir=/opt/adpki/backend

    chown -R www-data:www-data /opt/adpki/backend/vendor
    echo "$BACKEND_VERSION" > /opt/adpki/backend/VERSION
    chown adpki:www-data /opt/adpki/backend/VERSION
    chmod 640 /opt/adpki/backend/VERSION
    echo "✅ Backend installiert. (${BACKEND_VERSION})"

    # ------------------------------------------------------------
    # Frontend
    # ------------------------------------------------------------
    mkdir -p /opt/adpki/frontend/dist

    download_verified_release_asset \
        "AD-PKI Frontend" \
        "AD-PKI-Frontend" \
        "ad-pki-frontend.tar.gz" \
        "/opt/adpki/frontend/dist"

    echo "$FRONTEND_VERSION" > /opt/adpki/frontend/dist/VERSION
    chown adpki:www-data /opt/adpki/frontend/dist/VERSION
    chmod 640 /opt/adpki/frontend/dist/VERSION
    echo "✅ Frontend installiert. (${FRONTEND_VERSION})"

    echo
    echo "Alle Komponenten erfolgreich geladen und geprüft."
}

hold_runtime_packages() {
    echo
    echo "Sperre AD-PKI Runtime-DEB-Pakete gegen automatische Upgrades..."

    if ! command -v apt-mark >/dev/null 2>&1; then
        echo "Warnung: apt-mark nicht gefunden. Paketsperre wird übersprungen."
        return 0
    fi

    mkdir -p /etc/adpki

    local packages=(
        adpki
        php8.4-cli
        php8.4-fpm
        php8.4-common
        php8.4-pgsql
        php8.4-xml
        php8.4-mbstring
        php8.4-curl
        php8.4-zip
        php8.4-bcmath
        php8.4-opcache
        php8.4-intl
        php8.4-readline
        postgresql-client-17
        nginx
        nginx-common
    )

    if [ "${ADPKI_DB_MODE:-}" = "local" ]; then
        packages+=(postgresql-17 postgresql-common postgresql-client-common)
    fi

    : > /etc/adpki/held-packages.list

    stop_unattended_upgrades

    for package in "${packages[@]}"; do
        if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"; then
            echo "Sperre Paket: ${package}"
            apt-mark hold "$package" >/dev/null
            echo "$package" >> /etc/adpki/held-packages.list
        else
            echo "Überspringe nicht installiertes Paket: ${package}"
        fi
    done

    chmod 640 /etc/adpki/held-packages.list
    chown root:adpki /etc/adpki/held-packages.list 2>/dev/null || chown root:root /etc/adpki/held-packages.list

    echo
    echo "Gesperrte Pakete:"
    cat /etc/adpki/held-packages.list || true

    echo
    echo "Paketsperre OK."
}

# ============================================================
# HAUPTABLAUF
# ============================================================


echo
echo "Prüfe Runtime-Versionen..."

php -v | head -n1 || true
node -v || true
npm -v || true
psql --version || true

if [ "${ADPKI_DB_MODE:-}" = "local" ]; then
    if has_systemd; then
        if systemctl is-active --quiet postgresql; then
            if command -v runuser >/dev/null 2>&1 && id postgres >/dev/null 2>&1; then
                PG_SERVER_VERSION="$(runuser -u postgres -- psql -tAc 'SHOW server_version;' 2>/dev/null | xargs || true)"
                if [ -n "$PG_SERVER_VERSION" ]; then
                    echo "PostgreSQL Server: ${PG_SERVER_VERSION}"
                else
                    echo "Warnung: PostgreSQL Server-Version konnte nicht gelesen werden."
                fi
            fi
        else
            echo "Warnung: PostgreSQL ist installiert, aber nicht aktiv."
        fi
    else
        echo "Hinweis: PostgreSQL Server-Live-Prüfung übersprungen."
    fi
fi

# ------------------------------------------------------------
# 1. Komponenten von GitHub laden
# ------------------------------------------------------------
download_adpki_components

# ------------------------------------------------------------
# postinst configure (nach Download – Binaries existieren jetzt)
# ------------------------------------------------------------
if [ -x /var/lib/dpkg/info/adpki.postinst ]; then
    ADPKI_POSTINST_CONTEXT="runtime" /var/lib/dpkg/info/adpki.postinst configure
else
    echo "Warnung: adpki.postinst wurde nicht gefunden."
fi

# ------------------------------------------------------------
# 2. NTP-Management
# ------------------------------------------------------------
echo
echo "Konfiguriere AD-PKI NTP-Management..."

ensure_ntp_helper_permissions

if [ -f /usr/sbin/adpki-set-ntp ]; then
    chown root:root /usr/sbin/adpki-set-ntp
    chmod 750 /usr/sbin/adpki-set-ntp
else
    echo "Warnung: /usr/sbin/adpki-set-ntp wurde nicht gefunden."
fi

if [ -f /etc/sudoers.d/adpki ]; then
    chown root:root /etc/sudoers.d/adpki
    chmod 440 /etc/sudoers.d/adpki

    if visudo -c -f /etc/sudoers.d/adpki >/dev/null; then
        echo "sudoers für AD-PKI ist gültig."
    else
        echo "Fehler: sudoers-Datei /etc/sudoers.d/adpki ist ungültig."
        exit 1
    fi
else
    echo "Warnung: /etc/sudoers.d/adpki wurde nicht gefunden."
fi

# ------------------------------------------------------------
# 3. Laufzeitrechte setzen
# ------------------------------------------------------------
echo
echo "Setze AD-PKI Laufzeitrechte..."

# Go/CA-Core Storage
mkdir -p /var/lib/adpki/{root,intermediates,issued,private,crl,csrs,setup}

chown -R adpki:adpki /var/lib/adpki
find /var/lib/adpki -type d -exec chmod 750 {} \;
find /var/lib/adpki -type f -exec chmod 640 {} \;

chmod 700 /var/lib/adpki/private
find /var/lib/adpki/private -type d -exec chmod 700 {} \;
find /var/lib/adpki/private -type f -exec chmod 600 {} \;

# Logs
mkdir -p /var/log/adpki/{backend,ca-core,installer,setup,nginx}

chown root:adpki /var/log/adpki
chmod 775 /var/log/adpki

LOG_GROUP="adpki"
if getent group adm >/dev/null 2>&1; then
    LOG_GROUP="adm"
fi

chown -R www-data:"$LOG_GROUP" /var/log/adpki/backend
chmod 750 /var/log/adpki/backend
find /var/log/adpki/backend -type f -exec chmod 640 {} \; 2>/dev/null || true

chown -R adpki:"$LOG_GROUP" /var/log/adpki/ca-core
chmod 750 /var/log/adpki/ca-core
find /var/log/adpki/ca-core -type f -exec chmod 640 {} \; 2>/dev/null || true

chown -R adpki:"$LOG_GROUP" /var/log/adpki/installer
chmod 750 /var/log/adpki/installer
find /var/log/adpki/installer -type f -exec chmod 640 {} \; 2>/dev/null || true

chown -R adpki:"$LOG_GROUP" /var/log/adpki/setup
chmod 750 /var/log/adpki/setup
find /var/log/adpki/setup -type f -exec chmod 640 {} \; 2>/dev/null || true

chown -R www-data:"$LOG_GROUP" /var/log/adpki/nginx
chmod 750 /var/log/adpki/nginx
find /var/log/adpki/nginx -type f -exec chmod 640 {} \; 2>/dev/null || true

# Laravel Runtime
if [ -d /opt/adpki/backend/storage ]; then
    chown -R www-data:www-data /opt/adpki/backend/storage
    find /opt/adpki/backend/storage -type d -exec chmod 2770 {} \;
    find /opt/adpki/backend/storage -type f -exec chmod 660 {} \;
fi

if [ -d /opt/adpki/backend/bootstrap ]; then
    chown adpki:www-data /opt/adpki/backend/bootstrap
    chmod 750 /opt/adpki/backend/bootstrap
fi

if [ -d /opt/adpki/backend/bootstrap/cache ]; then
    chown -R www-data:www-data /opt/adpki/backend/bootstrap/cache
    find /opt/adpki/backend/bootstrap/cache -type d -exec chmod 2770 {} \;
    find /opt/adpki/backend/bootstrap/cache -type f -exec chmod 660 {} \;
fi

# ------------------------------------------------------------
# 4. Pakete sperren
# ------------------------------------------------------------
hold_runtime_packages

echo "AD-PKI-Konfiguration-Step OK."