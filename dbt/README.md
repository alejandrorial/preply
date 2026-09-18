# Preply — Breakage estimation (case study)

dbt project on DuckDB. Estimates breakage revenue per payment, refreshed
daily while a payment's 28-day cycle is still open, replaced by the known
actual once it closes. Built for Preply's Analytics Engineer case study.

## Deliverables

- **The dbt project** — this folder: staging → intermediate → marts, tests, and this README.
- **Dashboard mockup** — [`../breakage_dashboard.html`](../breakage_dashboard.html)
  at the repo root. A standalone file: open it in a browser, no server or
  build step. It is built from this project's `mart_breakage_daily`, with
  the data as of 2026-04-17 baked in.
- **Written summary + AI usage note** —
  [`../case_summary_slides.html`](../case_summary_slides.html), a 13-slide
  deck covering the approach, the data model, assumptions, caveats, what
  I'd do next, and how I used AI. Also a standalone file.

## Requirements

- A dbt with a DuckDB adapter, plus Python 3.9+ for the seeds.
- `pip3 install --user dbt-core dbt-duckdb` gets you there.

Nothing in this project is engine-specific beyond standard dbt (`ref`,
`var`, a `generate_schema_name` override) and DuckDB SQL, so either dbt
runtime works. For the record, it was built and verified on **dbt Fusion
2.0.0-preview.218** against DuckDB.

On macOS, `pip3 install --user` puts the `dbt` script in
`~/Library/Python/3.x/bin`, which usually isn't on `PATH` by default —
either add it, or call the full path.

## How to run it

From `dbt/` (`profiles.yml` lives at the project root, not in
`~/.dbt/`, so the project is self-contained):

```bash
export DBT_PROFILES_DIR=$(pwd)

dbt seed    # loads seeds/*.csv into dev.duckdb (raw_payments, raw_lessons, raw_students)
dbt run     # builds staging -> intermediate -> marts
dbt test    # runs the tests
```

This runs at the dataset's own point in time (2026-04-17) by default — see
below — so it reproduces the case as submitted, with 8,846 closed cycles and
849 still open and being estimated.

