# AD-PKI Debian Installer

[English](README.md) | [Deutsch](README.de.md)

Der AD-PKI Debian Installer installiert und konfiguriert die AD-PKI-Plattform
auf einem dedizierten Debian-Server. Er richtet die benötigte Laufzeitumgebung
ein, lädt geprüfte Releases der AD-PKI-Komponenten herunter, erstellt die
Dateisystem- und systemd-Struktur und führt durch die fachliche
Erstkonfiguration.

> [!IMPORTANT]
> Dieses Projekt ist für dedizierte Systeme vorgesehen. Der Installer verändert
> Webserver, PHP, PostgreSQL, NTP, systemd, Paketquellen und die für den Betrieb
> relevanten Ports des Hosts.

## Architektur

AD-PKI besteht aus drei Anwendungskomponenten:

- **Frontend:** Vue-basierte Weboberfläche
- **Backend:** Laravel API, Worker, Scheduler und Reverb-Dienst
- **CA Core:** Go-Dienst für PKI-Operationen

Die Installation ist bewusst in zwei Schritte getrennt:

1. `adpki-install` installiert Laufzeitumgebung und Anwendungen.
2. `adpki-setup` konfiguriert Datenbank und TLS, importiert das CA-Material und
   erstellt den ersten Administrator.

Der Installer erzeugt **keine** Root CA und keine Intermediate CA. Beide
Zertifikate müssen bereits vorhanden sein. Der private Schlüssel der Root CA
bleibt offline und wird vom Setup-Assistenten nicht benötigt.

## Voraussetzungen

- Debian 13 (Trixie)
- `amd64`-Architektur für das aktuelle Debian-Paket
- Root-Zugriff
- Dedizierter Host oder VM mit systemd
- Internetzugriff während der Installation
- Freie Ports `80/tcp` und `443/tcp`
- Ein DNS-Name, der für Let's Encrypt auf den Server zeigt
- Vorhandenes Root-CA-Zertifikat
- Vorhandenes Intermediate-CA-Zertifikat mit privatem Schlüssel
- PostgreSQL-17-Server oder die Erlaubnis, ihn lokal zu installieren

Der Runtime-Installer verwendet aktuell:

| Komponente | Versionsvorgabe |
| --- | --- |
| PHP | 8.4.x, mindestens 8.4.16 |
| PostgreSQL | 17.x, mindestens 17.9 |
| Node.js | 24.15.0 |
| Webserver | Nginx |

CA Core, Backend und Frontend werden aus den neuesten GitHub-Releases der
Organisation `alid-it` geladen. Die Release-Archive werden anhand der
veröffentlichten `SHA256SUMS` geprüft.

## Installation

### 1. Debian-Paket installieren

Paket herunterladen oder selbst bauen und anschließend installieren:

```bash
sudo apt install ./adpki_<version>_amd64.deb
```

Das Paket installiert die AD-PKI-Befehle, Konfigurationsvorlagen,
systemd-Units und Installer-Skripte. Die vollständige Laufzeitumgebung wird
erst im nächsten Schritt installiert.

### 2. Laufzeitumgebung installieren

```bash
sudo adpki-install
```

Dabei muss einer der PostgreSQL-Modi gewählt werden:

- **Vorhandener PostgreSQL-Server:** Ein vorhandener lokaler oder entfernter
  Server wird verwendet.
- **Neuer lokaler PostgreSQL-Server:** PostgreSQL wird auf dem AD-PKI-Host
  installiert und konfiguriert.

Dieser Schritt installiert Nginx, PHP, PostgreSQL-Client oder -Server,
Composer und Node.js. Danach werden die AD-PKI-Komponenten heruntergeladen und
bereitgestellt.

### 3. Erstkonfiguration ausführen

```bash
sudo adpki-setup
```

Der Setup-Assistent erledigt folgende Aufgaben:

1. Host und installierte Laufzeitumgebung prüfen.
2. Anwendungskonfiguration und Geheimnisse erzeugen.
3. PostgreSQL-Verbindung konfigurieren und testen.
4. Laravel-Migrationen und Seeder ausführen.
5. Root-CA-Zertifikat importieren.
6. Intermediate-CA-Zertifikat und privaten Schlüssel importieren.
7. Hinweise zur Client-Vertrauensstellung anzeigen.
8. Let's-Encrypt-Zertifikat beziehen und HTTPS aktivieren.
9. Ersten Administrator mit gewünschter Oberflächensprache erstellen.
10. Alle AD-PKI-Dienste aktivieren und prüfen.

Nach erfolgreichem Setup ist die Weboberfläche erreichbar unter:

```text
https://<deine-adpki-domain>
```

## Sprache des Administrators

