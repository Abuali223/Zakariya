/**
 * Iqror — Yuz terminali → davomat KO'PRIGI (camera-bridge)
 * -------------------------------------------------------------------
 * Kirish qismidagi yuz tanaydigan terminal (Hikvision / ZKTeco / Dahua)
 * har bir tanilgan shaxs uchun voqea (event) yuboradi. Bu xizmat o'sha
 * voqeani qabul qilib, uni o'quvchi/xodim bilan bog'laydi va Firestore'ga
 * yozadi: `checkins` jurnali + o'quvchi uchun davomat (Keldi/Kech) va
 * `students.attendance` foizi avtomatik yangilanadi.
 *
 * Firebase Admin SDK (xizmat hisobi) orqali yozadi — Firestore qoidalarini
 * chetlab o'tadi, shuning uchun bu skript ISHONCHLI serverda ishlashi kerak.
 *
 * Ishga tushirish:
 *   npm install
 *   cp config.example.json config.json   # va to'ldiring
 *   node index.cjs                        # webhook serveri (terminal shu yerga yuboradi)
 *   node index.cjs mark-absent 2026-09-01 # kun oxirida kelmaganlarni «Yo'q» qilish
 *
 * Batafsil: README.md
 */
const fs = require('fs');
const http = require('http');
const path = require('path');
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const CFG = JSON.parse(fs.readFileSync(path.join(__dirname, process.env.IQROR_CONFIG || 'config.json'), 'utf8'));
initializeApp({ credential: cert(require(path.resolve(__dirname, CFG.serviceAccount))) });
const db = getFirestore();

const START = CFG.attendanceStart || '08:30';       // dars boshlanishi (HH:MM, mahalliy vaqt)
const GRACE = Number(CFG.lateGraceMinutes || 0);     // shu daqiqagacha kechikish «Keldi» hisoblanadi
const TZ_NOTE = 'Terminal mahalliy vaqtni yuborishi kutiladi';

const pad = n => String(n).padStart(2, '0');
const minutesOf = hhmm => { const m = /(\d{1,2}):(\d{2})/.exec(hhmm || ''); return m ? (+m[1]) * 60 + (+m[2]) : null; };

// Voqeadan sana/vaqtni ajratadi. ISO ("2026-09-01T08:05:00") yoki "2026-09-01 08:05:00".
function partsFromTs(ts) {
  const s = String(ts || '');
  const m = /(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})/.exec(s);
  if (!m) return null;
  return { day: `${m[1]}-${m[2]}-${m[3]}`, ym: `${m[1]}-${m[2]}`, dd: m[3], hhmm: `${m[4]}:${m[5]}`, iso: `${m[1]}-${m[2]}-${m[3]}T${m[4]}:${m[5]}:00` };
}

// Turli terminallar turli maydon nomlari yuboradi — keng tarqalganlarini qo'llab-quvvatlaymiz.
function extractEvent(body) {
  const b = body || {};
  const cameraId = String(
    b.cameraId ?? b.personId ?? b.PersonID ?? b.employeeNoString ?? b.employeeNo ?? b.userId ?? b.pin ?? b.UserID ?? b.card ?? ''
  ).trim();
  const time = b.time ?? b.ts ?? b.dateTime ?? b.eventTime ?? b.strTime ?? b.happenTime ?? '';
  const deviceId = String(b.deviceId ?? b.deviceName ?? b.sn ?? b.SN ?? CFG.deviceId ?? 'terminal');
  const direction = String(b.direction ?? b.inOut ?? 'in');
  return { cameraId, time, deviceId, direction };
}

function classKeyOf(s) { return `${s.lang || 'uz'}-${Number(s.grade) || 0}-${s.classLetter || s.track || '-'}`; }

async function resolvePerson(cameraId) {
  if (!cameraId) return null;
  let q = await db.collection('students').where('cameraId', '==', cameraId).limit(1).get();
  if (!q.empty) { const d = q.docs[0]; return { personType: 'student', id: d.id, data: d.data() }; }
  q = await db.collection('teachers').where('cameraId', '==', cameraId).limit(1).get();
  if (!q.empty) { const d = q.docs[0]; return { personType: 'staff', id: d.id, data: d.data() }; }
  return null;
}

// O'quvchi davomatini belgilaydi (Keldi/Kech) — mavjud «Keldi»ni pasaytirmaydi.
async function markAttendance(sid, classKey, p, status) {
  const ref = db.collection('attendance').doc(`${sid}__${p.ym}`);
  await db.runTransaction(async tx => {
    const snap = await tx.get(ref);
    const days = (snap.exists && snap.data().days) || {};
    if (days[p.dd] === 'present') return;                 // ertalabki «Keldi» ustidan yozmaymiz
    const merged = Object.assign({}, days, { [p.dd]: status });
    tx.set(ref, { studentId: sid, classKey, month: p.ym, days: merged }, { merge: true });
  });
}

// students.attendance foizini qayta hisoblaydi (kabinet formulasi bilan bir xil).
async function recomputeStudentPct(sid) {
  const snap = await db.collection('attendance').where('studentId', '==', sid).get();
  let present = 0, late = 0, total = 0;
  snap.forEach(s => { const days = s.data().days || {}; Object.values(days).forEach(st => { total++; if (st === 'present') present++; else if (st === 'late') late++; }); });
  if (total) await db.collection('students').doc(sid).set({ attendance: Math.round((present + late) / total * 100) }, { merge: true });
}

