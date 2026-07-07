# GitHub Actions CI

Continuous integration for Dockershelf Python packaging: builder images on GHCR, scheduled
`meta-gbp update` / build / smoke test / APT publish across `py3.10`–`py3.14`.

Multi-arch (amd64 + arm64) is supported via the `arches` dispatch input and the
`arches-json` reusable-workflow input. arm64 jobs run on `ubuntu-24.04-arm` runners,
and `builder-images.yml` publishes `linux/amd64,linux/arm64` images via QEMU.
`trixie` is temporarily disabled in the committed `main.yml` files (`dists-json: '["unstable"]'`);
re-enable by restoring `'["trixie", "unstable"]'` once trixie builder images are ready.

## Workflows

| Workflow | Repo | Purpose |
|----------|------|---------|
| [`builder-images.yml`](../.github/workflows/builder-images.yml) | `python-pipeline` | Build and push `ghcr.io/dockershelf/dockershelf-python-builder/*` |
| [`update-meta-gbp.yml`](../.github/workflows/update-meta-gbp.yml) | `python-pipeline` | Reusable: update → build → smoke → publish |
| [`pr.yml`](../.github/workflows/pr.yml) | `python-pipeline` | `pre-commit` on pull requests |
| [`publish.yml`](../.github/workflows/publish.yml) | `python-pipeline` | Manual republish of local `dist/` to APT |
| [`main.yml`](https://github.com/Dockershelf/py3.14/blob/main/.github/workflows/main.yml) | each `py3.XX` | Weekly Tuesday schedule + dispatch → calls reusable workflow |

## CI workspace layout

```text
$GITHUB_WORKSPACE/
├── py3.14/              # triggering py repo
└── python-pipeline/     # orchestration checkout
```

Scripts:

- [`scripts/ci-setup-workspace.sh`](../scripts/ci-setup-workspace.sh) — submodule init, export GHCR image names
- [`scripts/ci-pull-builder-images.sh`](../scripts/ci-pull-builder-images.sh) — pull GHCR images or build locally
- [`scripts/debian-smoke-test.sh`](../scripts/debian-smoke-test.sh) — install `.deb`s in `debian:{suite}-slim`
- [`scripts/ci-publish.sh`](../scripts/ci-publish.sh) — rsync + `import-incoming.sh`
- [`scripts/ci-deploy-preflight.sh`](../scripts/ci-deploy-preflight.sh) — validate `DEPLOY_*` vars (optional `--connectivity`)

## GHCR images

| Image | Tag |
|-------|-----|
| `ghcr.io/dockershelf/dockershelf-python-builder/tools` | `latest`, `sha-<commit>` |
| `ghcr.io/dockershelf/dockershelf-python-builder/trixie` | `latest`, `sha-<commit>` |
| `ghcr.io/dockershelf/dockershelf-python-builder/unstable` | `latest`, `sha-<commit>` |

`builder-images.yml` pushes on push to `main`; pull requests build only (no push).

## Secrets and variables

Configure on **`Dockershelf/python-pipeline`** and each **`py3.XX`** repo (or at org level).

Run [`scripts/ci-check-config.sh`](../scripts/ci-check-config.sh) to list which secrets/variables are set (values are never printed). Use `--strict` to fail when deploy configuration is incomplete.

Full droplet + GitHub wiring: [`docs/deploy-setup.md`](deploy-setup.md).

### Secrets

| Name | Purpose |
|------|---------|
| `DEPLOY_SSH_KEY` | Private SSH key for `DEPLOY_USER@DEPLOY_HOST` |

### Repository variables

| Name | Example |
|------|---------|
| `DEPLOY_HOST` | `apt.dockershelf.com` |
| `DEPLOY_USER` | `deploy` |
| `DEPLOY_DIR` | `/var/www/debian` |
| `DEPLOY_INCOMING` | `/var/www/debian/incoming` |
| `DEBFULLNAME` | `Dockershelf Maintainer` |
| `DEBEMAIL` | `maintainer@example.com` |

Publish jobs run only when `publish` input is true **and** `DEPLOY_HOST` is set. When deploy variables are missing, build and smoke still run and the workflow summary notes that publish was skipped.

## GitHub settings

1. **`python-pipeline` → Settings → Actions → General**
   - Workflow permissions: read and write (for GHCR push).
   - Allow reuse of workflows by repos in the `Dockershelf` org.

2. **Each `py3.XX` repo**
   - Actions → access to `python-pipeline` reusable workflows.
   - Caller workflow needs `permissions: contents: write` (see each repo `main.yml`) so `meta-gbp update` commits can push with `GITHUB_TOKEN`.
   - Same secrets/variables as above (or inherit org-level).

3. **GHCR package visibility**
   - Link each `dockershelf-python-builder/*` package to `py3.10` … `py3.14` under **Package settings → Manage Actions access**, or make packages **public**.
   - Caller workflows use `permissions: packages: read`.
   - If `docker pull` is denied, CI builds from committed `dockerfiles/Dockerfile.*`.

## Schedule (UTC)

Packaging runs **weekly on Tuesday** (2 days before Dockershelf consumer images build on **Thursday** 06:00 UTC). Cron is staggered per Python line to reduce runner overlap:

| Repo | Cron | Notes |
|------|------|-------|
| py3.10 | `0 0 * * 2` | Tuesday 00:00 |
| py3.11 | `0 2 * * 2` | Tuesday 02:00 |
| py3.12 | `0 4 * * 2` | Tuesday 04:00 |
| py3.13 | `0 6 * * 2` | Tuesday 06:00 |
| py3.14 | `0 8 * * 2` | Tuesday 08:00 |

Scheduled runs publish when `DEPLOY_SSH_KEY` is configured. Use `workflow_dispatch` with `publish: false` to build and smoke-test only, and `arches` (JSON array, default `["amd64"]`) to select architectures. Multi-arch (amd64 + arm64) is supported: arm64 jobs run on `ubuntu-24.04-arm` runners, and `builder-images.yml` publishes `linux/amd64,linux/arm64` images via QEMU.

## Manual runs

**Full pipeline (py3.14):** Actions → packaging → Run workflow. Set `arches` to `["amd64","arm64"]` for multi-arch, or `["amd64"]` (default) for amd64 only.

**Republish existing debs:** `python-pipeline` → Actions → publish → choose suite (expects `dist/*.deb` checked in or uploaded to runner workspace — typically re-run build artifact flow instead).

## Failure modes

| Failure | Action |
|---------|--------|
| `meta-gbp update` rebase conflict | Resolve locally, push fix, re-run workflow |
| Builder image pull fails | CI falls back to `make build-tools-image build-builder-images` (slow) |
| Smoke test `apt-get -f install` fails | Check missing runtime deps in generated `.deb` set |
| Publish SSH/rsync fails | Verify `DEPLOY_*` variables and `DEPLOY_SSH_KEY` |
| arm64 runner unavailable | `ubuntu-24.04-arm` runners are GitHub-hosted; ensure `arches` only includes `arm64` when repo/plan supports it |

## Reference py for Dockerfiles

`make generate-dockerfiles` uses `DOCKERSHELF_REFERENCE_PY` (default `3.13`). When `debiandirs/*/control` changes materially in another line, bump the reference or regenerate builder images after merging control changes into `py3.13`.