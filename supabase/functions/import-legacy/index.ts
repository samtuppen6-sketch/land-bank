// LandBank V2 legacy importer
// Pulls the fixed source datasets from this repository and upserts them into V2.
// It never deletes records and is safe to rerun.

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type, x-landbank-import-key',
};

const FARMS_URL = 'https://raw.githubusercontent.com/samtuppen6-sketch/land-bank/main/farms.json';
const CONTACTS_URL = 'https://raw.githubusercontent.com/samtuppen6-sketch/land-bank/main/contacts.json';
const IMPORT_KEY = '4472'; // same temporary single-user gate already used by the legacy app
const BATCH = 150;

type AnyRow = Record<string, any>;

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

function chunks<T>(rows: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < rows.length; i += size) out.push(rows.slice(i, i + size));
  return out;
}

function str(v: unknown): string {
  return v == null ? '' : String(v).trim();
}

function domainOnly(v: unknown): string | null {
  const s = str(v);
  if (!s) return null;
  try {
    const u = new URL(/^https?:\/\//i.test(s) ? s : `https://${s}`);
    return u.hostname.toLowerCase().replace(/^www\./, '');
  } catch {
    return s.toLowerCase().replace(/^https?:\/\//, '').replace(/^www\./, '').split('/')[0] || null;
  }
}

function confidenceNumber(v: unknown): number {
  const s = str(v).toLowerCase();
  if (s === 'high') return 90;
  if (s === 'medium') return 65;
  if (s === 'check') return 30;
  return 50;
}

function stageFor(contact: AnyRow): string {
  return str(contact?.phone) && str(contact?.confidence).toLowerCase() !== 'check'
    ? 'contact_ready'
    : 'identified';
}

function probabilityFor(stage: string): number {
  return stage === 'contact_ready' ? 8 : 3;
}

function salesScore(contact: AnyRow): number {
  let score = 0;
  const confidence = str(contact?.confidence).toLowerCase();
  if (str(contact?.director) || (Array.isArray(contact?.directors) && contact.directors.length)) score += 15;
  if (str(contact?.phone)) score += confidence === 'check' ? 5 : 15;
  if (str(contact?.email)) score += /unverified|inferred|guess/i.test(str(contact?.email_status)) ? 3 : 10;
  if (str(contact?.website)) score += 5;
  return score;
}

async function rest(base: string, service: string, path: string, rows: AnyRow[], conflict: string) {
  if (!rows.length) return [];
  const url = `${base}/rest/v1/${path}?on_conflict=${encodeURIComponent(conflict)}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      apikey: service,
      Authorization: `Bearer ${service}`,
      'Content-Type': 'application/json',
      Prefer: 'resolution=merge-duplicates,return=representation',
    },
    body: JSON.stringify(rows),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${path} ${res.status}: ${text.slice(0, 800)}`);
  return text ? JSON.parse(text) : [];
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'POST required' }, 405);
  if (req.headers.get('x-landbank-import-key') !== IMPORT_KEY) return json({ error: 'unauthorised' }, 401);

  try {
    const body = await req.json().catch(() => ({}));
    const dryRun = body?.dry_run === true;
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !serviceKey) return json({ error: 'Supabase service environment is unavailable' }, 500);

    const [farmsRes, contactsRes] = await Promise.all([
      fetch(FARMS_URL, { headers: { 'User-Agent': 'LandBank-V2-Importer' } }),
      fetch(CONTACTS_URL, { headers: { 'User-Agent': 'LandBank-V2-Importer' } }),
    ]);
    if (!farmsRes.ok) throw new Error(`farms.json ${farmsRes.status}`);
    if (!contactsRes.ok) throw new Error(`contacts.json ${contactsRes.status}`);

    const farmData = await farmsRes.json();
    const contactData = await contactsRes.json();
    const fields: string[] = Array.isArray(farmData?.fields) ? farmData.fields : [];
    const sourceRows: any[][] = Array.isArray(farmData?.rows) ? farmData.rows : [];
    const contacts: AnyRow = contactData?.contacts || {};

    const farms: AnyRow[] = sourceRows.map((r: any[]) => {
      const o: AnyRow = {};
      fields.forEach((f, i) => { o[f] = r[i]; });
      return o;
    }).filter(o => str(o.no));

    const valid = farms.filter(o => str(o.name));
    const contactRecords = valid.filter(o => contacts[str(o.no)]);
    const ready = contactRecords.filter(o => stageFor(contacts[str(o.no)]) === 'contact_ready').length;

    if (dryRun) {
      return json({
        dry_run: true,
        source_farms: sourceRows.length,
        valid_farms: valid.length,
        contact_records: contactRecords.length,
        contact_ready: ready,
        fields,
        sample: valid.slice(0, 3),
      });
    }

    const totals = {
      source_farms: sourceRows.length,
      valid_farms: valid.length,
      organisations: 0,
      sites: 0,
      opportunities: 0,
      qualifications: 0,
      contact_points: 0,
    };

    for (const batch of chunks(valid, BATCH)) {
      const orgInput = batch.map(f => {
        const c = contacts[str(f.no)] || {};
        return {
          company_number: str(f.no),
          name: str(f.name),
          organisation_type: 'company',
          sic_text: str(f.sic) || null,
          registered_address: [str(f.addr), str(f.town), str(f.pc)].filter(Boolean).join(', ') || null,
          website: str(c.website) || null,
          domain: domainOnly(c.website),
          updated_at: new Date().toISOString(),
        };
      });
      const orgRows = await rest(supabaseUrl, serviceKey, 'lb_organisations', orgInput, 'company_number');
      totals.organisations += orgRows.length;
      const orgByNo = new Map(orgRows.map((r: AnyRow) => [str(r.company_number), r]));

      const siteInput = batch.map(f => ({
        legacy_company_number: str(f.no),
        name: str(f.name),
        address_line: str(f.addr) || null,
        town: str(f.town) || null,
        county: str(f.county) || null,
        postcode: str(f.pc) || null,
        lat: Number.isFinite(Number(f.lat)) ? Number(f.lat) : null,
        lng: Number.isFinite(Number(f.lng)) ? Number(f.lng) : null,
        parcel_count: Number.isFinite(Number(f.land)) ? Number(f.land) : 0,
        updated_at: new Date().toISOString(),
      }));
      const siteRows = await rest(supabaseUrl, serviceKey, 'lb_sites', siteInput, 'legacy_company_number');
      totals.sites += siteRows.length;
      const siteByNo = new Map(siteRows.map((r: AnyRow) => [str(r.legacy_company_number), r]));

      const oppInput = batch.map(f => {
        const no = str(f.no);
        const c = contacts[no] || {};
        const stage = stageFor(c);
        return {
          site_id: siteByNo.get(no)?.id,
          organisation_id: orgByNo.get(no)?.id || null,
          legacy_company_number: no,
          name: `${str(f.name)} solar opportunity`,
          stage,
          owner_name: 'sam',
          probability: probabilityFor(stage),
          sales_score: salesScore(c),
          site_score: null,
          commercial_score: null,
          priority_score: null,
          next_action: stage === 'contact_ready' ? 'Make first contact' : 'Enrich contact details',
          updated_at: new Date().toISOString(),
        };
      }).filter(x => x.site_id);
      const oppRows = await rest(supabaseUrl, serviceKey, 'lb_opportunities', oppInput, 'legacy_company_number');
      totals.opportunities += oppRows.length;
      const oppByNo = new Map(oppRows.map((r: AnyRow) => [str(r.legacy_company_number), r]));

      const qualificationInput = batch.map(f => {
        const no = str(f.no);
        const c = contacts[no] || {};
        const directors = Array.isArray(c.directors) ? c.directors.map((d: any) => d?.name).filter(Boolean) : [];
        const named = directors.length ? directors : (str(c.director) ? [str(c.director)] : []);
        const opp = oppByNo.get(no);
        if (!opp?.id) return null;
        return {
          opportunity_id: opp.id,
          decision_makers: named.join(', ') || null,
          updated_at: new Date().toISOString(),
        };
      }).filter(Boolean) as AnyRow[];
      const qualRows = await rest(supabaseUrl, serviceKey, 'lb_qualifications', qualificationInput, 'opportunity_id');
      totals.qualifications += qualRows.length;

      const cpInput: AnyRow[] = [];
      for (const f of batch) {
        const no = str(f.no);
        const org = orgByNo.get(no);
        const c = contacts[no] || {};
        if (!org?.id) continue;
        const conf = confidenceNumber(c.confidence);
        if (str(c.phone)) cpInput.push({
          organisation_id: org.id,
          type: /^07/.test(str(c.phone).replace(/\s/g, '')) ? 'mobile' : 'phone',
          value: str(c.phone),
          label: 'Seed contact',
          is_primary: true,
          verification_status: str(c.confidence).toLowerCase() === 'high' ? 'probable' : 'unknown',
          discovery_method: 'legacy_contact_dataset',
          provider: str(c.source) || 'LandBank seed data',
          confidence: conf,
          found_at: new Date().toISOString(),
        });
        if (str(c.email)) cpInput.push({
          organisation_id: org.id,
          type: 'email',
          value: str(c.email).toLowerCase(),
          label: 'Seed email',
          is_primary: true,
          verification_status: /unverified|inferred|guess/i.test(str(c.email_status)) ? 'unknown' : 'probable',
          discovery_method: /unverified|inferred|guess/i.test(str(c.email_status)) ? 'inferred_legacy_email' : 'legacy_contact_dataset',
          provider: str(c.source) || 'LandBank seed data',
          confidence: /unverified|inferred|guess/i.test(str(c.email_status)) ? Math.min(conf, 40) : conf,
          found_at: new Date().toISOString(),
        });
        if (str(c.website)) cpInput.push({
          organisation_id: org.id,
          type: 'website',
          value: str(c.website),
          label: 'Website',
          is_primary: true,
          verification_status: str(c.confidence).toLowerCase() === 'check' ? 'unknown' : 'probable',
          discovery_method: 'legacy_contact_dataset',
          provider: str(c.source) || 'LandBank seed data',
          confidence: conf,
          found_at: new Date().toISOString(),
        });
      }
      if (cpInput.length) {
        const cpRows = await rest(supabaseUrl, serviceKey, 'lb_contact_points', cpInput, 'organisation_id,type,value');
        totals.contact_points += cpRows.length;
      }
    }

    return json({ ok: true, source: { farms: FARMS_URL, contacts: CONTACTS_URL }, totals });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
