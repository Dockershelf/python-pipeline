# __PY_MINOR_DIR__

Debian packaging for CPython __PY_MINOR__: patches, `debiandirs/`, and changelog tracks used by the [Dockershelf python-pipeline](https://github.com/Dockershelf/python-pipeline).

## Supported Debian suites

- `trixie`
- `unstable`

Packaging trees live under `debiandirs/<suite>/`. Changelogs live under `changelogs/mainline/<suite>`.

## Build (from workspace)

Clone this repo as a sibling of `python-pipeline/`, then from `python-pipeline/`:

```bash
make materialize PY=__PY_MINOR__ DIST=trixie
make build PY=__PY_MINOR__ DIST=trixie
```

See the [operations manual](https://github.com/Dockershelf/python-pipeline/blob/main/docs/operations.md) for new lines, version bumps, and new suites.

## Layout

| Path | Purpose |
|------|---------|
| `cpython/` | Upstream CPython git submodule |
| `patches/` | Quilt series applied at materialize |
| `debiandirs/` | Per-suite Debian packaging (`trixie`, `unstable`) |
| `changelogs/mainline/` | Debian changelog history per suite |
