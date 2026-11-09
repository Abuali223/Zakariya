# Yangi dizayn (v2) — joriy etish eslatmasi

Egasining qarori (2026-11-09): yangi dizayn tasdiqlandi; **shrift (Roboto Condensed) va logotiplar o‘zgarmaydi**;
**ruxsatlar o‘zgarmaydi** — ish faqat dizayn. Bajarildi: 1-bosqich (umumiy ko‘rinish), 3-bosqich (Direktor bosh
sahifasi) va egasining keyingi so‘rovi bilan 2-bosqich (kompyuterda ikonali menyu, telefonda pastki menyu). Menyu
tuzilishi (guruhlar, bo‘limlar, ruxsatlar) o‘zgarmagan — faqat joylashuvi va ko‘rinishi.

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

## 2-bosqich — menyu (barcha rollar)

Yangi menyu **mavjud** `#tabs` tuzilmasi ustiga quriladi (`buildTabs` oxirida `v2NavSetup()`): tugmalar, guruhlar
(`NAV_GROUPS`), belgilar (badge) va har rolning bo‘limlari (`allowedTabs`) avvalgidek — faqat joylashuv va ko‘rinish
o‘zgaradi. Har bir rolda bo‘limlar soni v1 bilan bir xil (Direktor 44, Moliya menejeri 8, o‘qituvchi 5, hamshira 2 …).

**Kompyuter (kengligi ≥ 821 px).** Chapda to‘q yashil, 80 px li ikonali panel (sahifa aylantirilganda joyida turadi).
Har bir guruh — bitta ikonka va qisqa nom; bosilganda yonida oq ro‘yxat (flyout) ochiladi: sarlavhasi — guruh nomi,
ichida shu guruh bo‘limlari. Ro‘yxat bo‘lim tanlanganda, tashqariga bosilganda yoki Esc bilan yopiladi; ekrandan
chiqmaydi. Faol bo‘lim guruhi yalpiz rangli «pill» bilan belgilanadi; yopiq guruhda ichidagi belgilar yig‘indisi
ko‘rinadi (avvalgidek). Past ekranlarda (balandligi ≤ 700 / ≤ 540 px — kichik noutbuk yoki brauzer kattalashtirilgan)
panel ixchamlashadi, hamma ikonka sig‘adi.

**Telefon / planshet (≤ 820 px).** Chap menyu yashiriladi; pastda doimiy menyu: «Asosiy» (Statistika) + rolda bor
guruhlardan uchtasi (tartib: O‘quvchilar, Moliya, Xodimlar, O‘quv jarayoni, Xizmatlar, Sayt, Tizim, Boshqaruv) +
«Menyu». Guruh bosilsa — pastdan shu guruh bo‘limlari oynasi; «Menyu» — «Barcha bo‘limlar» (guruhlar bo‘yicha, ikki
ustunli kartalar, «Tasdiqlash» eng tepada). Oyna × tugmasi, fon, Esc yoki bo‘lim tanlash bilan yopiladi. Xabarlar
(toast) va sahifa pasti menyu ostida qolmaydi. Guruhsiz rollar (≤ 8 bo‘lim): ≤ 5 bo‘lim — hammasi pastki menyuda,
aks holda 4 tasi + «Menyu».

**Qulaylik.** Guruh tugmalarida `aria-expanded`, pastki menyuda `aria-current`; oyna ochilganda fokus × ga o‘tadi,
yopilganda bosilgan tugmaga qaytadi; bosiladigan joylar ≥ 44 px; `prefers-reduced-motion` da animatsiya yo‘q.

**Tekshiruv (lokal, soxta ma’lumot):** menyu sinovi 19/19 (panel, 8 guruh ro‘yxatining har biri ekran ichida, Esc /
tashqariga bosish, klaviatura, pastki menyu, «Barcha bo‘limlar» — 44 bo‘lim, guruh oynasi, fon bilan yopish, toast
joyi, guruhsiz rollar, `?ui=v1` tegilmagan); barcha rollar × barcha bo‘limlar × 1440/390 (Direktor — 1024 va past
1280×560 ham) — sahifa xatosi 0, gorizontal siljish yo‘q; bosh sahifa 11/11, bayram/ta’til 15/15, eski menyu sinovi (v1) 5/5. `?ui=v1` nazorat rasmlari
(27 ta) bir xil sharoitda 2-bosqichdan oldingi commit bilan solishtirildi: 22 tasi piksel-piksel bir xil, qolganlarida
farq faqat vaqtda (sanoq soat) va sinov skriptining menyu siljish tezligida (asl v1 rasmlari ham shunday). Past
ekranlar: 1366×625, 1280×560, 1024×600, 1093×500 — panel to‘liq sig‘adi.

