# Bug: nightly `k3dm-cleanup` never prunes the Docker volumes orphaned by hub rebuilds

**Filed:** 2026-10-02
**Status:** OPEN — spec ready, dispatched to Codex
**Branch:** `k3d-manager-v1.41.0`
**Found by:** Claude, 2026-10-02, when the operator asked what to purge on the M4 (Data volume 68%, 281 GB used).

## Symptom

- `docker system df`: local volumes take 79.7 GB, and 35.5 GB of that is unused. Almost all of it is two hub-era volumes no
  container references:
  - `k3d-k3d-cluster-recovery-server-data`: 17.9 GB, created 2026-09-10, from a manual recovery cluster.
  - an anonymous volume `60dfb5be…`: 16.8 GB, created 2026-09-04, k3s node data (`agent/ server/ storage/`).
- The Trivy cache (2.7 GB) and the Homebrew cache (2.4 GB) also grow without bound.

## Root cause

`bin/k3dm-cleanup`, run nightly at 03:00 by `com.k3d-manager.cleanup`, only prunes files: `/tmp`, run dir, screenshots,
Chromium, Packer and port caches. `bin/cluster-down` runs `docker system prune --force`, which never removes volumes, and only on
a full teardown. A hub rebuild or recovery cluster leaves its node-data volume behind, and nothing removes it.

## Fix

Add two steps to `bin/k3dm-cleanup`:

- **Remove unused Docker volumes.** A volume is removed only if all of the following hold:
  - it is unreferenced (`dangling=true`, which also counts stopped containers);
  - it is older than the retention period;
  - it is either anonymous or named `k3d-*`;
  - it is not on the keep list (default `k3dm-*`, the Go build caches).

  Named volumes from other projects are never touched.
- **Clean the Trivy and Homebrew caches once a week (Sunday).**

Both steps can be switched off by env var and are skipped quietly when the tool is missing or Docker is not running.

### S1: `bin/k3dm-cleanup`, new settings

Old:
```bash
K3DM_PORT_RETENTION_DAYS="${K3DM_PORT_RETENTION_DAYS:-7}"
```
New:
```bash
K3DM_PORT_RETENTION_DAYS="${K3DM_PORT_RETENTION_DAYS:-7}"
K3DM_DOCKER_VOLUME_PRUNE="${K3DM_DOCKER_VOLUME_PRUNE:-1}"
K3DM_DOCKER_VOLUME_RETENTION_DAYS="${K3DM_DOCKER_VOLUME_RETENTION_DAYS:-7}"
K3DM_DOCKER_KEEP_VOLUMES="${K3DM_DOCKER_KEEP_VOLUMES:-k3dm-*}"
K3DM_WEEKLY_CACHE_PRUNE="${K3DM_WEEKLY_CACHE_PRUNE:-1}"
K3DM_WEEKLY_CACHE_PRUNE_DAY="${K3DM_WEEKLY_CACHE_PRUNE_DAY:-7}"
```

### S2: `bin/k3dm-cleanup`, new functions directly above `_prune_pngs "${K3DM_STATE_DIR}"`

```bash
# Hub rebuilds and recovery clusters leave their k3s node-data volumes behind. Remove
# only volumes no container (running or stopped) references, older than the retention
# window, that are anonymous or k3d-*; never named volumes from other projects.
_prune_docker_volumes() {
  local vol created anon keep cutoff
  [[ "${K3DM_DOCKER_VOLUME_PRUNE}" == "1" ]] || return 0
  command -v docker >/dev/null 2>&1 || return 0
  docker info >/dev/null 2>&1 || return 0
  cutoff="$(date -u -v-"${K3DM_DOCKER_VOLUME_RETENTION_DAYS}"d +%F 2>/dev/null \
    || date -u -d "-${K3DM_DOCKER_VOLUME_RETENTION_DAYS} days" +%F)"
  while IFS= read -r vol; do
    [[ -n "${vol}" ]] || continue
    for keep in ${K3DM_DOCKER_KEEP_VOLUMES}; do
      # shellcheck disable=SC2053
      [[ "${vol}" == ${keep} ]] && continue 2
    done
    anon="$(docker volume inspect "${vol}" --format '{{range $k, $v := .Labels}}{{if eq $k "com.docker.volume.anonymous"}}anon{{end}}{{end}}' 2>/dev/null || true)"
    [[ "${anon}" == "anon" || "${vol}" == k3d-* ]] || continue
    created="$(docker volume inspect "${vol}" --format '{{.CreatedAt}}' 2>/dev/null || true)"
    [[ -n "${created}" && "${created:0:10}" < "${cutoff}" ]] || continue
    if docker volume rm "${vol}" >/dev/null 2>&1; then
      echo "k3dm-cleanup: removed unused Docker volume ${vol} (created ${created:0:10})"
    fi
  done < <(docker volume ls -q --filter dangling=true 2>/dev/null)
}

# Trivy's DB/scan cache and Homebrew's download cache are re-creatable; trim weekly.
_prune_weekly_caches() {
  [[ "${K3DM_WEEKLY_CACHE_PRUNE}" == "1" ]] || return 0
  [[ "$(date +%u)" == "${K3DM_WEEKLY_CACHE_PRUNE_DAY}" ]] || return 0
  if command -v trivy >/dev/null 2>&1 && trivy clean --all >/dev/null 2>&1; then
    echo "k3dm-cleanup: cleaned Trivy cache"
  fi
  if command -v brew >/dev/null 2>&1 && brew cleanup -s >/dev/null 2>&1; then
    echo "k3dm-cleanup: cleaned Homebrew cache"
  fi
}

```

