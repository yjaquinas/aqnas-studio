---
name: sqlite-conventions
description: Defines SQLite conventions for AQNAS projects, covering database file location (./data/app.db in dev, /opt/{project}/data/app.db in prod inside the ReadWritePaths= directive of systemd), WAL journaling mode, foreign_keys=ON pragma, connection management (per-request context manager, not a global connection), raw SQL over ORM (no SQLAlchemy, no Tortoise — use the stdlib sqlite3 module directly), plain-SQL migrations in app/models/migrations/ with integer-prefixed filenames, schema conventions (plural snake_case tables, INTEGER PRIMARY KEY for integer IDs, TEXT ISO8601 timestamps with CURRENT_TIMESTAMP default, NOT NULL by default, explicit CHECK constraints for enums), and backup via SQLite's built-in .backup API. Use when generating or reviewing app/models/db.py, writing or modifying migrations, adding new tables, debugging "database is locked" errors, deciding between SQL and ORM for a new feature, or when the user asks about SQLite, WAL mode, foreign keys, migrations, connection pooling, or backup strategy.
---

# sqlite-conventions

SQLite patterns for AQNAS projects.

## Why SQLite, why no ORM

SQLite is the default AQNAS database. One file. Zero operational overhead. Handles low-to-mid traffic fine. Deployment is `cp`.

No ORM. Raw SQL via the stdlib `sqlite3` module. Reasons:
- SQLite is simple enough that an ORM is more abstraction than it's worth
- SQL is the skill worth investing in, not any specific ORM's query DSL
- `sqlite3` is in the stdlib; every import is dependency weight avoided

If a project outgrows SQLite, migrate to Postgres with raw SQL still — not by introducing an ORM.

## File locations

| Environment | Path |
|---|---|
| Dev (local) | `./data/app.db` — relative to project root |
| Production | `/opt/{project}/data/app.db` — inside the `ReadWritePaths=` directive of the systemd unit |
| Tests | `:memory:` or `./tests/fixtures/test.db` (wiped before each run) |

`data/` is in `.gitignore`. The directory is created at boot if missing.

## Connection management

One connection per request, not a shared global. SQLite's concurrency model favors short-lived connections with WAL journaling.

```python
# app/models/db.py
from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

import structlog

log = structlog.get_logger()

DB_PATH = Path(os.getenv("DATABASE_PATH", "./data/app.db"))


def _configure(conn: sqlite3.Connection) -> None:
    """Pragmas set on every connection. WAL is file-level, but the others are per-connection."""
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    conn.execute("PRAGMA synchronous = NORMAL")
    conn.execute("PRAGMA temp_store = MEMORY")
    conn.row_factory = sqlite3.Row


@contextmanager
def connect() -> Iterator[sqlite3.Connection]:
    conn = sqlite3.connect(DB_PATH, isolation_level=None, timeout=5.0)
    _configure(conn)
    try:
        yield conn
    finally:
        conn.close()
```

Key settings:

| Pragma | Why |
|---|---|
| `foreign_keys = ON` | SQLite ships with FK enforcement off by default. Always turn it on. |
| `journal_mode = WAL` | Write-ahead log. Writers don't block readers. Massively improves concurrency. |
| `synchronous = NORMAL` | With WAL, NORMAL is the safe default — faster than FULL, survives crashes cleanly |
| `temp_store = MEMORY` | Temp tables in RAM, not on disk |
| `row_factory = sqlite3.Row` | Access columns by name (`row["id"]`) instead of index |

`isolation_level=None` means Python doesn't autobegin transactions — you control them explicitly with `BEGIN` / `COMMIT`. This is the preferred pattern.

`timeout=5.0` is the busy-wait when another writer holds the lock. Default is 5s; keep it unless profiling says otherwise.

## Transactions

Explicit only. No implicit autocommit or autobegin.

```python
with connect() as conn:
    conn.execute("BEGIN")
    try:
        conn.execute("INSERT INTO posts (title, body) VALUES (?, ?)", (title, body))
        conn.execute("INSERT INTO events (kind, ref) VALUES ('post_created', last_insert_rowid())")
        conn.execute("COMMIT")
    except Exception:
        conn.execute("ROLLBACK")
        raise
```

Or a helper:

```python
@contextmanager
def tx(conn: sqlite3.Connection) -> Iterator[None]:
    conn.execute("BEGIN")
    try:
        yield
        conn.execute("COMMIT")
    except Exception:
        conn.execute("ROLLBACK")
        raise
```

## Schema conventions

```sql
CREATE TABLE posts (
    id INTEGER PRIMARY KEY,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    author_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status TEXT NOT NULL CHECK (status IN ('draft', 'published', 'archived')) DEFAULT 'draft',
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_posts_author ON posts(author_id);
CREATE INDEX idx_posts_status ON posts(status) WHERE status != 'archived';
```

