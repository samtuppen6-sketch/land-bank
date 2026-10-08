/* LandBank Sales Pro — persistent, visible contact activity history.
   Read-only; never modifies customer tasks or contacts. */
(()=>{
'use strict';
const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const date=v=>{if(!v)return '';const d=new Date(v);return Number.isNaN(+d)?String(v):d.toLocaleString('en-GB',{weekday:'short',day:'numeric',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'})};
const label=t=>({'call':'Call logged','callback':'Callback scheduled','note':'Activity note','phone_followup':'Phone follow-up','email_followup':'Email follow-up','email_sent':'Email sent','qualification_review':'Qualification review'})[t]||String(t||'Activity').replaceAll('_',' ').replace(/\b\w/g,c=>c.toUpperCase());
const styles=[
'#lb-activity-history{margin-top:10px}',
'#lb-activity-history h3{display:flex;justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap}',
'#lb-activity-history .lb-history-refresh{border:1px solid #d7e0da;background:#fff;border-radius:7px;padding:6px 9px;font-size:12px;cursor:pointer}',
'#lb-activity-history .lb-history-note{background:#f6faf7;border:1px solid #e1eae3;border-radius:9px;padding:10px 12px;margin-top:9px}',
'#lb-activity-history .lb-history-note header{display:flex;justify-content:space-between;gap:10px;flex-wrap:wrap;align-items:center}',
'#lb-activity-history .lb-history-note header strong{font-size:13px}',
'#lb-activity-history .lb-history-note header time{font-size:11px;color:#66786e}',
'#lb-activity-history .lb-history-note p{margin:7px 0 0;white-space:pre-wrap;overflow-wrap:anywhere;font-size:13px}',
'#lb-activity-history .lb-history-extra{margin-top:6px;font-size:11px;color:#5c6c62}',
'#lb-activity-history .lb-history-muted{font-size:12px;color:#66786e}',
'#lb-activity-history .lb-history-open{color:#926100;font-weight:700}',
'#lb-activity-history .lb-history-done{color:#1e714b}',
'#lb-activity-history .lb-history-error{color:#a44234}'
].join('\n');
const style=document.createElement('style');style.id='lb-activity-styles';style.textContent=styles;document.head.appendChild(style);
async function load(id){
 const root=document.getElementById('lb-activity-history');
 if(!root||typeof window.lbApi!=='function')return;
 root.dataset.opp=id;
 root.innerHTML='<h3>Call notes & activity history <button type="button" class="lb-history-refresh">Refresh</button></h3><p class="lb-history-muted">Loading saved notes…</p>';
 const refresh=root.querySelector('.lb-history-refresh');
 refresh.onclick=()=>load(id);
 try{
  const rows=await window.lbApi('lb_tasks?select=id,type,title,notes,due_at,created_at,completed_at&opportunity_id=eq.'+encodeURIComponent(id)+'&order=created_at.desc&limit=100')||[];
  if(root.dataset.opp!==id)return;
  const withNotes=rows.filter(r=>r.notes&&String(r.notes).trim());
  let html='<h3>Call notes & activity history <button type="button" class="lb-history-refresh">Refresh</button></h3>';
  html+=withNotes.length?'<p class="lb-history-muted">Saved against this contact, newest first. Notes remain visible after follow-ups are completed.</p>':'<p class="lb-history-muted">No saved call notes for this contact yet. Add one below and it will appear here.</p>';
  html+=withNotes.map(r=>{
   const isDue=!!r.due_at&&!r.completed_at;
   return '<article class="lb-history-note"><header><strong>'+esc(label(r.type))+'</strong><time>'+esc(date(r.created_at))+'</time></header><p>'+esc(r.notes)+'</p>'+
    (isDue?'<div class="lb-history-extra lb-history-open">Action due: '+esc(date(r.due_at))+'</div>':
    r.completed_at?'<div class="lb-history-extra lb-history-done">Recorded / completed</div>':'')+'</article>';
  }).join('');
  if(rows.length===100)html+='<p class="lb-history-muted">Showing 100 latest activity records. Older notes remain stored in Sales Pro.</p>';
  root.innerHTML=html;
  root.querySelector('.lb-history-refresh').onclick=()=>load(id);
 }catch(e){if(root.dataset.opp!==id)return;root.innerHTML='<h3>Call notes & activity history <button type="button" class="lb-history-refresh">Retry</button></h3><p class="lb-history-error">Could not load saved notes: '+esc(e?.message||e)+'</p>';root.querySelector('.lb-history-refresh').onclick=()=>load(id)}
}
window.lbLoadActivityHistory=load;
})();