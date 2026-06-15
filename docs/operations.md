# Operations manual

How to add a new Python release line, bump an existing Python version, or add a new Debian suite to the Dockershelf packaging pipeline.

**Workspace:** run commands from `python-pipeline/` unless noted. Each `py3.XX/` repo is a sibling in the parent directory (`deadsnakes-pipeline/`).

**Version string format:** Debian package versions look like `3.14.5-1+trixie3`:

| Part | Meaning |
|------|---------|
| `3.14.5` | Upstream CPython version |
| `-1` | Debian packaging revision |
| `+trixie3` | Suite-specific rebuild counter (`trixie` codename + `3` = third rebuild for that suite) |

---

## Prerequisites

```bash
cd python-pipeline
cp config.env.example config.env   # once
make bootstrap
make build-tools-image
```

### Maintainer identity and package metadata

**Changelog entries** (`meta-gbp changelog`, `meta-gbp update`) use `DEBFULLNAME` and `DEBEMAIL` when set in `config.env`; otherwise `git config user.name` and `git config user.email` (via `docker-run`).

**`debian/control.in` and `debian/control`** in each `py3.XX` repo should list:

- `Maintainer:` — same identity as above
- `Vcs-Browser:` / `Vcs-Git:` — `https://github.com/Dockershelf/py3.XX` (not Debian salsa)

Keep `control.in` and `control` in sync. After bulk updates:

```bash
./scripts/retarget-py3-control.sh   # from python-pipeline/
```

**Packaging-only mainline changelog** (no upstream bump): `meta-gbp changelog -m '...' --only trixie`. If legacy changelog formatting breaks `dch`, use:

```bash
python3 scripts/bump-mainline-changelog.py -m 'Your message.' ..
```

---

## 1. Add a new Python release line (e.g. py3.15)

Use this when Dockershelf should ship a **new `py3.XX` repo** (first time packaging Python 3.15).

### 1.1 Create the packaging repository

1. Create `Dockershelf/py3.15` on GitHub (empty repo).
2. Seed from the closest existing line, usually the previous minor:

   ```bash
   cd ..   # deadsnakes-pipeline workspace root
   git clone https://github.com/Dockershelf/py3.14.git py3.15
   cd py3.15
   git remote set-url origin https://github.com/Dockershelf/py3.15.git
   ```

3. Reset history (recommended for a clean fork) or keep history — either works if content is correct.

### 1.2 Repoint cpython and retarget packaging metadata

```bash
cd py3.15
git submodule update --init cpython
git -C cpython fetch origin
git -C cpython checkout 3.15   # or the appropriate release branch
git add cpython
```

Update **every** file under `debiandirs/` and `changelogs/` that still says `3.14` → `3.15` (package names, paths, `VER=` in `debian/rules` templates). Practical approach:

- Copy `debiandirs/trixie` and `debiandirs/unstable` from a freshly validated tree, or
- Run a careful search-replace on `python3.14` → `python3.15`, `libpython3.14` → `libpython3.15`, etc.

Ensure both suites exist and match:

```text
debiandirs/trixie/
debiandirs/unstable/
changelogs/mainline/trixie
changelogs/mainline/unstable
```

Set initial changelog versions, e.g. `3.15.0-1+trixie1` and `3.15.0-1+unstable1`, with `distribution:` set to `trixie` / `unstable`.

Review `patches/series` — drop or refresh patches that no longer apply to 3.15.

Commit and push to `Dockershelf/py3.15`.

### 1.3 Register the repo in python-pipeline

Edit [`Makefile`](../Makefile) — add `3.15` to `PY_VERSIONS`:

```makefile
PY_VERSIONS := 3.10 3.11 3.12 3.13 3.14 3.15
```

`make bootstrap` will clone `py3.15` on fresh machines.

### 1.4 Build and publish

```bash
cd ../python-pipeline
make bootstrap
make list-dists                    # should show py3.15: trixie unstable

make materialize PY=3.15 DIST=trixie
make build PY=3.15
make publish DIST=trixie

make materialize PY=3.15 DIST=unstable
make build PY=3.15
make publish DIST=unstable
```

### 1.5 Downstream (Dockershelf images)

After packages are in your APT repo, update the main `dockershelf` repo separately:

- Shelf lists / `scripts/discover_shelf_versions.py`
- `python/build-image.sh` apt source and version pins

---

## 2. Bump Python patch version (e.g. 3.14.5 → 3.14.56)

Use this when **upstream CPython** releases a new patch and you want new `.deb` packages for an existing `py3.14` repo.

### 2.1 Update cpython and packaging tree

```bash
cd ../py3.14
git submodule update --init cpython
../python-pipeline/meta-gbp update
```

`meta-gbp update`:

1. Fetches the next CPython revision to import.
2. Rebases `patches/` via `gbp pq`.
3. Writes new changelog entries for **every** suite in `changelogs/mainline/`.

