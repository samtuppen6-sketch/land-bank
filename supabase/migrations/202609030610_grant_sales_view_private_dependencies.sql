-- Required by the public security-invoker contact and sales views.
-- The private schema is not exposed through the Data API.

grant usage on schema private to authenticated;
grant select on private.lb_best_contact_points_cache to authenticated;

