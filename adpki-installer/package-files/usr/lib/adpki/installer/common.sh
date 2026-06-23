#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

ADPKI_VERSION="0.1.21"

PHP_PACKAGE_MAJOR="8.4"
PHP_MIN_VERSION="8.4.16"
PHP_VERSION_POLICY="8.4.x>=8.4.16"
PHP_VERSION_POLICY_LABEL="8.4.x >= 8.4.16"

POSTGRES_MAJOR="17"
POSTGRES_MIN_VERSION="17.9"
POSTGRES_VERSION_POLICY="17.x>=17.9"
POSTGRES_VERSION_POLICY_LABEL="17.x >= 17.9"

NODE_VERSION="24.15.0"
GO_VERSION="1.26.1"

ADPKI_ENV="/etc/adpki/install.env"
ADPKI_LOG_DIR="/var/log/adpki/installer"
ADPKI_RUNTIME_INSTALLED=false

ensure_log_dir() {
    mkdir -p /var/log/adpki
    mkdir -p "$ADPKI_LOG_DIR"

    chown root:adpki /var/log/adpki 2>/dev/null || true
    chmod 775 /var/log/adpki 2>/dev/null || true

    if id adpki >/dev/null 2>&1 && getent group adm >/dev/null 2>&1; then
        chown adpki:adm "$ADPKI_LOG_DIR" 2>/dev/null || true
    elif id adpki >/dev/null 2>&1; then
        chown adpki:adpki "$ADPKI_LOG_DIR" 2>/dev/null || true
    else
        chown root:root "$ADPKI_LOG_DIR" 2>/dev/null || true
    fi

    chmod 750 "$ADPKI_LOG_DIR" 2>/dev/null || true
}

setup_logging() {
    local log_name="$1"
    local log_file="${ADPKI_LOG_DIR}/${log_name}.log"

    ensure_log_dir

    touch "$log_file"

    if getent group adm >/dev/null 2>&1; then
        chown root:adm "$log_file" 2>/dev/null || true
        chmod 640 "$log_file" 2>/dev/null || true
    elif getent group adpki >/dev/null 2>&1; then
        chown root:adpki "$log_file" 2>/dev/null || true
        chmod 640 "$log_file" 2>/dev/null || true
    else
        chown root:root "$log_file" 2>/dev/null || true
        chmod 600 "$log_file" 2>/dev/null || true
    fi

    exec > >(tee -a "$log_file") 2>&1

    echo
    echo "============================================================"
    echo "AD-PKI installer log: ${log_name}"
    echo "Started: $(date -Is)"
    echo "Logfile: ${log_file}"
    echo "============================================================"
    echo
}

load_env() {
    if [ -f "$ADPKI_ENV" ]; then
        # shellcheck disable=SC1090
        . "$ADPKI_ENV"
    else
        echo "Fehler: $ADPKI_ENV wurde nicht gefunden."
        echo "Bitte zuerst ausführen:"
        echo "  adpki-install"
        exit 1
    fi
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Bitte als root ausführen."
        exit 1
    fi
}

ensure_adpki_user() {
    echo
    echo "Prüfe AD-PKI Systembenutzer..."

    if ! getent group www-data >/dev/null 2>&1; then
        groupadd --system www-data
        echo "Gruppe www-data wurde angelegt."
    fi

    if ! getent group adpki >/dev/null 2>&1; then
        groupadd --system adpki
        echo "Gruppe adpki wurde angelegt."
    fi

if ! id adpki >/dev/null 2>&1; then
    useradd \
        --system \
        --gid adpki \
        --groups www-data \
        --home-dir /var/lib/adpki \
        --shell /usr/sbin/nologin \
        --comment "AD-PKI Service User" \
        adpki
else
    usermod -aG www-data adpki
fi

# www-data braucht adpki-Gruppe für Lesezugriff auf /var/lib/adpki
if getent group adpki >/dev/null 2>&1; then
    usermod -aG adpki www-data
fi

    mkdir -p /var/lib/adpki
    mkdir -p /var/log/adpki
    mkdir -p /var/log/adpki/installer

    # Go/CA-Core Storage: kein www-data Zugriff
    chown adpki:adpki /var/lib/adpki
    chmod 750 /var/lib/adpki

    # Log-Basis
    chown root:root /var/log/adpki
    chmod 755 /var/log/adpki

    # Installer-Logs
    if getent group adm >/dev/null 2>&1; then
        chown adpki:adm /var/log/adpki/installer 2>/dev/null || true
    else
        chown adpki:adpki /var/log/adpki/installer 2>/dev/null || true
    fi

    chmod 750 /var/log/adpki/installer

    echo "Gruppen:"
    id adpki
}