If the patch queue does not rebase cleanly, resolve conflicts interactively (default). To fail fast instead of opening a shell:

```bash
../python-pipeline/meta-gbp update --no-interactive
```

If that exits with a rebase conflict, run again **without** `--no-interactive` and fix conflicts under `work/`.

Or pin a specific commit:

```bash
../python-pipeline/meta-gbp update --rev <cpython-sha>
```

Review the generated changelog diff, then commit if `meta-gbp update` left changes unstaged (it usually commits automatically).

### 2.2 Build and publish per suite

```bash
cd ../python-pipeline

make materialize PY=3.14 DIST=trixie
make build PY=3.14
make publish DIST=trixie
```

Repeat for `unstable` (or any other suite) as needed.

### 2.3 Packaging-only rebuild (same upstream version)

If you changed **Debian packaging** (control, rules, patches) but **not** the CPython tarball version, bump only the `+suiteN` counter:

```bash
cd ../py3.14
../python-pipeline/meta-gbp changelog --only trixie -m 'Rebuild for trixie: fix control deps'
git add changelogs && git commit -m 'changelog: trixie rebuild'
```

Then `materialize` → `build` → `publish` for that suite.

---

## 3. Add a new Debian suite (e.g. `forky`)

Use this when Dockershelf images target a **new Debian codename** in addition to `trixie` and `unstable`.

### 3.1 Packaging repos (`py3.10` … `py3.14`)

For **each** `py3.XX` you intend to support on the new suite:

1. **Seed `debiandirs/<codename>/`** — copy from the closest existing suite and adjust:
   - `control` / `control.in` — `Build-Depends` may differ per Debian release.
   - `rules`, maintainer scripts, tests as needed.

   ```bash
   cd py3.13/debiandirs
   cp -a trixie forky
   # edit forky/control, forky/rules, …
   ```

2. **Add changelogs:**

   ```bash
   cp changelogs/mainline/trixie changelogs/mainline/forky
   # edit distribution field and version suffix: 3.13.x-1+forky1
   ```

3. Commit and push each `Dockershelf/py3.XX` repo.

### 3.2 python-pipeline configuration

Edit `config.env` (and [`config.env.example`](../config.env.example)):

```bash
DOCKERSHELF_SUITES=trixie unstable forky
```

Regenerate and build the builder image for the new suite:

```bash
make generate-dockerfiles
make build-builder-images
```

This produces `dockershelf-builder/forky` and `dockerfiles/Dockerfile.forky`.

### 3.3 APT repository (droplet)

Edit [`debian-repo-setup/reprepro-distributions`](../debian-repo-setup/reprepro-distributions) — add a stanza:

```text
Origin: Dockershelf
Label: Dockershelf Python
Suite: stable
Codename: forky
Architectures: amd64 arm64 source
Components: main
Description: Dockershelf Python packages for Debian forky
SignWith: SIGNWITH_KEY_ID
```

Deploy to the droplet (`conf/distributions`), then publish packages:

```bash
make materialize PY=3.13 DIST=forky
make build PY=3.13
make publish DIST=forky
```

### 3.4 Verify

```bash
make list-dists    # py3.13: trixie unstable forky
```

On a Debian `forky` machine:

```text
deb [signed-by=…] https://apt.luisalejandro.org/dockershelf forky main
apt update && apt install python3.13
```

---

## Quick reference

| Goal | Where | Key command |
|------|--------|-------------|
| New `py3.XX` repo | GitHub + each py repo | Fork py3.(N-1), retarget metadata |
| Register py version | `python-pipeline/Makefile` | Add to `PY_VERSIONS` |
| New upstream patch | `py3.XX/` | `meta-gbp update` |
| Packaging rebuild | `py3.XX/` | `meta-gbp changelog --only <suite> -m '…'` |
| Materialize gbp tree | `python-pipeline/` | `make materialize PY=3.14 DIST=trixie` |
| Binary build | `python-pipeline/` | `make build PY=3.14` |
| Publish to APT | `python-pipeline/` | `make publish DIST=trixie` |
| New Debian suite | All py repos + config + reprepro | `DOCKERSHELF_SUITES`, `generate-dockerfiles` |

---

## Troubleshooting

**`meta-gbp update` rebase fails** — run with interactive mode; fix conflicts under `work/`, complete rebase, exit 0 so `gbp pq export` runs.

**`make materialize` fails validation** — each suite under `changelogs/mainline/` needs a matching `debiandirs/<suite>/`. The `cpython` submodule must be at an upstream **release tag**, not a post-tag development snapshot.

**Build fails on `mk-build-deps`** — regenerate builder image: `make generate-dockerfiles && make build-builder-images`. Suite `control` Build-Depends may need tuning for Debian.

**`make publish` finds no `.deb` files** — artifacts land in `python-pipeline/dist/` after `make build`.
