# IQROR — bajarilgan ishlar tarixi

**Branch:** `claude/iqror-med-school-impl-iqdntl`
**Oxirgi holat:** barcha ishlar commit + push qilingan (GitHub: `Abuali223/Zakariya`).
**Maqsad:** davomat (Hikvision yuz terminali) → maosh, to'lov (Click/Uzum) va xavfsizlik bo'yicha tuzatmalar + yangi funksiyalar.

> Deploy (har safar): `cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- admin.html payments server migration sb deploy.sh && bash deploy.sh` → saytda **Ctrl+Shift+R**.
> (Faqat frontend o'zgargan bo'lsa `admin.html` yetarli; SQL/server o'zgarsa to'liq `deploy.sh`.)

---

## 1) Xavfsizlik (audit) tuzatmalari

| Kod | Nima qilindi | Fayl |
|-----|--------------|------|
| **A1** | Barcha `SECURITY DEFINER` (app.*) funksiyalariga `search_path` mahkamlandi — imtiyoz oshirish (privesc) yo'li yopildi (Supabase linteri 0011). **FORCE RLS QO'LLANMADI** (u pul RPC'larini buzardi yoki superuser'da no-op). | `migration/secdef-searchpath.sql` |
| **A2** | Ariza (imtihon) topshirishda nomzod o'ziga **natija/baho oldindan yoza olmaydi** (`status='submitted' AND result IS NULL AND gradedAt IS NULL`). Imtihon ochiq-savol/AI-baholi — javob kaliti saqlanmaydi, sizish yo'q. | `migration/applications-guard.sql`, `rls.sql` |

## 2) Davomat (attMetrics / maosh) tuzatmalari

