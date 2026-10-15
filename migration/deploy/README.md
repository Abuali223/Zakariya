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
| `backup.sh` | Kunlik pg_dump + Storage zaxira (cron) | `/opt/iqror/...` + crontab |

## Tartib (qisqacha)
1. Supabase o'rnatish + schema/rls/import — `../supabase-setup.md`.
2. Frontend'ni `/var/www/iqror` ga, server kodni `/opt/iqror` ga qo'ying.
3. `switch-backend.cjs supabase` + `sb/sb-config.js` to'ldiring.
4. Server config'lar (`ai-assistant/config.json`, `payments/config.json`) — `backend:"supabase"`.
5. systemd: `iqror-ai`, `iqror-pay` — enable --now.
6. nginx + certbot (SSL).
7. `backup.sh` ni crontab'ga.
8. `../CUTOVER-CHECKLIST.md` bo'yicha to'liq sinov → cutover.

## Xizmat papkasi (WorkingDirectory) — deploy yangi server kodini ishga tushirishi uchun
`deploy.sh` kodni **`~/iqror-repo`** da yangilaydi (git). Namuna unit'lar (`iqror-*.service`) esa
`WorkingDirectory=/opt/iqror` dan ishlaydi. Shuning uchun `deploy.sh` (6-bosqich) har xizmatning
`WorkingDirectory`'sini tekshiradi: u repo bo'lmasa va server kodi papkasiga o'xshasa (`payments/`, `ai-assistant/`
yoki `auth/` bor) — **server kodini o'sha papkaga ham yozadi** (faqat git'dagi fayllar: `ai-assistant payments server sb auth`).
`config.json`, `node_modules`, `backups/`, `supabase/` va boshqa fayllar **tegilmaydi** (egasi va ruxsatlari ham — maxfiy
`config.json`'ni 0600 qilib qo'ygan bo'lsangiz, shunday qoladi); yangi/yangilangan kod fayllari `payments/` papkasi egasi nomidan
yoziladi, mavjud papkalarning egasi/ruxsati o'zgarmaydi. Egasi biror faylga yoza olmasa — deploy shu bosqichda to'xtaydi (xizmatlar
qayta ishga tushirilmaydi, eski kod ishlab turadi). Hech narsa qilish shart emas — deploy chiqishida «… kodi /opt/iqror dan ishlaydi — server kodi o'sha yerga ham
yozilmoqda» qatorini ko'rasiz.

Tekshirish (ixtiyoriy): `systemctl show -p WorkingDirectory iqror-pay` va deploy'dan keyin
`sudo journalctl -u iqror-pay -n 20 --no-pager` (xatosiz ishga tushganini ko'rish).

> ⚠️ Unit'larni `WorkingDirectory=/home/<siz>/iqror-repo` ga o'zgartirmang va `/opt/iqror` ni ko'chirmang/symlink
> qilmang: `User=iqror` uy papkangizni o'qiy olmaydi (Ubuntu'da 0750) — xizmatlar ishga tushmay qoladi; `/opt/iqror`
> ichida esa zaxiralar (`backup.sh`) va Supabase fayllari bo'lishi mumkin.
