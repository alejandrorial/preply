{{ config(severity='warn') }}

-- A cycle can't have more hours booked than its plan allocated. Contained
-- to the specific payments where it happens, not a grain issue — warn.
with booked as (

    select
        payment_id
        , sum(hours_booked) as total_hours_booked

    from {{ ref('int_lesson_cycles') }}
    where payment_id is not null
    group by payment_id

)
, cycles as (

    select
        payment_id
        , plan_hours

    from {{ ref('int_payment_cycles') }}

)

select
    booked.payment_id
    , booked.total_hours_booked
    , cycles.plan_hours

from booked
inner join cycles
    on booked.payment_id = cycles.payment_id
where booked.total_hours_booked > cycles.plan_hours
