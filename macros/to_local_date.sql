{#-
  MLR-008: activity dates are computed in the USER'S local time zone.
  Raw events land in UTC; a 9pm workflow run in Los Angeles is "tomorrow" in UTC.
  Dispatched so the same model compiles on Postgres/DuckDB, Snowflake and Databricks.
-#}
{% macro to_local_date(utc_ts, tz) -%}
  {{ return(adapter.dispatch('to_local_date', 'lanternly_metrics')(utc_ts, tz)) }}
{%- endmacro %}

{% macro default__to_local_date(utc_ts, tz) -%}
  cast(({{ utc_ts }} at time zone 'UTC') at time zone {{ tz }} as date)
{%- endmacro %}

{% macro snowflake__to_local_date(utc_ts, tz) -%}
  cast(convert_timezone('UTC', {{ tz }}, {{ utc_ts }}) as date)
{%- endmacro %}

{% macro databricks__to_local_date(utc_ts, tz) -%}
  cast(from_utc_timestamp({{ utc_ts }}, {{ tz }}) as date)
{%- endmacro %}
