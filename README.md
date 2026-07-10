# Iqror Academy — veb-platforma

**Iqror Academy** — IT va MED (tibbiyot) yo‘nalishlarida chuqurlashtirilgan ta'lim
beruvchi zamonaviy maktabning rasmiy veb-platformasi: ochiq sayt, admin panel,
ota-ona kabineti, o‘qituvchilar tanlovi imtihoni va backend xizmatlari.
Ikki tilli (o‘zbek / rus).

🔗 **Sayt:** https://alilazer-cd582.web.app

## 📄 Sahifalar

| Fayl | Tavsif |
|------|--------|
| `index.html` | **Asosiy sayt** — mustaqil (self-contained) landing sahifa: hero, yo‘nalishlar, o‘quvchi natijalari (reyting + ID qidiruv), o‘qituvchilar, yutuqlar, galereya, narxlar, FAQ, aloqa/ariza formasi, **ota-ona kabineti** (davomat, baholar, monitoring, to‘lovlar, dars jadvali, uy vazifalari, choraklik xarakteristika) va AI chatbot. |
| `admin.html` | **Admin panel** — o‘quvchilar/o‘qituvchilar CRUD, davomat, baholar, monitoring, xarakteristika, to‘lovlar, arizalar, import (Excel/CSV/Google Sheets), ma'lumotnoma (transkript) chop etish. Rollar: admin, zavuch, kurator, sinf rahbari, fan o‘qituvchisi. |
| `imtihon.html` | **O‘qituvchilar tanlovi** — nomzodlar uchun imtihon sahifasi (savollar KaTeX bilan, AI baholash). |
| `oquv-platforma.html` | O‘quvchilar uchun oflayn o‘quv platformasi (darslar, SRS kartochkalar, testlar, AI murabbiy) — IT va tibbiyot bo‘yicha. |
| `prezentatsiya.html` | Maktab taqdimoti (slaydlar). |
| `manifest.json`, `sw.js`, `icon-192.png`, `icon-512.png` | PWA (o‘rnatiladigan ilova + network-first service worker). |
| `vendor/` | O‘z-o‘zida joylashgan kutubxonalar: KaTeX (matematik formulalar), SheetJS (`xlsx`). |
| `assets/`, `uploads/` | Logotip va rasm resurslari. |

## 🔥 Firebase

Loyiha Firebase (`alilazer-cd582`) ustida ishlaydi:

- **Hosting** — sayt (`firebase.json` → `public/`).
- **Auth** — email/parol + Google kirish.
- **Firestore** — barcha ma'lumotlar (o‘quvchilar, baholar, davomat, to‘lovlar, xarakteristika, arizalar…). Ruxsatlar: `firestore.rules`.
- **Storage** — rasmlar: `storage.rules`.
- **Cloud Functions** — `functions/` (AI: chatbot, oylik xulosa, imtihon baholash).

## 🧩 Backend xizmatlari (ixtiyoriy, mustaqil Node servislari)

| Papka | Vazifa |
|-------|--------|
| `functions/` | Firebase Cloud Function (`ai`) — Claude API orqali AI xizmatlari. |
| `ai-assistant/` | AI yordamchi serverning mustaqil varianti (Cloud Function o‘rniga). |
| `ai-grader/` | Imtihon javoblarini AI bilan baholovchi xizmat. |
| `camera-bridge/` | Yuz-terminal (kirish nazorati) → Firestore ko‘prigi. |
| `payments/` | To‘lov provayderlari (Click / Uzum / Payme) webhook serveri. |

Har bir xizmatning maxfiy sozlamalari (`config.json`, kalitlar) `.gitignore` bilan
himoyalangan va repozitoriyaga qo‘shilmaydi.

## 🚀 Deploy

```bash
firebase deploy --only hosting     # sayt
firebase deploy --only firestore:rules
firebase deploy --only functions:ai
```
