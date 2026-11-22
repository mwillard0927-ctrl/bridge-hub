// Project Boards — shared module for Phone Bridge + Bridge Hub
// mountBoard({sb, user, displayName, root, onUnread, toast}) → {projects(), postTo(projectId, {title, body, files}), refresh()}
const TAGS = ['Note', 'Idea', 'Question', 'Decision', 'Urgent'];
const TAGC = {Note: '#64748b', Idea: '#0e7490', Question: '#7c3aed', Decision: '#0f7a4a', Urgent: '#b91c1c'};
const MAXF = 10 * 1048576;
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;'}[c]));
const ago = t => { const s = (Date.now() - new Date(t)) / 1000; if (s < 60) return 'just now'; if (s < 3600) return Math.floor(s / 60) + ' min ago'; if (s < 86400) return Math.floor(s / 3600) + ' h ago'; return new Date(t).toLocaleDateString('en-US', {month: 'short', day: 'numeric'}) };
const kb = n => n > 1048576 ? (n / 1048576).toFixed(1) + ' MB' : Math.max(1, Math.round(n / 1024)) + ' KB';

const CSS = `
.bd{display:grid;gap:14px}
.bd .pbar{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
.bd .pchip{font:700 15px var(--body,system-ui);min-height:40px;padding:6px 14px;border-radius:999px;border:2px solid var(--line);background:var(--bg);color:var(--ink);cursor:pointer;position:relative}
.bd .pchip[aria-pressed=true]{background:var(--ink);color:var(--bg);border-color:var(--ink)}
.bd .pchip .n{display:inline-block;min-width:20px;padding:0 6px;margin-left:6px;border-radius:999px;background:#e11d48;color:#fff;font-size:12px;line-height:20px;text-align:center}
.bd .ghost{border-style:dashed;color:var(--mute)}
.bd .panel{background:var(--card);border-radius:16px;padding:14px;display:grid;gap:10px}
.bd .sub{display:flex;gap:6px;flex-wrap:wrap}
.bd .sub button,.bd .fl button{min-height:36px;padding:4px 12px;font-size:14px;border-radius:999px}
.bd .sub button[aria-pressed=true],.bd .fl button[aria-pressed=true]{background:var(--ink);color:var(--bg);border-color:var(--ink)}
.bd .sec{font:800 13px var(--body,system-ui);text-transform:uppercase;letter-spacing:.06em;color:var(--mute);margin:6px 2px 0}
.bd .post{background:var(--card);border-radius:16px;padding:12px 14px;display:grid;gap:6px;cursor:pointer;border-left:6px solid var(--tc,#64748b)}
.bd .post.unread{box-shadow:0 0 0 2px #e11d48 inset}
.bd .post.ment{background:linear-gradient(90deg,rgba(250,204,21,.18),transparent 60%),var(--card)}
.bd .post.res{opacity:.65}
.bd .ph{display:flex;gap:6px;align-items:center;flex-wrap:wrap;font-size:13px;color:var(--mute)}
.bd .tag{font-weight:700;font-size:12px;padding:2px 9px;border-radius:999px;background:var(--tc);color:#fff}
.bd .new{font-weight:800;font-size:11px;padding:2px 7px;border-radius:6px;background:#e11d48;color:#fff}
.bd .pt{font-weight:700;font-size:17px;overflow-wrap:anywhere}
.bd .pb{font-size:14.5px;color:var(--ink);opacity:.85;overflow-wrap:anywhere;white-space:pre-wrap}
.bd .pf{display:flex;gap:12px;flex-wrap:wrap;font-size:13px;color:var(--mute)}
.bd .late{color:#e11d48;font-weight:700}
.bd input[type=text],.bd input[type=date],.bd textarea,.bd select{font:16px/1.4 var(--body,system-ui);color:var(--ink);background:var(--bg);border:1.5px solid var(--line);border-radius:12px;padding:10px 12px;width:100%}
.bd textarea{min-height:90px;resize:vertical}
.bd .row{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
.bd .go{background:var(--acc);border-color:var(--acc);color:var(--accInk,#fff)}
.bd .bad{color:var(--bad)}
.bd .det{display:grid;gap:12px}
.bd .det .pb{opacity:1;font-size:16px}
.bd .rep{border-left:3px solid var(--line);padding:6px 0 6px 10px;display:grid;gap:4px}
.bd .rep .who{font-size:13px;color:var(--mute)}
.bd .rep .who b{color:var(--ink)}
.bd .rep .acts{display:flex;gap:6px}
.bd .rep .acts button{min-height:30px;padding:2px 10px;font-size:13px;border-radius:8px}
.bd .kids{margin-left:14px;display:grid;gap:6px}
.bd .mention{background:rgba(250,204,21,.35);border-radius:4px;padding:0 2px;font-weight:700}
.bd .thumb{max-width:100%;max-height:260px;border-radius:10px;display:block}
.bd .flink{display:inline-flex;align-items:center;gap:6px;font-weight:700;min-height:36px;padding:4px 12px;border:1.5px solid var(--line);border-radius:10px;background:var(--bg);cursor:pointer;color:var(--ink);font-size:14px}
.bd .empty{color:var(--mute);text-align:center;padding:24px 10px;border:1.5px dashed var(--line);border-radius:16px}
.bd .code{font:800 26px ui-monospace,monospace;letter-spacing:.2em}
.bd details>summary{cursor:pointer;font-weight:700;min-height:32px}
.bd .act{font-size:14px;padding:8px 0;border-bottom:1px solid var(--line);cursor:pointer}
.bd .act:last-child{border:0}
.bd .poll,.bd .chk{display:grid;gap:6px}
.bd .popt{position:relative;overflow:hidden;display:flex;justify-content:space-between;gap:8px;text-align:left;min-height:42px;padding:8px 12px;border-radius:10px;border:1.5px solid var(--line);background:var(--bg);color:var(--ink);font:600 15px var(--body,system-ui)}
.bd .popt.on{border-color:var(--acc)}
.bd .pbar2{position:absolute;left:0;top:0;bottom:0;background:rgba(15,122,74,.18);z-index:0}
.bd .ptxt,.bd .pct{position:relative;z-index:1}.bd .pct{color:var(--mute);font-size:13px;white-space:nowrap}
.bd .citem{display:flex;gap:10px;align-items:center;text-align:left;min-height:40px;padding:6px 10px;border-radius:10px;border:1.5px solid var(--line);background:var(--bg);color:var(--ink);font:500 15px var(--body,system-ui)}
.bd .citem small{margin-left:auto;color:var(--mute)}
.bd .citem.on span:nth-child(2){text-decoration:line-through;color:var(--mute)}
.bd .cbox{flex:0 0 22px;height:22px;border-radius:6px;border:2px solid var(--acc);display:flex;align-items:center;justify-content:center;font-weight:800;color:#fff}
.bd .citem.on .cbox{background:var(--acc)}
.bd .evt{font-size:15px}
.bd .remind{border:2px solid #facc15}
.bd .gal{display:grid;grid-template-columns:repeat(3,1fr);gap:6px}
.bd .gtile{position:relative;aspect-ratio:1;border-radius:10px;overflow:hidden;background:var(--card);cursor:pointer}
.bd .gtile img,.bd .gtile video{width:100%;height:100%;object-fit:cover;display:block}
.bd .gtile span{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;color:#fff;font-size:28px;text-shadow:0 1px 4px #000}
.bd .cgrid{display:grid;grid-template-columns:repeat(7,1fr);gap:4px}
.bd .chd{text-align:center;font-size:12px;color:var(--mute);font-weight:700}
.bd .cday{position:relative;min-height:46px;padding:4px;border-radius:8px;border:1px solid var(--line);background:var(--bg);color:var(--ink);font:600 14px var(--body,system-ui);display:flex;flex-direction:column;align-items:center;gap:2px}
.bd .cday.today{border:2px solid var(--acc)}.bd .cday.sel{background:var(--ink);color:var(--bg)}
.bd .cday i{font-style:normal;font-size:11px;background:#e11d48;color:#fff;border-radius:999px;padding:0 6px}
.bd .empty2{border:0;background:none}
.bd .tagbar{display:flex;gap:6px;flex-wrap:wrap;align-items:center;font-size:13px;color:var(--mute)}
.bd .tg{min-height:32px;padding:2px 10px;font:700 13px var(--body,system-ui);border-radius:999px;border:1.5px dashed var(--line);background:var(--bg);color:var(--ink);cursor:pointer}
.bd .tg[aria-pressed=true]{background:#facc15;border:1.5px solid #facc15;color:#111}
.bd .tagged{font-size:13px;color:var(--ink)}
.bd .tg.au[aria-pressed=true]{background:#0f7a4a;border:1.5px solid #0f7a4a;color:#fff}
.bd .priv{font-weight:700;font-size:12px;padding:2px 8px;border-radius:999px;background:#334155;color:#fff}
`;

