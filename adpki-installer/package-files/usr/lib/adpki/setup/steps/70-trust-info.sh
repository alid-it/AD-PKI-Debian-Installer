#!/usr/bin/env bash
set -euo pipefail

. /usr/lib/adpki/setup/common.sh

require_root
require_runtime_installed
setup_logging "70-trust-info"
load_install_env
load_setup_env_if_exists

require_command openssl

ROOT_CRT="/var/lib/adpki/root/root.crt"
INTERMEDIATE_CRT=""

# ---------------------------------------------------------------------------
# Zertifikate prüfen
# ---------------------------------------------------------------------------

echo "AD-PKI Trust-Konfiguration"
echo "=========================="
echo
echo "Die Root CA muss auf allen Clients als vertrauenswürdig eingestuft werden,"
echo "damit Zertifikate von AD-PKI ohne Warnungen akzeptiert werden."
echo
echo "Root CA Zertifikat:"
echo "  ${ROOT_CRT}"
echo

if [ ! -f "$ROOT_CRT" ]; then
    echo "Fehler: Root CA Zertifikat nicht gefunden: ${ROOT_CRT}"
    echo "Bitte zuerst Step 50 (import-root) ausführen."
    exit 1
fi

# Intermediate suchen
if [ -d /var/lib/adpki/intermediates ]; then
    INTERMEDIATE_CRT="$(find /var/lib/adpki/intermediates -name "*.crt" | sort | tail -n1 || true)"
fi

# ---------------------------------------------------------------------------
# Zertifikat-Infos ausgeben
# ---------------------------------------------------------------------------

echo "Root CA Details:"
openssl x509 -in "$ROOT_CRT" -noout \
    -subject \
    -issuer \
    -dates \
    -fingerprint -sha256 \
    2>/dev/null | sed 's/^/  /'
echo

if [ -n "$INTERMEDIATE_CRT" ] && [ -f "$INTERMEDIATE_CRT" ]; then
    echo "Intermediate CA Details:"
    openssl x509 -in "$INTERMEDIATE_CRT" -noout \
        -subject \
        -issuer \
        -dates \
        -fingerprint -sha256 \
        2>/dev/null | sed 's/^/  /'
    echo
else
    echo "Hinweis: Kein Intermediate CA Zertifikat gefunden."
    echo
fi

# ---------------------------------------------------------------------------
# Chain-Validierung
# ---------------------------------------------------------------------------

if [ -n "$INTERMEDIATE_CRT" ] && [ -f "$INTERMEDIATE_CRT" ]; then
    echo "Prüfe Zertifikatskette (Root → Intermediate)..."

    if openssl verify -CAfile "$ROOT_CRT" "$INTERMEDIATE_CRT" >/dev/null 2>&1; then
        echo "✅ Zertifikatskette gültig – Root und Intermediate gehören zusammen."
    else
        echo
        echo "❌ Fehler: Intermediate CA wurde nicht von dieser Root CA ausgestellt."
        echo
        echo "Root CA Subject:"
        openssl x509 -in "$ROOT_CRT" -noout -subject 2>/dev/null | sed 's/^/  /'
        echo "Intermediate CA Issuer:"
        openssl x509 -in "$INTERMEDIATE_CRT" -noout -issuer 2>/dev/null | sed 's/^/  /'
        echo
        echo "Bitte prüfe ob Root CA und Intermediate CA zusammenpassen."
        exit 1
    fi
    echo
fi

# ---------------------------------------------------------------------------
# Lokales Trust-Setup
# ---------------------------------------------------------------------------

echo "------------------------------------------------------------"
echo "Dieser Server – lokales CA-Trust"
echo "------------------------------------------------------------"
echo

LOCAL_DEST="/usr/local/share/ca-certificates/adpki-root-ca.crt"

if [ -f "$LOCAL_DEST" ]; then
    echo "Root CA bereits im lokalen Trust-Store vorhanden."
    echo "Aktualisiere..."
fi

