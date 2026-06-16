# Python pipeline — remaining gaps

Status as of 2026-06-16 after gaps 1–6 implementation pass.

Use this document for inline review comments. Each gap is numbered and grouped by priority.

---

## Resolved (gaps 1–6, Luis comments)

| Gap | Resolution |
|-----|------------|
| **1** | Weekly **Tuesday** crons (`0–40 3 * * 2` UTC stagger) on all `py3.10`–`py3.14`; packaging re-dispatched for py3.11–3.13 after build fix |
| **2** | `python/build-image.sh` rewritten to install from `apt.luisalejandro.org/dockershelf` (GPG key `0F6CBFE94AA83A5E`); PPA/mime-support removed |
| **3** | Cron root cause: `mk-build-deps` on read-only `/code` mount — fixed in `build` via `/tmp/build-deps` |
| **4** | Renamed to `ghcr.io/dockershelf/dockershelf-python-builder/*`; builder workflow pushed images (private; CI pulls via `docker login`) |
| **5** | `import-incoming.sh`: fixed `$?` capture, proactive remove, import summary |
| **6** | Added `scripts/seed-py-repo.sh`; `docs/operations.md` updated |

**Follow-up:** Confirm py3.11–3.13 packaging runs complete and APT index updated. Set GHCR packages **public** in org settings if unauthenticated `docker pull` is required.

---

## High — coverage and consumers

### 1. py3.10–py3.13 never run in CI

**What:** Workflows and staggered crons exist on all `py3.10`–`py3.14` repos (`09:45`–`10:05` UTC), but only **py3.14** has packaging workflow runs. py3.10–py3.13 show zero runs in GitHub Actions history.

**Impact:** APT repo (`https://apt.luisalejandro.org/dockershelf`) currently indexes **only Python 3.14** packages. Older lines are not built or published.

**Evidence:**

- `gh run list --repo Dockershelf/py3.10` (and py3.11–py3.13) — empty
- `Packages.gz` for trixie has `python3.14` but no `python3.10`–`python3.13`

**Suggested next step:** Dispatch py3.13 with `publish: false` (build + smoke only), then widen to py3.12 → py3.10.

*Luis Comment*: run the rest of the python versions. Also, daily builds are not necessary because dockershelf doesnt build the images on a daily basis. modify the crons to run only as often as the images are built.

---

### 2. Dockershelf Python images don’t use this APT repo

**What:** `python/build-image.sh` in the main Dockershelf repo still installs Python from the **deadsnakes PPA** (Ubuntu noble keys + PPA sources), not from `apt.luisalejandro.org/dockershelf`.

**Impact:** Packaging pipeline output is not consumed by published Docker images. Node images already support `DOCKERSHELF_APT_URL`; Python does not.

**Evidence:**

- `python/build-image.sh` — `DEADSNAKESPPA`, `keyserver.ubuntu.com`, noble release logic
- No `DOCKERSHELF_APT_URL` or `apt.luisalejandro.org` references under `python/`

**Suggested next step:** Mirror the node `build-image.sh` pattern — add APT source, signing key, and package install from Dockershelf repo.

*Luis Comment*: modify the build-image.sh to use the apt.luisalejandro.org repo instead of the deadsnakes PPA. Also, we can delete a lot of the code that is not needed (mime-support-dummy, UBUNTU_RELEASE logic, etc.)

---

### 3. Scheduled crons unproven in production

**What:** Each `py3.XX` repo `main.yml` schedules daily packaging with `publish: true` on cron (staggered UTC). Only manual `workflow_dispatch` on py3.14 has completed successfully.

**Impact:** Unknown whether cron-triggered runs behave the same as manual dispatch (permissions, concurrency, publish timing, runner availability).

**Evidence:**

- py3.14 cron: `5 10 * * *`
- py3.10–py3.13 crons: `45 9`, `50 9`, `55 9`, `0 10` UTC respectively
- No cron-triggered runs in history as of last scan

**Suggested next step:** Let crons fire once, then verify APT index and workflow summaries for all repos.

*Luis Comment*: I think the crons ran and they failed. Figure out why and fix it.

---

## Medium — efficiency and operations

### 4. GHCR pull still denied

