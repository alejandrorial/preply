with progress as (

    -- cycle_start deliberately left out: nothing here uses it today. It
    -- would need to be added back in if curve_lookback_months (see below)
    -- ever gets wired up, since that filter needs it.
    select
        payment_id
        , plan_hours
        , is_renewal
        , day_in_cycle
        , hours_booked_to_date
        , is_closed

    from {{ ref('int_cycle_daily_progress') }}
    where is_closed

    -- Extension point, not wired up today: `curve_lookback_months` (see
    -- dbt_project.yml) is null, meaning "use the full history of closed
    -- cycles" — our current decision. If a lookback window is ever needed
    -- (product changes, seasonality), it would filter on `cycle_start`
    -- here, e.g. (written as plain text on purpose — a live Jinja call
    -- inside a SQL comment still gets rendered, not treated as inert docs):
    --   and cycle_start >= as_of_date() - interval '<N> months'

)
, per_payment_pct as (

    select
        plan_hours
        , is_renewal
        , day_in_cycle
        , payment_id
        , hours_booked_to_date / plan_hours as pct_booked

    from progress

)

select
    plan_hours
    , is_renewal
    , day_in_cycle
    , count(*) as n_closed_cycles
    -- Population average, not a per-payment value: at low day_in_cycle this
    -- is skewed heavily toward 0 (most payments haven't booked anything
    -- yet), not evenly spread across payments. See column doc in schema.yml.
    , avg(pct_booked) as avg_pct_booked
    , plan_hours::varchar
    || '|'
    || is_renewal::varchar
    || '|'
    || day_in_cycle::varchar as segment_day_key

from per_payment_pct
group by plan_hours, is_renewal, day_in_cycle
