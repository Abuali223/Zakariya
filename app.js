// Arab Tili — Gibrid PWA + Supabase (vanilla JS)
const $ = (s, c=document)=>c.querySelector(s);
const $$ = (s, c=document)=>Array.from(c.querySelectorAll(s));

// ---- Theme ----
const THEME_KEY = 'theme';
(function initTheme(){
  const t = localStorage.getItem(THEME_KEY);
  if(t==='dark') document.documentElement.setAttribute('data-theme', 'dark');
  $('#btn-theme')?.addEventListener('click', ()=>{
    const cur = document.documentElement.getAttribute('data-theme');
    const next = cur==='dark' ? '' : 'dark';
    if(next) document.documentElement.setAttribute('data-theme', next);
    else document.documentElement.removeAttribute('data-theme');
    localStorage.setItem(THEME_KEY, next || '');
  });
})();

// ---- Router (hash) ----
const routes = {
  dash: renderDash,
  lessons: renderLessons,
  practice: renderPractice,
  tests: renderTests,
  tutor: renderTutor,
  parent: renderParent,
  profile: renderProfile
};
function navigate(){
  const hash = (location.hash||'#dash').slice(1);
  $$('.nav a').forEach(a=>a.classList.toggle('active', a.getAttribute('href')==='#'+hash));
  (routes[hash]||renderDash)();
}
window.addEventListener('hashchange', navigate);

// ---- IndexedDB (tiny wrapper) ----
let dbp = null;
function dbOpen(){
  if(dbp) return dbp;
  dbp = new Promise((resolve,reject)=>{
    const req = indexedDB.open('arab_gibrid_db', 1);
    req.onupgradeneeded = ()=>{
      const db = req.result;
      if(!db.objectStoreNames.contains('progress')) db.createObjectStore('progress', {keyPath:['user','item']});
      if(!db.objectStoreNames.contains('meta')) db.createObjectStore('meta', {keyPath:'k'});
    };
    req.onsuccess = ()=>resolve(req.result);
    req.onerror = ()=>reject(req.error);
  });
  return dbp;
}
function dbGet(store, key){ return dbOpen().then(db=>new Promise((res,rej)=>{ const tx=db.transaction(store,'readonly'); const r=tx.objectStore(store).get(key); r.onsuccess=()=>res(r.result); r.onerror=()=>rej(r.error);})); }
function dbPut(store, val){ return dbOpen().then(db=>new Promise((res,rej)=>{ const tx=db.transaction(store,'readwrite'); tx.objectStore(store).put(val); tx.oncomplete=()=>res(true); tx.onerror=()=>rej(tx.error);})); }
function dbAll(store){ return dbOpen().then(db=>new Promise((res,rej)=>{ const tx=db.transaction(store,'readonly'); const st=tx.objectStore(store); const out=[]; const c=st.openCursor(); c.onsuccess=()=>{ const cur=c.result; if(cur){ out.push(cur.value); cur.continue(); } else res(out); }; c.onerror=()=>rej(c.error);})); }

// ---- Content loader ----
const PACKS = [
  'colors','animals','family','body','numbers','verbs','basics','objects'
];
let CONTENT = {packs:{}};
async function loadContent(){
  for(const p of PACKS){
    const resp = await fetch(`./content/${p}.json`);
    CONTENT.packs[p] = await resp.json();
  }
}

// ---- SRS helpers ----
function key(item){ return `${item.ar}|${item.uz}`; }
function todayISO(){ return new Date().toISOString().slice(0,10); }
async function srsGet(user, item){
  const rec = await dbGet('progress', [user, key(item)]);
  return rec || { user, item: key(item), correct:0, wrong:0, ef:2.5, interval:0, due: Date.now(), updated_at: Date.now(), rev:0 };
}
async function srsUpdate(user, item, grade){ // 0..5
  const rec = await srsGet(user,item);
  const q = Math.max(0, Math.min(5, grade));
  if(q<3){ rec.interval=1; rec.ef=Math.max(1.3, rec.ef-0.2); rec.wrong++; }
  else { if(rec.interval===0) rec.interval=1; else if(rec.interval===1) rec.interval=2; else rec.interval=Math.round(rec.interval*rec.ef); rec.correct++; rec.ef=Math.max(1.3, rec.ef+(0.1-(5-q)*(0.08+(5-q)*0.02))); }
  rec.due = Date.now()+rec.interval*24*60*60*1000;
  rec.updated_at = Date.now(); rec.rev += 1;
  await dbPut('progress', rec);
  enqueue([{op:'upsert_progress', row:rec}]); // queue for sync
}

