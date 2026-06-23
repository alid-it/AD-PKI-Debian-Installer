#!/usr/bin/env bash
# /usr/lib/adpki/setup/common.sh

export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# Pfade
# ---------------------------------------------------------------------------

ADPKI_INSTALL_ENV="/etc/adpki/install.env"
ADPKI_SETUP_ENV="/etc/adpki/setup.env"
ADPKI_BACKEND_ENV="/etc/adpki/backend.env"
ADPKI_CA_ENV="/etc/adpki/ca.env"
ADPKI_SETUP_STATE="/var/lib/adpki/setup/setup.state"
ADPKI_SETUP_STEP_DIR="/var/lib/adpki/setup/steps"
ADPKI_SETUP_LOG_DIR="/var/log/adpki/setup"

BACKEND_DIR="/opt/adpki/backend"

# ---------------------------------------------------------------------------
# Voraussetzungen
# ---------------------------------------------------------------------------

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Fehler: Bitte als root ausführen."
        exit 1
    fi
}

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Fehler: Benötigter Befehl fehlt: ${cmd}"
        exit 1
    fi
}

require_runtime_installed() {
    if [ ! -f "$ADPKI_INSTALL_ENV" ]; then
        echo
        echo "Fehler: AD-PKI Runtime wurde noch nicht installiert."
        echo "  sudo adpki-install"
        echo
        exit 1
    fi

    # shellcheck disable=SC1090
    . "$ADPKI_INSTALL_ENV"

    if [ "${ADPKI_RUNTIME_INSTALLED:-false}" != "true" ]; then
        echo
        echo "Fehler: adpki-install wurde noch nicht erfolgreich abgeschlossen."
        echo "  sudo adpki-install"
        echo
        exit 1
    fi

    if [ ! -f "${BACKEND_DIR}/artisan" ]; then
        echo
        echo "Fehler: Laravel Backend fehlt: ${BACKEND_DIR}/artisan"
        echo "  sudo adpki-install"
        echo
        exit 1
    fi

    if [ ! -f /opt/adpki/frontend/dist/index.html ]; then
        echo
        echo "Fehler: Frontend Build fehlt: /opt/adpki/frontend/dist/index.html"
        echo "  sudo adpki-install"
        echo
        exit 1
    fi

    if [ ! -x /opt/adpki/ca-core/adpki-ca ]; then
        echo
        echo "Fehler: CA-Core Binary fehlt: /opt/adpki/ca-core/adpki-ca"
        echo "  sudo adpki-install"
        echo
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# ENV laden
# ---------------------------------------------------------------------------

load_install_env() {
    if [ ! -f "$ADPKI_INSTALL_ENV" ]; then
        echo "Fehler: ${ADPKI_INSTALL_ENV} nicht gefunden."
        exit 1
    fi
    # shellcheck disable=SC1090
    . "$ADPKI_INSTALL_ENV"
}

load_setup_env_if_exists() {
    if [ -f "$ADPKI_SETUP_ENV" ]; then
        # shellcheck disable=SC1090
        . "$ADPKI_SETUP_ENV"
    fi
}

load_backend_env_if_exists() {
    if [ -f "$ADPKI_BACKEND_ENV" ]; then
        # shellcheck disable=SC1090
        . "$ADPKI_BACKEND_ENV"
    fi
}

# ---------------------------------------------------------------------------
# Setup State
# ---------------------------------------------------------------------------

ensure_setup_dirs() {
    mkdir -p /etc/adpki
    mkdir -p "$ADPKI_SETUP_STEP_DIR"
    mkdir -p "$ADPKI_SETUP_LOG_DIR"

    if getent group adpki >/dev/null 2>&1; then
        chown root:adpki \
            "$ADPKI_SETUP_STEP_DIR" \
            "$ADPKI_SETUP_LOG_DIR" 2>/dev/null || true
        chmod 750 \
            "$ADPKI_SETUP_STEP_DIR" \
            "$ADPKI_SETUP_LOG_DIR" 2>/dev/null || true
    fi
}

is_setup_completed() {
    [ -f "$ADPKI_SETUP_STATE" ] && grep -q '^setup_completed=true$' "$ADPKI_SETUP_STATE"
}

mark_step_done() {
    local step="$1"
    ensure_setup_dirs
    echo "done_at=$(date -Is)" > "${ADPKI_SETUP_STEP_DIR}/${step}.done"
    if getent group adpki >/dev/null 2>&1; then
        chown root:adpki "${ADPKI_SETUP_STEP_DIR}/${step}.done" 2>/dev/null || true
        chmod 640 "${ADPKI_SETUP_STEP_DIR}/${step}.done" 2>/dev/null || true
    fi
}

is_step_done() {
    local step="$1"
    [ -f "${ADPKI_SETUP_STEP_DIR}/${step}.done" ]
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

setup_logging() {
    local name="$1"
    local log_file="${ADPKI_SETUP_LOG_DIR}/${name}.log"

    ensure_setup_dirs
    touch "$log_file"

    if getent group adpki >/dev/null 2>&1; then
        chown root:adpki "$log_file" 2>/dev/null || true
        chmod 640 "$log_file" 2>/dev/null || true
    else
        chmod 600 "$log_file" 2>/dev/null || true
    fi

    exec > >(tee -a "$log_file") 2>&1

    echo "============================================================"
    echo "AD-PKI Setup: ${name}"
    echo "Gestartet: $(date -Is)"
    echo "Log: ${log_file}"
    echo "============================================================"
    echo
}

# ---------------------------------------------------------------------------
# Eingabe-Hilfsfunktionen
# ---------------------------------------------------------------------------

prompt_required() {
    local label="$1"
    local value=""
    while [ -z "$value" ]; do
        read -rp "${label}: " value 2>/dev/tty </dev/tty
    done
    printf '%s' "$value"
}

prompt_default() {
    local label="$1"
    local default="$2"
    local value=""
    read -rp "${label} [${default}]: " value 2>/dev/tty </dev/tty
    printf '%s' "${value:-$default}"
}

prompt_secret_required() {
    local label="$1"
    local value=""
    while [ -z "$value" ]; do
        read -rsp "${label}: " value 2>/dev/tty </dev/tty
        echo >/dev/tty
        value="${value//$'\r'/}"
        value="${value//$'\n'/}"
    done
    printf '%s' "$value"
}

# ---------------------------------------------------------------------------
# ENV-Dateien schreiben
# ---------------------------------------------------------------------------

escape_env_value() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\$/\\\$}"
    value="${value//\`/\\\`}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}

set_env_value() {
    local file="$1"
    local key="$2"
    local value="$3"
    local escaped tmp

    value="${value//$'\r'/}"
    value="${value//$'\n'/}"
    escaped="$(escape_env_value "$value")"

    mkdir -p "$(dirname "$file")"
    touch "$file"

    tmp="$(mktemp)"
    grep -v -E "^${key}=" "$file" > "$tmp" 2>/dev/null || true
    printf '%s=%s\n' "$key" "$escaped" >> "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
}

set_backend_env_value() {
    local key="$1"
    local value="$2"

    touch "$ADPKI_BACKEND_ENV"
    set_env_value "$ADPKI_BACKEND_ENV" "$key" "$value"

    chown root:www-data "$ADPKI_BACKEND_ENV" 2>/dev/null || \
        chown root:root "$ADPKI_BACKEND_ENV" || true
    chmod 640 "$ADPKI_BACKEND_ENV"
}

write_setup_env_value() {
    local key="$1"
    local value="$2"

    set_env_value "$ADPKI_SETUP_ENV" "$key" "$value"

    chown root:adpki "$ADPKI_SETUP_ENV" 2>/dev/null || true
    chmod 640 "$ADPKI_SETUP_ENV" 2>/dev/null || true
}
