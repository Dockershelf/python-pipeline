# DigitalOcean Droplet — APT repository setup

Templates and scripts for hosting Dockershelf-built `.deb` packages with **reprepro** and **nginx**.

Public URL: **`https://apt.luisalejandro.org/dockershelf/`**

## Layout on the droplet

```text
/var/www/debian/
├── .gnupg/                    # reprepro Release signing key (deploy user)
├── conf/
│   └── distributions          # from reprepro-distributions
├── incoming/                  # rsync target for new .deb files
├── dists/                     # reprepro-generated indices
├── pool/                      # reprepro package pool
└── dockershelf-apt-signing.pub  # exported public key (for clients / image builds)
```

## Quick start (recommended)

On your **local machine**, generate a CI deploy key:

```bash
cd debian-repo-setup
./create-ci-deploy-key.sh ./keys
```

Copy this directory to the droplet (or clone `python-pipeline`), then on the **droplet as root**:

```bash
export DEPLOY_PUBLIC_KEY="$(cat keys/dockershelf-deploy-ci.pub)"
./bootstrap-droplet.sh
```

Configure DNS (`apt.luisalejandro.org` A record → droplet IP), TLS, and GitHub secrets — see [`docs/deploy-setup.md`](../docs/deploy-setup.md).

## Publish flow

From CI or `python-pipeline/` after `make build`:

```bash
make publish DIST=trixie
```

This rsyncs `dist/*.deb` to the droplet and runs `import-incoming.sh` over SSH.

## Client apt line

```text
deb [signed-by=/usr/share/keyrings/dockershelf-python.gpg] https://apt.luisalejandro.org/dockershelf trixie main
```

Use codename matching the image base (`trixie` or `unstable`).

Install the signing public key on clients:

```bash
curl -fsSL https://apt.luisalejandro.org/dockershelf/dockershelf-apt-signing.pub \
  | gpg --dearmor | sudo tee /usr/share/keyrings/dockershelf-python.gpg >/dev/null
```

(Adjust URL if you copy the key elsewhere.)

## Manual setup (appendix)

If you prefer not to use `bootstrap-droplet.sh`:

1. **Packages**
   ```bash
   sudo apt-get update
   sudo apt-get install -y reprepro nginx gnupg rsync
   ```

2. **GPG key** (for signing `Release` files)
   ```bash
   gpg --full-generate-key
   gpg --list-secret-keys --keyid-format long
   ```

3. **Repository tree**
   ```bash
   sudo mkdir -p /var/www/debian/conf /var/www/debian/incoming
   sudo cp reprepro-distributions /var/www/debian/conf/distributions
   # Edit SignWith: lines with your key id
   sudo chown -R deploy:deploy /var/www/debian
   ```

4. **Import script**
   ```bash
   sudo cp import-incoming.sh /usr/local/bin/dockershelf-import-incoming
   sudo chmod +x /usr/local/bin/dockershelf-import-incoming
   ```

5. **Nginx** — use [`nginx-debian.conf`](nginx-debian.conf) or re-run `bootstrap-droplet.sh` for the site block only.

6. **TLS**
   ```bash
   sudo certbot --nginx -d apt.luisalejandro.org
   ```

7. **Deploy user SSH** — add CI public key to `~deploy/.ssh/authorized_keys`.

## Files in this directory

| File | Purpose |
|------|---------|
| [`bootstrap-droplet.sh`](bootstrap-droplet.sh) | Idempotent droplet setup |
| [`create-ci-deploy-key.sh`](create-ci-deploy-key.sh) | Generate `DEPLOY_SSH_KEY` key pair |
| [`import-incoming.sh`](import-incoming.sh) | `reprepro includedeb` for incoming `.deb`s |
| [`nginx-debian.conf`](nginx-debian.conf) | Nginx template for `/dockershelf/` |
| [`reprepro-distributions`](reprepro-distributions) | `trixie` + `unstable` suites (amd64) |
