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
