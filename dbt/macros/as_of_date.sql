{%- macro as_of_date() -%}
{#
    Point in time the project treats as "today".
    - Default (`as_of_date` in dbt_project.yml): the dataset's frozen
      AS_OF_DATE, 2026-04-17 — the case's "assume today is the last day
      covered by the dataset". Without it, a real current_date leaves every
      cycle in this fixed dataset closed and nothing to estimate.
    - With `--vars '{as_of_date: null}'`: current_date, which is what a real
      daily production run would use.
    - With any other date: a backfill / debugging a specific day.
    Centralized here so the literal isn't repeated in every model. Every
    Jinja tag here is whitespace-trimmed on purpose (`{%-`/`-%}`) so this
    always renders as a single bare token, safe to drop into the middle of
    an expression or a comment without stray newlines breaking either.
#}
{%- set override = var('as_of_date', none) -%}
{%- if override -%}
    date '{{ override }}'
{%- else -%}
    current_date
{%- endif -%}
{%- endmacro -%}
