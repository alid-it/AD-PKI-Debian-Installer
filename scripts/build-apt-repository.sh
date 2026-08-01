#!/usr/bin/env bash
set -euo pipefail

PACKAGE_DIR="${1:?Usage: build-apt-repository.sh <package-dir> <output-dir>}"
OUTPUT_DIR="${2:?Usage: build-apt-repository.sh <package-dir> <output-dir>}"

if [ ! -d "$PACKAGE_DIR" ]; then
    echo "Package directory does not exist: $PACKAGE_DIR" >&2
    exit 1
fi

install -d \
    "$OUTPUT_DIR/pool/main/a/adpki" \
    "$OUTPUT_DIR/dists/stable/main/binary-amd64"

package_count=0
while IFS= read -r -d '' package; do
    install -m 0644 "$package" "$OUTPUT_DIR/pool/main/a/adpki/$(basename "$package")"
    package_count=$((package_count + 1))
done < <(find "$PACKAGE_DIR" -maxdepth 1 -type f \
    -name 'adpki_[0-9]*_amd64.deb' -print0 | sort -z)

if [ "$package_count" -eq 0 ]; then
    echo "No versioned AD-PKI amd64 packages found in $PACKAGE_DIR" >&2
    exit 1
fi

(
    cd "$OUTPUT_DIR"

    apt-ftparchive packages pool/main/a/adpki \
        > dists/stable/main/binary-amd64/Packages

    gzip -9n -c dists/stable/main/binary-amd64/Packages \
        > dists/stable/main/binary-amd64/Packages.gz

    apt-ftparchive \
        -o APT::FTPArchive::Release::Origin="AD-PKI" \
        -o APT::FTPArchive::Release::Label="AD-PKI" \
        -o APT::FTPArchive::Release::Suite="stable" \
        -o APT::FTPArchive::Release::Codename="stable" \
        -o APT::FTPArchive::Release::Architectures="amd64" \
        -o APT::FTPArchive::Release::Components="main" \
        -o APT::FTPArchive::Release::Description="Official AD-PKI Debian repository" \
        release dists/stable \
        > dists/stable/Release
)

cat > "$OUTPUT_DIR/index.html" <<'EOF'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>AD-PKI Debian Repository</title>
  </head>
  <body>
    <h1>AD-PKI Debian Repository</h1>
    <p>This repository is intended for APT clients. Installation instructions are available at <a href="https://adpki.de/docs/de/installation/">adpki.de</a>.</p>
  </body>
</html>
EOF

touch "$OUTPUT_DIR/.nojekyll"

echo "Built APT repository with $package_count package(s) in $OUTPUT_DIR"
