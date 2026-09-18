{{ config(materialized='table') }}
-- Table, not the intermediate default of view: is_closed depends on
-- as_of_date(), which resolves to current_date by default. A view
-- re-evaluates current_date on every query, silently drifting to whatever
-- day it happens to be queried — a table pins "today" to whenever dbt last
-- ran, matching a real daily batch job instead of a live-query moment.

with payments as (

    select
        payment_id
        , student_id
        , plan_hours
        , price_per_hour_usd
        , payment_at

    from {{ ref('stg_payments') }}

)
, cycles as (

    select
        payment_id
        , student_id
        , plan_hours
        , price_per_hour_usd
        , payment_at as cycle_start
        , payment_at + (interval 1 day * {{ var('cycle_length_days', 28) }})
            as cycle_end_exclusive
        , row_number()
            over (partition by student_id order by payment_at)
            as cycle_number

    from payments

)

select
    payment_id
    , student_id
    , plan_hours
    , price_per_hour_usd
    , cycle_start
    , cycle_start::date as cycle_start_date
    , cycle_end_exclusive
    , cycle_number
    , cycle_number > 1 as is_renewal
    -- Compared as dates, not raw timestamps: the case treats "today" as a
    -- whole day, so a cycle that ends at any point on the as_of_date is
    -- closed by end of day, not just if it ends before midnight.
    , cycle_end_exclusive::date <= {{ as_of_date() }} as is_closed

from cycles
