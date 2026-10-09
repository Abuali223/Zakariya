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

## 11) «Sababli / O'z hisobidan» — IKKI tugma (ish vaqtidagi chiqib-kelish) + oylikka ta'sir

- Ma'muriyat/HR kunlik davomatда **har xodim qatorida** (`Tanaffus` ustunida) IKKI tugma:
  - **«Sababli»** (type='excused') → o'sha kun chiqishi uchun oylik **kesilmaydi**.
  - **«O'z hisobidan»** (type='personal') → bosilganda **necha DAQIQA** ketgani so'raladi (prompt); oylikdan **soatbay** kesiladi = `awayMin/60 × breakPenaltyPerHour` (Narx jadvalidagi «tanaffus jarimasi soatiga»).
  - Qayta bosish / 0 kiritish → belgini **o'chiradi** (standart holatga qaytadi).
- **Nega qo'lda vaqt:** kameralar ko'pincha toza chiqdi→kirdi juftini yozmaydi (`scanBreakMin`≈0), shuning uchun avtomatik aniqlash ishlamaydi — ma'muriyat ketgan vaqtni qo'lda kiritadi.
- **`attMetrics` yangilandi** (6-param `breakMarks` = `{kun → {type, awayMin}}`): `personal` → `awayMin` to'liq `excessBreakMin`ga qo'shiladi (kamera aniqlagani INOBATGA OLINMAYDI — ikki marta hisoblanmaydi); `excused` → jarima yo'q; belgisiz → kamera bo'yicha. **Orqaga moslik:** eski Set yoki `type`siz yozuv → `excused`. Uch chaqiruv joyi (kunlik `bmMap`, oylik `bmByRef`, maosh `loadDed breakMarks`) bir xil normalizatsiya.
- `staff_break_marks` jadvali: `type text default 'excused'` + `"awayMin" integer default 0` ustunlari (idempotent ALTER). RLS: o'qish admin/hr/finance/cashier; yozish faqat admin/hr.
- **Tekshirildi:** `attMetrics` birlik testi 10/10 (excused=0, personal=awayMin×stavka, personal avtomatikni bosib o'tadi, eski Set/typesiz→excused, string awayMin, stavka=0). PG16: ustunlar idempotent, HR RLS bilan insert/update/delete round-trip. JS sintaksis toza.

## 12) Qabulxona (reception) huquqlari cheklandi

- **FAQAT o'quvchi holati cheklandi** (faollashtirish/muzlatish/chiqarish/sinov) — endi faqat **Ma'muriyat/direktor**. Frontend: ⏯️ tugma `canManageStudentStatus()`; o'quvchi formasidan `payStatus/activeFrom/stopFrom` maydonlari qabulxonaga yashirildi (`_recHide`). Backend: `students` BEFORE INS/UPD trigger (`trg_reception_student_lifecycle`) — UPDATE'da 42501 xato, INSERT'da jim tozalanadi. Fayl: `reception-guard.sql`.
- **MOLIYA KO'RISH QABULXONADA QOLDI** (foydalanuvchi aniqligi: bular pulga ta'sir qilmaydi, faqat ota-onaga xabar berish/undiruv uchun): qarzdorlik ustuni/filtri (`canSeeStudentFinance()=true`, `inv_sel` da `is_reception()`), 📞 to'lov eslatmasi (`canNote` + `pay_notes` pn_sel/ins/upd da `is_reception()`), chegirma/kontrakt/aka-uka/referral maydonlari (`student_private` — moliya triggeri OLIB TASHLANDI). To'lov KIRITISH/qaytarish (apply_payment RPC'lar, invoices YOZISH) baribir faqat moliya/kassirda. Fayl: `reception-access.sql`.
- **Qabulxona saqlagan imkoniyatlar:** o'quvchi qo'shish/asosiy ma'lumot + hujjat (PII) tahriri, qarzdorlik ko'rish, 📞 eslatma, chegirma maydonlari, arizalarni ko'rish. **Cheklangan:** faqat o'quvchi holati.
- **Eslatma (reachability):** `ROLE_TABS` bo'yicha `students` tab'i faqat direktor + qabulxona + kassir(ko'rish)da. `admin`/`admin_head`/`zavuch` o'quvchilar ekranini ko'rmaydi, shuning uchun `students`/`student_private` RLS'i `is_admin()` (direktor) bilan qolgan — o'zgartirilmadi.

## 13) Maosh — SOATBAY (hours-based) modelga o'tkazildi

- **Foydalanuvchi talabi:** oylik ÷ kunga ÷ ish soatiga → soatlik stavka; xodim necha soat ishlasa shuncha oylik. Kech/erta/«o'z hisobidan»/yo'qlama — hammasi soatbay ayiriladi. «Shu soat ishladingiz → shuncha oylik» hisoboti.
- **`attMetrics` to'liq qayta yozildi:**
  - `dailyMin = ish vaqti − tushlik (allowedBreakMin)` (masalan 08:00–17:00, 60 daq → 480 daq = 8 soat).
  - `monthlyMin = oydagi ish kunlari × dailyMin` (AVTOMATIK — foydalanuvchi tanlovi; har oy ish kuniga qarab o'zgaradi).
  - `perMin = oylik ÷ monthlyMin`; `hourRate = perMin×60` (soatlik stavka).
  - Kunlik: kech (grace keyin) + erta (grace keyin) + «o'z hisobidan» awayMin (yoki belgisiz→kamera) → `missMin += min(dailyMin, lm+em+bkm)` (bir kunlik normadan oshmaydi). Yo'qlama → to'liq kun (`dailyRate`).
  - `total = round(absent×dailyRate) + round(missMin×perMin)` (jami ushlanma). `workedMin = scheduledMin − absent×dailyMin − missMin`.
  - **Finding-2 tuzatildi:** skan yo'q + «o'z hisobidan» belgisi → «keldi, X daq ketdi» (yo'qlama emas).
- **Ko'rsatish:** oylik hisobotga **«Oylik (hisob)»** ustuni qo'shildi (= nominal prorata − ushlanma); Ushlanma tooltipi: ishlagan soat / norma + soatlik stavka + taqsimot. Maosh dialogida «Ishladi Xs / norma · soatiga …» + taqsimot.
- **Pre-existing bug tuzatildi:** `loadPayees` endi `workStart/workEnd/workDays` ni ham beradi → maosh dialogi shaxsiy ish vaqtini ishlatadi (ilgari standartga tushib qolardi).
- **Finding-1 tuzatildi:** «o'z hisobidan» prompti — Bekor yoki bo'sh → o'zgarmaydi; faqat **0** → belgini o'chiradi (ilgari bo'sh ham o'chirardi).
- **Narx jadvali:** eski kech/erta/oshiqcha-tanaffus **jarima summasi** maydonlari OLIB TASHLANDI (endi soatbay). Qoldi: kasal kun stavkasi + tushlik/tanaffus (daq/kun — kunlik sof soat shundan). Saqlashda jarimalar 0 ga yoziladi.
- **Mustaqil adversarial ko'rikdan keyin yana 2 edge-case tuzatildi:**
  - **Prorata bazasi** (real pul): `billingInterval` endi `personRules(s).workDays` bo'yicha prorata qiladi (`saWorkdaysFor`), ilgari qat'iy Dush–Juma edi. Shaxsiy ish kunli + oy o'rtasida kirgan xodimda gross va ushlanma endi BIR XIL bazada (misol: Dush/Chor/Juma, 15-dan → 7/13, ilgari 12/22 — ~21 000 so'm farq). Standart Dush–Juma va to'liq oy — o'zgarmaydi.
  - **Taqsimot mosligi** (faqat ko'rsatish): Ushlanma tooltipi/info endi komponentlarni DAQIQADA + bitta «qisman» summasi ko'rsatadi (ilgari kunlik cap ishlaganda komponent summalari jamidan oshib ketardi; pul to'g'ri edi).
- **Tekshirildi:** `attMetrics` birlik testi 13/13 (soatbay) + ko'p kunlik agregatsiya (22 ish kuni, 1 yo'qlama + kech 70daq + personal 120 → net 4 218 750, ≈165 soat × stavka) + `billingInterval` prorata 3/3 (standart/shaxsiy/to'liq). Grace, kunlik cap, personal-on-no-scan, eski Set/typesiz, hourRate×8≈dailyRate. JS sintaksis toza; 12 ustun = 12 sarlavha; ✏️ 1 ta. Ko'rik: (a)-(h) toza (NaN/Infinity/manfiy to'lov/ustun-mismatch yo'q).

## 14) To'liq loyiha BUG-TEKSHIRUVI (6 quyi-tizim, adversarial tasdiq) — 11 ta xato tuzatildi

Baseline toza edi (JS sintaksis, testlar, 60 migratsiya). 6 agent parallel ko'rik → 18 topilma → adversarial tasdiq → 11 ta haqiqiy xato tuzatildi (7 ta yolg'on signal rad etildi).

- **[H1] Maosh — checkout skani yo'q bo'lsa soxta «erta ketish»** (`attMetrics`): chiqish skani bo'lmaganda oxirgi adashgan skan (tushlik/ikkilangan) «ketgan» deb olinib, to'liq kungacha maosh noto'g'ri kesilardi (soatbay o'tgandan keyin kuchaygan edi). Endi kech FAQAT `'in'`, erta ketish FAQAT `'out'` skan bilan hisoblanadi; checkout yo'q → jarima yo'q (qo'lda «o'z hisobidan» belgilash mumkin). `agg()` display ham tuzatildi. **Bu skrinshotdagi o'qituvchilarning «Erta ketish» muammosining asl sababi.** Test: 5/5.
- **[M1] Qaytarilgan (chargeback) invoice qarzdan yo'qolardi** (`reverse-payment.sql`): to'liq reverse → status `'reversed'` bo'lib, moliya hamma joyida qarz=0 ko'rardi (undiruv to'xtardi). Endi `'pending'` (refund kabi) — **qarz tiriladi**; `reversedAt` audit saqlanadi. Test: debt 500000 tiklandi.
- **[M2] O'IBDO' (zavuch) API orqali o'quvchi holatini o'zgartira olardi**: trigger faqat qabulxonani bloklardi. Endi `(reception OR zavuch) AND NOT admin_head` — holat faqat Ma'muriyat. Superuser/service_role tegilmaydi. Test: zavuch 42501, direktor OK, seed OK.
- **[M4] reverse_payment credit_ledger nomuvofiq yozardi**: avans qisman sarflangan bo'lsa delta `-v_from_credit` (ortiqcha) edi. Endi `-least(v_cr, v_from_credit)` (haqiqatda olib tashlangani). Test: delta −30000, balanceAfter 0.
- **[M5] Uzum reverse — balansga qo'llangan to'lovni noto'g'ri invoice'dan qaytarardi** (`payments/index.cjs`): confirm paytida invoice terminal bo'lib pul balansga ketgan bo'lsa, reverse aloqasiz invoice/avansni buzardi. Endi `appliedTo` yoziladi; balans holatida invoice reverse QILINMAYDI — ma'muriyatga `needsManualReverse` belgilanadi.
- **[M6] writeBatch atomik emas → referral ikki marta chegirma** (`admin.html` invoice generatsiya): invoice'lar (chegirma bilan) yozilib, referral_ledger alohida oxirgi batchda yozilardi; oraliqда uzilса keyingi oyda referral qayta qo'llanardi. Endi ledger SHU BATCHDA (invoice bilan birga) + invoice'ga `referralUsedIds` yoziladi + qayta ishga tushganda yetishmagan ledger qatorlari TIKLANADI (o'z-o'zini davolaydi).
- **[L1]** Ruhsat/kasallik sanashda shaxsiy ish kunlari ishlatiladi (global Dush–Juma emas). **[L2]** A4 maosh hisobotiga «Davomat ushlanmasi» ustuni qo'shildi (gross−avans−ushlanma=net mos). **[L3]** `SESSION.email` o'rnatiladi (audit `by/createdBy` endi rolni emas, foydalanuvchini yozadi). **[L4]** Arz-shikoyat vaqti Asia/Tashkent (+05:00) da (UTC emas).
- **Rad etilgan (yolg'on signal):** reception chegirma = pulga ta'sir (foydalanuvchi atayin xohladi), refund over-refund (clamp bor), cashier applied_payments (RLS to'sadi), owns_child key (import holati), bus search_path (pg_temp bor), onSnapshot onError (kichik). + **M3 (admin/admin_head'da «students» tab yo'q)** — buzadigan xato emas, qoldirdim (ularga o'quvchi boshqaruvi berish = alohida qaror).

## 15) Statistika — MOLIYA DASHBOARDI qo'shildi

- **Asosiy «Statistika» paneliga** (direktor/moliya) moliyaviy bo'lim: oylik **sof foyda/zarar**, moliyaviy oqim, xarajat taqsimoti.
- **KPI plitkalar** (joriy oy): Sof foyda/zarar (yashil/qizil), Kirim, Chiqim, Foyda marjasi, Qarzdorlik, Avans.
- **Moliyaviy oqim** — so'nggi 6 oy «Kirim vs Chiqim» guruhlangan ustun diagrammasi (inline SVG, tashqi kutubxonasiz); har oy ustida o'sha oyning sof foydasi. Ranglar CVD (rang ko'rlik) uchun validator bilan tekshirilgan (Kirim #1F7A4D, Chiqim #E08A2E, ΔE>8) + qiymat yorliqlari + hover (`<title>`).
- **Xarajat taqsimoti** — joriy oy xarajatlari toifa bo'yicha (Maosh/Kommunal/Ijara…) saralangan gorizontal ustunlar + summa + %.
- Hisob-kitob `renderAccounting` bilan bir xil mantiq (balans-aware `paidAmt`, `monthColl`, `byCat`). Faqat `isAdmin || finance_mgr || treasurer`.
- **Bloklamaydi:** o'quvchi statistikasi darhol chiqadi; moliya (barcha invoice/xarajat) FONDA yuklanadi (`dash-fin` placeholder).
- **To'lov usuli bo'yicha kirim** — donut diagramma (Naqd/Click/Uzum/Bank/Terminal…) + izoh (usul · summa · %). Ranglar app'ning kanonik to'lov-usuli ranglari (renderAccounting bilan bir xil).
- Tekshirildi: JS sintaksis toza; Chromium bilan vizual preview (grafiklar to'g'ri chiqadi, layout mobil/desktop).

## 16) To'lov TAKROR himoyasi kuchaytirildi (double-apply)

- **Muammo:** kassir bitta to'lovni ikki marta kiritsa (har submit — yangi payId) — `apply_payment` ikki marta qo'llanardi (idempotentlik faqat BIR xil payId uchun). Takror posboni bor edi, lekin oynasi **3 DAQIQA** — kassir bir necha daqiqa/soatdan keyin qayta kiritsa ushlanmasdi.
- **Tuzatildi:** server-tomon takror tekshiruvi oynasi **12 soat (bugun)**ga uzaytirildi + xabar aniqroq («allaqachon N daqiqa/soat oldin yozilgan — ota-ona BIR marta to'lagan bo'lsa Bekor bosing»). Double-click + lokal navbat posbonlari saqlanadi.
- **«Bekor» endi QO'LLANGAN to'lovlar uchun bloklangan** (foydalanuvchi talabi): `canCancelPay` — `MONEY_MOVED` (`applied`/`confirmed`/`paid`) holatlar Bekor qilinmaydi (tugma o'rnida «🔒 qo'llangan» izohi + tushuntirish). Faqat fantom/xato (`failed`/`pending`/`unmatched`/`prepared`/`created`) yozuvlar Bekor qilinadi. Handler'да ham defense-in-depth tekshiruv (eskirgan DOM/poyga). Shunday qilib «applied to'lovni Bekor qilib fakturani buzish» xatosi takrorlanmaydi — noto'g'ri to'lov faqat fakturani qayta hisoblash orqali to'g'rilanadi.

## 17) Oylik davomat hisobotini PDF/chop etish

- **Talab:** «Xodim va o'qituvchilarni kechikish tanafus barcha malumotlari oylik hisobotini pdf qilib chiqarib olish imkoni bo'lsin.»
- **Qo'shildi:** Xodimlar davomati → **Oylik hisobot** rejimida jadval sarlavhasida **«🖨 PDF / Hisobot»** tugmasi (faqat xodim bo'lsa ko'rinadi).
- **Hisobot (A4 yotiq):** ekrandagi jadvalning BARCHA ustunlari — №, Xodim (lavozim+Kamera ID), Ishlagan kun, Ish vaqti (soatbay), Tanaffus, Ruhsat, Kasallik, Ruhsatsiz, O'rt. kelish, Kechikish (kun), Erta ketish (kun), Ushlanma, **Nominal oylik**, **Oylik (hisob)** + pastda **JAMI** qatori (ishlagan kun / ish vaqti / ushlanma / nominal / net yig'indisi).
- Hisobot oxirida: soatbay model izohi (grace daqiqalari bilan) + **Oydagi ruhsat / kasalliklar** ro'yxati (xodim · tur · dan · gacha · sabab) + direktor imzo/sana.
- `printMonthReport(mon, bodyRows, roster, workSet, lvSorted)` — `renderStaffAttendance` ichida; mavjud `printAccountingReport` naqshi (A4 `<!doctype html>` + `@page` + `printHTML` iframe). Ma'lumot `loadMonth`da allaqachon hisoblangan `bodyRows`dan olinadi (qayta so'rov yo'q). Oy nomi `fmtMonthUz`, summa `fmtSom`.
- Tekshirildi: JS sintaksis toza (`node --check`); Chromium bilan A4 yotiq PDF + screenshot — 14 ustun to'liq sig'adi, layout toza.

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