ensure_ntp_helper_permissions() {
    mkdir -p /usr/local/sbin
    chown root:root /usr/local/sbin
    chmod 755 /usr/local/sbin

    mkdir -p /etc/sudoers.d
    chown root:root /etc/sudoers.d
    chmod 755 /etc/sudoers.d

    if [ -f /usr/sbin/adpki-set-ntp ]; then
        chown root:root /usr/sbin/adpki-set-ntp
        chmod 750 /usr/sbin/adpki-set-ntp
    else
        echo "Hinweis: /usr/sbin/adpki-set-ntp wurde nicht gefunden."
    fi

    if [ -f /etc/sudoers.d/adpki ]; then
        chown root:root /etc/sudoers.d/adpki
        chmod 440 /etc/sudoers.d/adpki

        if command -v visudo >/dev/null 2>&1; then
            if visudo -c -f /etc/sudoers.d/adpki >/dev/null; then
                echo "sudoers für AD-PKI ist gültig."
            else
                echo "Fehler: sudoers-Datei /etc/sudoers.d/adpki ist ungültig."
                exit 1
            fi
        fi
    else
        echo "Hinweis: /etc/sudoers.d/adpki wurde nicht gefunden."
    fi
}

detect_os() {
    if [ ! -f /etc/os-release ]; then
        echo "Fehler: /etc/os-release nicht gefunden."
        exit 1
    fi

    . /etc/os-release

    OS_ID="${ID:-}"
    OS_CODENAME="${VERSION_CODENAME:-}"

    if [ "$OS_ID" != "debian" ]; then
        echo "Fehler: Dieses Script ist aktuell für Debian vorgesehen."
        echo "Erkannt: ${OS_ID}"
        exit 1
    fi

    if [ "$OS_CODENAME" != "trixie" ]; then
        echo "Warnung: Erwartet wird Debian 13 trixie."
        echo "Erkannt: ${OS_CODENAME}"

        read -rp "Trotzdem fortfahren? [y/N]: " CONTINUE_ANYWAY

        case "$CONTINUE_ANYWAY" in
            y|Y|yes|YES)
                ;;
            *)
                exit 1
                ;;
        esac
    fi
}

detect_arch() {
    DEB_ARCH="$(dpkg --print-architecture)"

    case "$DEB_ARCH" in
        amd64)
            NODE_ARCH="x64"
            GO_ARCH="amd64"
            ;;
        arm64)
            NODE_ARCH="arm64"
            GO_ARCH="arm64"
            ;;
        *)
            echo "Fehler: Architektur wird aktuell nicht unterstützt: ${DEB_ARCH}"
            echo "Unterstützt: amd64, arm64"
            exit 1
            ;;
    esac
}

has_systemd() {
    [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1
}

service_enable_start() {
    local service="$1"

    if has_systemd; then
        systemctl enable "$service" >/dev/null 2>&1 || true
        systemctl restart "$service" >/dev/null 2>&1 || systemctl start "$service" >/dev/null 2>&1 || true
    else
        echo "Hinweis: systemd läuft nicht. Service wird nicht gestartet: ${service}"
    fi
}

service_enable_only() {
    local service="$1"

    if has_systemd; then
        systemctl enable "$service" >/dev/null 2>&1 || true
    else
        echo "Hinweis: systemd läuft nicht. Service wird nicht aktiviert: ${service}"
    fi
}

db_mode_label() {
    case "${ADPKI_DB_MODE:-}" in
        existing)
            echo "vorhandener PostgreSQL-Server"
            ;;
        local)
            echo "neuer lokaler PostgreSQL-Server"
            ;;
        external)
            echo "vorhandener PostgreSQL-Server"
            ;;
        "")
            echo "nicht gesetzt"
            ;;
        *)
            echo "${ADPKI_DB_MODE}"
            ;;
    esac
}