export function mountBoard({sb, user, displayName, root, device = () => '', devices = () => [], token = () => '', isManager = () => false, onUnread = () => {}, toast = () => {}}) {
  if (!document.getElementById('bd-css')) { const st = document.createElement('style'); st.id = 'bd-css'; st.textContent = CSS; document.head.append(st); }
  root.classList.add('bd');
  const me = user.id, myName = (displayName || 'user').toLowerCase();
  let votes = [], q = '', qUser = '', calMonth = null, calSel = null, gallery = false, ptype = 'post', knownIds = null, alertsOn = false, pExcl = new Set(), eExcl = new Set(), myViews = new Set(), opens = [], lastSeen = {}, prevReads = null, newReads = 0, excl = new Set(), autoMade = false, projects = [], cur = null, members = [], names = {}, posts = [], replies = [], views = [], tab = 'board', filt = 'all', openId = null, replyTo = null, unread = {}, chan = null, urls = {}, busy = false, tmr = null;
  try { cur = localStorage.getItem('bd-cur-' + me) } catch (_) {}

  const nm = id => names[id] || 'someone';
  const dev = () => device() || '';
  const keyOf = (uid, d) => uid === me ? 'd:' + (d || '') : 'u:' + uid;
  const label = k => k.startsWith('d:') ? (k.slice(2) || 'this account') : nm(k.slice(2));
  const who = o => o.user_id === me ? (o.device || displayName) : nm(o.user_id) + (o.device ? ' · ' + o.device : '');
  const viewedBy = pid => [...new Set(views.filter(v => v.post_id === pid).map(v => keyOf(v.user_id, v.device)))];
  const audience = p => { const pk = keyOf(p.user_id, p.device); return [...new Set([...(p.recipients || P()?.allowed || devices()).map(d => 'd:' + d), ...members.filter(m => m.user_id !== me).map(m => 'u:' + m.user_id)])].filter(k => k !== pk); };
  const mineHere = p => p.user_id === me && (p.device || '') === dev();
  const seenHere = p => myViews.has(p.id);
  const handle = n => '@' + n.trim().replace(/\s+/g, '_');
  const people = () => [...new Set([...devices(), ...members.filter(m => m.user_id !== me).map(m => nm(m.user_id))].filter(Boolean))];
  const hasTag = (t, n) => new RegExp(reEsc(handle(n)) + '(?![\\w])', 'i').test(t || '');
  const tagsIn = t => people().filter(n => hasTag(t, n));
  const tagBar = target => { const L = people(); if (!L.length) return ''; const cur = root.querySelector('#' + target)?.value || '';
    return `<div class="tagbar" data-for="${target}"><span>Tag:</span>${L.map(n => `<button type="button" class="tg" data-tag="${esc(n)}" aria-pressed="${hasTag(cur, n)}">${esc(handle(n))}</button>`).join('')}</div>`; };
  const others = () => devices().filter(n => n && n !== dev());
  const inProj = () => { const al = P()?.allowed; return al ? others().filter(n => al.some(a => a.toLowerCase() === n.toLowerCase())) : others(); };
  const audBar = () => { const L = inProj(); if (!L.length) return ''; const allOn = L.every(n => !excl.has(n));
    return `<div class="tagbar aud"><span>Who sees it:</span>${L.map(n => `<button type="button" class="tg au" data-aud="${esc(n)}" aria-pressed="${!excl.has(n)}">${esc(n)}</button>`).join('')}<b style="font-size:13px;color:var(--ink)">${allOn ? '🌐 Whole board' : '🔒 Private'}</b></div>`; };
  const recipFromExcl = () => { const L = inProj(); return L.every(n => !excl.has(n)) ? null : L.filter(n => !excl.has(n)); };
  const track = p => { const aud = audience(p), out = {read: [], since: [], not: []};
    aud.forEach(k => { const v = views.filter(x => keyOf(x.user_id, x.device) === k && x.post_id === p.id).sort((a, b) => new Date(a.viewed_at) - new Date(b.viewed_at))[0];
      if (v) return out.read.push({k, at: v.viewed_at});
      const ls = k.startsWith('d:') ? lastSeen[k.slice(2)] : null;
      if (ls && new Date(ls) > new Date(p.created_at)) out.since.push({k, at: ls}); else out.not.push({k, at: ls}); });
    return out; };
  const tm = t => t ? new Date(t).toLocaleString('en-US', {month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit'}) : 'never';
  const projChips = (sel, attr) => { const L = others(); if (!L.length) return '<span>No other users yet.</span>';
    return '<span>Who can see it:</span>' + L.map(n => `<button type="button" class="tg au" ${attr}="${esc(n)}" aria-pressed="${!sel.has(n)}">${esc(n)}</button>`).join('') + `<b style="font-size:13px;color:var(--ink)">${L.every(n => !sel.has(n)) ? '🌐 Everyone' : '🔒 Only selected'}</b>`; };
  const newProjForm = () => `<div class="panel"><b>Start a project</b><div class="row"><input type="text" id="bd-nx" placeholder="Project name" maxlength="60" style="flex:1 1 200px"><button class="go" data-x="new-go">Create</button></div><div class="tagbar" id="bd-pch">${projChips(pExcl, 'data-pd')}</div></div>`;
  function notify(title, body, pid, tagged) {
    if (tagged) title = '🏷 ' + title + ' (you were tagged)';
    if (alertsOn && 'Notification' in window && Notification.permission === 'granted' && document.hidden && navigator.serviceWorker) {
      navigator.serviceWorker.ready.then(r => r.showNotification(title, {body, tag: pid, data: {url: location.origin + location.pathname}, icon: 'icon.svg'})).catch(() => {});
    } else if (!document.hidden) toast(title);
  }
  try { alertsOn = localStorage.getItem('bd-alerts-' + me) === 'on' && 'Notification' in window && Notification.permission === 'granted'; } catch (_) {}
  if (alertsOn && navigator.serviceWorker) navigator.serviceWorker.register('sw.js').catch(() => {});
  const dkey = d => { const x = new Date(d); return x.getFullYear() + '-' + String(x.getMonth() + 1).padStart(2, '0') + '-' + String(x.getDate()).padStart(2, '0'); };
  const evWhen = t => new Date(t).toLocaleString('en-US', {weekday: 'short', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit'});
  const datesOf = p => [p.due, p.event_at ? dkey(p.event_at) : null].filter(Boolean);
  function typeBlock(p) {
    if (p.ptype === 'poll' && Array.isArray(p.options)) {
      const vs = votes.filter(v => v.post_id === p.id), total = vs.length, mineV = vs.find(v => v.user_id === me && (v.device || '') === dev());
      return `<div class="poll">${p.options.map((o, i) => { const n = vs.filter(v => v.choice === i).length, pct = total ? Math.round(n * 100 / total) : 0;
        return `<button class="popt${mineV && mineV.choice === i ? ' on' : ''}" data-vote="${p.id}:${i}"><span class="pbar2" style="width:${pct}%"></span><span class="ptxt">${esc(o)}</span><span class="pct">${n} · ${pct}%</span></button>`; }).join('')}
        <div class="pf">${total} vote${total === 1 ? '' : 's'}${mineV ? ' · tap another to change' : ' · tap to vote'}${vs.length ? ' · ' + esc(vs.map(v => (v.user_id === me ? v.device : nm(v.user_id)) + ': ' + (p.options[v.choice] || '')).join(', ')) : ''}</div></div>`;
    }
    if (p.ptype === 'checklist' && Array.isArray(p.options)) {
      const done = p.options.filter(x => x.done).length;
      return `<div class="chk">${p.options.map((o, i) => `<button class="citem${o.done ? ' on' : ''}" data-chk="${p.id}:${i}:${o.done ? 0 : 1}"><span class="cbox">${o.done ? '✓' : ''}</span><span>${esc(o.t)}</span>${o.done && o.by ? `<small>${esc(o.by)}</small>` : ''}</button>`).join('')}<div class="pf">${done} of ${p.options.length} done</div></div>`;
    }
    if (p.ptype === 'event' && p.event_at) return `<div class="evt">🗓 <b>${esc(evWhen(p.event_at))}</b></div>`;
    return '';
  }
  const isUnread = p => !mineHere(p) && !seenHere(p) && p.status === 'open';
  const isAdmin = () => members.some(m => m.user_id === me && m.role === 'admin');
  const reEsc = x => x.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/\s+/g, '_?');
  const mentionsMe = t => [myName, dev()].filter(Boolean).some(n => new RegExp('@' + reEsc(n) + '\\b', 'i').test(t || ''));
  const hl = t => esc(t).replace(/@([a-z0-9_.]{2,30})/gi, (m, n) => `<span class="mention">${m}</span>`);
  const P = () => projects.find(p => p.id === cur);

  async function upsertProfile() { await sb.from('hub_profiles').upsert({user_id: me, username: displayName, updated_at: new Date().toISOString()}); }
  async function loadProjects() {
    const {data} = token() ? await sb.rpc('hub_my_projects', {p_token: token()}) : await sb.from('hub_projects').select('*').order('created_at');
    projects = data || [];
    if (!projects.length && !autoMade) { autoMade = true; const {data} = await sb.rpc('hub_create_project', {p_name: displayName + "'s board", p_token: token() || null}); if (data) { projects = [data]; } }
    if (!projects.some(p => p.id === cur)) cur = projects[0]?.id || null;
  }
  async function loadUnread() {
    if (!projects.length) { unread = {}; onUnread(0); return; }
    const [{data: ps}, {data: vs}] = await Promise.all([
      sb.from('hub_posts').select('id,project_id,user_id,device,status').eq('status', 'open').limit(2000),
      token() ? sb.rpc('hub_my_views', {p_token: token()}) : Promise.resolve({data: []})]);
    let all = ps || [];
    if (token()) for (const pr of projects) { const {data} = await sb.rpc('hub_private_posts', {p_token: token(), p_project: pr.id}); all = all.concat((data || []).filter(x => x.status === 'open')); }
    const seen = new Set((vs || []).map(v => v.post_id)); myViews = seen; unread = {};
    all.forEach(p => { if (!mineHere(p) && !seen.has(p.id)) unread[p.project_id] = (unread[p.project_id] || 0) + 1; });
    onUnread(Object.values(unread).reduce((a, b) => a + b, 0));
  }
  async function loadProject() {
    if (!cur) { members = []; posts = []; replies = []; views = []; return; }
    const [m, p, r, v] = await Promise.all([
      sb.from('hub_members').select('*').eq('project_id', cur),
      sb.from('hub_posts').select('*').eq('project_id', cur).order('created_at', {ascending: false}).limit(500),
      sb.from('hub_replies').select('*').eq('project_id', cur).order('created_at').limit(3000),
      token() && isManager() ? sb.rpc('hub_tracking', {p_token: token(), p_project: cur}) : Promise.resolve({data: null})]);
    members = m.data || []; posts = p.data || []; replies = r.data || [];
    const tr = v.data; views = tr ? (tr.views || []).map(x => ({...x, viewed_at: x.at})) : []; opens = tr ? tr.opens || [] : []; lastSeen = {}; (tr ? tr.devices || [] : []).forEach(d => lastSeen[d.name] = d.last_seen);
    if (token()) { const [pp, pr] = await Promise.all([sb.rpc('hub_private_posts', {p_token: token(), p_project: cur}), sb.rpc('hub_private_replies', {p_token: token(), p_project: cur})]);
      posts = [...posts, ...(pp.data || [])].sort((a, b) => new Date(b.created_at) - new Date(a.created_at)); replies = [...replies, ...(pr.data || [])].sort((a, b) => new Date(a.created_at) - new Date(b.created_at)); }
    if (token()) { const {data} = await sb.rpc('hub_poll_votes', {p_token: token(), p_project: cur}); votes = data || []; } else votes = [];
    { const ids = new Set([...posts.map(x => 'p' + x.id), ...replies.map(x => 'r' + x.id)]);
      if (knownIds && knownIds.cur === cur) { posts.forEach(x => { if (!knownIds.has('p' + x.id) && !mineHere(x)) notify((x.ptype === 'poll' ? 'New poll' : x.ptype === 'event' ? 'New event' : x.ptype === 'checklist' ? 'New checklist' : 'New post') + ' from ' + who(x), x.title, x.id, mentionsMe(x.title + ' ' + (x.body || ''))); });
        replies.forEach(x => { if (!knownIds.has('r' + x.id) && !(x.user_id === me && (x.device || '') === dev())) { const p = posts.find(q => q.id === x.post_id); notify(who(x) + ' replied' + (p ? ' to “' + p.title + '”' : ''), x.body.slice(0, 120), x.post_id, mentionsMe(x.body)); } }); }
      knownIds = ids; knownIds.cur = cur; }
    if (isManager()) { const mine = new Set(posts.filter(mineHere).map(p => p.id)); const reads = views.filter(x => mine.has(x.post_id) && !(x.user_id === me && (x.device || '') === dev()));
      const keys = new Set(reads.map(x => x.post_id + '|' + x.user_id + '|' + x.device));
      if (prevReads) reads.forEach(x => { const k = x.post_id + '|' + x.user_id + '|' + x.device; if (!prevReads.has(k)) { newReads++; const p = posts.find(q => q.id === x.post_id); toast('👁 ' + (x.user_id === me ? x.device : nm(x.user_id)) + ' just read “' + (p ? p.title : 'your post') + '”'); } });
      prevReads = keys; }
    const ids = [...new Set([...members.map(x => x.user_id), ...posts.map(x => x.user_id), ...replies.map(x => x.user_id)])];
    if (ids.length) { const {data} = await sb.from('hub_profiles').select('user_id,username').in('user_id', ids); (data || []).forEach(x => names[x.user_id] = x.username); }
  }
  async function refresh() { if (token()) sb.rpc('hub_ping', {p_token: token()}).then(() => {}); await loadProjects(); await Promise.all([loadProject(), loadUnread()]); render(); }
  const soon = () => { clearTimeout(tmr); tmr = setTimeout(() => refresh().catch(() => {}), 350); };

  async function fileUrl(path) { if (urls[path]) return urls[path]; const {data, error} = await sb.storage.from('boards').createSignedUrl(path, 3600); if (error) throw error; return urls[path] = data.signedUrl; }
  async function upload(pid, f) {
    if (f.size > MAXF) throw new Error(f.name + ' is over 10 MB');
    const path = pid + '/' + Date.now().toString(36) + '-' + (f.name || 'file').replace(/[^\w.-]+/g, '-');
    const {error} = await sb.storage.from('boards').upload(path, f, {contentType: f.type || 'application/octet-stream'});
    if (error) throw error;
    return {file_path: path, file_name: f.name || 'file', file_size: f.size, file_type: f.type || ''};
  }
  async function postTo(pid, {title, body, tag = 'Note', due = null, file = null, recipients = null, ptype = 'post', options = null, event_at = null}) {
    const extra = file ? await upload(pid, file) : {};
    const {error} = await sb.rpc('hub_post_x', {p_ptype: ptype, p_options: options, p_event_at: event_at, p_token: token(), p_project: pid, p_title: title.slice(0, 140), p_body: body, p_tag: tag, p_due: due || null,
      p_file_path: extra.file_path || null, p_file_name: extra.file_name || null, p_file_size: extra.file_size || null, p_file_type: extra.file_type || null, p_recipients: recipients && recipients.length ? recipients : null});
    if (error) throw error;
    soon();
  }
  async function markViewed(p) {
    if (mineHere(p) || seenHere(p)) return;
    myViews.add(p.id);
    await sb.rpc('hub_view', {p_token: token(), p_post: p.id});
    loadUnread();
  }

  /* ---------- render ---------- */
  function render() {
    const keep = {}; ['bd-t', 'bd-b', 'bd-r', 'bd-nx', 'bd-due', 'bd-tag', 'bd-opts', 'bd-ev', 'bd-q'].forEach(id => { const el = root.querySelector('#' + id); if (el && el.value) keep[id] = el.value; });
    const compOpen = root.querySelector('#bd-compose')?.open, act = document.activeElement?.id, formHTML = root.querySelector('#bd-form')?.innerHTML || '';
    draw();
    if (formHTML && root.querySelector('#bd-form')) root.querySelector('#bd-form').innerHTML = formHTML;
    Object.entries(keep).forEach(([id, v]) => { const el = root.querySelector('#' + id); if (el) el.value = v; });
    if (compOpen && root.querySelector('#bd-compose')) root.querySelector('#bd-compose').open = true;
    if (act && root.querySelector('#' + act)) root.querySelector('#' + act).focus();
    syncTags();
  }
  function draw() {
    const bar = `<div class="pbar">${projects.map(p => `<button class="pchip" data-p="${p.id}" aria-pressed="${p.id === cur}">${p.allowed ? '🔒 ' : ''}${esc(p.name)}${unread[p.id] ? `<span class="n">${unread[p.id]}</span>` : ''}</button>`).join('')}
      ${token() ? '<button class="pchip ghost" data-x="new">+ New project</button>' : ''}${'Notification' in window ? `<button class="pchip ghost" data-x="alerts">${alertsOn ? '🔔 Alerts on' : '🔕 Turn on alerts'}</button>` : ''}</div>
      <div id="bd-form"></div>`;
    if (!projects.length) { root.innerHTML = bar + `<div class="empty">No projects yet. Tap <b>+ New project</b> to start one.</div>`; return; }
    const subtabs = `<div class="sub">${[['board', 'Board'], ['cal', 'Calendar'], ['activity', 'Activity'], ['files', 'Files'], ['members', 'Access']].map(([k, l]) => `<button data-t="${k}" aria-pressed="${tab === k}">${l}</button>`).join('')}</div>`;
    let body = '';
    if (openId) body = detail(); else if (tab === 'board') body = board(); else if (tab === 'activity') body = activity(); else if (tab === 'files') body = files(); else if (tab === 'cal') body = calendar(); else body = membersView();
    root.innerHTML = bar + (openId ? '' : subtabs) + body;
    root.querySelectorAll('img[data-img]').forEach(async im => { try { im.src = await fileUrl(im.dataset.img) } catch (_) {} });
    root.querySelectorAll('[data-media]').forEach(async el => { try { el.src = await fileUrl(el.dataset.media) } catch (_) {} });
  }
  function card(p) {
    const seen = viewedBy(p.id), isNew = isUnread(p);
    const others = audience(p);
    const seenN = others.filter(k => seen.includes(k)), waiting = others.length - seenN.length;
    const rc = replies.filter(r => r.post_id === p.id).length;
    const late = p.due && p.status === 'open' && new Date(p.due + 'T23:59') < new Date();
    const ment = mentionsMe(p.body) || mentionsMe(p.title);
    return `<article class="post${isNew ? ' unread' : ''}${ment ? ' ment' : ''}${p.status === 'resolved' ? ' res' : ''}" style="--tc:${TAGC[p.tag] || '#64748b'}" data-open="${p.id}">
      <div class="ph"><span class="tag">${esc(p.tag || 'Note')}</span>${isNew ? '<span class="new">NEW</span>' : ''}${p.pinned ? '📌' : ''}${p.recipients ? `<span class="priv">🔒 ${esc(p.recipients.join(', '))}</span>` : ''}${p.status === 'resolved' ? '✅ Resolved' : ''}<span>${esc(who(p))} · ${ago(p.created_at)}</span></div>
      <div class="pt">${hl(p.title)}</div>
      ${p.body ? `<div class="pb">${hl(p.body.length > 180 ? p.body.slice(0, 180) + '…' : p.body)}</div>` : ''}
      ${typeBlock(p)}
      <div class="pf"><span>💬 ${rc}</span>${isManager() ? (() => { const t = track(p); return `<span>👁 ${t.read.length ? esc(t.read.map(x => label(x.k)).join(', ')) : 'No one yet'}</span>${t.since.length ? `<span>🟡 On since: ${esc(t.since.map(x => label(x.k)).join(', '))}</span>` : ''}${t.not.length ? `<span>⚪ Not on since: ${esc(t.not.map(x => label(x.k)).join(', '))}</span>` : ''}`; })() : ''}${p.due ? `<span class="${late ? 'late' : ''}">📅 ${late ? 'Overdue · ' : 'Due '}${new Date(p.due + 'T12:00').toLocaleDateString('en-US', {month: 'short', day: 'numeric'})}</span>` : ''}${p.file_name ? '<span>📎 ' + esc(p.file_name) + '</span>' : ''}${(() => { const t = tagsIn(p.title + ' ' + (p.body || '')); return t.length ? `<span class="tagged">🏷 ${esc(t.join(', '))}</span>` : '' })()}</div></article>`;
  }
  function board() {
    let L = posts;
    const ql = q.trim().toLowerCase();
    if (ql) L = L.filter(p => [p.title, p.body, p.file_name, p.device, ...(Array.isArray(p.options) ? p.options.map(o => typeof o === 'string' ? o : o.t) : []), ...replies.filter(r => r.post_id === p.id).flatMap(r => [r.body, r.file_name])].some(x => (x || '').toLowerCase().includes(ql)));
    if (qUser) L = L.filter(p => who(p).toLowerCase().includes(qUser.toLowerCase()) || replies.some(r => r.post_id === p.id && who(r).toLowerCase().includes(qUser.toLowerCase())));
    if (filt === 'mine') L = L.filter(p => mentionsMe(p.body) || mentionsMe(p.title) || replies.some(r => r.post_id === p.id && mentionsMe(r.body)));
    else if (filt === 'myposts') { L = L.filter(mineHere); newReads = 0; }
    else if (filt !== 'all') L = L.filter(p => p.tag === filt);
    const pinned = L.filter(p => p.pinned && p.status === 'open');
    const un = L.filter(p => !p.pinned && isUnread(p));
    const open = L.filter(p => !p.pinned && !isUnread(p) && p.status === 'open');
    const res = L.filter(p => p.status === 'resolved');
    const today = dkey(new Date()), tmr2 = dkey(new Date(Date.now() + 864e5));
    const soonL = posts.filter(p => p.status === 'open' && datesOf(p).some(d => d === today || d === tmr2));
    const remind = soonL.length ? `<div class="panel remind"><b>⏰ Coming up</b>${soonL.map(p => `<div class="act" data-open="${p.id}">${datesOf(p).includes(today) ? '<b>Today</b>' : 'Tomorrow'} · ${esc(p.title)}${p.event_at ? ' · ' + esc(new Date(p.event_at).toLocaleTimeString('en-US', {hour: 'numeric', minute: '2-digit'})) : ''}</div>`).join('')}</div>` : '';
    const users = [...new Set([...devices(), ...posts.map(who)])].filter(Boolean);
    const search = `<div class="row"><input type="text" id="bd-q" placeholder="🔍 Search posts, replies, files" value="${esc(q)}" style="flex:2 1 200px"><select id="bd-qu" style="flex:1 1 120px"><option value="">Anyone</option>${users.map(u => `<option${u === qUser ? ' selected' : ''}>${esc(u)}</option>`).join('')}</select></div>`;
    const extra = ptype === 'poll' ? '<textarea id="bd-opts" placeholder="Poll choices, one per line (2 or more)"></textarea>' : ptype === 'checklist' ? '<textarea id="bd-opts" placeholder="Checklist items, one per line"></textarea>' : ptype === 'event' ? '<label style="font-size:13px;color:var(--mute)">When<input type="datetime-local" id="bd-ev"></label>' : '';
    const compose = remind + search + `<details class="panel" id="bd-compose"><summary>＋ New post</summary>
      <div class="sub">${[['post', 'Post'], ['poll', 'Poll'], ['checklist', 'Checklist'], ['event', 'Event']].map(([k, l]) => `<button type="button" data-pt="${k}" aria-pressed="${ptype === k}">${l}</button>`).join('')}</div>
      <input type="text" id="bd-t" placeholder="${ptype === 'poll' ? 'Question, e.g. Pizza or tacos Friday?' : ptype === 'checklist' ? 'List name, e.g. Grocery list' : ptype === 'event' ? 'Event name, e.g. Game night' : 'Title'}" maxlength="140">
      ${extra}
      ${audBar()}
      ${tagBar('bd-b')}
      <textarea id="bd-b" placeholder="Details… tap a name above to tag them"></textarea>
      <div class="row"><select id="bd-tag" style="flex:1 1 120px">${TAGS.map(t => `<option>${t}</option>`).join('')}</select>
      <label style="flex:1 1 150px;font-size:13px;color:var(--mute)">Due (optional)<input type="date" id="bd-due"></label></div>
      <div class="row"><input type="file" id="bd-f" style="flex:1 1 200px;font-size:14px"><button class="go" data-x="post" style="flex:1 1 140px">Post to board</button></div></details>`;
    const fl = `<div class="fl sub"><button data-f="all" aria-pressed="${filt === 'all'}">All</button><button data-f="mine" aria-pressed="${filt === 'mine'}">@ Mentions me</button>${isManager() ? `<button data-f="myposts" aria-pressed="${filt === 'myposts'}">My posts${newReads ? ' · 👁 ' + newReads : ''}</button>` : ''}${TAGS.map(t => `<button data-f="${t}" aria-pressed="${filt === t}">${t}</button>`).join('')}</div>`;
    const sec = (t, a) => a.length ? `<div class="sec">${t}</div>${a.map(card).join('')}` : '';
    const list = pinned.length + un.length + open.length + res.length ? sec('📌 Pinned', pinned) + sec(`🔴 Unread (${un.length})`, un) + sec('Open', open) + (res.length ? `<details><summary class="sec">✅ Resolved (${res.length})</summary><div style="display:grid;gap:10px;margin-top:8px">${res.map(card).join('')}</div></details>` : '') : `<div class="empty">${posts.length ? 'Nothing matches that filter.' : 'No posts yet. Tap <b>＋ New post</b> to start the board.'}</div>`;
    return compose + fl + `<div style="display:grid;gap:10px">${list}</div>`;
  }
  function fileBlock(o, pid) {
    if (!o.file_path) return '';
    const img = /^image\//.test(o.file_type || ''), vid = /^video\//.test(o.file_type || ''), aud = /^audio\//.test(o.file_type || '');
    return `${img ? `<img class="thumb" data-img="${esc(o.file_path)}" alt="">` : ''}${vid ? `<video class="thumb" controls preload="metadata" data-media="${esc(o.file_path)}"></video>` : ''}${aud ? `<audio controls preload="none" data-media="${esc(o.file_path)}" style="width:100%"></audio>` : ''}<span class="flink" data-file="${esc(o.file_path)}" data-fpost="${pid || o.post_id || o.id}">📎 ${esc(o.file_name)} · ${kb(o.file_size || 0)}</span>`;
  }
  function tree(postId, parent, depth) {
    const kids = replies.filter(r => r.post_id === postId && (r.parent_id || null) === parent);
    if (!kids.length) return '';
    return kids.map(r => `<div class="rep"><div class="who"><b>${esc(who(r))}</b> · ${ago(r.created_at)}</div><div class="pb">${hl(r.body)}</div>${fileBlock(r, r.post_id)}
      <div class="acts"><button data-rto="${r.id}">Reply</button>${isManager() ? `<button class="bad" data-rdel="${r.id}">Delete</button>` : ''}</div>
      ${(() => { const k = tree(postId, r.id, depth + 1); return k ? `<div class="kids"${depth >= 3 ? ' style="margin-left:0"' : ''}>${k}</div>` : '' })()}</div>`).join('');
  }
  function detail() {
    const p = posts.find(x => x.id === openId); if (!p) { openId = null; return board(); }
    const can = isManager();
    const seen = viewedBy(p.id), others = audience(p);
    const rt = replyTo ? replies.find(r => r.id === replyTo) : null;
    return `<div class="det"><div class="row"><button data-x="back">← Back to board</button></div>
      <article class="post" style="--tc:${TAGC[p.tag] || '#64748b'};cursor:default"><div class="ph"><span class="tag">${esc(p.tag)}</span>${p.recipients ? `<span class="priv">🔒 Private: ${esc(p.recipients.join(', '))}</span>` : ''}${p.pinned ? '📌 Pinned' : ''}${p.status === 'resolved' ? '✅ Resolved' : ''}<span>${esc(who(p))} · ${ago(p.created_at)}</span>${p.due ? `<span>📅 Due ${new Date(p.due + 'T12:00').toLocaleDateString('en-US', {month: 'short', day: 'numeric'})}</span>` : ''}</div>
      <div class="pt" style="font-size:21px">${hl(p.title)}</div>${p.body ? `<div class="pb">${hl(p.body)}</div>` : ''}${typeBlock(p)}${fileBlock(p, p.id)}
      <div class="row">${can ? `<button data-x="status">${p.status === 'open' ? '✅ Mark resolved' : '↩ Reopen'}</button><button data-x="pin">${p.pinned ? 'Unpin' : '📌 Pin'}</button><button class="bad" data-x="delpost">Delete</button>` : ''}</div>
      ${isManager() ? (() => { const t = track(p); const fo = opens.filter(o => o.post_id === p.id);
        return `<div class="panel" style="background:var(--bg)"><b>Manager view · who's seen this</b>
        ${t.read.map(x => `<div>👁 <b>${esc(label(x.k))}</b> read it · ${tm(x.at)}</div>`).join('')}
        ${t.since.map(x => `<div>🟡 <b>${esc(label(x.k))}</b> was on since (last ${tm(x.at)}) but didn't open it</div>`).join('')}
        ${t.not.map(x => `<div>⚪ <b>${esc(label(x.k))}</b> hasn't been on since you posted (last ${tm(x.at)})</div>`).join('')}
        ${p.file_path || fo.length ? `<b style="margin-top:6px">📎 File opened by</b>${fo.length ? fo.map(o => `<div>${esc(o.user_id === me ? o.device : nm(o.user_id))} · ${tm(o.at)}</div>`).join('') : '<div style="color:var(--mute)">No one yet</div>'}` : ''}</div>`; })() : ''}</article>
      <div class="sec">Conversation (${replies.filter(r => r.post_id === p.id).length})</div>
      ${tree(p.id, null, 0) || '<div class="empty" style="padding:14px">No replies yet.</div>'}
      <div class="panel" id="bd-reply">${rt ? `<div class="row" style="font-size:14px;color:var(--mute)">Replying to <b style="color:var(--ink)">${esc(who(rt))}</b><button data-x="cancelrt" style="min-height:30px;padding:2px 10px;font-size:13px">Cancel</button></div>` : ''}
      ${tagBar('bd-r')}
      <textarea id="bd-r" placeholder="Write a reply… tap a name above to tag them"></textarea>
      <div class="row"><input type="file" id="bd-rf" style="flex:1 1 200px;font-size:14px"><button class="go" data-x="reply" style="flex:1 1 140px">Send reply</button></div></div></div>`;
  }
  function calendar() {
    const now = new Date(); if (!calMonth) calMonth = new Date(now.getFullYear(), now.getMonth(), 1);
    const y = calMonth.getFullYear(), m = calMonth.getMonth(), first = new Date(y, m, 1).getDay(), days = new Date(y, m + 1, 0).getDate();
    const by = {}; posts.forEach(p => datesOf(p).forEach(d => { (by[d] ??= []).push(p); }));
    const cells = []; for (let i = 0; i < first; i++) cells.push('<div class="cday empty2"></div>');
    for (let d = 1; d <= days; d++) { const k = y + '-' + String(m + 1).padStart(2, '0') + '-' + String(d).padStart(2, '0'), it = by[k] || [];
      cells.push(`<button class="cday${k === dkey(now) ? ' today' : ''}${k === calSel ? ' sel' : ''}" data-cd="${k}"><span>${d}</span>${it.length ? `<i>${it.length}</i>` : ''}</button>`); }
    const sel = calSel ? (by[calSel] || []) : [];
    return `<div class="panel"><div class="row" style="justify-content:space-between"><button data-cm="${m === 0 ? y - 1 : y}-${(m + 11) % 12}">‹</button><b style="font-size:18px">${calMonth.toLocaleDateString('en-US', {month: 'long', year: 'numeric'})}</b><button data-cm="${m === 11 ? y + 1 : y}-${(m + 1) % 12}">›</button></div>
      <div class="cgrid">${['S', 'M', 'T', 'W', 'T', 'F', 'S'].map(x => `<div class="chd">${x}</div>`).join('')}${cells.join('')}</div>
      <span style="color:var(--mute);font-size:13px">Shows events and anything with a due date. To add one, make an <b>Event</b> post or give a post a due date.</span></div>
      ${calSel ? `<div class="panel"><b>${new Date(calSel + 'T12:00').toLocaleDateString('en-US', {weekday: 'long', month: 'long', day: 'numeric'})}</b>${sel.length ? sel.map(p => `<div class="act" data-open="${p.id}">${p.event_at && dkey(p.event_at) === calSel ? '🗓 ' + esc(new Date(p.event_at).toLocaleTimeString('en-US', {hour: 'numeric', minute: '2-digit'})) + ' · ' : '📅 Due · '}${esc(p.title)}</div>`).join('') : '<span style="color:var(--mute)">Nothing this day.</span>'}</div>` : ''}`;
  }
  function activity() {
    const ev = [...posts.map(p => ({t: p.created_at, who: who(p), txt: `posted <b>${esc(p.title)}</b>`, id: p.id})),
      ...replies.map(r => { const p = posts.find(x => x.id === r.post_id); return {t: r.created_at, who: who(r), txt: `replied to <b>${esc(p ? p.title : 'a post')}</b>`, id: r.post_id} })]
      .sort((a, b) => new Date(b.t) - new Date(a.t)).slice(0, 60);
    return `<div class="panel">${ev.length ? ev.map(e => `<div class="act" data-open="${e.id}"><b>${esc(e.who)}</b> ${e.txt} · <span style="color:var(--mute)">${ago(e.t)}</span></div>`).join('') : '<span style="color:var(--mute)">No activity yet.</span>'}</div>`;
  }
  function files() {
    const f = [...posts.filter(p => p.file_path).map(p => ({...p, from: p.title, pid: p.id})), ...replies.filter(r => r.file_path).map(r => ({...r, from: (posts.find(p => p.id === r.post_id) || {}).title, pid: r.post_id}))]
      .sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
    const gsw = `<div class="sub"><button data-gal="0" aria-pressed="${!gallery}">List</button><button data-gal="1" aria-pressed="${gallery}">Photo gallery</button></div>`;
    if (gallery) { const imgs = f.filter(x => /^(image|video)\//.test(x.file_type || ''));
      return gsw + (imgs.length ? `<div class="gal">${imgs.map(x => /^video/.test(x.file_type) ? `<div class="gtile" data-open="${x.pid}"><video data-media="${esc(x.file_path)}" preload="metadata" muted></video><span>▶</span></div>` : `<div class="gtile" data-open="${x.pid}"><img data-img="${esc(x.file_path)}" alt="${esc(x.file_name)}"></div>`).join('')}</div>` : '<div class="empty">No photos or videos shared yet.</div>'); }
    return gsw + `<div class="panel">${f.length ? f.map(x => `<div class="act" style="cursor:default"><span class="flink" data-file="${esc(x.file_path)}" data-fpost="${x.pid}">📎 ${esc(x.file_name)}</span> <span style="color:var(--mute);font-size:13px">${kb(x.file_size || 0)} · ${esc(who(x))} · ${ago(x.created_at)} · in <a href="#" data-open="${x.pid}" style="color:var(--ink)">${esc(x.from || 'post')}</a></span></div>`).join('') : '<span style="color:var(--mute)">No files shared yet.</span>'}</div>`;
  }
  function membersView() {
    const p = P(), can = isManager() || (p.created_by_device || '').toLowerCase() === dev().toLowerCase();
    const allDev = devices();
    eExcl = new Set(p.allowed ? others().filter(n => !p.allowed.some(a => a.toLowerCase() === n.toLowerCase())) : []);
    return `<div class="panel"><b>Who can see this project</b><div>${p.allowed ? '🔒 ' + esc(p.allowed.join(', ')) : '🌐 Everyone on this board'}</div>
      ${p.created_by_device ? `<span style="color:var(--mute);font-size:14px">Started by ${esc(p.created_by_device)}</span>` : ''}
      ${can ? `<div class="tagbar" id="bd-ech">${projChips(eExcl, 'data-ed')}</div><div class="row"><button class="go" data-x="saveacc">Save who can see it</button></div>` : '<span style="color:var(--mute);font-size:14px">Only the user who started this project, or the manager, can change this.</span>'}</div>
      ${can ? `<div class="panel"><b>Project settings</b><div class="row"><input type="text" id="bd-rn" value="${esc(p.name)}" maxlength="60" style="flex:1 1 200px"><button data-x="rename">Rename</button></div><button class="bad" data-x="delproj">Delete project</button></div>` : ''}`;
  }

  /* ---------- actions ---------- */
  const confirm2 = (b, label) => { if (b.dataset.sure === '1') return true; const o = b.textContent; b.dataset.sure = '1'; b.textContent = label || 'Tap again'; setTimeout(() => { if (b.isConnected) { b.dataset.sure = ''; b.textContent = o } }, 3000); return false; };
  root.addEventListener('click', async e => {
    const t = e.target.closest('button,[data-open],[data-file],a'); if (!t || busy) return;
    const d = t.dataset;
    if (d.pt) { ptype = d.pt; render(); return; }
    if (d.vote) { const [pid, i] = d.vote.split(':'); const {error} = await sb.rpc('hub_vote', {p_token: token(), p_post: pid, p_choice: +i}); if (error) return toast(error.message); await loadProject(); render(); return; }
    if (d.chk) { const [pid, i, v] = d.chk.split(':'); const {error} = await sb.rpc('hub_check_item', {p_token: token(), p_post: pid, p_idx: +i, p_done: v === '1'}); if (error) return toast(error.message); await loadProject(); render(); return; }
    if (d.cm) { const [y, m] = d.cm.split('-').map(Number); calMonth = new Date(y, m, 1); calSel = null; render(); return; }
    if (d.cd) { calSel = d.cd; render(); return; }
    if (d.gal) { gallery = d.gal === '1'; render(); return; }
    if (d.pd) { pExcl.has(d.pd) ? pExcl.delete(d.pd) : pExcl.add(d.pd); const c = root.querySelector('#bd-pch'); if (c) c.innerHTML = projChips(pExcl, 'data-pd'); return; }
    if (d.ed) { eExcl.has(d.ed) ? eExcl.delete(d.ed) : eExcl.add(d.ed); const c = root.querySelector('#bd-ech'); if (c) c.innerHTML = projChips(eExcl, 'data-ed'); return; }
    if (d.aud) { excl.has(d.aud) ? excl.delete(d.aud) : excl.add(d.aud); if (!recipFromExcl() && excl.size) {} const ob = root.querySelector('.aud'); if (ob) ob.outerHTML = audBar(); return; }
    if (d.tag) { const bar = t.closest('.tagbar'), ta = root.querySelector('#' + bar.dataset.for); if (!ta) return;
      const h = handle(d.tag);
      if (hasTag(ta.value, d.tag)) ta.value = ta.value.replace(new RegExp('\\s?' + reEsc(h) + '(?![\\w])', 'gi'), '').trimStart();
      else { const pos = ta.selectionStart ?? ta.value.length, before = ta.value.slice(0, pos), after = ta.value.slice(pos);
        const ins = (before && !/\s$/.test(before) ? ' ' : '') + h + ' '; ta.value = before + ins + after; ta.selectionStart = ta.selectionEnd = (before + ins).length; }
      syncTags(); ta.focus(); return; }
    try {
      if (d.p) { cur = d.p; try { localStorage.setItem('bd-cur-' + me, cur) } catch (_) {} openId = null; replyTo = null; await loadProject(); render(); }
      else if (d.t) { tab = d.t; render(); }
      else if (d.f) { filt = d.f; render(); }
      else if (d.file) { e.preventDefault(); toast('Opening…'); if (token()) sb.rpc('hub_file_open', {p_token: token(), p_post: d.fpost || null, p_path: d.file}).then(() => {}); window.open(await fileUrl(d.file), '_blank'); }
      else if (d.open) { e.preventDefault(); openId = d.open; replyTo = null; tab = 'board'; const p = posts.find(x => x.id === openId); if (p) markViewed(p); render(); window.scrollTo({top: root.offsetTop - 10}); }
      else if (d.rto) { replyTo = d.rto; render(); root.querySelector('#bd-r')?.focus(); }
      else if (d.rdel) { if (!confirm2(t)) return; { const {error} = await sb.rpc('hub_mod', {p_token: token(), p_kind: 'reply', p_id: d.rdel, p_action: 'delete'}); if (error) throw error; } replies = replies.filter(r => r.id !== d.rdel && r.parent_id !== d.rdel); render(); }
      else if (d.kick) { if (!confirm2(t)) return; await sb.from('hub_members').delete().eq('project_id', cur).eq('user_id', d.kick); await loadProject(); render(); }
      else if (d.role) { const m = members.find(x => x.user_id === d.role); await sb.from('hub_members').update({role: m.role === 'admin' ? 'member' : 'admin'}).eq('project_id', cur).eq('user_id', d.role); await loadProject(); render(); }
      else if (d.x) await act(d.x, t);
    } catch (err) { toast(err.message || 'Something went wrong'); }
  });
  async function act(x, b) {
    const p = openId && posts.find(q => q.id === openId);
    if (x === 'alerts') {
      if (alertsOn) { alertsOn = false; try { localStorage.setItem('bd-alerts-' + me, 'off') } catch (_) {} render(); return toast('Alerts off'); }
      const perm = await Notification.requestPermission(); if (perm !== 'granted') return toast('Alerts are blocked. Allow notifications for this site in your browser settings.');
      if (navigator.serviceWorker) await navigator.serviceWorker.register('sw.js').catch(() => {});
      alertsOn = true; try { localStorage.setItem('bd-alerts-' + me, 'on') } catch (_) {} render(); toast('Alerts on'); return;
    }
    if (x === 'new') { pExcl = new Set(); const f = root.querySelector('#bd-form'); f.innerHTML = newProjForm(); f.querySelector('input').focus(); }
    else if (x === 'join') {
      const f = root.querySelector('#bd-form');
      f.innerHTML = `<div class="panel"><b>${x === 'new' ? 'Start a project' : 'Join a project'}</b><div class="row"><input type="text" id="bd-nx" placeholder="${x === 'new' ? 'Project name' : 'Invite code, e.g. 7F3A9C'}" maxlength="60" style="flex:1 1 200px"><button class="go" data-x="${x}-go">${x === 'new' ? 'Create' : 'Join'}</button></div></div>`;
      f.querySelector('input').focus();
    } else if (x === 'new-go' || x === 'join-go') {
      const v = root.querySelector('#bd-nx').value.trim(); if (!v) return;
      busy = true;
      const pl = others().filter(n => !pExcl.has(n)); const devs = pExcl.size ? pl : null;
      const {data, error} = x === 'new-go' ? await sb.rpc('hub_create_project', {p_name: v, p_token: token(), p_devices: devs}) : await sb.rpc('hub_join_project', {p_code: v, p_token: token()});
      busy = false; if (error) return toast(error.message);
      cur = data.id; try { localStorage.setItem('bd-cur-' + me, cur) } catch (_) {}
      tab = 'board'; root.querySelector('#bd-form').innerHTML = ''; await refresh(); toast(x === 'new-go' ? 'Project created' : 'Joined ' + data.name);
    } else if (x === 'post') {
      const title = root.querySelector('#bd-t').value.trim(), body = root.querySelector('#bd-b').value.trim();
      if (!title) return toast('Give the post a title.');
      let options = null, event_at = null;
      if (ptype === 'poll' || ptype === 'checklist') { const lines = (root.querySelector('#bd-opts')?.value || '').split('\n').map(x => x.trim()).filter(Boolean).slice(0, 50);
        if (ptype === 'poll' && lines.length < 2) return toast('Add at least 2 choices.'); if (ptype === 'checklist' && !lines.length) return toast('Add at least 1 item.');
        options = ptype === 'poll' ? lines : lines.map(t => ({t, done: false, by: null})); }
      if (ptype === 'event') { const v = root.querySelector('#bd-ev')?.value; if (!v) return toast('Pick when the event is.'); event_at = new Date(v).toISOString(); }
      busy = true; b.disabled = true; b.textContent = 'Posting…';
      try { await postTo(cur, {title, body, tag: root.querySelector('#bd-tag').value, due: root.querySelector('#bd-due').value, file: root.querySelector('#bd-f').files[0], recipients: recipFromExcl(), ptype, options, event_at}); excl = new Set(); ['#bd-opts', '#bd-ev'].forEach(q2 => { const el = root.querySelector(q2); if (el) el.value = ''; }); ptype = 'post'; ['#bd-t', '#bd-b', '#bd-due'].forEach(q => root.querySelector(q).value = ''); root.querySelector('#bd-compose').open = false; toast('Posted'); await loadProject(); render(); }
      catch (err) { b.disabled = false; b.textContent = 'Post to board'; throw err; }
      finally { busy = false; }
    } else if (x === 'back') { openId = null; replyTo = null; render(); }
    else if (x === 'cancelrt') { replyTo = null; render(); }
    else if (x === 'reply') {
      const body = root.querySelector('#bd-r').value.trim(), f = root.querySelector('#bd-rf').files[0]; if (!body) return toast('Write something first.');
      busy = true; b.disabled = true; b.textContent = 'Sending…';
      try { const extra = f ? await upload(cur, f) : {}; const {error} = await sb.rpc('hub_reply', {p_token: token(), p_post: p.id, p_parent: replyTo, p_body: body, p_file_path: extra.file_path || null, p_file_name: extra.file_name || null, p_file_size: extra.file_size || null, p_file_type: extra.file_type || null}); if (error) throw error; root.querySelector('#bd-r').value = ''; replyTo = null; await loadProject(); render(); }
      catch (err) { b.disabled = false; b.textContent = 'Send reply'; throw err; }
      finally { busy = false; }
    } else if (x === 'status' || x === 'pin' || x === 'delpost') {
      const action = x === 'status' ? (p.status === 'open' ? 'resolve' : 'reopen') : x === 'pin' ? (p.pinned ? 'unpin' : 'pin') : 'delete';
      if (x === 'delpost' && !confirm2(b)) return;
      const {error} = await sb.rpc('hub_mod', {p_token: token(), p_kind: 'post', p_id: p.id, p_action: action}); if (error) throw error;
      if (x === 'delpost') { if (p.file_path) await sb.storage.from('boards').remove([p.file_path]); openId = null; }
      await loadProject(); render(); }
    else if (x === 'copycode') { try { await navigator.clipboard.writeText(P().invite_code); toast('Code copied') } catch (_) { toast('Code: ' + P().invite_code) } }
    else if (x === 'rename') { const v = root.querySelector('#bd-rn').value.trim(); if (v) { const {error} = await sb.rpc('hub_project_admin', {p_token: token(), p_project: cur, p_action: 'rename', p_name: v}); if (error) throw error; await refresh(); toast('Renamed'); } }
    else if (x === 'saveacc') { const L = others(); const devs = eExcl.size ? L.filter(n => !eExcl.has(n)) : null; const {error} = await sb.rpc('hub_set_project_devices', {p_token: token(), p_project: cur, p_devices: devs}); if (error) throw error; await refresh(); toast('Saved'); }
    else if (x === 'leave') { if (!confirm2(b, 'Tap again to leave')) return; await sb.from('hub_members').delete().eq('project_id', cur).eq('user_id', me); cur = null; tab = 'board'; await refresh(); }
    else if (x === 'delproj') { if (!confirm2(b, 'Tap again — deletes everything')) return; const {error} = await sb.rpc('hub_project_admin', {p_token: token(), p_project: cur, p_action: 'delete'}); if (error) throw error; cur = null; tab = 'board'; await refresh(); }
  }

  function syncTags() { root.querySelectorAll('.tagbar').forEach(bar => { const v = root.querySelector('#' + bar.dataset.for)?.value || ''; bar.querySelectorAll('.tg[data-tag]').forEach(b => b.setAttribute('aria-pressed', hasTag(v, b.dataset.tag))); }); }
  let qT = null;
  root.addEventListener('change', e => { if (e.target.id === 'bd-qu') { qUser = e.target.value; render(); } });
  root.addEventListener('input', e => { if (e.target.id === 'bd-q') { q = e.target.value; clearTimeout(qT); qT = setTimeout(render, 250); } if (e.target.id === 'bd-b' || e.target.id === 'bd-r') syncTags(); });

  /* ---------- live ---------- */
  function live() {
    if (chan) sb.removeChannel(chan);
    const h = pl => { const r = pl.new && Object.keys(pl.new).length ? pl.new : pl.old || {}; if (pl.eventType === 'INSERT' && r.user_id && r.user_id !== me && (pl.table === 'hub_posts' || pl.table === 'hub_replies')) { const pr = projects.find(q => q.id === r.project_id); toast((pl.table === 'hub_posts' ? 'New post' : 'New reply') + (pr ? ' in ' + pr.name : '')); } soon(); };
    chan = sb.channel('boards-' + me);
    ['hub_posts', 'hub_replies', 'hub_members'].forEach(t => chan.on('postgres_changes', {event: '*', schema: 'public', table: t}, h));
    chan.subscribe();
  }

  const ping = () => { if (token()) sb.rpc('hub_ping', {p_token: token()}).then(() => {}); };
  (async () => { try { ping(); await upsertProfile(); await refresh(); live(); } catch (e) { root.innerHTML = `<div class="empty">Boards couldn't load: ${esc(e.message)}. Has the board setup SQL been run?</div>`; } })();
  document.addEventListener('visibilitychange', () => { if (!document.hidden) { ping(); soon(); } });
  const poll = setInterval(() => { if (!document.hidden && root.isConnected && !root.closest('[hidden]')) soon(); }, 20000);
  return {projects: () => projects, current: () => cur, postTo, refresh, destroy() { clearInterval(poll); if (chan) sb.removeChannel(chan); root.innerHTML = ''; }};
}
