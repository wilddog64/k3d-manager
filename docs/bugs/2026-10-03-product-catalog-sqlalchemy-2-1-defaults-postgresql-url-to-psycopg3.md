# Bug: product-catalog CI red — SQLAlchemy 2.1 resolves a bare `postgresql://` URL to psycopg 3, which is not installed

**Filed:** 2026-10-03
**Repo:** `shopping-cart-product-catalog`
**Severity:** High — every PR and every push to `main` fails CI; the publish job is skipped, so no new image can be built or promoted.

## Symptom

- PR #57 (build-push-deploy pin bump) — `Lint, Test & Build`: 4 failed / 105 passed; `Integration Test — Schema Self-Heal`: `ModuleNotFoundError: No module named 'psycopg'`.
- Dependabot PR #56 failed identically on 2026-09-28.
- The last green run was on `b6ff80b` (2026-09-22), and the source is unchanged since then.

## Root cause

- `pyproject.toml` declares `"sqlalchemy>=2.0.25"` (no upper bound) and `"psycopg2-binary>=2.9.9"`.
- CI resolved SQLAlchemy **2.0.54** on the last green run and **2.1.3** now.
- SQLAlchemy 2.1 changed the default DBAPI for the `postgresql` dialect from psycopg2 to psycopg (v3).
- `src/product_catalog/config.py:34` builds a driver-less `postgresql://` URL, so under 2.1 `create_engine()` in `database.py:15` imports `psycopg`. That fails at import time, which breaks every test module that imports `product_catalog.database`, as well as the integration job.
- The running image (built 2026-09-22 with 2.0.54) is unaffected. The break is in CI only, but it blocks every future build.

## Fix

Name the driver explicitly. `postgresql+psycopg2://` is valid on SQLAlchemy 2.0 and 2.1, and it matches the driver the project actually installs. We chose this over capping `sqlalchemy<2.1`, because a cap only postpones the problem.

## Spec (dispatched to Codex 2026-10-03)

### Before You Start

- Work repo: `~/src/gitrepo/personal/shopping-carts/shopping-cart-product-catalog`
- **Branch: `fix/sqlalchemy-explicit-psycopg2-driver`**, created from `origin/main` (`6b79fda`) with `git checkout -b fix/sqlalchemy-explicit-psycopg2-driver origin/main`, then pushed with `git push -u origin fix/sqlalchemy-explicit-psycopg2-driver`.
- Read `src/product_catalog/config.py` and `tests/unit/test_database.py` before editing.

### Change 1 — `src/product_catalog/config.py:34`

OLD:
```python
            f"postgresql://{self.db_username}:{self.db_password}"
```
NEW:
```python
            f"postgresql+psycopg2://{self.db_username}:{self.db_password}"
```

### Change 2 — new file `tests/unit/test_config.py`

```python
"""Tests for configuration."""

from sqlalchemy import create_engine

from product_catalog.config import Settings


def test_database_url_pins_psycopg2_driver():
    url = Settings().database_url
    assert url.startswith("postgresql+psycopg2://")
    assert create_engine(url).dialect.driver == "psycopg2"
```

`create_engine` does not connect, so this test needs no database. Under SQLAlchemy 2.1 it fails on the pre-fix source (the prefix assertion fails, and the import of `psycopg` fails too). That is the guard against reverting to a bare URL.

### Change 3 — `CHANGELOG.md`

Under `## [Unreleased]` → `### Fixed`, insert this bullet **after the last existing `- ` bullet of that list** (directly before the blank line that precedes `### Changed`):

```
- `src/product_catalog/config.py`: build the database URL as `postgresql+psycopg2://` instead of a bare `postgresql://`. `pyproject.toml` leaves `sqlalchemy` unbounded above, and SQLAlchemy 2.1 changed the default DBAPI for a bare `postgresql://` URL from psycopg2 to psycopg (v3), which this project does not install, so CI moved from 2.0.54 to 2.1.3 and every unit test importing `product_catalog.database` plus the schema self-heal integration job failed with `No module named 'psycopg'` (first seen on Dependabot #56, 2026-09-28). Naming the driver is correct on both 2.0 and 2.1; `tests/unit/test_config.py` asserts the engine resolves to psycopg2
```

### Gates (run and paste output)

- `grep -c 'f"postgresql://' src/product_catalog/config.py` → `0` (exits 1 on zero, which is expected)
- `grep -c 'postgresql+psycopg2://' src/product_catalog/config.py` → `1`
- In a fresh venv run `python -m venv .venv-fix && . .venv-fix/bin/activate && pip install -e ".[dev,rabbitmq]"` (the `make install-dev` set) so SQLAlchemy resolves to 2.1.x, print `python -c "import sqlalchemy; print(sqlalchemy.__version__)"`, then run `pytest tests/unit -q`. All tests must pass with zero failures.
- `ruff check src/ tests/` (the `make lint` command) is clean. Delete `.venv-fix` afterwards; it must not be committed.

### Definition of Done

- [ ] Changes 1–3 applied exactly; no other files touched.
- [ ] One commit with this exact message:
  ```
  fix(config): pin the psycopg2 driver in the database URL for SQLAlchemy 2.1

  Co-Authored-By: Codex <noreply@openai.com>
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```
- [ ] Pushed to `origin/fix/sqlalchemy-explicit-psycopg2-driver`; report the output of `git rev-parse origin/fix/sqlalchemy-explicit-psycopg2-driver`.
- [ ] Report the SHA, the SQLAlchemy version printed, and the pytest summary line.

### What NOT to Do

- Do NOT create a PR or merge anything.
- Do NOT commit to `main`; do NOT skip hooks (`--no-verify`).
- Do NOT modify files outside the three listed (no `pyproject.toml` pin, no workflow edits, no memory-bank).
- Do NOT add psycopg (v3) as a dependency.
- Do NOT touch the open branch `ci/bump-build-push-deploy-98b10f0` (PR #57).

### After merge (Claude)

Update PR #57 from `main` (`gh pr update-branch 57`) so its CI reruns green. Then, after #57 merges, verify that the main promote step pushes `newTag: sha-<merge>`.
