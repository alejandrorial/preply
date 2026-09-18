with progress as (

    select
        payment_id
        , snapshot_date
        , day_in_cycle
        , plan_hours
        , is_renewal
        , is_closed
        , hours_booked_to_date

    from {{ ref('int_cycle_daily_progress') }}

)
, cycles as (

    select
        payment_id
        , student_id
        , price_per_hour_usd

    from {{ ref('int_payment_cycles') }}

)
, curve_today as (

    select
        plan_hours
        , is_renewal
        , day_in_cycle
        , n_closed_cycles
        , avg_pct_booked as pct_booked_today

    from {{ ref('int_segment_burn_curves') }}

)
, curve_final as (

    select
        plan_hours
        , is_renewal
        , avg_pct_booked as pct_booked_final

    from {{ ref('int_segment_burn_curves') }}
    where day_in_cycle = {{ var('cycle_length_days', 28) }}

)
, projected as (

    select
        progress.payment_id
        , progress.snapshot_date
        , progress.day_in_cycle
        , progress.plan_hours
        , progress.is_renewal
        , progress.is_closed
        , progress.hours_booked_to_date
        , cycles.student_id
        , cycles.price_per_hour_usd
        , curve_today.n_closed_cycles
        -- day_in_cycle+1, not day_in_cycle: day_in_cycle is 0-indexed, but
        -- a rate needs "days elapsed" (day_in_cycle 0 is already 1 day
        -- in) — also sidesteps a divide-by-zero at day_in_cycle=0.
        , least(
            progress.plan_hours
            , progress.hours_booked_to_date / (progress.day_in_cycle + 1)
            * {{ var('cycle_length_days', 28) }}
        ) as linear_projected_hours
        , least(
            progress.plan_hours
            , progress.hours_booked_to_date
            + progress.plan_hours * greatest(
                curve_final.pct_booked_final - curve_today.pct_booked_today, 0
            )
        ) as segment_projected_hours

    from progress
    inner join cycles
        on progress.payment_id = cycles.payment_id
    left join curve_today
        on
            progress.plan_hours = curve_today.plan_hours
            and progress.is_renewal = curve_today.is_renewal
            and progress.day_in_cycle = curve_today.day_in_cycle
    left join curve_final
        on
            progress.plan_hours = curve_final.plan_hours
            and progress.is_renewal = curve_final.is_renewal

)
, breakage as (

    select
        payment_id
        , student_id
        , snapshot_date
        , day_in_cycle
        , plan_hours
        , is_renewal
        , is_closed
        , hours_booked_to_date
        , hours_booked_to_date * price_per_hour_usd * 0.2
            as commission_revenue_usd
        , case
            when n_closed_cycles is null or n_closed_cycles < 20 then 'linear'
            else 'segment'
        end as method_used
        , (plan_hours - linear_projected_hours) * price_per_hour_usd
            as estimated_breakage_linear_usd
        , (plan_hours - segment_projected_hours) * price_per_hour_usd
            as estimated_breakage_segment_usd
        , case
            when is_closed
                -- Cumulative and non-decreasing, so its value on the last
                -- spine row (day_in_cycle=cycle_length_days) equals its max
                -- across the whole cycle — avoids a self-join back to that
                -- one row.
                then (
                    plan_hours
                    - max(hours_booked_to_date) over (partition by payment_id)
                ) * price_per_hour_usd
        end as actual_breakage_usd

    from projected

)
, breakage_resolved as (

    select
        payment_id
        , student_id
        , snapshot_date
        , day_in_cycle
        , plan_hours
        , is_renewal
        , is_closed
        , hours_booked_to_date
        , commission_revenue_usd
        , method_used
        , estimated_breakage_linear_usd
        , estimated_breakage_segment_usd
        , actual_breakage_usd
        , coalesce(
            actual_breakage_usd
            , case
                when method_used = 'segment' then estimated_breakage_segment_usd
                else estimated_breakage_linear_usd
            end
        ) as breakage_usd
        , payment_id::varchar
        || '|'
        || snapshot_date::varchar as payment_snapshot_key

    from breakage

)
, students as (

    select
        student_id
        , country_code
        , acquisition_channel

    from {{ ref('stg_students') }}

)

select
    breakage_resolved.payment_id
    , breakage_resolved.student_id
    , breakage_resolved.snapshot_date
    , breakage_resolved.day_in_cycle
    , breakage_resolved.plan_hours
    , breakage_resolved.is_renewal
    , breakage_resolved.is_closed
    , breakage_resolved.hours_booked_to_date
    , breakage_resolved.commission_revenue_usd
    , breakage_resolved.method_used
    , breakage_resolved.estimated_breakage_linear_usd
    , breakage_resolved.estimated_breakage_segment_usd
    , breakage_resolved.actual_breakage_usd
    , breakage_resolved.breakage_usd
    , breakage_resolved.payment_snapshot_key
    , students.country_code
    , students.acquisition_channel
    -- True on each payment's single latest row — its final-day row if
    -- closed, today's row if still open. The dashboard's headline
    -- "breakage right now" totals should filter on this instead of
    -- snapshot_date = as_of_date(): that filter only catches payments
    -- whose cycle happens to still span today, which silently excludes
    -- almost every closed payment (its rows stop at its own cycle's
    -- final day, not today).
    , row_number() over (
        partition by breakage_resolved.payment_id
        order by breakage_resolved.snapshot_date desc
    ) = 1 as is_current_snapshot

from breakage_resolved
-- Left, not inner: a student_id with no match in stg_students (see the
-- warn-severity relationships test upstream) shouldn't silently drop that
-- payment's revenue from the mart, just leave its dimensions null.
left join students
    on breakage_resolved.student_id = students.student_id
