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

- **FAQAT o'quvchi holati cheklandi** (faollashtirish/muzlatish/chiqarish/sinov) — endi faqat **direktor** (Ma'muriyat rahbarida «O'quvchilar» bo'limi yo'q va server — RLS `students_upd` — unga ruxsat bermaydi; kerak bo'lsa alohida yoqiladi). Frontend: ⏯️ tugma `canManageStudentStatus()`; o'quvchi formasidan `payStatus/activeFrom/stopFrom` maydonlari qabulxonaga yashirildi (`_recHide`). Backend: `students` BEFORE INS/UPD trigger (`trg_reception_student_lifecycle`) — UPDATE'da 42501 xato, INSERT'da jim tozalanadi. Fayl: `reception-guard.sql`.
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

## 18) «Erkin ish soati» — direktor va aniq jadvalsiz xodimlar

- **Talab:** «Drektor va bazi xodimlar uchun ish soati erkin bo'lish kerak… maktab ishi bilan bazan kech keladi, maktabda uzoq qolib ketadi, aniq ish soati belgilanmagan. Bu xodimlar uchun ma'lumotiga ish soatini erkin belgilash joyini qo'shib qo'yamiz.»
- **Qo'shildi:** Xodim/O'qituvchi **kartochkasiga** «Erkin ish soati (aniq jadvalsiz)» belgisi (checkbox). Yoqilsa — davomatда **kech kelish / erta ketish / yo'qlama AVTOMATIK kesilmaydi**. Faqat ma'muriyat qo'lda «O'z hisobidan» belgilasa — o'sha daqiqa soatbay kesiladi. Ish vaqti/ish kunlari qoladi (faqat soat normasini hisoblash uchun ishlatiladi).
- **Texnik:**
  - `personRules(p)` -> `flexible` bayrog'i (`flexibleHours` '1'|true|1|'true').
  - `attMetrics` — `R.flexible` bo'lsa kunlik kech/erta/yo'qlama/avto-tanaffus mantiqi o'tkazib yuboriladi (faqat `personal` «O'z hisobidan» kesiladi). Oddiy xodimlar uchun hech narsa o'zgarmadi.
  - Forma: yangi `t:'checkbox'` maydon turi — yashirin input + bir xil nomli checkbox (belgilansa '1', aks holda '' — merge-upsert eski '1'ni to'g'ri tozalaydi).
  - `buildRoster` + `loadPayees` — payee/roster obyektlariga `flexibleHours` qo'shildi (attMetrics ikkala chaqiruvda ham ko'radi).
  - Davomat ekranida (kunlik + oylik) va PDF hisobotда «⏱ Erkin» belgisi; kunlik «Holat» da flexible xodim kelmasa qizil «Kelmadi» o'rniga ko'k «Erkin (belgilanmagan)».
  - **DB:** `migration/staff-workhours.sql` ga `flexibleHours text` ustuni (teachers + staff, idempotent). **Deploy'da migratsiya ishga tushishi SHART** (frontend-only sed yetmaydi — aks holda saqlashда «column not found»).
- **Tekshirildi:** 19 ta birlik testi (flex kech/yo'qlama kesmaydi, personal kesadi, excused 0, hourRate/monthlyMin saqlanadi, oddiy xodim o'zgarmagan); Chromium FormData (belgilanmagan->'', belgilangan->'1'); PG16'da migratsiya idempotent + insert/read; JS sintaksis toza.

## 19) Telefon + parol + OTP foydalanuvchi tizimi (6 bosqich)

Yangi auth: telefon (+998) + parol bilan ro'yxatdan o'tish/kirish, OTP (Eskiz SMS) tasdiqlash,
rollar (admin/teacher/parent), profil, ota-ona kabineti. Mavjud email/Google + moliya buzilmadi.

- **1 — DB** (`8a8a0a1`): `users` phone/firstName/lastName/status + RLS (rol/telefon/holatni o'zi o'zgartira olmaydi); `otp_codes` (mijozga yopiq); `child_claims.status`.
- **2 — auth server** (`3bd716a`): `auth/` xizmati. Parol — Supabase Auth bcrypt (sintetik email `998...@phone...`); OTP — HMAC hash, TTL/urinish/rate-limit; rol server tomonда majburlanadi (teacher→pending). Login lockout + umumiy xato. 60/60 test.
- **3 — mijoz qatlami** (`e95696f`): `sb/auth-api.js` (UI chaqiradi). Frontend/backend validatorlari aynan bir xil.
- **4 — frontend** (`60b88ac`): `index.html` telefon modali (ro'yxat/kirish/tiklash, maska, jonli parol qoidalari, ko'z, OTP taymer); `admin.html` login telefon YOKI email. 26/26 UI test.
- **5 — profil + tasdiqlash** (`87b1c27`): pending o'qituvchi gate; «Foydalanuvchilar» tabida tasdiqlash (banner + «✓ Tasdiqlash»); «Profil» (ism/parol/telefon-OTP); o'quvchi kodini 📋 nusxalash. 17/17 profil test.
- **6 — testlar + docs**: `migration/test-auth-rls.sql` (cross-rol RLS — parent faqat o'zini/farzandini; pending o'qituvchi o'zini tasdiqlay OLMAYDI; otp/login yopiq); `auth/DEPLOY.md` (fayllar/.env/deploy/ochiq savollar).
- **Arxitektura qarorlari (foydalanuvchi tasdiqlagan):** Eskiz SMS · o'qituvchi admin tasdig'idan keyin · ota-ona o'quvchi kodi bilan DARHOL (mavjud `claim_child`) · Supabase Auth + sintetik email.
- **⚠️ Deploy:** migratsiya + `auth/` xizmati (systemd `iqror-auth`, nginx `/authapi/`, port 8792) + Eskiz OTP shabloni moderatsiyasi shart. Batafsil — `auth/DEPLOY.md`.

## 20) Maktab ish oqimi auditi — davomat + moliya + loyiha chalkashliklari (7 yo'nalish)

7 yo'nalishda (o'quvchi davomati, xodim davomati→maosh, hisob-faktura hayot-sikli, to'lov qabul/taqsimlash,
moliya hisobotlari, ota-ona kabineti, loyiha/deploy) **45 ta** topilma; har biri kod o'qib + test bilan tekshirildi,
so'ng butun o'zgarishlar to'plami mustaqil «raqib» ko'rigidan o'tkazildi.

**O'quvchi davomati**
- Kurator saqlashi sinf o'zgargan oyda yarmida to'xtab qolardi → o'quvchi sinfi o'zgarsa uning oy qatorlari ham yangi sinf kalitiga ko'chadi (trigger `trg_student_class_rows`); saqlash o'quvchi-bo'yicha, xato bo'lsa kimniki saqlanmagani ko'rsatiladi.
- «Davomat %» endi server tomonda (trigger `trg_attendance_pct`) har saqlashda qayta hisoblanadi; admin, ota-ona kabineti va AI yordamchi — bitta formula (kasal/sababli maxrajdan chiqariladi).
- Bir ekrandan ikkinchi marta «Saqlash» bosilganda oraliqda boshqa xodim qo'ygan belgi (masalan «Bemor») endi ustidan yozilmaydi (har saqlashdan keyin ekran asosi yangilanadi; soxta «boshqa xodim o'zgartirgan» ogohlantirishi yo'q).
- Ro'yxatda chiqgan/muzlatilgan o'quvchilar (to'xtagan kundan keyin) yo'q; kamera (Hikvision) birinchi kirishidan «Keldi/Kechikdi» taklif qilinadi (qo'lda belgilangan holat ustiga yozilmaydi); bayram/yakshanba/kelajak kuni ogohlantiriladi.
- Sinf nomi/darajasi o'zgarsa o'quvchilari ham ko'chiriladi (kurator davomatni yo'qotmaydi). O'chirilgan o'quvchining ID'si yangi o'quvchiga berilmaydi.
- Profil (QR)/transkript chorak baholari ('q1'..'q4') to'g'ri o'qiladi; ota-ona kabinetida faqat joriy o'quv yili baholari.

**Xodim davomati → maosh**
- Bayram kunlari (`school_holidays`, «🎉 Bayramlar» tugmasi) — ushlanma hisoblanmaydi; bayramlar o'qilmasa maosh berish bloklanadi (jim noto'g'ri hisob yo'q).
- Xodim muzlatish -> qaytish: «to'xtatilgan davr» (`teachers/staff.pauses`) — o'sha kunlar maoshga kirmaydi va «yo'q» deb ushlanmaydi; avval qaytgan xodimning O'TGAN oy maoshi keyin hisoblansa 0 chiqardi.
- Xodim avansi: takroriy ID bloki, qayta bosishda ikkinchi yozuv yaratilmaydi.
- «Oylik hisobot»: xodimlar yoki o'qituvchilar ro'yxati o'qilmasa — hisobot chiqmaydi (avval butun guruh JAMI va imzoli PDF'dan ogohlantirishsiz tushib qolardi).
- Oylik hisobot, «Berish + chek» va «Oylik maoshni yozish» — bitta qoida (prorata, o'rinbosarlik, ushlanma, oxirgi yozuv); takroriy xodim ID'si bloklanadi; ma'lumot yuklanayotganda tugma o'chiq.
- Maosh berishda tarmoq uzilib qayta bosilsa — ikkinchi yozuv yaratilmaydi (yozuv bor bo'lsa «berildi» ko'rsatiladi).
- Maosh berish/«Oylik maoshni yozish» bonus stavkalarini (til/daraja/toifa) va jarima/tanaffus sozlamalarini HAR SAFAR bazadan o'qiydi; o'qib bo'lmasa — to'xtaydi (eski kesh yoki standart stavka bilan noto'g'ri «gross» yozilmaydi). Oylik hisobot ham yangi o'qiydi, o'qilmasa ogohlantiradi.
- Kamera ID bo'sh joysiz saqlanadi va solishtiriladi (nusxa-ko'chirishdagi « 101 » skan bilan mos kelmay, har kuni «yo'q» chiqardi).
- Takroriy maosh ID'li xodimlar «Oylik maoshni yozish»da bir-birining berilgan yozuvini olmaydi (nominal bilan, ogohlantirish bilan).
- Sinf nomi o'zgarsa fan o'qituvchilarining sinf biriktiruvi ham ko'chadi (qisman ko'chishda eski va yangi sinf ikkalasi saqlanadi; kurator — alohida, bitta sinf — bitta rahbar).

**Hisob-faktura (billing)**
- «Qayta hisoblash» endi to'lov qulfi ostida (`reprice_invoice`) — oraliqda kelgan to'lov ustiga yozilmaydi; holat bo'yicha keraksiz faktura faqat ANIQ holatda bekor qilinadi (o'tgan oy uchun shubhali holatlar tegilmaydi, ro'yxatda ko'rsatiladi).
- Holat o'tishi (muzlatish / chiqarish / qaytarish) faqat ⏯️ «Holat» oynasi orqali — tahrir formasida «To'lov/Ish holati»ni shunday o'zgartirish rad etiladi (forma to'xtatilgan davrni yozmasdi: muzlatilgan oylar hisoblanib, «[holat]» bekorlari qarz bo'lib tiklanardi). «Sinov»dan muzlatish/chiqarishda sinov kunlari hisoblanmaydi (qaytganda shu kundan); allaqachon to'xtatilgan bolani «Chiqdi»/«Muzlatish» qilganda to'lov ERTAROQ sanagacha qoladi; sinovdagi o'quvchini kelajak sana bilan faollashtirish rad etiladi (davomat ro'yxatidan yashirinmasin).
- Muzlatish → qaytish: `activeFrom` saqlanadi, oradagi kunlar «to'xtatilgan davr» (`students.pauses`) sifatida yoziladi — bir oyda muzlatib-qaytganda ham to'g'ri prorata. Qaytish sanasi kelajakda bo'lmaydi; noto'g'ri yozilgan davrni direktor ⏯️ Holat oynasida tahrirlaydi/o'chiradi.
- Kasal kun chegirmasi faqat haqiqatan TO'LANGAN kunlar uchun (sinov/muzlatilgan/grant/fakturasiz oy — yo'q).
- Narx kaliti IT/MED guruhdan ham aniqlanadi; monitoring chegirmasida «Informatika» hisoblanadi; qabulxona qo'shgan o'quvchi ro'yxatga olingan kundan prorata bilan.
- «Bekor»/«O'chir»/«To'lanmaganlarni o'chirish» — qulf ostida «to'lov yo'q»ligi qayta tekshiriladi. Yetim fakturalarda «Ehtimoliy egasi» ko'rsatiladi va ular o'chirilmaydi.
- O'quvchi tahrirlanganda/import qilinganda `studentId` endi o'zgarmaydi (avval import qilingan o'quvchilarda hujjat ID'siga almashib, qarz/avans/davomat «yetim» qolardi).
- Yangi o'quvchi ID'si bazadan tekshiriladi (bir vaqtda qo'shish / boshqa o'quvchining ID'si bloklanadi); Excel importda takroriy / o'chirilgan o'quvchi ID'si yoki boshqa ismga tegishli ID — qator o'tkaziladi, ogohlantiriladi. Bir ID bilan ikki xil ismli qator kelsa — IKKALASI ham o'tkaziladi (nusxa ko'chirilgan aka-uka ID'si boshqa bolani jim boshqa sinfga ko'chirmaydi); bazada to'qnash ID bo'lsa — ism AYNAN mos kelgan bittasi (bir xil ismlilar orasida — hujjat ID'si shu ID bo'lgani), aks holda o'tkaziladi.
- «Qayta hisoblash» to'lov qulfi bilan bir tartibda (o'zaro qulflanish yo'q); qaytarish (refund/reverse) qulf ostida qayta tekshiriladi; biriktirilmagan to'lov faqat to'liq qaytariladi.

**To'lovlar (Click/Uzum/kassa)**
- Uzum/Click: mavjud bo'lmagan ustunga yozish (PGRST204) sabab to'lov «xato» deb qaytmaydi; takroriy so'rov ikki marta qo'llanmaydi; o'quvchi kaliti doim kanonik (`IQ-xxxx`); 12 belgili kod bilan to'lov topiladi.
- Biriktirilmagan to'lov: biriktirish (`assign_payment`) va qaytarish bir-birini bloklaydi (ikki marta pul yo'q).
- Avans ko'chirish (reattribute) to'lov yozuvini ham ko'chiradi — Moliya tekshiruvida soxta «Ortiqcha» yo'q.
- Qaytarishning takroriy so'rovi (javob yo'qolgan) birinchi natijani qaytaradi — «qo'lda qaytarish» belgisi yo'qolmaydi; vaqtinchalik xatodan keyin avtomatik qaytsa, eski belgi tozalanadi.
- Provayder pul ALLAQACHON qo'llangandan keyin bekor qilsa/qaytarsa (javob yo'qolgan, restart): Click «bekor» va Uzum «reverse» posbonni tekshiradi — aynan shu fakturaga qo'llangan bo'lsa avtomatik qaytariladi (`reverse_payment`), balansga qo'llangan / faktura topilmagan / avans allaqachon sarflangan (`unrecovered`) bo'lsa — «↩️ Qo'lda qaytarilishi kerak» navbatiga (jim yo'qolmaydi).

