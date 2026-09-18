{{ config(severity='warn') }}

-- Guards the invariant a dashboard depends on blindly: every payment has
-- exactly one row flagged is_current_snapshot — never more than one, and
-- never zero.
--
-- The zero case is why this starts from int_payment_cycles rather than from
-- the mart alone: a payment that fell out of the mart entirely would never
-- appear in a `where is_current_snapshot ... group by payment_id` result at
-- all, so a mart-only version of this test can structurally only catch
-- duplicates, not disappearances. That gap is real — a backfill to an
-- earlier as_of_date drops every later payment out of int_cycle_daily_progress
-- (its calendar spine ends up empty), and the mart follows.
--
-- Payments whose cycle hasn't started yet as of this run's point in time are
-- deliberately out of scope: a backfill should only see what existed then,
-- so their absence is correct behavior, not a failure.
with expected as (

    select payment_id
    from {{ ref('int_payment_cycles') }}
    where cycle_start_date <= {{ as_of_date() }}

)
, flagged as (

    select
        payment_id
        , count(*) as current_snapshot_rows

    from {{ ref('mart_breakage_daily') }}
    where is_current_snapshot
    group by payment_id

)

select
    expected.payment_id
    , coalesce(flagged.current_snapshot_rows, 0) as current_snapshot_rows

from expected
left join flagged
    on expected.payment_id = flagged.payment_id
where coalesce(flagged.current_snapshot_rows, 0) <> 1
