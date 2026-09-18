{{ config(severity='warn') }}

-- A plan with 0 or fewer hours makes no business sense. Row-level value
-- quality, not grain — warn so it doesn't block the rest of the refresh.
-- The test fails if it returns any rows.
select *
from {{ ref('stg_payments') }}
where plan_hours <= 0
