// Auth foydalanuvchilar + Storage rasmlarni Supabase'ga ko'chirish.
// VPS'DA (Supabase o'rnatilgach) ishga tushiriladi. Firebase parol-hash Supabase
// bilan mos emas -> foydalanuvchi parolni email orqali tiklaydi (3 ta uchun oson).
//
// Muhit o'zgaruvchilari:
//   SUPABASE_URL       = http://<vps>:8000  (yoki https://api.iqror.uz)
//   SERVICE_ROLE_KEY   = Supabase service_role kaliti (maxfiy!)
//   DATABASE_URL       = Supabase Postgres (users jadvalini qayta kalitlash uchun)
//   BACKUP             = .../backup
//   STORAGE_BUCKET     = 'public' (yoki yaratilgan bucket)
const { createClient } = require('@supabase/supabase-js');
const { Client } = require('pg');
const fs = require('fs'), path = require('path');

const sb = createClient(process.env.SUPABASE_URL, process.env.SERVICE_ROLE_KEY, { auth: { autoRefreshToken: false, persistSession: false } });
const BACKUP = process.env.BACKUP, BUCKET = process.env.STORAGE_BUCKET || 'public';

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL });
  await pg.connect();

  // ---- 1) AUTH foydalanuvchilar ----
  const users = JSON.parse(fs.readFileSync(path.join(BACKUP, 'auth_users.json'), 'utf8'));
  let created = 0, remapped = 0, skipped = 0;
  for (const u of users) {
    const email = u.email;
    if (!email) { skipped++; continue; }                    // emailsiz (masalan Google-only) — qo'lda
    const { data, error } = await sb.auth.admin.createUser({ email, email_confirm: true });
    if (error) { console.log('  auth SKIP', email, '-', error.message); skipped++; continue; }
    created++;
    const newUid = data.user.id;
    // users jadvalini yangi Supabase uid'ga qayta kalitlash (RLS auth.uid() bilan mos bo'lishi uchun)
    const r = await pg.query('update users set id=$1 where id=$2', [newUid, u.localId || u.uid]);
    if (r.rowCount) remapped++;
    // parolni tiklash havolasini yuboramiz
    await sb.auth.admin.generateLink({ type: 'recovery', email }).catch(() => {});
  }
  console.log(`Auth: yaratildi ${created}, users qayta kalitlandi ${remapped}, o'tkazildi ${skipped}`);

  // ---- 2) STORAGE rasmlar ----
  await sb.storage.createBucket(BUCKET, { public: true }).catch(() => {});   // bor bo'lsa xato bermaydi
  const sdir = path.join(BACKUP, 'storage');
  let up = 0, uperr = 0;
  const walk = (d, base = '') => {
    for (const f of fs.readdirSync(d)) {
      const full = path.join(d, f), rel = base ? base + '/' + f : f;
      if (fs.statSync(full).isDirectory()) walk(full, rel);
      else files.push({ full, rel });
    }
  };
  const files = []; if (fs.existsSync(sdir)) walk(sdir);
  for (const { full, rel } of files) {
    const buf = fs.readFileSync(full);
    const { error } = await sb.storage.from(BUCKET).upload(rel, buf, { upsert: true });
    if (error) { uperr++; console.log('  storage ERR', rel, '-', error.message); } else up++;
  }
  console.log(`Storage: yuklandi ${up}, xato ${uperr}`);

  // ---- 3) Rasm URL'larини yangilash (Firebase URL -> Supabase URL) ----
  // students.photo / posterImage, teachers.photo, testimonials.photo, gallery.image, news.image
  // Firebase Storage URL'lari bilan Supabase URL'larini almashtirish uchun eslatma:
  console.log('\nⓘ Keyingi qadam: students.photo va h.k. dagi Firebase URL\'larini Supabase');
  console.log('  Storage public URL (' + process.env.SUPABASE_URL + '/storage/v1/object/public/' + BUCKET + '/<path>) ga almashtiring.');
  console.log('  Buni fayl nomiga qarab UPDATE bilan qilamiz (keyingi kichik skript).');

  await pg.end();
  console.log('\n✅ Auth + Storage import tugadi. Parol: 3 foydalanuvchi email orqali tiklaydi.');
})().catch(e => { console.error('ERR', e.stack || e.message); process.exit(1); });
