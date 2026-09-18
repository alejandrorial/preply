{{ config(severity='warn') }}

-- Guards the invariant a dashboard depends on blindly: exactly one row per
-- payment has is_current_snapshot — never zero, never more than one.
select
    payment_id
    , count(*) as current_snapshot_rows

from {{ ref('mart_breakage_daily') }}
where is_current_snapshot
group by payment_id
having count(*) <> 1
