// «Kassa» brauzer ssenariylari uchun SINTETIK urug' (LOKAL stend). Repo ommaviy: barcha ism «Sinov …», e-mail — example.org,
//   telefonlar — mavjud bo'lmagan 998 00 … diapazoni, to'lov tizimi identifikatorlari — nollar. Haqiqiy shaxs yoki maktab ma'lumoti yo'q.
//   node seed/gen-seed.cjs   →  $E2E_LOCAL/seed.sql (600) va $E2E_LOCAL/ids.json (foydalanuvchi va karta id'lari; keyingi
//   ishga tushirishlarda o'sha id'lar qayta ishlatiladi). Qaytarish PIN kodi — har safar tasodifiy (faqat seed.sql da; ssenariylar
//   uni bazadan o'qiydi). Oylar — joriy oy (Toshkent vaqti) va oldingisi: ssenariylar «shu oy» fakturalariga tayanadi.
'use strict';
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const LOCAL = process.env.E2E_LOCAL || path.join(__dirname, '..', 'local');
fs.mkdirSync(LOCAL, { recursive: true });
const IDS = path.join(LOCAL, 'ids.json');
const rd = f => { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch (_) { return null; } };
const w600 = (f, s) => { fs.writeFileSync(f, s, { mode: 0o600 }); fs.chmodSync(f, 0o600); };

// ---------- oylar (Toshkent vaqti, UTC+5) ----------
const tk = new Date(Date.now() + 5 * 3600e3);
const ym = (y, m) => `${y}-${String(m).padStart(2, '0')}`;
const Y = tk.getUTCFullYear(), M = tk.getUTCMonth() + 1;
const P = ym(Y, M), PREV = M === 1 ? ym(Y - 1, 12) : ym(Y, M - 1), NEXT = M === 12 ? ym(Y + 1, 1) : ym(Y, M + 1);

// ---------- foydalanuvchilar ----------
const USERS = [
  // kalit, email, ism, rol, telefon, ism, familiya, tasdiqlangan, qo'shimcha rol, sinflar, fanlar, sinf rahbarligi
  ['R_DIR', 'direktor@example.org', 'Sinov Direktor', 'director', '998000000001', 'Sinov', 'Direktor', true],
  ['R_MOL', 'moliya@example.org', 'Sinov Moliyachi', 'finance_mgr', '998000000002', 'Sinov', 'Moliyachi', true],
  ['R_KAS', 'kassir@example.org', 'Sinov Kassir', 'kassir', '998000000003', 'Sinov', 'Kassir', true],
  ['R_REC', 'qabul@example.org', 'Sinov Qabulxona', 'reception', '998000000004', 'Sinov', 'Qabulxona', true],
  ['R_TCH', 'oqituvchi@example.org', 'Sinov O‘qituvchi', 'teacher', '998000000005', 'Sinov', 'O‘qituvchi', true, [], ['uz-4-A', 'uz-4-B', 'uz-5-A'], ['Matematika'], ['uz-4-A']],
  ['R_ZAV', 'zavuch@example.org', 'Sinov Zavuch', 'zavuch', '998000000006', 'Sinov', 'Zavuch', true],
  ['R_KUR', 'kurator@example.org', 'Sinov Kurator', 'kurator', '998000000007', 'Sinov', 'Kurator', true, [], [], [], ['uz-5-A']],
  ['R_NUR', 'hamshira@example.org', 'Sinov Hamshira', 'nurse', '998000000008', 'Sinov', 'Hamshira', true],
  ['R_PAR1', 'otaona1@example.org', 'Sinov Ota 01', 'parent', '998000000009', 'Sinov', 'Ota', true],
];
let ids = rd(IDS) || {};
for (const u of USERS) if (!ids[u[0]]) ids[u[0]] = crypto.randomUUID();
for (const k of ['T1', 'T2', 'T3', 'S1', 'S2']) if (!ids[k]) ids[k] = crypto.randomUUID();
fs.writeFileSync(IDS, JSON.stringify(ids, null, 2));
const refundPin = String(1000 + crypto.randomInt(9000));

