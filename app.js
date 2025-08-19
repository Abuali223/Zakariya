const $ = s => document.querySelector(s), $$ = s => [...document.querySelectorAll(s)];

/* ===== 1) Kontent (fetch YO‘Q) ===== */
const CONTENT = { packs: {
  colors:{title:"Ranglar",items:[
    {ar:"أَحْمَر",tr:"aḥmar",uz:"qizil"},
    {ar:"أَزْرَق",tr:"azraq",uz:"ko‘k"},
    {ar:"أَخْضَر",tr:"akhḍar",uz:"yashil"},
    {ar:"أَصْفَر",tr:"aṣfar",uz:"sariq"},
    {ar:"بُنِّيّ",tr:"bunnī",uz:"jigarrang"},
    {ar:"بَنَفْسَجِيّ",tr:"banafsajī",uz:"siyohrang"},
    {ar:"وَرْدِيّ",tr:"wardī",uz:"pushti"}
  ]},
  animals:{title:"Hayvonlar",items:[
    {ar:"قِطّ",tr:"qiṭṭ",uz:"mushuk"},
    {ar:"كَلْب",tr:"kalb",uz:"it"},
    {ar:"أَسَد",tr:"asad",uz:"sher"},
    {ar:"فِيل",tr:"fīl",uz:"fil"},
    {ar:"جَمَل",tr:"jamal",uz:"tuya"}
  ]},
  family:{title:"Oila",items:[
    {ar:"أُمّ",tr:"umm",uz:"ona"},
    {ar:"أَب",tr:"ab",uz:"ota"},
    {ar:"بِنْت",tr:"bint",uz:"qiz"},
    {ar:"اِبْن",tr:"ibn",uz:"o‘g‘il"}
  ]},
  body:{title:"Tana a’zolari",items:[
    {ar:"عَيْن",tr:"‘ayn",uz:"ko‘z"},
    {ar:"أُذُن",tr:"udhun",uz:"quloq"},
    {ar:"فَم",tr:"fam",uz:"og‘iz"},
    {ar:"يَد",tr:"yad",uz:"qo‘l"}
  ]},
  numbers:{title:"Sonlar (1–6)",items:[
    {ar:"وَاحِد",tr:"wāḥid",uz:"bir"},
    {ar:"اِثْنَان",tr:"ithnān",uz:"ikki"},
    {ar:"ثَلَاثَة",tr:"thalātha",uz:"uch"},
    {ar:"أَرْبَعَة",tr:"arba‘a",uz:"to‘rt"},
    {ar:"خَمْسَة",tr:"khamsa",uz:"besh"},
    {ar:"سِتَّة",tr:"sitta",uz:"olti"}
  ]},
  verbs:{title:"Fe’llar",items:[
    {ar:"قَرَأَ",tr:"qara’a",uz:"o‘qidi"},
    {ar:"كَتَبَ",tr:"kataba",uz:"yozdi"},
    {ar:"ذَهَبَ",tr:"dhahaba",uz:"bordi"},
    {ar:"جَاءَ",tr:"jā’a",uz:"keldi"}
  ]},
  basics:{title:"Iboralar",items:[
    {ar:"مَرْحَبًا",tr:"marḥaban",uz:"salom"},
    {ar:"شُكْرًا",tr:"shukran",uz:"rahmat"},
    {ar:"نَعَمْ",tr:"na‘am",uz:"ha"},
    {ar:"لَا",tr:"lā",uz:"yo‘q"}
  ]},
  objects:{title:"Buyumlar",items:[
    {ar:"كِتَاب",tr:"kitāb",uz:"kitob"},
    {ar:"قَلَم",tr:"qalam",uz:"ruchka"},
    {ar:"بَاب",tr:"bāb",uz:"eshik"},
    {ar:"مَاء",tr:"mā’",uz:"suv"}
  ]}
}};
const PACKS = Object.keys(CONTENT.packs);

/* ===== 2) Router ===== */
const routes = { dash, lessons, practice, tests, tutor, parent, profile };
function nav(){
  const h = (location.hash||'#dash').slice(1);
  $$('.nav a').forEach(a=>a.classList.toggle('active', a.getAttribute('href')==='#'+h));
  (routes[h]||dash)();
}
addEventListener('hashchange', nav);

