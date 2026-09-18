{{ config(materialized='table') }}
-- Table, not the intermediate default of view: the calendar spine's upper
-- bound depends on as_of_date(). Same reasoning as int_payment_cycles —
-- pin "today" to build time, don't let a view re-evaluate current_date on
-- every later query.

with cycles as (

    select
        payment_id
        , plan_hours
        , is_renewal
        , is_closed
        , cycle_start
        , cycle_start_date

    from {{ ref('int_payment_cycles') }}

)
, spine as (

    -- Cross join on purpose, not an incremental/stateful snapshot: with the
    -- full booking history available, "what we knew as of day X" is always
    -- fully recomputable, so there is no state to maintain or to go stale.
    select
        cycles.payment_id
        , cycles.plan_hours
        , cycles.is_renewal
        , cycles.is_closed
        , cycles.cycle_start
        , day_offset.day_in_cycle
        , (
            cycles.cycle_start_date + (day_offset.day_in_cycle * interval 1 day)
        )::date as snapshot_date

    from cycles
    cross join range(
        0
        -- cycle_length_days + 1, not cycle_length_days: a cycle_start with
        -- any non-midnight time-of-day (every payment in this dataset)
        -- makes the N-day window span N+1 distinct calendar dates — the
        -- closing sliver from midnight to cycle_end_exclusive's
        -- time-of-day is still calendar day_in_cycle = cycle_length_days.
        -- Capping one short of that silently dropped bookings made in
        -- that last partial day from every downstream total — found by
        -- cross-checking this model's segment averages against an
        -- independent, from-scratch calculation (a real ~2pp discrepancy
        -- at day 27, not rounding noise, back when this was hardcoded to
        -- 28/29).
        , least(
            {{ var('cycle_length_days', 28) }} + 1
            , date_diff('day', cycles.cycle_start_date, {{ as_of_date() }}) + 1
        )
    ) as day_offset (day_in_cycle)

)
, lessons as (

    select
        payment_id
        , booked_date
        , hours_booked

    from {{ ref('int_lesson_cycles') }}

)
, progress as (

    select
        spine.payment_id
        , spine.cycle_start
        , spine.snapshot_date
        , spine.day_in_cycle
        , spine.plan_hours
        , spine.is_renewal
        , spine.is_closed
        , coalesce(sum(lessons.hours_booked), 0) as hours_booked_to_date

    from spine
    left join lessons
        on
            spine.payment_id = lessons.payment_id
            and spine.snapshot_date >= lessons.booked_date

    group by
        spine.payment_id
        , spine.cycle_start
        , spine.snapshot_date
        , spine.day_in_cycle
        , spine.plan_hours
        , spine.is_renewal
        , spine.is_closed

)

select
    payment_id
    , cycle_start
    , snapshot_date
    , day_in_cycle
    , plan_hours
    , is_renewal
    , is_closed
    , hours_booked_to_date
    , payment_id::varchar
    || '|'
    || snapshot_date::varchar as payment_snapshot_key

from progress
