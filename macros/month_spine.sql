{#- One row per calendar month between the metrics start month and the last closed month (inclusive). -#}
{% macro month_spine() -%}
  select cast(month_start as date) as month_start
  from (
    {{ dbt.date_spine(
        datepart="month",
        start_date="cast('" ~ var('metrics_start_month') ~ "' as date)",
        end_date=dbt.dateadd("month", 1, "cast('" ~ var('last_closed_month') ~ "' as date)")
    ) }}
  ) as spine(month_start)
{%- endmacro %}
