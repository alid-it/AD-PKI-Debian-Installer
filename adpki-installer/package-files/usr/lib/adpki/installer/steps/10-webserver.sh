#!/usr/bin/env bash
set -euo pipefail

. /usr/lib/adpki/installer/common.sh

require_root
load_env
setup_logging "10-webserver"

stop_unattended_upgrades

echo "Installiere Basispakete..."

apt-get install -y \
    apt-transport-https \
    unzip \
    tar \
    xz-utils \
    openssl

echo
echo "Installiere Webserver: nginx"

apt-get install -y nginx
service_enable_start nginx

# Default vhost deaktivieren
if [ -L /etc/nginx/sites-enabled/default ]; then
    rm -f /etc/nginx/sites-enabled/default
    echo "Default nginx vhost deaktiviert."
fi

echo "Webserver-Step OK."