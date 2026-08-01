# AD-PKI APT repository operations

The official Debian repository is published by the release workflow at
`https://packages.adpki.de`. GitHub Pages serves the static repository; the
website at `https://adpki.de` remains independent.

## One-time GitHub configuration

In `alid-it/AD-PKI-Debian-Installer`:

1. Open **Settings → Pages** and select **GitHub Actions** as the source.
2. Configure `packages.adpki.de` as the custom domain.
3. Add the following Actions secrets:
   - `ADPKI_RELEASE_TOKEN`: token that may create and update releases in
     `alid-it/AD-PKI`.
   - `APT_SIGNING_PRIVATE_KEY`: ASCII-armored private repository signing key.
   - `APT_SIGNING_KEY_FINGERPRINT`: full fingerprint of that key.
   - `APT_SIGNING_KEY_PASSPHRASE`: passphrase of the private key.

At the DNS provider, create this record after the custom domain has been added
to the GitHub Pages settings:

```text
Type:   CNAME
Name:   packages
Target: alid-it.github.io
```

Do not use a wildcard record for the Pages domain.

## Create a dedicated signing key

Generate this key on a trusted administrator system, not in GitHub Actions:

```bash
gpg --quick-generate-key "AD-PKI Debian Repository <packages@adpki.de>" rsa4096 sign 2y
gpg --list-secret-keys --keyid-format long --with-subkey-fingerprint
gpg --armor --export-secret-keys <FULL-FINGERPRINT> > adpki-apt-private.asc
gpg --armor --export <FULL-FINGERPRINT> > adpki-archive-keyring.asc
```

Store the private export and its passphrase in a password manager or another
encrypted backup. Never commit the private key. Publish and archive the public
key and fingerprint so clients can verify it independently.

## Publish a release

Create and push the next version tag. The workflow then:

1. builds the versioned Debian package;
2. uploads it to the central AD-PKI GitHub release;
3. collects all versioned AD-PKI packages;
4. generates `Packages`, `Packages.gz`, and `Release`;
5. creates signed `InRelease` and `Release.gpg` metadata;
6. deploys the repository through GitHub Pages.

Before announcing a release, verify:

```bash
curl -fsSL https://packages.adpki.de/dists/stable/InRelease | gpg --show-keys
curl -fI https://packages.adpki.de/dists/stable/main/binary-amd64/Packages.gz
```

## Key rotation

Publish the replacement public key before signing exclusively with the new
key. Keep the old key available during a transition period. If the private key
is compromised, revoke it, stop publishing, replace all repository secrets,
and communicate the new fingerprint through `adpki.de` and the GitHub project.
