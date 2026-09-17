with source as (

    select * from {{ source('preply_raw', 'raw_students') }}

)

, renamed as (

    select
        try_cast(student_id as bigint) as student_id
        , try_cast(join_ts as timestamp) as joined_at
        , try_cast(country_code as varchar) as country_code
        , try_cast(acquisition_channel as varchar) as acquisition_channel
        , try_cast(persona as varchar) as persona
        , try_cast(first_subject as varchar) as first_subject

    from source

)

select * from renamed
