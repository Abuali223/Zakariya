# Iqror Academy — Firebase → aHost (Supabase) migratsiya rejasi

**Maqsad:** shaxsiy ma'lumotlarni (o'quvchilar PII, baholar, rasmlar) O'zbekiston
hududidagi serverга (aHost VPS) ko'chirish — "Shaxsiy ma'lumotlar to'g'risida"gi
qonunning lokalizatsiya talabiga muvofiqlik uchun.

**Yondashuv:** Firebase (Google) → **Supabase (self-hosted, aHost VPS'да)**.
Supabase = PostgreSQL + Auth + Storage + API bir butun. Frontend UI o'zgarmaydi;
faqat ma'lumot qatlami (Firebase SDK → Supabase client) almashadi.

---

## Umumiy arxitektura

```
HOZIR (Firebase / Google, chet elда)          KEYIN (aHost VPS, O'zbekistонда)
  Firestore  (baza)                              PostgreSQL         (Supabase ichida)
  Firebase Auth (login)                          Supabase Auth
  Firebase Storage (rasm)                        Supabase Storage
  Cloud Functions (AI/to'lov)                    Node xizmat / Edge Functions
  Firebase Hosting (sayt)                        Nginx (statik sayt) / aHost
```

---

## Bosqichlar va mas'uliyat

| # | Bosqich | Kim | Holat |
|---|---------|-----|-------|
| 1 | **Firebase to'liq export (zaxira)** — 24 kolleksiya, 3 auth, 30 rasm (17 MB) | 🤖 Claude | ✅ Tayyor |
| 2 | **PostgreSQL sxema** (`schema.sql`) — 31 jadval | 🤖 Claude | ✅ Tayyor (0 xato) |
| 3 | **RLS** — Firestore Rules → Postgres qoidalari (`rls.sql`) | 🤖 Claude | ✅ Tayyor (test 25/25) |
| 4 | **Import skriptlari** (JSON → Postgres, rasm → Storage, auth, URL rewrite) | 🤖 Claude | ✅ Tayyor (276 yozuv) |
| 5 | **Frontend adapter** (Firebase SDK → Supabase shim, `sb/`) | 🤖 Claude | ✅ Tayyor (shim-test 17/17) |
| 6 | **VPS o'rnatish qo'llanmasi** (Supabase Docker) | 🤖 Claude (yozadi) / 👤 User (ishga tushiradi) | ✅ Yozildi |
| 7 | **Import + parallel sinov + cutover** | 👤 User (ishga tushiradi) / 🤖 Claude (yo'naltiradi) | ⏳ VPS kutmoqda |

**Kod tomoni 100% tayyor.** Frontend Firebase yuzasi (Firestore 20 + Auth 15 + Storage 4 +
App/Analytics) `sb/` shimlar bilan to'liq qoplangan. Cutover — bitta buyruq
(`switch-backend.cjs`). Batafsil: `CUTOVER-CHECKLIST.md`.

**Chegara:** Claude aHost VPS'ga kira olmaydi (xavfsizlik). Barcha kod/skript/qo'llanma
tayyorlanadi; VPS'даги buyruqlarни foydalanuvchi ishga tushiradi va saytни sinaydi.

---

## Ma'lumot xaritasi (kolleksiya → jadval)

Denormalizatsiya saqlanadi: har kolleksiya = bitta jadval, ichki map/array → **JSONB**.
`id` = Firestore hujjat IDsi (masalan `IQ-0001__2025-2026`).

| Kolleksiya | Hujjat | Izoh |
|---|---|---|
| students | 46 | Ommaviy (sharaf taxtasi) — PII yo'q |
| student_private | 32 | 🔒 PII (JSHSHIR, tel, vasiy, bio) — qulflangan |
| grades | 12 | `subjects` → jsonb |
| attendance | 38 | `days` → jsonb |
| monitoring | 0 | (bo'sh, koddan) score/status |
| characteristics | 0 | (bo'sh) choraklik umumiy izoh |
| subject_notes | 0 | (bo'sh) fan izohi |
| student_summaries | 1 | oylik xulosa |
| invoices | 58 | to'lovlar |
| payments | 0 | server yozadi |
| users | 3 | rollar (assignedClasses jsonb) |
| timetable | 3 | `days` → jsonb |
| homework | 9 | |
| enrollments | 0 | arizalar |
| applications | 0 | imtihon javoblari |
| exam_questions | 1 | `questions` → jsonb |
| checkins | 0 | yuz-terminal |
| classes | 24 | |
| teachers | 6 | |
| news, gallery, testimonials, plans, admission_steps, faq, events, achievements_school, achievements_students | kontent |
| settings | 1 | `contact`,`stats` → jsonb |
| config | 1 | ochiq sozlama |
| secrets | 1 | ⚠️ Anthropic kaliti → **DB'да emas, server env/vault'да** |

---

## Auth migratsiyasi
- 3 foydalanuvchi (email/parol + Google). Firebase scrypt parol-hash Supabase (bcrypt)
  bilan mos emas.
- **Strategiya (3 ta uchun oson):** foydalanuvchilar Supabase Auth'да qayta yaratiladi;
  parol **email orqali qayta tiklanadi** (reset link). Google-login → OAuth qayta ulanadi.
- `users` jadvalidagi rol/childIds/assignedClasses saqlanadi (auth uid bilan bog'lanadi).

## Storage migratsiyasi
- 30 rasm (16 MB) → Supabase Storage bucket'iga yuklanadi.
- URL'lar yangilanadi (Firebase Storage URL → Supabase Storage URL) — students.photo va h.k.

## Xavfsizlik (RLS)
Firestore Security Rules → PostgreSQL **Row Level Security**:
- `students` — ommaviy o'qish; PII yo'q (noPII).
- `student_private` — admin/zavuch/ota-ona (ownsChild).
- `grades/attendance/monitoring` — rol asosida (kurator/o'qituvchi/ota-ona).
- `subject_notes` — fan o'qituvchisi faqat o'z fani (izolyatsiya).
- `characteristics/summaries` — umumiy mualliflar + ota-ona.
- `secrets` — mijozга umuman yopiq (faqat server).

## Sinov strategiyasi (parallel)
1. Supabase VPS'да tayyor bo'ladi, ma'lumot import qilinadi.
2. Sayt **nusxasi** yangi backend'ga ulanib, **eski Firebase yonida** sinaladi.
3. Tekshiriladi: login, kabinet, admin CRUD, baho/davomat, RLS (begona ko'rmasligi), profil PDF/QR.
4. Faqat 100% muvofiq bo'lgачда cutover.

## Cutover + rollback
- **Cutover:** domen/frontend yangi backend'ga o'tadi.
- **Rollback:** muammо bo'lsa, frontend eski Firebase'ga qайtariladi (Firebase o'chirilmaydi,
  kamida 1 oy zaxirada turadi).

## Xatarlar va choralar
| Xatar | Chora |
|---|---|
| Ma'lumot yo'qolishi | To'liq zaxira (✅), parallel sinov, eski tizim saqlanadi |
| Parol migratsiyasi | Reset link (3 user — oson) |
| RLS xatosi (ruxsat) | Har qoida real token bilan sinaladi (Firebase'дагидек) |
| VPS xavfsizligi | HTTPS, firewall, MFA, backup, yangilanish |
| Qonuniy | Yurist bilan lokalizatsiya tasdiqlanadi (parallel) |

---

## Fayllar (`migration/`)
- `MIGRATION.md` — shu reja
- `export-firebase.cjs` — Firebase → JSON zaxira (bajarildi)
- `schema.sql` — PostgreSQL jadval sxemasi
- `rls.sql` — xavfsizlik qoidalari (keyingi)
- `import.cjs` — JSON → Supabase (keyingi)
- `supabase-setup.md` — VPS o'rnatish qo'llanmasi (keyingi)
