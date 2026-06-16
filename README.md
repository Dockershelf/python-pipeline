# Dockershelf Python packaging pipeline

Orchestration for building CPython into split Debian packages (`python3.13`, `libpython3.13-stdlib`, `python3.13-dev`, …) and publishing to a self-hosted APT repository.

Fork of [deadsnakes/runbooks](https://github.com/deadsnakes/runbooks), adapted for Debian (`trixie`, `unstable`) and Dockershelf hosting.

## Workspace layout

Clone this repo as a sibling of the `py3.*` packaging repos:

```text
deadsnakes-pipeline/
├── python-pipeline/     # this repo
├── py3.10/
├── py3.11/
├── …
└── py3.14/
```

## Quick start

```bash
cd python-pipeline
cp config.env.example config.env
make bootstrap
make build-tools-image    # gbp, dch, dpkg-parsechangelog
make build-builder-images
make materialize PY=3.13 DIST=trixie
make build PY=3.13
make publish DIST=trixie
```

## Build a single distribution

```bash
make materialize PY=3.13 DIST=trixie
make build PY=3.13
```

Output `.deb` files land in `dist/`.

## Generate builder Dockerfiles

```bash
make generate-dockerfiles
make build-builder-images
```

Builder images are tagged `dockershelf-python-builder/<suite>` (e.g. `dockershelf-python-builder/trixie`).

## Configuration

Copy `config.env.example` to `config.env`. Droplet APT hosting: [debian-repo-setup/README.md](debian-repo-setup/README.md). GitHub + DNS wiring: [docs/deploy-setup.md](docs/deploy-setup.md).

## Source repositories

| Local path (sibling) | Remote |
|----------------------|--------|
| `../py3.10/` … `../py3.14/` | `https://github.com/Dockershelf/py3.XX` |

`make bootstrap` clones any missing `py3.*` repos into the workspace parent directory.

## Operations manual

Step-by-step guides for maintainers:

- [Adding a new Python line (py3.15)](docs/operations.md#1-add-a-new-python-release-line-eg-py315)
- [Bumping Python patch version (3.14.x)](docs/operations.md#2-bump-python-patch-version-eg-3145--31456)
- [Adding a new Debian suite](docs/operations.md#3-add-a-new-debian-suite-eg-forky)

Full reference: [docs/operations.md](docs/operations.md)

## Continuous integration

GitHub Actions build GHCR builder images, run `meta-gbp update` / build / smoke test, and publish to the APT droplet. Setup: [docs/ci.md](docs/ci.md).
