# Iqror — AUTH serveri (telefon + parol + OTP)

Telefon raqam (+998XXXXXXXXX) + parol bilan ro‘yxatdan o‘tish / kirish / parol tiklash.
OTP (6 xonali SMS kod) orqali telefon tasdiqlanadi. **Maxfiy kalitlar faqat shu serverda.**

## Arxitektura (nega shunday)

- **Parol — Supabase Auth (bcrypt).** Biz parolni HECH QAYERDA saqlamaymiz/hash qilmaymiz.
  Har telefon uchun **sintetik email** yasaymiz: `998XXXXXXXXX@phone.iqroacademy.uz` va Supabase
  Auth’ga shu email + parol bilan yoziladi. Shunday qilib mavjud `sb/firebase-auth.js` shimi
  (signInWithPassword) qayta ishlatiladi — kam yangi kod, kam xato.
- **OTP — alohida qatlam (Eskiz SMS).** 6 xonali kod `otp_codes` jadvalida **HMAC hash** holida
  (ochiq emas), TTL ~3 daqiqa, 5 urinish, 60s qayta-yuborish, soatiga 5 ta. Kod to‘g‘ri bo‘lsa
  server qisqa muddatli imzolangan **ticket** beradi; ro‘yxatdan o‘tish/tiklash o‘sha ticket bilan
  yakunlanadi (OTP’ni chetlab bo‘lmaydi).
- **Rol server tomonда MAJBURLANADI.** Mijoz faqat `teacher` yoki `parent` yuboradi; boshqasi rad.
  `teacher` → `verified=false, status=pending` (admin tasdig‘ini kutadi). `parent` → darhol faol.
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

## config.json (maxfiy — gitga tushmaydi)

`serviceRoleKey`, `anonKey`, `auth.hmacSecret`, `sms.eskizEmail/eskizPassword` — barchasi MAXFIY.
`hmacSecret` ni yangilash eski ticketlar/OTP’larni bekor qiladi (xavfsiz, lekin faol oqimlar uziladi).
