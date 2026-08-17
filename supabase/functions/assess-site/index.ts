// LandBank V2 technical site assessment
// Open-data providers only: PVGIS + Planning Data API.
// Runs server-side because PVGIS does not allow browser AJAX.

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type, x-landbank-assess-key',
};
const ASSESS_KEY = '4472'; // temporary single-user gate, matching current LandBank architecture

type Row = Record<string, any>;

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}
function clamp(v: number, lo = 0, hi = 100) {
  return Math.max(lo, Math.min(hi, v));
}
function round1(v: number) { return Math.round(v * 10) / 10; }

async function rest(base: string, service: string, path: string, opt: {method?:string, body?:unknown, prefer?:string} = {}) {
  const headers: Record<string,string> = {
    apikey: service,
    Authorization: `Bearer ${service}`,
    'Content-Type': 'application/json',
  };
  if (opt.prefer) headers.Prefer = opt.prefer;
  const r = await fetch(`${base}/rest/v1/${path}`, {
    method: opt.method || 'GET', headers,
    body: opt.body == null ? undefined : JSON.stringify(opt.body),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`Supabase ${r.status}: ${text.slice(0,600)}`);
  return text ? JSON.parse(text) : null;
}

async function getSite(base: string, service: string, siteId: string) {
  const rows = await rest(base, service, `lb_sites?id=eq.${encodeURIComponent(siteId)}&select=*`);
  return rows?.[0] || null;
}

async function pvgis(lat: number, lon: number) {
  const q = new URLSearchParams({
    lat: String(lat), lon: String(lon), peakpower: '1', loss: '14',
    mountingplace: 'free', optimalinclination: '1', outputformat: 'json',
  });
  const url = `https://re.jrc.ec.europa.eu/api/v5_3/PVcalc?${q}`;
  const r = await fetch(url, { headers: { 'User-Agent': 'LandBank-V2/1.0' } });
  const text = await r.text();
  if (!r.ok) throw new Error(`PVGIS ${r.status}: ${text.slice(0,500)}`);
  const body = JSON.parse(text);
  const fixed = body?.outputs?.totals?.fixed || {};
  const annualKwhPerKwp = Number(fixed.E_y || 0);
  // Transparent UK-oriented normalization only for prioritisation, not engineering design.
  const score = annualKwhPerKwp > 0 ? round1(clamp((annualKwhPerKwp - 750) / 3.5)) : null;
  return {
    score,
    annual_kwh_per_kwp: annualKwhPerKwp || null,
    annual_irradiation_kwh_m2: Number(fixed['H(i)_y'] || 0) || null,
    system_loss_pct: 14,
    mounting: 'free-standing',
    optimal_inclination: true,
    source_url: url,
    raw: body,
  };
}

const CONSTRAINTS = [
  'flood-risk-zone',
  'green-belt',
  'conservation-area',
  'listed-building',
  'scheduled-monument',
  'site-of-special-scientific-interest',
  'ancient-woodland',
  'article-4-direction-area',
  'tree-preservation-zone',
];
const PENALTY: Record<string,number> = {
  'site-of-special-scientific-interest': 30,
  'ancient-woodland': 25,
  'scheduled-monument': 25,
  'flood-risk-zone': 20,
  'listed-building': 15,
  'green-belt': 10,
  'conservation-area': 10,
  'article-4-direction-area': 5,
  'tree-preservation-zone': 5,
};

async function planning(lat: number, lon: number) {
  const q = new URLSearchParams({ latitude:String(lat), longitude:String(lon), limit:'100' });
  CONSTRAINTS.forEach(d => q.append('dataset', d));
  q.append('field','entity'); q.append('field','name'); q.append('field','dataset'); q.append('field','reference');
  const url = `https://www.planning.data.gov.uk/entity.json?${q}`;
  const r = await fetch(url, { headers: { 'User-Agent': 'LandBank-V2/1.0' } });
  const text = await r.text();
  if (!r.ok) throw new Error(`Planning Data ${r.status}: ${text.slice(0,500)}`);
  const body = JSON.parse(text);
  const entities: Row[] = body?.entities || [];
  const byDataset: Record<string,number> = {};
  for (const e of entities) byDataset[e.dataset] = (byDataset[e.dataset] || 0) + 1;
  // Avoid double-penalising multiple features in the same designation dataset.
  const penalty = Object.keys(byDataset).reduce((sum,d)=>sum+(PENALTY[d]||0),0);
  const score = round1(clamp(100 - penalty));
  return {
    score,
    constraint_count: entities.length,
    datasets: byDataset,
    constraints: entities.map(e => ({entity:e.entity,name:e.name,dataset:e.dataset,reference:e.reference})),
    caveat: 'Point screening only. Absence of returned entities does not prove a site is constraint-free; dataset coverage varies and parcel-level screening remains required.',
    source_url: url,
    raw: body,
  };
}

function availableWeighted(site: Row, overrides: Row = {}) {
  const candidates: Array<[unknown,number]> = [
    [overrides.grid_score ?? site.grid_score, 25],
    [overrides.land_score ?? site.land_score, 20],
    [overrides.planning_score ?? site.planning_score, 15],
    [overrides.agricultural_score, 10],
    [overrides.topography_score, 10],
    [overrides.solar_score ?? site.solar_score, 10],
    [overrides.ownership_score ?? site.ownership_score, 10],
  ];
  const values: Array<[number,number]> = candidates
    .filter(([raw]) => raw !== null && raw !== undefined && raw !== '' && Number.isFinite(Number(raw)))
    .map(([raw,w]) => [Number(raw),w]);
  if (!values.length) return null;
  const weight = values.reduce((a,[,w])=>a+w,0);
  return round1(values.reduce((a,[v,w])=>a+v*w,0)/weight);
}

async function upsertAssessment(base:string, service:string, row:Row) {
  return rest(base, service, 'lb_site_assessments?on_conflict=site_id,assessment_type,provider', {
    method:'POST', body:[row], prefer:'resolution=merge-duplicates,return=minimal'
  });
}

Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response('ok', {headers:cors});
  if (req.method !== 'POST') return json({error:'POST required'},405);
  if (req.headers.get('x-landbank-assess-key') !== ASSESS_KEY) return json({error:'unauthorised'},401);
  try {
    const input = await req.json();
    const siteId = String(input?.site_id || '');
    if (!siteId) return json({error:'site_id required'},400);
    const base = Deno.env.get('SUPABASE_URL');
    const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!base || !service) throw new Error('Supabase service environment unavailable');
    const site = await getSite(base, service, siteId);
    if (!site) return json({error:'site not found'},404);
    if (site.lat == null || site.lng == null) return json({error:'site has no coordinates'},422);

    const providers = Array.isArray(input?.providers) && input.providers.length ? input.providers : ['pvgis','planning'];
    const result: Row = { site_id:siteId, site_name:site.name, lat:site.lat, lng:site.lng, assessed_at:new Date().toISOString() };
    const patch: Row = { updated_at:new Date().toISOString() };

    if (providers.includes('pvgis')) {
      try {
        const x = await pvgis(Number(site.lat),Number(site.lng));
        result.pvgis = {score:x.score, annual_kwh_per_kwp:x.annual_kwh_per_kwp, annual_irradiation_kwh_m2:x.annual_irradiation_kwh_m2};
        patch.solar_score = x.score;
        await upsertAssessment(base,service,{site_id:siteId,assessment_type:'solar',score:x.score,status:'screened',raw_data:x.raw,summary:{annual_kwh_per_kwp:x.annual_kwh_per_kwp,annual_irradiation_kwh_m2:x.annual_irradiation_kwh_m2,system_loss_pct:x.system_loss_pct,mounting:x.mounting,optimal_inclination:x.optimal_inclination},provider:'PVGIS 5.3',source_ref:x.source_url,assessed_at:new Date().toISOString()});
      } catch(e) { result.pvgis={error:e instanceof Error?e.message:String(e)}; }
    }

    if (providers.includes('planning')) {
      try {
        const x = await planning(Number(site.lat),Number(site.lng));
        result.planning={score:x.score,constraint_count:x.constraint_count,datasets:x.datasets,caveat:x.caveat};
        patch.planning_score=x.score;
        await upsertAssessment(base,service,{site_id:siteId,assessment_type:'planning',score:x.score,status:x.constraint_count?'constraints_found':'no_point_constraints_returned',raw_data:x.raw,summary:{constraint_count:x.constraint_count,datasets:x.datasets,constraints:x.constraints,caveat:x.caveat},provider:'Planning Data API',source_ref:x.source_url,assessed_at:new Date().toISOString()});
      } catch(e) { result.planning={error:e instanceof Error?e.message:String(e)}; }
    }

    patch.site_score = availableWeighted(site,patch);
    await rest(base,service,`lb_sites?id=eq.${encodeURIComponent(siteId)}`,{method:'PATCH',body:patch,prefer:'return=minimal'});
    result.site_score = patch.site_score;
    return json(result);
  } catch(e) {
    return json({error:e instanceof Error?e.message:String(e)},500);
  }
});