/** Bitta tanilish voqeasini qayta ishlaydi. Test qilinadigan yadro. */
async function handleEvent(raw) {
  const ev = extractEvent(raw);
  if (!ev.cameraId) return { ok: false, reason: 'no-cameraId' };
  const p = partsFromTs(ev.time) || partsFromTs(new Date().toISOString());
  const person = await resolvePerson(ev.cameraId);
  const status = person && person.personType === 'student'
    ? (minutesOf(p.hhmm) <= minutesOf(START) + GRACE ? 'present' : 'late')
    : null;

  // Xom voqeani jurnalga yozamiz (tanilmagan bo'lsa ham — sozlash uchun foydali)
  const checkin = {
    day: p.day, ts: p.iso, cameraId: ev.cameraId, deviceId: ev.deviceId, direction: ev.direction,
    source: 'camera', createdAt: FieldValue.serverTimestamp(),
    personType: person ? person.personType : 'unknown',
    refId: person ? person.id : null,
    name: person ? (person.data.name || '') : '',
    status: status || null
  };
  await db.collection('checkins').add(checkin);
  if (!person) return { ok: false, reason: 'unknown-cameraId', cameraId: ev.cameraId };

  if (person.personType === 'student') {
    const ck = classKeyOf(person.data);
    await markAttendance(person.id, ck, p, status);
    await recomputeStudentPct(person.id);
  }
  return { ok: true, personType: person.personType, id: person.id, name: checkin.name, status, day: p.day, time: p.hhmm };
}

/** Kun oxirida: o'sha kunda kelmagan o'quvchilarni «Yo'q» qiladi. */
async function markAbsent(day) {
  const p = partsFromTs(`${day}T00:00`); if (!p) throw new Error('Sana formati: YYYY-MM-DD');
  const students = await db.collection('students').get();
  let n = 0;
  for (const doc of students.docs) {
    const s = doc.data(), sid = doc.id;
    const attRef = db.collection('attendance').doc(`${sid}__${p.ym}`);
    const attSnap = await attRef.get();
    const cur = (attSnap.exists && (attSnap.data().days || {})[p.dd]) || '';
    if (cur === 'present' || cur === 'late') continue;      // allaqachon kelgan
    await attRef.set({ studentId: sid, classKey: classKeyOf(s), month: p.ym, days: { [p.dd]: 'absent' } }, { merge: true });
    await recomputeStudentPct(sid); n++;
  }
  return n;
}

// ---- CLI / server (faqat to'g'ridan-to'g'ri ishga tushirilganda; require() da emas) ----
const mode = require.main === module ? process.argv[2] : '__module__';
if (mode === '__module__') {
  // require() sifatida chaqirildi — server/CLI ishlamaydi, faqat funksiyalar eksport qilinadi
} else if (mode === 'mark-absent') {
  const day = process.argv[3] || new Date().toISOString().slice(0, 10);
  markAbsent(day).then(n => { console.log(`«Yo'q» belgilandi: ${n} o'quvchi (${day})`); process.exit(0); })
    .catch(e => { console.error('Xatolik:', e.message); process.exit(1); });
} else if (mode === 'test-event') {
  // node index.cjs test-event <cameraId> <YYYY-MM-DDTHH:MM>
  handleEvent({ cameraId: process.argv[3], time: process.argv[4] })
    .then(r => { console.log(JSON.stringify(r)); process.exit(0); }).catch(e => { console.error(e); process.exit(1); });
} else {
  // Webhook serveri — terminal tanilish voqealarini shu yerga POST qiladi.
  const PORT = Number(CFG.port || 8787);
  const TOKEN = CFG.webhookToken || '';
  const server = http.createServer((req, res) => {
    if (req.method === 'GET' && req.url === '/health') { res.writeHead(200); return res.end('ok'); }
    if (req.method !== 'POST') { res.writeHead(405); return res.end('POST kutiladi'); }
    if (TOKEN) { const t = req.headers['x-iqror-token'] || (new URL(req.url, 'http://x')).searchParams.get('token'); if (t !== TOKEN) { res.writeHead(401); return res.end('token noto\'g\'ri'); } }
    let data = ''; req.on('data', c => { data += c; if (data.length > 1e6) req.destroy(); });
    req.on('end', async () => {
      let body = {}; try { body = data ? JSON.parse(data) : {}; } catch (e) { try { body = Object.fromEntries(new URLSearchParams(data)); } catch (_) { body = {}; } }
      try { const r = await handleEvent(body); res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(r)); if (r.ok) console.log(`✓ ${r.name || r.id} · ${r.status || r.personType} · ${r.time || ''}`); else console.log(`… ${r.reason}: ${r.cameraId || ''}`); }
      catch (e) { console.error('handleEvent xato:', e.message); res.writeHead(500); res.end('xatolik'); }
    });
  });
  server.listen(PORT, () => console.log(`Iqror camera-bridge tinglayapti :${PORT}  (start=${START}, +${GRACE}daq · ${TZ_NOTE})`));
}

module.exports = { handleEvent, markAbsent, extractEvent, partsFromTs, classKeyOf };