**Note**: `dev.duckdb` uses an exclusive lock. If you have it open in VS
Code's DuckDB extension (or another client), close that connection before
running `dbt seed`/`dbt run`, or you'll get `IO Error: Could not set lock on
file`.

## Data model

Three layers, one clear grain per model:

| model | layer | grain |
|---|---|---|
| `stg_payments`, `stg_lessons`, `stg_students` | staging | one row per source record, cast/renamed only |
| `int_payment_cycles` | intermediate | one row per payment — cycle_start/end, cycle_number, is_renewal, is_closed |
| `int_lesson_cycles` | intermediate | one row per lesson — mapped to the one cycle it was booked into |
| `int_cycle_daily_progress` | intermediate | one row per payment × calendar day of its cycle — cumulative hours booked as of that day, recomputed from full booking history (no stored state) |
| `int_segment_burn_curves` | intermediate | one row per `(plan_hours, is_renewal)` segment × day-in-cycle — the historical average % of plan booked by that day, from closed cycles only |
| `mart_breakage_daily` | marts | one row per payment × snapshot_date — actual once closed, best current estimate while open |

**Estimation**: while a payment's cycle is open, `mart_breakage_daily`
prefers the segment burn-curve (Method B) — this payment's progress so far,
plus how much more its segment typically books before cycle end — falling
back to a linear extrapolation of the payment's own pace (Method A) when its
segment has fewer than 20 closed cycles of history. Both methods are
computed for every row (including closed cycles' historical days) so they
can be backtested against the known actual once it exists;
`estimated_breakage_linear_usd` / `estimated_breakage_segment_usd` /
`method_used` are all exposed on the mart for that reason. Full reasoning,
the backtest results, and the assumptions behind the n≥20 threshold are in
the written summary linked above.

**`is_current_snapshot`**: true on exactly one row per payment — its
final-day row if closed, today's row if still open. Any dashboard total
should filter on this, not on `snapshot_date = as_of_date()` (which would
silently exclude almost every already-closed payment). Enforced by
`assert_one_current_snapshot_per_payment`.

## Configuration

- **`cycle_length_days`** (dbt var, default `28`) — the subscription cycle
  length, used everywhere a cycle boundary or burn-curve percentage is
  computed (`int_payment_cycles`, `int_cycle_daily_progress`,
  `mart_breakage_daily`). Override at build time, e.g. to check what a
  30-day cycle would do: `dbt run --vars '{cycle_length_days: 30}'`.

## Point in time ("today")

The project never assumes `current_date` directly in a model — everything
goes through the `as_of_date()` macro (`macros/as_of_date.sql`), driven by
the `as_of_date` var:

- **Default: `2026-04-17`**, the last day the dataset covers — the case's
  "assume today is the last day covered by the dataset". This is deliberately
  the default rather than `current_date`: this dataset is a frozen snapshot,
  so a real current date leaves every cycle already closed, zero payments
  open, and nothing to estimate — the entire point of the model — without
  a single test failing to tell you.
- **Production behavior** (each daily run pins itself to the day it runs):

  ```bash
  dbt build --vars '{as_of_date: null}'
  ```

- **Backfill / debugging a specific day**:

  ```bash
  dbt build --vars '{as_of_date: 2026-01-15}'
  ```

  Note that a backfill legitimately sees fewer payments: any payment whose
  cycle hadn't started by that date has no rows yet. The
  `assert_one_current_snapshot_per_payment` test accounts for this — it
  checks every payment that *had* started by the run's point in time, so it
  catches a payment silently dropping out of the mart without raising false
  alarms on payments that simply didn't exist yet.

## Schemas

Each layer lands in its own physical schema, not the target's default one —
mirroring how a real warehouse separates layers for permissioning (only
`marts_preply` would be exposed to BI tools/stakeholders):

| layer | schema |
|---|---|
| staging | `stg_preply` |
| intermediate | `intermediate_preply` |
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
  intermediate/
    _schema.yml
    int_payment_cycles.sql
    int_lesson_cycles.sql
    int_cycle_daily_progress.sql
    int_segment_burn_curves.sql
  marts/
    _schema.yml
    mart_breakage_daily.sql
macros/
  as_of_date.sql             # the only place "today" is resolved
  generate_schema_name.sql   # literal per-layer schema names
tests/
  assert_hours_booked_positive.sql
  assert_plan_hours_positive.sql
  assert_cycles_are_contiguous.sql
  assert_no_cycle_overbooking.sql
  assert_one_current_snapshot_per_payment.sql
  assert_breakage_not_negative.sql
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
| `int_` | intermediate | table |
| `fct_` / `mart_` | marts | table |

Staging stays view: thin cast/rename over a source, cheap to recompute,
and in a warehouse billed per bytes scanned (BigQuery, Snowflake) a view
here costs the same as querying the source directly. Intermediate is
table: these models do real join/aggregation work (a range-join, an
aggregation over ~260k rows), and a warehouse billed per query would
otherwise repeat that computation on every read instead of paying once
for storage — same reasoning marts already gets by default.

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

## Business-logic tests

Beyond the standard `unique`/`not_null`/`accepted_values`/`relationships`
tests in each layer's `_schema.yml`, six singular tests in `tests/` check
things specific to this domain:

- `assert_hours_booked_positive`, `assert_plan_hours_positive` — no
  negative or zero-hour rows survive staging.
- `assert_cycles_are_contiguous` — a student's cycle N+1 starts exactly
  where cycle N's `cycle_end_exclusive` ends, with no gap or overlap.
- `assert_no_cycle_overbooking` — no payment's cumulative hours booked
  ever exceeds its plan size in `int_cycle_daily_progress`.
- `assert_one_current_snapshot_per_payment` — `is_current_snapshot` is
  true on exactly one row per payment (see "Data model" above).
- `assert_breakage_not_negative` — `breakage_usd` is never negative in
  the final mart.