**The anonymous test.** Docker marks an anonymous volume with the label `com.docker.volume.anonymous` set to an **empty
string**, so testing the label's value does not work; the template above tests whether the key exists. Verified live 2026-10-02
on Docker 29.4.0: anonymous volumes print `anon`, and the named `k3dm-gobuild-cache` prints nothing.

### S3: `bin/k3dm-cleanup`, call the new steps

Old:
```bash
_prune_packer_cache
_prune_port_markers

echo "k3dm-cleanup: done"
```
New:
```bash
_prune_packer_cache
_prune_port_markers
_prune_docker_volumes
_prune_weekly_caches

echo "k3dm-cleanup: done"
```

### S4: `scripts/tests/bin/k3dm_cleanup.bats`

**Safety first: these tests run the real script.** Without stubs, every existing test would call the real `docker`, `trivy`
and `brew` on the developer's machine and delete real volumes.

In `setup()`, after the existing `mkdir -p` line, add stubs. Each stub logs its arguments to `${BATS_TEST_TMPDIR}/calls`:
- `docker` stub:
  - `info` returns rc 0.
  - `volume ls -q --filter dangling=true` prints the lines in file `${BATS_TEST_TMPDIR}/volumes`, or nothing if the file is
    missing.
  - `volume inspect <v> --format <fmt>`: when `<fmt>` contains `CreatedAt`, it prints the value of the line `<v> created=<date>`
    in `${BATS_TEST_TMPDIR}/meta`. When `<fmt>` contains `com.docker.volume.anonymous`, it prints `anon` if `meta` has a line
    `<v> anon`.
  - `volume rm <v>` returns rc 0.
- `trivy` and `brew` stubs return rc 0.

Then `export PATH="${BATS_TEST_TMPDIR}/stubbin:${PATH}"`. All existing `run env …` calls inherit PATH.

Add these tests:
1. **Old orphaned volumes go, everything else stays.** The `volumes` file holds `k3d-old-server-data`, `anonold`, `anonnew`,
   `k3dm-gobuild-cache`, `otherproject-db`. In `meta`:
   - `k3d-old-server-data` and `otherproject-db` are created `2026-01-01T00:00:00Z`;
   - `anonold` is created `2026-01-01T00:00:00Z` and is `anon`;
   - `anonnew` is created with today's date, `$(date -u +%F)T00:00:00Z`, and is `anon`;
   - `k3dm-gobuild-cache` is created `2026-01-01T00:00:00Z` and is `anon`.

   Assert:
   - rc 0;
   - calls contain `volume rm k3d-old-server-data` and `volume rm anonold`;
   - calls do NOT contain `volume rm anonnew`, `volume rm k3dm-gobuild-cache` or `volume rm otherproject-db`. Use
     `run grep -c` and compare against `0`.
2. **`K3DM_DOCKER_VOLUME_PRUNE=0` with the same fixtures:** calls contain no `volume rm`.
3. **Weekly caches on the prune day:** run with `K3DM_WEEKLY_CACHE_PRUNE_DAY="$(date +%u)"`. Calls contain `clean --all`
   and `cleanup -s`.
4. **Weekly caches off the prune day:** `K3DM_WEEKLY_CACHE_PRUNE_DAY` set to a different day,
   `$(( $(date +%u) % 7 + 1 ))`. Calls contain neither.

Use `run`/`[ ]` assertions only. No bare `!` negations at line start.

## Gate (paste output)

1. `bats scripts/tests/bin/k3dm_cleanup.bats` reports 0 failures (5 existing + 4 new).
2. Safety: paste the `setup()` lines that create the stubs and export PATH, and confirm they run before any test body.
   Because PATH is exported, no test can reach the real `docker`, `trivy` or `brew`.
3. Mutation: change `[[ "${anon}" == "anon" || "${vol}" == k3d-* ]] || continue` to `:`. Test 1 must FAIL (`otherproject-db`
   gets removed). Restore it.
4. `shellcheck bin/k3dm-cleanup`: no new warnings. Compare `git show HEAD:bin/k3dm-cleanup | shellcheck -f gcc - | wc -l`
   against the count after.
5. `grep -rnE '^[[:space:]]*! ' scripts/tests --include='*.bats'` prints nothing.
6. `git diff --stat` shows only `bin/k3dm-cleanup` and `scripts/tests/bin/k3dm_cleanup.bats`.

## Definition of Done

- [ ] S1–S4 applied exactly; only these 2 files changed
- [ ] Gates output pasted
- [ ] Commit message: `fix(cleanup): prune orphaned Docker volumes nightly and trim Trivy/Homebrew caches weekly`
- [ ] Pushed to `origin/k3d-manager-v1.41.0`; report `git rev-parse origin/k3d-manager-v1.41.0`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`
- Do NOT run `bin/k3dm-cleanup` outside BATS (it would act on the real Docker host)
- Do NOT call the real `docker`, `trivy` or `brew` from any test
- Do NOT add `docker image prune`, `docker system prune --volumes` or anything that touches named non-`k3d-*` volumes
- Do NOT modify other files or the memory-bank

## Rollout

None. The launch agent already runs `bin/k3dm-cleanup` from the repo checkout at 03:00 daily, so the change applies on the next
nightly run after the branch is checked out. Claude checks `~/Library/Logs/k3dm-cleanup.log` for the
`removed unused Docker volume` lines the morning after.
