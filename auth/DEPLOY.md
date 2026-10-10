# Telefon + parol + OTP auth — deploy va sozlash

Bu hujjat: **o'zgartirilgan/qo'shilgan fayllar**, **muhit o'zgaruvchilari (maxfiy kalitlar)**,
**deploy qadamlari**, **sinov** va **qolgan ochiq savollar**.

---

## 1) Qo'shilgan / o'zgartirilgan fayllar

**Yangi (auth server):**
- `auth/index.cjs` — auth HTTP serveri (request-otp / verify-otp / register / login / reset-confirm / change-phone-confirm).
- `auth/lib.cjs` — sof yordamchilar (telefon/parol/OTP hash/ticket).
- `auth/_fake.cjs`, `auth/auth.test.cjs` — birlik testlar (60 ta, tashqi xizmatsiz).
- `auth/config.example.json`, `auth/package.json`, `auth/README.md`, `auth/.gitignore`.

**Yangi (DB migratsiyalari):**
- `migration/auth-phone.sql` — `users`: phone/firstName/lastName/status + RLS qattiqlashtirish.
- `migration/otp-codes.sql` — `otp_codes` (mijozga yopiq).
- `migration/auth-login-attempts.sql` — `auth_login_attempts` + `otp_codes.uid` + `public.auth_uid_by_email` RPC.
- `migration/parent-student-links.sql` — `child_claims.status` (bog'lash o'zgarmaydi).
- `migration/test-auth-rls.sql` — RLS cross-rol testi (qo'lda ishga tushiriladi).

**Yangi (mijoz qatlami):**
- `sb/auth-api.js` — UI chaqiradigan modul (OTP/register/login/reset + validatorlar).

**Yangi (deploy):**
- `migration/deploy/iqror-auth.service` — systemd xizmati.

**O'zgartirilgan:**
- `index.html` — telefon+parol+OTP modali (ro'yxat/kirish/tiklash). Eski email/Google saqlanadi.
- `admin.html` — telefon YOKI email bilan kirish; pending-gate; «Foydalanuvchilar» tasdiqlash;
  «Profil» (ism/parol/telefon-OTP); o'quvchi kodini nusxalash.
- `migration/run-all.sql`, `deploy.sh` — yangi migratsiyalar + `sb/auth-api.js`.
- `migration/deploy/nginx.conf.example` — `/authapi/` proxy.

---

## 2) Muhit o'zgaruvchilari / maxfiy kalitlar

Barcha maxfiy kalitlar **serverda**, repoga tushmaydi (gitignore).

**`auth/config.json`** (`auth/config.example.json`dan nusxa):
| Kalit | Nima | Maxfiy? |
|---|---|---|
| `serviceRoleKey` | Supabase service_role (RLS chetlab) | ✅ ha |
| `anonKey` | Supabase anon (login/parol tekshiruvi) | ommaviy |
| `auth.hmacSecret` | OTP hash + ticket imzosi (`openssl rand -hex 32`) | ✅ ha |
| `auth.phoneEmailDomain` | sintetik email domeni (`phone.iqroacademy.uz`) | yo'q |
| `auth.otpTtlSec / otpMaxAttempts / otpResendSec / otpMaxPerHour` | OTP chegaralari | yo'q |
| `auth.loginMaxFails / loginLockMin` | login lockout | yo'q |
| `auth.otpTemplate` | SMS matni (`{code}`) — **Eskiz moderatsiyasi shart** | yo'q |
| `auth.corsOrigin` | ruxsat etilgan sayt origini (`https://iqroacademy.uz,...`) | yo'q |
| `sms.eskizEmail / eskizPassword` (yoki `sms.token`) | Eskiz hisobi | ✅ ha |

**`sb/sb-config.js`** (frontend, allaqachon mavjud): `SUPABASE_URL`, `SUPABASE_ANON_KEY`.
Auth bazasi `SUPABASE_URL` originidan olinadi (`<origin>/authapi`); boshqa bo'lsa — `window.IQROR_AUTH_BASE`.

> ⚠️ **Maxfiy kalitlarni menga (yoki repoga) YUBORMANG.** Ularni faqat serverда `config.json`ga qo'ying.

---

## 3) Deploy qadamlari

1. **Eskiz**: OTP shablonini (`IQROR Academy tasdiqlash kodi: {code}. Hech kimga bermang.`) kabinetда
   moderatsiyaga bering (1–2 kun). Tasdiqlanmasa kod yuborilmaydi.

2. **Kod + migratsiya** (VPS'da):
   ```bash
   cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl
   git checkout FETCH_HEAD -- admin.html index.html sb auth payments server migration deploy.sh
   bash deploy.sh          # SQL migratsiyalar + /sb (auth-api.js) + admin.html + index.html
   ```

3. **Auth serverni sozlash + ishga tushirish**:
   ```bash
   cd /opt/iqror/auth && cp config.example.json config.json   # to'ldiring (yuqoridagi jadval)
   npm install
   sudo cp ~/iqror-repo/migration/deploy/iqror-auth.service /etc/systemd/system/
   sudo systemctl daemon-reload && sudo systemctl enable --now iqror-auth
   curl -s http://127.0.0.1:8792/health     # -> ok
   ```

4. **nginx**: `/authapi/` blokini qo'shing (namuna `migration/deploy/nginx.conf.example`'da), so'ng:
   ```bash
   sudo nginx -t && sudo systemctl reload nginx
   ```

5. **Tekshirish**: saytда «Kirish» → telefon bilan ro'yxatdan o'ting (o'zingizning raqamingiz),
   kod kelishini, o'qituvchi «tasdiq kutmoqda» ekranini, admin panelда tasdiqlashni sinab ko'ring.

---

## 4) Sinov (hozir o'tgan)

- **Server birlik**: `cd auth && npm test` → 60/60 (ro'yxat, OTP muddati/xato/lockout, qayta-yuborish
  + soatlik limit, parol qoidalari, login lockout, parol tiklash, orphan reclaim, rol majburlash,
  telefon o'zgartirish).
- **Frontend (Chromium)**: telefon modali 26/26, profil modali 17/17 (maska, parol checklist, ko'z,
  OTP, pending/auto-login, tiklash). Konsol xatosiz.
- **RLS cross-rol (PG16)**: `migration/test-auth-rls.sql` — parent faqat o'zini/o'z farzandini ko'radi;
  otp/login jadvallari mijozga yopiq; **parent o'zini director, pending o'qituvchi o'zini tasdiqlay
  olmaydi**; admin ko'radi va tasdiqlaydi.
- **Migratsiyalar**: PG16 to'liq build toza, idempotent.

---

## 5) Xavfsizlik ko'rigi (bajarildi)

Adversarial xavfsizlik ko'rigi o'tkazildi (12 tasdiqlangan topilma). **Barcha CRITICAL/HIGH tuzatildi va
PG16'да tekshirildi** (`migration/test-auth-rls.sql`):

- **[CRITICAL] OTP brute-force (race)** — urinish sanog'i endi ATOMIK (`otp_consume`, FOR UPDATE):
  5-dan keyin to'g'ri kod ham o'tmaydi; ishlatilgan kod qayta ishlamaydi.
- **[CRITICAL] O'qituvchi self-insert eskalatsiyasi** — `users_ins` endi teacher'ni ruxsat BERMAYDI
  (oddiy user o'ziga role=teacher + sinf yoza olmaydi). O'qituvchi faqat server/admin tomonidan.
- **[HIGH] Tasdiqlanmagan o'qituvchi ma'lumot o'qishi** — `is_staff()`/`is_teacher_for_class()` endi
  `status='active'` talab qiladi: pending/blocked o'qituvchi (seansi bo'lsa ham) xodim/o'quvchi
  ro'yxatini RLS darajasida o'qiy olmaydi.
- **[MEDIUM] Login pending/blocked** — `login()` bunday hisobga token bermaydi.
- **[MEDIUM] SMS flood** — telefon (5/soat) + **IP (20/soat)** limitlari.
- **[LOW] Parol tiklash orakuli** — «yangi≠eski» sinovi (joriy parolni oshkor qilardi) RESET'дан
  olib tashlandi (profil «parolni o'zgartirish»да saqlanadi — u xavfsiz).
- **[LOW] Orphan reclaim** — register faqat HAQIQIY yetim (users qatori yo'q) auth hisobini o'chiradi
  (tirik hisobni buzmaydi). changePhone — users avval, auth keyin, xatoда orqaga qaytaradi.
- **[LOW] Admin telefon-login** — AuthAPI yuklanishini KUTADI (telefon email deb ketmaydi).

### Tavsiya etilgan qo'shimcha qattiqlashtirish (ixtiyoriy, kod emas — konfiguratsiya)

- **nginx `limit_req`** `/authapi/` uchun (ayniqsa `/authapi/login` va `/authapi/verify-otp`) — tarmoq
  darajasida brute-force/flood sekinlashtiradi. Masalan:
  ```nginx
  limit_req_zone $binary_remote_addr zone=authapi:10m rate=10r/s;
  location /authapi/ { limit_req zone=authapi burst=20 nodelay; proxy_pass http://127.0.0.1:8792/; ... }
  ```
- **GoTrue-direct login**: bizning login-lockout faqat `/authapi/login`ni qo'riqlaydi; sintetik email
  bilan to'g'ridan-to'g'ri Supabase GoTrue'ga ham urinish mumkin. Himoya: (a) parol bcrypt + murakkab
  (8+/katta/kichik/raqam); (b) Supabase GoTrue'ning o'z rate-limit sozlamalari; (c) pending/blocked hisob
  RLS'да hech narsa ko'rmaydi. Supabase loyiha sozlamalarida GoTrue rate-limit yoqilganini tekshiring.

## 6) Qolgan ochiq savollar / tavsiyalar

- **Eskiz shabloni** moderatsiyadan o'tishi kerak (yagona tashqi bog'liqlik).
- **Supabase ommaviy signup**: hozir yetim/squat hisob register'да avtomatik tiklanadi. Qo'shimcha
  qat'iylik uchun Supabase'да sintetik-email domeni uchun to'g'ridan-to'g'ri signup'ni o'chirish
  mumkin (ixtiyoriy; hozir shart emas).
- **O'qituvchi verified gate (RLS)**: hozir pending o'qituvchi login qila olsa ham, sinf
  biriktirilmagani uchun o'quvchi ma'lumotini ko'rolmaydi (RLS) + frontend «kutmoqda» ekrani.
  Agar xohlasangiz, RLS'да ham `verified` talab qilib qo'yish mumkin (keyingi qattiqlashtirish).
- **Mavjud email adminlar**: o'zgarishsiz ishlaydi (status bo'sh → gate ta'sir qilmaydi). Istasangiz
  ularga ham telefon biriktirish mumkin (Profil → telefon qo'shish; hozir faqat mavjud telefonni
  o'zgartirish bor — email-only hisobga telefon qo'shishni keyin qo'shsa bo'ladi).
