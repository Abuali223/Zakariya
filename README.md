# Iqror Academy — veb-platforma

**Iqror Academy** — IT va MED (tibbiyot) yo‘nalishlarida chuqurlashtirilgan ta'lim
beruvchi zamonaviy maktabning rasmiy veb-platformasi: ochiq sayt, admin panel,
ota-ona kabineti, o‘qituvchilar tanlovi imtihoni va backend xizmatlari.
Ikki tilli (o‘zbek / rus).

🔗 **Sayt:** https://iqroacademy.uz

## 📄 Sahifalar

| Fayl | Tavsif |
|------|--------|
| `index.html` | **Asosiy sayt** — mustaqil (self-contained) landing sahifa: hero, yo‘nalishlar, o‘quvchi natijalari (reyting + ID qidiruv), o‘qituvchilar, yutuqlar, galereya, narxlar, FAQ, aloqa/ariza formasi, **ota-ona kabineti** (davomat, baholar, monitoring, to‘lovlar, dars jadvali, uy vazifalari, choraklik xarakteristika, **avtobus kuzatuvi**) va AI chatbot. |
| `admin.html` | **Admin panel** — o‘quvchilar/o‘qituvchilar CRUD, davomat, baholar, monitoring, xarakteristika, to‘lovlar, arizalar, import (Excel/CSV/Google Sheets), ma'lumotnoma (transkript) chop etish. Rollar: admin, zavuch, kurator, sinf rahbari, fan o‘qituvchisi, moliya, kassir. |
| `imtihon.html` | **O‘qituvchilar tanlovi** — nomzodlar uchun imtihon sahifasi (savollar KaTeX bilan, AI baholash). |
| `oquv-platforma.html` | O‘quvchilar uchun oflayn o‘quv platformasi (darslar, SRS kartochkalar, testlar, AI murabbiy) — IT va tibbiyot bo‘yicha. |
| `haydovchi.html` | **Avtobus haydovchisi** — maxfiy havola orqali (login yo‘q) joylashuvni ulashish sahifasi. |
| `verify.html` | O‘quvchi profili / hujjat haqiqiyligini tekshirish sahifasi. |
| `prezentatsiya.html` | Maktab taqdimoti (slaydlar). |
| `manifest.json`, `sw.js`, `icon-192.png`, `icon-512.png` | PWA (o‘rnatiladigan ilova + network-first service worker). |
| `vendor/` | O‘z-o‘zida joylashgan kutubxonalar: KaTeX (matematik formulalar), SheetJS (`xlsx`). |
| `assets/`, `uploads/` | Logotip va rasm resurslari. |

## 🗄️ Backend — mustaqil (self-hosted) Supabase

Loyiha **o‘z serverida** ishlaydi (ilgari Firebase'da edi — endi to‘liq
Supabase/PostgreSQL'ga ko‘chirilgan):

- **Nginx** — statik saytni (`/var/www/iqror`) uzatadi.
- **Supabase (PostgreSQL)** — barcha ma'lumotlar (o‘quvchilar, baholar, davomat,
  to‘lovlar, xarakteristika, arizalar, avtobus…). Ruxsatlar — **RLS** (Row Level
  Security) siyosatlari: `migration/*.sql`.
- **Supabase Storage** — rasmlar; ruxsatlar `migration/storage-rls.sql`.
- **`/sb` shim** — sahifalar Firebase SDK importlarini `/sb` shimga yozadi
  (`sb/firebase-*.js`), u Firebase shaklidagi API'ni Supabase ustida bajaradi.
  Shu sabab frontend kodni deyarli o‘zgartirmasdan ko‘chirildi.

## 🧩 Backend xizmatlari (mustaqil Node servislari)

| Papka | Vazifa |
|-------|--------|
| `server/` | Supabase Admin SDK shimi (`sb-admin.js`) + backend yordamchilari — Node servislari shu orqali bazaga ulanadi. |
| `ai-assistant/` | AI yordamchi serveri — Claude API orqali chatbot, oylik xulosa, xavf tahlili. |
| `ai-grader/` | Imtihon javoblarini AI bilan baholovchi xizmat. |
| `camera-bridge/` | Yuz-terminal (kirish nazorati) → baza ko‘prigi. |
| `payments/` | To‘lov provayderlari (Click / Uzum / Payme) webhook serveri + SMS xabarnoma ishchisi (`sms-worker.cjs`). |

Har bir xizmatning maxfiy sozlamalari (`config.json`, kalitlar) va `sb/sb-config.js`
`.gitignore` bilan himoyalangan — repozitoriyaga qo‘shilmaydi.

## 🚀 Deploy

Bitta buyruq (kod yangilash + paketlar + SQL migratsiya + frontend + shim):

```bash
bash deploy.sh
```

`deploy.sh` git'dan kodni oladi, idempotent SQL migratsiyalarni (`migration/`)
qo‘llaydi, `/sb` shimlarni va sahifalarni `/var/www/iqror` ga joylaydi.
`config.json` va `sb/sb-config.js` ga tegmaydi.
