-- MLR-010: the ONE place where test / QA accounts are removed. Every downstream model
-- joins to this set, so no dashboard can forget the filter.
select *
from {{ ref('stg_accounts') }}
where not is_test_account
