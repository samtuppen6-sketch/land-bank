update public.lb_contact_points
set provider='website_crawl',discovery_method='published_website',source_url='https://bodensgroup.com/',confidence=90,
    verification_status='probable',do_not_contact=false,label='Published on website [normalised]'
where id='816040df-278b-42fb-ab74-55f94d9b2df6'::uuid;

update public.lb_contact_points
set provider='website_crawl',discovery_method='published_website',source_url='https://www.greenheath.co.uk/',confidence=90,
    verification_status='probable',do_not_contact=false,label='Published on website [normalised]'
where id='549c6bf9-c4aa-4496-bbb0-da98f8857503'::uuid;

update public.lb_contact_points
set verification_status='invalid',confidence=0,do_not_contact=true,is_primary=false,
    label=coalesce(label,'')||' [superseded malformed phone]'
where id in (
  '144a6fc4-30fd-4e25-ad9f-151d545a665e'::uuid,
  '4d065032-c728-4bf7-b712-8ee4e78b3ee1'::uuid
);

select public.lb_refresh_origination_scores();