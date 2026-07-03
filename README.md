# Iqror IT MED School — veb-platforma

**Iqror IT MED School** — IT va MED yo‘nalishlarida chuqurlashtirilgan ta'lim beruvchi
zamonaviy maktabning rasmiy veb-sayti. Ikki tilli (o‘zbek / rus), to‘liq statik va
GitHub Pages'da bevosita ishlaydi.

🔗 **Sayt:** `https://<username>.github.io/<repo>/`

## 📄 Fayllar

| Fayl | Tavsif |
|------|--------|
| `index.html` | **Asosiy sayt** — mustaqil (self-contained), moslashuvchan (responsive) landing sahifa: hero, yo‘nalishlar, o‘quvchi natijalari (reyting + ID qidiruv), o‘qituvchilar reytingi, yutuqlar, maktab hayoti, aloqa/ariza formasi. UZ/RU tillari. |
| `Iqror IT MED School.dc.html` | Dizayn manbasi (design-component format). `support.js` runtime + `image-slot.js` bilan render bo‘ladi. `index.html` — shu dizaynning ishlab chiqarishga tayyor kompilyatsiyasi. |
| `support.js`, `image-slot.js` | Dizayn runtime va rasm-slot komponenti (faqat `.dc.html` uchun). |
| `uploads/`, `assets/` | Logotip va rasm resurslari. |
| `oquv-platforma.html` | **Bonus:** o‘quvchilar uchun oflayn o‘quv platformasi (darslar, SRS kartochkalar, testlar, AI murabbiy) — IT, tibbiyot va tibbiy informatika bo‘yicha. |
| `arab-tili.html` va boshqalar | Avvalgi «Arab Tili» PWA loyihasi (saqlab qolindi). |

## 🔥 Firebase (ixtiyoriy)

`index.html` ichida Firebase moduli mavjud (`iqror-72879` loyihasi):

- **Analytics** — tashriflar statistikasi.
- **Firestore** — ariza (enrollment) formasi ma'lumotlari `enrollments` to‘plamiga saqlanadi.

Internet bo‘lmasa yoki Firebase sozlanmagan bo‘lsa, sayt baribir to‘liq ishlayveradi.

**Ariza formasi ishlashi uchun** Firebase konsolida:
1. **Authentication → Anonymous** yoqilishi kerak (anonim yozuv uchun).
2. **Firestore Database** yaratilib, quyidagi qoidalar qo‘shilishi tavsiya etiladi:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /enrollments/{doc} {
      allow create: if request.auth != null;   // faqat yozish (arizalarni o‘qish adminda)
      allow read, update, delete: if false;
    }
  }
}
```

## 🚀 Deploy (GitHub Pages)

`.github/workflows/pages.yml` — `main` ga har push qilinganda saytni avtomatik deploy qiladi.

- **Settings → Pages → Source: GitHub Actions** tanlangan bo‘lsa, deploy avtomatik ishlaydi.
- Muqobil: **Settings → Pages → Source: `main` / `(root)`** ham qo‘llab-quvvatlanadi (`.nojekyll` mavjud).
