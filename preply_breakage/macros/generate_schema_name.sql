{#
    dbt's default behavior prefixes a custom `+schema` config with the
    target's schema (e.g. `main_stg_preply`). We want the literal schema
    name declared in dbt_project.yml (`stg_preply`, `working_preply`,
    `marts_preply`), so we override the default macro. This is the standard
    override documented in dbt's own docs, not a project-specific hack.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- if custom_schema_name is none -%}

        {{ target.schema }}

    {%- else -%}

        {{ custom_schema_name | trim }}

    {%- endif -%}

{%- endmacro %}
