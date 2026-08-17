alter table public.lb_sites add column if not exists location_geom geometry(Point,4326);
update public.lb_sites set location_geom=ST_SetSRID(ST_MakePoint(lng,lat),4326) where lat is not null and lng is not null and location_geom is null;
create index if not exists lb_sites_location_geom_gix on public.lb_sites using gist(location_geom);

create or replace function public.lb_sync_site_location_geom()
returns trigger language plpgsql as $$
begin
  if new.lat is not null and new.lng is not null then new.location_geom:=ST_SetSRID(ST_MakePoint(new.lng,new.lat),4326); else new.location_geom:=null; end if;
  return new;
end;$$;

drop trigger if exists lb_sites_location_geom_sync on public.lb_sites;
create trigger lb_sites_location_geom_sync before insert or update of lat,lng on public.lb_sites for each row execute function public.lb_sync_site_location_geom();
