{{ config(severity='warn') }}

-- A booking with 0 or fewer hours makes no business sense. Row-level value
-- quality, not grain — warn so it doesn't block the rest of the refresh.
-- The test fails if it returns any rows.
select *
from {{ ref('stg_lessons') }}
where hours_booked <= 0
