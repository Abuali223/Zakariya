#!/usr/bin/env node
// =====================================================================
// IQROR — SINOV NUSXASI uchun SINTETIK ma'lumot (seed). Node.js 18+, npm paketlarisiz.
//
//   node seed.cjs [--today YYYY-MM-DD]   -> stdout: SQL (bitta tranzaksiya; faqat iqror_sinov bazasiga yuklanadi)
//   node seed.cjs --accounts             -> stdout: sinov hisoblari ro'yxati (JSON; parolsiz — parolni install.sh yaratadi)
//
//   Hammasi TO'QIMA: «Sinov O‘quvchi 01», «Sinov Ota 01», +998 22 000 00 01 kabi mavjud bo'lmagan raqamlar. Haqiqiy
//   o'quvchi, ota-ona, xodim, telefon yoki summa YO'Q. Bir xil sana uchun natija har doim bir xil (tasodif — urug'li).
//
//   Nima yuklanadi: 10 ta sinov hisobi (Direktor, Moliya menejeri, Buxgalter, 2 ta Kassir, G‘aznachi, HR, O‘IBDO‘, O‘qituvchi,
//   Qabulxona), 6 sinf, 60 o'quvchi, o'qituvchi va xodimlar (IQT-/IQX- ID bilan), narx jadvali va sozlamalar, joriy va
//   o'tgan oy hisob-fakturalari (to'langan / qisman / to'lanmagan), to'lovlar (naqd / Click / bank / terminal), avans,
//   biriktirilmagan Click to'lovi, xarajatlar, xodim avansi, davomat, baho, monitoring, arizalar va boshqa bo'limlar uchun
//   namuna yozuvlar — admin panelning har bir bo'limi ma'lumot bilan ochilishi uchun.
//
//   To'lovlar ilovaning O'Z funksiyasi (public.apply_payment) orqali qo'llanadi — faktura holati, avans va avans jurnali
//   haqiqiy tizimdagidek hisoblanadi («Moliya tekshiruvi» toza chiqadi).
// =====================================================================
'use strict';
const crypto = require('crypto');

