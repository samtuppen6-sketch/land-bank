import { createClient } from 'npm:@supabase/supabase-js@2';

type Job = {
  id: string;
  opportunity_id: string | null;
  site_id: string | null;
  organisation_id: string;
  priority_score: number | null;
  providers: string[] | null;
  status: string;
  attempts: number | null;
  last_result: Record<string, unknown> | null;
};

type Org = {
  id: string;
  company_number: string | null;
  name: string | null;
  companies_house_updated_at: string | null;
};

const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), {
  status,
  headers: { 'Content-Type': 'application/json' },
});

function adminClient() {
  const url = Deno.env.get('SUPABASE_URL');
  let key = '';
  const modern = Deno.env.get('SUPABASE_SECRET_KEYS');
  if (modern) {
    try { key = JSON.parse(modern)?.default || ''; } catch { /* fallback below */ }
  }
  if (!key) key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  if (!url || !key) throw new Error('Missing Supabase admin credentials');
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

function companiesHouseAuth() {
  let raw = (Deno.env.get('COMPANIES_HOUSE_API_KEY') || '').trim();
  if (!raw) throw new Error('Missing COMPANIES_HOUSE_API_KEY');
  if ((raw.startsWith('"') && raw.endsWith('"')) || (raw.startsWith("'") && raw.endsWith("'"))) raw = raw.slice(1, -1).trim();
  if (/^basic\s+/i.test(raw)) return raw;
  return `Basic ${btoa(`${raw}:`)}`;
}

function addressText(a: Record<string, unknown> | null | undefined) {
  if (!a) return null;
  const fields = ['premises','address_line_1','address_line_2','locality','region','postal_code','country'];
  const parts = fields.map(k => String(a[k] ?? '').trim()).filter(Boolean);
  return parts.length ? parts.join(', ') : null;
}

function personParts(fullName: string) {
  const full = fullName.trim();
  if (!full) return { first_name: null, last_name: null };
  if (full.includes(',')) {
    const [last, rest = ''] = full.split(',', 2);
    const first = rest.trim().split(/\s+/).filter(Boolean)[0] || null;
    return { first_name: first, last_name: last.trim() || null };
  }
  const bits = full.split(/\s+/).filter(Boolean);
  return { first_name: bits[0] || null, last_name: bits.length > 1 ? bits[bits.length - 1] : null };
}

async function chGet(path: string, auth: string) {
  const res = await fetch(`https://api.company-information.service.gov.uk${path}`, {
    headers: { Authorization: auth, Accept: 'application/json' },
  });
  let body: any = null;
  try { body = await res.json(); } catch { body = null; }
  return { status: res.status, ok: res.ok, body };
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'POST required' }, 405);
  const suppliedBatchKey = req.headers.get('x-landbank-batch-key') || '';
  if (!suppliedBatchKey) return json({ error: 'unauthorised' }, 401);

  try {
    const sb = adminClient();
    const { data: validBatchKey, error: keyError } = await sb.rpc('lb_batch_key_valid', { p_key: suppliedBatchKey });
    if (keyError || !validBatchKey) return json({ error: 'unauthorised' }, 401);

    const auth = companiesHouseAuth();
    let requestedLimit = 50;
    try {
      const body = await req.json();
      if (Number.isFinite(Number(body?.limit))) requestedLimit = Number(body.limit);
    } catch { /* body optional */ }
    const limit = Math.max(1, Math.min(100, Math.floor(requestedLimit)));

    const { data: jobsRaw, error: jobsError } = await sb
      .from('lb_enrichment_queue_jobs')
      .select('id,opportunity_id,site_id,organisation_id,priority_score,providers,status,attempts,last_result')
      .eq('status', 'queued')
      .contains('providers', ['companies_house'])
      .lte('next_attempt_at', new Date().toISOString())
      .order('priority_score', { ascending: false })
      .limit(limit);

    if (jobsError) throw jobsError;
    const jobs = (jobsRaw || []) as Job[];
    if (!jobs.length) return json({ status: 'ok', processed: 0, message: 'No Companies House jobs ready' });

    const orgIds = [...new Set(jobs.map(j => j.organisation_id).filter(Boolean))];
    const { data: orgsRaw, error: orgsError } = await sb
      .from('lb_organisations')
      .select('id,company_number,name,companies_house_updated_at')
      .in('id', orgIds);
    if (orgsError) throw orgsError;
    const orgMap = new Map((orgsRaw || []).map((o: Org) => [o.id, o]));

    let succeeded = 0, notFound = 0, retried = 0, skipped = 0;
    const errors: Array<{job_id:string; company_number?:string|null; error:string}> = [];

    for (const job of jobs) {
      const org = orgMap.get(job.organisation_id);
      const companyNumber = org?.company_number?.trim();
      const remaining = (job.providers || []).filter(p => p !== 'companies_house');
      const now = new Date().toISOString();

      if (!org || !companyNumber) {
        await sb.from('lb_enrichment_events').insert({
          prospect_key: job.opportunity_id || job.id,
          organisation_id: job.organisation_id || null,
          site_id: job.site_id || null,
          provider: 'companies_house', enrichment_type: 'company_profile', status: 'skipped',
          error_message: 'missing_company_number', created_at: now,
        });
        await sb.from('lb_enrichment_queue_jobs').update({
          providers: remaining,
          status: remaining.length ? 'queued' : 'completed',
          completed_at: remaining.length ? null : now,
          locked_at: null,
          updated_at: now,
        }).eq('id', job.id);
        skipped++;
        continue;
      }

      await sb.from('lb_enrichment_queue_jobs').update({ status: 'processing', locked_at: now, updated_at: now }).eq('id', job.id);

      try {
        const no = encodeURIComponent(companyNumber);
        const [profileRes, officersRes] = await Promise.all([
          chGet(`/company/${no}`, auth),
          chGet(`/company/${no}/officers?items_per_page=35`, auth),
        ]);

        if ([401,403].includes(profileRes.status) || [401,403].includes(officersRes.status)) {
          await sb.from('lb_enrichment_queue_jobs').update({ status: 'queued', locked_at: null, last_error: 'companies_house_auth_failed', updated_at: now }).eq('id', job.id);
          return json({ status: 'halted', processed: succeeded + notFound + skipped, error: 'Companies House authentication failed' }, 502);
        }

        if (profileRes.status === 429 || officersRes.status === 429) {
          const next = new Date(Date.now() + 6 * 60 * 1000).toISOString();
          await sb.from('lb_enrichment_queue_jobs').update({
            status: 'queued', locked_at: null, attempts: (job.attempts || 0) + 1,
            next_attempt_at: next, last_error: 'companies_house_rate_limited', updated_at: now,
          }).eq('id', job.id);
          retried++;
          continue;
        }

        if (profileRes.status === 404) {
          await sb.from('lb_organisations').update({
            company_status: 'not_found', companies_house_updated_at: now, updated_at: now,
          }).eq('id', org.id);
          await sb.from('lb_enrichment_events').insert({
            prospect_key: job.opportunity_id || job.id, organisation_id: org.id, site_id: job.site_id || null,
            provider: 'companies_house', enrichment_type: 'company_profile', status: 'not_found',
            confidence: 100, source_ref: companyNumber, payload: { company_number: companyNumber }, created_at: now,
          });
          await sb.from('lb_enrichment_queue_jobs').update({
            providers: remaining, status: remaining.length ? 'queued' : 'completed',
            completed_at: remaining.length ? null : now, locked_at: null, last_error: null,
            last_result: { ...(job.last_result || {}), companies_house: { status: 'not_found', checked_at: now } },
            updated_at: now,
          }).eq('id', job.id);
          notFound++;
          continue;
        }

        if (!profileRes.ok || !officersRes.ok) {
          throw new Error(`Companies House HTTP ${profileRes.status}/${officersRes.status}`);
        }

        const company = profileRes.body || {};
        const activeOfficers = (officersRes.body?.items || [])
          .filter((x: any) => !x.resigned_on && x.officer_role !== 'corporate-director')
          .slice(0, 35);

        const orgUpdate = {
          name: company.company_name || org.name,
          company_status: company.company_status || null,
          sic_text: Array.isArray(company.sic_codes) ? company.sic_codes.join(', ') : null,
          registered_address: addressText(company.registered_office_address),
          companies_house_updated_at: now,
          updated_at: now,
        };
        const { error: orgUpdateError } = await sb.from('lb_organisations').update(orgUpdate).eq('id', org.id);
        if (orgUpdateError) throw orgUpdateError;

        const { data: existingLinks } = await sb
          .from('lb_organisation_people')
          .select('person_id,role,lb_people(full_name)')
          .eq('organisation_id', org.id);
        const linkMap = new Map<string, string>();
        for (const link of (existingLinks || []) as any[]) {
          const fullName = String(link.lb_people?.full_name || '').trim().toUpperCase();
          if (fullName) linkMap.set(`${fullName}|${String(link.role || '')}`, link.person_id);
        }

        await sb.from('lb_organisation_people').update({ is_primary: false }).eq('organisation_id', org.id).eq('source', 'companies_house');

        for (let i = 0; i < activeOfficers.length; i++) {
          const officer = activeOfficers[i];
          const fullName = String(officer.name || '').trim();
          const role = String(officer.officer_role || 'officer');
          if (!fullName) continue;
          const key = `${fullName.toUpperCase()}|${role}`;
          let personId = linkMap.get(key) || null;
          const parts = personParts(fullName);

          if (!personId) {
            const { data: inserted, error: personError } = await sb.from('lb_people').insert({
              full_name: fullName,
              first_name: parts.first_name,
              last_name: parts.last_name,
              occupation: officer.occupation || null,
            }).select('id').single();
            if (personError) throw personError;
            personId = inserted.id;
          } else if (officer.occupation) {
            await sb.from('lb_people').update({ occupation: officer.occupation, updated_at: now }).eq('id', personId);
          }

          const { error: linkError } = await sb.from('lb_organisation_people').upsert({
            organisation_id: org.id,
            person_id: personId,
            role,
            appointed_on: officer.appointed_on || null,
            resigned_on: null,
            is_primary: i === 0,
            source: 'companies_house',
          }, { onConflict: 'organisation_id,person_id,role' });
          if (linkError) throw linkError;
        }

        const summary = {
          company_number: company.company_number || companyNumber,
          company_name: company.company_name || org.name,
          company_status: company.company_status || null,
          sic_codes: company.sic_codes || [],
          officer_count: activeOfficers.length,
          has_charges: company.has_charges ?? null,
          has_insolvency_history: company.has_insolvency_history ?? null,
          checked_at: now,
        };

        await sb.from('lb_enrichment_events').insert({
          prospect_key: job.opportunity_id || job.id,
          organisation_id: org.id,
          site_id: job.site_id || null,
          provider: 'companies_house', enrichment_type: 'company_profile_and_officers', status: 'success',
          confidence: 100, source_ref: companyNumber, payload: summary, created_at: now,
        });

        await sb.from('lb_enrichment_queue_jobs').update({
          providers: remaining,
          status: remaining.length ? 'queued' : 'completed',
          completed_at: remaining.length ? null : now,
          locked_at: null,
          last_error: null,
          last_result: { ...(job.last_result || {}), companies_house: summary },
          updated_at: now,
        }).eq('id', job.id);
        succeeded++;
      } catch (e) {
        const message = e instanceof Error ? e.message : String(e);
        const attempts = (job.attempts || 0) + 1;
        const abandonCH = attempts >= 3;
        const providers = abandonCH ? remaining : (job.providers || []);
        const status = providers.length ? 'queued' : (abandonCH ? 'failed' : 'queued');
        await sb.from('lb_enrichment_queue_jobs').update({
          providers,
          status,
          attempts,
          locked_at: null,
          next_attempt_at: new Date(Date.now() + (attempts * 10) * 60 * 1000).toISOString(),
          last_error: message.slice(0, 1000),
          updated_at: new Date().toISOString(),
        }).eq('id', job.id);
        await sb.from('lb_enrichment_events').insert({
          prospect_key: job.opportunity_id || job.id,
          organisation_id: job.organisation_id || null,
          site_id: job.site_id || null,
          provider: 'companies_house', enrichment_type: 'company_profile_and_officers', status: abandonCH ? 'failed' : 'retry',
          source_ref: companyNumber, error_message: message.slice(0, 1000), created_at: new Date().toISOString(),
        });
        errors.push({ job_id: job.id, company_number: companyNumber, error: message });
        retried++;
      }
    }

    return json({ status: 'ok', selected: jobs.length, succeeded, not_found: notFound, retried, skipped, errors: errors.slice(0, 10) });
  } catch (e) {
    return json({ status: 'error', error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
