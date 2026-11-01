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
| POST | `/auth/request-otp` | `{phone, purpose:'register'|'reset'|'change_phone', jwt?}` | `{ok, resendAfter, smsUncertain?, warning?}` yoki `{ok:false, smsFailed?, redirect?, error}` |
| POST | `/auth/verify-otp` | `{phone, purpose, code}` | `{ok, ticket}` |
| POST | `/auth/register` | `{ticket, password, firstName, lastName, role}` | `{ok, verified, pending, message}` |
| POST | `/auth/login` | `{phone, password}` | `{ok, access_token, refresh_token, role, verified}` yoki `{ok:false, status?:'blocked'|'pending', error}` |
| POST | `/auth/reset-confirm` | `{ticket, newPassword}` | `{ok, message}` |
| POST | `/auth/change-phone-confirm` | `{ticket}` | `{ok, message}` |
| POST | `/auth/sms-remind` | `{jwt, studentId, preview?}` | `{ok, preview?, name, phone, due, months, message}` / `{ok, sent}` / `{ok:false, already?, error}` |
| POST | `/auth/block-user` | `{jwt, uid}` (faqat FAOL direktor) | `{ok, already, prevRole, claims, sessions, message}` / `{ok:false, error}` + HTTP 401/403/400/404/409/502 |
| POST | `/auth/unblock-user` | `{jwt, uid}` (faqat FAOL direktor) | `{ok, already, role, status, claims, message}` / `{ok:false, error}` |
| GET | `/auth/health` | — | `ok` (ommaviy, hech qanday ma'lumotsiz — tashqi kuzatuv uchun) |
| GET | `/auth/health/deep` | `Authorization: Bearer <direktor JWT>` | `{ok, at, checks:[{key, name, ok, info, at?, ms}]}`; anon 401, boshqa rol 403 |

Mijoz `login`/`register`dan keyin `supabase.auth.setSession({access_token, refresh_token})` chaqiradi
(seansni brauzerda o‘rnatadi).

## SMS kod yetib bormasa — aniq xato

Eskiz'ga so‘rov (~8 soniya muddat — `auth.otpSmsTimeoutMs`, standart 8000; javob baribir muddat + ≤2 s ichida qaytadi) natijasi
ikki xil bo‘ladi (`payments/sms.cjs`: `ambiguous` / `definitelyNotSent` — `sms_log`dagi `failed`/`unknown` bilan bir xil qoida):
- **SMS ANIQ ketmadi** — Eskiz rad etdi (4xx: shablon moderatsiyada, balans tugagan...), Eskiz'ga kirib/ulanib bo‘lmadi:
  `request-otp` → `{ok:false, smsFailed:true, error:'SMS yuborilmadi. Birozdan so‘ng qayta urinib ko‘ring yoki maktabga
  murojaat qiling.'}` (avval `{ok:true}` qaytib, odam kelmaydigan kodni kutardi). Kod yozuvi o‘chiriladi: bu urinish soatlik
  (telefon/IP) limitga va 60 s «qayta yuborish» kutishiga **sanalmaydi**, oldin yetib borgan kod amal qilaveradi; sayt «Qayta
  yuborish»ni darhol bosiladigan qiladi.
- **Natija NOANIQ** — Eskiz 5xx yoki id'siz javob berdi, so‘rov yetib borgandan keyin uzildi yoki muddat o‘tdi (SMS navbatga
  qo‘yilgan bo‘lishi mumkin): `{ok:true, smsUncertain:true, warning:'SMS kechikishi mumkin: …', resendAfter:60}` — kod FAOL
  (kechikib kelgan SMS'dagi kod ishlaydi), sayt kodni kiritish bosqichiga o‘tib sariq ogohlantirish ko‘rsatadi; urinish limitga
  va 60 s kutishga **sanaladi** — aks holda Eskiz sekinlashganda har so‘rov limitsiz haqiqiy SMS yuborardi (SMS-bombing, xarajat).
Kod avval «yuborilmoqda» holida yoziladi (tekshirib bo‘lmaydi) va Eskiz javobidan keyin faollashadi. Sinov rejimi (`sms.dryRun`)
o‘zgarmagan. ⚠️ Parol tiklashda Eskiz aniq rad etib turgan paytda mavjud raqam «SMS yuborilmadi», ro‘yxatda yo‘q raqam esa
«kod yuborildi» oladi — faqat nosozlik paytida.

**Bloklangan hisob** (`users.status='blocked'`): telefon+parol bilan kirishda GoTrue taqig‘i (`user_banned`) — «Hisobingiz
bloklangan. Administratorga murojaat qiling.» (urinish lockout'ga sanalmaydi; admin panelda email bilan kirishda ham shu matn);
parolni tiklash — SMS YUBORILMAYDI (ro‘yxatda yo‘q raqam kabi javob, pulli SMS behuda ketmaydi), oldin olingan tiklash kodi
bilan ham parol o‘zgarmaydi; telefon almashtirish — rad.

## Maktab Wi‑Fi'si — ishonchli IP (`auth.otpTrustedIps`)

Bir IP soatiga `otpMaxPerIpHour` (20) ta kod so‘ray oladi (SMS «pompalash»dan himoya). Maktabda ota-onalar bitta Wi‑Fi'dan
(bitta tashqi IP) ro‘yxatdan o‘tsa — 20 tadan keyin «Juda ko‘p so‘rov» chiqadi. Maktabning tashqi IP'sini ishonchli qiling:
```json
"auth": { "otpTrustedIps": ["203.0.113.7"], "otpMaxPerTrustedIpHour": 300 }
```
- Aniq IP yoki CIDR (`"203.0.113.0/28"`, IPv6 ham). Juda keng tarmoq (IPv4 /16 dan, IPv6 /32 dan keng) va yaroqsiz yozuv
  qabul qilinmaydi (serverni ishga tushirishda ogohlantirish). Telefon bo‘yicha limit (`otpMaxPerHour`, 5) O‘ZGARMAYDI.
- **Maktab IP'sini aniqlash:** maktab Wi‑Fi'siga ulangan telefon/kompyuterda `https://ifconfig.me` ni oching (yoki
  `curl -s https://ifconfig.me`) — chiqqan raqam. Yoki maktabda bir nechta ota-ona ro‘yxatdan o‘tgan soatdan keyin serverda:
  `sudo docker exec supabase-db psql -U postgres -d postgres -c "select ip, count(*) from public.otp_codes where \"createdAt\" > now() - interval '2 hours' group by ip order by 2 desc limit 5"`
  — eng ko‘p takrorlangan IP. Provayder IP'ni o‘zgartirsa (statik bo‘lmasa) — yangisini yozing; provayderdan statik IP so‘rash tavsiya etiladi.
- O‘zgartirgach: `sudo systemctl restart iqror-auth` (jurnalda: «ishonchli (maktab) IP yozuvlari: N ta»).
- Mijoz IP'si: so‘rov nginx'dan (127.0.0.1) kelsa — `X-Real-IP` (nginx `$remote_addr`) yoki `X-Forwarded-For`ning OXIRGI qiymati;
  to‘g‘ridan-to‘g‘ri ulanishda — soket manzili. Mijoz yozgan sarlavha limitni chetlab o‘tmaydi (`net.cjs`, `net.test.cjs`).
  nginx'da `proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $remote_addr;` bo‘lishi shart
  (`migration/deploy/nginx.conf.example`) — aks holda hamma so‘rov bitta IP (127.0.0.1) bo‘lib ko‘rinadi.
- Login limiti telefon bo‘yicha (15 daqiqada 10 xato) — IP bo‘yicha login limiti yo‘q, shuning uchun bu sozlama faqat OTP'ga ta’sir qiladi.

## Hisobni bloklash (ishdan bo‘shatish) — «Foydalanuvchilar» → «🚫 Bloklash»

«O‘chirish» faqat `users` qatorini o‘chiradi — kirish hisobi (auth) qoladi, odam telefon/parol bilan qayta kiradi. Ishdan ketgan
xodim yoki muammoli hisob uchun **Bloklash** (faqat FAOL direktor; tasdiq oynasi bilan):
1. GoTrue taqig‘i (`ban_duration: 876000h`) — yangi kirish va token yangilash yopiladi;
2. bazada (atomik, `public.user_block`): `users.role` olinadi (avvalgisi `blockedRole`ga), `status='blocked'`, `blockedAt/blockedBy`;
   RLS rol funksiyalari statusni tekshirmaydi — rol olinishi ochiq seansni ham DARHOL yopadi; kirish seanslari
   (`auth.sessions`, `auth.refresh_tokens`) o‘chiriladi; ota-ona bo‘lsa — FAOL `child_claims` → `revoked`;
3. o‘zini va oxirgi FAOL direktorni bloklash — rad; 2-bosqich bajarilmasa 1-bosqich orqaga qaytariladi (hech narsa o‘zgarmaydi).
«Blokdan chiqarish» — taqiq olinadi, rol `blockedRole`dan qaytadi (bloklangan paytda qo‘lda rol berilgan bo‘lsa — o‘sha),
shu bloklashda to‘xtatilgan farzand bog‘lanishlari qaytadi; rol tayinlanmagan yangi xodim — yana «kutmoqda». Hammasi
o‘zgarishlar tarixiga (change_log) direktor nomi bilan yoziladi.
- Bloklangan hisobning roli/holati FAQAT «Blokdan chiqarish» bilan o‘zgaradi: «Tahrirlash» oynasida saqlab bo‘lmaydi, eskirgan
  oyna (ro‘yxat bloklashdan oldin ochilgan) ham saqlay olmaydi — baza rad etadi (`trg_users_block_cols`, 42501).
  `blockedRole/blockedAt/blockedBy` va `status='blocked'` — faqat shu ikki RPC orqali.
- Bloklangan ota-ona muddati tugamagan seans (JWT, ≤1 soat) bilan ham farzand ma’lumotini ko‘rmaydi, farzand biriktira olmaydi
  (`claim_child` rad) va o‘z bog‘lanishini o‘chira olmaydi (`owns_child`/`owns_student_doc`/`has_active_child` statusni tekshiradi).
- **Eski usulda bloklangan** hisob (`status='blocked'`, lekin rol SAQLANGAN, taqiqsiz — oldingi versiyalardan) ro‘yxatda
  «eski usulda: rol saqlangan» deb ko‘rinadi: «🚫 To‘liq bloklash» uni to‘liq bloklaydi (rol → `blockedRole`, taqiq, seanslar).

**To‘liq o‘chirish** (masalan hisob egasining talabi bilan; qaytarib bo‘lmaydi) — serverda, email bo‘yicha (telefon hisobida
email — `998XXXXXXXXX@phone.iqroacademy.uz`). Avval kimligini tekshiring, so‘ng bitta tranzaksiyada:
```bash
E='998XXXXXXXXX@phone.iqroacademy.uz'   # o‘chiriladigan hisob (X — raqamlar; o‘zgartirilmasa hech narsa o‘chmaydi)
sudo docker exec -i supabase-db psql -U postgres -d postgres -X -v ON_ERROR_STOP=1 -v e="$E" <<'SQL'
select u.id, u.name, u.role, u.status from public.users u join auth.users a on a.id::text = u.id where lower(a.email) = lower(:'e');
begin;
create temp table del_uid on commit drop as select id::text as uid from auth.users where lower(email) = lower(:'e');
do $$ begin if (select count(*) from del_uid) <> 1 then raise exception 'Aniq bitta hisob topilmadi — hech narsa o''chirilmadi'; end if; end $$;
delete from public.child_claims where uid in (select uid from del_uid);
update public.staff    set "userUid" = '' where "userUid" in (select uid from del_uid);
update public.teachers set "userUid" = '' where "userUid" in (select uid from del_uid);
delete from public.users where id in (select uid from del_uid);
delete from auth.users  where id::text in (select uid from del_uid);
commit;
SQL
```
(Davomat, maosh, to‘lov tarixi o‘chirilmaydi — ular HR/moliya yozuvlari; o‘zgarishlar tarixida o‘chirish qayd etiladi.)

## «🩺 Tizim holati» — `GET /authapi/health/deep`

Faqat FAOL direktor JWT bilan (admin panel → Sozlamalar). Har tekshiruv ≤ 3 s, parallel: baza (`config` jadvalidan yengil
so‘rov), GoTrue (`/auth/v1/health`), Eskiz (kalit bormi va AMAL QILADIMI — Eskiz’ga kirib tasdiqlangan matnlar ro‘yxati
so‘raladi, `GET /api/user/templates`, SMS yuborilmaydi; `auth.health.eskizCheck: false` — faqat kalit borligi; balans — faqat
`auth.health.eskizBalance: true` bo‘lsa, `GET /api/user/get-limit`), to‘lov va AI serverlari (`127.0.0.1:8790/8791/health`), oxirgi muvaffaqiyatli onlayn to‘lov
(Click/Uzum — `payments` jadvalidan), oxirgi zaxira (`/var/log/iqror-backup.log` dagi oxirgi «backup OK»; 26 soatdan eski yoki
oxirgi urinish xato — qizil). Javobda kalit, token, parol, manzil, email, telefon YO‘Q. Sozlama (`auth.health`, ixtiyoriy):
`backupLog` (false — o‘chiq), `backupMaxAgeHours`, `payPort`/`aiPort` (0 — o‘chiq), `eskizCheck` (standart true), `eskizBalance`.

## Xavfsizlik eslatmalari

- Login xatosi **umumiy** (“Telefon yoki parol noto‘g‘ri”) — qaysi biri noto‘g‘riligini oshkor qilmaydi.
  Lockout: 15 daqiqada 10 xato → vaqtincha blok (`auth_login_attempts`).
- `reset` da **enumeration yo‘q**: raqam ro‘yxatda bo‘lmasa ham `ok` qaytadi (SMS yuborilmaydi).
- `register` da telefon band bo‘lsa — **ataylab** aniq xabar + `redirect:'login'` (spec talabi).
- **Yetim (squat) hisob**: kimdir sintetik email bilan to‘g‘ridan-to‘g‘ri hisob ochib qo‘ysa (users
  qatorisiz), haqiqiy egasi ro‘yxatdan o‘tganда server uni **o‘chirib qayta yaratadi** (`auth_uid_by_email`).
- OTP kodi va parol **hech qachon** logga yozilmaydi (faqat DRY rejimда kod ko‘rinadi).
- Tarmoq darajasida: nginx `limit_req` `/authapi/` uchun (10 so‘rov/s, burst 20) — `migration/deploy/nginx.conf.example`.

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
- o‘zgaruvchilar BITTA so‘z qilib yoziladi: summa `5800000`, oylar `09.2026` / `09.2026,10.2026` / `08.2026-10.2026`
  (oraliq — faqat KETMA-KET oylar uchun; uzilish bo‘lsa vergul bilan: `05.2026,06.2026,08.2026-10.2026` — to‘langan oy qarzdek
  ko‘rinmaydi);
- Eskiz’dagi naqshlar o‘qiladi (`GET /api/user/templates`; «Eslatma» — 10 daqiqa kesh; yangilab bo‘lmasa yoki Eskiz
  5 soniyada javob bermasa — oxirgi muvaffaqiyatli ro‘yxat bilan davom etadi; `sms.dryRun` sinov rejimida ham o‘qiladi —
  sinov matni haqiqiy matn bilan bir xil) va ism naqshga sig‘adigan shaklda olinadi: to‘liq → «Familiya Ism» → «Ism» → «Familiya»;
- admin tasdiq oynasida aynan yuboriladigan matn ko‘rinadi; ism qisqartirilgan bo‘lsa — izoh; matn hech bir tasdiqlangan
  naqshga mos kelmasa — ⚠️ ogohlantirish (SMS baribir urinib ko‘riladi — yakuniy hakam Eskiz’ning o‘zi).

**Tekshiruv (hech narsa yubormaydi):**
```bash
cd ~/iqror-repo/payments && sudo $(which node) eskiz-shablon.cjs   # ikkala sozlamani o'zi topadi (sudo — pastga qarang)
sudo $(which node) eskiz-shablon.cjs --config /opt/iqror/auth/config.json --config ./config.json   # aniq fayllar
node eskiz-shablon.cjs --name "Aliyeva Malika" --months 2026-09,2026-10 --due 5800000
```
Har SMS turi o‘zini **yuboradigan** jarayon sozlamasidan tekshiriladi: «Eslatma» va OTP — auth serveri
(`/opt/iqror/auth/config.json`, bo‘lmasa `../auth/config.json`), avtomatik qarz va yangi faktura — `sms-worker`
(`./config.json`, bo‘lmasa `/opt/iqror/payments/config.json`). Har tur uchun BIRINCHI mavjud fayl jonli hisoblanadi:
unda Eskiz kaliti yo‘q / to‘ldirilmagan bo‘lsa — boshqa faylga o‘tilmaydi, qator «⚪ TEKSHIRILMADI» (bu jarayon SMS yubora
olmaydi). Ikkala sozlama alohida login qilinadi (email bir xil, parol boshqa bo‘lsa ham). `/opt/iqror/auth/config.json` faqat egasiga o‘qilsa
(0600) — `sudo` bilan ishga tushiring (aks holda «Eslatma»/OTP qatori «⚪ TEKSHIRILMADI» bo‘ladi). `--config`
(`--config=YO‘L`, bir necha marta) berilsa — faqat o‘sha fayllar (turi ichidan aniqlanadi: `auth` bo‘limi bor — auth
serveri); nisbiy yo‘l joriy papkaga nisbatan.

Natija: Eskiz’dagi har bir matn holati (Servis / Moderatsiyada / Rad etilgan) va naqshi; tizimning har SMS turi
(«Eslatma», avtomatik qarz, yangi faktura, OTP) mos-mos emasligi — **5 xil** ism/oy/summa/kod bilan, jumladan 1 so‘zli
ism (moderator misolni so‘zma-so‘z tasdiqlagan, faqat ba’zi joylarni o‘zgaruvchi qilgan yoki ism uchun «%w %w» — aniq
2 so‘z — yozgan bo‘lsa ham ushlanadi: aks holda faqat o‘sha misol o‘tib, haqiqiy SMS’lar rad etilardi);
mos bo‘lmasa — aniq sababi (moderatsiyada / rad etilgan / so‘zma-so‘z tasdiqlangan / qaysi o‘zgaruvchi necha so‘z /
qaysi belgi farq qiladi va qaysi FAYLda tuzatish kerak) va nima qilish kerakligi. HAQIQIY misol bilan yuborilgan,
hali moderatsiyadagi matn ham taniladi (maslahat — kutish, qayta yuborish emas). OTP qatori ✅ bo‘lishi kerak (ro‘yxat
kodi SMS’i yetib borayotgan bo‘lsa) — bu tekshiruvning o‘zi to‘g‘ri ishlayotganini ko‘rsatadi. Chiqish kodi: 0 — hammasi
mos, 2 — mos emas yoki tekshirilmagan tur bor, 1 — sozlama/ulanish xatosi (sozlama fayli matni, jumladan buzilgan
JSON xabari, hech qachon chiqarilmaydi; `config.example.json`dagi to‘ldirilmagan kalitlar qabul qilinmaydi).

**Eskiz’ga matn yuborish:** `{name}` kabi belgilar bilan EMAS, HAQIQIY misol bilan yuboring (moderator o‘zgaruvchi
joylarni misoldan aniqlaydi) va izohda yozing: ism — 1–4 so‘z, oy — 1 so‘z, summa — 1 son (bu joylar har SMS’da
o‘zgaradi). Masalan:
```
Eslatma: Aliyeva Malika uchun 09.2026,10.2026 oy to'lovi hali yopilmagan (qarz: 5800000 so'm). Iltimos, to'lovni amalga oshiring. IQROR Academy
```

## Qarzdorga SMS eslatma («Moliya» → «Qarzdorlar» → «Eslatma») — `sms-remind.cjs`

Admin panelda tugma bosilganda: avval **ko‘rib chiqish** (`preview:true` — hech narsa yuborilmaydi), admin
oynada o‘quvchi, telefon, qarz, oylar va SMS matnini ko‘rib tasdiqlaydi, keyin yuboriladi.
- **Ruxsat:** faqat FAOL `director` / `finance_mgr` (`sms.remindRoles` bilan o‘zgartiriladi) — JWT + `users` jadvali.
- **Tinch soat:** `sms.sendHours` (shu `auth/config.json`da; standart `[9, 20]` — Toshkent 09:00–19:59). Oraliqdan tashqarida
  «Eslatma» rad etiladi (sababi oynada yoziladi). Avtomatik SMS (`payments/config.json` → `sms.sendHours`) alohida
  o‘qiladi — ikkalasini bir xil qo‘ying. `false` — cheklovsiz (tavsiya etilmaydi).
- **Bugun shu raqamga boshqa SMS ketgan bo‘lsa** (yangi faktura, aka-uka eslatmasi) — bloklanmaydi, tasdiq oynasida
  ogohlantiriladi (`phoneToday`).
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
  (`{month}` — qarzdor oylar bitta so‘z: `09.2026,10.2026`, ketma-ket 3+ oy `08.2026-10.2026`, uzilish bilan
  `05.2026,06.2026,08.2026-10.2026`; `{due}` — `5800000`). ⚠️ Bu matn ham Eskiz kabinetida **shablon sifatida tasdiqlangan** bo‘lishi shart — aks holda Eskiz rad
  etadi va admin panel shuni aniq aytadi (yuqoridagi «Eskiz SMS shabloni»: naqsh, ism moslash, `node eskiz-shablon.cjs`).
- `sms.dryRun: true` bo‘lsa — SMS ketmaydi, admin «SINOV rejimi» xabarini ko‘radi (jurnalga yozilmaydi); Eskiz naqshlari
  baribir o‘qiladi (faqat GET) — sinovdagi matn va ⚠️ ogohlantirish haqiqiy yuborishdagidek.

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
- Maydon `sb/auth-api.js` → `bindPhoneInput` bilan ulanadi: o‘rtadagi tuzatishda kursor joyida qoladi (raqamlar tartibi
  buzilib, boshqa yaroqli raqamga kod ketmaydi); to‘liq raqam nusxa qilib qo‘yilsa (ko‘rinmas belgilar bilan ham) — maydon
  shu raqam bilan almashtiriladi; `+998 ` ortidan yana `998…` yozilsa — aniq maslahat (`phoneHint`).

## config.json (maxfiy — gitga tushmaydi)

`serviceRoleKey`, `anonKey`, `auth.hmacSecret`, `sms.eskizEmail/eskizPassword` — barchasi MAXFIY.
`hmacSecret` ni yangilash eski ticketlar/OTP’larni bekor qiladi (xavfsiz, lekin faol oqimlar uziladi).
