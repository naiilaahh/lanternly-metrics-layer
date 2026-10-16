-- Day-grain time spine required by MetricFlow for cumulative metrics and time offsets.
{{ config(materialized='table') }}
select cast(date_day as date) as date_day
from (
    {{ dbt.date_spine(
        datepart="day",
        start_date="cast('2025-01-01' as date)",
        end_date="cast('2031-01-01' as date)"
    ) }}
) as spine(date_day)
