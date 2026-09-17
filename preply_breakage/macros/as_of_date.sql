{% macro as_of_date() %}
{#
    Point in time the project treats as "today".
    - No override: current_date (normal production behavior, one run per day).
    - With `--vars '{as_of_date: 2026-04-17}'`: pins that date, to reproduce
      the case study with the dataset's frozen AS_OF_DATE, or for
      backfills/debugging.
    Centralized here so the literal isn't repeated in every model.
#}
{%- set override = var('as_of_date', none) -%}
{%- if override -%}
    date '{{ override }}'
{%- else -%}
    current_date
{%- endif -%}
{% endmacro %}