// ---------- yordamchilar ----------
const q = v => v == null ? 'null' : "'" + String(v).replace(/'/g, "''") + "'";
const j = v => q(JSON.stringify(v)) + '::jsonb';
const hex = n => crypto.randomBytes(n).toString('hex');

// ---------- sinflar, narxlar ----------
const CLASSES = [['uz-1-A', 1, 'uz', 'A'], ['uz-4-A', 4, 'uz', 'A'], ['uz-4-B', 4, 'uz', 'B'], ['uz-5-A', 5, 'uz', 'A'], ['uz-7-A', 7, 'uz', 'A'], ['ru-7-B', 7, 'ru', 'B'], ['uz-9-IT', 9, 'uz', 'IT']];
const PRICE = { 0: 2200000, 1: 2500000, 2: 2500000, 3: 2600000, 4: 2800000, 5: 3200000, 6: 3200000, 7: 3400000, 8: 3400000, 9: 3600000, 10: 3800000, 11: 3800000 };
const priceRows = [];
let ord = 1;
for (const lang of ['uz', 'ru']) for (let g = 0; g <= 11; g++) priceRows.push([`${lang}-${g}`, g, '', lang, PRICE[g] + (lang === 'ru' ? 200000 : 0), ord++]);
for (const [t, add] of [['IT', 400000], ['MED', 300000]]) for (const g of [9, 10, 11]) priceRows.push([`uz-${g}-${t}`, g, t, 'uz', PRICE[g] + add, ord++]);
const priceOf = (lang, g, track) => (priceRows.find(r => r[0] === `${lang}-${g}${track ? '-' + track : ''}`) || priceRows.find(r => r[0] === `${lang}-${g}`))[4];

// ---------- o'quvchilar (17 ta; IQ-0016 — muzlatilgan, IQ-0017 — chiqib ketgan) ----------
const ST = [
  // id, sinf, harf, til, yo'nalish, holati
  ['IQ-0001', 4, 'A', 'uz', '', ''], ['IQ-0002', 4, 'A', 'uz', '', ''], ['IQ-0003', 4, 'A', 'uz', '', ''], ['IQ-0004', 4, 'B', 'uz', '', ''],
  ['IQ-0005', 4, 'B', 'uz', '', ''], ['IQ-0006', 5, 'A', 'uz', '', ''], ['IQ-0007', 5, 'A', 'uz', '', ''], ['IQ-0008', 5, 'A', 'uz', '', ''],
  ['IQ-0009', 7, 'A', 'uz', '', ''], ['IQ-0010', 7, 'A', 'uz', '', ''], ['IQ-0011', 7, 'B', 'ru', '', ''], ['IQ-0012', 7, 'B', 'ru', '', ''],
  ['IQ-0013', 9, 'IT', 'uz', 'IT', ''], ['IQ-0014', 9, 'IT', 'uz', 'IT', ''], ['IQ-0015', 1, 'A', 'uz', '', ''], ['IQ-0016', 4, 'A', 'uz', '', 'muzlatilgan'],
  ['IQ-0017', 7, 'A', 'uz', '', 'chiqdi'],
].map(([id, g, letter, lang, track, ps]) => { const n = id.slice(3); return [id, `Sinov O‘quvchi ${n}`, g, letter, lang, track, ps, `Sinov Ota ${n}`, '9980001' + n.padStart(5, '0')]; });   // ota-ona telefoni: 998 00 01… (xodimlarnikidan farqli)
const CODES = {}; for (const s of ST) CODES[s[0]] = hex(6).toUpperCase();
const active = ST.filter(s => !s[6]);

let sql = `\\set ON_ERROR_STOP on
-- LOKAL sinov stendi urug'i (tests/kassa-e2e/seed/gen-seed.cjs; sintetik). postgres nomidan, JWT siz (tizim — import kabi).
begin;
`;
for (const u of USERS) {
  const [k, email, name, role, phone, first, last, verified, extra, assigned, subjects, homeroom] = u;
  sql += `insert into public.users(id,email,name,role,verified,status,phone,"firstName","lastName","extraRoles","assignedClasses","assignedSubjects","homeroomClasses","createdAt","updatedAt") values (${q(ids[k])},${q(email)},${q(name)},${q(role)},${verified},'active',${q(phone)},${q(first)},${q(last)},${j(extra || [])},${j(assigned || [])},${j(subjects || [])},${j(homeroom || [])}, now() - interval '200 days', now() - interval '100 days');\n`;
}
CLASSES.forEach(([id, g, lang, letter], i) => { sql += `insert into public.classes(id,grade,lang,letter,"order") values (${q(id)},${g},${q(lang)},${q(letter)},${i + 1});\n`; });
sql += `insert into public.class_seats(id,capacity,"updatedBy") values ('uz-1-A',24,${q(ids.R_DIR)}),('uz-4-A',24,${q(ids.R_DIR)}),('uz-4-B',24,${q(ids.R_DIR)}),('uz-5-A',26,${q(ids.R_DIR)}),('uz-7-A',26,${q(ids.R_DIR)}),('ru-7-B',20,${q(ids.R_DIR)});\n`;
for (const r of priceRows) sql += `insert into public.price_table(id,grade,track,lang,amount,"order") values (${q(r[0])},${r[1]},${q(r[2])},${q(r[3])},${r[4]},${r[5]});\n`;
// tasdiq talablari keyingi oydan (joriy oy — avvalgi tartibda; ssenariylar shunga tayanadi)
sql += `insert into public.config(id,"sickRate","sickApprovalFrom","bonusApprovalFrom","discountApprovalFrom","payrollApprovalFrom","invoiceCreators","referralAmount") values ('finance',45000,${q(NEXT)},${q(NEXT)},${q(NEXT)},${q(NEXT)},'',300000);
insert into public.config(id,"entryDeadlineDay") values ('monitoring',5);
insert into public.config(id,"refundPin") values ('security',${q(refundPin)});
insert into public.config(id,"clickServiceId","clickMerchantId","uzumUrlTemplate",enabled) values ('payments','00000','00000','https://example.org/pay?amount={amount}&account={id}',true);
insert into public.config(id,"allowedBreakMin","latePenalty","earlyPenalty","breakPenaltyPerHour") values ('staffatt',60,0,0,0);
`;
// o'qituvchilar / xodimlar (IQT-001 — R_TCH ga, IQX-001 — R_KAS ga bog'langan)
sql += `insert into public.teachers(id,"teacherId",name,phone,subject_uz,subject_ru,"order","baseSalary",salary,"payStatus","activeFrom","userUid") values
  (${q(ids.T1)},'IQT-001','Sinov O‘qituvchi','998000000005','Matematika','Математика',1,6000000,6000000,'','2025-09-01',${q(ids.R_TCH)}),
  (${q(ids.T2)},'IQT-002','Sinov Ona tili','998000000010','Ona tili','Родной язык',2,5500000,5500000,'','2025-09-01',null),
  (${q(ids.T3)},'IQT-003','Sinov Ingliz tili','998000000011','Ingliz tili','Английский язык',3,5800000,5800000,'','2025-09-01',null);
insert into public.staff(id,"staffId",name,position,phone,salary,"order","payStatus","activeFrom","cameraId","userUid") values
  (${q(ids.S1)},'IQX-001','Sinov Kassir','Kassir','998000000003','4500000',1,'','2025-09-01','1201',${q(ids.R_KAS)}),
  (${q(ids.S2)},'IQX-002','Sinov Qorovul','Qorovul','998000000012','3500000',2,'','2025-09-01','1202',null);
update public.users set "staffRefType"='teacher',"staffRefId"=${q(ids.T1)},"staffCode"='IQT-001' where id=${q(ids.R_TCH)};
update public.users set "staffRefType"='staff',"staffRefId"=${q(ids.S1)},"staffCode"='IQX-001' where id=${q(ids.R_KAS)};
`;
ST.forEach(([id, name, g, letter, lang, track, ps, father, phone], i) => {
  const exit = ps === 'chiqdi';
  sql += `insert into public.students(id,"studentId",name,grade,"classLetter",lang,track,"order",score,attendance,"payStatus","activeFrom","stopFrom","exitReason","exitNote","exitAt","exitBy") values (${q(id)},${q(id)},${q(name)},${g},${q(letter)},${q(lang)},${q(track)},${i + 1},${70 + (i * 7) % 30},${85 + (i * 3) % 15},${q(ps)},'2025-09-01',${q(ps ? (exit ? PREV + '-15' : PREV + '-28') : '')},${q(exit ? 'kochish' : null)},${q(exit ? 'Sinov: boshqa maktabga o‘tdi' : null)},${q(exit ? PREV + '-15' : null)},${q(exit ? ids.R_DIR : null)});\n`;
  sql += `update public.student_codes set code=${q(CODES[id])} where id=${q(id)};\n`;
  sql += `insert into public.student_private(id,"fatherName","parentPhone",address,"birthDate") values (${q(id)},${q(father)},${q(phone)},'Sinov manzil',${q(`20${g > 6 ? '13' : '16'}-0${(i % 9) + 1}-1${i % 9}`)});\n`;
});
sql += `insert into public.child_claims(id,uid,"studentId",code,status) values (${q(ids.R_PAR1 + '__IQ-0001')},${q(ids.R_PAR1)},'IQ-0001',${q(CODES['IQ-0001'])},'active');\n`;
// fakturalar va to'lovlar: o'tgan oy — to'langan; joriy oy — to'langan / qisman / to'lanmagan (id raqami bo'yicha)
const pays = [];
for (const s of active) {
  const [sid, name, g, letter, lang, track] = s, ck = `${lang}-${g}-${letter}`, amt = priceOf(lang, g, track), pk = `${lang}-${g}${track ? '-' + track : ''}`;
  for (const m of [PREV, P]) {
    let status = 'paid', paid = amt;
    if (m === P) { const n = Number(sid.slice(3)); status = n % 3 === 0 ? 'pending' : (n % 3 === 1 ? 'paid' : 'partial'); paid = status === 'paid' ? amt : (status === 'partial' ? Math.round(amt / 2) : 0); }
    sql += `insert into public.invoices(id,"studentId","studentName","classKey",month,amount,"paidAmount",status,provider,"baseAmount",discount,"discountInfo","isGrant","pctApplied","sickDaysApplied","sickAmount","sickNoteRefs","bonusRef","approvalRefs","referralUsedIds","priceKey","billedFrom","billedTo","createdAt","paidAt") values (${q(sid + '__' + m)},${q(sid)},${q(name)},${q(ck)},${q(m)},${amt},${paid},${q(status)},${q(paid ? (sid === 'IQ-0001' && m === P ? 'click' : 'cash') : '')},${amt},0,'',false,0,0,0,'{}'::jsonb,'','[]'::jsonb,'[]'::jsonb,${q(pk)},'','',${q(m + '-01T05:00:00Z')},${paid >= amt ? q(m + '-0' + (3 + (Number(sid.slice(3)) % 5)) + 'T07:00:00Z') : 'null'});\n`;
    if (paid) pays.push([sid, name, ck, m, paid]);
  }
}
let pn = 0;
for (const [sid, name, ck, m, amt] of pays) {
  pn++;
  if (sid === 'IQ-0001' && m === P) {   // onlayn (Click) to'lov — sintetik to'lovchi
    sql += `insert into public.payments(id,"studentId","invoiceId",provider,amount,status,raw,click_trans_id,merchant_trans_id,"payerName","payerPhone","payerClass",matched,"createdAt") values ('click_e2e_1','IQ-0001',${q('IQ-0001__' + P)},'click',${amt},'paid','{"src":"click"}'::jsonb,'0000000001','IQ-0001','Sinov To‘lovchi','998000000009','4-A',true,${q(P + '-03T07:00:00Z')});
insert into public.applied_payments(id,"studentId",amount,result,"createdAt") values ('click_e2e_1','IQ-0001',${amt},'{"ok":true}'::jsonb,${q(P + '-03T07:00:01Z')});\n`;
    continue;
  }
  const day = String(3 + (pn % 5)).padStart(2, '0');
  const id = `man_${Date.UTC(Number(m.slice(0, 4)), Number(m.slice(5)) - 1, 3 + (pn % 5), 7) + pn}_${hex(3).slice(0, 5)}`;
  sql += `insert into public.payments(id,"studentId","invoiceId",provider,amount,status,raw,"payerName","createdAt") values (${q(id)},${q(sid)},${q(sid + '__' + m)},'cash',${amt},'applied',${j({ method: 'cash', note: '', by: 'kassir@example.org' })},${q(name)},${q(m + '-' + day + 'T07:00:00Z')});
insert into public.applied_payments(id,"studentId",amount,result,"createdAt") values (${q(id)},${q(sid)},${amt},'{"ok":true}'::jsonb,${q(m + '-' + day + 'T07:00:01Z')});\n`;
}
sql += `insert into public.student_credit(id,"studentId",credit) values ('IQ-0003','IQ-0003',100000),('IQ-0010','IQ-0010',0);
insert into public.refunds(id,target,"targetId","studentId","studentName",amount,reason,"byEmail",month,"createdAt") values ('rf_e2e_1','invoice',${q('IQ-0010__' + PREV)},'IQ-0010','Sinov O‘quvchi 0010',50000,'Sinov: ortiqcha to‘lov qaytarildi','direktor@example.org',${q(PREV)},${q(PREV + '-20T09:00:00Z')});
insert into public.expenses(id,date,month,category,amount,note) values ('exp_e2e_1',${q(P + '-02')},${q(P)},'kanselyariya',150000,'Sinov: qog‘oz'),('exp_e2e_2',${q(P + '-02')},${q(P)},'kommunal',2400000,'Sinov: elektr energiyasi');
commit;
select 'urug'' yuklandi: users='||(select count(*) from public.users)||' students='||(select count(*) from public.students)||' invoices='||(select count(*) from public.invoices)||' payments='||(select count(*) from public.payments);
`;
w600(path.join(LOCAL, 'seed.sql'), sql);
console.log(`urug' yozildi: ${path.join(LOCAL, 'seed.sql')} (oylar ${PREV}, ${P}), ${IDS}`);
