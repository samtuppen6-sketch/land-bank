/* LandBank: user-initiated, read-only handover pack preview. Never sends or submits. */
(()=>{
'use strict';
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const val=x=>x===null||x===undefined||x===''?'To be confirmed':String(x);
const yn=x=>x===true?'Yes':x===false?'No':'To be confirmed';
const num=x=>x==null?'To be confirmed':Number(x).toLocaleString('en-GB',{maximumFractionDigits:2});
const money=x=>x==null?'Not modelled':new Intl.NumberFormat('en-GB',{style:'currency',currency:'GBP',maximumFractionDigits:0}).format(Number(x));
const block=(title,pairs)=>'<section class="lbp-section"><h2>'+esc(title)+'</h2><dl class="lbp-fields">'+pairs.map(p=>'<div class="lbp-field"><dt>'+esc(p[0])+'</dt><dd>'+esc(val(p[1]))+'</dd></div>').join('')+'</dl></section>';
const css=[
'#lb-pack-preview{position:fixed;inset:0;overflow:auto;z-index:200;background:#edf2ee;color:#102019;font:14px/1.45 Arial,sans-serif}',
'#lb-pack-preview *{box-sizing:border-box}',
'#lb-pack-preview .lbp-toolbar{position:sticky;top:0;z-index:1;padding:12px;display:flex;flex-wrap:wrap;gap:8px;background:#102019;color:white;align-items:center}',
'#lb-pack-preview .lbp-toolbar span{flex:1;min-width:180px;font-size:12px}',
'#lb-pack-preview .lbp-toolbar button{border:0;border-radius:8px;padding:10px 12px;font-weight:bold;background:#2d8b5f;color:#fff}',
'#lb-pack-preview .lbp-toolbar #lbp-close{background:white;color:#102019}',
'#lb-pack-preview .lbp-paper{max-width:850px;margin:20px auto;background:#fff;padding:36px;box-shadow:0 7px 22px #10201914}',
'#lb-pack-preview .lbp-head{border-bottom:3px solid #2d8b5f;padding-bottom:18px}',
'#lb-pack-preview .lbp-logo{font-size:21px;letter-spacing:2px;font-weight:bold;color:#1e714b}',
'#lb-pack-preview .lbp-sub{font-size:11px;font-weight:bold;letter-spacing:1px;margin:12px 0}',
'#lb-pack-preview h1{font-size:23px;line-height:1.2;margin:6px 0}',
'#lb-pack-preview .lbp-section{padding:16px 0;border-bottom:1px solid #d7e0da;break-inside:avoid-page}',
'#lb-pack-preview h2{font-size:16px;margin:0 0 12px}',
'#lb-pack-preview .lbp-fields{display:grid;grid-template-columns:1fr 1fr;gap:12px 17px;margin:0}',
'#lb-pack-preview .lbp-field{min-width:0;overflow-wrap:anywhere}',
'#lb-pack-preview dt{font-size:11px;color:#66786e;font-weight:bold}',
'#lb-pack-preview dd{margin:2px 0;white-space:pre-wrap}',
'#lb-pack-preview .lbp-notes{white-space:pre-wrap;overflow-wrap:anywhere}',
'#lb-pack-preview .lbp-foot{font-size:11px;color:#66786e;margin-top:18px}',
'@media(max-width:650px){#lb-pack-preview .lbp-paper{margin:0;padding:20px}#lb-pack-preview .lbp-toolbar button{flex:1}}',
'@media print{@page{size:A4;margin:13mm}body.lb-pack-print>*:not(#lb-pack-preview){display:none!important}body.lb-pack-print #lb-pack-preview{position:static!important;overflow:visible!important;inset:auto!important;background:#fff!important}#lb-pack-preview .lbp-toolbar{display:none!important}#lb-pack-preview .lbp-paper{max-width:none!important;margin:0!important;padding:0!important;box-shadow:none!important}}'
].join('\n');
const date=()=>new Date().toLocaleString('en-GB',{dateStyle:'long',timeStyle:'short'});
function make(r,q){
const contact=q?.preferred_contact_name||r.decision_makers;
const phone=q?.preferred_contact_mobile||r.phone;
const addr=[r.address_line,r.town,r.county,r.postcode].filter(Boolean).join(', ');
const access=q?.access_notes||r.access_notes;
const sections=[
 block('Organisation and contact',[
 ['Site / farm',r.site_name],['Organisation',r.organisation_name],
 ['Company number',r.company_number],['Location',addr],
 ['Preferred contact',contact],['Other recorded decision makers',r.decision_makers],
 ['Telephone',phone],['Email',r.email],['Preferred contact time',r.preferred_contact_time]
 ]),
 block('Landowner qualification',[
 ['Interested in solar',yn(r.interested_in_solar_income)],['Authorised decision-maker',yn(r.authorised_decision_maker)],
 ['Consent to share details',yn(r.consent_to_share)],
 ['Acres available',r.acres_available==null?'To be confirmed':num(r.acres_available)],
 ['Usable acres',r.usable_acres==null?'To be confirmed':num(r.usable_acres)],
 ['Contiguous',yn(r.contiguous)],['Current land use',r.current_land_use],
 ['Occupier / tenant',r.occupier_or_tenant],['Large vehicle access',yn(r.large_vehicle_access)],
 ['Mortgage or charge',yn(r.mortgage_or_charge)],['Site visit interest',yn(r.site_visit_interest)],
 ['Repayment preference (%)',r.repayment_preference_pct==null?'To be confirmed':num(r.repayment_preference_pct)],
 ['Access / plots discussed',access]
 ]),
 '<section class="lbp-section"><h2>Saved handover and call notes</h2><div class="lbp-notes">'+esc(val(r.handover_notes))+'</div></section>',
 block('Desktop site screening — indicative',[
 ['Site potential',num(r.site_potential_score)],
 ['Evidence confidence',r.site_potential_confidence==null?'To be confirmed':num(r.site_potential_confidence)+'%'],
 ['Grid evidence class',r.grid_evidence_class],
 ['Grid node',r.grid_node_name],
 ['Indicative distance to node',r.grid_distance_km==null?'To be confirmed':num(r.grid_distance_km)+' km'],
 ['Generation headroom',r.generation_headroom_mw==null?'Not established':num(r.generation_headroom_mw)+' MW'],
 ['Solar screening score',num(r.solar_score)],['Flood screen',r.flood_zone],
 ['Planning screen score',num(r.planning_screen_score)],['Agricultural grade',r.agricultural_grade],
 ['Median slope',r.topography_median_slope_deg==null?'To be confirmed':num(r.topography_median_slope_deg)+'°']
 ]),
 block('Indicative export scenario (if modelled)',[
 ['Base capacity',r.capacity_mwp_base==null?'Not modelled — acreage unconfirmed':num(r.capacity_mwp_base)+' MWp'],
 ['Base annual generation',r.annual_generation_mwh_base==null?'Not modelled':num(r.annual_generation_mwh_base)+' MWh'],
 ['Base gross export illustration',money(r.annual_gross_value_base)]
 ])
].join('');
const title=val(r.site_name||r.organisation_name);
const markup='<div class="lbp-paper"><header class="lbp-head"><div class="lbp-logo">LANDBANK</div><p class="lbp-sub">LANDOWNER OPPORTUNITY HANDOVER PACK</p><h1>'+esc(title)+'</h1><small>Prepared from saved Sales Pro records · '+esc(date())+'</small></header>'+sections+'<footer class="lbp-foot">Confidential. Site screening and commercial figures are indicative only, not a grid offer, planning approval or guaranteed return. Confirm acreage, title, site boundaries and grid availability independently. Generated only at the user’s request.</footer></div>';
const copy='LANDBANK — LANDOWNER OPPORTUNITY HANDOVER PACK\n'+title+'\n'+date()+'\n\nContact: '+val(contact)+'\nPhone: '+val(phone)+'\nEmail: '+val(r.email)+'\nOrganisation: '+val(r.organisation_name)+'\nSite: '+val(addr)+'\n\nInterested in solar: '+yn(r.interested_in_solar_income)+'\nAuthorised decision maker: '+yn(r.authorised_decision_maker)+'\nPermission to share: '+yn(r.consent_to_share)+'\nLand available (acres): '+val(r.acres_available)+'\nUsable acres: '+val(r.usable_acres)+'\nAccess / plots: '+val(access)+'\n\nSaved handover notes:\n'+val(r.handover_notes)+'\n\nDesktop screening: site score '+val(r.site_potential_score)+', grid node '+val(r.grid_node_name)+', grid distance '+val(r.grid_distance_km)+' km; grid capacity not confirmed. Indicative base annual gross export: '+money(r.annual_gross_value_base)+'\n';
return {markup,copy};
}
async function generate(id){
 if(!id||typeof window.lbApi!=='function'){alert('Open a saved opportunity first.');return;}
 let packRow,qualRow;
 try{
 const [p,q]=await Promise.all([
 window.lbApi('lb_handover_pack?select=*&opportunity_id=eq.'+encodeURIComponent(id)+'&limit=1'),
 window.lbApi('lb_qualifications?select=preferred_contact_name,preferred_contact_mobile,access_notes&opportunity_id=eq.'+encodeURIComponent(id)+'&limit=1')
 ]);
 packRow=p?.[0];qualRow=q?.[0];
 if(!packRow)throw new Error('No saved handover data was returned');
 }catch(e){alert('Unable to load saved handover pack: '+(e?.message||e));return;}
 const pack=make(packRow,qualRow);
 document.getElementById('lb-pack-preview')?.remove();
 document.getElementById('lb-pack-style')?.remove();
 const style=document.createElement('style');style.id='lb-pack-style';style.textContent=css;document.head.appendChild(style);
 const preview=document.createElement('div');preview.id='lb-pack-preview';
 preview.setAttribute('role','dialog');preview.setAttribute('aria-modal','true');
 preview.innerHTML='<div class="lbp-toolbar"><span>Preview only — nothing sent or marked handed over.</span><button type="button" id="lbp-copy">Copy</button><button type="button" id="lbp-print">Print / Save PDF</button><button type="button" id="lbp-close">Close</button></div>'+pack.markup;
 document.body.appendChild(preview);
 document.getElementById('lbp-close').onclick=()=>{preview.remove();style.remove();document.body.classList.remove('lb-pack-print');};
 document.getElementById('lbp-print').onclick=()=>{document.body.classList.add('lb-pack-print');window.print();};
 document.getElementById('lbp-copy').onclick=async()=>{
 const button=document.getElementById('lbp-copy');
 try{await navigator.clipboard.writeText(pack.copy);button.textContent='Copied ✓';}
 catch{const t=document.createElement('textarea');t.value=pack.copy;preview.appendChild(t);t.select();const ok=document.execCommand('copy');t.remove();button.textContent=ok?'Copied ✓':'Copy unavailable';}
 };
}
window.lbGenerateHandoverPack=generate;
})();