// ---- Offline Queue + Sync ----
const QKEY = 'sync_queue';
function enqueue(rows){
  const q = JSON.parse(localStorage.getItem(QKEY) || '[]');
  q.push(...rows); localStorage.setItem(QKEY, JSON.stringify(q));
}
async function flushQueue(){
  const q = JSON.parse(localStorage.getItem(QKEY) || '[]');
  if(!q.length || !window.supabase) return;
  try{
    const rows = q.filter(x=>x.op==='upsert_progress').map(x=>x.row);
    if(!rows.length) return;
    // Upsert to Supabase
    const { data, error } = await supabase.from('progress').upsert(rows, { onConflict: 'user,item' });
    if(!error){ localStorage.setItem(QKEY, '[]'); console.log('Synced', rows.length); }
  }catch(e){ console.warn('Sync failed', e); }
}
window.addEventListener('online', flushQueue);
setInterval(flushQueue, 10000);
$('#btn-sync')?.addEventListener('click', flushQueue);

// ---- Auth (optional) ----
let supabase = null; let currentUser = 'local';
function hasConfig(){ return (window.SUPABASE_URL && window.SUPABASE_ANON_KEY); }
async function initSupabase(){
  if(!hasConfig()){ console.log('Supabase config.js topilmadi — lokal rejim.'); return; }
  supabase = window.supabase.createClient(window.SUPABASE_URL, window.SUPABASE_ANON_KEY);
  const { data: { user } } = await supabase.auth.getUser();
  if(user){ currentUser = user.id; } else currentUser = 'local';
  supabase.auth.onAuthStateChange((_evt, sess)=>{ currentUser = (sess && sess.user)? sess.user.id : 'local'; });
  $('#btn-auth')?.addEventListener('click', async()=>{
    const email = prompt('Email kiriting (magic link yuboriladi):');
    if(!email) return;
    const { error } = await supabase.auth.signInWithOtp({ email });
    alert(error? ('Xatolik: '+error.message) : 'Emailga havola yuborildi.');
  });
}

// ---- Pages ----
function renderDash(){
  const total = Object.values(CONTENT.packs).reduce((n,p)=>n+p.items.length,0);
  $('#page').innerHTML = `
    <div class="row space">
      <div><h2>Dashboard</h2><div class="muted">Bugun tavsiya: adaptiv 12 ta mashq</div></div>
      <div style="min-width:260px">
        <div class="muted">Umumiy progress</div>
        <div class="progress"><div id="gprog"></div></div>
      </div>
    </div>
    <div class="row" style="margin-top:12px; gap:12px; flex-wrap:wrap">
      <div class="card"><div class="muted">⭐ Ball</div><h3 id="stat-points">0</h3></div>
      <div class="card"><div class="muted">🔥 Seriya</div><h3 id="stat-streak">0</h3></div>
      <div class="card"><div class="muted">🎯 Jami element</div><h3>${total}</h3></div>
    </div>
  `;
  updateGlobal();
}
function updateGlobal(){
  dbAll('progress').then(rows=>{
    const mastered = rows.filter(r=>r.correct>=3).length;
    const total = Object.values(CONTENT.packs).reduce((n,p)=>n+p.items.length,0);
    const percent = Math.round((mastered/Math.max(1,total))*100);
    $('#gprog').style.width = percent+'%';
    $('#stat-points').textContent = rows.reduce((s,r)=>s + r.correct*3 + r.wrong*1, 0);
    // streak (naive): suppose we touched today
    $('#stat-streak').textContent = '—';
  });
}

