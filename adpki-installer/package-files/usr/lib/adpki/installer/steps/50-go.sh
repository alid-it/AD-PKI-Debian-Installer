#!/usr/bin/env bash
set -euo pipefail

. /usr/lib/adpki/installer/common.sh

require_root
load_env
detect_arch
setup_logging "50-go"

echo "Installiere Go ${GO_VERSION}..."

GO_TAR="go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
GO_URL="https://go.dev/dl/${GO_TAR}"

case "$GO_ARCH" in
    amd64)
        GO_SHA256="031f088e5d955bab8657ede27ad4e3bc5b7c1ba281f05f245bcc304f327c987a"
        ;;
    arm64)
        GO_SHA256="a290581cfe4fe28ddd737dde3095f3dbeb7f2e4065cab4eae44dfc53b760c2f7"
        ;;
    *)
        echo "Fehler: Keine Go-Prüfsumme für Architektur ${GO_ARCH} hinterlegt."
        exit 1
        ;;
esac

curl -fsSL "$GO_URL" -o "/tmp/${GO_TAR}"

echo "${GO_SHA256}  /tmp/${GO_TAR}" | sha256sum -c -

rm -rf /usr/local/go
tar -C /usr/local -xzf "/tmp/${GO_TAR}"

rm -f "/tmp/${GO_TAR}"

ln -sfn /usr/local/go/bin/go /usr/local/bin/go
ln -sfn /usr/local/go/bin/gofmt /usr/local/bin/gofmt

GO_ACTUAL="$(go version | awk '{print $3}' | sed 's/^go//')"

if [ "$GO_ACTUAL" != "$GO_VERSION" ]; then
    echo "Fehler: Go-Version passt nicht."
    echo "Erwartet: ${GO_VERSION}"
    echo "Gefunden:  ${GO_ACTUAL}"
    exit 1
fi

go version

echo "Go-Step OK."
