import { unzipSync, strFromU8 } from 'https://esm.sh/fflate@0.8.2';

const WORKBOOK_URL = 'https://www.enwl.co.uk/globalassets/get-connected/network-information/network-development-plan/archive/enwl-network-headroom-report-april-2025.xlsx';
const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': '*' } });

function strip(s: string) {
  return s.replace(/<[^>]+>/g, '').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&#39;/g, "'").replace(/&quot;/g, '"');
}
function colValue(row: string, ref: string, shared: string[]) {
  const m = row.match(new RegExp(`<c[^>]*r="${ref}\\d+"([^>]*)>([\\s\\S]*?)<\\/c>`));
  if (!m) return null;
  const v = (m[2].match(/<v>([\s\S]*?)<\/v>/) || [])[1];
  if (v == null) return null;
  return /t="s"/.test(m[1]) ? (shared[Number(v)] ?? v) : v;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*' } });
  try {
    const r = await fetch(WORKBOOK_URL, { headers: { 'User-Agent': 'LandBank-V2/1.0' } });
    if (!r.ok) throw new Error(`ENWL workbook HTTP ${r.status}`);
    const bytes = new Uint8Array(await r.arrayBuffer());
    const zip = unzipSync(bytes);
    const sharedXml = strFromU8(zip['xl/sharedStrings.xml']);
    const shared = [...sharedXml.matchAll(/<si>([\s\S]*?)<\/si>/g)].map(m => strip(m[1]));
    const sheet = strFromU8(zip['xl/worksheets/sheet9.xml']);
    const rows: unknown[] = [];
    for (const rm of sheet.matchAll(/<row[^>]*r="(\d+)"[^>]*>([\s\S]*?)<\/row>/g)) {
      const rowNo = Number(rm[1]);
      if (rowNo < 12) continue;
      const body = rm[0];
      const primary = colValue(body, 'B', shared);
      const easting = Number(colValue(body, 'E', shared));
      const northing = Number(colValue(body, 'F', shared));
      if (!primary || !Number.isFinite(easting) || !Number.isFinite(northing)) continue;
      const inv = Number(colValue(body, 'O', shared));
      const slv = Number(colValue(body, 'P', shared));
      const shv = Number(colValue(body, 'Q', shared));
      const battery = Number(colValue(body, 'R', shared));
      rows.push({
        row: rowNo,
        primary_substation: primary,
        bsp_group: colValue(body, 'C', shared),
        gsp_group: colValue(body, 'D', shared),
        easting,
        northing,
        generation_headroom_inverter_mw: Number.isFinite(inv) ? inv : null,
        synchronous_lv_mw: Number.isFinite(slv) ? slv : null,
        synchronous_hv_mw: Number.isFinite(shv) ? shv : null,
        battery_headroom_mw: Number.isFinite(battery) ? battery : null,
        comments: colValue(body, 'ND', shared),
      });
    }
    return json({
      source: 'SP Electricity North West Network Headroom Report April 2025',
      source_url: WORKBOOK_URL,
      report_period: 'April 2025',
      scenario: 'Best View',
      forecast_year: 2026,
      technology: 'Inverter Based',
      metric: 'Generation Headroom - N-0 -(MW)',
      record_count: rows.length,
      rows,
    });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});