cp "$ROOT_CRT" "$LOCAL_DEST"
update-ca-certificates

echo "✅ Root CA wurde lokal eingetragen."
echo

# ---------------------------------------------------------------------------
# Download-Hinweis
# ---------------------------------------------------------------------------

APP_URL="${ADPKI_APP_URL:-https://$(hostname -f)}"

echo "------------------------------------------------------------"
echo "Zertifikat herunterladen"
echo "------------------------------------------------------------"
echo
echo "Das Root CA Zertifikat ist über die WebUI abrufbar:"
echo
echo "  ${APP_URL}/api/ca/root"
echo
echo "Oder direkt vom Server kopieren:"
echo
echo "  scp root@$(hostname -f):${ROOT_CRT} ./adpki-root-ca.crt"
echo

# ---------------------------------------------------------------------------
# Windows
# ---------------------------------------------------------------------------

echo "------------------------------------------------------------"
echo "Windows – Gruppenrichtlinie (GPO)"
echo "------------------------------------------------------------"
echo
echo "1. Zertifikat auf dem Domain Controller ablegen"
echo "2. Gruppenrichtlinienverwaltung öffnen (gpmc.msc)"
echo "3. GPO erstellen oder bearbeiten"
echo "4. Navigieren zu:"
echo "     Computerkonfiguration"
echo "     → Richtlinien"
echo "     → Windows-Einstellungen"
echo "     → Sicherheitseinstellungen"
echo "     → Richtlinien für öffentliche Schlüssel"
echo "     → Vertrauenswürdige Stammzertifizierungsstellen"
echo "5. Zertifikat importieren"
echo "6. GPO verknüpfen und auf Clients anwenden"
echo
echo "Alternativ per PowerShell (lokal auf dem Client):"
echo
echo '  Import-Certificate -FilePath "adpki-root-ca.crt" \'
echo '    -CertStoreLocation "Cert:\LocalMachine\Root"'
echo

# ---------------------------------------------------------------------------
# Linux / Debian
# ---------------------------------------------------------------------------

echo "------------------------------------------------------------"
echo "Linux – Debian/Ubuntu"
echo "------------------------------------------------------------"
echo
echo "  sudo cp adpki-root-ca.crt /usr/local/share/ca-certificates/adpki-root-ca.crt"
echo "  sudo update-ca-certificates"
echo

# ---------------------------------------------------------------------------
# Linux / RHEL
# ---------------------------------------------------------------------------

echo "------------------------------------------------------------"
echo "Linux – RHEL/Rocky/AlmaLinux"
echo "------------------------------------------------------------"
echo
echo "  sudo cp adpki-root-ca.crt /etc/pki/ca-trust/source/anchors/adpki-root-ca.crt"
echo "  sudo update-ca-trust extract"
echo

# ---------------------------------------------------------------------------
# macOS
# ---------------------------------------------------------------------------

echo "------------------------------------------------------------"
echo "macOS"
echo "------------------------------------------------------------"
echo
echo "  sudo security add-trusted-cert -d -r trustRoot \\"
echo '    -k /Library/Keychains/System.keychain adpki-root-ca.crt'
echo

# ---------------------------------------------------------------------------
# Browser
# ---------------------------------------------------------------------------

echo "------------------------------------------------------------"
echo "Browser (Firefox)"
echo "------------------------------------------------------------"
echo
echo "Firefox verwendet einen eigenen Zertifikatsspeicher:"
echo
echo "  Einstellungen → Datenschutz & Sicherheit"
echo "  → Zertifikate anzeigen → Zertifizierungsstellen"
echo "  → Importieren → adpki-root-ca.crt"
echo "  → 'Dieser CA vertrauen, um Websites zu identifizieren' aktivieren"
echo

# ---------------------------------------------------------------------------
# Abschluss
# ---------------------------------------------------------------------------

write_setup_env_value "ADPKI_TRUST_CONFIGURED" "true"
mark_step_done "70-trust-info"

echo "Trust-Info-Step OK."