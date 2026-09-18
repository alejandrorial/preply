with source as (

    select
        lesson_id
        , student_id
        , booking_ts
        , hours_booked

    from {{ source('preply_raw', 'raw_lessons') }}

)
, renamed as (

    select
        try_cast(lesson_id as bigint) as lesson_id
        , try_cast(student_id as bigint) as student_id
        , try_cast(booking_ts as timestamp) as booked_at
        , try_cast(hours_booked as decimal(10, 2)) as hours_booked

    from source

)

select * from renamed
