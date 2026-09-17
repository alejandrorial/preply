# Preply — Breakage estimation (case study)

dbt project on DuckDB. Current state: **sources + staging layer**. The
intermediate layer (cycle logic, lesson-to-cycle mapping, per-segment
booking curves) and the marts come in following commits — the full design,
including the worked example and the decisions behind it, lives in the
proposal document (outside this repo).

## Requirements

- Python 3.9+ (on this machine: 3.9.6 — caps dbt-core at 1.10.x; with Python
  3.10+ you can move to a newer dbt version without changing anything else
  in the project).
- `pip3 install --user dbt-core dbt-duckdb`

The `dbt` script installs into `~/Library/Python/3.9/bin` on macOS, which
usually isn't on `PATH` by default. Either add it to your `PATH`, or call
the full path: `~/Library/Python/3.9/bin/dbt`.

## How to run it

From `preply_breakage/` (`profiles.yml` lives at the project root, not in
`~/.dbt/`, so the project is self-contained):

```bash
export DBT_PROFILES_DIR=$(pwd)

dbt seed   # loads seeds/*.csv into dev.duckdb (raw_payments, raw_lessons, raw_students)
dbt run    # builds the models (staging only, for now)
dbt test   # runs the tests
```

**Note**: `dev.duckdb` uses an exclusive lock. If you have it open in VS
Code's DuckDB extension (or another client), close that connection before
running `dbt seed`/`dbt run`, or you'll get `IO Error: Could not set lock on
file`.

## Point in time ("today")

The project never assumes `current_date` directly in a model — everything
goes through the `as_of_date()` macro (`macros/as_of_date.sql`):

- No override: uses `current_date` (normal production behavior).
- To reproduce the case study with the dataset's real `AS_OF_DATE`
  (2026-04-17, the last day it covers), or for a backfill/debugging a
  specific day:

  ```bash
  dbt run --vars '{as_of_date: 2026-04-17}'
  ```

## Schemas

Each layer lands in its own physical schema, not the target's default one —
mirroring how a real warehouse separates layers for permissioning (only
`marts_preply` would be exposed to BI tools/stakeholders):

| layer | schema |
|---|---|
| staging | `stg_preply` |
| intermediate | `working_preply` |
| marts | `marts_preply` |

Configured in `dbt_project.yml` (`+schema` per folder) plus
`macros/generate_schema_name.sql`, the standard dbt override that makes the
schema name literal instead of prefixed with the target's schema (dbt's
default would otherwise produce `main_stg_preply` instead of `stg_preply`).
In this single-file local DuckDB setup there's no real permission boundary
between schemas, but it keeps the project's shape identical to what it would
be on a real warehouse.

## Structure

```
models/
  staging/
    _schema.yml    # sources + descriptions and tests for the stg_ models
    stg_payments.sql
    stg_lessons.sql
    stg_students.sql
tests/
  assert_hours_booked_positive.sql
  assert_plan_hours_positive.sql
seeds/
  raw_payments.csv, raw_lessons.csv, raw_students.csv   # the case's real dataset
  dataset_README.md                                     # dataset documentation as received
.sqlfluff          # lint: fixed indentation + leading commas (see Conventions)
```

Seeds are a local stand-in for real ingestion (Fivetran or similar) — the
rest of the project treats `raw_payments`/`raw_lessons`/`raw_students` as
**sources**, not as seeds, so moving to a real warehouse only means changing
`_schema.yml`.

## Conventions

So every new layer — built by me, you, or whoever picks this up — follows
the same pattern without having to ask:

**Model naming** (prefix = layer):
| prefix | layer | default materialization |
|---|---|---|
| `stg_` | staging | view |
| `int_` | intermediate | view |
| `fct_` / `mart_` | marts | table |

**One `_schema.yml` per folder**, not one file per model, and not separate
"sources.yml" + "models.yml" files. The leading `_` keeps it at the top when
listing the folder. Sources and models for that same layer live in the same
file.

**Tests in two places, deliberately, not duplicated**: `unique`/`not_null`
on primary keys live on the `source` — if one fails, the problem is in
ingestion, not our SQL. Business-logic tests (`accepted_values`,
`relationships`, singular tests) live on the `stg_`/`int_`/`fct_` model,
over the already-renamed columns.

**Severity is deliberate, not just the default**: `unique`/`not_null` on
primary keys stay at `error` (the default) — a broken or duplicated key
means the table's grain itself is compromised, and nothing should build on
top of it. Everything else (FK `relationships`, `not_null` on individual
business columns, `accepted_values`, the singular tests) is set to `warn` —
a bad value there is contained to that one row, so it shouldn't block the
rest of that day's refresh. This only matters once tests run in the same
pass as the build (`dbt build` instead of separate `dbt run` + `dbt test`,
see below) — `error` severity is what makes `dbt build` skip downstream
models of a failed node. Someone still has to look at `WARN`s; they're not a
silent pass.

**Casting**: `try_cast`, not a hard `::` / `cast()`. A hard cast failing on a
single bad row would fail the whole model — and everything downstream of it
— blocking that day's refresh for every other, perfectly healthy row too.
`try_cast` keeps the warehouse refreshing and turns a bad value into `NULL`
instead, caught by the `not_null` tests on every casted column.

Residual risk, named rather than hidden: a `NULL` isn't as loud as a failed
build — it silently drops out of `sum()`s and out of any join or date-range
filter downstream (e.g. a `NULL payment_at` would make that payment
invisible to the whole cycle/breakage calculation, not just flagged). This
only stays safe if test failures are actually looked at promptly. With more
time, the more robust version of this is a quarantine pattern — route rows
that fail to cast into a `stg_payments__rejected` side table instead of
either failing the build or letting them vanish into a `NULL` — so a bad row
is visible and investigable without blocking anything or hiding in an
aggregate. Not built here: with this dataset verified clean (0 cast
failures, 0 nulls across all three sources), it would be speculative
complexity for a case study, but it's what I'd add first at real scale.

**SQL style — enforced with SQLFluff, not from memory**:
- Fixed 4-space indentation, never tabs.
- Leading commas (before the column, including the comma separating CTEs),
  never at the end of a line.
- Keywords and identifiers in lowercase.

```bash
export DBT_PROFILES_DIR=$(pwd)
sqlfluff lint models/ tests/     # check
sqlfluff format models/ tests/   # auto-fix what it can
```

Config lives in `.sqlfluff` (project root) — it uses dbt's templater, so it
needs `DBT_PROFILES_DIR` just like `dbt run` does.

## Staging layer decisions

- Explicit type casts instead of relying on `dbt seed`'s inference.
- `hours` → `plan_hours` in payments, so it isn't confused with
  `hours_booked` in lessons.
- Timestamps renamed with an `_at` suffix (`payment_at`, `booked_at`,
  `joined_at`) for consistency.
- No business logic here (no cycles, no payment-to-booking mapping) — that's
  exactly what separates staging from intermediate.
