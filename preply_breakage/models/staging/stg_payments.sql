with source as (

    select * from {{ source('preply_raw', 'raw_payments') }}

)

, renamed as (

    select
        try_cast(payment_id as bigint) as payment_id
        , try_cast(student_id as bigint) as student_id
        , try_cast(payment_ts as timestamp) as payment_at
        -- "hours" is the plan allocation, not hours booked (that lives in
        -- stg_lessons.hours_booked) — renamed to remove the ambiguity.
        , try_cast(hours as smallint) as plan_hours
        , try_cast(price_per_hour_usd as decimal(10, 2)) as price_per_hour_usd

    from source

)

select * from renamed