Die Standardsprache des Frontends ist Englisch. Während der
Erstkonfiguration kann für den Administrator Deutsch oder eine andere
unterstützte Kontosprache ausgewählt werden. Die Auswahl wird im
Administratorkonto gespeichert.

## CLI-Befehle

```bash
sudo adpki status
sudo adpki restart
sudo adpki logs
sudo adpki update
```

| Befehl | Funktion |
| --- | --- |
| `adpki status` | Status von Nginx, PHP-FPM und AD-PKI-Diensten anzeigen |
| `adpki restart` | AD-PKI-Laufzeitdienste neu starten |
| `adpki logs` | systemd-Logs der Anwendungsdienste live anzeigen |
| `adpki update` | CA Core, Backend und Frontend aus GitHub-Releases aktualisieren |

Der Updater fragt vor Änderungen nach einer Bestätigung, prüft
SHA-256-Prüfsummen, führt ausstehende Datenbankmigrationen aus und versucht,
vorher ein Datenbank-Backup zu erstellen.

## Dateien und Verzeichnisse

```text
/opt/adpki/
├── backend/
├── frontend/
└── ca-core/

/etc/adpki/
├── backend.env
├── ca.env
├── install.env
├── setup.env
└── versions.env

/var/lib/adpki/
├── root/
├── intermediates/
├── issued/
├── private/
├── crl/
├── csrs/
├── backups/
└── setup/

/var/log/adpki/
├── backend/
├── ca-core/
├── installer/
├── nginx/
└── setup/
```

Konfigurationsdateien und private PKI-Daten werden mit eingeschränkten
Berechtigungen angelegt. Diese Rechte sollten nicht gelockert werden, ohne die
Trennung der Dienstbenutzer `adpki` und `www-data` zu prüfen.

## Dienste

Die Installation verwaltet folgende systemd-Units:

```text
adpki-ca.service
adpki-worker.service
adpki-reverb.service
adpki-scheduler.service
adpki-scheduler.timer
```

Zusätzlich werden Nginx und `php8.4-fpm` benötigt.

## Logs und Fehlersuche

Installer- und Setup-Logs befinden sich unter:

```text
/var/log/adpki/installer/
/var/log/adpki/setup/
```

Nützliche Prüfungen:

```bash
sudo adpki status
sudo nginx -t
sudo journalctl -u adpki-ca.service -u adpki-worker.service \
  -u adpki-reverb.service --since today
```

Häufige Installationsprobleme:

- Apache oder ein anderer Dienst verwendet bereits Port 80 oder 443.
- Der DNS-Eintrag zeigt nicht auf den Server.
- Eingehender Port 80 ist blockiert und verhindert die Let's-Encrypt-Challenge.
- Der PostgreSQL-Benutzer darf die gewählte Datenbank nicht verändern.
- Zertifikat und privater Schlüssel gehören nicht zur selben Intermediate CA.

## Debian-Paket bauen

Debian-Paketwerkzeuge installieren:

```bash
sudo apt install build-essential debhelper devscripts
```

Paket bauen:

```bash
cd adpki-installer
dpkg-buildpackage -us -uc -b
```

Die Paketversion wird aus `debian/changelog` gelesen. Die erzeugten Dateien
`.deb`, `.buildinfo` und `.changes` werden im übergeordneten Verzeichnis
abgelegt:

```text
../
```

## Deinstallation

Paket entfernen:

```bash
sudo apt remove adpki
```

Paketverwaltete Konfiguration bereinigen:

```bash
sudo apt purge adpki
```

Anwendungsdaten bleiben absichtlich erhalten. Für eine vollständige Löschung
müssen folgende Verzeichnisse geprüft und manuell entfernt werden:

```text
/opt/adpki
/etc/adpki
/var/lib/adpki
/var/log/adpki
```

Vor dem Löschen müssen Datenbank, Konfiguration, Zertifikate und private
Schlüssel gesichert werden.

## Sicherheitshinweise

- Privaten Schlüssel der Root CA offline aufbewahren.
- Zugriff auf Intermediate-CA-Schlüssel und AD-PKI-Backups beschränken.
- Dedizierten Server verwenden und administrativen SSH-Zugriff begrenzen.
- Debian und AD-PKI-Komponenten aktuell halten.
- Datenbank und `/etc/adpki` regelmäßig sichern.
- Wiederherstellung testen, bevor die Installation produktiv verwendet wird.

## Lizenz

Copyright © 2024–2026 Ali Danakiran.

Dieses Projekt steht unter der GNU Affero General Public License, Version 3
oder neuer (`AGPL-3.0-or-later`). Siehe [`LICENSE`](LICENSE) und
[`adpki-installer/debian/copyright`](adpki-installer/debian/copyright).
