# DigitalOcean Droplet — APT repository setup

Templates for hosting Dockershelf-built Python `.deb` packages with **reprepro** and **nginx** (Option A).

## Layout on the droplet

```text
/var/www/debian/
├── conf/
│   └── distributions          # from reprepro-distributions
├── incoming/                  # rsync target for new .deb files
├── dists/                     # reprepro-generated indices
└── pool/                      # reprepro package pool
```

## One-time server setup

1. **Packages**
   ```bash
   sudo apt-get update
   sudo apt-get install -y reprepro nginx gnupg rsync
   ```

2. **GPG key** (for signing `Release` files; export public key for image builds)
   ```bash
   gpg --full-generate-key
   gpg --list-secret-keys --keyid-format long
   ```

3. **Repository tree**
   ```bash
   sudo mkdir -p /var/www/debian/conf /var/www/debian/incoming
   sudo cp reprepro-distributions /var/www/debian/conf/distributions
   # Edit SignWith: lines with your key id
   sudo chown -R "$USER":"$USER" /var/www/debian
   ```

4. **Import script**
   ```bash
   sudo cp import-incoming.sh /usr/local/bin/dockershelf-import-incoming
   sudo chmod +x /usr/local/bin/dockershelf-import-incoming
   ```

5. **Nginx**
   ```bash
   sudo cp nginx-debian.conf /etc/nginx/sites-available/dockershelf-apt
   sudo ln -sf /etc/nginx/sites-available/dockershelf-apt /etc/nginx/sites-enabled/
   sudo nginx -t && sudo systemctl reload nginx
   sudo certbot --nginx -d apt.dockershelf.example
   ```

6. **Deploy user SSH access** — allow your CI/local machine to `rsync` into `/var/www/debian/incoming/`.

## Client apt line (Dockershelf images)

```text
deb [signed-by=/usr/share/keyrings/dockershelf-python.gpg] https://apt.dockershelf.example/debian trixie main
```

Use codename matching the image base (`trixie` or `unstable`).

## Publish flow (from local pipeline)

From `python-pipeline/` after `make build`:

```bash
make publish DIST=trixie
```

This rsyncs `dist/*.deb` to the droplet and runs `import-incoming.sh` over SSH.