/* ===== 3) IndexedDB (progress) ===== */
let dbp=null;
function dbOpen(){
  if(dbp) return dbp;
  dbp = new Promise((resolve,reject)=>{
    const req = indexedDB.open('arab_db',1);
    req.onupgradeneeded = ()=>{ const db=req.result;
      if(!db.objectStoreNames.contains('progress')) db.createObjectStore('progress',{keyPath:['user','item']});
    };
    req.onsuccess = ()=>resolve(req.result);
    req.onerror  = ()=>reject(req.error);
  });
  return dbp;
}
function dbPut(v){
  return dbOpen().then(db=>new Promise((res,rej)=>{
    const tx=db.transaction('progress','readwrite');
    tx.objectStore('progress').put(v);
    tx.oncomplete=()=>res(true);
    tx.onerror=()=>rej(tx.error);
  }));
}
function key(i){ return i.ar+'|'+i.uz }
async function srsUpdate(user,item,grade){
  const now=Date.now();
  const rec={user,item:key(item),correct:grade>=3?1:0,wrong:grade<3?1:0,ef:2.5,interval:1,due:now,updated_at:now,rev:1};
  await dbPut(rec);
  enqueue([{op:'upsert_progress',row:rec}]);
  alert(grade>=3?'Ajoyib!':'Qiyin belgilandi');
}

/* ===== 4) Offline Queue + (ixtiyoriy) Supabase sync ===== */
const QKEY='sync_q';
function enqueue(rows){
  const q=JSON.parse(localStorage.getItem(QKEY)||'[]');
  q.push(...rows); localStorage.setItem(QKEY,JSON.stringify(q));
}
let supabase=null,currentUser='local';
function hasCfg(){ return (window.SUPABASE_URL && window.SUPABASE_ANON_KEY) }
async function initSupabase(){
  if(!hasCfg()) return;
  supabase = window.supabase.createClient(window.SUPABASE_URL,window.SUPABASE_ANON_KEY);
  const { data:{ user } } = await supabase.auth.getUser();
  currentUser = user ? user.id : 'local';
  $('#btn-auth').addEventListener('click', async ()=>{
    const email = prompt('Email kiriting:'); if(!email) return;
    const { error } = await supabase.auth.signInWithOtp({ email });
    alert(error?('Xato: '+error.message):'Emailga havola yuborildi');
  });
}
async function flush(){
  const q=JSON.parse(localStorage.getItem(QKEY)||'[]');
  if(!q.length || !supabase) return;
  const rows=q.filter(x=>x.op==='upsert_progress').map(x=>x.row);
  const { error } = await supabase.from('progress').upsert(rows,{ onConflict:'user,item' });
  if(!error) localStorage.setItem(QKEY,'[]');
}
$('#btn-sync')?.addEventListener('click', flush);
setInterval(flush, 10000);
addEventListener('online', flush);

/* ===== 5) Sahifalar ===== */
function dash(){
  const total = Object.values(CONTENT.packs).reduce((n,p)=>n+p.items.length,0);
  $('#page').innerHTML = `
    <h2>Dashboard</h2>
    <div class="progress"><div id="gprog" style="width:0%"></div></div>
    <p>Jami element: ${total}</p>`;
}
function lessons(){
  const cards = Object.entries(CONTENT.packs).map(([k,p])=>`
    <div class="card">
      <b>${p.title}</b>
      <div>${p.items.length} so‘z</div>
      <button class="btn" onclick="openPack('${k}')">Ko‘rish</button>
    </div>`).join('');
  $('#page').innerHTML = `<h2>Darslar</h2><div class="grid6">${cards}</div>`;
}
window.openPack = function(k){
  const p = CONTENT.packs[k];
  const html = p.items.map(i=>`
    <div class="card flash">
      <div class="rtl">${i.ar}</div>
      <div>${i.tr||''}</div>
      <b>${i.uz}</b>
      <div style="margin-top:8px">
        <button class="btn" onclick='markHard(${JSON.stringify(i)})'>Qiyin</button>
        <button class="btn" onclick='markGood(${JSON.stringify(i)})'>Yodladim</button>
      </div>
    </div>`).join('');
  $('#page').innerHTML = `<h2>${p.title}</h2><div class="grid6">${html}</div>`;
};
window.markHard = i => srsUpdate(currentUser, i, 2);
window.markGood = i => srsUpdate(currentUser, i, 5);

