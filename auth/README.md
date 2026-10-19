# Iqror — AUTH serveri (telefon + parol + OTP)

Telefon raqam (+998XXXXXXXXX) + parol bilan ro‘yxatdan o‘tish / kirish / parol tiklash. OTP (6 xonali SMS kod) orqali
telefon tasdiqlanadi. **SMS faqat O‘zbekiston raqamlariga** yuboriladi. **Maxfiy kalitlar faqat shu serverda.**

## Arxitektura (nega shunday)

- **Parol — Supabase Auth (bcrypt).** Biz parolni HECH QAYERDA saqlamaymiz/hash qilmaymiz.
  Har telefon uchun **sintetik email** yasaymiz: `998XXXXXXXXX@phone.iqroacademy.uz` va Supabase
  Auth’ga shu email + parol bilan yoziladi. Shunday qilib mavjud `sb/firebase-auth.js` shimi
  (signInWithPassword) qayta ishlatiladi — kam yangi kod, kam xato.
- **OTP — alohida qatlam (Eskiz SMS).** 6 xonali kod `otp_codes` jadvalida **HMAC hash** holida
  (ochiq emas), TTL ~3 daqiqa, 5 urinish, 60s qayta-yuborish, soatiga 5 ta. Kod to‘g‘ri bo‘lsa
  server qisqa muddatli imzolangan **ticket** beradi; ro‘yxatdan o‘tish/tiklash o‘sha ticket bilan
  yakunlanadi (OTP’ni chetlab bo‘lmaydi).
- **Rol server tomonда MAJBURLANADI.** Mijoz `staff` («Xodim») yoki `parent` («Ota-ona») yuboradi; boshqasi (admin,
  director, …) rad — «Noto‘g‘ri rol. Sahifani yangilang…». ESKI sahifa (brauzerda uzoq ochiq qolgan, «O‘qituvchi» tugmasi)
  `teacher` yuboradi — u ham `staff` sifatida qabul qilinadi. `staff` → `verified=false, status=pending` (admin
  tasdig‘ini kutadi; telefon bo‘yicha HR yozuviga avtomatik bog‘lanadi va tasdiqlash oynasida lavozimiga mos rol
  oldindan tanlanadi). `parent` → darhol faol.
- **service_role** (RLS chetlab) — foydalanuvchi yaratish/yangilash; **anon** — login (parol tekshiruvi).

## Endpointlar  (nginx `/authapi/*` → `127.0.0.1:8792`)

> ⚠️ Tashqi yo‘l **`/authapi/`** — chunki `/auth/` BAND (Supabase GoTrue, kong:8000). Port **8792**
> (8790 = to‘lov, 8791 = AI). Server yo‘lning oxirgi bo‘lagiga qarab marshrutlaydi.

| Metod | Yo‘l | Tana | Javob |
|---|---|---|---|
| POST | `/auth/request-otp` | `{phone, purpose:'register'|'reset'|'change_phone', jwt?}` | `{ok, resendAfter}` yoki `{ok:false, redirect?}` |
| POST | `/auth/verify-otp` | `{phone, purpose, code}` | `{ok, ticket}` |
| POST | `/auth/register` | `{ticket, password, firstName, lastName, role}` | `{ok, verified, pending, message}` |
| POST | `/auth/login` | `{phone, password}` | `{ok, access_token, refresh_token, role, verified}` |
| POST | `/auth/reset-confirm` | `{ticket, newPassword}` | `{ok, message}` |
| POST | `/auth/change-phone-confirm` | `{ticket}` | `{ok, message}` |
| POST | `/auth/sms-remind` | `{jwt, studentId, preview?}` | `{ok, preview?, name, phone, due, months, message}` / `{ok, sent}` / `{ok:false, already?, error}` |
| GET | `/auth/health` | — | `ok` |

Mijoz `login`/`register`dan keyin `supabase.auth.setSession({access_token, refresh_token})` chaqiradi
(seansni brauzerda o‘rnatadi).

## Xavfsizlik eslatmalari

- Login xatosi **umumiy** (“Telefon yoki parol noto‘g‘ri”) — qaysi biri noto‘g‘riligini oshkor qilmaydi.
  Lockout: 15 daqiqada 10 xato → vaqtincha blok (`auth_login_attempts`).
- `reset` da **enumeration yo‘q**: raqam ro‘yxatda bo‘lmasa ham `ok` qaytadi (SMS yuborilmaydi).
- `register` da telefon band bo‘lsa — **ataylab** aniq xabar + `redirect:'login'` (spec talabi).
- **Yetim (squat) hisob**: kimdir sintetik email bilan to‘g‘ridan-to‘g‘ri hisob ochib qo‘ysa (users
  qatorisiz), haqiqiy egasi ro‘yxatdan o‘tganда server uni **o‘chirib qayta yaratadi** (`auth_uid_by_email`).
- OTP kodi va parol **hech qachon** logga yozilmaydi (faqat DRY rejimда kod ko‘rinadi).

