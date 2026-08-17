// LandBank V2 prospect enrichment Edge Function
// Provider keys stay in Supabase secrets rather than in the browser.
//
// Optional secrets:
//   COMPANIES_HOUSE_API_KEY
//   GOOGLE_PLACES_API_KEY
//   HUNTER_API_KEY
//
// POST body example:
// {
//   "company_number":"01234567",
//   "company_name":"Example Farms Ltd",
//   "town":"Lincoln",
//   "postcode":"LN1 1AA",
//   "director_name":"Jane Smith",
//   "domain":"examplefarms.co.uk",
//   "providers":["companies_house","google_places","hunter"]
// }

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

type Input = {
  company_number?: string;
  company_name?: string;
  town?: string;
  postcode?: string;
  director_name?: string;
  domain?: string;
  providers?: Array<'companies_house'|'google_places'|'hunter'>;
};

type NormalizedContact = {
  type: 'phone'|'email'|'website';
  value: string;
  provider: string;
  verification_status: 'verified'|'probable'|'catch_all'|'unknown'|'invalid';
  confidence: number;
  source_ref?: string;
  discovery_method: string;
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

function cleanName(s = '') {
  return s.toUpperCase()
    .replace(/\b(LIMITED|LTD|LLP|PLC|FARMS?|FARMING|AGRICULTURE|AGRICULTURAL|HOLDINGS?)\b/g, ' ')
    .replace(/[^A-Z0-9 ]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function normPc(s = '') { return s.toUpperCase().replace(/\s/g, ''); }
function outwardPc(s = '') { return normPc(s).slice(0, -3); }
function domainOnly(s = '') {
  return s.trim().toLowerCase().replace(/^https?:\/\//, '').replace(/^www\./, '').split('/')[0];
}
function nameTokens(s = '') {
  return new Set(cleanName(s).split(' ').filter(x => x.length >= 3));
}
function tokenOverlap(a = '', b = '') {
  const aa = nameTokens(a), bb = nameTokens(b);
  if (!aa.size || !bb.size) return 0;
  let hit = 0;
  aa.forEach(t => { if (bb.has(t)) hit++; });
  return hit / Math.max(aa.size, bb.size);
}
function splitPerson(full = '') {
  const p = full.trim().split(/\s+/).filter(Boolean);
  if (p.length < 2) return { first_name: '', last_name: '' };
  return { first_name: p[0], last_name: p[p.length - 1] };
}

async function companiesHouse(input: Input) {
  const key = Deno.env.get('COMPANIES_HOUSE_API_KEY');
  if (!key) return { provider:'companies_house', skipped:true, reason:'missing_api_key' };
  if (!input.company_number) return { provider:'companies_house', skipped:true, reason:'missing_company_number' };

  const auth = btoa(`${key}:`);
  const base = 'https://api.company-information.service.gov.uk';
  const no = encodeURIComponent(input.company_number);
  const [companyRes, officerRes] = await Promise.all([
    fetch(`${base}/company/${no}`, { headers:{ Authorization:`Basic ${auth}` } }),
    fetch(`${base}/company/${no}/officers?items_per_page=35`, { headers:{ Authorization:`Basic ${auth}` } })
  ]);

  const company = companyRes.ok ? await companyRes.json() : null;
  const officerBody = officerRes.ok ? await officerRes.json() : { items:[] };
  const officers = (officerBody.items || [])
    .filter((x:any) => !x.resigned_on && x.officer_role !== 'corporate-director')
    .map((x:any) => ({
      name: x.name,
      role: x.officer_role,
      occupation: x.occupation || '',
      appointed_on: x.appointed_on || null,
      address: x.address || null,
      farming_signal: /farm|agricult|land/i.test(`${x.occupation || ''} ${x.name || ''}`)
    }))
    .sort((a:any,b:any) => Number(b.farming_signal)-Number(a.farming_signal) || String(a.appointed_on||'').localeCompare(String(b.appointed_on||'')));

  return {
    provider:'companies_house',
    ok: companyRes.ok || officerRes.ok,
    company: company ? {
      company_number: company.company_number,
      company_name: company.company_name,
      company_status: company.company_status,
      sic_codes: company.sic_codes || [],
      registered_office_address: company.registered_office_address || null,
      has_charges: company.has_charges ?? null,
      has_insolvency_history: company.has_insolvency_history ?? null,
    } : null,
    officers,
    primary_director: officers[0] || null,
  };
}

async function googlePlaces(input: Input) {
  const key = Deno.env.get('GOOGLE_PLACES_API_KEY');
  if (!key) return { provider:'google_places', skipped:true, reason:'missing_api_key' };
  if (!input.company_name) return { provider:'google_places', skipped:true, reason:'missing_company_name' };

  const query = [input.company_name, input.town, input.postcode].filter(Boolean).join(' ');
  const res = await fetch('https://places.googleapis.com/v1/places:searchText', {
    method:'POST',
    headers:{
      'Content-Type':'application/json',
      'X-Goog-Api-Key':key,
      'X-Goog-FieldMask':'places.id,places.displayName,places.formattedAddress,places.nationalPhoneNumber,places.websiteUri,places.primaryType'
    },
    body:JSON.stringify({ textQuery:query, maxResultCount:5 })
  });
  if (!res.ok) return { provider:'google_places', ok:false, status:res.status, error:(await res.text()).slice(0,500) };
  const body = await res.json();
  const targetPc = normPc(input.postcode || '');
  const targetOut = outwardPc(input.postcode || '');
  const candidates = (body.places || []).map((p:any) => {
    const addr = p.formattedAddress || '';
    const addrPc = normPc(addr);
    const exactPc = !!targetPc && addrPc.includes(targetPc);
    const outward = !!targetOut && addrPc.includes(targetOut);
    const overlap = tokenOverlap(input.company_name || '', p.displayName?.text || '');
    const match_score = Math.min(100, Math.round((exactPc?55:outward?30:0) + overlap*40 + (p.websiteUri?5:0)));
    return {
      place_id:p.id,
      name:p.displayName?.text || '',
      formatted_address:addr,
      phone:p.nationalPhoneNumber || '',
      website:p.websiteUri || '',
      primary_type:p.primaryType || '',
      match_score,
      postcode_exact:exactPc,
      name_overlap:Math.round(overlap*100),
    };
  }).sort((a:any,b:any)=>b.match_score-a.match_score);

  const best = candidates[0] || null;
  const contacts: NormalizedContact[] = [];
  if (best?.phone) contacts.push({
    type:'phone', value:best.phone, provider:'google_places',
    verification_status:best.match_score>=80?'probable':'unknown',
    confidence:best.match_score, source_ref:best.place_id,
    discovery_method:'google_places_text_search'
  });
  if (best?.website) contacts.push({
    type:'website', value:best.website, provider:'google_places',
    verification_status:best.match_score>=80?'probable':'unknown',
    confidence:best.match_score, source_ref:best.place_id,
    discovery_method:'google_places_text_search'
  });

  return { provider:'google_places', ok:true, query, best, candidates, contacts };
}

async function hunter(input: Input) {
  const key = Deno.env.get('HUNTER_API_KEY');
  if (!key) return { provider:'hunter', skipped:true, reason:'missing_api_key' };
  const domain = domainOnly(input.domain || '');
  if (!domain && !input.company_name) return { provider:'hunter', skipped:true, reason:'missing_domain_or_company' };

  const root = 'https://api.hunter.io/v2';
  const domainQs = domain ? `domain=${encodeURIComponent(domain)}` : `company=${encodeURIComponent(input.company_name || '')}`;
  const domainRes = await fetch(`${root}/domain-search?${domainQs}&limit=10&api_key=${encodeURIComponent(key)}`);
  const domainBody = domainRes.ok ? await domainRes.json() : null;
  const resolvedDomain = domain || domainBody?.data?.domain || '';

  let finderBody:any = null;
  if (input.director_name && resolvedDomain) {
    const person = splitPerson(input.director_name);
    if (person.first_name && person.last_name) {
      const u = `${root}/email-finder?domain=${encodeURIComponent(resolvedDomain)}&first_name=${encodeURIComponent(person.first_name)}&last_name=${encodeURIComponent(person.last_name)}&api_key=${encodeURIComponent(key)}`;
      const fr = await fetch(u);
      if (fr.ok) finderBody = await fr.json();
    }
  }

  const contacts: NormalizedContact[] = [];
  const email = finderBody?.data?.email;
  const verification = finderBody?.data?.verification?.status || '';
  if (email) contacts.push({
    type:'email', value:email, provider:'hunter',
    verification_status: verification === 'valid' ? 'verified' : verification === 'accept_all' ? 'catch_all' : 'unknown',
    confidence: Math.round(Number(finderBody?.data?.score || 0)),
    source_ref:(finderBody?.data?.sources || [])[0]?.uri,
    discovery_method:'hunter_email_finder'
  });

  const published = (domainBody?.data?.emails || []).slice(0,10).map((e:any) => ({
    email:e.value,
    type:e.type,
    confidence:e.confidence,
    first_name:e.first_name,
    last_name:e.last_name,
    position:e.position,
    verification:e.verification?.status || null,
    sources:e.sources || []
  }));

  return {
    provider:'hunter', ok:domainRes.ok,
    domain:resolvedDomain,
    organization:domainBody?.data?.organization || null,
    pattern:domainBody?.data?.pattern || null,
    accept_all:domainBody?.data?.accept_all ?? null,
    published_emails:published,
    named_email:finderBody?.data || null,
    contacts
  };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers:cors });
  if (req.method !== 'POST') return json({ error:'POST required' }, 405);
  try {
    const input = await req.json() as Input;
    const requested = new Set(input.providers?.length ? input.providers : ['companies_house','google_places','hunter']);
    const results:any[] = [];

    // CH first: it can supply a director name used by Hunter.
    let working = { ...input };
    if (requested.has('companies_house')) {
      const ch:any = await companiesHouse(working);
      results.push(ch);
      if (!working.director_name && ch?.primary_director?.name) working.director_name = ch.primary_director.name;
    }

    // Google next: it can supply a domain used by Hunter.
    if (requested.has('google_places')) {
      const gp:any = await googlePlaces(working);
      results.push(gp);
      if (!working.domain && gp?.best?.website) working.domain = domainOnly(gp.best.website);
    }

    if (requested.has('hunter')) results.push(await hunter(working));

    const contacts = results.flatMap((r:any) => r.contacts || []);
    return json({
      input,
      resolved:{ director_name:working.director_name || null, domain:working.domain || null },
      contacts,
      providers:results,
      human_review_required: results.some((r:any) => r.provider === 'google_places' && r.best && r.best.match_score < 70)
    });
  } catch (e) {
    return json({ error:e instanceof Error ? e.message : String(e) }, 500);
  }
});