// ---------------------------------------------------------------- sinov hisoblari (parollar bu yerda YO'Q)
const uuidOf = key => { const h = crypto.createHash('sha256').update('iqror-sinov:' + key).digest('hex');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-8${h.slice(17, 20)}-${h.slice(20, 32)}`; };
const DOMAIN = 'sinov.test';   // .test — hech qachon haqiqiy domen bo'lmaydi (RFC 2606)
const ACCOUNTS = [
  { key: 'direktor', label: 'Direktor', role: 'director', first: 'Sinov', last: 'Direktor' },
  { key: 'moliya', label: 'Moliya menejeri', role: 'finance_mgr', first: 'Sinov', last: 'Moliya-Menejer' },
  { key: 'buxgalter', label: 'Buxgalter', role: 'accountant', first: 'Sinov', last: 'Buxgalter' },   // kassa bo'limi (--dev) bilan: tasdiq va kunni tekshirish
  { key: 'kassir1', label: 'Kassir 1', role: 'kassir', first: 'Sinov', last: 'Kassir-Bir' },
  { key: 'kassir2', label: 'Kassir 2', role: 'kassir', first: 'Sinov', last: 'Kassir-Ikki' },
  { key: 'gaznachi', label: 'G‘aznachi', role: 'treasurer', first: 'Sinov', last: 'G‘aznachi' },
  { key: 'hr', label: 'HR', role: 'hr', first: 'Sinov', last: 'HR-Xodim' },
  { key: 'zavuch', label: 'O‘IBDO‘', role: 'zavuch', first: 'Sinov', last: 'O‘IBDO‘' },
  { key: 'oqituvchi', label: 'O‘qituvchi', role: 'teacher', first: 'Sinov', last: 'O‘qituvchi-01' },
  { key: 'qabul', label: 'Qabulxona', role: 'reception', first: 'Sinov', last: 'Qabulxona' },
].map(a => Object.assign(a, { email: `${a.key}@${DOMAIN}`, uid: uuidOf('user:' + a.key), name: `${a.first} ${a.last}` }));
const U = Object.fromEntries(ACCOUNTS.map(a => [a.key, a]));

module.exports = { ACCOUNTS };
if (require.main !== module) return;

const args = process.argv.slice(2);
if (args.includes('--accounts')) {
  process.stdout.write(JSON.stringify(ACCOUNTS.map(a => ({ label: a.label, role: a.role, email: a.email, name: a.name, uid: a.uid })), null, 1) + '\n');
  process.exit(0);
}
const argVal = n => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : null; };

// ---------------------------------------------------------------- sana (Toshkent)
const pad = (n, w) => String(n).padStart(w || 2, '0');
const TODAY = argVal('--today') || new Date(Date.now() + 5 * 3600e3).toISOString().slice(0, 10);
if (!/^\d{4}-\d{2}-\d{2}$/.test(TODAY)) { console.error('seed.cjs: --today YYYY-MM-DD'); process.exit(2); }
const [TY, TM, TD] = TODAY.split('-').map(Number);
const ymOf = (y, m) => { const d = new Date(Date.UTC(y, m - 1, 1)); return d.getUTCFullYear() + '-' + pad(d.getUTCMonth() + 1); };
const CUR = ymOf(TY, TM), PREV = ymOf(TY, TM - 1), PREV2 = ymOf(TY, TM - 2), NEXT = ymOf(TY, TM + 1);
const daysIn = ym => { const [y, m] = ym.split('-').map(Number); return new Date(Date.UTC(y, m, 0)).getUTCDate(); };
const wday = d => new Date(d + 'T00:00:00Z').getUTCDay();          // 0 = yakshanba
const dayOf = (ym, d) => `${ym}-${pad(Math.min(Math.max(1, d), daysIn(ym)))}`;
// Joriy oyda kelajak sanasi bo'lmasin: kun bugundan oshmaydi.
const curDay = d => dayOf(CUR, Math.min(d, TD));
const ts = (day, hh, mm, ss) => `${day}T${pad(hh)}:${pad(mm)}:${pad(ss || 0)}+05:00`;
const SY = TM >= 9 ? TY : TY - 1, YEAR = `${SY}-${SY + 1}`, SCHOOL_START = `${SY}-09-01`;

// ---------------------------------------------------------------- urug'li tasodif
function mulberry32(a) { return function () { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
const rnd = mulberry32(0x51407);
const ri = (a, b) => a + Math.floor(rnd() * (b - a + 1));
const pick = arr => arr[Math.floor(rnd() * arr.length)];
const hexOf = (key, n) => crypto.createHash('sha256').update('iqror-sinov:' + key).digest('hex').slice(0, n);

// ---------------------------------------------------------------- SQL yordamchilari
const q = v => v == null ? 'null' : "'" + String(v).replace(/'/g, "''") + "'";
const j = v => q(JSON.stringify(v)) + '::jsonb';
const out = [];
const sql = s => out.push(s);
function ins(table, row) {
  const cols = Object.keys(row);
  const vals = cols.map(c => { const v = row[c];
    if (v === null || v === undefined) return 'null';
    if (typeof v === 'number' || typeof v === 'boolean') return String(v);
    if (typeof v === 'object') return j(v);
    return q(v); });
  sql(`insert into public.${table}(${cols.map(c => '"' + c + '"').join(',')}) values (${vals.join(',')});`);
}

sql(`\\set ON_ERROR_STOP on
-- IQROR SINOV NUSXASI — sintetik seed (seed.cjs, sana ${TODAY}). Faqat sinov bazasiga!
begin;
do $$ begin
  if current_database() !~ '^(iqror_sinov|sinov_t_[a-z0-9_]+)$' then
    raise exception 'sinov seed: bu baza (%) sinov bazasi EMAS — seed faqat iqror_sinov ga yuklanadi', current_database();
  end if;
  if exists (select 1 from public.users) or exists (select 1 from public.students) or exists (select 1 from public.invoices) then
    raise exception 'sinov seed: baza bo''sh emas — seed faqat yangi (bo''sh) sinov bazasiga yuklanadi (bash reset.sh)';
  end if;
end $$;
-- Seed yozuvlari «O‘zgarishlar tarixi»ni to'ldirmasin; yozuvlar tizim (server) nomidan — sanalar o'zgarmay saqlanadi.
set local iqror.migrating = '1';
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
`);

// ---------------------------------------------------------------- foydalanuvchilar (sinov hisoblari)
const TEACH_CLASSES = ['uz-5-A', 'uz-8-A', 'uz-10-IT'];
for (const a of ACCOUNTS) {
  ins('users', { id: a.uid, email: a.email, name: a.name, role: a.role, verified: true, status: 'active', phone: null,
    firstName: a.first, lastName: a.last, extraRoles: [],
    assignedClasses: a.role === 'teacher' ? TEACH_CLASSES : [], assignedSubjects: a.role === 'teacher' ? ['Matematika', 'Algebra'] : [],
    homeroomClasses: a.role === 'teacher' ? ['uz-5-A'] : [],
    createdAt: ts(SCHOOL_START, 9, 0), updatedAt: ts(dayOf(PREV, 1), 9, 0) });
}

// ---------------------------------------------------------------- sinflar, narx jadvali, sozlamalar
const CLASSES = [
  { id: 'uz-1-A', grade: 1, lang: 'uz', letter: 'A', track: '' },
  { id: 'uz-3-B', grade: 3, lang: 'uz', letter: 'B', track: '' },
  { id: 'uz-5-A', grade: 5, lang: 'uz', letter: 'A', track: '' },
  { id: 'ru-6-A', grade: 6, lang: 'ru', letter: 'A', track: '' },
  { id: 'uz-8-A', grade: 8, lang: 'uz', letter: 'A', track: '' },
  { id: 'uz-10-IT', grade: 10, lang: 'uz', letter: 'IT', track: 'IT' },
];
CLASSES.forEach((c, i) => {
  ins('classes', { id: c.id, grade: c.grade, lang: c.lang, letter: c.letter, order: i + 1 });
  ins('class_seats', { id: c.id, capacity: 24, updatedBy: U.direktor.uid });
});
// To'qima, yaxlit narxlar (haqiqiy narx jadvali EMAS).
const PRICE = { 0: 2000000, 1: 2200000, 2: 2200000, 3: 2300000, 4: 2400000, 5: 2600000, 6: 2700000, 7: 2800000, 8: 2900000, 9: 3100000, 10: 3300000, 11: 3400000 };
const priceRows = []; let ord = 1;
for (const lang of ['uz', 'ru']) for (let g = 0; g <= 11; g++) priceRows.push({ id: `${lang}-${g}`, grade: g, track: '', lang, amount: PRICE[g] + (lang === 'ru' ? 200000 : 0), order: ord++ });
for (const [t, add] of [['IT', 400000], ['MED', 300000]]) for (const g of [9, 10, 11]) priceRows.push({ id: `uz-${g}-${t}`, grade: g, track: t, lang: 'uz', amount: PRICE[g] + add, order: ord++ });
priceRows.forEach(r => ins('price_table', r));
const priceKeyOf = c => `${c.lang}-${c.grade}${c.track ? '-' + c.track : ''}`;
const priceOf = c => priceRows.find(r => r.id === priceKeyOf(c)).amount;

// Tasdiq qoidalari joriy oydan yoqilgan (Direktor / Moliya / HR tasdiqlarini mashq qilish uchun). Qaytarish PIN — sinov uchun.
const REFUND_PIN = '2468';
ins('config', { id: 'finance', sickRate: 40000, sickApprovalFrom: CUR, bonusApprovalFrom: CUR, discountApprovalFrom: CUR, payrollApprovalFrom: CUR, invoiceCreators: '', referralAmount: 300000 });
ins('config', { id: 'monitoring', entryDeadlineDay: 5 });
ins('config', { id: 'security', refundPin: REFUND_PIN });
ins('config', { id: 'payments', enabled: false, clickServiceId: '', clickMerchantId: '', uzumUrlTemplate: '' });   // onlayn to'lov havolalari YO'Q
ins('config', { id: 'staffatt', allowedBreakMin: 60, latePenalty: 0, earlyPenalty: 0, breakPenaltyPerHour: 0 });
ins('settings', { id: 'site', contact: { phone: '+998 22 000 00 00', address: 'Sinov shahri, Namuna ko‘chasi, 1-uy', email: 'info@' + DOMAIN }, stats: { students: 60, teachers: 8, years: 1 } });
ins('school_holidays', { id: dayOf(PREV, 1), day: dayOf(PREV, 1), name: 'Sinov bayrami (namuna)', createdBy: U.direktor.uid });
ins('school_holidays', { id: dayOf(NEXT, 8), day: dayOf(NEXT, 8), name: 'Sinov ta’til kuni (namuna)', createdBy: U.direktor.uid });

// ---------------------------------------------------------------- o'qituvchilar va xodimlar (maosh ID'lari — IQT- / IQX-)
const SUBJ = [['Matematika', 'Математика'], ['Ona tili', 'Родной язык'], ['Ingliz tili', 'Английский язык'], ['Fizika', 'Физика'],
  ['Informatika', 'Информатика'], ['Tarix', 'История'], ['Biologiya', 'Биология'], ['Rus tili', 'Русский язык']];
const TEACHERS = SUBJ.map((s, i) => ({ id: uuidOf('teacher:' + (i + 1)), teacherId: 'IQT-' + pad(i + 1, 3), name: `Sinov O‘qituvchi ${pad(i + 1)}`,
  phone: '99822000' + pad(100 + i + 1, 4), subject_uz: s[0], subject_ru: s[1], order: i + 1, baseSalary: 5000000 + i * 250000, salary: 5000000 + i * 250000,
  payStatus: '', activeFrom: SCHOOL_START, cameraId: String(101 + i), userUid: i === 0 ? U.oqituvchi.uid : null }));
TEACHERS[0].name = U.oqituvchi.name;
TEACHERS.forEach(t => ins('teachers', t));
const STAFF_DEF = [['Kassir', U.kassir1], ['Kassir', U.kassir2], ['HR menejer', U.hr], ['Qabulxona xodimi', U.qabul], ['Qorovul', null], ['Tozalov xodimi', null]];
const STAFF = STAFF_DEF.map(([pos, acc], i) => ({ id: uuidOf('staff:' + (i + 1)), staffId: 'IQX-' + pad(i + 1, 3), name: acc ? acc.name : `Sinov Xodim ${pad(i + 1)}`,
  position: pos, phone: '99822000' + pad(200 + i + 1, 4), salary: String(3000000 + i * 300000), order: i + 1, payStatus: '', activeFrom: SCHOOL_START,
  cameraId: String(201 + i), userUid: acc ? acc.uid : null }));
STAFF.forEach(s => ins('staff', s));
sql(`update public.users set "staffRefType"='teacher', "staffRefId"=${q(TEACHERS[0].id)}, "staffCode"=${q(TEACHERS[0].teacherId)} where id=${q(U.oqituvchi.uid)};`);
STAFF.filter(s => s.userUid).forEach(s => sql(`update public.users set "staffRefType"='staff', "staffRefId"=${q(s.id)}, "staffCode"=${q(s.staffId)} where id=${q(s.userUid)};`));

// ---------------------------------------------------------------- xodimlar davomati (yuz terminali skanlari — to'qima)
//   Har ish kuni (Dush–Juma, bayramsiz): keldi 07:35–07:58, ketdi 17:02–17:25 — maoshdan ushlanma chiqmaydi. Namuna uchun:
//   bitta xodimga kasallik (2 kun, haq to'lanadi), bitta xodimda sababsiz 1 kun yo'qlama, bitta xodimda bir marta kechikish.
const HOLIDAYS = new Set([dayOf(PREV, 1)]);
const workdays = (ym, upTo) => { const r = []; for (let k = 1; k <= Math.min(upTo, daysIn(ym)); k++) { const d = dayOf(ym, k), w = wday(d); if (w !== 0 && w !== 6 && !HOLIDAYS.has(d)) r.push(d); } return r; };
const PREV_WD = workdays(PREV, 31), CUR_WD = workdays(CUR, TD - 1);
const PEOPLE = TEACHERS.map(t => ({ cam: t.cameraId, name: t.name, refId: t.id, refType: 'teacher' })).concat(STAFF.map(s => ({ cam: s.cameraId, name: s.name, refId: s.id, refType: 'staff' })));
const SICK = { who: PEOPLE[2], days: PREV_WD.slice(8, 10) };            // o'qituvchi 03 — 2 kun kasallik
const ABSENT = { who: PEOPLE[8 + 4], day: PREV_WD[12] };                // xodim 05 (qorovul) — 1 kun sababsiz
const LATE = { who: PEOPLE[8 + 3], day: CUR_WD[Math.max(0, CUR_WD.length - 2)] };   // qabulxona — bir marta kechikdi
const scan = (p, day, status, hh, mm) => ins('staff_checkins', { id: `sinov_${p.cam}_${day.replace(/-/g, '')}_${status}`, personId: p.cam, name: p.name, status,
  ts: ts(day, hh, mm, (Number(p.cam) * 7) % 60), day, raw: { sinov: true }, createdAt: ts(day, hh, mm, 59) });
for (const day of PREV_WD.concat(CUR_WD)) for (const p of PEOPLE) {
  if (SICK.who === p && SICK.days.includes(day)) continue;
  if (ABSENT.who === p && ABSENT.day === day) continue;
  const k = (Number(p.cam) * 13 + Number(day.slice(8)) * 7) % 23;
  if (LATE.who === p && LATE.day === day) scan(p, day, 'in', 8, 42); else scan(p, day, 'in', 7, 35 + k);
  scan(p, day, 'out', 17, 2 + k);
}
if (wday(TODAY) !== 0 && wday(TODAY) !== 6) for (const p of PEOPLE) scan(p, TODAY, 'in', 7, 35 + (Number(p.cam) * 13) % 23);   // bugun: faqat «keldi»
if (SICK.days.length) ins('staff_leaves', { id: uuidOf('leave:1'), refId: SICK.who.refId, refType: SICK.who.refType, cameraId: SICK.who.cam, name: SICK.who.name, type: 'kasallik',
  startDay: SICK.days[0], endDay: SICK.days[SICK.days.length - 1], reason: 'Sinov yozuvi: kasallik varaqasi (namuna)', createdBy: U.hr.email, createdAt: ts(SICK.days[0], 9, 5) });

// ---------------------------------------------------------------- o'quvchilar (60 ta, 6 sinf)
const STUDENTS = [];
CLASSES.forEach((c, ci) => { for (let k = 1; k <= 10; k++) { const n = ci * 10 + k;
  STUDENTS.push({ n, sid: 'IQ-' + pad(n, 4), name: `Sinov O‘quvchi ${pad(n)}`, cls: c, classKey: c.id, price: priceOf(c), priceKey: priceKeyOf(c),
    father: `Sinov Ota ${pad(n)}`, mother: `Sinov Ona ${pad(n)}`, phone: '99822000' + pad(n, 4) }); } });
const byN = n => STUDENTS[n - 1];
// Holatlar: 58 — muzlatilgan (o'tgan oy o'rtasidan), 59 — chiqib ketgan (o'tgan oy), 60 — sinov (to'lovsiz).
byN(58).payStatus = 'muzlatilgan'; byN(58).stopFrom = dayOf(PREV, 16);
byN(59).payStatus = 'chiqdi'; byN(59).stopFrom = dayOf(PREV, 11);
byN(60).payStatus = 'sinov';
for (const s of STUDENTS) {
  const exit = s.payStatus === 'chiqdi';
  ins('students', { id: s.sid, studentId: s.sid, name: s.name, grade: s.cls.grade, classLetter: s.cls.letter, lang: s.cls.lang, track: s.cls.track,
    order: s.n, score: 60 + (s.n * 7) % 40, attendance: 85 + (s.n * 3) % 15, payStatus: s.payStatus || '', activeFrom: s.payStatus === 'sinov' ? '' : SCHOOL_START,
    stopFrom: s.stopFrom || '', exitReason: exit ? 'kochish' : null, exitNote: exit ? 'Sinov yozuvi: oila ko‘chib ketdi (namuna)' : null,
    exitAt: exit ? s.stopFrom : null, exitBy: exit ? U.direktor.uid : null });
  ins('student_private', { id: s.sid, fatherName: s.father, motherName: s.mother, parentPhone: s.phone, address: `Sinov shahri, Namuna ko‘chasi, ${s.n}-uy`,
    birthDate: `${SY - 6 - s.cls.grade}-${pad(1 + (s.n % 12))}-${pad(1 + (s.n * 5) % 28)}` });
}
const ACTIVE = STUDENTS.filter(s => !s.payStatus);

// ---------------------------------------------------------------- davomat, baho, monitoring (namuna)
function attDays(ym, upTo, seedN) {
  const d = {};
  for (let k = 1; k <= Math.min(upTo, daysIn(ym)); k++) { const w = wday(dayOf(ym, k)); if (w === 0 || w === 6) continue;
    const r = (k * 31 + seedN * 17) % 23; d[pad(k)] = r === 0 ? 'absent' : (r === 1 ? 'late' : (r === 2 ? 'sick' : 'present')); }
  return d;
}
for (const s of ACTIVE) {
  ins('attendance', { id: `${s.sid}__${PREV}`, studentId: s.sid, classKey: s.classKey, month: PREV, days: attDays(PREV, 31, s.n) });
  if (TD > 1) ins('attendance', { id: `${s.sid}__${CUR}`, studentId: s.sid, classKey: s.classKey, month: CUR, days: attDays(CUR, TD - 1, s.n) });
}
for (const s of ACTIVE.filter(s => s.cls.grade >= 5)) {
  ins('grades', { id: `${s.sid}__${YEAR}`, studentId: s.sid, classKey: s.classKey, year: YEAR,
    subjects: { Matematika: { q1: 3 + (s.n % 3) }, 'Ona tili': { q1: 4 + (s.n % 2) }, 'Ingliz tili': { q1: 3 + ((s.n + 1) % 3) } } });
  ins('monitoring', { id: `${s.sid}__${PREV}__matematika`, studentId: s.sid, classKey: s.classKey, subject: 'Matematika', period: PREV, score: 62 + (s.n * 7) % 38,
    status: 'approved', enteredAt: ts(dayOf(PREV, 25), 10, 0), enteredBy: U.oqituvchi.uid, approvedAt: ts(dayOf(PREV, 27), 10, 0), approvedBy: U.zavuch.uid });
}

// ---------------------------------------------------------------- hisob-fakturalar (o'tgan va joriy oy)
function invoiceRow(s, month) {
  return { id: `${s.sid}__${month}`, studentId: s.sid, studentName: s.name, classKey: s.classKey, month, amount: s.price, paidAmount: 0, status: 'pending', provider: '',
    baseAmount: s.price, discount: 0, discountInfo: '', isGrant: false, pctApplied: 0, sickDaysApplied: 0, sickAmount: 0, sickNoteRefs: {}, bonusRef: '',
    approvalRefs: [], referralUsedIds: [], priceKey: s.priceKey, billedFrom: '', billedTo: '', createdAt: ts(dayOf(month, 1), 10, 0) };
}
for (const s of ACTIVE) { ins('invoices', invoiceRow(s, PREV)); ins('invoices', invoiceRow(s, CUR)); }
// Muzlatilgan va chiqib ketgan o'quvchining o'tgan oy fakturasi — o'qigan kunlari uchun (taxminan yarim oy), to'langan.
for (const n of [58, 59]) { const s = byN(n), part = Math.round(s.price / 2 / 1000) * 1000;
  ins('invoices', Object.assign(invoiceRow(s, PREV), { amount: part, discountInfo: `Oyning bir qismi (${dayOf(PREV, 1)} — ${s.stopFrom})`, billedFrom: dayOf(PREV, 1), billedTo: s.stopFrom })); s.partPrev = part; }

// ---------------------------------------------------------------- to'lovlar — ilovaning apply_payment funksiyasi orqali
sql(`
-- To'lov yozuvi + balansga qo'llash (eng eski qarzdan) + sanalarni to'lov kuniga keltirish.
create function pg_temp.sinov_pay(p_id text, p_ref text, p_sid text, p_amount numeric, p_provider text, p_ts timestamptz, p_cols jsonb)
returns void language plpgsql as $f$
declare v jsonb;
begin
  insert into public.payments(id, "studentId", provider, amount, status, "payerName", "payerPhone", "payerClass", matched, raw,
                              click_trans_id, merchant_trans_id, merchant_prepare_id, merchant_confirm_id, "createdAt")
  values (p_id, p_sid, p_provider, p_amount, 'pending', p_cols->>'payerName', p_cols->>'payerPhone', p_cols->>'payerClass', true, coalesce(p_cols->'raw', '{}'::jsonb),
          p_cols->>'click_trans_id', p_cols->>'merchant_trans_id', p_cols->>'merchant_prepare_id', p_cols->>'merchant_confirm_id', p_ts);
  v := public.apply_payment(p_sid, p_amount, p_provider, p_ref);
  if not coalesce((v->>'ok')::boolean, false) then raise exception 'sinov seed: apply_payment(%) -> %', p_id, v; end if;
  update public.payments set status = 'applied' where id = p_id;
  update public.applied_payments set "createdAt" = p_ts where id = p_ref;
  update public.invoices set "paidAt" = p_ts where "studentId" = p_sid and "paidAt" = now();
  update public.credit_ledger set "at" = p_ts where "studentId" = p_sid and "at" = now();
  update public.student_credit set "updatedAt" = p_ts where id = p_sid;
end $f$;
`);
const PAYS = [];   // { sid, amount, method, day, hh, mm }
const addPay = (s, amount, method, day, by) => PAYS.push({ s, amount, method, day, hh: ri(9, 16), mm: ri(0, 59), by: by || (rnd() < 0.5 ? U.kassir1 : U.kassir2) });
const METHODS_PREV = ['cash', 'cash', 'cash', 'cash', 'click', 'click', 'bank', 'terminal'];
for (const s of ACTIVE) {
  const t = s.n % 10;      // har sinfda bir xil taqsimot
  // --- o'tgan oy fakturasi
  if (t === 9) { /* to'lamagan (ikki oylik qarzdor) */ }
  else if (t === 8) addPay(s, Math.round(s.price * 0.4 / 1000) * 1000, 'cash', dayOf(PREV, ri(5, 20)));          // qisman
  else if (t === 7) addPay(s, s.price, 'cash', curDay(ri(1, 3)));                                               // kech — joriy oyda to'ladi
  else if (t === 6) { addPay(s, 1000000, 'cash', dayOf(PREV, ri(3, 10))); addPay(s, s.price - 1000000, 'click', dayOf(PREV, ri(12, 22))); }   // ikki bo'lib, aralash usul
  else addPay(s, s.price, pick(METHODS_PREV), dayOf(PREV, ri(2, 24)));
  // --- joriy oy fakturasi
  if (t <= 2) addPay(s, s.price, pick(['cash', 'cash', 'click', 'bank']), curDay(ri(2, 9)));                    // to'liq
  else if (t === 3) addPay(s, s.price + 500000, 'cash', curDay(ri(2, 9)));                                      // ortiqcha to'lov -> avans
  else if (t === 4 || t === 5) addPay(s, Math.round(s.price / 2 / 1000) * 1000, pick(['cash', 'terminal']), curDay(ri(2, 9)));   // qisman
  // t = 6..9 — joriy oy to'lanmagan
}
for (const n of [58, 59]) addPay(byN(n), byN(n).partPrev, 'cash', dayOf(PREV, 8));
PAYS.sort((a, b) => (a.day + pad(a.hh) + pad(a.mm)).localeCompare(b.day + pad(b.hh) + pad(b.mm)));
PAYS.forEach((p, i) => {
  const t = ts(p.day, p.hh, p.mm, i % 60), ms = Date.parse(t);
  if (p.method === 'click') {
    const tr = String(9900000001 + i);     // to'qima Click tranzaksiya raqami
    sql(`select pg_temp.sinov_pay(${q('click_' + tr)}, ${q(tr)}, ${q(p.s.sid)}, ${p.amount}, 'click', ${q(t)}, ${j({ payerName: p.s.sid, payerPhone: p.s.phone, payerClass: `${p.s.cls.grade}-${p.s.cls.letter}`,
      click_trans_id: tr, merchant_trans_id: p.s.sid, merchant_prepare_id: String(ms).slice(0, 10), merchant_confirm_id: String(ms + 4000).slice(0, 10), raw: { mode: 'balance', sinov: true } })});`);
  } else {
    const id = `man_${ms}_${hexOf('pay:' + i, 5)}`;
    sql(`select pg_temp.sinov_pay(${q(id)}, ${q(id)}, ${q(p.s.sid)}, ${p.amount}, ${q(p.method)}, ${q(t)}, ${j({ payerName: p.s.father,
      raw: { manual: true, method: p.method, date: p.day, note: '', forPeriod: '', byUid: p.by.uid } })});`);
  }
});
// Biriktirilmagan Click to'lovi (telefon bo'yicha o'quvchi topilmagan) — kassir «Biriktirish»ni mashq qiladi.
ins('payments', { id: 'click_9900009901', studentId: '', provider: 'click', amount: 1500000, status: 'unmatched', matched: false, payerName: 'Sinov Ota 77',
  payerPhone: '998220009901', payerClass: '5-A', click_trans_id: '9900009901', merchant_trans_id: 'Sinov Ota 77', raw: { mode: 'free', sinov: true }, createdAt: ts(curDay(3), 11, 20) });

// ---------------------------------------------------------------- xarajatlar, xodim avansi
const EXP = [[PREV, 3, 'Ijara', 25000000, 'Bino ijarasi (namuna)'], [PREV, 6, 'Kommunal', 3200000, 'Elektr va suv (namuna)'], [PREV, 10, 'Oziq-ovqat', 8400000, 'Oshxona mahsulotlari (namuna)'],
  [PREV, 14, 'Kanselyariya', 650000, 'Qog‘oz, ruchka (namuna)'], [PREV, 20, 'Avtobus', 4000000, 'Yoqilg‘i (namuna)'], [PREV, 27, 'Maosh', 55000000, 'Oylik maoshlar (namuna)'],
  [CUR, 2, 'Ijara', 25000000, 'Bino ijarasi (namuna)'], [CUR, 4, 'Kommunal', 2900000, 'Elektr va suv (namuna)'], [CUR, 6, 'Xo‘jalik tovarlari', 780000, 'Tozalov vositalari (namuna)'],
  [CUR, 8, 'Marketing', 1500000, 'Reklama (namuna)']];
EXP.forEach(([m, d, cat, amount, note], i) => { const day = m === CUR ? curDay(d) : dayOf(m, d);
  ins('expenses', { id: 'exp_sinov_' + pad(i + 1), date: day, month: m, category: cat, amount, note, createdAt: ts(day, 15, 10 + i), updatedAt: ts(day, 15, 10 + i) }); });
[[TEACHERS[2], 'teachers', 1000000, 3], [STAFF[4], 'staff', 500000, 5]].forEach(([p, coll, amount, d], i) => { const day = curDay(d), tid = p.teacherId || p.staffId;
  ins('staff_advances', { id: `adv_${tid}_sinov${i + 1}`, teacherId: tid, payeeRef: `${coll}:${p.id}`, teacherName: p.name, amount, month: CUR, date: day, note: 'Sinov avansi (namuna)', createdAt: ts(day, 16, 5 + i) }); });

// ---------------------------------------------------------------- qabul (arizalar), arz-shikoyat, e'lon, boshqa bo'limlar
const LEADS = [['yangi', 'qongiroq', 1], ['boglanildi', 'sayt', 3], ['sinov', 'keldi', 5], ['yangi', 'sayt', 0]];
LEADS.forEach(([status, source, ago], i) => { const day = curDay(Math.max(1, TD - ago)), id = uuidOf('lead:' + i);
  ins('enrollments', { id, name: `Sinov Nomzod ${pad(i + 1)}`, phone: '+998 22 000 03 ' + pad(i + 1), grade: String(1 + i * 2), direction: 'uz', lang: 'uz', ts: ts(day, 10, i),
    status, note: 'Sinov arizasi (namuna)', childName: `Sinov Nomzod ${pad(i + 1)}`, parentName: `Sinov Ota-ona ${pad(i + 1)}`, source, stageAt: ts(day, 10, i), created: ts(day, 10, i), createdBy: U.qabul.uid });
  ins('enrollment_events', { id: uuidOf('lead-ev:' + i), enrollmentId: id, type: 'stage', payload: { to: status, source }, at: ts(day, 10, i), by: U.qabul.uid }); });
ins('feedback', { id: uuidOf('fb:1'), type: 'taklif', uid: null, authorName: 'Sinov Ota 05', authorRole: 'parent', studentId: 'IQ-0005', studentName: byN(5).name,
  text: 'Sinov taklifi: to‘garaklar jadvalini ertaroq e’lon qilsangiz (namuna).', status: 'new', createdAt: ts(curDay(2), 12, 0) });
ins('class_announcements', { id: uuidOf('ann:1'), classKeys: ['all'], title: 'Sinov e’loni: ota-onalar yig‘ilishi', body: 'Bu — sinov nusxasidagi namuna e’lon.',
  createdBy: U.direktor.uid, createdAt: ts(curDay(1), 9, 30), expiresAt: ts(dayOf(NEXT, 5), 18, 0), pinned: true });
ins('timetable', { id: 'uz-5-A', classKey: 'uz-5-A', days: Object.fromEntries(['mon', 'tue', 'wed', 'thu', 'fri'].map((d, i) =>
  [d, [{ time: '08:30', subject: SUBJ[i % 8][0] }, { time: '09:25', subject: SUBJ[(i + 1) % 8][0] }, { time: '10:30', subject: SUBJ[(i + 2) % 8][0] }]])) });
ins('homework', { id: uuidOf('hw:1'), classKey: 'uz-5-A', subject: 'Matematika', text: 'Sinov vazifasi: 12-mashq (namuna)', dueDate: dayOf(NEXT, 2), createdAt: ts(curDay(2), 14, 0) });
ins('exams', { id: uuidOf('exam:1'), classKey: 'uz-8-A', subject: 'Fizika', date: dayOf(NEXT, 10), time: '10:00', room: '12', note: 'Sinov imtihoni (namuna)' });
ins('olympiads', { id: uuidOf('ol:1'), studentId: 'IQ-0041', studentName: byN(41).name, classKey: byN(41).classKey, subject: 'Matematika', name: 'Sinov olimpiadasi', level: 'maktab', result: '1-o‘rin', date: dayOf(PREV, 18), mentor: TEACHERS[0].name, note: 'namuna' });
ins('canteen_menu', { id: TODAY, breakfast: 'Sutli bo‘tqa, choy', lunch: 'Mastava, osh, salat', snack: 'Meva', note: 'Sinov menyusi (namuna)', allergens: [], updatedBy: U.direktor.uid, updatedAt: ts(TODAY, 8, 0) });
ins('bus_routes', { id: 'sinov-1', name: 'Sinov yo‘nalishi 1', driver_key: hexOf('bus:1', 24), active: false });
// Veb-sayt bo'limlari (namuna matnlar)
ins('news', { id: 'sinov-yangilik-1', date: curDay(1), tag_uz: 'Yangilik', tag_ru: 'Новость', title_uz: 'Sinov yangiligi', title_ru: 'Тестовая новость', body_uz: 'Bu — sinov nusxasidagi namuna yangilik.', body_ru: 'Это пример новости в тестовой копии.', order: 1 });
ins('events', { id: 'sinov-tadbir-1', date: dayOf(NEXT, 12), title_uz: 'Sinov tadbiri', title_ru: 'Тестовое мероприятие', desc_uz: 'Namuna tadbir.', desc_ru: 'Пример мероприятия.', order: 1 });
ins('faq', { id: 'sinov-savol-1', q_uz: 'Bu haqiqiy sayt-mi?', q_ru: 'Это настоящий сайт?', a_uz: 'Yo‘q — bu sinov nusxasi, ma’lumotlar to‘qima.', a_ru: 'Нет — это тестовая копия, данные вымышленные.', order: 1 });
ins('plans', { id: 'sinov-tarif-1', name_uz: 'Sinov tarifi', name_ru: 'Тестовый тариф', price: '2 200 000', featured: '', features_uz: 'Namuna', features_ru: 'Пример', order: 1 });
ins('admission_steps', { id: 'sinov-qadam-1', num: 1, title_uz: 'Ariza', title_ru: 'Заявка', text_uz: 'Namuna qadam.', text_ru: 'Пример шага.', order: 1 });
ins('testimonials', { id: 'sinov-fikr-1', name: 'Sinov Ota 01', rating: 5, role_uz: 'Ota-ona', role_ru: 'Родитель', text_uz: 'Namuna fikr (sinov).', text_ru: 'Пример отзыва (тест).', order: 1, nameConsent: true });
ins('gallery', { id: 'sinov-rasm-1', image: '/icon-512.png', caption_uz: 'Sinov rasmi', caption_ru: 'Тестовое фото', order: 1 });
ins('achievements_school', { id: 'sinov-yutuq-1', year: SY, text_uz: 'Sinov yutug‘i (namuna)', text_ru: 'Тестовое достижение', order: 1 });
ins('achievements_students', { id: 'sinov-oquvchi-yutuq-1', name: byN(41).name, year: SY, text_uz: 'Sinov olimpiadasi g‘olibi (namuna)', text_ru: 'Победитель тестовой олимпиады', order: 1 });

// Tasdiq kutayotgan chegirma so'rovi (Direktor va Moliya menejeri «Tasdiqlash» bo'limida mashq qiladi).
ins('discount_requests', { id: uuidOf('dr:1'), studentId: 'IQ-0012', kind: 'social', params: {}, fromMonth: NEXT, toMonth: ymOf(TY, TM + 3),
  reason: 'Sinov so‘rovi: ko‘p bolali oila (namuna)', status: 'pending', requestedBy: U.qabul.uid, requestedAt: ts(curDay(Math.max(1, TD - 1)), 11, 30) });

// «O‘zgarishlar tarixi» bo'sh bo'lmasin: Direktor nomidan ikki-uchta haqiqiy tahrir (tarixga yoziladi).
sql(`
set local iqror.migrating = '0';
select set_config('request.jwt.claims', ${q(JSON.stringify({ sub: U.direktor.uid, role: 'authenticated' }))}, true);
update public.class_seats set capacity = 26, "updatedAt" = now() where id = 'uz-5-A';
update public.students set score = 91 where id = 'IQ-0021';
update public.student_private set address = 'Sinov shahri, Namuna ko‘chasi, 100-uy' where id = 'IQ-0021';
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
`);

sql(`
commit;
notify pgrst, 'reload schema';
select 'sinov seed (${TODAY}): hisoblar=' || (select count(*) from public.users) || ', o''quvchilar=' || (select count(*) from public.students)
  || ', fakturalar=' || (select count(*) from public.invoices) || ' (to''langan ' || (select count(*) from public.invoices where status = 'paid')
  || ', qisman ' || (select count(*) from public.invoices where status = 'partial') || ', to''lanmagan ' || (select count(*) from public.invoices where status = 'pending')
  || '), to''lovlar=' || (select count(*) from public.payments) || ', avans=' || (select coalesce(sum(credit), 0) from public.student_credit)
  || ', xarajatlar=' || (select count(*) from public.expenses);
`);
process.stdout.write(out.join('\n') + '\n');