find_exact_apt_version() {
    local package="$1"
    local wanted_version="$2"

    apt-cache madison "$package" | awk -v wanted="$wanted_version" '
        $3 ~ wanted && found == 0 {
            print $3
            found = 1
        }
        END {
            exit 0
        }
    '
}

apt_install_exact_or_fail() {
    local package="$1"
    local wanted_version="$2"
    local exact_version

    exact_version="$(find_exact_apt_version "$package" "$wanted_version")"

    if [ -z "$exact_version" ]; then
        echo
        echo "Fehler: Paket ${package} in Version ${wanted_version} nicht gefunden."
        echo
        echo "Verfügbare Versionen:"
        apt-cache madison "$package" || true
        echo
        exit 1
    fi

    echo "Installiere ${package}=${exact_version}"
    apt-get install -y "${package}=${exact_version}"
}

mark_runtime_installed() {
    if [ ! -f "$ADPKI_ENV" ]; then
        echo "Fehler: ${ADPKI_ENV} wurde nicht gefunden."
        exit 1
    fi

    sed -i '/^ADPKI_RUNTIME_INSTALLED=/d' "$ADPKI_ENV"
    sed -i '/^ADPKI_RUNTIME_INSTALLED_AT=/d' "$ADPKI_ENV"

    {
        echo "ADPKI_RUNTIME_INSTALLED=true"
        echo "ADPKI_RUNTIME_INSTALLED_AT=$(date -Is)"
    } >> "$ADPKI_ENV"

    chmod 640 "$ADPKI_ENV"
    chown root:adpki "$ADPKI_ENV" 2>/dev/null || chown root:root "$ADPKI_ENV"

    echo
    echo "AD-PKI Runtime-Status wurde gesetzt:"
    echo "  ADPKI_RUNTIME_INSTALLED=true"
}

stop_unattended_upgrades() {
    if systemctl is-active --quiet unattended-upgrades 2>/dev/null; then
        echo "Stoppe unattended-upgrades..."
        systemctl stop unattended-upgrades || true
    fi

    # Warten bis Lock frei ist
    local timeout=120
    local waited=0
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
        echo "Warte auf Paketmanager-Lock..."
        sleep 3
        waited=$((waited + 3))
        if [ "$waited" -ge "$timeout" ]; then
            echo "Fehler: dpkg/apt Lock nach ${timeout}s noch belegt."
            exit 1
        fi
    done

    echo "✅ Paketmanager bereit."
}

write_env() {
    mkdir -p /etc/adpki

    ADPKI_DB_MODE_LABEL="$(db_mode_label)"

    cat > "$ADPKI_ENV" <<EOF_ENV
ADPKI_WEB_SERVER="${ADPKI_WEB_SERVER}"
ADPKI_DB_MODE="${ADPKI_DB_MODE}"
ADPKI_DB_MODE_LABEL="${ADPKI_DB_MODE_LABEL}"
ADPKI_INSTALLER_VERSION="${ADPKI_VERSION}"
ADPKI_RUNTIME_INSTALLED=false
ADPKI_PHP_VERSION_POLICY="${PHP_VERSION_POLICY}"
ADPKI_PHP_MIN_VERSION="${PHP_MIN_VERSION}"
ADPKI_POSTGRES_VERSION_POLICY="${POSTGRES_VERSION_POLICY}"
ADPKI_POSTGRES_MIN_VERSION="${POSTGRES_MIN_VERSION}"
ADPKI_NODE_VERSION="${NODE_VERSION}"
ADPKI_GO_VERSION="${GO_VERSION}"
EOF_ENV

    chmod 640 "$ADPKI_ENV"
    chown root:adpki "$ADPKI_ENV" 2>/dev/null || chown root:root "$ADPKI_ENV"
}