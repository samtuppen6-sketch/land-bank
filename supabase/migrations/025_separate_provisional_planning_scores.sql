-- Early prototype point checks are retained in lb_site_assessments as evidence,
-- but they must not populate the portfolio-grade planning_score.
update public.lb_sites s
set planning_score=null,updated_at=now()
where planning_score is not null
  and exists(
    select 1 from public.lb_site_assessments a
    where a.site_id=s.id and a.assessment_type='planning' and a.provider='Planning Data API'
  );

select public.lb_recalculate_site_score(id)
from public.lb_sites s
where exists(
  select 1 from public.lb_site_assessments a
  where a.site_id=s.id and a.assessment_type='planning' and a.provider='Planning Data API'
);
