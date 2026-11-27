-- Singular test | guards the invariant behind the FK fix.
--
-- Every week_date_key on a fact must exist in dim_date. That held only because the
-- ingestion window starts on a Monday; when it started on a Tuesday (2019-01-01), the
-- first week's Monday fell outside the spine and 12,460 fact rows had a dangling FK.
-- This asserts the invariant directly, so the relationships tests can never be
-- satisfied by accident.

select
    min(full_date)                                   as spine_start,
    extract(isodow from min(full_date))              as spine_start_isodow
from {{ ref('dim_date') }}
having extract(isodow from min(full_date)) <> 1