| Kod | Nima qilindi |
|-----|--------------|
| **B1** | Oylik hisobotdagi «Ruhsatsiz» ustuni hayot-sikl oralig'i bilan FILTRLANGAN (oy o'rtasida kirgan/muzlatilgan ikki marta sanalmaydi — «Ushlanma» puli bilan mos). |
| **B2** | Kechikish/erta ketish skan **statusi** (in/out) bo'yicha hisoblanadi (adashgan break/out birinchi skan bo'lsa jarima buzilmaydi). |
| **B3** | `billingInterval`: muzlatilgan/chiqdi, lekin to'xtatish sanasi (stopFrom) yo'q bo'lsa — SKIP (ortiqcha to'liq-oy undiruvi emas). |
| **E1** | `computeTuition`: kasal kun chegirmasi prorataDAN KEYIN, FLAT ayiriladi (ilgari net*fraction kasal summasini ham ulushга ko'paytirib ikki marta kamaytirardi). |

## 3) To'lov server (payments/index.cjs) tuzatmalari

| Kod | Nima qilindi |
|-----|--------------|
| **C1** | `hikEventId()` — Hik hodisa IDsi QURILMA bilan namespace (mac/ip/deviceName) + serialsiz holatda DETERMINISTIK (ilgari `Date.now()` fallback dubl qilardi). |
| **F1** | `readBody()` HECH QACHON osilmaydi (end/error/aborted/close hammasi resolve), >8MB tana → 413. |
| **F2** | Debug loglardan maxfiy ma'lumot olib tashlandi (CLICK-DEBUG: imzo/secret uzunligini emas, faqat `sigMatch`/`hasSecret`; PAY-BODY `redactPII`; HIK-EVENT xom tanani loglamaydi). |

## 4) To'lov RPC (SQL) tuzatmalari

| Kod | Nima qilindi | Fayl |
|-----|--------------|------|
| **D1** | `split_payment` allocatsiyalarni **kanonik sid bo'yicha YIG'adi** — bir sid ikki marta kelsa pul yo'qolmaydi (ilgari ikkinchisi jim yo'qolardi). | `migration/split-payment.sql` |
| **D2** | `reattribute_avans` — `p_ref` endi MAJBURIY + idempotentlik guardи VALIDATSIYADAN KEYIN (xato ref'ni "yoqib" yubormaydi). | `migration/reattribute-avans.sql` |

## 5) Shim

| Kod | Nima qilindi |
|-----|--------------|
| **G1** | `setDoc` merge semantikasi aniq hujjatlashtirildi (Supabase upsert allaqachon merge — Firestore to'liq-REPLACE ataylab emulatsiya qilinmaydi, ma'lumot yo'qolmasin). Xatti-harakat o'zgarmadi. | `sb/firebase-firestore.js` |

---

## 6) YANGI FUNKSIYALAR — davomat ekrani

- **Xodim qo'shish ekranidan**: «+ Xodim qo'shish» tugmasi + «Bog'lanmagan» Kamera ID qatorida «➕ Xodim qilib bog'lash» (Kamera ID + ism oldindan to'ldirilgan holda).
- **Tahrirlash**: har xodim/o'qituvchi qatorida **✏️** — to'liq kartochka (ism, lavozim, ish vaqti, Kamera ID, holat...). Kunlik va oylik ko'rinishlarda.
- **Lavozim / rol**: erkin matn o'rniga DROPDOWN — «Foydalanuvchilar» bo'limidagi rollar bilan BIR XIL (Direktor, HR, Kassir, Qorovul, Oshpaz...). O'z matnini yozish ham mumkin. *(Bu — davomat/maosh uchun lavozim; tizimga kirish roli alohida «Foydalanuvchilar»da.)*
- **Shaxsiy ish vaqti** (xodim VA o'qituvchi kartochkasida): `workStart`/`workEnd` (HH:MM) + **ish kunlari** alohida belgilash (Dush..Yakshanba — Shanba/Yakshanba ham, istalgan kombinatsiya). Bo'sh = standart 08:00–17:00, Dush–Juma. Davomat/maosh shaxsiy jadval bo'yicha hisoblanadi. | DB: `migration/staff-workhours.sql` (`workStart/workEnd/workDays` → staff + teachers).

## 7) Vaqt mintaqasi (timezone) tuzatmasi

- Qurilma hodisa vaqtini UTC yuborganda sayt 5 soat orqada ko'rsatardi (07:37 → 02:37). **O'zbekiston doimo +05:00 (DST yo'q)**:
  - `admin.html`: `tzHMParts()` — tz-ko'rsatilgan (Z/±offset) vaqtni mahalliyga o'tkazadi (mavjud UTC yozuvlar ham to'g'ri ko'rinadi).
  - `payments/index.cjs`: `toTashkent()` — kiruvchi vaqt DOIM +05:00 ga normallashtirib saqlanadi.

## 8) Kechikish/erta ketish jarimasi — SOZLANADIGAN

- **«Narx jadvali»** bo'limida (kasal kun stavkasi yonida): «Kechikish jarimasi (so'm/marta)» va «Erta ketish jarimasi (so'm/marta)». `config/finance`'ga saqlanadi (`latePenalty`/`earlyPenalty`). Bo'sh → standart 20 000; **0 → jarima o'chiriladi**. Barcha xodim/o'qituvchilarga amal qiladi.
- **MUHIM:** jarimalar FAQAT xodim/o'qituvchi maoshiga ta'sir qiladi — **o'quvchilarga (hisob-faktura) ta'sir qilmaydi** (`computeTuition` jarimani umuman o'qimaydi, faqat `sickRate`ni).

## 9) To'lov oqimi TEST qamrovi tiklandi

- `payments/_fake-sb.cjs` (yangi) — soxta Supabase `from()` + **sodiq `rpc()`** (apply_payment/apply_to_invoice/reverse_payment — haqiqiy SQL kabi in-memory).
- `flow.test.cjs` (11/11), `uzum.test.cjs` (20/20), `attr.test.cjs` (9/9) — `cd payments && npm test`.
- **Differential tekshiruv**: bir xil ssenariylar HAQIQIY Postgres RPC va mock'да — natija AYNAN bir xil (mock rubber-stamp emas).

---

## 10) Ish vaqtidagi tanaffus (chiqib-kirish) nazorati — SOZLANADIGAN

- **MUAMMO:** jarima faqat kelish/ketish chegarasini tekshirardi — xodim o'rtada uzoq chiqib ketsa (chiqdi-kirdi) jarima yo'q edi.
- **YECHIM («Narx jadvali»):** «Ruxsat etilgan tanaffus (daq/kun)» (standart 60) + «Oshiqcha tanaffus jarimasi (so'm/soat)» (standart **0 = jarima yo'q**). Kunlik tanaffus ruxsatdan oshsa — oshig'iga soatiga jarima. `config/finance` (`allowedBreakMin`/`breakPenaltyPerHour`). Oylik hisobot «Ushlanma» tooltip'ida va maosh berishda ko'rinadi.
- `scanBreakMin()` — tanaffus mantig'i `agg()`+`attMetrics`'da bir xil. JS test 9/9. Faqat `admin.html`.

## 11) «Sababli / O'z hisobidan» — bitta tugma (ish vaqtidagi tanaffus)

- Ma'muriyat/HR kunlik davomatда har xodim qatorida (tanaffus bo'lgan kunlarda) bitta tugma: **«Sababli»** (o'sha kun tanaffus jarimasi tushmaydi) / **«O'z hisobidan»** (kesiladi). Standart — o'z hisobidan.
- `staff_break_marks` jadvali (RLS: o'qish admin/hr/finance/cashier; yozish faqat admin/hr). `attMetrics` 6-param `breakExcused` — sababli kunlar tanaffus jarimasidan chiqariladi (kech/erta/yo'qlamaga tegmaydi). Kunlik + oylik + maosh berish — hammasi hisobga oladi.

## 12) Qabulxona (reception) huquqlari cheklandi

- **FAQAT o'quvchi holati cheklandi** (faollashtirish/muzlatish/chiqarish/sinov) — endi faqat **Ma'muriyat/direktor**. Frontend: ⏯️ tugma `canManageStudentStatus()`; o'quvchi formasidan `payStatus/activeFrom/stopFrom` maydonlari qabulxonaga yashirildi (`_recHide`). Backend: `students` BEFORE INS/UPD trigger (`trg_reception_student_lifecycle`) — UPDATE'da 42501 xato, INSERT'da jim tozalanadi. Fayl: `reception-guard.sql`.
- **MOLIYA KO'RISH QABULXONADA QOLDI** (foydalanuvchi aniqligi: bular pulga ta'sir qilmaydi, faqat ota-onaga xabar berish/undiruv uchun): qarzdorlik ustuni/filtri (`canSeeStudentFinance()=true`, `inv_sel` da `is_reception()`), 📞 to'lov eslatmasi (`canNote` + `pay_notes` pn_sel/ins/upd da `is_reception()`), chegirma/kontrakt/aka-uka/referral maydonlari (`student_private` — moliya triggeri OLIB TASHLANDI). To'lov KIRITISH/qaytarish (apply_payment RPC'lar, invoices YOZISH) baribir faqat moliya/kassirda. Fayl: `reception-access.sql`.
- **Qabulxona saqlagan imkoniyatlar:** o'quvchi qo'shish/asosiy ma'lumot + hujjat (PII) tahriri, qarzdorlik ko'rish, 📞 eslatma, chegirma maydonlari, arizalarni ko'rish. **Cheklangan:** faqat o'quvchi holati.
- **Eslatma (reachability):** `ROLE_TABS` bo'yicha `students` tab'i faqat direktor + qabulxona + kassir(ko'rish)da. `admin`/`admin_head`/`zavuch` o'quvchilar ekranini ko'rmaydi, shuning uchun `students`/`student_private` RLS'i `is_admin()` (direktor) bilan qolgan — o'zgartirilmadi.

## Tekshiruv usullari (shu sessiyada ishlatilgan)
- **PG16** lokal: `migration/run-all.sql` to'liq build + funksional SQL testlar (pul RPC'lari service_role claim bilan).
- **JS birlik testlari**: haqiqiy funksiyalar `admin.html`dan ajratib olinib (billingInterval/attMetrics/personRules/tzHMParts, Hik id, readBody, redactPII) — barchasi o'tdi.
- **npm test** (payments): uchala to'plam yashil.

## Muhim eslatmalar / qoidalar
- **Branch:** faqat `claude/iqror-med-school-impl-iqdntl` (boshqasiga push YO'Q, ruxsatsiz).
- **Maxfiy kalitlar** (qurilma paroli, Google/Brevo kalitlari) kodga/gitga YOZILMAYDI. Agar fosh bo'lsa — rotatsiya qiling.
- **Ochiq (shoshilinch bo'lmagan) nuqta:** yo'q — to'lov testlari tiklandi. (Ilgari eskirgan edi.)

## Commitlar (shu sessiya, eng yangidan eskiga)
```
b1eeffe docs(davomat): jarima sozlamasi joyi — «Narx jadvali»
cc1dde2 feat(davomat): kechikish/erta ketish jarima summasini sozlanadigan
2001baa test(to'lov): pul oqimi test qamrovini tiklash (fake Supabase .rpc())
3e98881 fix(davomat): vaqtni Asia/Tashkent (+05:00) ga keltirish — UTC 5 soat farqi
f9a4ccb fix(davomat): o'qituvchini tahrirlashda xato (teacher -> teachers)
6ca1160 feat(davomat): xodim/o'qituvchini davomat ekranidan TAHRIRLASH (✏️)
47b2a3f fix(davomat): lavozim ro'yxati rollar bilan bir xil + ish kunlari erkin (Shan/Yak)
0bb73c6 feat(davomat): ekranidan xodim qo'shish/bog'lash + lavozim + shaxsiy ish vaqti
39d06ba docs(shim): setDoc merge semantikasini hujjatlashtirish
61556da fix(to'lov-RPC): split_payment dublikat sid + reattribute_avans ref majburiy
ba6f529 fix(to'lov-server): Hik ID barqaror+qurilma bilan, readBody, log PII
f1ba5db fix(davomat+to'lov): ruhsatsiz ustuni, skan in/out, muzlatilgan skip, kasal prorata
99fd1d5 fix(xavfsizlik): SECURITY DEFINER search_path + ariza oldindan-baholashni to'sish
```
