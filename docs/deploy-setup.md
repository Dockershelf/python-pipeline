# APT deploy setup

End-to-end checklist to wire GitHub Actions publish to the DigitalOcean APT droplet.
No packaging run is required to complete these steps.

Public repository URL: **`https://apt.dockershelf.com/dockershelf/`**

## Architecture

```text
py3.XX workflow  →  update-meta-gbp.yml  →  build  →  smoke  →  publish
                                                                    │
                                                                    ├─ rsync → /var/www/debian/incoming/
                                                                    └─ SSH  → import-incoming.sh → reprepro
                                                                                    │
                                                                              nginx /dockershelf/
```

## 1. DNS

Create an **A** record:

| Name | Value |
|------|-------|
| `apt.dockershelf.com` | Droplet public IP (e.g. `159.223.128.61`) |

Verify: `dig +short apt.dockershelf.com`

## 2. Droplet bootstrap

On your local machine:

```bash
cd debian-repo-setup
./create-ci-deploy-key.sh ./keys
```

Copy `debian-repo-setup/` to the droplet, then as **root**:

```bash
export DEPLOY_PUBLIC_KEY="$(cat keys/dockershelf-deploy-ci.pub)"
./bootstrap-droplet.sh
```

See [`debian-repo-setup/README.md`](../debian-repo-setup/README.md) for layout and manual fallback.

Enable TLS when DNS resolves:

```bash
sudo certbot --nginx -d apt.dockershelf.com
```

## 3. GitHub secrets

Store the **private** CI key as `DEPLOY_SSH_KEY` at **org** level (recommended) or on each repo:

```bash
gh secret set DEPLOY_SSH_KEY --org Dockershelf < keys/dockershelf-deploy-ci
```

Org secrets are inherited by `python-pipeline` and all `py3.*` repos when access is granted.

## 4. GitHub variables

Set at org level (recommended) or per repo:

| Variable | Value |
|----------|-------|
| `DEPLOY_HOST` | `apt.dockershelf.com` |
| `DEPLOY_USER` | `deploy` |
| `DEPLOY_DIR` | `/var/www/debian` |
| `DEPLOY_INCOMING` | `/var/www/debian/incoming` |

```bash
gh variable set DEPLOY_HOST --org Dockershelf --body "apt.dockershelf.com"
gh variable set DEPLOY_USER --org Dockershelf --body "deploy"
gh variable set DEPLOY_DIR --org Dockershelf --body "/var/www/debian"
gh variable set DEPLOY_INCOMING --org Dockershelf --body "/var/www/debian/incoming"
```

## 5. Verify configuration

```bash
./scripts/ci-check-config.sh --strict
```

This exits non-zero if `DEPLOY_SSH_KEY` or required variables are missing on any tracked repo.

## 6. Connectivity test (optional)

In GitHub: **python-pipeline → Actions → Deploy connectivity → Run workflow**.

Requires `DEPLOY_SSH_KEY` and all `DEPLOY_*` variables. Does not upload packages.

## 7. Full pipeline test (optional, later)

1. Ensure [`builder-images.yml`](../.github/workflows/builder-images.yml) has populated GHCR (or CI will build images locally).
2. **py3.14 → Actions → packaging → Run workflow** with `publish: true`.
3. On the droplet after publish:
   ```bash
   curl -I https://apt.dockershelf.com/dockershelf/dists/trixie/Release
   ```

## Local publish

Copy `config.env.example` to `config.env`, set deploy values, then:

```bash
make build PY=3.14
make publish DIST=trixie
```

`make publish` uses the same rsync + `import-incoming.sh` path as CI.

## Client apt source

```text
deb [signed-by=/usr/share/keyrings/dockershelf.gpg] https://apt.dockershelf.com/dockershelf trixie main
```

Export the signing key from the droplet (`/var/www/debian/dockershelf-apt-signing.pub`) for image builds and client setup.

## Troubleshooting

| Symptom | Check |
|---------|--------|
| Publish job skipped | `DEPLOY_SSH_KEY` unset — workflow summary notes this; build/smoke still run |
| Preflight fails on empty var | Set all four `DEPLOY_*` variables |
| SSH permission denied | Public key in `~deploy/.ssh/authorized_keys` from bootstrap |
| `reprepro` signing error | `GNUPGHOME=/var/www/debian/.gnupg` on droplet; re-run bootstrap |
| 404 on Release URL | DNS/TLS, nginx `/dockershelf/` alias, or no packages published yet |

See also [`docs/ci.md`](ci.md).
