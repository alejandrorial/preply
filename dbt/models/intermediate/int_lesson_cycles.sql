with lessons as (

    select
        lesson_id
        , student_id
        , booked_at
        , hours_booked

    from {{ ref('stg_lessons') }}

)
, cycles as (

    select
        payment_id
        , student_id
        , cycle_start
        , cycle_start_date
        , cycle_end_exclusive

    from {{ ref('int_payment_cycles') }}

)
, mapped as (

    -- left join on purpose — a lesson that matches no cycle (payment_id is
    -- null below) is a real, testable condition, not something to silently
    -- drop with an inner join. The join itself needs cycle_start's exact
    -- timestamp, not cycle_start_date: a booking on the same calendar date
    -- but before the exact payment instant belongs to the previous cycle.
    select
        lessons.lesson_id
        , lessons.student_id
        , lessons.booked_at
        , lessons.booked_at::date as booked_date
        , lessons.hours_booked
        , cycles.payment_id
        , cycles.cycle_start
        , date_diff('day', cycles.cycle_start_date, lessons.booked_at::date)
            as day_in_cycle

    from lessons
    left join cycles
        on
            lessons.student_id = cycles.student_id
            and lessons.booked_at >= cycles.cycle_start
            and lessons.booked_at < cycles.cycle_end_exclusive

)

select * from mapped