**What:** CI logs in successful py3.14 builds show `Error response from daemon: denied` when pulling `ghcr.io/dockershelf/dockershelf-builder/*`. `ci-pull-builder-images.sh` falls back to building images locally from committed Dockerfiles.

**Impact:** Extra ~2+ minutes per image per job. Every packaging run rebuilds builder images instead of pulling cached GHCR layers.

**Evidence:**

- Build job log (py3.14 run `27523814722`): `pull failed for ghcr.io/dockershelf/dockershelf-builder/tools` → `falling back to local docker build`
- `scripts/ci-check-config.sh` notes: link `dockershelf-builder/*` packages to py3.* repos or make public

**Suggested next step:** GHCR package settings — grant `py3.*` repos read access, or make builder images public.

*Luis Comment*: its important to pull the builder images from the public repository instead of building them locally. Find out why the pull is denied and fix it. Also, i think we have to change the builder image name to dockershelf-python-builder to match the naming convention of the other builder images.

---

### 5. reprepro first-attempt noise (retry masks failures)

**What:** Trixie publish logged `cannot be included` for several packages on first `reprepro includedeb`. `import-incoming.sh` retry logic (`remove` + second `includedeb`) recovered; job stayed green and final index looks complete.

**Impact:** Transient or real conflicts may be hidden behind retry. Logs look alarming even on success. Harder to tell partial publish from full publish without droplet inspection.

**Evidence:**

- py3.14 publish (trixie) job logs — reprepro errors before retry
- Post-publish `Packages.gz` — full `python3.14` + `libpython3.14-*` set present

**Suggested next step:** Harden `import-incoming.sh` — fail fast on unrecoverable errors, summarize which packages needed retry, optional post-import verification.

*Luis Comment*: figure out if reprepro errors are fatal and fix them. Leave alone if they are just warnings. Try to fix the errors also if they are nice to have.

---

### 6. No seed-py-repo.sh

**What:** Adding a new Python release line is documented manually in `docs/operations.md` (clone py3.14, retarget metadata, submodule checkout). Node pipeline has `scripts/seed-node-repo.sh` for equivalent automation.

**Impact:** Higher friction and error rate when spinning up py3.15+ or re-seeding a repo. No scripted validation of required files.

**Evidence:**

- `docs/operations.md` §1 — manual clone/repoint steps
- `node-pipeline/scripts/seed-node-repo.sh` exists; no `seed-py-repo.sh` in python-pipeline

**Suggested next step:** Add `scripts/seed-py-repo.sh` modeled on node seed script + operations doc update.

*Luis Comment*: add a seed-py-repo.sh script to the python-pipeline.

---

### 7. publish.yml is a weak escape hatch

**What:** Standalone `publish.yml` on `python-pipeline` expects `dist/*.deb` in the **python-pipeline repo checkout**. It does not download artifacts from a packaging workflow run.

**Impact:** Cannot republish from a failed publish step without manually obtaining `.deb` files. Workflow is only useful if someone commits or uploads debs to `dist/` in that repo (unusual).

**Evidence:**

- `.github/workflows/publish.yml` — `debs=(dist/*.deb)` check on checkout root
- Main publish path is `update-meta-gbp.yml` publish job with artifact download

**Suggested next step:** Either wire `publish.yml` to accept workflow artifacts / manual upload, or document deprecate in favor of re-dispatching packaging with `publish: true`.

---

## Lower — hygiene and verification

### 8. pr.yml never exercised

**What:** `python-pipeline` has `pr.yml` running pre-commit on pull requests. Remote repo has `.pre-commit-config.yaml`. No PR workflow runs in GitHub history.

**Impact:** Pre-commit hooks untested in CI. Regressions in yaml/python formatting could land on `main` undetected until a PR is opened.

**Evidence:**

- `gh run list --repo Dockershelf/python-pipeline --workflow "Pull request"` — empty
- `.pre-commit-config.yaml` exists on GitHub remote

**Suggested next step:** Open a trivial PR to verify `pr.yml`, or run pre-commit locally in CI on push to main.

---

### 9. DEBFULLNAME / DEBEMAIL not customized

**What:** Optional repo variables `DEBFULLNAME` and `DEBEMAIL` are not set. CI uses defaults: `Dockershelf Maintainer` and `41898282+github-actions[bot]@users.noreply.github.com`.

