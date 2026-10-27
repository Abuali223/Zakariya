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
| `backup.sh` | Zaxira: maktab ma'lumotlari (`public` + `app`, Supabase konteyneridagi pg_dump — parol kerak emas) + Storage | bir martalik: `bash ~/iqror-repo/migration/deploy/backup.sh` (→ `~/iqror-backups`); har kuni: `sudo crontab -e` → `30 22 * * * bash /home/ubuntu/iqror-repo/migration/deploy/backup.sh >> /var/log/iqror-backup.log 2>&1` (→ `/opt/iqror/backups`; server UTC'da 22:30 = Toshkent 03:30) |

## Tartib (qisqacha)
1. Supabase o'rnatish + schema/rls/import — `../supabase-setup.md`.
2. Frontend'ni `/var/www/iqror` ga, server kodni `/opt/iqror` ga qo'ying.
3. `switch-backend.cjs supabase` + `sb/sb-config.js` to'ldiring.
4. Server config'lar (`ai-assistant/config.json`, `payments/config.json`) — `backend:"supabase"`.
5. systemd: `iqror-ai`, `iqror-pay` — enable --now.
6. nginx + certbot (SSL).
7. `backup.sh` ni root crontab'ga (yuqoridagi qator). Zaxira fayllari faqat egasiga o'qiladi (600); ularni vaqti-vaqti bilan serverdan TASHQARIGA ham ko'chiring.
   14 kundan eskisi o'chiriladi — faqat skriptlarning o'z fayllari (`db_*`, `storage_*`, `auth_*`, `web_*`, `srv_*`) papkaning o'zida;
   qo'lda qo'yilgan boshqa fayllar va ichki papkalar tegilmaydi.
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
2. **Zaxiralar** → `/opt/iqror/backups` (root, 600): `db_*` (public+app) + `storage_*` (`backup.sh`), `auth_*` (auth sxemasi —
   olinmasa faqat ogohlantiradi), `web_*` (`/var/www/iqror`), `srv_*` (xizmatlar kodi papkasi, `config.json`'lar bilan, `node_modules`'siz).
   Zaxira olinmasa — deploy **boshlanmaydi**.
3. **`deploy.sh`** (pastda). 4. **Keyingi tekshiruvlar:** sayt fayllari va server kodi fayl-ma-fayl shu versiya bilan solishtiriladi,
   bazadagi yangi obyektlar (5 / 1 / 7), 7/7 «BIR XIL», xizmatlar va `/health`, Eskiz shablonlari (hech narsa yubormaydi), cron'lar.

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
- **`⚠️ kunlik zaxira cron yo'q`** — bir marta (root crontab'ning boshqa qatorlari saqlanadi, qayta ishlatsa ham takrorlanmaydi):
  ```bash
  sudo -v && { sudo crontab -l 2>/dev/null | grep -v "migration/deploy/backup\.sh"; echo "30 22 * * * bash /home/ubuntu/iqror-repo/migration/deploy/backup.sh >> /var/log/iqror-backup.log 2>&1"; } | sudo crontab - && sudo crontab -l
  ```
  Cron muhitida ishlashini hozir tekshirish (cron'dagi kabi tor PATH bilan; oxirgi qator `backup OK`):
  `sudo env -i PATH=/usr/bin:/bin HOME=/root bash /home/ubuntu/iqror-repo/migration/deploy/backup.sh`
- **Oldindan tekshiruv 3-band (takroriy maosh kalitlari)** — ikki xodim/o'qituvchida bir xil ID: birinchi maosh/avans berilganda
  ikkalasiniki aralashadi. Tuzatish (admin panel, Ctrl+Shift+R dan keyin): «+ Qo'shish» oynasi ID maydonida taklif qilgan
  keyingi bo'sh ID'ni eslab, oynani yoping → takroriy juftlikning BIRINING kartasini oching → ID maydoniga shu ID → «Saqlash» →
  tasdiqda «eski ID boshqa xodimda ham bor (takroriy) … ESKI ID'da qoladi» — shu kutilgan (maosh/avans tarixi bo'lsa, u eski
  ID egasida qoladi). O'qituvchi bilan xodimda bir xil `IQT-` ID bo'lsa — xodimnikini `IQX-` ga o'zgartiring («xodim farzandi»
  bog'lanishi faqat o'qituvchiga bo'ladi). Qayta tekshirish: yuqoridagi `predeploy-checks.sql` — 3-band bo'sh.
- **`⚠️ student_codes: N ta o'quvchisiz kod … avtomatik tozalanmadi` («Arvoh kodlar»)** — o'chirilgan o'quvchilardan qolgan
  ota-ona kodlari: zararsiz (to'lov serveri ham, ota-ona bog'lanishi ham faqat MAVJUD o'quvchi qatori orqali ishlaydi). O'quvchilar
  ataylab o'chirilgan bo'lsa (zaxiradan tiklash rejalashtirilmagan bo'lsa) — deploy'ning o'zi qiladigan tozalash, chegarasiz:
  ```bash
  sudo docker exec -i supabase-db psql -U postgres -d postgres -X -v ON_ERROR_STOP=1 <<'SQL'
  begin;
  select count(*) as "arvoh kodlar (oldin)" from public.student_codes sc where not exists (select 1 from public.students s where s.id = sc.id);
  delete from public.student_codes sc where not exists (select 1 from public.students s where s.id = sc.id);
  select count(*) as "arvoh kodlar (keyin)" from public.student_codes sc where not exists (select 1 from public.students s where s.id = sc.id);
  commit;
  SQL
  ```
- **SMS: `payments / sms-worker` sozlamasida Eskiz kaliti yo'q** — faqat avtomatik qarz/yangi faktura SMS'lari (sms-worker cron)
  uchun kerak; «Eslatma» tugmasi va OTP auth serveri sozlamasidan ketadi. Kerak bo'lsa — `payments/config.json` ga
  `sms.eskizEmail`/`sms.eskizPassword` va cron (`payments/README.md` §7.4).

Faqat deploy (zaxira va tekshiruvlarsiz): `bash ~/iqror-repo/deploy.sh` — kod (o'zini ham) + paketlar + oldindan tekshiruv (xizmat
kodi papkasi — bazaga tegishdan OLDIN) + SQL (bitta tranzaksiya) + `/sb` + sahifalar + server kodi + xizmatlar + 7/7 baza tekshiruvi.

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
