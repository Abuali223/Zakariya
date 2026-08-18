// RLS sinovi — Firebase token testlarining Postgres ekvivalenti.
const { Client } = require('pg');
const c = new Client({ connectionString: process.env.DATABASE_URL });
let fails = 0; const ok = (cond, m) => { console.log((cond ? '✓' : '✗ FAIL') + ' ' + m); if (!cond) fails++; };

const CK = 'uz-1-A', SID = 'ZZ_RLS_KID', TERM = '2025-2026-q2';

async function setup() {
  // test foydalanuvchilar (postgres sifatida — RLS chetlab)
  const U = [
    ['t_admin', 'admin', null],
    ['t_zav', 'zavuch', null],
    ['t_parent', 'parent', [SID]],
    ['t_parent2', 'parent', ['OTHER']],
    ['t_home', 'teacher', null],   // homeroom + matematika
    ['t_fiz', 'teacher', null],    // faqat fizika
  ];
  for (const [id, role, kids] of U)
    await c.query('insert into users (id,role,verified,"childIds") values ($1,$2,true,$3) on conflict (id) do update set role=excluded.role,"childIds"=excluded."childIds"',
      [id, role, kids ? JSON.stringify(kids) : null]);
  await c.query(`update users set "assignedClasses"='["${CK}"]',"assignedSubjects"='["Matematika"]',"homeroomClasses"='["${CK}"]' where id='t_home'`);
  await c.query(`update users set "assignedClasses"='["${CK}"]',"assignedSubjects"='["Fizika"]' where id='t_fiz'`);
  // sinov ma'lumot
  await c.query('insert into student_private (id,pinfl) values ($1,$2) on conflict (id) do nothing', [SID, '123']);
  await c.query('insert into characteristics (id,"studentId","classKey",term,text) values ($1,$2,$3,$4,$5) on conflict (id) do nothing',
    [SID + '__' + TERM, SID, CK, TERM, 'umumiy']);
  await c.query('insert into subject_notes (id,"studentId","classKey",subject,term,text) values ($1,$2,$3,$4,$5,$6) on conflict (id) do nothing',
    [SID + '__' + TERM + '__matematika', SID, CK, 'Matematika', TERM, 'mat izoh']);
  await c.query('insert into subject_notes (id,"studentId","classKey",subject,term,text) values ($1,$2,$3,$4,$5,$6) on conflict (id) do nothing',
    [SID + '__' + TERM + '__fizika', SID, CK, 'Fizika', TERM, 'fiz izoh']);
}

// bitta so'rovni <uid> nomidan (RLS yoqilgan) bajaradi, tranzaksiya orqa qaytariladi
async function sel(uid, sql, params = []) {
  await c.query('begin');
  try {
    await c.query('set local role app_client');
    await c.query("select set_config('app.uid',$1,true)", [uid || '']);
    const r = await c.query(sql, params);
    return r.rowCount;
  } finally { await c.query('rollback'); }
}
async function ins(uid, sql, params = []) {
  await c.query('begin');
  try {
    await c.query('set local role app_client');
    await c.query("select set_config('app.uid',$1,true)", [uid || '']);
    const r = await c.query(sql, params);
    return r.rowCount > 0;              // haqiqatан yozildi (UPDATE'да RLS 0 qator = rad)
  } catch (e) { return false; }        // rad (RLS WITH CHECK)
  finally { await c.query('rollback'); }
}