## Ishga tushirish

```bash
cd auth
cp config.example.json config.json      # to'ldiring (serviceRoleKey/anonKey/hmacSecret/eskiz)
npm install
node index.cjs                            # 127.0.0.1:8792 da tinglaydi
npm test                                  # birlik testlar (tashqi xizmatsiz)
```

## Eskiz SMS shabloni — MUHIM

Eskiz yuborishdan oldin SMS matnini **moderatsiyadan** o‘tkazishni talab qiladi. `auth.otpTemplate`
(standart `IQROR Academy tasdiqlash kodi: {code}. Hech kimga bermang.`) ni Eskiz kabinetida tasdiqlang,
aks holda kodlar yuborilmaydi. `{code}` — 6 xonali kod bilan almashadi.

**Eskiz nimani solishtiradi.** Har bir SMS siz kabinetga yuborgan **asl matn** bilan emas, moderator tasdiqlagan
**naqsh** (`template`) bilan solishtiriladi. Naqshda o‘zgaruvchi joylar: `%w` — 1 so‘z, `%d` — 1 son (`5800000`,
`09.2026`), `%w{1,4}` — 1–4 so‘z. Masalan asl matn `Eslatma: {name} uchun {month} oy to'lovi …` bo‘lsa, naqsh
`Eslatma: %w uchun %w oy to'lovi …` bo‘lishi mumkin — unda `Aliyeva Malika` (2 so‘z), `09.2026, 10.2026` (2 bo‘lak),
`5 800 000` (3 bo‘lak) sig‘maydi va Eskiz «Этот смс текст еще не прошел модерацию» deb rad etadi (matn hali
moderatsiyada bo‘lsa ham xuddi shu xato). O‘zgarmas qism esa harfma-harf bir xil bo‘lishi kerak (`'` va `‘` — har xil belgi).

**Tizim buni o‘zi hal qiladi:**
- o‘zgaruvchilar BITTA so‘z qilib yoziladi: summa `5800000`, oylar `09.2026` / `09.2026,10.2026` / `05.2026-10.2026`;
- Eskiz’dagi naqshlar o‘qiladi (`GET /api/user/templates`; «Eslatma» — 10 daqiqa kesh, Eskiz 5 soniyada javob bermasa
  naqshsiz davom etadi) va ism naqshga sig‘adigan shaklda olinadi: to‘liq → «Familiya Ism» → «Ism» → «Familiya»;
- admin tasdiq oynasida aynan yuboriladigan matn ko‘rinadi; ism qisqartirilgan bo‘lsa — izoh; matn hech bir tasdiqlangan
  naqshga mos kelmasa — ⚠️ ogohlantirish (SMS baribir urinib ko‘riladi — yakuniy hakam Eskiz’ning o‘zi).

**Tekshiruv (hech narsa yubormaydi):**
```bash
cd ~/iqror-repo/payments && node eskiz-shablon.cjs                 # config.json'ni o'zi topadi
node eskiz-shablon.cjs --config ../auth/config.json                # «Eslatma» va OTP matni auth sozlamasidan
node eskiz-shablon.cjs --name "Aliyeva Malika" --months 2026-09,2026-10 --due 5800000
```
Natija: Eskiz’dagi har bir matn holati (Servis / Moderatsiyada / Rad etilgan) va naqshi; tizimning har SMS turi
(«Eslatma», avtomatik qarz, yangi faktura, OTP) mos-mos emasligi, mos bo‘lmasa — aniq sababi (qaysi o‘zgaruvchi necha
so‘z, qaysi belgi farq qiladi) va nima qilish kerakligi. OTP qatori ✅ bo‘lishi kerak (ro‘yxat kodi SMS’i yetib
borayotgan bo‘lsa) — bu tekshiruvning o‘zi to‘g‘ri ishlayotganini ko‘rsatadi. Chiqish kodi: 0 — hammasi mos, 2 — mos
emas, 1 — sozlama/ulanish xatosi.

**Eskiz’ga matn yuborish:** `{name}` kabi belgilar bilan EMAS, HAQIQIY misol bilan yuboring (moderator o‘zgaruvchi
joylarni misoldan aniqlaydi) va izohda yozing: ism — 1–4 so‘z, oy — 1 so‘z, summa — 1 son. Masalan:
```
Eslatma: Aliyeva Malika uchun 09.2026,10.2026 oy to'lovi hali yopilmagan (qarz: 5800000 so'm). Iltimos, to'lovni amalga oshiring. IQROR Academy
```

## Qarzdorga SMS eslatma («Moliya» → «Qarzdorlar» → «Eslatma») — `sms-remind.cjs`