function practice(){
  const all = Object.values(CONTENT.packs).flatMap(p=>p.items).sort(()=>Math.random()-.5).slice(0,12);
  const html = all.map(i=>`
    <div class="card flash">
      <div class="rtl">${i.ar}</div><div>${i.tr||''}</div><b>${i.uz}</b>
      <div style="margin-top:8px">
        <button class="btn" onclick='markHard(${JSON.stringify(i)})'>Qiyin</button>
        <button class="btn" onclick='markGood(${JSON.stringify(i)})'>Yodladim</button>
      </div>
    </div>`).join('');
  $('#page').innerHTML = `<h2>Mashq (SRS)</h2><div class="grid6">${html}</div>`;
}
function tests(){
  $('#page').innerHTML = `<h2>Testlar</h2><div class="card">Demo test: tez orada.</div>`;
}

/* ===== 6) AI Tutor (serversiz + onlayn fallback) ===== */
function tutor(){
  $('#page').innerHTML = `
    <h2>AI Tutor</h2>
    <div class="card">
      <div class="row" style="gap:6px; margin-bottom:8px">
        <select id="t-level"><option>A1</option><option>A2</option><option>B1</option></select>
        <input id="t-topic" placeholder="Mavzu (ixtiyoriy)" />
      </div>
      <div style="display:grid; grid-template-rows:1fr auto; height:320px; border:1px solid var(--border); border-radius:12px; overflow:hidden">
        <div id="chatlog" style="padding:10px; overflow:auto; background:#131a33"></div>
        <div class="row" style="padding:10px; background:#0f152a">
          <input id="t-input" placeholder="Savolingiz..." style="flex:1"/>
          <button class="btn primary" id="t-send">Yuborish</button>
        </div>
      </div>
      <p class="muted" style="margin-top:6px">Oflayn: lokal javob. Onlayn: serverdagi SI (agar config.js to‘ldirilgan).</p>
    </div>`;
  $('#t-send').addEventListener('click', async ()=>{
    const q = $('#t-input').value.trim(); if(!q) return;
    const log = $('#chatlog'); log.innerHTML += `<div class="card" style="margin:6px">${q}</div>`;
    $('#t-input').value='';
    const ctx = { level: $('#t-level').value, topic: ($('#t-topic').value||'general') };
    const { answer, source } = await window.AI.tutor(q, ctx);
    log.innerHTML += `<div class="card" style="margin:6px"><div>${answer.replace(/\n/g,'<br>')}</div><div class="muted" style="margin-top:6px">manba: ${source}</div></div>`;
  });
}

function parent(){
  $('#page').innerHTML = `
    <h2>Ota-ona paneli</h2>
    <div class="grid6">
      <div class="card"><div class="muted">Bugungi vaqt</div><b>0</b> daqiqa</div>
      <div class="card"><div class="muted">Oxirgi faol kun</div><b>${new Date().toISOString().slice(0,10)}</b></div>
      <div class="card"><div class="muted">Yodlangan so‘z</div><b>0</b></div>
      <div class="card"><div class="muted">Kutilayotgan mashq</div><b>0</b></div>
    </div>`;
}
function profile(){
  $('#page').innerHTML = `<h2>Profil</h2><div class="card">Login yoqsangiz, progress qurilmalar o‘rtasida sinxron bo‘ladi.</div>`;
}

/* ===== 7) PWA install ===== */
let deferredPrompt=null;
addEventListener('beforeinstallprompt', e=>{ e.preventDefault(); deferredPrompt=e; $('#btn-install').hidden=false; });
$('#btn-install')?.addEventListener('click', async ()=>{
  if(!deferredPrompt) return; deferredPrompt.prompt();
  await deferredPrompt.userChoice; deferredPrompt=null; $('#btn-install').hidden=true;
});

/* ===== 8) Init ===== */
(async()=>{
  await initSupabase();        // ixtiyoriy, config.js bo‘lmasa local rejim
  if(!location.hash) location.hash = '#dash';
  nav();
})();