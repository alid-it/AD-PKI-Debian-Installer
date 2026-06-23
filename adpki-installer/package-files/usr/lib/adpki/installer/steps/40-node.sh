#!/usr/bin/env bash
set -euo pipefail

. /usr/lib/adpki/installer/common.sh

require_root
load_env
detect_arch
setup_logging "40-node"

echo "Installiere Node.js ${NODE_VERSION}..."

NODE_DIR="/opt/node-v${NODE_VERSION}"
NODE_TAR="node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz"
NODE_BASE_URL="https://nodejs.org/download/release/v${NODE_VERSION}"
NODE_URL="${NODE_BASE_URL}/${NODE_TAR}"
NODE_SHASUMS_URL="${NODE_BASE_URL}/SHASUMS256.txt"

if [ ! -d "$NODE_DIR" ]; then
    curl -fsSL "$NODE_URL" -o "/tmp/${NODE_TAR}"
    curl -fsSL "$NODE_SHASUMS_URL" -o "/tmp/SHASUMS256-node-${NODE_VERSION}.txt"

    NODE_SHA256="$(grep " ${NODE_TAR}$" "/tmp/SHASUMS256-node-${NODE_VERSION}.txt" | awk '{print $1}')"

    if [ -z "$NODE_SHA256" ]; then
        echo "Fehler: SHA256 für ${NODE_TAR} wurde nicht gefunden."
        exit 1
    fi

    echo "${NODE_SHA256}  /tmp/${NODE_TAR}" | sha256sum -c -

    tar -xf "/tmp/${NODE_TAR}" -C /opt
    mv "/opt/node-v${NODE_VERSION}-linux-${NODE_ARCH}" "$NODE_DIR"

    rm -f "/tmp/${NODE_TAR}" "/tmp/SHASUMS256-node-${NODE_VERSION}.txt"
fi

ln -sfn "${NODE_DIR}/bin/node" /usr/local/bin/node
ln -sfn "${NODE_DIR}/bin/npm" /usr/local/bin/npm
ln -sfn "${NODE_DIR}/bin/npx" /usr/local/bin/npx

NODE_ACTUAL="$(node -v | sed 's/^v//')"

if [ "$NODE_ACTUAL" != "$NODE_VERSION" ]; then
    echo "Fehler: Node-Version passt nicht."
    echo "Erwartet: ${NODE_VERSION}"
    echo "Gefunden:  ${NODE_ACTUAL}"
    exit 1
fi

node -v
npm -v

echo "Node-Step OK."
