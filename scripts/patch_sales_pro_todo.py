from pathlib import Path

p=Path('sales-pro.html')
s=p.read_text()

def rep(old,new,label):
    global s
    n=s.count(old)
    if n!=1:
        raise SystemExit(f'{label}: expected 1 match, found {n}')
    s=s.replace(old,new,1)

rep(
    '<nav class="tabs"><button class="on" data-v="today">Today</button>',
    '<nav class="tabs"><button class="on" data-v="todo">To-Do<span id="todoBadge"></span></button><button data-v="today">Today</button>',
    'nav'
)

css='''.todoSummary{display:grid;grid-template-columns:repeat(3,1fr);gap:9px;margin-top:14px}.todoBucket{margin-top:17px}.todoBucketHead{display:flex;align-items:center;justify-content:space-between;margin-bottom:7px}.todoBucketHead h2{margin:0;font-size:16px}.todoBucketHead span{display:inline-flex;min-width:28px;height:28px;align-items:center;justify-content:center;border-radius:99px;background:#dde8e0;font-weight:900}.todoItem{display:grid;grid-template-columns:170px minmax(280px,1fr) 260px 190px;gap:12px;align-items:center;background:white;border:1px solid var(--line);border-radius:11px;padding:12px;margin-bottom:7px;box-shadow:var(--shadow)}.todoItem.overdue{border-left:5px solid var(--red)}.todoItem.today{border-left:5px solid var(--green2)}.todoItem.upcoming{border-left:5px solid var(--blue)}.todoWhen b,.todoWhen small,.todoMain b,.todoMain small,.todoMain strong,.todoContact small,.todoContact b{display:block}.todoWhen small,.todoMain small,.todoContact small,.muted{color:var(--muted);font-size:10px}.todoMain strong{margin-top:5px}.todoMain p{margin:4px 0 0;color:#405449;font-size:11px}.todoState{display:inline-block;border-radius:99px;padding:3px 7px;margin-bottom:5px;font-size:9px;font-weight:900;letter-spacing:.04em}.todoItem.overdue .todoState{background:var(--redp);color:var(--red)}.todoItem.today .todoState{background:var(--pale);color:var(--green)}.todoItem.upcoming .todoState{background:var(--bluep);color:var(--blue)}.todoCall{display:inline-block;margin-top:5px;color:var(--green);font-weight:850;text-decoration:none}.todoActions{display:flex;gap:6px;justify-content:flex-end}.todoActions button{padding:8px 10px;border-radius:8px;white-space:nowrap}.todoEmpty{margin-top:17px;background:white;border:1px solid var(--line);border-radius:var(--r);padding:28px;text-align:center;box-shadow:var(--shadow)}.todoEmpty h2{margin:0 0 5px}.todoEmpty p{color:var(--muted);margin:0 0 14px}'''
rep('@media(max-width:900px){',css+'@media(max-width:900px){.todoSummary{grid-template-columns:1fr 1fr 1fr}.todoItem{grid-template-columns:1fr}.todoActions{justify-content:flex-start}', 'css')

section='''<section class="view on" id="v-todo"><div class="section"><div class="sectionhead"><div><h2>To-Do list</h2><p>Callbacks and scheduled next actions. Overdue items stay until completed or rescheduled.</p></div></div><div class="todoSummary"><div class="metric"><small>Overdue</small><b id="tdOverdue">0</b></div><div class="metric"><small>Due today</small><b id="tdToday">0</b></div><div class="metric"><small>Upcoming</small><b id="tdUpcoming">0</b></div></div><div id="todoBuckets"></div></div></section>\n'''
rep('<section class="view on" id="v-today">',section+'<section class="view" id="v-today">','todo section')
rep('}function bval(id){','}window.lbOpenRec=openRec;function bval(id){','open record export')
rep("$('msg').textContent='Saved ✓';await load();", "$('msg').textContent='Saved ✓';window.dispatchEvent(new Event('lb:todo-refresh'));await load();", 'save refresh')
rep("$('msg').textContent='Logged ✓'}async function handover", "$('msg').textContent='Logged ✓';window.dispatchEvent(new Event('lb:todo-refresh'))}async function handover", 'log refresh')
rep('</script></body></html>','</script><script src="sales-pro-todo.js"></script></body></html>','todo script')

p.write_text(s)
print('Sales Pro To-Do patch applied')
