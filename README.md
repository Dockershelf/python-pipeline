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

Builder images are tagged `dockershelf-builder/<suite>` (e.g. `dockershelf-builder/trixie`).

## Configuration

Copy `config.env.example` to `config.env`. See `debian-repo-setup/README.md` for droplet APT hosting.

## Source repositories

| Local path (sibling) | Remote |
|----------------------|--------|
| `../py3.10/` … `../py3.14/` | `https://github.com/Dockershelf/py3.XX` |

`make bootstrap` clones any missing `py3.*` repos into the workspace parent directory.

## Future work

- GitHub Actions for `build-tools-image` and `build-builder-images`
- Debian smoke test (install `.deb` files from `dist/` on `trixie` / `unstable`)
- Operational runbooks for adding a new Python minor or Debian suite
