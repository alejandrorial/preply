{{ config(severity='warn') }}

-- Both figures are bounded at 0 by construction (least()/greatest() clamps
-- in fct_payment_breakage_daily) — this is a sanity check on that
-- invariant holding, not a business rule on its own.
select
    payment_id
    , snapshot_date
    , breakage_usd
    , commission_revenue_usd

from {{ ref('mart_breakage_daily') }}
where breakage_usd < 0 or commission_revenue_usd < 0
