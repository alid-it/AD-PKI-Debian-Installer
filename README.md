# AD-PKI Debian Installer

[English](README.md) | [Deutsch](README.de.md)

The AD-PKI Debian Installer deploys and configures the AD-PKI platform on a
dedicated Debian server. It installs the required runtime, downloads verified
releases of the AD-PKI components, prepares the filesystem and systemd
services, and guides the administrator through the initial PKI setup.

> [!IMPORTANT]
> This project is intended for dedicated systems. The installer changes the
> web server, PHP, PostgreSQL, NTP, systemd, package repositories, and firewall-
> relevant ports of the host.

## Architecture

AD-PKI consists of three application components:

- **Frontend:** Vue-based web interface
- **Backend:** Laravel API, workers, scheduler, and Reverb service
- **CA Core:** Go service for PKI operations

Installation is deliberately split into two stages:

1. `adpki-install` installs the runtime and application components.
2. `adpki-setup` configures the database, imports the CA material, enables TLS,
   and creates the first administrator.

The installer does **not** generate a Root CA or Intermediate CA. Both
certificates must already exist. The Root CA private key must remain offline
and is never requested by the setup wizard.

## Requirements

- Debian 13 (Trixie)
- `amd64` architecture for the current Debian package
- Root access
- A dedicated host or VM with systemd
- Internet access during installation
- Ports `80/tcp` and `443/tcp` available
- A DNS name resolving to the server for Let's Encrypt
- An existing Root CA certificate
- An existing Intermediate CA certificate and its private key
- A PostgreSQL 17 server, or permission to install one locally

The runtime installer currently uses:

| Component | Version policy |
| --- | --- |
| PHP | 8.4.x, at least 8.4.16 |
| PostgreSQL | 17.x, at least 17.9 |
| Node.js | 24.15.0 |
| Web server | Nginx |

The CA Core, Backend, and Frontend are downloaded from the latest GitHub
releases published by the `alid-it` organization. Release archives are checked
against their published `SHA256SUMS`.

## Installation

### 1. Install the Debian package

Download or build the package, then install it:

```bash
sudo apt install ./adpki_<version>_amd64.deb
```

Installing the package adds the AD-PKI commands, configuration templates,
systemd units, and installer scripts. It does not install the complete runtime
yet.

### 2. Install the runtime

```bash
sudo adpki-install
```

Select one of the PostgreSQL modes when prompted:

- **Existing PostgreSQL server:** use an existing local or remote server.
- **New local PostgreSQL server:** install and configure PostgreSQL on the
  AD-PKI host.

This stage installs Nginx, PHP, PostgreSQL client or server, Composer, and
Node.js. It then downloads and deploys the AD-PKI components.

### 3. Run the initial setup

```bash
sudo adpki-setup
```

The setup wizard performs the following tasks:

1. Validates the host and installed runtime.
2. Creates the application configuration and secrets.
3. Configures and tests the PostgreSQL connection.
4. Runs Laravel migrations and seeders.
5. Imports the Root CA certificate.
6. Imports the Intermediate CA certificate and private key.
7. Displays client trust instructions.
8. Obtains a Let's Encrypt certificate and enables HTTPS.
9. Creates the first administrator and selects their interface language.
10. Enables and checks all AD-PKI services.

After a successful setup, open:

```text
https://<your-adpki-domain>
```

## Administrator language

The frontend default is English. During initial setup, the administrator can
choose German or one of the other supported account languages. The selected
locale is stored on the administrator account.

## CLI commands

```bash
sudo adpki status
sudo adpki restart
sudo adpki logs
sudo adpki update
```

| Command | Purpose |
| --- | --- |
| `adpki status` | Show the status of Nginx, PHP-FPM, and AD-PKI services |
| `adpki restart` | Restart the AD-PKI runtime services |
| `adpki logs` | Follow the systemd logs of the application services |
| `adpki update` | Update CA Core, Backend, and Frontend from GitHub releases |

The updater asks for confirmation, checks SHA-256 sums, runs pending database
migrations, and attempts to create a database backup before changing the
installed components.

## Files and directories

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

Configuration files and private PKI data are created with restricted
permissions. Do not relax these permissions without reviewing the service
user separation between `adpki` and `www-data`.

## Services

The installation manages these systemd units:

```text
adpki-ca.service
adpki-worker.service
adpki-reverb.service
adpki-scheduler.service
adpki-scheduler.timer
```

Nginx and `php8.4-fpm` are also required.

## Logs and troubleshooting

Installer and setup logs are stored under:

```text
/var/log/adpki/installer/
/var/log/adpki/setup/
```

Useful checks:

```bash
sudo adpki status
sudo nginx -t
sudo journalctl -u adpki-ca.service -u adpki-worker.service \
  -u adpki-reverb.service --since today
```

Common installation blockers:

- Apache or another service is already using port 80 or 443.
- The DNS record does not resolve to the server.
- Inbound port 80 is blocked, preventing the Let's Encrypt challenge.
- The PostgreSQL user cannot create or modify the selected database.
- The supplied certificate and private key do not form a valid Intermediate
  CA pair.

## Build the Debian package

Install the Debian packaging tools:

```bash
sudo apt install build-essential debhelper devscripts
```

Build the package:

```bash
cd adpki-installer
dpkg-buildpackage -us -uc -b
```

The package version is read from `debian/changelog`. The resulting `.deb`,
`.buildinfo`, and `.changes` files are written to the parent directory:

```text
../
```

## Removal

Remove the package:

```bash
sudo apt remove adpki
```

Purge package-managed configuration:

```bash
sudo apt purge adpki
```

Application data is intentionally retained. If complete deletion is required,
review and remove these directories manually:

```text
/opt/adpki
/etc/adpki
/var/lib/adpki
/var/log/adpki
```

Back up the database, configuration, certificates, and private keys before
removing any data.

## Security notes

- Keep the Root CA private key offline.
- Restrict access to the Intermediate CA private key and AD-PKI backups.
- Use a dedicated server and limit administrative SSH access.
- Keep Debian and AD-PKI components updated.
- Back up the database and `/etc/adpki` regularly.
- Test restore procedures before relying on the installation in production.

## License

Copyright © 2024–2026 Ali Danakiran.

This project is licensed under the AGPL-3.0. See [`LICENSE`](LICENSE) and
[`adpki-installer/debian/copyright`](adpki-installer/debian/copyright).
