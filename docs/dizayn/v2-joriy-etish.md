# Yangi dizayn (v2) — joriy etish eslatmasi

Egasining qarori (2026-11-09): yangi dizayn tasdiqlandi; **shrift (Roboto Condensed) va logotiplar o‘zgarmaydi**;
**ruxsatlar o‘zgarmaydi** — ish faqat dizayn. Bajarildi: 1-bosqich (umumiy ko‘rinish) va 3-bosqich (Direktor bosh
sahifasi). 2-bosqich (ikonali menyu / telefonda pastki menyu) so‘ralmagan — guruhlangan menyu tuzilishi o‘zgarmagan,
faqat ko‘rinishi yangilangan.

## Qanday ishlaydi

- `admin.html` `<head>` dagi kichik skript `<html data-ui="v2">` ni qo‘yadi (standart — yangi dizayn).
- Barcha yangi uslublar bitta blokda: `<style id="ui-v2">` (asosiy CSS'dan keyin). **Har bir qoida
  `html[data-ui="v2"]` bilan boshlanadi** — bayroq bo‘lmasa sahifa piksel-piksel avvalgidek.
- Eski ko‘rinishga qaytish (shu qurilmada eslab qolinadi):
  - manzilga `?ui=v1` qo‘shish (qaytarish: `?ui=v2`), yoki
  - «Profil» → «Ko‘rinish» → «Eski dizayn» / «Yangi dizayn».
- Hech qanday SQL, RLS, rol yoki bo‘lim ro‘yxati o‘zgarmagan. Chop etiladigan hisobotlar (PDF) o‘z uslubida — tegilmagan.

## 1-bosqich — umumiy ko‘rinish (barcha rollar)

Fon: yalpiz → iliq «kanvas». Chap menyu: to‘q yashil panel, faol bo‘lim yalpiz rangda. Kartalar: oq, 20 px burchak, yumshoq
soya. Tugmalar va chiplar: «pill» shakli; asosiy tugma (`.btn.gold`) iliq rangda. Maydonlar: 12 px burchak, yashil fokus
halqasi. Oyna (modal): 24 px burchak. Xabarlar (toast): to‘q grafit. Jadvallar zichligi o‘zgarmagan (katak oralig‘i
avvalgidek); telefonda jadval-kartochka ko‘rinishi saqlangan. Moliya / Buxgalteriya / Marketing bloklarida faqat
burchak va soya yangilangan (tuzilish o‘zgarmagan).

## 3-bosqich — Direktor bosh sahifasi («Statistika»)

`renderDashboard()` → v2 da `renderDashboardV2()`, v1 da `renderDashboardClassic()` (eski sahifa, o‘zgarmagan).
Sahifa **faqat o‘qiydi**: yozuv, SMS yoki holat o‘zgarishi yo‘q; tugmalar faqat tegishli bo‘limni ochadi
(«+ Yangi o‘quvchi» — mavjud qo‘shish oynasini ochadi, saqlash avvalgi tekshiruvlar bilan).

| Blok | Manba (ilovada avvaldan bor) |
|---|---|
| Salomlashuv, sana, bayram/ta’til belgisi | `users` (ism), `school_holidays` (`loadHolidays`, `holIsBreak`) |
| Bugun e’tibor talab qiladi | «Tasdiqlash» navbatlari `count()`; bugungi davomat; xodimlar kelishi; 2+ oy qarz; so‘nggi 7 kun arizalari |
| Bugungi davomat | `attendance` (oy hujjatlari, `days[DD]`), «Davomat» bo‘limi bilan bir xil; o‘rtacha — o‘quvchi kartochkasidan (klassik bilan bir xil) |
| O‘rtacha ball, O‘quvchilar, Sinflar, Foydalanuvchilar | klassik sahifa bilan **bir xil hisob** — `dashCoreStats()` |
| To‘lovlar — joriy oy | `dashFinData()` (klassik moliya bilan bir xil): kirim, hisoblangan, qolgan |
| Qarzdorlik (shu oy / 1 / 2 / 3+ oy) | hisob-fakturalar; «Moliya → Qarzdorlar» bilan bir xil qoida (joriy oygacha qolgan qism) |
| Moliya, Moliyaviy oqim (6 oy) | `dashFinData()`: kirim, chiqim, sof foyda, marja, avans, xarajat va to‘lov usuli taqsimoti |
| Xodimlar bugun | `staff`, `teachers`, `staff_checkins`, `staff_leaves` — «Xodimlar davomati» qoidalari (Kamera ID, ish kunlari, kechikish chegarasi) |
| Tasdiqlash kutmoqda | `approvalQueuesForMe()` — Direktor navbatlari |
| Hafta kalendari | `school_holidays` (🎉 bayram, 🏖 ta’til) |
| Xavf ostidagi o‘quvchilar | klassik ro‘yxat (eng past 60 tasi; tepada 4 tasi, «Hammasi» — to‘liq jadval) |

Kirishda ilova bo‘limni bir necha marta chizadi (eski xatti-harakat) — v2 bir necha soniya ichidagi takroriy so‘rovlarni
birlashtiradi (`dv2Once`), shuning uchun har bir manba bir marta o‘qiladi. Animatsiya (raqamlar sanog‘i, kartalarning
paydo bo‘lishi) faqat birinchi ochilishda; `prefers-reduced-motion` yoqilgan bo‘lsa — umuman yo‘q.

## Tekshiruv (lokal, soxta ma’lumot)

- 44 bo‘lim (Direktor) + Moliya menejeri, kassir, hamshira, O‘IBDO‘, qabulxona, kurator, o‘qituvchi — barcha bo‘limlar,
  kompyuter (1440) va telefon (390): sahifa xatosi 0, gorizontal siljish yo‘q; har rolning bo‘limlari soni v1 bilan bir xil.
- `?ui=v1`: 27 ta nazorat rasmi avvalgisi bilan piksel-piksel bir xil (farqlar faqat vaqtga bog‘liq: sanoq soat, menyu siljishi).
- Bosh sahifa: klassik sahifadagi 14 ta raqam v2 da aynan teng; tugmalar to‘g‘ri bo‘limga; almashtirgichlar; «Ko‘rinish»
  almashtirgichi; reduced-motion — 11/11.
- Avvalgi avtomatik sinovlar: guruhlangan menyu 5/5, bayram/ta’til 15/15.
- Matn kontrasti (WCAG): eng pasti 5,2:1.
