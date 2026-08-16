-- =====================================================================
-- Iqror Academy — PostgreSQL (Supabase) sxemasi
-- Firestore kolleksiyalari -> jadvallar. id = Firestore hujjat IDsi.
-- Ustun nomlari Firestore maydonlari bilan bir xil (camelCase, qo'shtirnoqда)
-- -> frontend adapter deyarli o'zgarтirmасдан ishlaydi.
-- Ichki map/array -> JSONB. Sanalar -> timestamptz.
-- RLS alohida faylда (rls.sql).
-- =====================================================================

-- ============ OMMAVIY: o'quvchilar (sharaf taxtasi) — PII YO'Q ============
create table if not exists students (
  id             text primary key,           -- = studentId
  "studentId"    text,
  name           text,
  grade          int,
  "classLetter"  text,
  track          text,
  lang           text default 'uz',
  score          numeric,
  attendance     numeric,
  photo          text,
  "posterImage"  text,
  subjects       jsonb,                       -- array
  "cameraId"     text,
  "order"        int,
  "updatedAt"    timestamptz default now()
);

-- ============ 🔒 MAXFIY: shaxsiy ma'lumot (qulflangan) ============
create table if not exists student_private (
  id            text primary key,             -- = studentId
  pinfl         text,
  "parentPhone" text,
  "parentPhone2" text,
  guardian      text,
  "birthDate"   text,
  metrika       text,
  "prevSchool"  text,
  address       text,
  "livesWith"   text,
  health        text,
  interests     text,
  clubs         text,
  "fatherName"  text,
  "fatherWork"  text,
  "motherName"  text,
  "motherWork"  text
);

-- ============ Baholar (choraklik) ============
create table if not exists grades (
  id          text primary key,               -- = {sid}__{year}
  "studentId" text,
  "classKey"  text,
  year        text,
  subjects    jsonb                            -- {fan: {1,2,3,4}}
);
create index if not exists idx_grades_student on grades ("studentId");
create index if not exists idx_grades_class   on grades ("classKey");

-- ============ Davomat ============
create table if not exists attendance (
  id          text primary key,               -- = {sid}__{YYYY-MM}
  "studentId" text,
  "classKey"  text,
  month       text,
  days        jsonb                            -- {dd: 'present'|...}
);
create index if not exists idx_att_student on attendance ("studentId");
create index if not exists idx_att_class   on attendance ("classKey");

-- ============ Monitoring (fan ball) ============
create table if not exists monitoring (
  id          text primary key,               -- = {sid}__{period}__{slug}
  "studentId" text,
  "classKey"  text,
  subject     text,
  period      text,
  score       numeric,
  status      text,                            -- 'pending' | 'approved'
  "updatedAt" timestamptz default now()
);
create index if not exists idx_mon_student on monitoring ("studentId");
create index if not exists idx_mon_class   on monitoring ("classKey");

-- ============ Choraklik umumiy xarakteristika ============
create table if not exists characteristics (
  id          text primary key,               -- = {sid}__{term}
  "studentId" text,
  "classKey"  text,
  year        text,
  quarter     text,
  term        text,
  text        text,
  "byUid"     text,
  "byName"    text,
  "updatedAt" timestamptz default now()
);
create index if not exists idx_char_student on characteristics ("studentId");

-- ============ Fan izohi (o'qituvchi, izolyatsiya) ============
create table if not exists subject_notes (
  id          text primary key,               -- = {sid}__{term}__{slug}
  "studentId" text,
  "classKey"  text,
  subject     text,
  slug        text,
  year        text,
  quarter     text,
  term        text,
  text        text,
  "byUid"     text,
  "byName"    text,
  "updatedAt" timestamptz default now()
);
create index if not exists idx_note_student on subject_notes ("studentId");

-- ============ Oylik xulosa ============
create table if not exists student_summaries (
  id          text primary key,               -- = {sid}__{YYYY-MM}
  "studentId" text,
  "classKey"  text,
  month       text,
  text        text,
  sig         text,
  lang        text,
  "byUid"     text,
  "byName"    text,
  "updatedAt" timestamptz default now()
);
create index if not exists idx_sum_student on student_summaries ("studentId");

-- ============ To'lovlar (buxgalteriya) ============
create table if not exists invoices (
  id            text primary key,             -- = {sid}__{YYYY-MM}
  "studentId"   text,
  "studentName" text,
  "classKey"    text,
  month         text,
  amount        numeric,
  provider      text,
  status        text,                          -- 'paid'|'canceled'|'reversed'|null
  "providerTrans" text,                        -- to'lov tizimi tranzaksiya id
  "paidAt"      timestamptz,
  "reversedAt"  timestamptz,
  "createdAt"   timestamptz default now()
);
create index if not exists idx_inv_student on invoices ("studentId");

-- ============ To'lov jurnali (server yozadi) ============
create table if not exists payments (
  id          text primary key,
  "studentId" text,
  "invoiceId" text,
  provider    text,
  amount      numeric,
  status      text,
  raw         jsonb,
  -- Click SHOP-API maydonlari
  "click_trans_id"      text,
  "merchant_trans_id"   text,
  "merchant_prepare_id" text,
  "merchant_confirm_id" text,
  -- Uzum Merchant API maydoni
  "transId"             text,
  "createdAt" timestamptz default now()
);

-- ============ Xarajatlar (buxgalteriya — chiqim) ============
create table if not exists expenses (
  id          text primary key,
  date        text,                            -- "YYYY-MM-DD"
  month       text,                            -- "YYYY-MM"
  category    text,
  amount      numeric,
  note        text,
  "createdAt" timestamptz default now(),
  "updatedAt" timestamptz default now()
);
create index if not exists idx_exp_month on expenses (month);

-- ============ Foydalanuvchilar (rollar) — id = auth uid ============
create table if not exists users (
  id                 text primary key,        -- = auth.users.id (uid)
  email              text,
  name               text,
  role               text,                     -- admin|zavuch|kurator|teacher|parent|student
  verified           boolean default false,
  "childIds"         jsonb,
  "childId"          text,
  "activeChildId"    text,
  "assignedClasses"  jsonb,
  "assignedSubjects" jsonb,
  "homeroomClasses"  jsonb,
  "createdAt"        timestamptz default now()
);

-- ============ Dars jadvali / uy vazifasi ============
create table if not exists timetable (
  id         text primary key,                 -- = classKey
  "classKey" text,
  days       jsonb
);
create table if not exists homework (
  id          text primary key,
  "classKey"  text,
  subject     text,
  text        text,
  "dueDate"   text,
  "createdAt" timestamptz default now()
);
create index if not exists idx_hw_class on homework ("classKey");

-- ============ Arizalar / imtihon ============
create table if not exists enrollments (
  id        text primary key,
  name      text, phone text, grade text, direction text, lang text,
  ts        text,
  status    text default 'yangi',            -- lead voronka: yangi|boglanildi|sinov|qabul|rad
  note      text,
  "updatedAt" timestamptz default now(),
  created   timestamptz default now()
);
create table if not exists applications (
  id         text primary key,
  name       text, phone text, specialty text,
  answers    jsonb, status text, ts text, day text,
  created    timestamptz default now()
);
create table if not exists exam_questions (
  id            text primary key,              -- = slug (specialty)
  specialty     text, slug text,
  questions     jsonb, count int, "generatedBy" text,
  "updatedAt"   timestamptz default now()
);

-- ============ Kirish nazorati (yuz-terminal, server) ============
create table if not exists checkins (
  id          text primary key,
  "studentId" text, "cameraId" text,
  ts          timestamptz,
  raw         jsonb
);

-- ============ Sinflar / o'qituvchilar ============
create table if not exists classes (
  id      text primary key,
  grade   int, lang text, letter text, "order" int
);
create table if not exists teachers (
  id           text primary key,
  "teacherId"  text, name text, phone text, photo text,
  "subject_uz" text, "subject_ru" text,
  rating numeric, years int, certs int, avg numeric, votes int,
  "order" int
);

-- ============ Kontent (ommaviy) ============
create table if not exists news (
  id text primary key, date text, image text, video text,
  "tag_uz" text, "tag_ru" text, "title_uz" text, "title_ru" text,
  "body_uz" text, "body_ru" text, "order" int
);
create table if not exists gallery (
  id text primary key, image text, video text,
  "caption_uz" text, "caption_ru" text, "order" int
);
create table if not exists testimonials (
  id text primary key, name text, photo text, rating numeric,
  "role_uz" text, "role_ru" text, "text_uz" text, "text_ru" text,
  "order" int, "createdAt" timestamptz default now()
);
create table if not exists plans (
  id text primary key, "name_uz" text, "name_ru" text, price text,
  featured text, "features_uz" text, "features_ru" text,
  "order" int, "createdAt" timestamptz default now()
);
create table if not exists admission_steps (
  id text primary key, num int, "title_uz" text, "title_ru" text,
  "text_uz" text, "text_ru" text, "order" int, "createdAt" timestamptz default now()
);
create table if not exists faq (
  id text primary key, "q_uz" text, "q_ru" text, "a_uz" text, "a_ru" text,
  "order" int, "createdAt" timestamptz default now()
);
create table if not exists events (
  id text primary key, date text, "title_uz" text, "title_ru" text,
  "desc_uz" text, "desc_ru" text, "order" int, "createdAt" timestamptz default now()
);
create table if not exists achievements_school (
  id text primary key, year int, "text_uz" text, "text_ru" text, "order" int
);
create table if not exists achievements_students (
  id text primary key, name text, year int, "text_uz" text, "text_ru" text, "order" int
);

-- ============ Sozlamalar / config ============
create table if not exists settings (
  id text primary key, contact jsonb, stats jsonb
);
create table if not exists config (
  id text primary key, url text, enabled boolean, "keySet" boolean,
  "clickServiceId" text, "clickMerchantId" text, "uzumUrlTemplate" text,
  "updatedAt" timestamptz default now()
);

-- ⚠️ secrets (Anthropic kaliti) — DB'га EMAS. Server env/vault'да saqlanadi.
-- Bu jadval faqat "server-only" (RLS bilan hamma mijozга yopiq) — rls.sql'да.
create table if not exists secrets (
  id text primary key, "anthropicKey" text, "updatedAt" timestamptz default now()
);
