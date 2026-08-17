// LandBank V2 bulk Planning Data importer.
// Downloads GeoJSON pages into PostGIS and refreshes site intersections when a dataset completes.

const cors={
  'Access-Control-Allow-Origin':'*',
  'Access-Control-Allow-Headers':'content-type, x-landbank-batch-key',
};
const BATCH_KEY='4472';
const PRIORITY=['green-belt','agricultural-land-classification','site-of-special-scientific-interest','ancient-woodland','scheduled-monument'];
const CONFIG:Record<string,{penalty:number,kind:'planning'|'agriculture'}>={
  'green-belt':{penalty:10,kind:'planning'},
  'site-of-special-scientific-interest':{penalty:30,kind:'planning'},
  'ancient-woodland':{penalty:25,kind:'planning'},
  'scheduled-monument':{penalty:25,kind:'planning'},
  'agricultural-land-classification':{penalty:0,kind:'agriculture'},
};
type Row=Record<string,any>;
function json(data:unknown,status=200){return new Response(JSON.stringify(data,null,2),{status,headers:{...cors,'Content-Type':'application/json'}})}
async function rest(base:string,service:string,path:string,opt:{method?:string,body?:unknown,prefer?:string}={}){const headers:Record<string,string>={apikey:service,Authorization:`Bearer ${service}`,'Content-Type':'application/json'};if(opt.prefer)headers.Prefer=opt.prefer;const r=await fetch(`${base}/rest/v1/${path}`,{method:opt.method||'GET',headers,body:opt.body==null?undefined:JSON.stringify(opt.body)});const text=await r.text();if(!r.ok)throw new Error(`Supabase ${r.status}: ${text.slice(0,800)}`);return text?JSON.parse(text):null}
async function rpc(base:string,service:string,name:string,body:Row){return rest(base,service,`rpc/${name}`,{method:'POST',body,prefer:'return=representation'})}
function chunks(features:any[],maxBytes=900000){const out:any[][]=[];let cur:any[]=[];let bytes=2;for(const f of features){const n=JSON.stringify(f).length+1;if(cur.length&&bytes+n>maxBytes){out.push(cur);cur=[];bytes=2}cur.push(f);bytes+=n}if(cur.length)out.push(cur);return out}
Deno.serve(async req=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
  if(req.method!=='POST')return json({error:'POST required'},405);
  if(req.headers.get('x-landbank-batch-key')!==BATCH_KEY)return json({error:'unauthorised'},401);
  try{
    const base=Deno.env.get('SUPABASE_URL'),service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if(!base||!service)throw new Error('Supabase service environment unavailable');
    const input=await req.json().catch(()=>({}));
    let dataset=String(input?.dataset||'');
    const imports:Row[]=await rest(base,service,'lb_constraint_imports?select=*&status=neq.completed')||[];
    if(dataset){if(!CONFIG[dataset])return json({error:'unsupported dataset'},400)}else{dataset=PRIORITY.find(d=>imports.some(x=>x.dataset===d))||''}
    if(!dataset)return json({status:'complete',message:'all configured datasets imported'});
    const state=imports.find(x=>x.dataset===dataset)||((await rest(base,service,`lb_constraint_imports?dataset=eq.${encodeURIComponent(dataset)}&select=*`))||[])[0];
    if(!state)return json({error:`import state missing for ${dataset}`},500);
    const offset=Number(state.next_offset||0),pageSize=Math.max(1,Math.min(100,Number(state.page_size||50)));
    await rest(base,service,`lb_constraint_imports?dataset=eq.${encodeURIComponent(dataset)}`,{method:'PATCH',body:{status:'importing',attempts:Number(state.attempts||0)+1,last_error:null,started_at:state.started_at||new Date().toISOString(),updated_at:new Date().toISOString()},prefer:'return=minimal'});
    const q=new URLSearchParams({dataset,limit:String(pageSize),offset:String(offset)});
    for(const f of ['entity','name','dataset','reference'])q.append('field',f);
    const sourceUrl=`https://www.planning.data.gov.uk/entity.geojson?${q}`;
    const r=await fetch(sourceUrl,{headers:{'User-Agent':'LandBank-V2/1.0'}});
    const text=await r.text();
    if(!r.ok)throw new Error(`Planning Data ${r.status}: ${text.slice(0,700)}`);
    const fc=JSON.parse(text),features=Array.isArray(fc?.features)?fc.features:[];
    const nextOffset=offset+features.length,complete=features.length<pageSize;
    const packs=chunks(features);
    if(!packs.length){await rpc(base,service,'lb_ingest_constraint_batch',{p_dataset:dataset,p_features:[],p_next_offset:nextOffset,p_complete:true,p_source_url:sourceUrl})}
    else{for(let i=0;i<packs.length;i++){await rpc(base,service,'lb_ingest_constraint_batch',{p_dataset:dataset,p_features:packs[i],p_next_offset:nextOffset,p_complete:complete&&i===packs.length-1,p_source_url:sourceUrl})}}
    let intersections:null|number=null,classified:null|number=null;
    if(complete){if(CONFIG[dataset].kind==='planning'){intersections=await rpc(base,service,'lb_refresh_constraint_intersections',{p_dataset:dataset,p_penalty:CONFIG[dataset].penalty})}else{classified=await rpc(base,service,'lb_apply_agricultural_classification',{})}}
    return json({status:complete?'completed_dataset':'page_imported',dataset,offset,page_size:pageSize,features:features.length,next_offset:nextOffset,complete,intersection_result:intersections,classification_result:classified,source_url:sourceUrl});
  }catch(e){const msg=e instanceof Error?e.message:String(e);try{const base=Deno.env.get('SUPABASE_URL'),service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');const input=await req.clone().json().catch(()=>({}));const d=String(input?.dataset||'');if(base&&service&&d&&CONFIG[d])await rest(base,service,`lb_constraint_imports?dataset=eq.${encodeURIComponent(d)}`,{method:'PATCH',body:{status:'failed',last_error:msg,updated_at:new Date().toISOString()},prefer:'return=minimal'})}catch{}return json({error:msg},500)}
});
