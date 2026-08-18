import * as XLSX from 'npm:xlsx@0.18.5';

const WORKBOOK_URL = 'https://spenergynetworks.opendatasoft.com/api/explore/v2.1/catalog/datasets/spm-nshr-data-workbook/alternative_exports/spen_2024_ndp_spm_nshr_xlsx';

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data, null, 2), {status,headers:{'Content-Type':'application/json','Cache-Control':'no-store','Access-Control-Allow-Origin':'*'}});
}
function boolish(v: unknown) { if(v===true||v===1)return true; return ['true','yes','y','1'].includes(String(v??'').trim().toLowerCase()); }

Deno.serve(async (req: Request) => {
  if(req.method==='OPTIONS')return new Response('ok',{headers:{'Access-Control-Allow-Origin':'*'}});
  if(req.method!=='POST'&&req.method!=='GET')return json({error:'GET or POST required'},405);
  try{
    const r=await fetch(WORKBOOK_URL,{headers:{'User-Agent':'LandBank-V2/1.0'}});
    if(!r.ok)throw new Error(`SPEN workbook HTTP ${r.status}`);
    const wb=XLSX.read(await r.arrayBuffer(),{type:'array',cellDates:false});
    const sheet=wb.Sheets['Baseline Scenario (Gen)'];
    if(!sheet)throw new Error('Baseline Scenario (Gen) sheet missing');
    const rows=XLSX.utils.sheet_to_json(sheet,{header:1,raw:true,defval:null}) as unknown[][];
    const records:Record<string,unknown>[]=[];
    for(const row of rows.slice(3)){
      const group=String(row[1]??'').trim(); if(!group)continue;
      records.push({
        headroom_group:group,
        voltage_kv:row[2]==null||row[2]===''?null:Number(row[2]),
        grid_gsp_group:row[3]??null,
        subject_to_upstream_constraints:boolish(row[4]),
        headroom_release_date:row[5]??null,
        fully_converted_headroom_mw_2026_27:row[25]==null||row[25]===''?null:Number(row[25]),
        scenario:'Baseline',generation_type:'Fully Converted',year:'2026/27',source_sheet:'Baseline Scenario (Gen)'
      });
    }
    return json({source:'SP Energy Networks SPM Network Scenario Headroom Report',workbook_url:WORKBOOK_URL,workbook_modified:'2026-06-15',scenario:'Baseline',generation_type:'Fully Converted',year:'2026/27',count:records.length,records});
  }catch(e){return json({error:e instanceof Error?e.message:String(e)},500)}
});
