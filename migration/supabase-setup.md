# aHost VPS'da Supabase o'rnatish va ma'lumotni ko'chirish (runbook)

Bu — **siz VPS'da** bajaradigan qadamlar. Har biri nusxa-joylash (copy-paste).
Muammo bo'lsa — chiqqan xatoni menga tashlang, yechib beraman.

> **Talab:** aHost'da **VPS** (Ubuntu 22.04+, root, ≥2 vCPU, ≥4 GB RAM, ≥40 GB SSD), domen (masalan `iqror.uz`), SSL.

---

## 1. VPS tayyorlash
```bash
# root sifatida
apt update && apt -y upgrade
apt -y install docker.io docker-compose-plugin git ufw
systemctl enable --now docker
# firewall
ufw allow OpenSSH && ufw allow 80 && ufw allow 443 && ufw --force enable
```

## 2. Supabase (self-hosted) o'rnatish
```bash
git clone --depth 1 https://github.com/supabase/supabase
cd supabase/docker
cp .env.example .env
```
`.env` faylida **ALBATTA o'zgartiring** (xavfsizlik):
- `POSTGRES_PASSWORD` — kuchli parol
- `JWT_SECRET` — 40+ tasodifiy belgi
- `ANON_KEY`, `SERVICE_ROLE_KEY` — JWT_SECRET asosida yangilang (Supabase hujjatidagi generator)
- `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD` — admin panel uchun
- `SITE_URL`, `API_EXTERNAL_URL` — domeningiz (masalan `https://api.iqror.uz`)
- `SMTP_*` — parol tiklash emaillari uchun (masalan aHost pochta yoki Gmail SMTP)

Ishga tushirish:
```bash
docker compose up -d
docker compose ps          # hammasi 'running/healthy' bo'lishi kerak
```

## 3. Sxema + xavfsizlik (RLS)
`migration/` papkadagi fayllarni VPS'ga ko'chiring, keyin:
```bash
# Postgres'ga ulanish (Supabase ichidagi db)
export PGURL="postgresql://postgres:PAROL@localhost:5432/postgres"
psql "$PGURL" -f schema.sql      # 31 jadval
psql "$PGURL" -f rls.sql         # 112 xavfsizlik siyosati
```

## 4. Ma'lumotni yuklash (JSON zaxira → Postgres)
Zaxira papkasini (`backup/`) VPS'ga ko'chiring, keyin:
```bash
npm install pg @supabase/supabase-js
BACKUP=./backup DATABASE_URL="$PGURL" node import.cjs         # 276 yozuv
```

## 5. Auth + rasmlar
```bash
export SUPABASE_URL="https://api.iqror.uz"
export SERVICE_ROLE_KEY="<.env dagi SERVICE_ROLE_KEY>"
BACKUP=./backup DATABASE_URL="$PGURL" STORAGE_BUCKET=public \
  node import-auth-storage.cjs
# 3 foydalanuvchi email orqali parol tiklaydi
```

## 6. Tekshirish (sanity)
```bash
psql "$PGURL" -c "select count(*) from students;"        # 46
psql "$PGURL" -c "select count(*) from invoices;"        # 58
psql "$PGURL" -c "select count(*) from student_private;" # 32
```
RLS ishlashini `test-rls.cjs` bilan sinash mumkin (test roli bilan).

## 7. Frontend'ni Supabase'ga ulash  (shimlar TAYYOR — `sb/` papkada)
Frontend Firebase SDK o'rniga `sb/` ichidagi **shim**larni ishlatadi (bir xil API,
lekin Supabase ustida). Cutover = bitta buyruq (qaytariladi).
```bash
cp sb/sb-config.example.js sb/sb-config.js     # SUPABASE_URL + ANON_KEY + BUCKET to'ldiring
node migration/switch-backend.cjs supabase --dry   # avval ko'ring
node migration/switch-backend.cjs supabase         # importlarni /sb ga o'tkazadi
# rollback kerak bo'lsa:  node migration/switch-backend.cjs firebase
```
`/sb/` papka frontend bilan birga deploy qilinsin (index.html yonida `/sb/...`).

Rasm URL'larини (eski Firebase → Supabase) import'dan keyin bir marta yangilang:
```bash
DRY=1 SUPABASE_URL=https://api.iqror.uz STORAGE_BUCKET=public \
  DATABASE_URL="$PGURL" node migration/rewrite-storage-urls.cjs   # ko'rish
SUPABASE_URL=https://api.iqror.uz STORAGE_BUCKET=public \
  DATABASE_URL="$PGURL" node migration/rewrite-storage-urls.cjs   # yozish
```

Supabase dashboard'да yoqing: Email + Google + **Anonymous** kirish, `public` Storage
bucket (ochiq), SMTP. To'liq ro'yxat — **`migration/CUTOVER-CHECKLIST.md`**.

## 8. Statik sayt (frontend) hosting
Ikki variant:
- **A)** Statik fayllarni (index.html, admin.html, vendor/…) aHost virtual hosting yoki
  o'sha VPS'dagi **Nginx** orqali `iqror.uz` da bering.
- **B)** Nginx reverse-proxy: `iqror.uz` → statik, `api.iqror.uz` → Supabase (8000).
SSL: `certbot` (Let's Encrypt) bilan bepul.

## 9. Parallel sinov → cutover
1. Yangi tizim (Supabase) **eski Firebase yonida** sinaladi (test subdomain).
2. Tekshiring: login, kabinet, admin CRUD, baho/davomat, RLS (begona ko'rmasligi),
   profil PDF/QR, to'lovlar.
3. **100% muvofiq** bo'lgach — domenni yangi frontend'ga o'tkazasiz (cutover).
4. **Firebase kamida 1 oy** zaxirada qoladi (rollback uchun).

## 10. Xavfsizlik va zaxira (majburiy)
- `.env` dagi barcha default parol/kalitlar **o'zgartirilgan** bo'lsin.
- **Kunlik backup:** `pg_dump` + Storage nusxa (cron bilan, boshqa joyга).
- Faqat 80/443 ochiq; Postgres (5432) faqat localhost.
- Supabase Studio (dashboard) parol bilan himoyalangan, ochiq internetда emas.
- Muntazam `apt upgrade` + Docker image yangilash.

## 11. Anthropic kaliti (AI)
- `secrets` DB'ga ko'chirilmadi. Anthropic kalitini **AI xizmati serverining
  ENV** o'zgaruvchisiga qo'ying (Cloud Function o'rniga VPS'dagi kичик Node xizmat).

---

## Rollback (agar muammo bo'lsa)
Frontend'ni **eski Firebase konfiguratsiyasiga** qaytaring (bitta config o'zgarishi).
Firebase o'chirilmagani uchun ma'lumot joyida. Muammo yechilgach yana Supabase'ga o'tasiz.