function renderLessons(){
  const cards = Object.entries(CONTENT.packs).map(([key, pack])=>`
    <div class="card">
      <div class="rtl" style="font-size:34px">${pack.preview||'ا'}</div>
      <b>${pack.title}</b>
      <div class="muted">${pack.items.length} ta so‘z</div>
      <div class="row" style="margin-top:8px"><button class="btn" onclick="openPack('${key}')">Ko‘rish</button></div>
    </div>`).join('');
  $('#page').innerHTML = `<h2>Darslar</h2><div class="grid6">${cards}</div>`;
}
window.openPack = function(key){
  const pack = CONTENT.packs[key];
  const items = pack.items.map(i=>`
    <div class="card flash">
      <div class="rtl">${i.ar}</div>
      <div class="muted">${i.tr||''}</div>
      <b>${i.uz}</b>
      <div class="row" style="justify-content:center; margin-top:8px">
        <button class="btn" onclick="markHard('${key}', '${i.ar.replace(/'/g,'\\\'')}', '${i.uz.replace(/'/g,'\\\'')}')">Qiyin</button>
        <button class="btn" onclick="markGood('${key}', '${i.ar.replace(/'/g,'\\\'')}', '${i.uz.replace(/'/g,'\\\'')}')">Yodladim</button>
      </div>
    </div>
  `).join('');
  $('#page').innerHTML = `<h2>${pack.title}</h2><div class="grid6">${items}</div>`;
};

window.markHard = async function(pack, ar, uz){
  await srsUpdate(currentUser, {ar,uz}, 2); alert('Belgilandi: Qiyin'); updateGlobal();
};
window.markGood = async function(pack, ar, uz){
  await srsUpdate(currentUser, {ar,uz}, 5); alert('Ajoyib!'); updateGlobal();
};

function renderPractice(){
  // very simple: merge all items and pick 12
  const all = Object.values(CONTENT.packs).flatMap(p=>p.items);
  const pick = all.sort(()=>Math.random()-0.5).slice(0,12);
  const html = pick.map(i=>`
    <div class="card flash">
      <div class="rtl">${i.ar}</div><div class="muted">${i.tr||''}</div><b>${i.uz}</b>
      <div class="row" style="justify-content:center; margin-top:8px">
        <button class="btn" onclick="markHard('any','${i.ar}','${i.uz}')">Qiyin</button>
        <button class="btn" onclick="markGood('any','${i.ar}','${i.uz}')">Yodladim</button>
      </div>
    </div>`).join('');
  $('#page').innerHTML = `<h2>Mashq (SRS)</h2><div class="grid6">${html}</div>`;
}

function renderTests(){
  $('#page').innerHTML = `
    <h2>Testlar</h2>
    <div class="card">
      <div class="row space">
        <div><b>Aralash — 10 savol</b><div class="muted">80% o‘tish balli</div></div>
        <button class="btn primary" onclick="startQuiz()">Boshlash</button>
      </div>
    </div>
    <div id="quiz" style="margin-top:10px"></div>`;
}
window.startQuiz = function(){
  const all = Object.values(CONTENT.packs).flatMap(p=>p.items);
  const pool = all.sort(()=>Math.random()-0.5).slice(0,10);
  const div = $('#quiz'); div.innerHTML='';
  let idx=0, score=0;
  ask();
  function ask(){
    const it = pool[idx];
    const opts = [it.uz];
    while(opts.length<4){
      const r = all[Math.floor(Math.random()*all.length)].uz;
      if(!opts.includes(r)) opts.push(r);
    }
    opts.sort(()=>Math.random()-0.5);
    div.innerHTML = `
      <div class="card">
        <div><b>Savol ${idx+1}/10:</b> “${it.ar}” ning o‘zbekcha ma’nosi qaysi?</div>
        <div class="row" style="flex-direction:column; align-items:stretch; gap:8px; margin-top:8px">
          ${opts.map(o=>`<button class="btn" data-o="${o}">${o}</button>`).join('')}
        </div>
      </div>`;
    $$('#quiz .btn').forEach(b=>b.addEventListener('click', async()=>{
      const o = b.getAttribute('data-o');
      if(o===it.uz){ b.classList.add('primary'); score++; await srsUpdate(currentUser, it, 5); }
      else { b.style.borderColor = 'var(--bad)'; await srsUpdate(currentUser, it, 2); }
      idx++; if(idx<10) ask(); else div.innerHTML = `<div class="card"><b>Natija:</b> ${score}/10</div>`;
      updateGlobal();
    }));
  }
};

