# Betrieb des AD-PKI-APT-Repositorys

Das offizielle Debian-Repository wird vom Release-Workflow unter
`https://packages.adpki.de` veröffentlicht. GitHub Pages stellt das statische
Paket-Repository bereit. Die Website und Dokumentation unter
`https://adpki.de` bleiben davon unabhängig auf dem Strato-Server.

## Einmalige GitHub-Konfiguration

Im Repository `alid-it/AD-PKI-Debian-Installer`:

1. **Settings → Pages** öffnen und unter **Build and deployment** als Quelle
   **GitHub Actions** auswählen.
2. `packages.adpki.de` als **Custom domain** eintragen.
3. Unter **Settings → Secrets and variables → Actions** folgende
   Repository-Secrets anlegen:
   - `ADPKI_RELEASE_TOKEN`: Token, mit dem Releases in `alid-it/AD-PKI`
     erstellt und aktualisiert werden dürfen.
   - `APT_SIGNING_PRIVATE_KEY`: ASCII-armierter privater Signierschlüssel des
     Paket-Repositorys.
   - `APT_SIGNING_KEY_FINGERPRINT`: vollständiger Fingerabdruck dieses
     Schlüssels.
   - `APT_SIGNING_KEY_PASSPHRASE`: Passphrase des privaten Schlüssels.

## DNS-Konfiguration bei Strato

Die Custom Domain zuerst in den GitHub-Pages-Einstellungen eintragen. Danach
bei Strato folgenden DNS-Eintrag erstellen:

```text
Typ:    CNAME
Name:   packages
Ziel:   alid-it.github.io
```

Für die Pages-Domain keinen Wildcard-DNS-Eintrag verwenden. DNS-Änderungen und
die Ausstellung des GitHub-Pages-TLS-Zertifikats können einige Zeit benötigen.
Sobald GitHub HTTPS anbietet, in den Pages-Einstellungen **Enforce HTTPS**
aktivieren.

## Eigenen Signierschlüssel erstellen

Den Schlüssel auf einem vertrauenswürdigen Administrationssystem erzeugen,
nicht innerhalb von GitHub Actions:

```bash
gpg --quick-generate-key \
  "AD-PKI Debian Repository <danakiranali@gmail.com>" \
  rsa4096 sign 2y

gpg --list-secret-keys \
  --keyid-format long \
  --with-subkey-fingerprint

gpg --armor --export-secret-keys <VOLLSTÄNDIGER-FINGERABDRUCK> \
  > adpki-apt-private.asc

gpg --armor --export <VOLLSTÄNDIGER-FINGERABDRUCK> \
  > adpki-archive-keyring.asc
```

Den Inhalt von `adpki-apt-private.asc` ausschließlich im Secret
`APT_SIGNING_PRIVATE_KEY` hinterlegen. Den privaten Schlüssel niemals in Git
committen oder öffentlich hochladen.

Den privaten Export und seine Passphrase zusätzlich in einem Passwortmanager
oder einem anderen verschlüsselten Backup sichern. Der öffentliche Schlüssel
und sein Fingerabdruck dürfen und sollen dagegen veröffentlicht werden, damit
Benutzer die Herkunft unabhängig prüfen können.

## Release veröffentlichen

Den nächsten Versions-Tag erstellen und zu GitHub pushen. Der Workflow führt
danach automatisch folgende Schritte aus:

1. Das versionierte Debian-Paket bauen.
2. Das Paket in das zentrale AD-PKI-GitHub-Release hochladen.
3. Alle vorhandenen versionierten AD-PKI-Pakete einsammeln.
4. `Packages`, `Packages.gz` und `Release` erzeugen.
5. Die signierten Dateien `InRelease` und `Release.gpg` erstellen.
6. Den öffentlichen Repository-Schlüssel exportieren.
7. Das vollständige Repository über GitHub Pages veröffentlichen.

## Veröffentlichung überprüfen

Nach einem Release zunächst Erreichbarkeit und Signaturdateien kontrollieren:

```bash
curl -fI https://packages.adpki.de/
curl -fI https://packages.adpki.de/dists/stable/InRelease
curl -fI \
  https://packages.adpki.de/dists/stable/main/binary-amd64/Packages.gz

curl -fsSL https://packages.adpki.de/adpki-archive-keyring.asc \
  | gpg --show-keys --with-fingerprint
```

Anschließend das Repository auf einem sauberen Debian-13-Testsystem einbinden:

```bash
sudo install -d -m 0755 /etc/apt/keyrings

curl -fsSL https://packages.adpki.de/adpki-archive-keyring.asc \
  | sudo tee /etc/apt/keyrings/adpki.asc >/dev/null

sudo chmod 0644 /etc/apt/keyrings/adpki.asc

sudo tee /etc/apt/sources.list.d/adpki.sources >/dev/null <<'EOF'
Types: deb
URIs: https://packages.adpki.de
Suites: stable
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/adpki.asc
EOF

sudo apt update
apt-cache policy adpki
sudo apt install adpki
```

Bei späteren Versionen muss nur noch das normale Systemupdate ausgeführt
werden:

```bash
sudo apt update
sudo apt upgrade
```

## Schlüsselwechsel

Einen Ersatzschlüssel veröffentlichen, bevor ausschließlich mit diesem neuen
Schlüssel signiert wird. Den alten öffentlichen Schlüssel während einer
Übergangszeit weiter anbieten.

Falls der private Schlüssel kompromittiert wurde:

1. Veröffentlichung neuer Repository-Metadaten sofort stoppen.
2. Betroffenen Schlüssel widerrufen.
3. Alle GitHub-Secrets ersetzen.
4. Einen neuen Repository-Schlüssel erzeugen und veröffentlichen.
5. Den neuen Fingerabdruck über `adpki.de` und die offiziellen
   GitHub-Repositories bekannt geben.