**Ota-ona kabineti**
- Farzandni bog'lash import qilingan o'quvchida ham ishlaydi (ID yoki hujjat kaliti); kalitlari to'qnashgan (eski import dublikati) o'quvchida bog'lash rad etiladi va boshqa oilaning ma'lumoti hech qachon ochilmaydi.
- Server ruxsati (RLS) qator-aniq: `owns_child` (studentId bilan kalitlangan jadvallar) va `owns_student_doc` (students / student_private / student_phones — hujjat ID bilan). Bir ID ikki o'quvchiga tegishli bo'lsa (eski import: takroriy ID yoki biri hujjat ID'si, ikkinchisi o'quvchi ID'si) — shu ID bo'yicha ota-onaga HECH NARSA ochilmaydi (avval aniq-kalit moslash boshqa oila bolasining maxfiy ma'lumotini ko'rsatib qo'yardi). Ro'yxati — «⚠️ Ma'lumot sifati» oynasida («⛔ To'qnash o'quvchi ID'lari»). AI yordamchining `/student-summary` tekshiruvi ham shu qoida bilan (faqat faol bog'lanish, to'qnash kalit — 403) va import qilingan bolaning ma'lumotini kanonik ID bo'yicha topadi.
- Davomat % noma'lum bo'lsa «—» (0% emas); sinf o'rtachasi faqat yetarli ma'lumot bo'lsa; faqat joriy o'quv yili baholari; profil/transkript chorak baholari to'g'ri.

**Moliya hisobotlari**
- Qo'lda to'lov «Sana»si faqat oxirgi 31 kun ichida (kelajak/juda eski sana rad etiladi); darhol chop etiladigan chek, qayta chop etish va kassa — bir xil kun; «📋 To'lov tarixi» ham shu kunni ko'rsatadi (kiritilgan kun — izohda).
- «To'lov usuli bo'yicha kirim» va sana bo'yicha yig'im — HAQIQIY to'lovlardan (Toshkent kuni; qo'lda kiritilganda — chekdagi «Sana»), barcha ekranlarda bir xil; qaytarilgan pul bir marta ayiriladi; maosh ikki marta hisoblanmaydi; to'lovlar o'qilmasa «0» emas, xato ko'rsatiladi.
- «↩️ Qo'lda qaytarilishi kerak» kartasi — Uzum qaytargan / Click bekor qilgan, lekin avtomatik to'liq ayirib bo'lmagan to'lovlar (sababi «Izoh»da). «↩ Fakturadan» tugmasi pulni tanlangan fakturadan ayiradi (naqd qaytarish yozilmaydi, Moliya tekshiruvi farqsiz yopiladi) — faqat QOLDIQni: server o'zi qaytarib bo'lgan va avval qo'lda ayirilgan qism hisobga olinadi (bir pul ikki marta ayirilmaydi); avansdagisi — «✏️ Avansni tuzatish».
- Bosh sahifadagi «O'rtacha davomat» — faqat davomati ma'lum o'quvchilar bo'yicha (noma'lum «0» deb hisoblanmaydi).
- Oylik xulosa (ma'lumotnoma) o'quvchining kanonik ID'si bilan yoziladi — import qilingan bolada ham hisobotda va ota-ona kabinetida ko'rinadi (eski yozuvlar ham o'qiladi).
- «Davomat %» faqat server triggeri yozadi (admin ekrani endi `students/<studentId>` ga yozmaydi — import qilingan bolada jim yo'qolar, to'qnashuvda boshqa bolani buzardi); monitoring tasdiqlanganda «Umumiy ball» o'quvchining hujjat ID'si bilan yoziladi (import qilingan bolada ham yangilanadi).

**Loyiha/deploy chalkashliklari**
- Migratsiya fayllarini ALOHIDA ishga tushirib bo'lmaydi (qo'riqchi) — eski usul xavfsizlik/moliya qoidalarini eski holatga qaytarardi; endi faqat butun zanjir (`deploy.sh`).
- `deploy.sh` auth serverini ham yangilaydi (yoqilgan bo'lsa qayta ishga tushiradi); xizmat boshqa papkadan (`/opt/iqror`) ishlasa server kodini o'sha yerga ham yozadi — papka egasi nomidan, `config.json`/`node_modules` va papkalarning egasi/ruxsati o'zgarmaydi (avvalgi `chown -R` maxfiy config.json'ni xizmat o'qiy olmaydigan qilib qo'yishi mumkin edi); kod fayllari doim 0644/0755 (tizim umask'iga bog'liq emas); birinchi marta yo'q `auth/`, `sb/` papkalari egasi nomiga yaratiladi.
- O'quvchi holati/o'chirish tugmalari — faqat direktor (server qoidasi bilan bir xil); «📚 Sinflar» — faqat direktor.
- Deploy oxiridagi baza tekshiruvi (`migration/verify-db.sh`): kengaytma funksiyalari (pgcrypto — Supabase'da `extensions` sxemasida) va Supabase'ning standart ruxsatlari endi soxta «farq» bermaydi (avval har deployda «36 ta funksiya yo'q / 384 ta obyekt» deb chiqardi). Haqiqiy xavf alohida: 🔴 repo'da yo'q RLS policy, 🔴 RLS o'chiq jadval mijozga ochiq, 🟠 mijozga ochiq ortiqcha view / funksiya / farqli ta'rif.

**Ma'lum cheklovlar / ochiq savollar**
- 7–9-sinf monitoring chegirmasida «Algebra/Geometriya» alohida fan sifatida hisoblanmaydi (maktab tasdiqlasa qo'shiladi).
- Ma'muriyat rahbari o'quvchi holatini o'zgartira olmaydi (hozircha faqat direktor) — kerak bo'lsa yoqiladi.
- Hech qachon davomat yozilmagan eski o'quvchilarda «Davomat %» eski qo'lda kiritilgan qiymat (ko'pincha 0) bo'lib qoladi — birinchi davomat saqlanganda avtomatik to'g'rilanadi.
- Kalitlari almashib ketgan eski import fakturalarini (yetim) egasiga ko'chirish — har holat alohida (SQL); «Ehtimoliy egasi» ustuni yordam beradi.
- To'qnash o'quvchi ID'larini tuzatish (ID'ni ko'chirish) ham hozircha texnik yordam (SQL) bilan; tuzatilguncha bu bolalarning ota-ona kabineti yopiq. `rekey-students.sql`ni bunday holatda ishga tushirmang — u `child_claims`ni ham ko'chiradi.

## 21) Aka-uka 10% chegirmasi (oktyabr regressiyasi) + «Qarzdorlar» → «Eslatma» SMS

**Aka-uka chegirmasi — 3 farzandli oila oktyabrda faqat bittasiga 10% olgan edi (sentyabrda hammasi olgan)**
- Sabab: 14-oktyabrdagi o'zgarish oilani FAQAT ota/ona F.I.Sh bo'yicha guruhlardi (farzand ismi faqat ota/ona maydonlari butunlay bo'sh bo'lsa). Kartalarda ota/ona maydonlari har xil to'ldirilgan bo'lsa (birida faqat ota, birida faqat ona — o'z familiyasida) oila «2 + 1» bo'linib, 2 kishilik guruhda faqat bittasi (ID tartibi) 10% olardi. Skrinshotdagi holat (IQ-0255 → 2 610 000, IQ-0268/IQ-0276 → 2 900 000) testda aynan qayta hosil qilindi.
- Tuzatma: familiya o'zaklari = farzand ismi ∪ ota F.I.Sh ∪ ona F.I.Sh (bir xil telefon sharti o'zgarmadi). Faqat qirra QO'SHADI: sentyabr usulida ham, ota/ona usulida ham topilgan oila guruhlanadi; begona (umumiy o'zaksiz) bolalar bir telefonda bo'lsa ham qo'shilmaydi. 40 000 tasodifiy ssenariyda hech kimning avvalgi 10% i olinmadi. O'quvchi ismi-familiyasi o'zgarsa ham «Qayta hisoblash» eslatmasi chiqadi.
- Familiya taqqoslash yozuv farqlariga chidamli: apostrof turlari (Gʻ / G' / G‘ / G’ / G`) bir xil; lotin ↔ rus transliteratsiyasi x/h (Xasanov / Hasanov / Хасанов) va q/k (Qodirov / Kodirov / Қодиров) bir xil.
- O'quvchi kartasida «Aka-uka chegirmasi» → yangi «Yo‘q — oilaga qo‘shilmasin»: bola umumiy telefon tufayli begona oilaga noto'g'ri qo'shilib qolsa, avtomatik guruhdan chiqariladi («Ha» — avvalgidek majburiy 10%).
- Ota/ona F.I.Sh to'ldirilgan bo'lsa, farzand ismidan faqat FAMILIYA (…ov/…ova/…ev/…eva) va «… o'g'li / … qizi» oldidagi otaning ismi olinadi — «Abdulla», «Ozoda» kabi ismlar begona oilalarni (masalan buvining telefonidagi amakivachchalarni) birlashtirmaydi. Bir telefonda umumiy so'zli, lekin guruhlanmagan bolalar «Ehtimoliy aka-uka guruhlanmadi» ogohlantirishida ko'rsatiladi (admin «Ha» qo'yadi yoki ota/ona F.I.Sh ni to'ldiradi); 8+ bolali «oila» ogohlantirishida telefon va bolalar ro'yxati bor.
- «↻ Qayta hisoblash» endi aka-uka ogohlantirishlarini ham ko'rsatadi (masalan, bitta telefonda 8 tadan ortiq bola — avtomatik chegirma berilmadi).
- ⚠️ Mavjud oktyabr fakturalari avtomatik o'zgarmaydi: «To'lovlar» → 2026-10 → «↻ Qayta hisoblash» (to'lanmaganlari 2 610 000 ga tushadi). Oktyabrni TO'LIQ to'lab bo'lgan oilalar uchun: qayta hisoblash yangi narxi to'langandan KAM bo'lgan to'langan fakturalarni alohida ro'yxatda ko'rsatadi — tasdiqlansa farq (masalan 290 000) o'quvchi AVANSIGA qaytadi (keyingi oy to'loviga ishlatiladi), faktura «to'langan» qoladi; narx OSHGAN to'langan fakturaga avvalgidek tegilmaydi (qarz tiklanmaydi). Avtomatik taklif faqat aniq holatda: 3+ farzandli oila (slot raqobati yo'q) va aka-uka chegirmasiz qayta hisoblangan narx (o'sha prorata/kasal kun/referral bilan) to'langan summaga TENG — ya'ni farq faqat kechikkan 10%; qolganlari (2 farzandli oila, oraliq monitoring, prorata o'zgargan) faqat «qo'lda tekshiring» ro'yxatida. Server: `reprice_invoice` — `p_meta.paidDecrease` faqat 0 < yangi < to'langan kamayishga ruxsat beradi (qulf ostida, avans jurnali bilan). Referral jurnali o'qilmasa generatsiya/qayta hisoblash to'xtaydi (ishlatilgan referral ikki marta qo'llanmasin).

**«Moliya» → «Qarzdorlar» → «Eslatma» — endi haqiqiy SMS (Eskiz, auth-server `/authapi/sms-remind`)**
- Bosilganda avval ko'rib chiqish: o'quvchi, ota-ona telefoni, qarz (oylar bilan) va SMS matni ko'rsatiladi; tasdiqlansa yuboriladi.
- Qarz, telefon va matn SERVERDA aniqlanadi (mijoz summasiga ishonilmaydi; o'quvchining barcha kalitlaridagi fakturalar); ruxsat — faqat faol direktor / moliya menejeri; ID to'qnashuvida rad (SMS boshqa oilaga ketmasin); bir o'quvchiga kuniga BITTA (takror bosish / parallel so'rovda ham bitta SMS — baza PK claim); Eskiz aniq rad etsa — qayta urinish mumkin, natija noaniq bo'lsa (tarmoq/timeout) — bugun qayta yuborilmaydi (ikki marta SMS ketmasin); soatlik/kunlik limit parallel so'rovlarda ham oshmaydi; Eskiz xatosi tushunarli ko'rsatiladi (masalan, shablon tasdiqlanmagan); `sms_log`da kim yuborgani (`sentBy`) saqlanadi; avtomatik `sms-worker` shu kuni qo'lda eslatma olgan (yoki olayotgan) o'quvchini o'tkazadi; Eskiz so'rovi 20 s da uziladi (osilib qolmaydi).
- `sms-worker` (cron): faqat yaroqli O'zbekiston mobil raqamiga yuboradi (otaniki noto'g'ri bo'lsa onaniki); Eskiz'ga umuman ulanib bo'lmasa claim qaytariladi va run to'xtaydi (xabarlar keyingi cron'da ketadi); ketma-ket 5 ta Eskiz xatosida to'xtaydi; Eskiz aniq rad etganlari (`rejected:`) qayta urinadi, natija noaniq bo'lganlari qayta yuborilmaydi; ID to'qnashuvidagi o'quvchiga SMS yubormaydi; ismlar GSM-7 (SMS qismi ko'paymaydi). README cron: qarz eslatmasi 10:20 + `flock -w` (avvalgi `-n` bilan «new» bilan bir vaqtda jim o'tkazib yuborilardi).
- Talab: SMS matni Eskiz kabinetida shablon sifatida tasdiqlangan bo'lishi kerak (auth/README.md).

## 22) Ro'yxatdan o'tishda «Noto‘g‘ri rol» + chet el ota-ona telefon raqamlari

**«Noto‘g‘ri rol» (SMS keldi, «Yakunlash» bosilganda xato)**
- Sabab: brauzerda uzoq ochiq qolgan ESKI sahifa (13-oktyabrgacha «O‘qituvchi» tugmasi) serverga `role:'teacher'` yuboradi, yangi server esa faqat `staff`/`parent` ni qabul qilardi. Server endi `teacher` ni ham «Xodim» (`staff`, tasdiq kutadi) deb qabul qiladi; katta-kichik harf/bo'shliq farq qilmaydi. Boshqa qiymat (admin, director…) — avvalgidek rad, lekin xabar aniq: «Sahifani yangilang (Ctrl+F5)…».
- Xodim ro'yxatdan o'tganda telefon bo'yicha «Xodimlar»dagi yozuviga (masalan IQX-001) avtomatik bog'lanadi; javob xabarida kod va lavozim ko'rsatiladi. «Foydalanuvchilar» → «✓ Tasdiqlash» oynasida HR lavozimiga mos rol (masalan «Moliya Menejeri» → «Moliya menejeri») OLDINDAN tanlanadi — direktor tekshirib «Saqlash» bosadi (xavfsizlik: avtomatik faollashtirish yo'q; Direktor/Ma'muriyat rahbari roli faqat taklif qilinadi).

**Chet el raqamlari (+7, +48, …) — ma'lumot sifatida to'g'ri, SMS esa FAQAT O'zbekiston raqamlariga**
- Yagona telefon qoidasi `server/phone.cjs` (PHONE-CANON bloki `sb/auth-api.js` va `admin.html` da AYNAN bir xil; `auth/phone.test.cjs` bloklar bir xilligini, 30 000+ tasodifiy kirishda natija bir xilligini va xavfsizlik invariantini tekshiradi). O'zbekiston: 998… / 9 xonali (faqat `+`siz). Chet el: FAQAT `+` (yoki `00`) bilan to'liq — `+48 789 706 619` → `48789706619` (bazada `+`siz). `+`siz uzun raqam noaniq (yaroqsiz); chala chet el raqami (`+7 903 157 11`) jimgina O'zbekiston raqamiga aylanmaydi.
- «⚠️ Sifat»: `+` bilan to'g'ri yozilgan chet el raqami xato emas. Yangi «🌍 Faqat chet el raqami — SMS ketmaydi» ro'yxati: O'zbekiston raqami yo'q oilalar (ikkinchi maydonga O'zbekistondagi raqamni yozish taklifi). Yaroqsiz raqam yonida faqat ISHONCHLI maslahat («79031571124 → +7 903 157 11 24 ?»); xato terilgan O'zbekiston raqamiga chet el raqami, chala raqamga O'zbekiston raqami taklif qilinmaydi. «Telefon umuman yo'q» — faqat ikkala maydon bo'sh bo'lsa.
- **SMS faqat O'zbekiston raqamlariga** (foydalanuvchi talabi): OTP (ro'yxat/parol tiklash/telefon almashtirish) chet el raqami uchun darhol aniq xabar bilan rad (Email/Google bilan kirish taklif qilinadi; bazaga qaralmaydi — enumeration yo'q); «Eslatma» va `sms-worker` faqat O'zbekiston raqamini oladi (ota chet el raqami bo'lsa — onaning O'zbekiston raqami), O'zbekiston raqami bo'lmasa — SMS yo'q (sababi aytiladi); `payments/sms.cjs` chet el raqamiga Eskiz'ga so'rov yubormaydi. Oldingi commit'dagi xalqaro SMS (`send-global`), «maktab ma'lumotida bormi» tekshiruvi, xalqaro chegaralar va IP cheklagich olib tashlandi.
- Telefon maydoni: maska raqamlarni HECH QACHON tashlamaydi (ortiqcha raqam ko'rinadi, raqam yaroqsiz — avval `+998 ` ortidan yozilgan boshqa raqam 9 xonaga kesilib begona odamning O'zbekiston raqamiga aylanib, OTP kodi unga ketishi mumkin edi); oyna ochilganda kursor maydon OXIRIGA qo'yiladi; tozalangan maydon bo'sh qoladi; `+998 ` ortidan `+` yozilsa — boshqa raqam rejimi (va «faqat O'zbekiston» xabari). 400 000 tasodifiy kirishda: yaroqsiz kiritma maska orqali hech qachon yaroqli O'zbekiston raqamiga aylanmaydi.
- Xavfsizlik: ro'yxat xabaridagi HR maydonlari (kod/lavozim) HTML belgilarisiz; index.html server xabarini matn sifatida ko'rsatadi (XSS yopildi). Admin login: `@` bor qiymat doim email.
- Tasdiqlash oynasi: telefon bo'yicha (bog'lanmagan) taklifda oddiy rol «yuqori huquqli» deb atalmaydi — «yozuv hali bog'lanmagan» deyiladi.
- Aka-uka guruhlash o'zgarmadi (raqamning oxirgi 9 xonasi; 20 000 tasodifiy ssenariyda eski/yangi natija bir xil).

## 23) «Eslatma» SMS'ini Eskiz rad etdi — shablon NAQSHI bilan moslash

- Sabab: Eskiz SMS'ni kabinetga yuborilgan ASL matn (`Eslatma: {name} uchun {month} …`) bilan emas, moderator tasdiqlagan NAQSH (`GET /api/user/templates` → `template`) bilan solishtiradi; naqshda o'zgaruvchi joylar `%w` (1 so'z), `%d` (1 son), `%w{1,4}` (1–4 so'z). Tizim esa ism («Familiya Ism» — 2 so'z), oylar («09.2026, 10.2026» — 2 bo'lak) va summani («5 800 000» — 3 bo'lak) bo'shliq bilan yozardi — bitta so'zli naqshga sig'masdi. Matn hali moderatsiyada bo'lsa ham Eskiz xuddi shu «Этот смс текст еще не прошел модерацию» xatosini beradi.
- Endi: summa `5800000`, oylar `09.2026` / `09.2026,10.2026` / `08.2026-10.2026` (har doim bitta so'z; oraliq faqat ketma-ket oylar — §25); Eskiz naqshlari o'qiladi («Eslatma» — 10 daqiqa kesh, Eskiz 5 soniyada javob bermasa naqshsiz davom etadi; `sms-worker` — run boshida, `--dry` da ham) va ism naqshga sig'adigan shaklda olinadi (to'liq → «Familiya Ism» → «Ism» → «Familiya»). Admin tasdiq oynasida aynan yuboriladigan matn, ism qisqartirilgan bo'lsa — izoh, hech bir tasdiqlangan naqshga mos kelmasa — ⚠️ ogohlantirish. Eskiz rad etsa xabar sababini va tekshiruv buyrug'ini aytadi. Yangi modul: `payments/eskiz-template.cjs` (sof funksiyalar).
- Diagnostika (hech narsa yubormaydi): `cd ~/iqror-repo/payments && node eskiz-shablon.cjs` — Eskiz'dagi har bir matn holati/naqshi va tizimning har SMS turi (Eslatma, avtomatik qarz, yangi faktura, OTP) mosligi; mos bo'lmasa — aniq sabab (moderatsiyada / rad etilgan / `{name}` o'zgaruvchi qilinmagan / qaysi o'zgaruvchi necha so'z / qaysi belgi farq qiladi, masalan `'` U+0027 va `‘` U+2018) va nima qilish kerakligi. OTP qatori ✅ bo'lishi — tekshiruvning o'zi to'g'riligining belgisi (ro'yxat kodi SMS'i ishlayapti).
- Eskiz'ga matnni `{name}` bilan emas, HAQIQIY misol bilan yuborish tavsiya etiladi (izohda: ism 1–4 so'z, oy 1 so'z, summa 1 son).
- Testlar: `payments/eskiz-template.test.cjs` (22), `payments/eskiz-shablon.test.cjs` (24, soxta Eskiz bilan alohida jarayonda), `payments/sms.test.cjs` (+templates(): 41), `auth/sms-remind.test.cjs` (108: moslash, kesh, sekin Eskiz, parallel so'rovlar, sinxron xato); PG16 + PostgREST e2e (naqsh bilan yuborish, `sms_log` matni); Chromium (admin/index).

## 24) Telefon maydoni: kursor tahrir joyida qoladi, nusxa qo'yish (ko'rik topilmalari)

- Topilma (raqib ko'rigi, Chromium'da tasdiqlangan, o'rta): maska har kiritishda maydon qiymatini qayta yozardi — brauzer bunda kursorni OXIRGA sakratadi. Raqamning o'rtasini tuzatganda (masalan «91» ni «90» ga) keyingi raqamlar oxirga tushib, tartib buzilardi va ko'pincha BOSHQA yaroqli +998 raqam chiqardi — ro'yxat / parol tiklash / telefon almashtirish kodi begona odamga ketishi mumkin edi.
- Tuzatish: `sb/auth-api.js` → `bindPhoneInput` (index.html: kirish/ro'yxat/parol tiklash; admin.html: «Profil → Telefonni o'zgartirish»). Kursor tahrir joyida qoladi (o'ngidagi raqamlar soni saqlanadi); faqat bo'shliq o'chirilsa — yonidagi raqam o'chadi (tugma «ishlamay» qolmaydi), `+998` prefiksi raqamlari esa bu yo'l bilan o'chmaydi; to'liq raqam nusxa qilib qo'yilsa (`998901234567`, `+998 90 …`, kontaktlardagi ko'rinmas yo'nalish belgilari bilan) — maydon shu raqam bilan almashtiriladi (avval `+998 ` ortiga yopishib yaroqsiz bo'lardi). `+998 ` ortidan yana `998…` yozilsa — aniq maslahat (raqam avtomatik o'zgartirilmaydi). `auth-api.js?v=5` (kesh yangilanadi).
- Prefiksni tahrirlash mumkinligi (uchinchi topilma) — tekshiruvda rad etildi: xavfsiz (hech qachon begona raqam/SMS yo'q) va ataylab (kirish maydonida chet el raqami uchun) — o'zgartirilmadi.
- Testlar: `auth/phone.test.cjs` (157: brauzer semantikasini taqlid qiluvchi maydon, ko'rikdagi barcha ssenariylar, 30 000+ tasodifiy tahrir fuzz — raqamlar ketma-ketligi va kursor doim niyatdagidek; eski maska bilan aynan ko'rikdagi begona raqamlar chiqadi); Chromium: haqiqiy index.html/admin.html/auth-api.js + haqiqiy `request-otp` — tuzatilgan raqamga SMS, ssenariylar haqiqiy klaviaturada, 1500+ tahrir fuzz, mobil (Pixel 7) — 43/43.

## 25) Raqib ko'rigi (R6) tuzatmalari — telefon maydoni, Eskiz oylar/kesh, diagnostika buyrug'i

- **Telefon maydoni (yuqori, oldingi tuzatmaning regressiyasi):** chet el raqamida (`+47 912 345 67`) «+» oldida Delete
  bosilsa «+» o'chib, raqamlar 9 xonali O'zbekiston qoidasi bilan qayta o'qilib BEGONA `+998 …` raqamga aylanardi (OTP
  kodi o'shanga ketishi mumkin edi). Endi boshidagi «+» ga tegadigan qisman tahrir (Delete/Backspace/belgilab o'chirish/
  oldiga yozish) bekor qilinadi (qiymat va kursor joyida qoladi); butun maydonni belgilab yozish/o'chirish — odatdagidek.
  O'chirishdan keyin raqam talqini o'zgarsa (O'zbekiston ↔ chet el) — tahrir bekor. IME (kompozitsiya) paytida maska
  ishlamaydi — tugagach bir marta (raqamlar takrorlanmaydi); maydon ichida sudrab ko'chirish o'chiq; avtoto'ldirish
  (inputType yo'q) bloklanmaydi. Testlar: `auth/phone.test.cjs` 169; Chromium (haqiqiy klaviatura, CDP IME) 37 + avvalgi 86.
- **«Eslatma» oylari (o'rta):** 3+ oy har doim «birinchi-oxirgi» oraliq qilib yozilardi — oradagi TO'LANGAN oy ham
  qarzdek ko'rinardi (05,06,08,10 → `05.2026-10.2026`). Endi oraliq faqat ketma-ket oylar uchun:
  `05.2026,06.2026,08.2026,10.2026`, `05.2026,06.2026,08.2026-10.2026` (dekabr→yanvar ham ketma-ket). Bitta so'z bo'lib qoladi.
- **Naqshlar keshi:** yangilash xato bersa yoki Eskiz 5 soniyada javob bermasa — oxirgi MUVAFFAQIYATLI ro'yxat bilan
  davom etadi (avval ro'yxat tashlab yuborilib, mos matn o'rniga rad etiladigan matn ketardi va kunlik 3 urinish kuyardi).
- **Sinov rejimi (`sms.dryRun`):** naqshlar endi o'qiladi (faqat GET, `tplReader`) — sinovdagi matn haqiqiy matn bilan bir xil.
- **`eskiz-shablon.cjs`:** (1) har SMS turi o'zini yuboradigan jarayon sozlamasidan: «Eslatma»/OTP — auth
  (`/opt/iqror/auth/config.json` → `../auth/config.json`), debt/new — sms-worker (`./config.json` →
  `/opt/iqror/payments/config.json`); o'qilmagani «⚪ TEKSHIRILMADI» (✅ emas, chiqish 2); (2) tekshiruv 4 xil
  ism/oy/summa/kod bilan — moderator misolni so'zma-so'z tasdiqlagan bo'lsa ✅ emas, «SO'ZMA-SO'Z tasdiqlangan» deyiladi;
  (3) HAQIQIY misol bilan yuborilgan yozuvlar taniladi (moderatsiyada → ⏳ + kutish, rad etilgan → RAD ETGAN, apostrof
  farqi → U+2018 + «Tuzatish» aynan o'qilgan fayl bilan); (4) `--config=YO'L`, bir necha `--config`, nisbiy yo'l joriy
  papkaga nisbatan; sudo maslahati buyruq argumentlari bilan; buzilgan JSON xabari fayl bo'lagini (parolni) chiqarmaydi;
  `config.example.json`dagi to'ldirilmagan kalitlar rad etiladi. Testlar: `eskiz-shablon.test.cjs` 44, `eskiz-template` 25,
  `sms-remind` 114.

## 26) Raqib ko'rigi (R7) — R6 tuzatmalari ustidan

- **Telefon maydoni (yuqori):** chet el kodi yozilgandan keyin (`+48 `, `+`, `+7`) 9 xonali milliy raqam nusxa qilib
  qo'yilsa, u yaroqli O'zbekiston raqami deb topilib butun maydon jimgina `+998 …` ga almashardi (OTP begonaga). Endi
  to'liq raqam bilan almashtirish faqat maydonda (belgilangan qismdan tashqari) foydalanuvchi narsasi bo'lmasa: bo'sh
  yoki faqat «+998»; aks holda brauzer odatdagidek qo'yadi (`+48 789 706 619`). To'ldirilgan raqam ustiga belgilamasdan
  qo'yish ham jimgina almashtirmaydi.
- **IME:** kompozitsiya `compositionend`siz tugasa (o'rtada nusxa qo'yish, fokus ketishi, oddiy kiritish kelishi) —
  bayroq tiklanadi, maska o'chib qolmaydi. Ko'rinib turgan «+998» ni belgilab yozish endi ishlaydi (tugmalar yutilmaydi);
  ortida raqamlar bo'lsa — tahrir bekor (begona raqam yo'q).
- **`eskiz-shablon.cjs`:** avtomatik qidiruvda har tur uchun birinchi MAVJUD fayl jonli (o'z `config.json`ida kalit
  to'ldirilmagan bo'lsa `/opt`dagi boshqa faylga o'tib noto'g'ri ✅ bermaydi — «TEKSHIRILMADI»); bir xil email, boshqa
  parol — ikkala sozlama alohida login qilinadi (xato qaysi faylda ekani aytiladi, parol chiqmaydi); moderator faqat
  ba'zi joylarni o'zgaruvchi qilgan yoki ism uchun «%w %w» yozgan bo'lsa — «Tuzatish» emas, qayta yuborish maslahati;
  sinov qiymatlarida 1 so'zli ism ham bor (5 to'plam).
- Ko'rik yakuni (4 tasdiqlangan — hammasi tuzatilgan) bo'yicha aniqlashtirish: nusxaning o'zi to'liq xalqaro raqam bo'lsa
  (`+`/`00` bilan yoki `998` + 9 raqam) — u maydonni almashtiradi (natija aynan nusxadagi raqam); 9 xonali milliy qism esa
  foydalanuvchi yozgan narsa ustiga hech qachon almashtirmaydi. Tashlab ketilgan kompozitsiya `beforeinput`da ham
  aniqlanadi — «oldingi qiymat» hozirgi qiymatdan olinadi (eskirgan qiymatga tiklash yo'q). `auth-api.js?v=7`.
- Rad etildi: `smsMonths` uzilishli oylarda SMS uzunligi oshishi — ataylab (to'g'rilik muhimroq, §25).
- Testlar: `phone.test` 186 (tuzatmasiz yangi testlar yiqiladi), `eskiz-shablon.test` 48; Chromium 53 + 43 + 19 + 10 + 14.

## 27) Qabulxona — o'quvchini «⏹️ Chiqarish»

- «O'quvchilar» ro'yxatida qabulxonaga (`reception`) har o'quvchi qatorida **⏹️** tugmasi (chiqib ketganlarda yo'q).
  Oyna faqat bitta amal — «Chiqarish (butunlay ketdi)» va sana. Faollashtirish/muzlatish/sinov, sanani tuzatish,
  «to'xtatilgan davrlar» — avvalgidek faqat direktor (⏯️). O'IBDO'/kassir/ma'muriyat rahbarida tugma yo'q.
- Chiqqan sana — **o'tgan oyning 1-sanasidan oldin emas** (eski oylar to'lovi orqaga qarab o'zgarmasin); undan
  oldingisi — direktor orqali. Saqlangach: «Direktorga ayting: To'lovlar → tegishli oy → ↻ Qayta hisoblash».
- Yozuv qoidasi direktornikidek (`payStatus='chiqdi'`, `stopFrom`; muzlatilgan bo'lsa eski to'xtatish sanasi
  saqlanadi; sinovdan chiqsa `activeFrom = stopFrom + 1`). Qabulxona yozuvi — sof UPDATE (`updateDoc`), keyin bazadan
  qayta o'qib tekshiriladi: o'zgarmagan bo'lsa «Saqlanmadi…» (jim «muvaffaqiyat» yo'q). Sanalar Toshkent vaqti bo'yicha.
- **Baza himoyasi** (`migration/reception-guard.sql`, `trg_reception_student_lifecycle`): qabulxonaga FAQAT shu o'tish
  ruxsat — `payStatus` → `chiqdi` (avval chiqdi emas; NULL/'' ga o'tkazish — rad), `pauses` o'zgarmaydi, `stopFrom` —
  HAQIQIY sana (`2026-99-99` — rad) va (o'zgarmagan yoki ≥ o'tgan oyning 1-sanasi, Toshkent vaqti; muzlatilganda faqat
  eski sanadan ERTAROQ), `activeFrom` — o'zgarmagan, sinovdan chiqsa AYNAN `stopFrom+1`. Tekshiruv NULL-xavfsiz.
  Boshqa har qanday holat o'zgarishi — 42501 (O'IBDO' — avvalgidek hammasi taqiqlangan). Yangi qator tozalanishi
  (INSERT) endi FAQAT haqiqatan yangi qatorga: shim `setDoc`i — UPSERT, mavjud qatorga upsert UPDATE qoidasidan o'tadi.
- Testlar: PG16 40/40 (oddiy UPDATE + shim'ning upsert shakli `INSERT … ON CONFLICT DO UPDATE SET col = EXCLUDED.col`,
  NULL hujumlari, muzlatilgan/sinov qoidalari, yaroqsiz sanalar); haqiqiy stek e2e (PG16 to'liq zanjir + PostgREST 12 +
  supabase-js + haqiqiy shim + haqiqiy `openStatusModal`) 24/24 — eski kodda (c082e4c) 16 tasi yiqiladi; Chromium 30/30.

## 28) Biriktirilmagan to'lov — «💡 Ehtimol shu o'quvchi» takliflari

- «To'lovlar» → «⚠️ Biriktirilmagan to'lovlar» → **Biriktirish**: o'quvchilar ro'yxati tepasida to'lovchi yozgan ism
  bo'yicha **3 tagacha** taklif: to'liq ism, ID · sinf, joriy qarz, «NN% mos» (va «qarz = summa ✓» belgisi).
  Moslik 60% dan past bo'lsa — bo'lim chiqmaydi (oddiy ro'yxat). Taklifni bosish = ro'yxatdan tanlash: bitta
  o'quvchi rejimida tasdiqlash oynasi (endi kimga va qancha — «Ism (ID) — summa» ham yoziladi), bo'lib rejimida
  «+ Qo'shish». **Tizim hech qachon o'zi biriktirmaydi.**
- Yagona modul **`sb/name-match.js`** (brauzer: `import()` → `globalThis.IqrorNameMatch`; server: `require('../sb/name-match.js')`
  — keyingi avtomatik biriktirish uchun; tashqi kutubxona yo'q). `normalizeName`: kirill → lotin (ғ→g', қ→q, ў→o', ҳ→h,
  ё→yo, ю→yu, я→ya, ш→sh, ч→ch, ц→ts; «е» so'z boshida/unlidan keyin → ye), kichik harf, bo'shliqlar, barcha apostroflar
  → `'`, h→x (kh→x; sh/ch tegilmaydi), yeva/yev/yevich → eva/ev/evich, o'→u, takror harflar → bitta, «qizi/o'g'li/
  kizi/ugli» va undan oldingi so'z (otasining ismi) tashlanadi.
- Solishtirish: so'zlar tartibi muhim emas (eng yaxshi juftlash); har juft — o'zimiz yozgan Levenshtein (o↔u yarim
  narx; «Jasur = Jasurbek», «Malika = Malikaxon» — qisqa shakl). Begona ismlar ham umumiy harflar (-ov, -eva) tufayli
  ~30% «o'xshaydi» — shu daraja hisobga olinmaydi. Umumiy ball — juftlar geometrik o'rtachasi: faqat ism yoki faqat
  familiya mos (aka-uka, adash) — 50% dan past; bitta so'zli ism ×0.6; ortiqcha so'z −5%. Solishtirishda bitta harfli
  so'zlar (bosh harf «X.», sinf «5-A») va to'lov izohi so'zlari («uchun», «to'lov», «sinf», oy nomlari…) hisobga olinmaydi
  — «Xadicha uchun», «Turg'unboyeva X.» endi yalang ism bilan bir xil ball oladi. Kirill «сҳ» = `s'h` (Исҳоқов = Isxoqov).
- Bonus: joriy qarz = to'lov summasi → +10%, oylik to'lov = summa → +5% (eng kattasi, qo'shilmaydi); ism bo'yicha
  50% dan past nomzodni bonus 60% ga yetkaza olmaydi (≤ 59%). Qarz — «Qarzdorlar» qoidasi (≤ joriy oy, bekor/
  qaytarilgan hisobga olinmaydi); oylik — so'nggi amaldagi faktura summasi.
- Faqat o'qishni tark etmaganlar (chiqdi + to'xtatish sanasi o'tgan — tashqari; muzlatilgan/sinov — kiradi).
  O'quvchilar ro'yxati xotiradan (baza qayta o'qilmaydi); qarz uchun faqat nomzodlar fakturalari `in` so'rovi bilan
  (kalit — butun ilovadagidek `studentId||_id`) o'qiladi. Nomzodlar bonusdan OLDIN «birinchi N ta» bilan kesilmaydi:
  summa bonusi (+10%) bilan top-3 ga kira oladigan hammasi qoladi (`shortlist`, ko'pi bilan 40). Takliflar
  aniqlanguncha (odatda bir zumda, ko'pi bilan ~2.5 s) ro'yxat chizilmaydi — keyin tepasiga blok qo'shilib, kassir
  boshqa qatorni bosib qo'ymasin; qarz so'rovi sekin/xato bo'lsa — ism bo'yicha takliflar «qarz: —» bilan chiqadi.
  Modul yuklanmasa — oyna avvalgidek, keyingi ochishda yangi manzil bilan qayta uriniladi (`?v=2&r=N`).
  `deploy.sh` `/sb` ga `name-match.js` ni ham joylaydi.
- Topshiriqdagi holatlar (`payments/name-match.test.cjs` konsolga chiqaradi): «Turg'unboyeva Hadicha» → 100%,
  «Турғунбоева Хадича» → 100%, «Xadicha Turgunboeva» → 91% (yuqori moslik); «Aliyev Jasur» → 0% (taklif qilinmaydi,
  qarz = summa bo'lsa ham). Testlar: `name-match.test` 84; Chromium 47/47 (haqiqiy `admin.html` + deploy SHIM bilan
  `/sb/name-match.js`: takliflar, tasdiqlash matni, avtomatik biriktirish yo'qligi, bo'lib rejimi, so'rovlar soni, faktura
  xatosi, sekin tarmoq, yopilgan oyna, XSS, telefon ekrani, ID to'qnashuvi, 9 ta adash, bosh harf/izoh so'zlari,
  modulni qayta yuklash).

## 29) Raqib ko'rigi (R8) — §27–28 ustidan

- 16 topilmadan 15 tasi tasdiqlandi, hammasi tuzatildi (biri — aka-uka qofiyali ismlari — rad etildi: talab qilingan
  Levenshtein bilan imlo variantidan farqlab bo'lmaydi; to'g'ri o'quvchi ro'yxatda bo'lsa doim birinchi chiqadi).
- **Yuqori:** qabulxona «⏹️ Chiqarish» haqiqiy yozish yo'lida ISHLAMASDI — shim `setDoc`i UPSERT, triggerning
  yangi-qator tozalashi EXCLUDED'ni bo'shatardi: faol/sinov/muzlatilgan — «42501», bo'sh holatli o'quvchida esa jim
  «Holat saqlandi ✓», lekin o'quvchi faol qolardi. Endi: UI `updateDoc` + qayta o'qib tekshiradi; trigger faqat haqiqiy
  yangi qatorni tozalaydi. **Yuqori:** NULL bilan chetlab o'tish (qabulxona `payStatus=null` qilib muzlatilganni
  faollashtira olardi) — tekshiruv NULL-xavfsiz. **O'rta:** muzlatilgan o'quvchining sanasini kechroqqa surish (eski
  oylar qayta to'lanadigan bo'lardi) va sinovdan chiqarishda `activeFrom` o'zgarmasa sinov kunlari to'lanadigan bo'lishi
  — yopildi. **Past:** yaroqsiz sanalar, UI/baza sana mintaqasi, takliflar: bosh harf/izoh so'zlari, «birinchi 8 ta»
  kesish, ID to'qnashuvida begona qarz, sekin tarmoqda takliflar yo'qolishi, modul xatosidan keyin qayta urinmaslik,
  qo'shimcha apostrof turlari, «сҳ».

## 30) «Eng landavur odam ham xato qilmasin» — ikki qo'shimcha himoya

- **Qabulxona «⏹️ Chiqarish» — ikkinchi tasdiq.** «Saqlash» bosilgach (sana tekshiruvidan keyin) yana so'raladi:
  «Turg'unboyeva Xadicha» (5-sinf «A» · O‘zbek, ID IQ-0101) chiqarilsinmi? — chiqqan sana va «⚠️ Qaytarish (qayta
  faollashtirish) — faqat direktor orqali». «Bekor» — hech narsa yozilmaydi, oyna ochiq qoladi. Direktor oynasida
  qo'shimcha tasdiq yo'q (u o'zi qaytara oladi).
- **«Biriktirish» — past moslikda ogohlantirish.** Tanlangan o'quvchining moslik foizi 75% dan past bo'lsa (taklifdan —
  ko'rsatilgan foiz; ro'yxatdan — ism o'xshashligi, taklifda bo'lsa o'sha foiz), tasdiqlash oynasi boshida:
  «⚠️ Ism to‘liq mos emas (67% mos) — to‘lovchi yozgan ism: «Xadicha»», keyin avvalgi «Ism (ID) — summa / Shu
  o‘quvchiga biriktirilsinmi?». To'lovchi ism yozmagan bo'lsa (masalan faqat telefon raqami) — ogohlantirish yo'q.
  Bo'lib biriktirishda (aka-uka) — yo'q: u yerda ismlar ataylab farq qiladi.
- Testlar: Chromium 35/35 (chiqarish oynasi) va 54/54 («Biriktirish»); haqiqiy stek (PG16 + PostgREST + shim) 31/31 —
  2-tasdiq matni, «Bekor» bosilsa bazada o'zgarish yo'qligi.

## 31) Raqib ko'rigi (R9) — R8 tuzatmalari ustidan

- Ikkinchi tekshiruv (asl repro skriptlar + variantlar + regressiya qidiruvi): R8 tuzatmalari asosan to'g'ri; 21 topilmadan
  14 tasi tasdiqlandi va tuzatildi (7 tasi rad etildi).
- **Yuqori (tuzatmaning o'zi kiritgan):** triggerning «qator bormi?» tekshiruvi qulfsiz edi — parallel ravishda shu `id`
  o'zgartirilsa/o'chirilsa, qabulxona qo'shgan yangi qator TOZALANMAGAN (masalan «sinov», kelajak `activeFrom`) qolardi.
  Endi tekshiruv qatorni qulflaydi (`FOR UPDATE` — parallel tranzaksiya tugashini kutadi); qabulxona/O'IBDO' qator kaliti
  `id` ni umuman o'zgartira olmaydi (ilovada bunday amal yo'q). Ikki sessiyali poyga testi: eski triggerda yiqiladi, yangisida o'tadi.
- **O'rta:** sanasiz muzlatilgan o'quvchini chiqarishda bugungi sana qo'yilardi → muzlatilgan oylar to'lanadigan bo'lib
  qolardi. Endi: sana o'zgarmaydi («chiqdi», sanasiz — to'lov hisoblanmaydi), oynada sana maydoni yashirin, izoh va
  tasdiqda «sanasiz»; bazada ham sanasiz muzlatilganga yangi sana qo'yish — rad. **O'rta:** «sana o'zgarmagan» istisnosi
  faol o'quvchidagi qolib ketgan eski sana bilan chiqishni orqaga surishga imkon berardi — endi bu istisno faqat muzlatilgan/sinov uchun.
- **Takliflar (past):** bosh harflar endi TEKSHIRILADI («Karimov J.» → faqat Jasur ~72%; zid bosh harf — rad; «Sh.»,
  «Ш.», «Ю.», «Ya.», «Ё.» ham); o'quvchi yozuvi tozalanmaydi (koreyscha «O», «Avgust» ismi saqlanadi), izoh so'zlari faqat
  to'lovchi matnidan va faqat ismda yo'q bo'lsa tashlanadi; raqamga yopishgan bo'laklar (`IQ-0042`, `5-A`, `11B`, hex kod,
  `2026-yil`, «so'm») olib tashlanadi; izoh so'zlari kirill yozuvi bilan ham («оплата за обучение», «сўм», «қизим»…);
  apostroflar Unicode toifasi bo'yicha (ˊ ˋ ‵ “ ” " ham), ko'rinmas belgilar o'chiriladi; qarz so'rovlari parallel.
- Testlar: `name-match.test` 103; PG16 51/51 + poyga 2/2; haqiqiy stek e2e 36/36; Chromium 37/37 + 56/56.

## 32) Raqib ko'rigi (R10) — R9 tuzatmalari ustidan

- Uchinchi tekshiruv: baza himoyasi (trigger, RLS, poygalar, 816 o'tish × 5 oy to'lov tekshiruvi) — topilma yo'q. Takliflarda
  9 topilma tasdiqlandi, hammasi tuzatildi.
- **Yuqori:** raqamdan (ID, telefon, summa) keyin yozilgan apostrofli ism kesilardi: «IQ-0042 Ra'no Karimova» → «no» qolib,
  bosh harf deb o'qilardi — yagona taklif opa-singil «Karimova Nodira 82%» (ogohlantirishsiz) edi. Endi apostrof — so'z
  harfi; Ra'no / Jo'ra / G'ayrat / O'tkir / Turg'unboyeva 100%. **O'rta:** raqamdan keyin bo'shliq bilan yozilgan qisqa ism
  (Ali, Lola, Umid) ham o'chirilardi — endi faqat raqamga YOPISHGAN bo'lak («5-A», «11B», «2026-yil») va raqamdan keyingi
  yakka harf («5 A») olib tashlanadi.
- **O'rta:** bosh harf «O'.» / «Ў.» o'quvchi ismidagi «O'tkir» (= utkir) bilan mos kelmasdi (3%), «E.» / «Е.» — Yelena /
  Евгений bilan ham; aka-uka bo'lsa noto'g'ri bola (Otabek / Ойбек) 82% taklif qilinardi. Endi o' = u, «O.» — O va O',
  «E.» — e va ye bilan mos. **O'rta:** nuqtasiz yakka harf (sinf harfi «6-sinf B», «5 класс А», ruscha «и», «X adicha»
  xatosi) zid bosh harf deb hisoblanib, 3 so'zli yozuvni (otasining ismi bilan) 10% ga tushirardi. Endi bosh harf —
  faqat NUQTA bilan («X.», «J.», «Sh.»); boshqa yakka harf ismdagi so'zga aynan teng bo'lsagina hisobga olinadi (koreyscha
  «O Viktoriya» ↔ «O Viktoriya Sergeyevna» 95%; boshqa familiyali «Kim Viktoriya» — faqat ism mos darajasida, 57%).
- **Past:** faqat izoh matni («Avgust oyi uchun to'lov», «Оплата за август») «Karimov Avgust»ni taklif qilardi — endi 2+ izoh
  so'zi bo'lsa matn izoh hisoblanadi (oy nomi ism emas); «Karimov Jasur avgust uchun» → Jasur 100%, ukasi Avgust 3%.
  Kirill «сын» izoh so'zlaridan olib tashlandi (koreyscha familiya Син / Sin: «Син Виктория» → Shin 72%, Kim 10%).
  Qo'shtirnoq / ko'rinmas belgi so'zlar ORASIDA (bo'shliqsiz, «Turg'unboyeva«Xadicha»») so'zlarni yopishtirib qo'ymaydi.
- **Past (oyna):** taklifdan tanlanganda ⚠️ endi DOIM ko'rsatilgan foiz bo'yicha (67% «Avgust» taklifi ogohlantirishsiz
  edi); ro'yxatdan tanlanganda «ism yozganmi?» — o'sha o'quvchi ismi bilan solishtirish qoidasi bo'yicha. To'lovchi matni
  ⚠️ qatorida bitta qatorga keltiriladi (qator ko'chishi / boshqaruv / yo'nalish belgilari — bo'shliq: soxta «o'quvchi —
  summa» qatori yasab bo'lmaydi), 80 belgi — emoji bo'linmaydi. Modul manzili `?v=3` (brauzer eski nusxani ishlatmasin).
- Testlar: `name-match.test` 128 (25 tasi yangi; R9 kodida 23 tasi yiqiladi); Chromium «Biriktirish» 68/68 (12 tasi yangi;
  R9 kodida 10 tasi yiqiladi) + chiqarish 37/37; PG16 51/51 + poyga 2/2; to'liq zanjir + RLS 12/12; haqiqiy stek e2e 36/36.
  Topshiriqdagi 4 holat o'zgarmadi: 100% / 100% / 91% / 0% (taklif qilinmaydi).

## 33) Raqib ko'rigi (R11) — R10 tuzatmalari ustidan

- To'rtinchi tekshiruv: R10 ning 9 tuzatmasidan 7 tasi to'liq yopilgan, 2 tasining yaqin varianti qolgan edi; uch yo'nalishdagi
  yangi qidiruv (algoritm regressiyalari, qoidalar izchilligi, tasdiqlash oynasi) 14 topilmani tasdiqladi. Hammasi tuzatildi.
- **Yuqori:** yopishgan bosh harflar («Karimov J.O.», «Иванова М.А.») — ikkinchisi tushib qolardi va boshqa otaning farzandi
  (amakivachcha, qarzi summaga teng) 78% bilan ogohlantirishsiz BIRINCHI taklif qilinardi. Endi bosh harflar so'z tartibi bilan
  aniqlanadi va rolga ega: boshqa bosh harfdan keyingisi («J.R.») yoki ikki to'liq so'zdan keyingisi («Karimov Jasur R.») —
  otasining ismi bosh harfi: 3 so'zli yozuvda faqat otasining ismi bilan solishtiriladi (Javohir Olimovich 68%, amakivachcha
  Jasur Bahodirovich 8%; «Karimov Jasur R.» — Rustamovich 95%, Bahodirovich 10%), 2 so'zli yozuvda hisobga olinmaydi.
  Ism bosh harfi esa otasining ismiga juftlanmaydi: R9/R10 da «Usmonov A.» → «Usmonov Nur Anvarovich» 78% (A — Anvarovich
  orqali), «Karimov Z.» → aka-ukasi «… Zafarovich» chiqardi — endi chiqmaydi.
- **O'rta:** «Y.» Ye-ismlarga (Yelena, Yegor, Yevgeniy) zid edi — endi mos; «Yo.» / «Ё.» — Yo'ldosh bilan ham. Nuqtali sinf
  harfi («5-sinf A.», «5 класс А.», «5 кл. А») bosh harf deb o'qilib, ukasini 78% ogohlantirishsiz taklif qilardi — endi sinf
  so'zi yonidagi yakka harf olib tashlanadi. «N.» bosh harfi raqamdan oldin ham bosh harf («No 5», «Nr. 12» — raqam belgisi).
- **O'rta:** otasining ismi bilan yozilgan (3 so'zli) o'quvchida to'lovchining ortiqcha so'zi («tel.», «12 okt», «5 кл.»,
  «тыс.», «10 kun», «питание», «Toshkent») otasining ismiga majburan juftlanib, to'g'ri o'quvchini 10% ga tushirardi
  (taklif yo'q, ro'yxatdan tanlansa soxta ⚠️). Endi to'lovchi otasining ismini yozmagan (yoki faqat mos bosh harfini yozgan)
  bo'lsa, yozuv otasining ismisiz ham solishtiriladi (×0.95); aka-uka (boshqa ism) baribir rad etiladi. Izoh so'zlari
  kengaytirildi (tel, okt, kun, chi, chorak, so'mlik, кл, тыс, питание, ребенка, на/по/до…, shahar va tuman nomlari, manzil
  so'zlari, «F.I.O.» yorlig'i); «сына» / «сынок» qaytarildi (R10 da «сын» bilan birga tasodifan olib tashlangan edi). Manzil
  qisqartmasi («Toshkent sh.», «Chilonzor t.», «Karimov Jasur t. Chilonzor», «г. Ташкент») — bosh harf emas
  («Karimov Sh. Toshkent» — bosh harf).
- **Past:** koreyscha qisqa familiya + otasining ismi («Ли Виктория Сергеевна») boshqa oiladagi «Kim Viktoriya Sergeyevna» ni
  95–100% ko'rsatardi — endi hisobga olinmagan 2 harfli so'z (yoki «O») bo'lsa va ismda juftsiz yoki faqat bosh harf bilan
  juftlangan so'z qolsa, ball ≤ 64% (bonus bilan ham ⚠️). Ruscha «на/до/по» — koreyscha «Na», «Do» bilan adashmaydi.
  ⚠️ endi «Ли», «Ж К» kabi qisqa ism yozilganda ham chiqadi (`wroteName`). Apostrof turlari (′ ＇ ‛ ‚ ՚ ‵ ^ ¨) hamma
  qoidalarda bir xil; « » doim so'zlarni ajratadi; ID / telefonga yopishgan ism («IQ-0042-Ali», «998901112233Ali») kesilmaydi.
- **Past (oyna):** R10 dagi «soxta qator yasab bo'lmaydi» to'liq to'g'ri emas edi (Braille bo'sh belgisi U+2800 bilan
  mumkin edi). Endi ⚠️ qatorida to'lovchi matnidan faqat SO'ZLAR ko'rsatiladi: raqam, qavs, tire, emoji, ko'rinmas va «bo'sh»
  harflar (Braille bo'sh belgisi, Hangul to'ldiruvchilari) tashlanadi, diakritika uyumi 2 tagacha; 80 belgi — grafema
  bo'yicha. Modul manzili `?v=4`.
- Tekshiruv: `name-match.test` 159 (R10 kodida yangi testlarning 14 tasi yiqiladi, keyin `wroteName` yo'qligi sabab to'xtaydi);
  Chromium «Biriktirish» 77/77 (R10 kodida 11 tasi yiqiladi) + chiqarish 37/37. Differensial skaner (R8/R9/R10/R11 yonma-yon,
  admin.html dagi kabi taklif zanjiri): tasodifiy 60 000 to'lovchi matnida (ikki xil urug') to'g'ri o'quvchi bali R10 ga
  nisbatan 6 054 / 6 059 holatda > 5 ball oshdi, 0 holatda tushdi; maktab darajasida (354 o'quvchi × 92 shablon × 3 qarz holati,
  har biriga 4 aka-uka, 2 adash va 300 boshqa o'quvchi; 2 va 3 so'zli yozuv) to'g'ri o'quvchi birorta holatda yo'qolmadi, R10
  topa olmagan 18 426 holatda endi topiladi, 40 ta keng tarqalgan shablonda bayroq yo'q. Qolgan bayroqlar — faqat bosh harfli
  matnlarda bir xil bosh harfli aka-ukalar tengligi (quyida). Topshiriqdagi 4 holat o'zgarmadi: 100% / 100% / 91% / 0%.
- Ongli qoldirilganlar (hammasi ⚠️ bilan yoki teng ko'rsatiladi, ishonchli noto'g'ri taklif yo'q): bir xil bosh harfli aka-uka
  teng chiqadi («Petrova Y.» → Yelena va Yana 82%; «Qodirov B.B.» → Bekzod va Bahodir Bahodirovich); qisqa ismdagi bir harf
  farqi (Ali / Vali 72%); oy nomi + yil («Avgust 2026» → Karimov Avgust 67% ⚠️); koreyscha «O» familiyasi raqamdan keyin
  («IQ-0042 O Viktoriya»); noma'lum joy nomi + qisqartma («Em Nikita Gazalkent sh.» — to'g'ri o'quvchi ham topilmaydi);
  kichik harfli so'zlar ko'rinmas belgi bilan yopishgani.

## 34) Tahrirda ID o'zgarmasin — o'quvchi / o'qituvchi / xodim (audit va tuzatmalar)

- Savol: «o'quvchi, o'qituvchi yoki xodim tahrir qilinsa ID o'zgarib ketmayaptimi?» To'rt yo'nalishda (o'quvchi, o'qituvchi, xodim,
  shim/baza/server) haqiqiy stekda (PG16 + PostgREST 12 + to'liq admin.html + shim, rollar JWT bilan) tekshirildi, har topilma
  mustaqil tekshiruvchi tomonidan qayta takrorlandi: 39 topilmadan 37 tasi tasdiqlandi (TCH-8 — ataylab, INF-7 — yo'l yo'q).
- **Javob:** oddiy tahrirda yozuvning ichki kaliti (`_id`) hech qachon o'zgarmasdi. Lekin biznes ID / bog'lovchi kalitlar quyidagi
  holatlarda JIM o'zgarardi yoki dublikat paydo bo'lardi — hammasi tuzatildi:
  - eski ID chetida bo'sh joy (`'IQ-0005 '`, `' IQT-005'`, `'IQX-004 '`) har «Saqlash»da kesilardi → hisob-faktura, avans, davomat,
    ota-ona ulanishi, maosh/avans/qoldiq «yetim» bo'lib, keyingi generatsiya ikkinchi faktura yaratardi;
  - eskirgan ro'yxat/oynadan saqlash boshqa admin bergan ID / Kamera ID / sinf / muzlatishni qaytarib yuborardi;
  - setDoc (upsert) o'chirilgan yozuvni qayta tiklardi (yangi ota-ona kodi bilan) yoki nomsiz «arvoh» yozuv yaratardi (Holat,
    foydalanuvchini qayta bog'lash, Kamera ID importi, Excel import);
  - davomatdagi «➕ Xodim qilib bog'lash» MAVJUD xodimni bog'lash o'rniga ikkinchi nusxasini yaratardi (davomat yangisiga,
    maosh/avans eskisiga — ushlanmasiz to'liq maosh);
  - o'chirilgan o'qituvchi/xodimning ID'si yangi odamga berilardi (uning qoldig'i/avansini meros olardi);
  - Kamera ID noyobligi tekshirilmasdi; Kamera ID o'zgarsa eski skanlar jim uzilardi; HIK importi «o'zgaradi»ni avtomatik belgilardi;
  - qabulxona tahriri (o'qituvchilar ro'yxatini ko'rmaydi) «Xodim farzandi» bog'lanishini (student_private.teacherId) o'chirardi;
  - olimpiada granti takroriy ID'da boshqa bolaga yozilardi; ro'yxat yuklanmagan holda Excel import mavjudlarni YANGI deb yaratardi;
  - ID o'zgartirish tasdig'ida «(bo'sh)» deyilardi, pul esa ichki kalit ostida turardi.
- **Tuzatma (admin.html):** tahrir formasi endi faqat O'ZGARGAN maydonlarni yozadi (oyna ochilgandagi qiymatga nisbatan), saqlashdan
  oldin yozuvni bazadan qayta o'qiydi (o'chirilgan → saqlanmaydi; ID/Kamera ID/holat/sinf boshqa joyda o'zgargan → «qayta oching»)
  va sof UPDATE qiladi (`updateDoc(..., {mustExist:true})`). O'quvchi `studentId`si tahrirda hech qachon yozilmaydi (faqat bo'sh
  bo'lsa hujjat kaliti bilan to'ldiriladi); o'qituvchi/xodim ID'si o'zgarmasa (bo'sh joy farqi ham) — yozilmaydi. ID ataylab
  o'zgartirilsa — `rekey_payroll_id` maosh berish / avans / «xodim farzandi» bog'lanishi va foydalanuvchi yorlig'ini BITTA
  tranzaksiyada yangi ID'ga ko'chiradi (eski ID boshqa xodimda ham bo'lsa — ko'chirmaydi va shuni aytadi); tasdiq oynasi haqiqiy
  kalitni va yozuvlar sonini ko'rsatadi. ID o'chirib yuborilsa — asl ID qaytariladi. Takroriy ID o'qituvchi + xodim ro'yxatlari
  bo'yicha tekshiriladi; yangi ID o'chirilgan xodimlar tarixidan ham katta (`payroll_id_high_water`), egasiz tarixli ID rad etiladi.
  Kamera ID: boshqa odamda bo'lsa saqlanmaydi; o'zgarsa va eski skanlar bo'lsa ogohlantiriladi. Holat oynasi joriy holatni bazadan
  o'qiydi va oyna ochilgandan beri o'zgargan bo'lsa yozmaydi. Davomatdagi tugma endi «🔗 Xodimga bog'lash»: Kamera ID'si yo'q
  mavjud xodim/o'qituvchilar (ism mosi yuqorida) ro'yxati, yangi xodim — faqat ikkinchi tugma bilan va bir xil ismda tasdiq bilan.
  HIK importi: ro'yxat o'qilmasa to'xtaydi, band ID — «band», «o'zgaradi» belgilanmaydi, yozishdan oldin ro'yxat qayta o'qiladi.
  Tanlov (select/dynselect) bazadagi qiymat variantlarda bo'lmasa uni «joriy qiymat» sifatida saqlaydi. Olimpiada granti — faqat
  aniq bitta o'quvchiga. Import — ro'yxat bazadan, ID'lar bo'sh joysiz solishtiriladi, mavjud o'quvchiga sof UPDATE.
  O'qituvchi/xodimni o'chirishda maosh tarixi bo'lsa ogohlantiriladi.
- **Baza (migration/id-guards.sql):** ilova foydalanuvchisi (direktor ham) `students.id` va mavjud `studentId`ni o'zgartira olmaydi
  (bo'sh studentId'ni to'ldirish mumkin; SQL/service_role — tegilmaydi); teachers/staff qator kaliti ham. `payroll_id_high_water`,
  `payroll_key_info`, `rekey_payroll_id` (faqat direktor/HR). **Shim:** payload'dagi `id` qator kalitini bosib o'tmaydi;
  bo'sh/aniqlanmagan kalit bilan yozish — xato; `updateDoc` `mustExist` bilan 0 qatorda `not-found` beradi.
  `rekey-students.sql` chetida bo'sh joyli ID'ni o'tkazib yuboradi; `import.cjs` to'la bazaga `FORCE_IMPORT=1`siz yozmaydi.
- **Tekshiruv:** audit stsenariylari tuzatilgan kodda qayta ishga tushirildi — o'quvchi (forma 60 saqlash, eskirgan sahifa,
  kesish, import, Holat, o'chirish poygasi, API), o'qituvchi (28 holat + 2), xodim (8 skript + yangi 13 tekshiruv), infra
  (shim/baza/server/qayta deploy): ID'lar o'zgarmaydi, arvoh/dublikat yaratilmaydi, tarix ko'chadi. Shim selftest 29/29
  (sahifalash uchun soxta mijoz tuzatildi), Chromium «Biriktirish» 77/77, chiqarish 37/37, to'lov/SMS/auth/server testlari yashil.
- **Ma'lumot tekshiruvi (prod, faqat o'qish):** bo'sh joyli kalitlar bormi —
  `select id,"studentId" from students where "studentId"<>btrim("studentId");`
  `select id,"teacherId" from teachers where "teacherId"<>btrim("teacherId");`
  `select id,"staffId" from staff where "staffId"<>btrim("staffId");` — bo'lsa, ular endi tahrirda o'zgarmaydi (bog'liq yozuvlar
  bilan mos qoladi); tozalash kerak bo'lsa — bog'liq jadvallar bilan birga, alohida skript bilan.

## 35) Raqib ko'rigi (R12) — R11 tuzatmalari ustidan (ism solishtirish)

- Beshinchi tekshiruv (algoritm regressiyalari, qoidalar izchilligi, tasdiqlash oynasi; R8–R11 bilan yonma-yon, haqiqiy Chromium):
  16 topilma tasdiqlandi — hammasi tuzatildi.
- **Ism bo'la oladigan izoh so'zlari** («мая» = Майя, «марта» = Марта, «августа»; koreyscha «На / До / Со»): R11 ularni izoh
  so'zi qilgani uchun «Petrova Mayya uchun», «Оплата за обучение Петрова Майя» 57% ga tushib, opa-singil bilan teng chiqardi
  (ruscha otasining ismli yozuvda qarzi summaga teng opa-singil 100% ⚠️ siz birinchi). Endi ular izoh sanog'iga kirmaydi; ismda
  bo'lsa va ism o'rni bo'sh bo'lsa (to'lovchining boshqa ism so'zlari yozuvdagidan kam) — ism (izoh matnida — boshqa so'z ham shu
  ismga mos kelsa); ismda yo'q, lekin ism o'rnida — boshqa bola: ball ≤ 45% (bonus bilan ham taklif yo'q), «На Виктория …» ↔
  boshqa oila ≤ 64% (⚠️). «до 1 мая», «Оплата на …», «… на октябрь», «за сына» — izoh. Shu qoida «Avgust» / «May»ga ham:
  «Karimov Jasur avgust» endi ukasi Karimov Avgust'ni 95% ko'rsatmaydi.
- **Otasining ismisiz solishtirish (R')** adash / amakivachchani ko'tarardi: «Karimov Jasur Bahodir», «(dadasi Bahodir)», «otasi
  Bahodir, …», «Bahodirov», «Bah.», «Bahodirovic», «Rustamovch», «Rustamova», «Li Viktoriya S.», «Umid R. Xolmatov» — boshqa
  otaning farzandi 90–100% (qarz = summa bilan birinchi, ⚠️ siz). Endi R' DALIL bilan: to'lovchining juftlanmagan so'zi,
  tashlangan bosh harfi va «otasi …» / «… o'g'li» dagi ism yozuvdagi otasining ismi bilan solishtiriladi: mos (o'zagi,
  qisqartma, xato yozuv) — R' to'liq; zid (boshqa bosh harf, otasining ismi shaklidagi so'z, boshqa ota ismi, to'liq ism ICHIDAGI
  so'z — «Karimov Jasur Rustam» ↔ Karimov Rustam …) — R' yo'q (amakivachcha ~10–40%); noma'lum so'z («Guliston») — R' ≤ 64% (⚠️).
  Boshqa bo'lakdagi aka-uka («Karimova Malika va Karimov Ali», «…, Karimov Ali») — dalil emas (95% saqlanadi).
- **Sinf so'zi yonidagi yopishgan bosh harflar** («5 класс Ж.Р. Каримов», «5-A sinf J.R. Karimov», «5-sinf A.S. Usmonov»):
  birinchisi sinf harfi deb kesilib, aka 82% ⚠️ siz chiqardi — endi sinf harfi faqat yakka harf bo'lsa va sinfda harf hali
  yozilmagan bo'lsa olinadi; «5-sinf O Viktoriya» — koreyscha «O» saqlanadi.
- **«Familiya I.» oldidagi ortiqcha so'z** (Guliston, Сын, Iqro akademiyasi…) bosh harfni otasining ismi deb o'qitardi (to'g'ri
  o'quvchi 3%). Endi bosh harf roli yozuvga qarab: oldingi so'z yozuvdagi FAMILIYAGA mos, undan oldingisi hech biriga mos emas —
  ism bosh harfi («Usmonov Bekzod A.» ↔ Aliyev Bekzod — yo'q); vergul / «;» / «/» — bo'lak chegarasi; «Li Viktoriya S.» — 2 harfli
  familiya ham ism so'zi. To'lov / karta / qarindosh so'zlari (Платеж, Перевод, Payment, Humo, Uzcard, мама, папа, buvisi, talaba,
  student…), manzil / yorliq bo'laklari (kv, uy, ga, da, bn, IT, MED, л/с, д/с, ИНН, S/N, No:, Nº) — izoh; «Ни» (koreyscha
  familiya) — izoh emas; «Popov N. 5 класс» — «N.» bosh harf.
- **Kichiklar:** qo'sh ism (otasining ismisiz 3 so'zli «Karimov Muhammad Ali») + «Karimov M.R.» — 8% → 64% (⚠️); manzil
  qisqartmasi bosh harfdan keyin («Каримов Ж. г. Ташкент», «Karimov J. t. Chilonzor») — 8% → 68% (teskari tartib bilan bir xil);
  oxirgi nuqtasiz yopishgan bosh harflar («Иванова М.А», «J.R Karimov», «Тошматов Э.О») — tekshiriladi (zid otasining ismi < 30%).
- **⚠️ oynasi:** «o'quvchi (ID) — summa» qatori endi BIRINCHI, ⚠️ undan keyin — to'lovchi matni (Hangul jamo, ﾞ, teri rangi
  belgilari bilan minglab belgi) uni ko'rinishdan siqib chiqara olmaydi; to'lovchi matnidan faqat lotin (asosiy, Latin-1,
  Extended-A) va o'zbek/rus kirill harflari, o'zbekcha apostroflar va bosh harf nuqtasi ko'rsatiladi, ko'pi bilan 80 harf —
  o'xshash harflar (ʗ, ↄ, ˗, ー, Ƽ, 𝐗) bilan soxta «(IQ-…) — summa» qatori yasab bo'lmaydi. Faqat izoh / yorliq / ruscha «и»
  («Оплата за сентябрь и октябрь», «IT kursi uchun», «5-«A»», «л/с 0042», «Оплата до 1 мая») — ⚠️ yo'q; «Майя», «Ж К», «О»,
  «Ли» — ⚠️ bor. Modul manzili `?v=5`.
- Tekshiruv: `name-match.test` 173 (14 yangi); R12 ko'rigining 114 holati (probe) 114/114 (R11 kodida 22/114); Chromium
  «Biriktirish» 110/110 (33 yangi holat; R11 kodida 34 tasi yiqiladi), chiqarish 37/37. Differensial skanerda tasodifiy son
  generatorining xatosi topildi (siklga tushib, 60 000 «namuna» aslida ~1 500 xil matn edi) — tuzatildi; endi 60 000 haqiqiy
  tasodifiy matnda (ikki urug') to'g'ri o'quvchi bali R11 ga nisbatan 29 / 32 holatda > 5 ball oshdi (koreyscha «O» raqamdan
  keyin), 0 holatda tushdi; maktab darajasida (354 o'quvchi × 92 shablon × 3 qarz holati, 4 yozuv formati) to'g'ri o'quvchi
  birorta holatda yo'qolmadi va boshqa bola undan oldinga o'tmadi, R11 ko'rsatmagan noto'g'ri taklif faqat «Familiya Ism P.»
  shablonida qoldi (koreyscha «O» familiyasi, ≤ 74% — ⚠️ bilan).
- Ongli qoldirilganlar: koreyscha «O» familiyasi + boshqa familiyali adash («O Ivan A.» → «Ten Ivan Andreyevich» 64%, bonus bilan
  74% — ⚠️; R11 da boshqa adash 75% ⚠️ siz edi); «… Bahodir o'g'li» yozuvi o'zbekcha bo'lsa otasining ismi yozuvda saqlanmaydi
  (normalizeName) — adash teng; ruscha kelishik shakllari («Петровой Анны» — 44%); bir xil bosh harfli aka-uka tengligi.

## 36) ID tuzatmalari ustidan raqib ko'rigi (§34 ustidan) — topilmalar va tuzatmalar

- Beshta yo'nalish (forma, SQL, oqimlar, shim, auditni qayta tekshirish) haqiqiy stekda (PG16 + PostgREST 12 + to'liq admin.html
  Chromium'da, rollar JWT bilan). Xulosa: asos mustahkam (jim ID o'zgarishi yoki arvoh yozuv topilmadi), lekin 30 dan ortiq yaqin
  bo'shliq topildi — hammasi tuzatildi:
- **Kamera ID va qabulxona (o'rta):** qabulxona o'qituvchi/xodim jadvallarini va skanlarni ko'rmaydi (RLS) — o'qituvchining Kamera
  ID'si o'quvchiga jim saqlanardi (o'qituvchi skani bolani «keldi» qilardi), eski skanlar haqidagi ogohlantirish ham chiqmasdi.
  Endi `camera_owners` / `camera_has_scans` (id-guards.sql, faqat ism va tur, chetidagi bo'sh joysiz) — forma, HIK importi va
  bog'lash oynasi shular orqali tekshiradi.
- **O'qituvchi maoshi (o'rta):** forma maosh paneli yuklanishidan oldin saqlansa — tillar va sertifikatlar bo'sh yozilib, oylik
  1 500 000 so'mga tushardi. Endi panel yo'q bo'lsa ular yozilmaydi; hisoblangan maosh ziddiyat deb so'ralmaydi va bazadagi
  (boshqa admin o'zgartirgan staj/til bilan) qiymatlardan qayta hisoblanadi.
- **Sinf rahbari (o'rta):** «Sinf rahbari» ro'yxati yuklanmagan holda saqlansa kurator jim olib tashlanardi — endi ro'yxat
  yuklanmaguncha (yoki o'qilmasa) saqlanmaydi.
- **Excel import va yangi o'quvchi (o'rta):** oldindan ko'rish ochiq turganda boshqa admin shu ID bilan o'quvchi qo'shsa, import
  uning ustiga yozardi (ota-ona kodi va maxfiy ma'lumoti yangi bolaga o'tardi). Endi shim'da `createDoc` (sof INSERT, 23505): import
  avtomatik ID'ni qayta beradi, fayldagi aniq ID'ni o'tkazadi; qisman yozilgandan keyin qayta «Saqlash» yozilganlarni qayta
  yaratmaydi; yangi o'quvchi formasi ham faqat INSERT.
- **HIK importi (o'rta):** umumiy belgilash «o'zgaradi» qatorlarini ham belgilab, skan tarixi bor Kamera ID'ni ogohlantirishsiz
  almashtirardi (oylik «yo'qlama» ushlanmasi). Endi «o'zgaradi» faqat qo'lda, tarix bo'lsa aniq tasdiq; oldindan ko'rishdan beri
  odamning Kamera ID'si o'zgargan bo'lsa yozilmaydi.
- **Bir xil ism (o'rta):** yangi xodim/o'qituvchi tekshiruvi so'z tartibini hisobga olmasdi («Sobirov Jamshid» = «Jamshid Sobirov»)
  — endi tartibdan va kichik imlodan mustaqil; bog'lash oynasida «ism mos» faqat haqiqiy moslikda, qidiruv so'zlar bo'yicha;
  skan o'quvchiniki bo'lishi mumkin bo'lsa (Kamera ID'si yo'q, ismi mos) — ogohlantirish.
- **Baza (past):** `payroll_id_high_water` ruxsatni regex'dan OLDIN tekshiradi (oldin istalgan foydalanuvchi kalit borligini bilib
  olishi mumkin edi); yangi ID ostidagi yetim «xodim farzandi» bog'lanishi ham band; ko'chiriladigan bog'lanishlar soni tasdiqda
  aniq; maosh berish va ID o'zgartirish bir kalitda navbat bilan (advisory lock) — o'zgartirish paytida berilgan maosh eski kalitda
  yetim qolmay xato bilan qaytadi; maosh/avans faqat mavjud xodim kaliti bilan; `teacherId`/`staffId` ilovadan faqat
  `rekey_payroll_id` orqali o'zgaradi (API orqali to'g'ridan-to'g'ri o'zgartirish va takroriy yangi ID — rad).
- **Forma (past):** maxfiy maydonlar ro'yxat fonida hali yuklanmagan bo'lsa forma ochilishidan oldin o'qiladi («Qaysi xodim»ni
  bo'shatish endi yoziladi, soxta «boshqa joyda o'zgartirilgan» savoli yo'q); eski sana/vaqt formati («01.09.2025», «9:00»),
  NULL til, «85» ball, «500000» summa, eski til kaliti — o'zgartirilmagan «Saqlash»da yozilmaydi; tahrirda takroriy / o'chirilgan
  xodim ID'si yozilsa asl ID qaytariladi; ID o'zgarib qolgan maydonlar yozilmasa — aniq xabar va qayta «Saqlash» ishlaydi;
  foydalanuvchini qayta bog'lashda yangi yozuv o'chirilgan bo'lsa — avvalgi bog'lanish tiklanadi; o'chirish ogohlantirishi ichki
  kalit va «xodim farzandi»ni ham aytadi.
- **Shim (past):** «undefined»/«null»/bo'shliq kalit rad (getDoc so'rovsiz «yo'q»), writeBatch kalitni navbatga qo'shishda
  tekshiradi, bo'sh payload bilan `mustExist` bor qatorni «topilmadi» demaydi; admin.html shim'ni `?v=2` bilan yuklaydi (keshdagi
  eski shim + yangi sahifa = oq ekran bo'lmasin), deploy.sh `createDoc` borligini tekshiradi; xato xabarida bazaning izohi.
- Tekshiruv: SQL — rekey 28/28, xodim 11/11, yangi tuzatmalar 60/60 (regex oracle, yetim bog'lanish, sanoq, maosh/ID poygasi ikki
  tartibda, kalit triggeri, kamera RPC 7 rol, ID triggeri), zanjir 3 marta qayta qo'llandi (xato yo'q); forma — 101 maydon tahririda
  94 (qolgan 7 — test artefaktlari), o'zgartirilmagan saqlash 27/27 (hech narsa yozilmaydi), kamera / maosh paneli / rahbar /
  maxfiy ma'lumot / parallel tahrir stsenariylari; oqimlar — bog'lash 21/21, HIK 23/24 (qolgani ataylab o'zgargan xatti-harakat),
  ID o'zgarishi 13/13, o'chirish/olimpiada/import 20/20, poygalar 3/3, qisman xato 2/2; shim selftest PASS; Chromium «Biriktirish»
  110/110, chiqarish 37/37; to'lov/SMS/auth/server testlari yashil.

## 37) Yakuniy raqib ko'rigi (R13) — R12 ism solishtirish va §36 ID tuzatmalari ustidan

- To'rt yo'nalish (ism solishtirish algoritmi, SQL, formalar, shim) haqiqiy stekda, har topilma alohida tekshiruvchi bilan qayta
  tasdiqlandi: 15 topilma (ikkitasi bitta xato) — hammasi tuzatildi.
- **Ism solishtirish — R12 qoidalarining yon ta'siri:**
  - **Yil qisqartmasi / bo'shliqli nuqtali sinf harfi bosh harf bo'lib qolardi (yuqori):** «oktyabr 2026 y. J. Karimov uchun»,
    «2026 г. Ж. Каримов», «5-sinf A. J. Karimov», «5 класс А. Ж. Каримов» — «y.» / «г.» / sinf harfi ism bosh harfi deb olinib,
    to'g'ri bola 3% ga tushar, ismi shu harf bilan boshlanadigan aka-ukasi 82% ⚠️ siz yagona taklif edi. Endi faqat YOPISHGAN bosh
    harflar («5-sinf A.S. Usmonov», «5 класс Ж.Р.») saqlanadi; yil qisqartmasi («2026 y.», «2026 г.», «2026 й.») doim olib tashlanadi.
  - **«5-A J. Karimov» — bosh harf o'chardi (o'rta):** sinf harfi kesilgandan keyin «J.» raqamdan keyingi harfga o'xshab qolardi
    (to'g'ri bola 57%, aka-ukasi bilan teng). Endi raqamdan keyingi yakka harf sinf harfi kesilishidan OLDIN qidiriladi; tire /
    nuqtadan keyingi NUQTALI harf («5- J.», «IQ-0042. J.», «1. J. Karimov 2. B. Karimov», «2026-y. J.») — bosh harf. «5A J.
    Karimov» (R11 dan beri 57%) ham endi 72%.
  - **Onasining / to'lovchining familiyasi otasining ismi deb o'qilardi (o'rta):** «Karimov Jasur - Rahimova Dilnoza», «… onasi
    Rahimova», «Rahimova Dilnoza Karimov Jasur» ↔ Karimov Jasur Rustamovich 85–96% → 29% (taklif yo'q, soxta ⚠️). Endi bo'shliqli
    tire — bo'lak chegarasi; ona so'zidan keyingi so'zlar, boshqa odamning to'liq ismi va o'g'il ismi yonidagi «-ova» — dalil emas;
    otasining ismi shaklidagi so'z faqat o'quvchi ismi YONIDA va jinsi mos bo'lsa zid («Karimov Jasur Bahodirov» — amakivachcha).
  - **O'zbekcha ↔ ruscha yozuvdagi bir ota (o'rta):** «Qodir o'g'li» ↔ Kadyrovich, «Qosim qizi» ↔ Kasymovna, Ortiq ↔ Artyk,
    G'ulom ↔ Gulyam, Botir ↔ Batyr, Qo'chqor ↔ Kuchkar, Jamol ↔ Djamal — 95% → 38–72%, amakivachcha yagona taklif edi. Endi
    otasining ismi solishtirishda q→k, o→a, undoshlar orasidagi y→i, dj/dzh→j, apostrofsiz (R14 da aniqlashtirildi — pastga qarang).
  - **«Humo» (qiz ismi) izoh so'zi qilingan edi (o'rta):** «Valiyeva Humo R.» ↔ Valiyeva Humo 3% (opa-singli Rano 82% ⚠️ siz),
    «Humo» yozilgan to'lovni boshqa bolaga biriktirishda ⚠️ yo'q edi. Endi Humo — ism; faqat karta so'zi yonida («Humo karta»,
    «karta Humo», «Перевод с карты HUMO») — izoh.
  - **Ism bo'la oladigan izoh so'zlari ismda (o'rta):** «Petrova Mayya I.», «Na Viktoriya S.», «Petrova Mayya Guliston»,
    «Karimova Mayya va Karimov Ali», «Karimov Avgust R.» — 90–95% → 3% (boshqa bo'lak, bosh harf, noma'lum so'z «ism o'rni band»
    deb sanalardi). Endi so'z yozuvdagi boshqa so'zga mos so'z yonida (shu bo'lakda) bo'lsa va uning narigi yonida boshqa ism so'zi
    / boshqa harfli ism bosh harfi bo'lmasa — ism; «Karimov Jasur avgust», «Avgust Karimov Jasur», «May Karimov J.» — baribir izoh.
  - **Bosh harf roli yozuvga qarab o'zgarganda (past):** «Jasur Karimov R.» ↔ ukasi Karimov Rustam 68% (bonus bilan 78% ⚠️ siz).
    Endi bunday (noaniq) holatda ball ≤ 64% — bonus bilan ham ⚠️; «Guliston Karimov J.» ↔ Karimov Jasur — 64% (taklif, ⚠️ bilan).
  - Tekshiruv: `name-match.test` 180 (7 yangi to'plam); R12 ko'rigining 114 holati 114/114; R13 ko'rigining hamma juftlari R11
    qiymatiga qaytdi yoki yaxshilandi; 120 000 tasodifiy matnda R12 ga nisbatan 0 farq, R11 ga nisbatan 29 / 32 oshdi, 0 tushdi;
    Chromium «Biriktirish» 110/110 va R13 holatlari (to'g'ri bola taklif qilinadi, noto'g'ri tanlashda ⚠️). Modul manzili `?v=6`.
  - Ongli qoldirilganlar: sinf so'zidan keyingi bo'shliqli bosh harflar («5-sinf A. S. Usmonov») — A sinf harfi (R11 bilan bir
    xil); boshqa familiyali ota («Karimov Jasur Rahimov» ↔ … Rustamovich) — otasining ismi shaklidagi so'z, zid; onasi bilan bir
    xil ismli qiz, onasining ismi oldin («Nazarova Nodira Hamidova Nodira») — juftlash noaniq.
- **Ism solishtirish — R14 (R13 tuzatmalari ustidan yana bir ko'rik): 6 topilma — hammasi tuzatildi:**
  - **Bosh harf ham «buklanardi» (o'rta):** «O.» har qanday A- bilan boshlanadigan otasining ismiga, «A.» esa O- ga mos kelardi —
    otasi boshqa amakivachcha 10% → 95–100% ⚠️ siz, qarzi bo'lsa birinchi. To'liq ismlarda ham Komil/Kamol, Nodir/Kadyr,
    Sarvar/Sardor bir ism deb olinardi. Endi bosh harf faqat aynan mos bo'lsa dalil; faqat ruscha yozuvda mos bosh harf
    («Q.» ↔ Kadyrovich) — dalil ham, zid ham emas (60–64%, ⚠️ bilan); to'liq ism faqat yozilish farqi bo'lsa bir ism (Qodir =
    Kadyr, G'ulom = Gulyam, Jo'ra = Dzhura), o'xshash boshqa ism emas.
  - **Bosh harflardan keyingi oy nomi aka-ukaning ismi bo'lardi (o'rta):** «J.R. Karimov avgust uchun» — ukasi Karimov Avgust
    95–100% ⚠️ siz birinchi; «Оплата Н.С. Петрова 15 мая» — Petrova Mayya. Endi bosh harfli familiya yonidagi oy nomi (yozuvdagi
    birinchi so'z bo'lmasa) ism deb tiklanmaydi.
  - **«5 - A.» sinf harfi bosh harf bo'lib qolardi (past):** endi tire / nuqtadan keyingi nuqtali harf faqat ID'dan keyin
    («IQ-0042. J.») yoki raqamli ro'yxatda («1. J. Karimov 2. A. Karimova») bosh harf; «5 - A.», «5- A.», «11 - B.» — sinf.
  - **So'z ichidagi tire (past):** «Abdul-Aziz», «Karimov-Bahodirovich» bo'lak chegarasi bo'lib, otasining ismi bosh harfi dalil
    bo'lmay qolardi — endi faqat bo'shliqli tire chegara.
  - **«Humo/Uzcard» (past):** «/» bo'lakni ajratib, Humo qiz ismi deb o'qilardi (soxta ⚠️ 74%) — endi karta konteksti.
  - **«Boshqa odamning to'liq ismi» juda keng edi (past):** «Bahodirov Guliston», «Bahodirov matematika», «Bahodir aka» —
    amakivachcha zidligini bekor qilardi. Endi faqat ayol familiyasi shaklidagi so'z bo'lsa («… Rahimova Dilnoza»).
  - Ongli qoldirilganlar (R14): Qobil ↔ Kabulovich (Kabul — Qobul, boshqa ism) — zid, taklif yo'q (R12 bilan bir xil);
    Ibrohim ↔ Ibragimovich, Abdulloh ↔ Abdullayevich — 77% (⚠️ siz, R12 bilan bir xil); Xo'ja ↔ Khodzhayevich — past (R12 dan
    beri); «Karimova Malika Bahodirova Guliston» — «Bahodirova Guliston» boshqa ayol deb o'qiladi.
  - Tekshiruv (R14): `name-match.test` 185 (5 yangi to'plam, 500 belgili matn < 1,5 s); R12 ko'rigining 114 holati 114/114;
    R14 ko'rigining barcha juftlari; 120 000 tasodifiy matnda R12 ga nisbatan 0 farq, R11 ga nisbatan 29 oshdi, 0 tushdi;
    maktab darajasida (366 kishi × 22 shablon × 5 yozuv shakli × 3 qarz holati) R11 ga nisbatan yo'qolgan to'g'ri bola faqat
    ongli qoldirilganlarda; Chromium «Biriktirish» 110/110, «Chiqarish» 37/37. Modul manzili `?v=7`.
- **Ism solishtirish — R15 (R14 tuzatmalari ustidan ko'rik): 6 topilma (ikkitasi bitta xato) — hammasi tuzatildi:**
  - **Raqamga yopishgan sinf / ID / yildan keyingi so'z boshqa bo'lak bo'lib qolardi (o'rta):** «Yo'ldoshev Jasur 5-A Sherzod»,
    «… 5-sinf …», «… IQ-0601 …», «… 2026-yil …» — «5-A» dagi tire bo'shliqli tire deb olinib, otasining ismi dalil bo'lmay
    qolardi: otasi boshqa amakivachcha 64% ⚠️ → 90%, qarzi bo'lsa 100% ⚠️ siz birinchi; uchta amakivachcha qarzdor bo'lsa to'g'ri
    bola umuman taklif qilinmasdi. «Karimov 5-A Jasur R.» — ukasi Karimov Rustam 78% ⚠️ siz. Endi raqamga yopishgan tire
    chegara emas (bo'shliqli tire — avvalgidek chegara).
  - **Sana / katta son / matn boshidagi «1.» dan keyingi bosh harf o'chirilardi (past):** «1. J. R. Karimov», «15.10. J. R.
    Karimov», «№ 42 - J. R. Karimov», «1. Ж. Р. Каримов» — J. sinf harfi deb kesilib, R. ism bosh harfi bo'lib qolardi: ukasi
    Rustam 82% ⚠️ siz yagona taklif. Endi sinf raqami bo'la olmaydigan son (12 va undan katta, ID), sana va matn boshidagi
    «1.» (ketidan yana bosh harf va ism kelsa) dan keyingi nuqtali harf — bosh harf.
  - **Otasining ismida «y» tashlanib qisqargan o'zak (past):** «Karimov Jasur Ahadov» ↔ …Yahyoyevich, «Fozilov» ↔
    Fayziyevich, «Aubakirov» ↔ Ayubovich — boshqa otalar bir ism deb olinib, amakivachcha 10% → 90% (qarzi bo'lsa 100%
    birinchi). Endi -ov shaklida o'zagi aynan teng yoki «y» bilan ham boshi bir bo'lishi kerak («G'ulomov» = Gulyamovich,
    «Hayitov» = Khaitovich, «Qodirov» = Kadyrovich — avvalgidek).
  - **Otasining ismi + onasining familiyasi (past):** «Karimov Jasur Bahodirov Rahimova (Dilnoza)» — «Bahodirov Rahimova»
    boshqa ayolning ismi deb, amakivachcha 29% → 86–96% bo'lardi. Endi ayolning to'liq ismi — familiya + otasining ismi
    shaklida bo'lmagan ism («Rahimova Dilnoza»).
  - **«HUMO|UZCARD» (past):** «|» bo'lakni ajratib, Humo qiz ismi deb o'qilardi (soxta ⚠️ 64–74%) — endi «/» kabi karta konteksti.
  - **«J.» ↔ Дж / Dzh / Ж (qo'shimcha, skanerda topildi):** R14 dan beri «Karimov Muhammad J.» ↔ Каримов Мухаммад Джамалович
    betaraf (64% ⚠️) edi, «J. Karimov» ↔ Каримов Джамшид esa hamma versiyada zid (3%). O'zbekcha J ruscha Дж / Ж bilan
    bir harf (Q/K, O/A kabi ikki xil o'qilmaydi) — endi bosh harf sifatida mos (95% / 72%); Q. ↔ Kadyrovich, O. ↔ Akmalovich —
    avvalgidek betaraf.
  - Ongli qoldirilganlar (R15): sinf raqami (1–11) + tire / nuqta + bo'shliqli ikki bosh harf («5- J. R. Karimov») — birinchi
    harf sinf harfi deb o'qiladi; bu yozuv «5 - A. J. Karimov» (A sinf, J. ism) bilan bir xil va ularni ajratib bo'lmaydi;
    «1. J. Karimov» (yakka bosh harf) — 57%, R12 bilan bir xil; «Humo, Uzcard», «Humo (karta)» — vergul / qavs bo'lak chegarasi;
    bo'shliqli tireli sinf («… 5 - A Sherzod») — R13 dagi kabi chegara.
  - Tekshiruv (R15): `name-match.test` 191 (6 yangi to'plam — eski modulda 6 tasi ham yiqiladi); R12 ko'rigining 114 holati
    114/114; R13/R14 ko'riklarining 169 jufti R14 bilan aynan bir xil; ko'ruvchilarning barcha R15 juftlari va Chromium
    ssenariylari (12 ta) tuzalgan; 1200 o'quvchili maktabda tire / sinf / ID / yil skaneri (4 yozuv shakli × 30 shablon × 4 qarz
    holati) — R13 va R12 dan yomon holat faqat ongli qoldirilganlarda; maktab darajasidagi skaner (R11 / R12 ga nisbatan)
    9dda871 bilan bir xil; Chromium «Biriktirish» 110/110, «Chiqarish» 37/37. Modul manzili `?v=8`.
- **Maosh / formalar — R15 (9dda871 ustida haqiqiy stekda ko'rik): 4 xato (6 topilma) — hammasi tuzatildi:**
  - **Javobi yo'qolgan maosh + shu orada ID o'zgarsa — «yozilmadi» (past, 2e8911c regressiyasi):** kassir «Berish»ni bosgan,
    yozuv bazaga tushgan, javob yo'qolgan; HR shu orada xodim ID'sini o'zgartirgan (yozuv yangi kalitga ko'chgan). Qayta bosishda
    «maosh hech kimga yozilmadi» chiqardi — kassir ikkinchi marta berishi mumkin edi. Endi «eskirgan» xabaridan oldin shu
    oynaning yozuvi id bo'yicha o'qiladi: bor bo'lsa — «✓ Maosh berildi» (takror yozilmaydi); o'qib bo'lmasa — «tekshirib
    bo'lmadi, qayta urinib ko'ring» («yozilmadi» deyilmaydi).
  - **Yangi o'quvchi: bir xil ism tekshiruvi (past):** javobi yo'qolgan qator bazada, oyna yopilib bola qayta qo'shilsa — ism
    oxiridagi bo'shliq, katta-kichik harf yoki apostrof turi («O‘g‘iloy» / «O'g'iloy») farq qilsa tekshiruv uni topmasdi
    (ikkita o'quvchi, ikkala fakturasi). Endi ism saqlashdan oldin qirqiladi, bazadan katta-kichik harfsiz so'raladi
    (shim'da `ilike`) va bo'shliq / apostrof farqisiz solishtiriladi; shu oynada ID o'zgartirilsa — o'z qatori ham «bor» deb
    ko'rsatiladi.
  - **Stavka tarixi standart stavkalarni yozmasdi (past):** `config/salary` hali bo'lmagan maktabda birinchi «Stavkalarni
    saqlash» `ratesPrev = []` yozardi — boshqa sessiyalar stavka o'zgargani uchun eskirgan maoshni yangilamasdi (ro'yxat / CSV).
    Endi avvalgi stavka sifatida standart stavkalar yoziladi.
  - **Maosh kaliti «oracle»si (past, 512a649 dan beri):** `app.guard_payroll_id` har qanday foydalanuvchiga (ota-ona, o'quvchi,
    qabulxona…) POST /teachers yoki /staff javobidagi 23505 / 42501 farqi bilan taxmin qilingan ID bor-yo'qligini bildirardi.
    Endi trigger faqat direktor / HR uchun ishlaydi (ularning RLS'i bilan bir xil), qolganlarga RLS xabarsiz rad etadi (42501).
  - Tekshiruv (R15): o'z portlarimdagi PG16 + PostgREST + Chromium stekida ko'ruvchilarning skriptlari: ism tekshiruvi 8/8
    variant (qabulxona va direktor), shu oynada qayta bosish / ID o'zgarishi / yangi o'quvchi (t6, t9) o'tdi; stavka tarixi
    qatorsiz va qator bilan 7/7; javobi yo'qolgan maosh + ID o'zgarishi 2/2; ID «oracle» — hamma rol uchun 42501; SQL
    to'plamlari t7_review 60/60, t3_rekey 28/28, t6_staff 11/11, f1 23/23, f3 11/11, F3 poygasi 12/12 (qolgan eski
    kutilmalar 9dda871 da ham xuddi shunday); shim selftest'ga `ilike` qo'shildi.
- **Maosh / avans kaliti:**
  - **Eski oynadan berilgan maosh ID'ning yangi egasiga yozilardi (o'rta→past):** kassir «Maosh berish»ni ochgan, shu orada HR
    Anvarning ID'sini IQT-001 → IQT-050 qilib, bo'shagan IQT-001 ni Nodiraga bergan bo'lsa — «Maosh berildi — Aliyev Anvar», yozuv
    esa Nodira kaliti ostida (Nodira kam oladi, Anvarga ikki marta beriladi). Endi maosh/avans yozuvida `payeeRef` (jadval:qator
    id) — baza yozuvni shu odamning HOZIRGI kaliti bilan solishtiradi, teng bo'lmasa rad etadi; «ALLAQACHON berilgan» savolidan
    oldin ham xodim qatori qayta o'qiladi; oylik hisobotdagi «💵 Oylik» xodimni qator id'si bilan ochadi (hisobot eskirgan bo'lsa
    — ogohlantirish va yangilash, boshqa odam yoki ro'yxatdagi birinchisi tanlanmaydi).
  - **Xato xabari (past):** kassir faqat «Xatolik: 23503» ko'rardi va shu oynada qayta bosardi — endi «Maosh yozilmadi — oynani
    yopib, qayta oching» (server izohi bilan), hisobot darhol yangilanadi; avansda javobi yo'qolgan bosish «yozildi» deb ko'rsatiladi.
  - **Bir vaqtdagi ikki yangi ID (past):** ikki HR bir soniyada bir xil ID bilan xodim qo'shsa yoki ID o'zgartirish bilan to'qnashsa —
    ikkalasi ham o'tib, bitta kalit ikki kishida qolardi. Endi takror tekshiruvi `rekey_payroll_id` bilan bir xil qulfda (300 juft
    parallel yozuvda 0 dublikat).
  - **Kalit «oracle»si yopildi:** maosh ko'ra olmaydigan foydalanuvchi (ota-ona, o'qituvchi, qabulxona) xato matnidan xodimning
    maosh kalitini bilib olardi — endi u holda tekshiruv xabarisiz RLS rad etadi.
- **Formalar:**
  - **Excel import / yangi o'quvchi — javob yo'qolsa dublikat (o'rta):** INSERT bazada yozilgan, javobi esa yo'qolgan bo'lsa (tarmoq,
    504; Chromium POST'ni o'zi qayta yuborishi ham mumkin) qayta «Saqlash» o'z qatoriga urilib, «ID band» deb ikkinchi nusxani
    yaratardi (ikkalasiga faktura) yoki fayldagi ID bilan maxfiy ma'lumotni tashlab ketardi. Endi 23505 da bazadagi qator o'qiladi
    — o'zimiz yozgan qator (ID, ism, sinf, guruh, yo'nalish, til, tartib) bo'lsa yozilgan deb hisoblanadi; qator ID'si xatoda
    saqlanadi; yangi o'quvchi formasida javob kelmasa «shu oynada qayta Saqlash» xabari, bir xil ism bazadan ham tekshiriladi.
  - **Forma ochilishi poygasi (past):** maxfiy maydonlar o'qilayotganda boshqa qatorni bosish mumkin edi — kech kelgan o'qish B
    formasini A bilan almashtirib, kiritilgan narsa A ga yozilardi. Endi «yuklanmoqda…» oynasi ro'yxatni yopadi, faqat oxirgi
    chaqiruv chiziladi, o'qib bo'lmasa forma ochilmaydi («Qayta urinish»).
  - **Maosh stavkasi o'zgargach saqlangan maosh (past):** faqat bonus stavkasi o'zgarganda «Saqlash» ro'yxatdagi «Maosh»ni
    yangilamasdi. Endi saqlangan maosh avvalgi stavkalardan biri bilan hisoblangan bo'lsa (shu sessiya va bazadagi tarix
    `config.ratesPrev`, oxirgi 6 ta) — joriy stavka bilan yangilanadi; boshqa sababdan mos kelmaydigan eski qiymat tegilmaydi.
  - **HIK report (past):** shu orada Kamera ID'si o'zgargan odam o'tkazib yuborilsa — endi xabarda ismi bilan aytiladi.
  - Ongli qoldirilgan: import oynasi yopilib, fayl qayta import qilinsa — javobi yo'qolgan qator «o'zgarishsiz» deb o'tkaziladi
    (maxfiy ma'lumoti yozilmaydi); 504 da nginx HTML matni toastda ko'rinadi.

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