Rules:
- **Table names** — plural, snake_case (`posts`, `blog_posts`, `user_sessions`)
- **Column names** — snake_case (`created_at`, not `createdAt`)
- **IDs** — `INTEGER PRIMARY KEY`. This aliases SQLite's `rowid` and is fast. Don't use UUIDs unless a specific reason (external sharing, public slugs — use a separate `slug TEXT UNIQUE` column for that)
- **Foreign keys** — always `ON DELETE` clause. Usually `CASCADE` for owned records, `SET NULL` for optional references, `RESTRICT` for protection
- **Timestamps** — `TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP`. SQLite stores them as ISO 8601 strings. Sort lexicographically = sort chronologically.
- **NOT NULL by default** — every column unless the domain genuinely allows null. Nullable columns are a choice to justify, not a default
- **Enums** — `TEXT` with `CHECK (col IN (...))` constraint. Don't use integers mapped to meanings — SQL with literal strings is self-documenting
- **Partial indexes** — use `WHERE` clauses to index only hot subsets (e.g., exclude archived rows)

## Migrations

Plain SQL files, integer-prefixed, one file per change, in `app/models/migrations/`:

```
app/models/migrations/
├── 0001_initial.sql
├── 0002_add_posts_status.sql
├── 0003_add_users_email_unique.sql
└── 0004_add_comments.sql
```

Apply at app startup via a simple runner that tracks applied migrations in a `_migrations` table:

```sql
CREATE TABLE IF NOT EXISTS _migrations (
    filename TEXT PRIMARY KEY,
    applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

Runner:
1. List files in `migrations/`, sort
2. For each, check if `filename` is in `_migrations`
3. If not, `BEGIN`, execute the SQL file, `INSERT INTO _migrations`, `COMMIT`
4. Run on every startup — safe because already-applied migrations are skipped

Rules:
- Migrations are **append-only**. Never edit an applied migration. If a schema was wrong, write a new migration to fix it.
- Keep migrations **narrow** — one logical change per file. "Add users table" and "add posts table" are two files, not one.
- Don't include DML (INSERT/UPDATE/DELETE) in schema migrations except for seed data and lookup tables. Data migrations go in separate `.sql` files with a `data_` prefix when they're too large or risky for ad-hoc scripting.

## Query patterns

Parameterize everything. Never string-format user input into SQL.

```python
# YES
conn.execute("SELECT * FROM posts WHERE author_id = ? AND status = ?", (user_id, "published"))

# NO — SQL injection
conn.execute(f"SELECT * FROM posts WHERE author_id = {user_id}")
```

For dynamic IN clauses:

```python
ids = [1, 2, 3]
placeholders = ",".join("?" * len(ids))
conn.execute(f"SELECT * FROM posts WHERE id IN ({placeholders})", ids)
```

The `f"..."` here is safe because only the **count of placeholders** is interpolated; the values themselves are still parameters.

## Backup

SQLite's built-in Online Backup API, not `cp` of a WAL-mode file:

```python
def backup(dest: Path) -> None:
    with connect() as src:
        dest_conn = sqlite3.connect(dest)
        src.backup(dest_conn)
        dest_conn.close()
```

Why not `cp`? WAL mode has a separate `-wal` file that holds pending writes. `cp` of just the main `.db` file captures a snapshot that's missing recent writes. The Online Backup API handles this correctly.

Cron the backup. Rotate. Ship to object storage (B2, R2, S3) for off-host copies.

## What not to do

- Don't use an ORM. Not SQLAlchemy, not Peewee, not Tortoise. Raw `sqlite3`.
- Don't share a single connection across threads/tasks. One connection per request.
- Don't leave `foreign_keys = OFF`. Orphaned rows will bite you.
- Don't use `INTEGER` for booleans without a `CHECK (col IN (0, 1))` constraint, or use `TEXT` with `CHECK (col IN ('true', 'false'))`. SQLite's flexible typing means `TRUE` silently becomes the string `'TRUE'` without constraints.
- Don't use `DATETIME` as a column type thinking it's real. SQLite accepts any type name; `TEXT` with ISO 8601 is what's actually stored.
- Don't store money as REAL. Use INTEGER cents or TEXT with a decimal string.
- Don't commit `*.db` files. In `.gitignore`.
- Don't backup via `cp` of a WAL-mode database.

## Failure modes

- **"database is locked".** Long-running read transactions blocking a writer, or a process that crashed holding the lock. Check for zombie connections. If WAL is enabled (it should be), writers don't normally block readers.
- **Foreign key violation on insert.** `foreign_keys = ON` is doing its job. Fix the referenced row first.
- **Missing `-wal` and `-shm` files after a crash.** Normal. SQLite recreates them on next open.
- **Migration partially applied.** Every migration runs in a transaction; a failure rolls back cleanly. If it committed before failing, the `_migrations` table records it as applied — review that table manually to untangle.
- **Dates don't sort correctly.** Stored as non-ISO format. Always use `CURRENT_TIMESTAMP` or explicit ISO 8601 (`strftime('%Y-%m-%dT%H:%M:%fZ', 'now')`).
- **Unique constraint violation after schema change.** Migration added `UNIQUE` but existing data violates it. Resolve duplicates in a data migration before applying the schema migration.
