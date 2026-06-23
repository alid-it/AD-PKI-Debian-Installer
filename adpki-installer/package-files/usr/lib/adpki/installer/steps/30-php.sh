#!/usr/bin/env bash
set -euo pipefail

. /usr/lib/adpki/installer/common.sh

require_root
load_env
setup_logging "30-php"

echo "Installiere PHP ${PHP_VERSION_POLICY_LABEL}..."

PHP_PACKAGES=(
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
)

apt install -y "${PHP_PACKAGES[@]}"
apt install -y unzip

service_enable_start php8.4-fpm

echo
echo "Installiere Composer..."

if ! command -v composer >/dev/null 2>&1; then
    export COMPOSER_ALLOW_SUPERUSER=1

    EXPECTED_SIGNATURE="$(curl -s https://composer.github.io/installer.sig)"
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    ACTUAL_SIGNATURE="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

    if [ "$EXPECTED_SIGNATURE" != "$ACTUAL_SIGNATURE" ]; then
        echo "Fehler: Composer-Installer-Signatur ungültig."
        rm -f composer-setup.php
        exit 1
    fi

    php composer-setup.php --quiet --install-dir=/usr/local/bin --filename=composer
    rm -f composer-setup.php

    chmod 755 /usr/local/bin/composer
    echo "Composer installiert: $(composer --version)"
else
    echo "Composer ist bereits installiert: $(composer --version)"
fi

PHP_ACTUAL="$(php -r 'echo PHP_VERSION;')"

if ! dpkg --compare-versions "$PHP_ACTUAL" ge "$PHP_MIN_VERSION"; then
    echo "Fehler: PHP-Version ist zu alt."
    echo "Erwartet mindestens: ${PHP_MIN_VERSION}"
    echo "Gefunden:            ${PHP_ACTUAL}"
    exit 1
fi

case "$PHP_ACTUAL" in
    8.4.*)
        ;;
    *)
        echo "Fehler: PHP Major/Minor passt nicht."
        echo "Erwartet: PHP 8.4.x"
        echo "Gefunden: ${PHP_ACTUAL}"
        exit 1
        ;;
esac

if [ -f "$ADPKI_ENV" ]; then
    sed -i '/^ADPKI_PHP_INSTALLED_VERSION=/d' "$ADPKI_ENV"
    echo "ADPKI_PHP_INSTALLED_VERSION=${PHP_ACTUAL}" >> "$ADPKI_ENV"
fi

php -v | head -n1
php -m | grep -E '^(bcmath|curl|intl|mbstring|openssl|PDO|pdo_pgsql|pgsql|xml|zip)$' || true

echo "PHP-Step OK."