function renderTutor(){
  $('#page').innerHTML = `
    <h2>AI Tutor</h2>
    <div class="card">
      <div class="row" style="gap:6px; margin-bottom:8px">
        <select id="t-level"><option>A1</option><option>A2</option><option>B1</option></select>
        <select id="t-topic">${PACKS.map(p=>`<option>${p}</option>`).join('')}</select>
        <span class="pill">Arabcha ↔ O‘zbekcha</span>
      </div>
      <div style="display:grid; grid-template-rows:1fr auto; height:320px; border:1px solid var(--border); border-radius:12px; overflow:hidden">
        <div id="chatlog" style="padding:10px; overflow:auto; background:#131a33"></div>
        <div class="row" style="padding:10px; background:#0f152a">
          <input id="t-input" placeholder="Savolingiz..." style="flex:1"/>
          <button class="btn primary" id="t-send">Yuborish</button>
        </div>
      </div>
      <div class="muted" style="margin-top:6px">Eslatma: haqiqiy javoblar uchun serverdagi SI endpoint talab qilinadi.</div>
    </div>`;
  $('#t-send').addEventListener('click', async()=>{
    const q = $('#t-input').value.trim(); if(!q) return;
    const log = $('#chatlog'); log.innerHTML += `<div class="card" style="margin:6px">${q}</div>`;
    $('#t-input').value='';
    if(!supabase){ log.innerHTML += `<div class="card" style="margin:6px">Demo: SI ulanmagan.</div>`; return; }
    // Call your SI function (you must deploy it on Supabase edge)
    const { data, error } = await supabase.functions.invoke('tutor', { body: { q, level: $('#t-level').value, topic: $('#t-topic').value } });
    log.innerHTML += `<div class="card" style="margin:6px">${error? ('Xato: '+error.message) : (data?.answer||'Javob ololmadi')}</div>`;
  });
}

function renderParent(){
  $('#page').innerHTML = `
    <h2>Ota-ona paneli</h2>
    <div class="row" style="gap:12px; flex-wrap:wrap">
      <div class="card"><div class="muted">Bugungi vaqt</div><b id="p-min">0</b> daqiqa</div>
      <div class="card"><div class="muted">Oxirgi faol kun</div><b id="p-day">—</b></div>
      <div class="card"><div class="muted">Yodlangan so‘z</div><b id="p-mst">0</b></div>
      <div class="card"><div class="muted">Kutilayotgan mashq</div><b id="p-due">0</b></div>
    </div>`;
  dbAll('progress').then(rows=>{
    $('#p-mst').textContent = rows.filter(r=>r.correct>=3).length;
    $('#p-due').textContent = rows.filter(r=>r.due<=Date.now()).length;
    $('#p-day').textContent = todayISO();
    $('#p-min').textContent = Math.floor(rows.length/3);
  });
}

function renderProfile(){
  $('#page').innerHTML = `
    <h2>Profil</h2>
    <div class="row">
      <input id="nickname" placeholder="Ism (nik)" />
      <button class="btn" id="save">Saqlash</button>
    </div>
    <p class="muted">Login yoqsangiz, progressingiz qurilmalar o‘rtasida sinxron bo‘ladi.</p>`;
  $('#save').addEventListener('click', ()=> alert('Saqlash demo.'));
}

// ---- Install (PWA) ----
let deferredPrompt=null;
window.addEventListener('beforeinstallprompt', e=>{ e.preventDefault(); deferredPrompt=e; $('#btn-install').hidden=false; });
$('#btn-install')?.addEventListener('click', async()=>{ if(!deferredPrompt) return; deferredPrompt.prompt(); await deferredPrompt.userChoice; deferredPrompt=null; $('#btn-install').hidden=true; });

// ---- Init ----
(async function init(){
  try{ await loadContent(); }catch(e){ console.error('Kontent yuklanmadi', e); }
  await initSupabase();
  navigate(); // initial
  // default page
  if(!location.hash) location.hash = '#dash';
})();
