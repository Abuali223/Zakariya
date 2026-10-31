# Zaxiradan tiklash (RESTORE) — server yo'qolsa yoki buzilsa

Bu hujjat `backup.sh` olgan zaxiradan maktab tizimini **yangi (bo'sh) serverda** qayta qurish tartibi. Buyruqlar Ubuntu
serverda, oddiy foydalanuvchidan (`ubuntu`), kerakli joyda `sudo` bilan. **Avval mashq qiling** (pastda «Har chorak mashq»):
haqiqiy avariya kuni birinchi marta o'qiladigan yo'riqnoma ishlamay qolishi mumkin.

> ⚠️ Zaxira fayllarida shaxsiy ma'lumot (JSHSHIR, telefon, manzil), parol xeshlari va kalitlar bor. Ularni faqat root
> o'qiydigan joyda (600) saqlang, ochiq kanallarga (Telegram, email) yubormang. Tiklash tugagach vaqtinchalik papkalarni o'chiring.

Maqsad (RTO — tizim qancha vaqtda qayta ishlaydi): **4 soat** ichida. Haqiqiy natijani pastdagi jadvalga yozing.

## 1. Kerakli fayllar (bir xil vaqt belgisi `<vaqt>`, masalan `20261031_223001`)

| Fayl | Ichida | Kerak bo'ladi |
|---|---|---|
| `db_<vaqt>.sql.gz` | maktab ma'lumoti: `public` + `app` sxemalari (jadvallar, funksiyalar, RLS, ma'lumot) | 5-qadam |
| `auth_<vaqt>.sql.gz` | kirish hisoblari (`auth` sxemasi, parol xeshlari; seans/token ma'lumotisiz) | 6-qadam |
| `storage_meta_<vaqt>.sql.gz` | rasm/video yozuvlari (`storage.buckets`, `storage.objects`) | 7-qadam |
| `storage_<vaqt>.tar.gz` | rasm/video fayllarining o'zi | 7-qadam |
| `secrets_<vaqt>.tar.gz` (`.gpg` / `.enc`) | Supabase `.env`, `auth`/`payments`/`ai-assistant` `config.json`, `sb-config.js`, nginx sayt sozlamasi, `iqror-*.service` | 3-qadam |

Joyi: serverda `/opt/iqror/backups` (server butunlay yo'qolgan bo'lsa — tashqi nusxa: `RCLONE_REMOTE`, kompyuter/disk).
Eng oxirgi to'liq to'plamni tanlang (`backup OK` yozilgan kun: `/var/log/iqror-backup.log`). Butunligini tekshiring:
```bash
cd /joy/zaxira && for f in db_<vaqt>.sql.gz auth_<vaqt>.sql.gz storage_meta_<vaqt>.sql.gz storage_<vaqt>.tar.gz; do gzip -t "$f" && echo "OK $f"; done
gzip -dc db_<vaqt>.sql.gz | tail -n 3      # «PostgreSQL database dump complete» bo'lishi shart
```
Shifrlangan sirlar fayli uchun KALIT kerak: `.gpg` — yopiq gpg kaliti (serverda emas — direktor kompyuteri/USB'da saqlanadi),
`.enc` — `BACKUP_PASSFILE`dagi parol (u ham server tashqarisida saqlanishi shart). Kalit yo'qolsa — sirlarni tiklab bo'lmaydi.

## 2. Yangi serverni tayyorlash
1. Ubuntu 22.04/24.04, `docker`, `git`, `nginx`, `certbot`, `cron`, Node.js (`/usr/bin/node`) — `../supabase-setup.md` §1.
2. Domen A-yozuvlarini yangi IP'ga o'tkazing (DNS tarqalishi vaqt oladi — birinchi qilinadigan ish).
3. Xizmat foydalanuvchisi va papkalar: `sudo useradd -r -m -d /opt/iqror -s /usr/sbin/nologin iqror` (bor bo'lsa — o'tkazing),
   `sudo mkdir -p /opt/iqror/backups /var/www/iqror`.
4. Supabase: `cd /opt/iqror && sudo git clone --depth 1 https://github.com/supabase/supabase && cd supabase/docker && sudo cp .env.example .env`
   — `.env`ni HOZIR TO'LDIRMANG: 3-qadamda zaxiradagi `.env` qo'yiladi (eski kalitlar bilan — saytdagi `sb-config.js` va xizmatlar
   `config.json`idagi kalitlar o'zgarmasdan ishlaydi). Imkon bo'lsa eski server bilan bir xil Supabase versiyasini oling.
5. Repo: `cd ~ && git clone <repo manzili> iqror-repo`.

## 3. Sirlarni tiklash
```bash
sudo install -d -m 700 /root/iqror-restore
# shifrlanmagan:
sudo tar -xzf secrets_<vaqt>.tar.gz -C /root/iqror-restore
# gpg bilan shifrlangan (yopiq kalit import qilingan kompyuterda yoki serverda):
gpg --decrypt secrets_<vaqt>.tar.gz.gpg | sudo tar -xzf - -C /root/iqror-restore
# parol fayli bilan (openssl):
sudo sh -c 'openssl enc -d -aes-256-cbc -pbkdf2 -pass file:/root/backup-pass -in secrets_<vaqt>.tar.gz.enc | tar -xzf - -C /root/iqror-restore'
sudo find /root/iqror-restore -type f      # fayllar asl yo'llari bilan: opt/iqror/..., etc/nginx/..., etc/systemd/system/...
```
Joy-joyiga qo'ying (egalari va ruxsatlari bilan):
```bash
R=/root/iqror-restore
sudo cp $R/opt/iqror/supabase/docker/.env /opt/iqror/supabase/docker/.env && sudo chmod 600 /opt/iqror/supabase/docker/.env
for s in auth payments ai-assistant; do [ -f $R/opt/iqror/$s/config.json ] && sudo install -D -o iqror -g iqror -m 600 $R/opt/iqror/$s/config.json /opt/iqror/$s/config.json; done
[ -f $R/var/www/iqror/sb/sb-config.js ] && sudo install -D -m 644 $R/var/www/iqror/sb/sb-config.js /var/www/iqror/sb/sb-config.js
sudo install -m 644 $R/etc/nginx/sites-available/iqror /etc/nginx/sites-available/iqror
sudo install -m 644 $R/etc/systemd/system/iqror-*.service /etc/systemd/system/ && sudo systemctl daemon-reload
```
Zaxirada «topilmadi» deb yozilgan fayl bo'lsa (`/var/log/iqror-backup.log` — `sirlar: topilmadi`) — o'sha faylni
`config.example.json`dan qo'lda to'ldiring (kalitlarni tegishli kabinetdan: Eskiz, Click/Uzum, Anthropic).

## 4. Supabase'ni ishga tushirish
```bash
cd /opt/iqror/supabase/docker && sudo docker compose up -d && sudo docker compose ps     # hammasi running/healthy
```

## 5. Baza (maktab ma'lumoti: public + app)
Faqat **yangi, bo'sh** bazaga (unda `public` jadvallari yo'q — deploy.sh hali ishga tushirilmagan). Zaxirada `public` sxemasini
yaratish qatori bor — Supabase uni allaqachon yaratgan, shu qator olib tashlanadi:
```bash
gzip -dc db_<vaqt>.sql.gz | sed -e '/^CREATE SCHEMA public;$/d' -e '/^ALTER SCHEMA public OWNER TO /d' \
  | sudo docker exec -i supabase-db psql -U postgres -d postgres -X -q -v ON_ERROR_STOP=1
sudo docker exec supabase-db psql -U postgres -d postgres -At -c 'select count(*) from public.students' -c 'select count(*) from public.users'
```
Xato chiqsa (`already exists` — baza bo'sh emas) — TO'XTANG va maslahatlashing (yarim tiklangan bazaga deploy qilmang).
Eslatma: tiklashda Supabase'ning standart huquqlari (anon/authenticated'ga keng GRANT) qaytib qoladi — 8-qadamdagi `deploy.sh`
migratsiya zanjirini qayta qo'llab, ularni asl holiga keltiradi (RLS esa tiklangan zahotiyoq ishlaydi). Shuning uchun 8-qadamni
o'tkazib yubormang.

## 6. Kirish hisoblari (xodim va ota-ona loginlari, parollar)
Yangi Supabase `auth` jadvallarini o'zi yaratgan (bo'sh). Zaxira avval VAQTINCHALIK bazaga yuklanadi, so'ng undan faqat
foydalanuvchilar ma'lumoti asosiy bazaga ko'chiriladi (qayta ishga tushirsa ham takrorlanmaydi):
```bash
sudo docker exec supabase-db createdb -U postgres iqror_restore_tmp
gzip -dc auth_<vaqt>.sql.gz | sed '/^ALTER .* OWNER TO /d' | sudo docker exec -i supabase-db psql -U postgres -d iqror_restore_tmp -X -q -v ON_ERROR_STOP=1
sudo docker exec supabase-db sh -c 'pg_dump -U postgres -d iqror_restore_tmp --data-only --column-inserts --on-conflict-do-nothing --table=auth.users --table=auth.identities | psql -U postgres -d postgres -X -q -v ON_ERROR_STOP=1'
sudo docker exec supabase-db dropdb -U postgres iqror_restore_tmp
sudo docker exec supabase-db psql -U postgres -d postgres -At -c 'select count(*) from auth.users'
cd /opt/iqror/supabase/docker && sudo docker compose restart auth
```
Seanslar tiklanmaydi (ataylab) — hamma bir marta qayta kiradi. Bloklangan hisoblar bloklangan holicha qoladi (`users.status`).

## 7. Rasm va videolar (storage)
Avval yozuvlar (metama'lumot), keyin fayllar:
```bash
gzip -dc storage_meta_<vaqt>.sql.gz | sudo docker exec -i supabase-db psql -U postgres -d postgres -X -q -v ON_ERROR_STOP=1
cd /opt/iqror/supabase/docker && sudo docker compose stop storage
sudo tar -xzf storage_<vaqt>.tar.gz -C /opt/iqror/supabase/docker/volumes/storage
sudo docker compose start storage
```

## 8. Server kodi, sayt va xizmatlar
```bash
cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration
bash deploy.sh        # migratsiya zanjiri (tiklangan bazaga ham xavfsiz), sayt, /sb, server kodi -> /opt/iqror
for s in auth payments ai-assistant; do (cd /opt/iqror/$s && sudo -u iqror npm install --omit=dev); done
sudo systemctl enable --now iqror-auth iqror-pay iqror-ai
sudo ln -sf /etc/nginx/sites-available/iqror /etc/nginx/sites-enabled/iqror && sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d <sayt> -d www.<sayt> -d api.<sayt>      # SSL sertifikatlari zaxirada yo'q — qayta olinadi
bash migration/deploy/full-deploy.sh   # zaxira va tozalash cron'larini o'rnatadi, hammasini tekshiradi (oxirgi qator ✅)
```

## 9. Tekshirish ro'yxati (hammasi ✓ bo'lmaguncha «tiklandi» demang)
- ☐ `curl -s https://<sayt>/authapi/health` → `ok`; `curl -s https://api.<sayt>/pay/health` → `ok`; `…/ai/health` → `{"ok":true…}`
- ☐ Admin panel: direktor kiradi; **Sozlamalar → 🩺 Tizim holati** — qizil qator yo'q (zaxira qatori ertasi kungacha qizil bo'lishi mumkin)
- ☐ O'quvchilar, xodimlar soni zaxira vaqtidagi bilan bir xil; oxirgi to'lov va hisob-fakturalar zaxira vaqtiga mos
- ☐ Ota-ona telefon+parol bilan kiradi va farzandini ko'radi; o'qituvchi o'z sinfini ko'radi
- ☐ Rasmlar (o'quvchi surati, sayt rasmlari) ochiladi
- ☐ OTP SMS keladi (o'z raqamingiz bilan «Parolni tiklash»); «Qarzdorlar → Eslatma» ko'rib chiqish oynasi ochiladi
- ☐ Click/Uzum kabinetida webhook manzili yangi serverga ishlayapti (sinov to'lovi yoki provayder tekshiruvi)
- ☐ Ertasi kuni: `sudo tail -n 3 /var/log/iqror-backup.log` — `backup OK`; tashqi kuzatuv (UptimeRobot) yashil
- ☐ `/root/iqror-restore` va vaqtinchalik nusxalar o'chirildi: `sudo rm -rf /root/iqror-restore`

## 10. RTO jurnali (har mashq va har haqiqiy tiklashdan keyin to'ldiring)

| Sana | Kim | Turi (mashq / haqiqiy) | Boshlandi | Tugadi | RTO (daqiqa) | Muammo / izoh |
|---|---|---|---|---|---|---|
| | | | | | | |

## 11. Har chorak mashq (30 daqiqa, ishlayotgan tizimga tegmaydi)
1. **Baza zaxirasi o'qiladimi** — ishlayotgan serverda VAQTINCHALIK bazaga yuklab ko'rish (asosiy bazaga tegmaydi):
```bash
F=$(sudo ls -t /opt/iqror/backups/db_*.sql.gz | head -n 1); echo "$F"
sudo docker exec supabase-db createdb -U postgres iqror_drill
sudo docker exec supabase-db psql -U postgres -d iqror_drill -q -c 'create schema if not exists extensions; create extension if not exists pgcrypto with schema extensions'
sudo sh -c "gzip -dc $F" | sed -e '/^CREATE SCHEMA public;$/d' -e '/^ALTER SCHEMA public OWNER TO /d' \
  | sudo docker exec -i supabase-db psql -U postgres -d iqror_drill -X -q -v ON_ERROR_STOP=1 && echo "MASHQ: baza zaxirasi OK"
sudo docker exec supabase-db psql -U postgres -d iqror_drill -At -c 'select count(*) from public.students' -c 'select max("createdAt") from public.payments'
sudo docker exec supabase-db psql -U postgres -d postgres -At -c 'select count(*) from public.students'     # jonli baza bilan solishtiring
sudo docker exec supabase-db dropdb -U postgres iqror_drill
```
2. **Sirlar fayli ochiladimi** — kalit/parol haqiqatan qo'lingizdami: `sudo tar -tzf …secrets_<vaqt>.tar.gz` (yoki `gpg --decrypt … | tar -tzf -`,
   `openssl enc -d … | tar -tzf -`) — ro'yxatda `.env` va `config.json`lar bo'lishi kerak.
3. **Tashqi nusxa bormi** — `rclone ls <remote>` (yoki kompyuterdagi nusxa) — oxirgi kunlar fayllari.
4. Yilda bir marta — **to'liq mashq** bo'sh VPS'da (yuqoridagi 2–9-qadamlar) va RTO'ni jadvalga yozing.
