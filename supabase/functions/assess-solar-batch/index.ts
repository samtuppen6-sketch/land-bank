// LandBank V2 national PVGIS portfolio worker.
// Processes the explicit solar_screen queue only; planning/grid/ownership remain separate evidence layers.

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type, x-landbank-batch-key',
};
const BATCH_KEY = '4472'; // temporary internal gate while the current single-user PIN architecture remains
const MAX_BATCH = 15;

type Row = Record<string, any>;

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

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

async function patchQueue(base:string, service:string, id:string, body:Row) {
  return rest(base, service, `lb_assessment_queue?id=eq.${encodeURIComponent(id)}`, {
    method:'PATCH', body:{...body,updated_at:new Date().toISOString()}, prefer:'return=minimal'
  });
}

Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response('ok', {headers:cors});
  if (req.method !== 'POST') return json({error:'POST required'},405);
  if (req.headers.get('x-landbank-batch-key') !== BATCH_KEY) return json({error:'unauthorised'},401);

  try {
    const base = Deno.env.get('SUPABASE_URL');
    const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!base || !service) throw new Error('Supabase service environment unavailable');
    const input = await req.json().catch(() => ({}));
    const batchSize = Math.max(1, Math.min(MAX_BATCH, Number(input?.batch_size || 10)));

    const staleBefore = new Date(Date.now() - 15 * 60 * 1000).toISOString();
    await rest(base, service,
      `lb_assessment_queue?job_type=eq.solar_screen&status=eq.processing&locked_at=lt.${encodeURIComponent(staleBefore)}`,
      {method:'PATCH',body:{status:'queued',locked_at:null,last_error:'Recovered stale processing lock',updated_at:new Date().toISOString()},prefer:'return=minimal'}
    );

    const now = new Date().toISOString();
    const queue: Row[] = await rest(base, service,
      `lb_assessment_queue?job_type=eq.solar_screen&status=in.(queued,failed)&attempts=lt.5&next_attempt_at=lte.${encodeURIComponent(now)}&select=id,site_id,attempts&order=attempts.asc,next_attempt_at.asc&limit=${batchSize}`
    ) || [];

    const outcome: Row = {requested:batchSize,claimed:queue.length,completed:0,requeued:0,failed:0,items:[]};

    for (const item of queue) {
      const attempt = Number(item.attempts || 0) + 1;
      await patchQueue(base,service,item.id,{status:'processing',attempts:attempt,locked_at:new Date().toISOString(),last_error:null});
      try {
        const r = await fetch(`${base}/functions/v1/assess-site`, {
          method:'POST',
          headers:{'Content-Type':'application/json','x-landbank-assess-key':'4472'},
          body:JSON.stringify({site_id:item.site_id,providers:['pvgis']})
        });
        const text = await r.text();
        let payload: any = {};
        try { payload = text ? JSON.parse(text) : {}; } catch { payload = {raw:text.slice(0,1000)}; }
        if (!r.ok || payload?.error || payload?.pvgis?.error) {
          throw new Error(payload?.error || payload?.pvgis?.error || `assess-site ${r.status}: ${text.slice(0,500)}`);
        }

        await patchQueue(base,service,item.id,{
          status:'completed',locked_at:null,completed_at:new Date().toISOString(),last_error:null,
          last_result:{provider:'PVGIS 5.3',solar_score:payload?.pvgis?.score,site_score:payload?.site_score,annual_kwh_per_kwp:payload?.pvgis?.annual_kwh_per_kwp}
        });
        outcome.completed++;
        outcome.items.push({site_id:item.site_id,status:'completed',solar_score:payload?.pvgis?.score,site_score:payload?.site_score});
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        const finalFailure = attempt >= 5;
        const retryMinutes = Math.min(120, Math.pow(2, Math.max(0,attempt-1)) * 5);
        await patchQueue(base,service,item.id,{
          status:finalFailure?'failed':'queued',locked_at:null,last_error:msg,
          next_attempt_at:new Date(Date.now()+retryMinutes*60*1000).toISOString()
        });
        if (finalFailure) outcome.failed++; else outcome.requeued++;
        outcome.items.push({site_id:item.site_id,status:finalFailure?'failed':'requeued',attempt,error:msg.slice(0,300)});
      }
    }

    const progress = await rest(base, service, 'lb_assessment_progress?job_type=eq.solar_screen&select=*');
    outcome.progress = progress?.[0] || null;
    return json(outcome);
  } catch (e) {
    return json({error:e instanceof Error?e.message:String(e)},500);
  }
});