Admin panelda tugma bosilganda: avval **ko‘rib chiqish** (`preview:true` — hech narsa yuborilmaydi), admin
oynada o‘quvchi, telefon, qarz, oylar va SMS matnini ko‘rib tasdiqlaydi, keyin yuboriladi.
- **Ruxsat:** faqat FAOL `director` / `finance_mgr` (`sms.remindRoles` bilan o‘zgartiriladi) — JWT + `users` jadvali.
- **Qarz serverda** hisoblanadi (`invoices`, joriy Toshkent oyigacha; bekor/qaytarilgan/to‘langan — 0) — «Qarzdorlar»
  kartasi bilan bir xil qoida. Telefon: `student_private.parentPhone` (yaroqsiz bo‘lsa `parentPhone2`).
- **O‘quvchi:** bosilgan kalit bitta o‘quvchiga mos bo‘lishi shart (ID to‘qnashuvida — rad, SMS boshqa oilaga ketmasin);
  qarz o‘quvchining barcha kalitlaridagi (studentId + eski hujjat id) fakturalardan, qulf — kanonik kalit bilan.
- **Takror yo‘q:** bir o‘quvchiga **kuniga bitta** (`sms_log` id `remind__<kanonik kalit>__<YYYY-MM-DD>`, atomik claim;
  parallel bosishda ham bitta SMS). Eskiz **aniq rad etsa** shu kuni `remindMaxRetries` (3) martagacha qayta urinish;
  natija **noaniq** bo‘lsa (tarmoq xatosi/timeout — `unknown`, yoki jarayon uzilgan — `sending`) — bugun qayta
  yuborilmaydi. Limit: foydalanuvchiga soatiga `remindMaxPerHour` (60), maktabga kuniga `remindMaxPerDay` (500);
  `0` — eslatma o‘chirilgan; `remindRoles: []` — hech kim. Limit claim’dan keyin ham qayta sanaladi (parallel so‘rovlar
  oshib keta olmaydi). Avtomatik `sms-worker` shu kuni qo‘lda eslatma olgan (yoki olayotgan) o‘quvchini o‘tkazadi.
- **Matn:** `sms.templates.remind` → `sms.templates.debt` → standart:
  `Eslatma: {name} uchun {month} oy to'lovi hali yopilmagan (qarz: {due} so'm). Iltimos, to'lovni amalga oshiring. IQROR Academy`
  (`{month}` — qarzdor oylar bitta so‘z: `09.2026,10.2026`, 3 va undan ko‘p bo‘lsa `05.2026-10.2026`; `{due}` —
  `5800000`). ⚠️ Bu matn ham Eskiz kabinetida **shablon sifatida tasdiqlangan** bo‘lishi shart — aks holda Eskiz rad
  etadi va admin panel shuni aniq aytadi (yuqoridagi «Eskiz SMS shabloni»: naqsh, ism moslash, `node eskiz-shablon.cjs`).
- `sms.dryRun: true` bo‘lsa — SMS ketmaydi, admin «SINOV rejimi» xabarini ko‘radi (jurnalga yozilmaydi).

## Telefon raqamlari: SMS faqat O‘zbekiston raqamlariga

Raqam qoidasi — `server/phone.cjs` (brauzer `sb/auth-api.js` va `admin.html` da AYNAN shu blok; `phone.test.cjs` tekshiradi):
- O‘zbekiston: `+998 90 123 45 67`, `998901234567`, `901234567` (9 xonali — faqat `+`siz) → kanonik `998901234567`.
- Chet el raqami (`+7 903 157 11 24`, `+48 789 706 619` — faqat `+` yoki `00` bilan) — **ma’lumot sifatida to‘g‘ri**
  (o‘quvchi kartasi, «⚠️ Sifat» xato demaydi), lekin unga **SMS yuborilmaydi** (maktab qoidasi):
  - OTP (`request-otp`: ro‘yxat / parol tiklash / telefon almashtirish) chet el raqami uchun darhol rad etiladi:
    «SMS kod faqat O‘zbekiston raqamlariga yuboriladi… yoki «Email yoki Google bilan» kiring» (bazaga qaralmaydi —
    enumeration yo‘q); brauzer ham shu xabarni ko‘rsatadi;
  - «Eslatma» (`sms-remind`) va avtomatik `sms-worker` faqat O‘zbekiston raqamini oladi (ota chet el raqami bo‘lsa —
    onaning O‘zbekiston raqami); O‘zbekiston raqami umuman bo‘lmasa — SMS yo‘q, sababi aytiladi;
  - `payments/sms.cjs` `send()` chet el raqamiga Eskiz’ga so‘rov yubormaydi (`bad_phone:intl`).
- Kiritish maskasi raqamlarni hech qachon tashlab yubormaydi (ortiqcha raqam ko‘rinadi, raqam yaroqsiz bo‘ladi) —
  `+998 ` ortidan yozilgan boshqa raqam begona odamning O‘zbekiston raqamiga aylanib, kod unga ketmaydi.

## config.json (maxfiy — gitga tushmaydi)

`serviceRoleKey`, `anonKey`, `auth.hmacSecret`, `sms.eskizEmail/eskizPassword` — barchasi MAXFIY.
`hmacSecret` ni yangilash eski ticketlar/OTP’larni bekor qiladi (xavfsiz, lekin faol oqimlar uziladi).