## 3-bosqich — Direktor bosh sahifasi («Statistika»)

`renderDashboard()` → v2 da `renderDashboardV2()`, v1 da `renderDashboardClassic()` (eski sahifa, o‘zgarmagan).
Sahifa **faqat o‘qiydi**: yozuv, SMS yoki holat o‘zgarishi yo‘q; tugmalar faqat tegishli bo‘limni ochadi
(«+ Yangi o‘quvchi» — mavjud qo‘shish oynasini ochadi, saqlash avvalgi tekshiruvlar bilan).

| Blok | Manba (ilovada avvaldan bor) |
|---|---|
| Salomlashuv, sana, bayram/ta’til belgisi | `users` (ism), `school_holidays` (`loadHolidays`, `holIsBreak`) |
| Bugun e’tibor talab qiladi | «Tasdiqlash» navbatlari `count()`; bugungi davomat; xodimlar kelishi; 2+ oy qarz; so‘nggi 7 kun arizalari |
| Davomat | `attendance` jurnali (oy hujjatlari, `days[DD]`): bugun belgilangan bo‘lsa — bugungi foiz, aks holda — shu oydagi foiz. Formula bazadagi «Davomat %» bilan bir xil: (keldi + kech) / (jami − bemor − sababli). O‘quvchi kartochkasidagi «Davomat %» (butun davr) bosh sahifada ishlatilmaydi |
| O‘quvchilar, Sinflar, Foydalanuvchilar | klassik sahifa bilan **bir xil hisob** — `dashCoreStats()` |
| O‘rtacha ball | faqat bahosi bor o‘quvchilar bo‘yicha (baho yo‘qlar «0» deb hisoblanmaydi); umuman yo‘q bo‘lsa «—» |
| To‘lovlar — joriy oy | `dashFinData()` (klassik moliya bilan bir xil): kirim, hisoblangan, qolgan; «bugun tushdi» — kassa asosida (`cashByMethod`) |
| Qarzdorlik | katta raqam — **muddati o‘tgan** qarz (o‘tgan oylar: 1 / 2 / 3+ oy); shu oy hali to‘lanmagani va jami alohida. Jami — «Moliya → Qarzdorlar» bilan bir xil qoida (joriy oygacha qolgan qism) |
| Moliya, Moliyaviy oqim (6 oy) | `dashFinData()`: kirim, chiqim, sof foyda, marja, avans, xarajat va to‘lov usuli taqsimoti |
| Xodimlar bugun | `staff`, `teachers`, `staff_checkins`, `staff_leaves` — «Xodimlar davomati» qoidalari (Kamera ID, ish kunlari, kechikish chegarasi) |
| Tasdiqlash kutmoqda | `approvalQueuesForMe()` — Direktor navbatlari |
| Hafta kalendari | `school_holidays` (🎉 bayram, 🏖 ta’til) + «O‘quv taqvimi (tadbirlar)» (`events`: sana, nomi) — nuqta va tanlangan kun ro‘yxati |
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

## 2026-11-09 — productiondagi haqiqiy ma'lumot bo'yicha tuzatishlar

Deploydan keyin Direktor sahifasida chalg'ituvchi raqamlar ko'rindi — sabab dizayn emas, ma'lumot bo'shliqlari:
«4 %» (o'quvchi kartochkalaridagi «Davomat %» o'rtachasi — klassik sahifada ham aynan shu), «0 / 100» (baho kiritilmagan),
ismsiz salomlashuv (profilda ism yo'q), «100 % marja» (shu oy xarajat kiritilmagan), «1,14 mlrd qarz» (shu oyning muddati
kelmagan fakturalari ham qo'shilgan). Tuzatildi: davomat jurnaldan; ball — baholanganlar bo'yicha yoki «—»; ism — `firstName`
bo'lmasa `name`/`displayName`; xarajat yo'q bo'lsa «kiritilmagan» va marja «—»; qarz — muddati o'tgani alohida;
«bugun tushdi»; kalendarda tadbirlar. «Tasdiqlash» bo'limi navbatlari endi PARALLEL yuklanadi (productionda ~7 s edi).

## Holat: to‘xtatilgan (2026-11-09)
Egasining qarori: dizayn ishlari vaqtincha to‘xtatildi, ustuvorlik — moliya (`docs/moliya/buxgalteriya-ish-reja.md`).
1-, 2- va 3-bosqichlar bajarilgan (2-bosqich — 6446f57, deployni egasi qiladi). Ota-ona kabinetini (`index.html`) shu
uslubga o‘tkazish boshlanmagan — egasi so‘raganda davom etadi. Yangi moliya ekranlari faqat mavjud komponentlardan
quriladi va ikkala ko‘rinishda (v1, v2) ishlaydi.
