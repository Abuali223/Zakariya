# deploy/ — VPS ops fayllari (nginx, systemd, backup) + VPS spetsifikatsiyasi

Bu papka VPS bosqichini "kalit burab ishga tushadigan" qiladi. Barcha fayllar tayyor;
VPS'da nusxalab ishga tushirasiz.

## aHost VPS spetsifikatsiyasi (buyurtma uchun)

| Daraja | vCPU | RAM | SSD | Kimga |
|---|---|---|---|---|
| Minimal | 2 | **4 GB** | 60 GB | Bitta maktab (hozirgi holat) — ishlaydi |
| **Tavsiya** | 4 | **8 GB** | 80–100 GB | Zaxira + AI xizmati + o'sish uchun havotirsiz |

- **OS:** Ubuntu 22.04 LTS (yoki 24.04). Root/sudo.
- **Domen:** `iqror.uz` + `api.iqror.uz` (A-yozuv VPS IP'ga), SSL bepul (certbot).
- **Sabab:** Supabase to'liq to'plami (Postgres + Kong + Auth + Storage + Realtime +
  Studio) Docker'da ~4 GB RAM oladi; 8 GB — qulay zaxira.

## Fayllar
| Fayl | Vazifasi | Qayerga |
|---|---|---|
| `nginx.conf.example` | iqror.uz (statik) + api.iqror.uz (Supabase+AI+to'lov) reverse-proxy | `/etc/nginx/sites-available/iqror` |
| `iqror-ai.service` | AI yordamchi doimiy (systemd) | `/etc/systemd/system/` |
| `iqror-pay.service` | To'lov serveri doimiy (systemd) | `/etc/systemd/system/` |
| `backup.sh` | Zaxira: maktab ma'lumotlari (`public` + `app`, Supabase konteyneridagi pg_dump — parol kerak emas) + kirish hisoblari (`auth`) + Storage fayllari va metama'lumoti + **sirlar** (`.env`, `config.json`'lar, nginx, unit'lar); 60 kun saqlanadi | bir martalik: `bash ~/iqror-repo/migration/deploy/backup.sh` (→ `~/iqror-backups`); har kuni: `sudo crontab -e` → `30 22 * * * bash /home/ubuntu/iqror-repo/migration/deploy/backup.sh >> /var/log/iqror-backup.log 2>&1` (→ `/opt/iqror/backups`; server UTC'da 22:30 = Toshkent 03:30) |
| `RESTORE.md` | Zaxiradan tiklash (yangi serverda): sirlar, baza, auth, storage, xizmatlar, tekshirish ro'yxati, RTO jurnali, har chorak mashq | — |

## Tartib (qisqacha)
1. Supabase o'rnatish + schema/rls/import — `../supabase-setup.md`.
2. Frontend'ni `/var/www/iqror` ga, server kodni `/opt/iqror` ga qo'ying.
3. `switch-backend.cjs supabase` + `sb/sb-config.js` to'ldiring.
4. Server config'lar (`ai-assistant/config.json`, `payments/config.json`) — `backend:"supabase"`.
5. systemd: `iqror-ai`, `iqror-pay` — enable --now.
6. nginx + certbot (SSL).
7. `backup.sh` ni root crontab'ga (yuqoridagi qator). Zaxira fayllari faqat egasiga o'qiladi (600); ularni serverdan TASHQARIGA ham
   ko'chiring (`RCLONE_REMOTE`, pastda «Zaxira: 60 kun, sirlar, tashqi nusxa»). `backup.sh` fayllari (`db_*`, `auth_*`, `storage_*`,
   `storage_meta_*`, `secrets_*`) — 60 kundan (`KEEP_DAYS`), deploy arxivlari (`web_*`, `srv_*`) — 14 kundan eskisi o'chiriladi,
   faqat papkaning o'zida; qo'lda qo'yilgan boshqa fayllar va ichki papkalar tegilmaydi. Tiklash — `RESTORE.md`.
8. `../CUTOVER-CHECKLIST.md` bo'yicha to'liq sinov → cutover.

## To'liq deploy — tavsiya etilgan BITTA buyruq (`full-deploy.sh`)
Serverda oddiy foydalanuvchi sifatida (**sudo'siz**; parol so'ralsa — o'zingizniki), tinch paytda (tungi 03:30 zaxira vaqtida emas):
```bash
cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash migration/deploy/full-deploy.sh
```
Avval yangi `deploy.sh` va `migration/` olinadi — shuning uchun juda eski serverda ham (o'z-o'zini yangilay olmaydigan eski
`deploy.sh`) ishlaydi. `full-deploy.sh` tartibi:
1. **Oldindan tekshiruv (faqat o'qiydi):** baza konteyneri, xizmatlar (papka / yoqilgan / holat), diskdagi joy, uzoq
   tranzaksiyalar (60 s gacha kutadi), `predeploy-checks.sql` (to'qnashuvchi o'quvchi kalitlari, chetida bo'sh joyli kalitlar,
   takroriy maosh kalitlari, arvoh kodlar, ota-ona bog'lanishi holati, deploy qayta yozadigan qatorlar soni).
2. **Zaxiralar** → `/opt/iqror/backups` (root, 600): `backup.sh` — `db_*` (public+app) + `auth_*` (hisoblar va parol xeshlari;
   sessiya/token jadvallarining ma'lumotisiz; olinmasa faqat ogohlantiradi) + `storage_*` (rasm/video — papka topilmasa
   `⚠️ storage papkasi topilmadi` va xulosada «storage YO'Q»), `web_*` (`/var/www/iqror`), `srv_*` (xizmatlar kodi papkasi,
   `config.json`'lar bilan, `node_modules`'siz).
   Zaxira olinmasa — deploy **boshlanmaydi**.
3. **`deploy.sh`** (pastda). 4. **Keyingi tekshiruvlar:** sayt fayllari va server kodi fayl-ma-fayl shu versiya bilan solishtiriladi,
   bazadagi yangi obyektlar (har qatordagi «kutilgan N» bilan solishtiring: funksiyalar, ID qo'riqchilari, `change_log`
   triggerlari — 24, `camera_days` — 1), 7/7 «BIR XIL», xizmatlar va `/health`, Eskiz shablonlari (hech narsa yubormaydi),
   SMS cron va kunlik zaxira cron (yo'q bo'lsa o'zi o'rnatadi; cron xizmati va oxirgi tungi zaxira log'i tekshiriladi).

Natija: oxirgi qator `✅ TO'LIQ DEPLOY MUVAFFAQIYATLI` (chiqish kodi 0). `⚠️ … «!!» qatorlari bor` (kod 2) — deploy bajarilgan,
lekin `!!` bilan boshlangan qatorlarni ko'rib chiqing. `❌` (kod 1 yoki boshqa) — xabarni o'qing. Butun chiqish `~/iqror-deploy-<vaqt>.log`
da (600). **Deploy'dan keyin:** barcha kompyuter/telefonlardagi ochiq admin oynalarini yangilang (Ctrl+Shift+R) — eski ochiq oyna
ayrim kartalarni saqlay olmaydi (yangi ID qo'riqchilari).

Xato bo'lsa:
| Xabar | Nima bo'lgan | Nima qilish |
|---|---|---|
| `❌ … deploy BOSHLANMADI` | Oldindan tekshiruv to'xtatdi — baza, sayt, server kodi **o'zgarmagan** | Xabardagi «Tuzatish:» buyrug'ini bajaring, so'ng shu buyruqni qayta |
| `❌ SQL migratsiya xato … Sabab: … 20 soniyadan ko'p band` | Boshqa ulanish jadvalni band qilgan (lock timeout) — baza **o'zgarmagan** | Bir ozdan so'ng qayta ishga tushiring (xabardagi so'rov kim band qilganini ko'rsatadi) |
| `❌ SQL migratsiya xato` (boshqa sabab) | Tranzaksiya bekor — baza **o'zgarmagan** | Xabardagi fayl/ERROR va «To'liq log» yo'lini yuboring |
| `❌ Xizmat(lar) ishga tushmadi` | Baza, sayt, kod yangi; xizmat yiqilmoqda | `sudo journalctl -u <xizmat> -n 50 --no-pager` — sababni tuzatib qayta ishga tushiring |
| `⚠️ … 7/7 baza tekshiruvi FARQ topdi` | Deploy bajarilgan; prod'da repo'da yo'q obyekt bor | 🔴 qatorlar (ortiqcha RLS policy) — albatta hal qiling |

Orqaga qaytarish — avval faqat KOD (yangi baza eski sahifalarni ham qabul qiladi): `sudo tar -xzf /opt/iqror/backups/web_<vaqt>.tgz -C /var/www`;
server kodi — `full-deploy.sh` oxirida chiqqan `sudo tar -xzf …/srv_… -C /opt/iqror` buyrug'i, so'ng `sudo systemctl restart iqror-pay iqror-ai iqror-auth`.
Bazani zaxiradan tiklash oddiy emas (sxemalarni o'chirib tiklash, storage policy'larini qayta yaratish, deploy'dan keyingi yozuvlar
yo'qoladi) — faqat maslahatlashib.

### Deploy'dan keyingi ⚠️ / ℹ️ qatorlar — nima qilish
Buyruqlar oddiy foydalanuvchidan (ubuntu); `sudo` o'zi kerakli joyda. Kod bloklarini GitHub sahifasidan yoki shu fayldan nusxalang.

**`⚠️ kunlik zaxira cron yo'q`** — eng muhimi (zaxirasiz kun = yo'qolishi mumkin bo'lgan kun):
   *Endi `full-deploy.sh` cron yo'q bo'lsa uni O'ZI o'rnatadi* («✓ kunlik zaxira cron (root) O'RNATILDI»; `DB_CONT` /
   `BACKUP_DIR` standart bo'lmasa — qatorga yoziladi). Izohga olingan (`#`) qator — atayin o'chirilgan deb olinadi va qayta
   yoqilmaydi; umuman o'rnatmaslik: `IQROR_NO_BACKUP_CRON=1 bash migration/deploy/full-deploy.sh`. Kunlik zaxiraga kirish
   hisoblari (`auth_*.sql.gz` — xodim/ota-ona hisoblari, parol xeshlari; kirish tokenlari OLINMAYDI) ham kiradi. Quyidagi qo'lda
   yo'l — faqat deploy o'rnata olmagan bo'lsa (`!! … o'rnatib bo'lmadi`; `cron o'rnatilmagan` bo'lsa avval
   `sudo apt install -y cron && sudo systemctl enable --now cron`):
1. Bir marta, BITTA `sudo` bilan (root crontab'ning boshqa qatorlari saqlanadi; qayta ishlatsa ham takrorlanmaydi):
```bash
sudo sh -c '{ crontab -l 2>/dev/null | grep -av "migration/deploy/backup\.sh"; echo "30 22 * * * bash /home/ubuntu/iqror-repo/migration/deploy/backup.sh >> /var/log/iqror-backup.log 2>&1"; } | crontab - && crontab -l'
```
2. Cron muhitida (tor PATH bilan) hozir sinash — oxirgi qator `backup OK` bo'lishi kerak:
```bash
sudo env -i PATH=/usr/bin:/bin HOME=/root bash /home/ubuntu/iqror-repo/migration/deploy/backup.sh
```
   `docker buyrug'i topilmadi` / `baza topilmadi` chiqsa — repo'dagi `backup.sh` eski (cron PATH tuzatmasidan oldingi): avval
   `cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- migration/deploy/backup.sh`.
3. `systemctl is-active cron` — `active`; `date` — UTC (22:30 UTC = Toshkent 03:30; server Toshkent vaqtida bo'lsa — `30 3 * * *`).
   Ertasi kuni: `tail -n 3 /var/log/iqror-backup.log` — bugungi sana va `backup OK`. Zaxiralarni vaqti-vaqti bilan serverdan TASHQARIGA ham ko'chiring.

**O'qituvchi/xodim ID'si — PASPORT kabi.** ID'ni tizim beradi (`IQT-…` o'qituvchi, `IQX-…` xodim; yangi kartada maydon qulf,
qiymat «Saqlash»da bazadan qayta hisoblanadi), keyin u o'zgarmaydi — tahrirda ham, eski oyna / to'g'ridan API orqali ham (baza:
42501). Har berilgan ID `payroll_ids` reyestriga yoziladi va HECH QACHON qayta berilmaydi: o'qituvchi/xodim o'chirilsa (yoki
ishdan chiqsa, o'rniga boshqa odam kelsa) ham, yangi odam doim yangi raqam oladi (o'chirilganlarning maosh/avans tarixi, «xodim
farzandi» bog'lanishi va xodimga bog'langan login yorlig'idagi raqamlar ham hisobga olinadi). ID'lar katta-kichik harf va chetidagi
bo'shliqlardan (tab, NBSP ham) va ko'rinmas belgilardan (zero-width, bidi — nusxa-ko'chirishda qo'shiladi) qat'i nazar
solishtiriladi: «IQX-001» va «iqx-001 » — bitta ID (takroriy). Deploy reyestrni har
safar joriy ro'yxat + tarix bilan to'ldiradi (chiqishda «ID reyestri (payroll_ids): N ta ID …», «reyestrda yo'q joriy ID: 0»).
O'qituvchi xodimga aylansa (yoki aksincha) — yangi kartochka (yangi ID) ochiladi, eskisi «⏯️ Holat → Ishdan chiqqan» qilinadi;
eski ID unda qoladi va boshqa hech kimga berilmaydi.

**Oldindan tekshiruv 9-band — abadiy band bo'ladigan ID'lar.** Ro'yxatdagi raqamlar deploy'da reyestrga yoziladi va keyingi yangi
ID shulardan katta bo'ladi. G'alati (juda katta, masalan `IQT-999999999`) raqam chiqsa — deploy'dan OLDIN manbasini tuzating
(«qayerdan» ustuni): aks holda u yangi ID chegarasini abadiy ko'taradi (9 xonadan oshsa yangi ID berib bo'lmaydi). Reyestrga
allaqachon tushgan bo'lsa (faqat hech kimga BERILMAGAN, egasi ham, maosh/avans tarixi ham yo'q xato raqam uchun) — bitta
tranzaksiyada manba va reyestr yozuvi (raqamni o'zingiznikiga almashtiring):
```bash
sudo docker exec supabase-db psql -U postgres -d postgres -X -1 -v ON_ERROR_STOP=1 -c "update public.users set \"staffCode\" = null where \"staffCode\" = 'IQT-999999999'" -c "update public.student_private set \"teacherId\" = null where \"teacherId\" = 'IQT-999999999'" -c "delete from public.payroll_ids where id = 'IQT-999999999' and released_at is not null and row_id is null"
```

**Oldindan tekshiruv 3-band — takroriy o'qituvchi/xodim ID'lari** (ikki kishida bir xil ID; deploy chiqishida
`OGOHLANTIRISH: takroriy o'qituvchi/xodim ID «…»`): bu odamlarga maosh va avans berish BLOKLANGAN («Xodimlar davomati → Oylik»da
qizil «⛔ Takroriy ID» kartasi) — birinchi oylikdan OLDIN tuzating. Bu — BIR MARTALIK tuzatish (faqat bo'sh yoki takroriy ID
uchun; keyin yangi ID ham pasport kabi o'zgarmaydi). Admin panelda (deploy'dan keyin Ctrl+Shift+R), direktor yoki HR:
1. Juftlikdagi kartani «Tahrir» bilan oching: ID maydoni ostida qizil izoh va **«Yangi noyob ID berish»** tugmasi chiqadi → bosing
   (hech qachon berilmagan keyingi ID qo'yiladi; «Bekor» — qaytarish) → «Saqlash» → tasdiq oynasi «Bir martalik ID tuzatish:
   «IQX-001» → «IQX-0…» … Eski ID boshqa xodimda ham bor (takroriy) … o'sha ID'da qoladi» → OK.
2. O'qituvchi + xodim juftligida tugma prefiksi jadvaliga mos KELMAYDIGAN kartada chiqadi: `IQT-…` ikkalasida (masalan IQT-016)
   — xodim kartasida («Xodimlar» bo'limi), `IQX-…` ikkalasida — o'qituvchi kartasida. Prefiksi mos karta (IQT- — o'qituvchi, IQX- —
   xodim) ID'ni SAQLAYDI, unda sariq izoh shuni aytadi. Ikki xodim (yoki ikki o'qituvchi) juftligida (IQX-001) tugma ikkalasida
   bor — BIRINI tuzating, ikkinchisining kartasi o'zidan toza bo'ladi (ID'si qoladi).
3. Kimdir shu paytda shu ID'ni olgan bo'lsa — «… avval berilgan» xabari va yangi taklif qo'yiladi: yana «Saqlash».
4. Qayta tekshirish (faqat o'qiydi) — chiqishdagi «== 3)» jadvali bo'sh bo'lishi kerak (yoki «Oylik»dagi qizil karta yo'qoladi):
```bash
sudo docker exec -i supabase-db psql -U postgres -d postgres -X -P pager=off < ~/iqror-repo/migration/deploy/predeploy-checks.sql
```

**`⚠️ student_codes: N ta o'quvchisiz kod … avtomatik tozalanmadi` («Arvoh kodlar»)** — o'chirilgan o'quvchilardan qolgan ota-ona
kodlari, kaliti hech qaysi tirik o'quvchining id'si ham, studentId'si ham emas: zararsiz (to'lov serveri va ota-ona bog'lanishi
ularni ishlatmaydi; kaliti tirik o'quvchining studentId'siga teng kodlar — import dublikatlari — arvoh hisoblanmaydi va
TEGILMAYDI: to'lov serveri ular bilan to'lovni tirik bolaga biriktiradi). Hech narsa qilish shart emas. O'quvchilar ataylab
o'chirilgan bo'lsa (zaxiradan tiklash rejalashtirilmagan) va ⚠️ qatori chiqmasin desangiz — shu README bilan kelgan deploy'dan
KEYIN (`student_id_high_water` himoyasi kengaytirilgan: o'chirilgan bolaning ID'si yangi bolaga berilmaydi), bitta tranzaksiyada:
```bash
sudo docker exec supabase-db psql -U postgres -d postgres -X -1 -v ON_ERROR_STOP=1 -c 'select count(*) as "arvoh kodlar (oldin)" from public.student_codes sc where not exists (select 1 from public.students s where s.id = sc.id or s."studentId" = sc.id)' -c 'delete from public.student_codes sc where not exists (select 1 from public.students s where s.id = sc.id or s."studentId" = sc.id)' -c 'select count(*) as "arvoh kodlar (keyin)" from public.student_codes sc where not exists (select 1 from public.students s where s.id = sc.id or s."studentId" = sc.id)'
```

**SMS: `payments / sms-worker` sozlamasida Eskiz kaliti yo'q** — faqat avtomatik qarz / yangi faktura SMS'lari (sms-worker cron)
uchun kerak; «Eslatma» tugmasi va OTP auth serveri sozlamasidan ketadi. Kerak bo'lsa: `payments/config.json` nusxasini oling
(`sudo cp … config.json.bak`), `sms.eskizEmail`/`sms.eskizPassword` ni auth sozlamasidagi qiymatlar bilan yozing, diagnostika
ko'rsatgan JSON tekshiruvidan o'tkazing va cron qo'ying (`payments/README.md` §7.4). Kalit va parollarni hech kimga yubormang.

Faqat deploy (zaxira va tekshiruvlarsiz): `bash ~/iqror-repo/deploy.sh` — kod (o'zini ham) + paketlar + oldindan tekshiruv (xizmat
kodi papkasi — bazaga tegishdan OLDIN) + SQL (bitta tranzaksiya) + `/sb` + sahifalar + server kodi + xizmatlar + 7/7 baza tekshiruvi.

## Zaxira: 60 kun, sirlar, shifrlash, tashqi nusxa (`backup.sh`)
Har tungi zaxira (`/opt/iqror/backups`, root, 600): `db_*` (public+app), `auth_*` (hisoblar, parol xeshlari; seans/token
ma'lumotisiz), `storage_*` (rasm/video fayllari), `storage_meta_*` (fayllar yozuvi — busiz rasmlarni tiklab bo'lmaydi),
`secrets_*` (Supabase `/opt/iqror/supabase/docker/.env`, `/opt/iqror/{auth,payments,ai-assistant}/config.json`, `sb-config.js`,
`/etc/nginx/sites-available/iqror`, `/etc/systemd/system/iqror-*.service`). Topilmagan fayl NOMI logga yoziladi
(`sirlar: topilmadi …`) — ichidagi qiymatlar hech qachon logga chiqmaydi. Oxirgi qator: `backup OK -> … + auth + storage +
storage metama’lumoti + sirlar (N fayl…)`. Sozlash (cron qatorida `O'ZGARUVCHI=qiymat bash …/backup.sh` ko'rinishida):

| O'zgaruvchi | Standart | Nima |
|---|---|---|
| `KEEP_DAYS` | `60` | necha kun saqlanadi |
| `SUPA_ENV` / `SRV_DIR` / `WEB_DIR` / `NGINX_SITE` / `UNIT_DIR` | `/opt/iqror/supabase/docker/.env` / `/opt/iqror` / `/var/www/iqror` / `/etc/nginx/sites-available/iqror` / `/etc/systemd/system` | sirlar yo'llari (server tuzilishi boshqacha bo'lsa) |
| `SECRETS_EXTRA` | — | qo'shimcha fayllar (bo'shliq bilan) |
| `BACKUP_GPG_RECIPIENT` | — | sirlar faylini gpg ochiq kaliti bilan shifrlash (`secrets_*.tar.gz.gpg`; yopiq kalit serverda EMAS — direktor kompyuterida) |
| `BACKUP_PASSFILE` | — | yoki parol fayli (600) bilan openssl aes-256 (`secrets_*.tar.gz.enc`; parolni server tashqarisida ham saqlang) |
| `RCLONE_REMOTE` | — | tashqi nusxa: `rclone copy` (shifrlangan «crypt» remote tavsiya etiladi; xato bo'lsa — ogohlantirish, lokal zaxira saqlanadi) |

Shifrlash so'ralgan-u, bajarilmasa (kalit/parol fayli yo'q) — sirlar fayli ochiq holda SAQLANMAYDI (ogohlantirish). Tashqi nusxa
sozlash: `sudo apt install -y rclone && sudo rclone config` (masalan Google Drive yoki S3 + ustidan «crypt»), so'ng cron qatorida
`RCLONE_REMOTE=iqrorcrypt:zaxira`. Har chorak tiklash mashqi — `RESTORE.md` §11.

## Tashqi kuzatuv (UptimeRobot) va Telegram ogohlantirish
Server o'zini o'zi kuzatolmaydi (o'chib qolsa — xabar ham yubormaydi). Bepul tashqi xizmat (UptimeRobot yoki shunga o'xshash —
Better Stack, Freshping) har 5 daqiqada 4 manzilni tekshiradi:

| Manzil | Kutilgan javob |
|---|---|
| `https://<sayt>/` | 200 (sahifa) |
| `https://<sayt>/authapi/health` | 200 `ok` (kirish, SMS kod) |
| `https://api.<sayt>/pay/health` | 200 `ok` (Click/Uzum to'lovlari) |
| `https://api.<sayt>/ai/health` | 200 `{"ok":true…}` (AI yordamchi; o'rnatilmagan bo'lsa — qo'shmang) |

1. uptimerobot.com'da hisob oching (maktab emaili bilan) → «Add New Monitor» → turi **HTTP(s)**, manzil, interval **5 daqiqa**;
   ikkinchi manzil uchun «Keyword» turi (`ok` so'zi) ham mumkin. To'rtala manzilni qo'shing.
2. **Telegram — ikki kishiga** (masalan direktor va texnik xodim): kuzatuv xizmatining «Alert contacts / Integrations» bo'limida
   Telegram'ni tanlang — u bot havolasini beradi; HAR BIR odam o'z Telegram'ida shu havolani ochib «Start» bosadi (har biri alohida
   kontakt bo'lib qo'shiladi). Har monitorga ikkala kontaktni biriktiring. Sinov: monitorni bir daqiqaga «Pause»/noto'g'ri manzil
   qilib xabar kelishini tekshiring, so'ng qaytaring.
3. Xabar kelsa: admin panel → Sozlamalar → **🩺 Tizim holati** (qaysi xizmat qizil), serverda `systemctl status iqror-auth iqror-pay iqror-ai`,
   `sudo journalctl -u <xizmat> -n 50 --no-pager`. Ommaviy `/health` faqat «ok» qaytaradi — hech qanday ma'lumot ochilmaydi.

## Tozalash ishlari (OTP / login urinishlari) va jurnal (journald) hajmi
- `otp_codes` va `auth_login_attempts` jadvallari har ro'yxat/kirishda o'sadi; `app.otp_gc()` va `app.login_attempts_gc()` (bazada bor)
  1 kundan eski yozuvlarni o'chiradi. `full-deploy.sh` root crontab'ga kunlik qatorni O'ZI qo'shadi (22:50 server vaqti; marker
  `# iqror-auth-gc` — bor bo'lsa, izohga olingan bo'lsa ham, qayta qo'shilmaydi; o'rnatmaslik: `IQROR_NO_GC_CRON=1`). Qo'lda:
```bash
sudo sh -c '{ crontab -l 2>/dev/null | grep -av "iqror-auth-gc"; echo "50 22 * * * PATH=/usr/local/bin:/usr/bin:/bin:/snap/bin docker exec supabase-db psql -U postgres -d postgres -X -q -c '"'"'select app.otp_gc()'"'"' -c '"'"'select app.login_attempts_gc()'"'"' >/dev/null 2>&1 # iqror-auth-gc (OTP/login tozalash — full-deploy.sh)"; } | crontab - && crontab -l | grep iqror-auth-gc'
```
  Hozir bir marta tekshirish: `sudo docker exec supabase-db psql -U postgres -d postgres -c 'select app.otp_gc()' -c 'select app.login_attempts_gc()'`.
- **journald** (xizmatlar jurnali) diskni to'ldirmasin — 500 MB chegara:
```bash
sudo mkdir -p /etc/systemd/journald.conf.d && printf '[Journal]
SystemMaxUse=500M
' | sudo tee /etc/systemd/journald.conf.d/iqror.conf
sudo systemctl restart systemd-journald && journalctl --disk-usage
```
  Zaxira log'i (`/var/log/iqror-backup.log`) kichik — kuniga bir necha qator.

## nginx: mijoz IP'si, /authapi/ so'rov chegarasi, gzip (`nginx.conf.example`)
- `/authapi/`, `/pay/`, `/ai/` uchun `proxy_set_header X-Real-IP $remote_addr;` (va `X-Forwarded-For $remote_addr`) — auth-server
  OTP limitini HAQIQIY mijoz IP'si bo'yicha hisoblaydi (maktab IP'si — `auth/README.md`, `otpTrustedIps`).
- `limit_req_zone … zone=iqror_authapi rate=10r/s` (fayl boshida, http darajasi) + `/authapi/` ichida `limit_req … burst=20 nodelay` —
  OTP/login «bombardimon»ini tarmoq darajasida sekinlashtiradi (oshsa 429).
- `gzip on` (server{} ichida — Ubuntu nginx.conf'idagi `gzip on;` bilan «duplicate» xatosi bermaydi): HTML, CSS, JS, JSON, SVG.
- Sayt `/authapi/` ga O'Z domenidan murojaat qiladi — `location /authapi/` sayt server{} blokida ham bo'lishi kerak (namunada bor).
- Qo'llash: namunadan kerakli qatorlarni `/etc/nginx/sites-available/iqror` ga ko'chiring → `sudo nginx -t && sudo systemctl reload nginx`.

## Xizmat papkasi (WorkingDirectory) — deploy yangi server kodini ishga tushirishi uchun
`deploy.sh` kodni **`~/iqror-repo`** da yangilaydi (git). Namuna unit'lar (`iqror-*.service`) esa
`WorkingDirectory=/opt/iqror` dan ishlaydi. Shuning uchun `deploy.sh` (6-bosqich) har xizmatning
`WorkingDirectory`'sini tekshiradi: u repo bo'lmasa va server kodi papkasiga o'xshasa (`payments/`, `ai-assistant/`
yoki `auth/` bor) — **server kodini o'sha papkaga ham yozadi** (faqat git'dagi fayllar: `ai-assistant payments server sb auth`).
`config.json`, `node_modules`, `backups/`, `supabase/` va boshqa fayllar **tegilmaydi** (egasi va ruxsatlari ham — maxfiy
`config.json`'ni 0600 qilib qo'ygan bo'lsangiz, shunday qoladi); yangi/yangilangan kod fayllari `payments/` papkasi egasi nomidan
yoziladi (ruxsatlari 0644/0755 — tizim umask'iga bog'liq emas), mavjud papkalarning egasi/ruxsati o'zgarmaydi; yo'q papkalar
(birinchi marta `auth/`, `sb/`) shu egasi nomiga yaratiladi. Bularning hammasi **bazaga tegishdan OLDIN** (2-bosqichda, `sudo`
bilan — `/opt/iqror` 0750 bo'lsa ham) tekshiriladi: egasi yoza olmaydigan kod papkasi (masalan qo'lda `sudo cp -r` qilingan root
egali `server/`) yoki server kodiga o'xshamaydigan `WorkingDirectory` bo'lsa — deploy **boshlanmaydi** va tuzatish buyrug'ini
ko'rsatadi (`sudo chown -R iqror:iqror …` yoki `sudo chmod o+x /opt/iqror`). Hech narsa qilish shart emas — deploy chiqishida
«… kodi /opt/iqror dan ishlaydi — server kodi o'sha yerga ham yozilmoqda» qatorini ko'rasiz.

Tekshirish (ixtiyoriy): `systemctl show -p WorkingDirectory iqror-pay` va deploy'dan keyin
`sudo journalctl -u iqror-pay -n 20 --no-pager` (xatosiz ishga tushganini ko'rish).

> ⚠️ Unit'larni `WorkingDirectory=/home/<siz>/iqror-repo` ga o'zgartirmang va `/opt/iqror` ni ko'chirmang/symlink
> qilmang: `User=iqror` uy papkangizni o'qiy olmaydi (Ubuntu'da 0750) — xizmatlar ishga tushmay qoladi; `/opt/iqror`
> ichida esa zaxiralar (`backup.sh`) va Supabase fayllari bo'lishi mumkin.