**Impact:** Changelog and git commit attribution show bot identity instead of a human maintainer. Functional, not blocking.

**Evidence:**

- `update-meta-gbp.yml` — `vars.DEBFULLNAME || 'Dockershelf Maintainer'`
- `ci-check-config.sh` lists these as optional

**Suggested next step:** Set org- or repo-level variables if branded maintainer strings are desired.

---

### 10. End-user apt install not verified

**What:** Release URLs and `Packages.gz` index verified via curl. No test from a clean Debian container using the documented client `sources.list` + signing key.

**Impact:** TLS, nginx, reprepro, and signing may work for metadata fetch but `apt install python3.14` could still fail (keyring path, suite name, dependency resolution).

**Evidence:**

- `curl -I https://apt.luisalejandro.org/dockershelf/dists/trixie/Release` — 200
- `deploy-setup.md` client apt source documented; no automated smoke on consumer side

**Suggested next step:** Add consumer smoke test script or CI job: `docker run debian:trixie-slim`, add repo, `apt install python3.14`, run `python3.14 --version`.

---

### 11. CI cost at scale

**What:** py3.14 build jobs run ~33 minutes per suite (trixie and unstable in parallel). Five repos × two suites × daily cron ≈ substantial GitHub Actions runner hours once all crons are active.

**Impact:** Cost and queue time grow linearly with number of Python lines. No shared build cache across repos beyond GHCR builder images (which are currently rebuilt locally anyway).

**Evidence:**

- py3.14 run `27523814722` job timings: build (trixie) ~32 min, build (unstable) ~33 min
- Five staggered crons configured

**Suggested next step:** Fix GHCR pulls (gap 4), consider build-only-on-upstream-change logic, or reduce cron frequency for older Python lines.

---

### 12. Local workspace drift

**What:** Local `deadsnakes-pipeline/python-pipeline/` checkout is out of sync with GitHub `Dockershelf/python-pipeline`. Only 3 scripts on disk locally vs full set on remote. Uncommitted edits and deleted legacy scripts not pushed.

**Impact:** Local development and docs may reference files that exist only on remote (or vice versa). Risk of editing stale tree.

**Evidence (local):**

- `scripts/` — only `ci-publish.sh`, `ci-deploy-preflight.sh`, `ci-check-config.sh`
- GitHub remote `scripts/` — includes `ci-setup-workspace.sh`, `debian-smoke-test.sh`, `fix-changelog-headings.sh`, `retarget-py3-control.sh`, etc.
- `git status` — modified `config.env.example`, `docs/ci.md`, `docs/deploy-setup.md`, `ci-check-config.sh`; deleted legacy scripts

**Suggested next step:** `git pull` in python-pipeline submodule/checkout; commit or discard local changes intentionally.

---

### 13. Actions Node 20 deprecation warnings

**What:** GitHub Actions logs warn that Node 20 will be deprecated on hosted runners. Workflows use `actions/checkout@v4`, `actions/setup-python@v5`, `docker/login-action@v3`, etc.

**Impact:** No failure today. Future runner image updates may break or warn more aggressively.

**Evidence:**

- CI logs mention Node 20 deprecation for checkout/setup actions

**Suggested next step:** Bump action versions when Node 24–compatible releases are available; test on a PR.

---

## Closed (for reference)

These were open in earlier gap reports and are now resolved:

| Item | Resolution |
|------|------------|
| Build GnuPG `chmod` in CI | Conditional in `build` runbook |
| Deploy secrets/variables | `ci-check-config.sh --strict` passes all repos |
| Full py3.14 pipeline | Run `27523814722` success |
| unstable `mime-support` | Remote py repos use `media-types` |
| Nightly track | Removed |
| Publish races / wrong codename debs | `ci-publish.sh` + `import-incoming.sh` filtering (`dfce9b2`) |
| cpython dev snapshot pin | Auto-pin in `meta-gbp` |
| APT metadata live | Release 200; python3.14 packages indexed |

---

## Comment guide

When commenting inline, prefix with the gap number, e.g.:

- `Gap 1: defer py3.10 until …`
- `Gap 2: blocked on …`
- `Gap 4: fixed by making GHCR public`