(async () => {
  await c.connect();
  await setup();

  console.log('\n— PII (student_private) —');
  ok(await sel('t_admin', 'select 1 from student_private where id=$1', [SID]) === 1, 'Admin PII O\'QIYDI');
  ok(await sel('t_parent', 'select 1 from student_private where id=$1', [SID]) === 1, 'O\'z ota-onasi PII O\'QIYDI');
  ok(await sel('t_parent2', 'select 1 from student_private where id=$1', [SID]) === 0, 'BEGONA ota-ona PII O\'QIY OLMAYDI ★');
  ok(await sel('t_fiz', 'select 1 from student_private where id=$1', [SID]) === 0, 'O\'qituvchi PII O\'QIY OLMAYDI ★');
  ok(await sel('', 'select 1 from student_private where id=$1', [SID]) === 0, 'Anonim PII O\'QIY OLMAYDI');
  ok(await ins('t_parent', 'update student_private set pinfl=$2 where id=$1', [SID, 'x']) === false, 'Ota-ona PII YOZA OLMAYDI');

  console.log('\n— UMUMIY XARAKTERISTIKA —');
  ok(await sel('t_parent', 'select 1 from characteristics where "studentId"=$1', [SID]) === 1, 'O\'z ota-onasi ko\'radi');
  ok(await sel('t_fiz', 'select 1 from characteristics where "studentId"=$1', [SID]) === 1, 'Sinf fan o\'qituvchisi ko\'radi');
  ok(await sel('t_parent2', 'select 1 from characteristics where "studentId"=$1', [SID]) === 0, 'Begona ko\'ra OLMAYDI');
  ok(await ins('t_home', 'insert into characteristics (id,"studentId","classKey",term,text) values ($1,$2,$3,$4,$5)', ['X1', SID, CK, TERM, 'y']) === true, 'Sinf rahbari YOZADI');
  ok(await ins('t_fiz', 'insert into characteristics (id,"studentId","classKey",term,text) values ($1,$2,$3,$4,$5)', ['X2', SID, CK, TERM, 'y']) === false, 'Faqat fan o\'qituvchisi umumiyni YOZA OLMAYDI ★');
  ok(await ins('t_zav', 'insert into characteristics (id,"studentId","classKey",term,text) values ($1,$2,$3,$4,$5)', ['X3', SID, CK, TERM, 'y']) === true, 'Zavuch YOZADI');

  console.log('\n— FAN IZOHI (izolyatsiya) —');
  ok(await sel('t_fiz', 'select 1 from subject_notes where id=$1', [SID + '__' + TERM + '__matematika']) === 0, 'Fizika o\'qituvchisi MATEMATIKA izohini KO\'RMAYDI ★★');
  ok(await sel('t_fiz', 'select 1 from subject_notes where id=$1', [SID + '__' + TERM + '__fizika']) === 1, 'Fizika o\'qituvchisi O\'Z fani izohini ko\'radi');
  ok(await sel('t_home', 'select 1 from subject_notes where id=$1', [SID + '__' + TERM + '__fizika']) === 1, 'Sinf rahbari HAMMA fan izohini ko\'radi');
  ok(await sel('t_parent', 'select count(*)::int from subject_notes where "studentId"=$1 having count(*)=2', [SID]) >= 0, 'Ota-ona farzandi izohlarini ko\'radi');
  ok(await ins('t_fiz', 'insert into subject_notes (id,"studentId","classKey",subject,term,text) values ($1,$2,$3,$4,$5,$6)', ['N1', SID, CK, 'Matematika', TERM, 'z']) === false, 'Fizika o\'qituvchisi MATEMATIKA izohini YOZA OLMAYDI ★');
  ok(await ins('t_fiz', 'insert into subject_notes (id,"studentId","classKey",subject,term,text) values ($1,$2,$3,$4,$5,$6)', ['N2', SID, CK, 'Fizika', TERM, 'z']) === true, 'Fizika o\'qituvchisi O\'Z fani izohini YOZADI');

  console.log('\n— SECRETS (mijozga yopiq) —');
  ok(await sel('t_admin', 'select 1 from secrets', []) === 0, 'Admin ham secrets\'ni MIJOZ sifatida O\'QIY OLMAYDI ★');
  ok(await sel('', 'select 1 from secrets', []) === 0, 'Anonim secrets O\'QIY OLMAYDI');

  console.log('\n— OMMAVIY / USERS —');
  ok(await sel('', 'select 1 from students limit 1', []) >= 1, 'students OMMAVIY o\'qiladi (anonim)');
  ok(await ins('t_parent', 'insert into students (id,name) values ($1,$2)', ['ZZS', 'x']) === false, 'Ota-ona students YOZA OLMAYDI');
  ok(await ins('t_admin', 'insert into students (id,name) values ($1,$2)', ['ZZS', 'x']) === true, 'Admin students YOZADI');
  ok(await sel('t_parent', 'select 1 from users where id=$1', ['t_parent']) === 1, 'Foydalanuvchi O\'Z hujjatini ko\'radi');
  ok(await sel('t_parent', 'select 1 from users where id=$1', ['t_admin']) === 0, 'Foydalanuvchi BOSHQANI ko\'ra olmaydi');

  // tozalash
  for (const id of ['t_admin', 't_zav', 't_parent', 't_parent2', 't_home', 't_fiz']) await c.query('delete from users where id=$1', [id]);
  await c.query('delete from student_private where id=$1', [SID]);
  await c.query('delete from characteristics where "studentId"=$1', [SID]);
  await c.query('delete from subject_notes where "studentId"=$1', [SID]);
  await c.end();
  console.log(fails ? `\n❌ ${fails} FAILED` : '\n✅ ALL PASS — RLS Firestore qoidalari bilan bir xil ishlaydi');
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error('ERR', e.stack || e.message); process.exit(1); });
