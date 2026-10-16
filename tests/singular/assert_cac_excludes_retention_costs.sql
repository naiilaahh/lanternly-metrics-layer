-- MLR-012: Customer Success spend is tagged as a retention cost and must never be in CAC.
select *
from {{ ref('fct_company_costs_monthly') }}
where (channel = 'customer_success' and cost_type = 'acquisition')
   or (cost_type = 'acquisition' and channel is null)
