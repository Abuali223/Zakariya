# Iqror — AUTH serveri (telefon + parol + OTP)

Telefon raqam (+998XXXXXXXXX yoki chet el raqami: +7…, +48… — «Chet el raqamlari» bo‘limi) + parol bilan ro‘yxatdan
o‘tish / kirish / parol tiklash. OTP (6 xonali SMS kod) orqali telefon tasdiqlanadi. **Maxfiy kalitlar faqat shu serverda.**

## Arxitektura (nega shunday)

- **Parol — Supabase Auth (bcrypt).** Biz parolni HECH QAYERDA saqlamaymiz/hash qilmaymiz.
  Har telefon uchun **sintetik email** yasaymiz: `998XXXXXXXXX@phone.iqroacademy.uz` (chet el: `79031571124@…`) va Supabase
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
(masalan `IQROR Academy tasdiqlash kodi: {code}. Hech kimga bermang.`) ni Eskiz kabinetida tasdiqlang,
aks holda kodlar yuborilmaydi. `{code}` — 6 xonali kod bilan almashadi.

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
  (`{month}` — qarzdor oylar, masalan `09.2026, 10.2026`). ⚠️ Bu matn ham Eskiz kabinetida **shablon sifatida
  tasdiqlangan** bo‘lishi shart — aks holda Eskiz rad etadi va admin panel shuni aniq aytadi.
- `sms.dryRun: true` bo‘lsa — SMS ketmaydi, admin «SINOV rejimi» xabarini ko‘radi (jurnalga yozilmaydi).

## Chet el raqamlari (xalqaro OTP / SMS)

Raqam qoidasi — `server/phone.cjs` (brauzer `sb/auth-api.js` va `admin.html` da AYNAN shu blok; `phone.test.cjs` tekshiradi):
- O‘zbekiston: `+998 90 123 45 67`, `998901234567`, `901234567` (9 xonali — faqat `+`siz) → kanonik `998901234567`.
- Chet el: **faqat `+` (yoki `00`) bilan** to‘liq: `+7 903 157 11 24` → kanonik `79031571124` (bazada `+`siz saqlanadi).
  `+`siz uzun raqam (`79031571124`, `8 903 …`) — noaniq, yaroqsiz («⚠️ Sifat» `+` qo‘shishni taklif qiladi).
  Asosiy davlatlar uchun uzunlik aniq tekshiriladi; chala raqam (`+7 903 157 11`) hech qachon O‘zbekiston raqamiga aylanmaydi.
- Mijoz serverga raqamni doim `+` bilan yuboradi (`wirePhone`).

OTP chet el raqamiga **Eskiz xalqaro SMS** (`/api/message/sms/send-global`, `country_code` bilan) orqali ketadi.
⚠️ Eskiz kabinetida xalqaro SMS yoqilgan va balans yetarli bo‘lishi kerak. Firibgarlik (xalqaro SMS «pumping») himoyasi:
- `register` / `change_phone`: chet el raqami **maktab ma’lumotlarida bo‘lishi shart** — o‘quvchi kartasidagi ota/ona
  telefoni (`student_private.parentPhone/parentPhone2`) yoki xodim/o‘qituvchi telefoni. Aks holda: «maktab ma’lumotlarida
  topilmadi — farzandingiz kartasiga shu raqamni (+ bilan) yozdiring». Ro‘yxat `knownPhoneCacheSec` (60) soniya keshlanadi;
  bunday rad javoblari IP bo‘yicha soatiga `otpMaxPerIpHour` tadan.
- Butun tizim bo‘yicha chegara: `otpIntlMaxPerHour` (20) / `otpIntlMaxPerDay` (60) ta chet el OTP; `0` — o‘chirilgan.
- Eskiz chet el raqamini ANIQ rad etsa (xalqaro SMS yoqilmagan va h.k.) — foydalanuvchiga aytiladi (kod bekor qilinadi).
- O‘chirish: `auth.intlOtp: false` yoki `sms.international: false` (ikkinchisi qo‘lda/avtomatik SMS’ni ham o‘chiradi).

«Eslatma» (sms-remind) va avtomatik `sms-worker` ham chet el raqamiga yuboradi (`sms.international` ≠ false). Worker’da
chet el raqamini Eskiz aniq rad etsa — o‘sha xabar yakuniy (qayta urinilmaydi) va ketma-ket xato hisobiga kirmaydi.

## config.json (maxfiy — gitga tushmaydi)

`serviceRoleKey`, `anonKey`, `auth.hmacSecret`, `sms.eskizEmail/eskizPassword` — barchasi MAXFIY.
`hmacSecret` ni yangilash eski ticketlar/OTP’larni bekor qiladi (xavfsiz, lekin faol oqimlar uziladi).
