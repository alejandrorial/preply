{{ config(severity='warn') }}

-- A renewal's cycle_start should match the previous cycle's
-- cycle_end_exclusive for the same student — payments are assumed
-- contiguous. Compared by date, not exact timestamp: this dataset's
-- payment timestamps carry up to ~1 second of jitter around a clean
-- 28-day gap (verified — 6,691 of 6,695 renewals differ at the
-- millisecond level, 0 differ by date), and nothing in this project reasons
-- about cycle boundaries below day precision anyway. A gap that survives
-- this coarser check means either a student churned and reactivated with a
-- fresh anchor (not distinguished from a data quality problem by the
-- current model), or a genuine ingestion issue.
with cycles as (

    select
        payment_id
        , student_id
        , cycle_number
        , cycle_start
        , lag(cycle_end_exclusive)
            over (partition by student_id order by cycle_number)
            as previous_cycle_end

    from {{ ref('int_payment_cycles') }}

)

select *
from cycles
where
    cycle_number > 1
    and cycle_start::date <> previous_cycle_end::date
