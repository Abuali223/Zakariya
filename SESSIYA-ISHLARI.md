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
- Sabab: 14-oktyabrdagi o'zgarish oilani FAQAT ota/ona F.I.Sh bo'yicha guruhlardi (farzand ismi faqat ota/ona maydonlari butunlay bo'sh bo'lsa). Kartalarda ota/ona maydonlari har xil to'ldirilgan bo'lsa (birida faqat ota, birida faqat ona — o'z familiyasida) oila «2 + 1» bo'linib, 2 kishilik guruhda faqat bittasi (ID tartibi) 10% olardi. Skrinshotdagi holat (bir bola chegirmali, ikki aka-ukasi to'liq narxda) testda aynan qayta hosil qilindi.
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
  — «Xadicha uchun», «Tirg'unboyeva X.» endi yalang ism bilan bir xil ball oladi. Kirill «сҳ» = `s'h` (Исҳоқов = Isxoqov).
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
- Topshiriqdagi holatlar (`payments/name-match.test.cjs` konsolga chiqaradi): «Tirg'unboyeva Hadicha» → 100%,
  «Тирғунбоева Хадича» → 100%, «Xadicha Tirgunboeva» → 91% (yuqori moslik); «Aliyev Jasur» → 0% (taklif qilinmaydi,
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
  «Familiya Ism» (5-sinf «A» · O‘zbek, ID IQ-NNNN) chiqarilsinmi? — chiqqan sana va «⚠️ Qaytarish (qayta
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
  harfi; Ra'no / Jo'ra / G'ayrat / O'tkir / Tirg'unboyeva 100%. **O'rta:** raqamdan keyin bo'shliq bilan yozilgan qisqa ism
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
  Qo'shtirnoq / ko'rinmas belgi so'zlar ORASIDA (bo'shliqsiz, «Tirg'unboyeva«Xadicha»») so'zlarni yopishtirib qo'ymaydi.
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
- **R16 (fef23af ustida mustaqil ko'rik): 3 topilma (hammasi past) — 2 tasi tuzatildi, 1 tasi ongli qoldirildi:**
  - **Onasining ismi otasining ismi shakliga o'xshasa (R15 regressiyasi):** «Ivanova Lyubov Petrov Mark», «Petrova Anna Ivanova
    Eva», «… Rahimova Zeba / Sevi» — R15 dagi «otasining ismi + onasining familiyasi» qoidasi Lyubov / Eva / Zeba / Sevi ni ham
    otasining ismi deb olib, to'g'ri bolani 85% → 10–64% ga tushirardi. Endi ayolning to'liq ismidagi ism otasining ismi shaklida
    deb faqat o'zagi 3+ harf bo'lsa olinadi (Lyubov / Любовь, Ruboba — ism ro'yxatida); «Bahodirov Rahimova» — baribir zid.
  - **Yangi shim keshdan eski olinardi:** `sb/firebase-firestore.js` o'zgardi (`ilike`), lekin `admin.html` uni avvalgidek
    `?v=2` bilan import qilardi — deploydan keyin ochiq qolgan oyna (yoki service worker'siz brauzer) eski shimni ishlatib, yangi
    bir xil ism tekshiruvi jim ishlamasdi. Endi `?v=4` (`?v=3` ni index.html eski shim uchun ishlatadi).
  - Ongli qoldirilgan: apostrofsiz o' + ruscha yozuv («Qochqor» ↔ Kuchkarovich, «Tolqin» ↔ Tulkinovich) — 48–64% (⚠️, to'g'ri
    bola qo'lda tanlanadi; boshqa bola chiqmaydi). Apostrof bilan («Qo'chqor», «To'lqin») — 90%+. Yakka «o» ni «u» deb ham o'qish
    Olmos ↔ O'lmas, Qozi ↔ Qo'zi kabi boshqa otalarni bir xil qilardi.
  - Tekshiruv (R16): `name-match.test` 192 (yangi to'plam fef23af modulida yiqiladi); probe12 114/114; avval tuzatilgan 271 juft
    o'zgarmadi; Chromium «Biriktirish» 110/110, «Chiqarish» 37/37; haqiqiy stekda bir xil ism (x3 10/10, x6 — shim `?v=4`),
    rollar 9/9, hisobot kalitlari 9/9; shim selftest; to'lov testlari to'liq. Maosh / formalar bo'yicha R16 ko'rigi xato topmadi.
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

## 38) Deploy tayyorligi — to'liq deploy buyrug'i (`full-deploy.sh`) va `deploy.sh` mustahkamlash
Oxirgi deploy'dan beri katta o'zgarishlar bo'lgani uchun deploy alohida tekshirildi (4 yo'nalish, wf_6d1980f9): `deploy.sh`
qamrovi, eski prod holatlaridan baza yangilanishi (PG16 + Supabase o'rinbosarlari + PostgREST), brauzer keshi / service worker
(Chromium) va to'liq simulyatsiya qilingan server (namespace, systemd/docker o'rinbosarlari, haqiqiy PG16) — 5 ta eski holatdan
(69d33af, 815becd, 9d76057, c66d0b3, 9dda871).
- **Natija:** `deploy.sh` o'zgargan barcha ish fayllarini qamraydi; deploy'ga kirmaydigan statik fayllar (vendor/, ikonlar,
  manifest) hech qaysi holatdan beri o'zgarmagan; har holatdan yangilanish o'tdi, 7/7 «BIR XIL (2270)», ikkinchi ishga tushirish
  ma'lumotni o'zgartirmaydi. Brauzerda eski shim keshi muammosi 77eca17 da (`?v=4`) tuzatilgan; SW versiyasini oshirish
  oflayn rejimni buzishi aniqlandi (oshirilmadi); faqat admin.html'ni nusxalash ishlamaydi (shimlarsiz) — doim to'liq deploy.
- **Tuzatildi (kod):**
  - **To'lov kanonlashi to'qnashuvda (o'rta, 69d33af/815becd'dan):** `invoice-guards.sql` doc-id bilan qolgan to'lov/qaytarishni
    o'quvchining studentId'siga ko'chirardi — import to'qnashuvida (studentId boshqa o'quvchining id/studentId'siga teng) pul jim
    BOSHQA bolaga o'tardi. Endi bunday qatorlar doc id'da qoladi va deploy `⚠️ OGOHLANTIRISH` ko'rsatadi.
  - **`/opt/iqror` 0750 (o'rta):** sinxronlash `sudo`siz `[ -d ]` bilan tekshirilgani uchun jim o'tkazilib, xizmatlar ESKI kod bilan
    qayta ishga tushardi, deploy esa ✅ derdi. Endi `sudo test`.
  - **Root egali kod papkasi (o'rta):** `tar` yarim yo'lda (baza va sayt yangilangandan keyin) xato berib, `/opt` aralash qolardi.
    Endi yozish huquqi bazaga tegishdan OLDIN tekshiriladi — deploy boshlanmaydi va `chown`/`chmod` buyrug'ini ko'rsatadi; server
    kodiga o'xshamaydigan WorkingDirectory ham shu yerda to'xtatadi (`IQROR_ALLOW_UNSYNCED=1` — ongli o'tkazish).
  - **Qat'iy /tmp fayllari (past):** avvalgi `sudo` ishga tushirishdan qolgan root egali `/tmp/iqror-*` soxta «migratsiya xato» va
    7/7'da ESKI natija bilan soxta «BIR XIL» berardi. Endi har ishga tushishda `mktemp`; barmoq izi olinmasa — xato.
  - **Kichiklar:** lock timeout'da sabab va kim band qilgani; muhim NOTICE'lar (to'qnashuv, arvoh kodlar) chiqishda; o'rnatilmagan
    unit o'tkaziladi (avval deploy'ni oxirida uzardi); `*.bak` faqat sahifa o'zgarganda (qayta ishga tushirish eski nusxani
    yo'qotmaydi); xizmat holati 5 s + NRestarts (keyinroq yiqiladigani ham ushlanadi); 7/7 farqida yakuniy xabar ⚠️;
    `DB_CONT` o'zgartirilishi mumkin; `sudo bash deploy.sh` — aniq xabar; «Davomat %» tenglashi MATERIALIZED (3000 o'quvchida
    ~4.9 s → ~0.4 s qulf ostida, natija aynan bir xil).
- **Yangi:** `migration/deploy/full-deploy.sh` (oldindan tekshiruv → zaxiralar → deploy → fayl-ma-fayl keyingi tekshiruv) va
  `migration/deploy/predeploy-checks.sql` (faqat o'qiydi). Buyruq: `migration/deploy/README.md` → «To'liq deploy».
- **Simulyator ko'rigi, 2-raund (14e0baf ustida; 10 nosozlik + 11 yangilanish yo'li, 69d33af..9dda871):** yangilanish yo'llari
  hammasi o'tdi (`.bak` eski nusxada qoladi, to'qnashuv himoyasi ishlaydi, «Davomat %» funksiya bilan bir xil). Topilgan va
  tuzatilganlar: 0751 root:root `/opt/iqror`da oldindan tekshiruv o'tib, 6-bosqichdagi `tar -C` o'qish huquqi yo'qligidan yiqilardi
  (baza va sayt yangilangandan keyin) — endi `cd` bilan, tekshiruv bilan aynan bir xil; `full-deploy.sh` yiqilib qayta ko'tarilayotgan
  xizmatni ✅ derdi — endi «!!» va kod 2; SQL FATAL/ulanish uzilganda xato hisoboti `set -e` bilan uzilib, log yo'li aytilmasdi;
  WorkingDirectory'siz unit jim o'tkazilardi (eski kod qayta ishga tushardi) — endi ExecStart'dan topiladi, topilmasa boshlanmaydi;
  `sudo -E bash deploy.sh` butun deployni root qilardi; uzoq tranzaksiya kutishida eskirgan ogohlantirish; `web_/srv_` arxivlari
  tozalanmasdi; zaxira fayllari noclobber bilan (symlink orqali ustidan yozilmaydi). Qayta sinov (c4cbbfe): hammasi kutilganidek.
- **Yakuniy tayyorlik (fe34e00, ef3cdb5):** to'lov kanonlashida 2-shakl to'qnashuv — o'quvchining doc id'si BOSHQA o'quvchining
  studentId'si bo'lsa (A2: id fbA2, kalit IQ-0921; B2: id IQ-0921, kalit IQ-0922), A2'ning IQ-0921 bilan yozilgan to'lovi B2'ga
  (IQ-0922) ko'chib ketardi (simulyator: 1 100 000) — endi joyida qoladi, predeploy 1-band ham ko'rsatadi; `backup.sh` va
  `full-deploy.sh` zaxira fayllari noclobber + `mv -T` (2169 ta oldindan qo'yilgan symlink bilan sinaldi — nishon fayl buzilmadi).
- **Yakuniy raqib ko'rigi (ef3cdb5; standart server — tayyor, 69d33af/c66d0b3/9dda871/77eca17 matritsasi o'tdi) topilmalari,
  32aad0e da tuzatildi:** `backup.sh` /opt/iqror/backups ichidagi HAR QANDAY 14 kundan eski `*.gz`ni (qo'lda qo'yilgan dump'larni,
  ichki papkalarda ham) o'chirardi — endi faqat o'z fayllari; guruhga yoziladigan, lekin egasi boshqa kod papkasi oldindan
  tekshiruvdan o'tib, tuzatmasiz tar'da 6-bosqichda (baza va sayt yangilangandan keyin) yiqilardi — endi egalik ham tekshiriladi;
  masklangan iqror-ai/pay soxta «BOSHLANMADI» berardi — endi masklangan/o'chirilgan xizmatga tegilmaydi; `WorkingDirectory=-/opt/iqror`
  yoki `~` repo ichi deb o'qilib /opt jim o'tkazilardi; sudo UMASK 027'da yangi sayt fayli 0640 (nginx 403) — endi 0644;
  69d33af/815becd'dan birinchi deployda kanonlash indekssiz ~14 s qulf ostida — endi indeks oldin (0,5 s).
- **Yakuniy tekshiruv (84336cc; kod 32aad0e bilan bir xil) — TAYYOR:** simulyatorda 9d76057 bazadan bitta buyruq: sudo UMASK 027'da
  ✅ (sayt fayllari 0644, zaxiralar 600; faqat eski `db_*` o'chdi — `manual/` va qo'lda qo'yilgan dump'lar qoldi), qayta ishga
  tushirish ✅; egasi boshqa kod papkasi (root:iqror 0775) — bazaga tegmasdan BOSHLANMADI (barmoq izi 2258→2258, ma'lumot, sayt,
  `config.json` bir xil, xizmatlar qayta ishga tushmadi), «Tuzatish:» buyrug'idan keyin ✅; masklangan iqror-ai va o'chirilgan
  iqror-pay'ga tegilmadi ✅; `WorkingDirectory=-/opt/iqror` — /opt yangilandi ✅; nisbiy yo'l — BOSHLANMADI ✅; zaxira nomlaridagi
  symlink'lar — nishon o'zgarmadi ✅. (Bir marta ko'ringan «xizmat failed» simulyator stub'ining o'zida edi: holat fayllari
  chaqiruvchining umask'ini olardi; haqiqiy systemd'da bunday emas — stub tuzatildi, qayta sinov ✅.) Testlar: 11 to'plam
  (sms 41, eskiz 25+48, name-match 192, auth 94, sms-remind 114, phone 186, attr/uzum/flow/sb-admin) — hammasi o'tdi.
- **Ongli qoldirilgan / qo'lda:** eski 69d33af `deploy.sh` o'zini yangilay olmaydi — buyruq avval `git checkout FETCH_HEAD -- deploy.sh
  migration` qiladi; deploy tinch paytda (lock_timeout 20 s; to'lov RPC'lari bilan deadlock ehtimoli — provayderlar qayta urinadi);
  deploy'dan keyin ochiq admin oynalarini yangilash; takroriy maosh kalitlari va chetida bo'sh joyli o'quvchi kalitlari — faqat
  SQL bilan (predeploy 2–3-band); 7/7 barmoq izi trigger/indeks/grant'larni solishtirmaydi (bugun yashirin farq topilmadi);
  `npm` faqat repo'da; bazani zaxiradan tiklash oddiy emas (avval kod bo'yicha orqaga qaytarish).

## 39) Kirim-chiqim: Google Sheet («IQRO_Financial_Tracker_2026_2027») va tizim — tahlil
Buxgalteriya hozir Google Sheet'da (Dashboard + har oy «tushum»/«chiqim»). 4 agentli tahlil (tizim inventarizatsiyasi, Sheet
semantikasi, farqlar + taklif, raqib-tekshiruv) — to'liq hisobot: `KIRIM-CHIQIM-TAHLIL.md`.
- **Sheet'dagi muammolar:** «Noyabr tushum» buzilgan (hamma «Active», 11 yangi o'quvchi yo'q — ularning qoldig'i yo'qoladi);
  3 ta takroriy ID (ortiqcha qarz); ID'siz to'lovlar; chiqib ketganlarda «osilgan» avans (4 tasi chiqimda qaytarilgan — ikki
  marta) va qarz; bankka topshirilgan tushum «xarajat» deb yozilgan (foyda kam). (ID va summalar 2026-10-30 da olib tashlandi.)
- **Tizim bilan:** to'lov usullari, qarz o'tishi, avans, qaytarish, biriktirish — bor (yaxshiroq); xarajatda tasdiqlovchi /
  Р/О / usul / kimga — yo'q; oylik o'quvchi reyestri, Kutilgan (qoldiq bilan), Yig'im %, sinflar va 12 oylik jadval, eksport —
  yo'q; chegirma/prorata/referral/reward qoidalari farq qiladi (D1–D10); «Kirim» faktura asosida, Sheet kassa asosida.
- **Qarorlar (2026-10-26):** hozircha faqat tahlil (kod o'zgarmaydi); import yo'q — noyabrdan tizim asosiy manba; pul
  hisoblash qoidalari tizimdagidek qoladi. Keyingi bosqichlar taklifi — hisobotda, 8-bo'lim.

## 40) Prod deploy (2026-10-27, c66d0b3 → 38f6554) — natija va keyingi qadamlar
`✅ TO'LIQ DEPLOY MUVAFFAQIYATLI`: 72 fayl bitta tranzaksiyada, 7/7 «BIR XIL» (2270 obyekt), xizmatlar active + `/health` ok,
yangi obyektlar 5/1/7, sayt fayllari yangi. Xizmatlar repo'dan ishlaydi (`papka=/home/ubuntu/iqror-repo`) — /opt sinxroni va `srv_*`
zaxirasi kerak bo'lmadi (kod git'da; `config.json` git'ga tegmaydi). Chiqishdagi ⚠️/ℹ️ qatorlar tahlili (PG16'da sinaldi) +
4 ko'zli raqib-tekshiruv (har topilma ikkinchi skeptik bilan) — tuzatilganlari:
- **Zaxira cron yo'q** (eng muhimi). Buyruq: BITTA `sudo sh -c '…crontab -l | grep -av … | crontab -'` — `sudo -v` bilan avvalgi
  shakl Ubuntu cloud image'da (NOPASSWD + %sudo, qulflangan parol; verifypw=all) parol so'rab to'xtardi, pipeline'dagi ikki sudo
  esa noto'g'ri parolda root'ning boshqa cron qatorlarini JIM o'chirardi; `grep -a` — UTF-8 bo'lmagan qatorlar ham saqlanadi
  (soxta crontab bilan 4 holat). `backup.sh`: cron'ning tor PATH'ida docker topilsin (standart papkalar + `/snap/bin` PATH
  OXIRIGA) va docker umuman topilmasa — «konteyner ishlamayapti» o'rniga aniq «docker buyrug'i topilmadi». Cron muhitida sinov:
  `sudo env -i PATH=/usr/bin:/bin HOME=/root bash …/backup.sh`. Hajm: kuniga ~4 MB (baza), fayllar 0 MB — 14 kunda ~60 MB.
- **Takroriy maosh kalitlari** IQT-016 (xodim + o'qituvchi), IQX-001 (2 xodim), tarixi 0. Aralashuv emas — maosh/avans berish
  BLOKLANGAN (isDupId, «⛔ Takroriy ID» kartasi) — birinchi oylikdan OLDIN tuzatish. Ilova yo'li to'g'ri (PG16 + direktor JWT):
  yangi admin.html takroriy kartani sof UPDATE bilan saqlaydi (eski oynaning upsert'i 23505 — shuning uchun Ctrl+Shift+R);
  «ID o'zgartirish» yangi ID bilan `shared=true, moved=false`; keyin 3-band bo'sh. FAQAT xodim kartasi: o'qituvchi (Nodirov)
  o'zgartirilsa «xodim farzandi» bog'lanishi IQT-016'da xodimga qolardi — tasdiqda «xodim farzandi» so'zi = o'qituvchi kartasi.
- **169 arvoh kod.** Raqib topdi: kaliti TIRIK o'quvchining studentId'siga teng kod (import: o'chirilgan dublikat IQ-0042 + tirik
  fbX9/IQ-0042) arvoh EMAS — to'lov serveri «IQ-0042 KOD» to'lovini u bilan tirik bolaga biriktiradi (codeMatchesAny + studentExists;
  attr.test T14b). Deploy'ning avto-tozalashi (student-ids.sql), predeploy 5-band va README buyrug'i endi faqat `s.id = sc.id OR
  s."studentId" = sc.id` mos kelmaydiganlarni oladi (sinaldi: IQ-0921 qoldi). Ikkinchi topilma: `student_id_high_water` ota-ona
  ko'radigan jadvallarning bir qismini olmasdi (characteristics, subject_notes, student_summaries, olympiads, credit_ledger,
  refunds, student_private) — kod o'chirilgach o'chirilgan bolaning IQ raqami yangi bolaga berilib, YANGI ota-ona eski bolaning
  tavsifnomasini ko'rardi (raqib PG16'da ko'rsatdi). Endi union to'liq; `student_history` → `other`/`private` (admin.html: yangi
  o'quvchi formasi va import ham tekshiradi; o'chirish ogohlantirishlari o'zgarmadi). README tozalash buyrug'i heredoc'siz
  (`psql -1 -c … -c …`; chekinish/«SQL» terminator xatosi yo'q; xatoda to'liq orqaga — sinaldi).
- **Eskiz:** auth serveri ✅ (OTP #94502, «Eslatma» #94504 MOS); `payments/config.json` da kalit yo'q va SMS cron yo'q — avtomatik
  qarz/yangi faktura SMS ishlatilmayapti (ixtiyoriy). `eskiz-shablon.cjs` maslahati sababga qarab (`roleTip`): kalit yo'q/
  to'ldirilmagan — shu faylga yozish (nusxa + JSON tekshiruvi; auth uchun keyin restart; sms-worker uchun ixtiyoriy); JSON buzilgan /
  papka — «SHU faylni tuzating» (xizmat buzilgan fayl bilan yiqiladi); ruxsat yo'q — sudo; topilmadi — `--config <xizmat papkasi>/…`
  (`systemctl show -p WorkingDirectory`). Erta chiqishda ham maslahat; explicit rejimda kalitsiz fayl — ⚪ (chiqish 1 emas). JSON
  tekshiruv buyrug'i faqat OK/«JSON xato» chiqaradi (Node'ning o'z xatosi fayl qatorini — parol bilan — chiqarardi). 58/58 test.
  `payments/README.md` §7.4: log fayli foydalanuvchiga yoziladigan (aks holda cron qatori umuman ishlamaydi) + `node` to'liq yo'li.
- **AI:** `/health` → `claude-opus-4-8` — amaldagi model (o'zgartirish shart emas).

## 41) O'qituvchi/xodim ID'si — PASPORT kabi (o'zgarmas, hech qachon qayta berilmaydi)
Talab: «ID'ni pasport singari o'zgarmas qil — tahrirlasa ham; o'qituvchi/xodim o'zgarsa ham takrorlanib qolmasin».
- **Reyestr `public.payroll_ids`** (id = kanonik `upper(btrim)`, coll/row_id, source, released_at): har berilgan teacherId/staffId.
  Hech qachon o'chirilmaydi (egasi o'chirilsa/almashsa — faqat `released_at`). RLS yoqilgan, mijozga grant yo'q (service_role —
  faqat o'qish); faqat SECURITY DEFINER funksiya/triggerlar yozadi. Har deploy'da to'ldiriladi (idempotent): joriy ro'yxat
  (takroriyda prefiksi jadvaliga mos egasi birinchi) + tarix — maosh, avans, «xodim farzandi», `users.staffCode` (o'chirilgan
  odamning login yorlig'i ham). Takroriy ID'lar deploy chiqishida `OGOHLANTIRISH` bilan.
- **BEFORE trigger** (`guard_payroll_id`): ilova foydalanuvchisi (har qanday rol) mavjud ID'ni o'zgartira olmaydi — faqat
  `rekey_payroll_id` ichida (`iqror.rekey`), aks holda 42501 (eski oyna / API / upsert). YANGI qator (direktor/HR): faqat shu
  jadval prefiksi + kanonik raqam (22023), raqam > high-water va reyestrda yo'q (23505), shu ID bo'yicha navbatda (advisory lock).
  Mavjud qatorga upsert (setDoc) — o'tkaziladi (ID o'zgarishini UPDATE yo'li ushlaydi). BEFORE INSERT'da ID avtomatik
  BERILMAYDI (upsert'ning EXCLUDED qiymatiga oqib ketardi) — ID'ni mijoz hisoblaydi, baza tekshiradi.
- **AFTER trigger** (`record_payroll_id`): yakuniy qiymat reyestrga (band bo'lsa ilova — 23505, har izolyatsiyada PK to'siq; SQL —
  qayta bog'lash yoki NOTICE); eski ID — boshqa joriy egasi qolmasa «bo'shatilgan». SQL/service_role tekshiruvsiz, lekin yoziladi.
- **`payroll_id_state(coll,row)`** → `{reason: empty|unique|duplicate|keep, fixable, next}`: takroriyda prefiksi mos egasi
  ID'ni SAQLAYDI (IQT-016: o'qituvchi Nodirov qoladi, xodim Abdullayeva tuzatiladi; IQX-001 — ikkala xodimda tugma, birini
  tuzatish kifoya). **`rekey_payroll_id`** — faqat bo'sh/takroriy ID, BIR MARTA; yangi ID shu prefiks + kanonik + > high-water
  (navbat ichida qayta tekshiriladi); tarix (maosh/avans/farzand) faqat egasi yagona bo'lsa ko'chadi.
- **admin.html:** ID maydoni doim qulf; tahrirda ID umuman yozilmaydi (DOM o'zgartirilsa ham); bo'sh/takroriy ID'da
  «Yangi noyob ID berish» (+ «Bekor»), tasdiq «Bir martalik ID tuzatish …»; 23505 bo'lsa yangi taklif. Yangi kartada ID
  «Saqlash»da bazadan hisoblanadi (`payrollNextId`: ikkala ro'yxat + `payroll_id_high_water`; RPC xatosi — saqlanmaydi);
  barqaror qator id'si (`_pidRow`) — javobi yo'qolgan INSERT'dan keyin qayta «Saqlash» ikkinchi odam yaratmaydi; ID band
  bo'lsa keyingi raqam bilan qayta (2 marta). HIK kamera importi ham shu qoida bilan (3 urinish; high-water o'qilmasa —
  qo'shmaydi). O'chirish tasdig'ida ID va «qayta berilmaydi». Eski «qo'lda ID yozish» va eski baza PATCH fallback'i olib tashlandi.
- **Deploy:** `full-deploy.sh` yakuniy tekshiruvi — 8 funksiya, 9 trigger (yoqilgan), reyestr soni/RLS, «reyestrda yo'q joriy
  ID: 0», takroriy ID'lar soni; `predeploy-checks.sql` 3-band (upper(btrim) bo'yicha), 9-band (abadiy band bo'ladigan
  o'chirilganlar ID'lari), 10-band (reyestrda yo'q joriy ID). README «O'qituvchi/xodim ID'si — PASPORT kabi» + 3-band yangi tartib.
- **Sinov:** PG16 (HEAD zanjir → prod'ga o'xshash ma'lumot → yangi zanjir ×2): funksional T00–T25, parallel C1–C6 (bir xil ID
  ikki INSERT — ikkinchisi 23505; ikki tuzatish — 42501; REPEATABLE READ — serializatsiya xatosi, takror yo'q); verify-db «BIR
  XIL» (+ trigger/constraint/index barmoq izi bilan ham). HAQIQIY admin.html + shim + PostgREST 12 + Chromium: 74/74 (yangi
  o'qituvchi/xodim, DOM/API soxtalashtirish, IQT-016/IQX-001/bo'sh ID tuzatish, o'chirilgan ID qayta berilmasligi, HR, ikki
  admin poygasi, javob yo'qolishi, eskirgan taklif) + kamera importi 11/11. Unit: payments 192, auth 186, sb-admin ✓.
- **Raqib ko'rigi** (3 yo'nalish × skeptik tekshiruv; 8 topilma, hammasi tuzatildi):
  - (yuqori) Ochiq ro'yxatdan o'tgan hisob (users qatori hali yo'q) `users_ins` orqali o'ziga `staffCode='IQT-999999999'` yozib,
    yangi ID chegarasini abadiy ko'tarardi (9 xonadan oshgach yangi o'qituvchi/xodim qo'shib bo'lmasdi); qabulxona —
    `student_private."teacherId"` orqali. Tuzatish: `staff-user-link.sql` users_ins — self-insert'da staffRefType/staffRefId/
    staffCode bo'sh bo'lishi shart (users_upd kabi; bog'lashni faqat admin/server); id-guards 9-band — «xodim farzandi»ga
    ilovadan faqat mavjud kalit (o'zgarmagan eski qiymat tegilmaydi; 23503); login yorlig'i manba — faqat xodimga bog'langan
    hisobniki. README: 9-band g'alati raqamlari va reyestrdan xato raqamni olib tashlash buyrug'i (sinaldi: chegara 999999999 → 20,
    qayta deploy'dan keyin ham).
  - Kanonik ID `app.pid_key` (JavaScript trim() to'plami — NBSP/tab/BOM ham — + katta harf) hamma joyda: btrim bilan
    «IQX-004<NBSP>» alohida hisoblanib, baza o'zi ko'rinishi bir xil «IQX-004» ni berardi. predeploy 2-band ASCII bo'lmagan
    belgilarni ham ko'rsatadi; 3/9/10-bandlar kanonik.
  - UI takror tekshiruvlari (Oylik kartasi, maosh, avans, «Maosh xarajati») ham kanonik (`pidKey`): «IQX-002»/«iqx-002 » juftligi
    endi haqiqatan bloklanadi (avval karta «bloklangan» der, maosh esa o'tardi).
  - `lock table` DO ichida: zanjirsiz `psql -f run-all.sql` (autocommit) yarim yo'lda to'xtamaydi (rc=0).
  - Forma: javobi yo'qolgan INSERT'dan keyin Kamera ID tekshiruvi o'z qatorini (`_pidRow`) «boshqa odam» demaydi; 42501
    (boshqa admin shu orada tuzatgan) — «fix» rejimi asl ID'ga qaytadi, ikkinchi «Saqlash» boshqa maydonlarni saqlaydi; taklif
    hali kelmagan «Saqlash» rad etiladi; Oylik kartasi matni prefiks bo'yicha (IQX- juftligida tugma o'qituvchi kartasida).
  - Qayta sinov (UTF8 klaster): SQL T00–T30, C1–C6, verify-db BIR XIL (1900 / 2095 obyekt), brauzer 74 + 11 + 23 (tuzatmalar).
- **Ikkinchi raqib ko'rigi** (fa7cdd3 tuzatmalari ustidan; 6 topilma, 5 tasdiqlangan — hammasi tuzatildi):
  - «Xodim farzandi» ro'yxati eskirgan keshdan olinardi: boshqa sessiyada ID'si tuzatilgan/o'chirilgan o'qituvchi tanlansa,
    9-band trigger butun maxfiy blokni (JSHSHIR, telefon, 50% toifa) rad etar, forma esa «Saqlandi ✓» deb yopilardi. Endi
    ro'yxat doim bazadan; maxfiy blok yozilmasa oyna OCHIQ qoladi (bazaning izohi bilan), 23503'da ro'yxat yangilanadi; qayta
    «Saqlash» o'quvchini takror yaratmaydi.
  - 9-band trigger yozish huquqi yo'q rollarga (ota-ona, o'qituvchi, moliya) 23503/42501 farqi orqali ID borligini va yashirin
    bog'lanishni oshkor qilardi — endi faqat priv_ins/priv_upd egalari (direktor, qabulxona) tekshiriladi, qolganlarni RLS rad etadi.
  - Kanonik ID: ko'rinmas format belgilari (U+200B, bidi, soft hyphen …) HAMMA joydan olinadi; bo'shliq — JS trim() to'plamining
    aniq ro'yxati (locale'ga bog'liq \s emas); katta harf — faqat a–z (translate / replace). JS pidCanon va SQL app.pid_key
    4 448 252 satrda (har kod nuqtasi oldida/oxirida/ichida) AYNAN bir xil va idempotent. Avvalgi deploy reyestri yangi shaklga
    keltiriladi (sinaldi: CHECK keyin validatsiyadan o'tadi).
  - O'quvchi formasi: javobi yo'qolgan INSERT'dan keyin o'z Kamera ID'si qayta «Saqlash»ni to'sardi (eski muammo) — `_ins` ham «o'zimiz».
  - Saqlash ishlovchisi faqat O'Z formasiga tegadi (`e.target`): oyna yopilib boshqa karta ochilsa, kech 23505/42501 unga «fix» rejimini
    qo'ymaydi, kech «Saqlandi» uni yopmaydi; «Bekor»dan keyin kelgan eski taklif qo'llanmaydi (gen hisoblagichi).
  - Faqat bo'shliqdan iborat turli ID'lar endi bir-biriga «takroriy» hisoblanmaydi (pidKey xom qiymatga qaytadi).
  - Sinov: SQL T00–T32 + reyestr qayta-kanoniklash, C1–C6, verify-db BIR XIL, autocommit run-all rc=0, predeploy eski/yangi bazada
    xatosiz; brauzer 74 + 11 + 23 + 19; unit 192/186/✓.

## 42) Raqib (Schoolify) tahlilidan keyin: 3 ta tez xato + ochiq muammolar (2026-10-29)
Talab: «uchala xatoni tuzat va aniqlangan ochiq muammolarni to‘g‘rila … drektor sifatida kirib real holatda tekshir».
- **Tez xatolar:** bosma hujjatlardagi QR/manzil `iroacademy.uz` (mavjud bo'lmagan domen) → bitta manba `SITE_HOST/SITE_URL`
  = `iqroacademy.uz`; ota-ona profilidagi QR `/verify.html?id=`; eski QR havolalari (`/verify?id=` — prod'da 404) uchun
  `verify/index.html` yo'naltirish sahifasi (deploy.sh joylaydi, nginx o'zgarmaydi). Imtihon sahifasi va savollar muharririda
  «AI baholaydi» matni olib tashlandi — **qo'lda baholash** (daraja, 0–100 ball, tavsiya, izoh; kim/qachon). Eski AI natijasi
  `result.ai`'da «AI (eski)» deb alohida ko'rsatiladi. Payme filtri/yozuvlari olib tashlandi (Click + Uzum).
- **SMS (ota-onani bezovta qilmaslik):** tinch soat `sendHours` (standart Toshkent 9–20; worker va qo'lda «Eslatma»); bir telefonga
  kuniga bitta avtomatik SMS (bazadagi `sms_log`dan, qo'lda eslatma ham sanaladi). Qarz eslatmasi — har o'quvchiga BITTA SMS
  (barcha oylar + jami qarz, qo'lda «Eslatma» bilan bir xil matn), aka-uka eslatma kunlarida navbatma-navbat; qayta urinishda
  `createdAt` yangilanadi; `debt` cron'i tinch soatda ishlasa — ogohlantirish + kod 2. Qo'lda «Eslatma»: bugun shu raqamga SMS
  ketgan bo'lsa — ogohlantirish (bloklamaydi).
- **Kamera uzilishi (xodim davomati/maosh):** shu kuni ishlashi kerak bo'lganlarning (ruhsatdagilarsiz) 30% dan kami ko'rinsa —
  kun «kamera ishlamagan»: skani yo'qqa yo'qlama yozilmaydi, skanli kunda kech/erta/tanaffus avtomatik kesilmaydi; o'rinbosar
  yozilgan kelmagan — baribir yo'qlama. Oylik hisobot, maosh oynasi (`camera_days` RPC — kunlik Kamera ID ro'yxati), PDF va kunlik
  ko'rinish BIR XIL qoida. Tungi / 0 soatlik smena (bo'sh maydon standartga tushganda ham) — saqlashda ogohlantirish.
- **O'zgarishlar tarixi (`change_log`, faqat direktor):** 24 trigger — faktura, to'lov, avans (`student_credit`, `credit_ledger`), tavsiya bonusi,
  qaytarish, xarajat, narx, sozlamalar, maosh/avans/o'rinbosarlik/ruhsat, o'qituvchi/xodim, foydalanuvchi (rol, biriktirishlar,
  login telefon/email — qiymatsiz), ota-ona↔farzand bog'lanishi, «Bemor» kunlari. Maxfiy qiymatlar `***`. Deploy paytidagi tuzatishlar
  yozilmaydi (`set local iqror.migrating`, run-all.sql ham endi bitta tranzaksiya). Yozuv xatosi asosiy amalni to'xtatmaydi.
  Admin'da «O'zgarishlar tarixi» bo'limi: Toshkent sanasi/vaqti, bo'lim filtri, ism/rol/ID qidiruvi, 1000+ ogohlantirish.
- **Pul UX:** qarzdorlar — hammasi (12 tadan keyin «Barchasini ko'rsatish») + CSV (formula himoyasi, oy yili bilan); «Bank»
  xarajati tasdiqi; o'tgan oyni qayta hisoblash — alohida ogohlantirish. Tavsiya bonusi — bola haqiqatan o'qigan bo'lsa (oldingi
  oylar ham hisobga olinadi, bonus yo'qolmaydi). Yozda (iyul–avgust) sinf o'zgarsa — tugagan yil baholari eski sinfda qoladi.
- **Zaxira:** `full-deploy.sh` kunlik cron'ni o'zi o'rnatadi (DB_CONT/BACKUP_DIR bilan, izohli qatorni qayta yoqmaydi,
  `IQROR_NO_BACKUP_CRON=1`, cron xizmati va oxirgi log tekshiruvi); `backup.sh` — auth (token jadvallari ma'lumotisiz), storage
  papkasini konteynerdan topadi (topilmasa — ogohlantirish), bir vaqtda bitta nusxa (flock).
- **Ommaviy sayt:** haqiqiy saytda namuna (to'qima) ism/ball/narx/raqam birinchi chizishda ham ko'rsatilmaydi (`?demo=1` — dizayn);
  bo'sh bo'lim — «Tez orada qo'shiladi», raqam — «—». verify.html — «faqat ro'yxatda borligi» tasdiqlanadi. Taqdimotdagi eskirgan
  da'volar (Firebase, 3 provayder, AI baholash) to'g'rilandi. AI yordamchi: o'quvchi xulosasi — direktor/ota-ona, xavf — direktor/zavuch.
- **Raqib ko'rigi (5 tekshiruvchi + 2 tasdiqlovchi):** SQL, pul/davomat, UI, SMS, deploy — 39 topilma; ichida 3 ta regressiyam
  (qarz SMS'i aka-ukaga hech qachon bormasligi, tavsiya bonusi yo'qolishi, `fmtSum` — tarix sahifasi qotishi) — hammasi tuzatildi.
- **Sinov:** PG16 deploy yo'li (38f6554 → yangi ×2, xatosiz, change_log bo'sh) va noldan qurish — barmoq izi BIR XIL; SQL: audit 29,
  camera_days 10, yozgi qoida 8; brauzer (haqiqiy admin.html/index.html + PostgREST + RLS) 70 + 9; SMS worker (haqiqiy baza) 21;
  backup 8, cron 9, deploy sahifa nusxasi; npm: payments 52/25/58/192 (+attr/uzum/flow), auth 94/124/186; ESLint no-undef — yangi nom yo'q.
- **Deploydan keyin (foydalanuvchi):** 2 ta takroriy maosh ID — «Yangi noyob ID berish»; Eskiz kaliti + SMS cron (tasdiqdan keyin);
  `/var/log/iqror-backup.log` va storage zaxirasi («storage YO'Q» chiqsa — `STORAGE_VOL`); direktor kirishi — jonli tekshiruv uchun.

## 43) Jonli saytni real holatda tekshirish (2026-10-30): RLS tezligi, avtobus maxfiyligi, tez almashtirish xatosi
Vaqtinchalik sinov hisobi (email, avval «Ota-ona», keyin direktor bergan «Direktor» roli). Faqat o'qish: brauzer har qanday yozuv
so'rovini o'zi to'xtatadi; natijada faqat sonlar/holat kodlari — ism, telefon, ID chiqarilmadi.
- **Ochiqlik (anon + tasdiqlanmagan ota-ona, 62 jadval + 9 RPC):** maxfiy jadvallar yopiq (users — faqat o'z qatori, payroll_ids —
  ruxsat yo'q, change_log — anon'ga ruxsat yo'q / ota-onaga 0 qator, qolganlari 0 qator); RPC'lar anon'ga 401, ota-onaga 403 yoki bo'sh. Hammaga ochiq qatorlar faqat mo'ljallangan
  maydonlar: `config/ai` (manzil, holat, «kalit bor» belgisi — kalitning o'zi `secrets`da), `config/payments` (Click ID'lari),
  `settings/site`, `exam_questions` (savol matni, javob kaliti YO'Q).
- **Topilma 1 — `staff_checkins` 500 (57014, vaqt chegarasi):** kamera hodisalari jadvali (barcha o'quvchi+xodim) katta; policy'dagi
  `app.is_admin() or app.is_hr() or …` HAR QATOR uchun chaqiriladi -> mehmon/ota-ona so'rovi 3 s'da uziladi (istalgan odam bazani
  soniyalab band qila oladi), direktor sahifalari ham sekin. **Tuzatma `migration/rls-initplan.sql`** (zanjir oxirida): public'dagi
  barcha policy'larda argumentsiz rol yordamchilari `(SELECT app.f())` ga o'raladi (Supabase linter 0003) — so'rovga BIR MARTA.
  O'zini subso'rovda o'qiydigan jadval (users) avtomatik chetlanadi — aks holda 42P17 «infinite recursion» (sinov matritsasi
  ushladi: profilni saqlash buzilardi). PG16, 300 ming qator: anon 6,5 s -> 26 ms; HR oylik 537 -> 7 ms; direktor 186 -> 7 ms.
  Himoyalar (raqib ko'rigidan keyin): matndan ko'rinmaydigan halqa (security_invoker view, boshqa sxema) uchun o'ralgan har
  jadval `authenticated` nomidan EXPLAIN qilinadi — 42P17 bo'lsa asl policy qaytariladi (OGOHLANTIRISH); '...' satr ichidagi
  matn o'ralmaydi; boshqa rol egasi bo'lgan jadval tegilmaydi; jadval qulfi KUTILMAYDI (`lock … nowait`: zanjir jadvallari
  allaqachon qulflangan — bir zumda; qo'lda yaratilgan band jadval — o'tkazib yuboriladi, aks holda har policy 20 s kutib butun
  sayt to'xtab turardi); ALTER xatosi deployni to'xtatmaydi; `chain.sh` rls-initplan.sql zanjirda OXIRGI ekanini majburlaydi
  (undan keyin qo'shilgan fayl — xato, baza o'zgarmaydi).
- **Topilma 2 — avtobusning jonli joylashuvi har kirgan hisobga ochiq edi** (`bp_sel`: `app.uid() is not null`) — ro'yxatdan o'tish
  ochiq, ya'ni begona odam ham GPS/tezlik/haydovchi ismini ko'rardi (farzandsiz sinov hisobi bilan tasdiqlandi). **Tuzatma
  `migration/bus-access.sql`:** faqat xodim (`is_staff`) yoki FAOL bog'langan farzandi bor ota-ona (`app.has_active_child()` —
  claim_child kod bilan yozgan `child_claims`; bola ro'yxatda bo'lishi va «chiqdi» (ketish sanasi kelgan) bo'lmasligi shart —
  child_claims o'chirilmaydi, aks holda sobiq oila ham ko'rardi). Kabinet avtobusni avvaldan shunday ko'rsatardi — endi baza ham.
  Eski xato ham yopildi: bus_positions'da DELETE siyosati yo'q edi — yo'nalish o'chirilganda oxirgi joylashuv va haydovchi ismi
  qolib ketardi (RLS 0 qatorni jim «o'chirardi»); endi direktor o'chiradi (`bp_del`), avvalgi yetim qatorlar deployda tozalanadi.
- **Topilma 3 — tez bo'lim almashtirishda eski render xatosi** («Imtihonlar»: `Cannot set properties of null`): `openTab` endi
  eski (almashtirilgan) ko'rinish renderining xatosini jim o'tkazadi, joriy bo'lim xatosi avvalgidek konsolda.
- **Direktor paneli (37 bo'lim):** hammasi ochildi; ochilishda ilova hech narsa yozishga urinmadi; xato javob 0; konsol xatosi 0
  (3-topilmadan tashqari). Amaliy ish (To'lovlar bo'limi): 3 ta to'lov biriktirilmagan («o'quvchi topilmadi — qo'lda biriktiring»),
  4 ta hisob-fakturaning o'quvchisi ro'yxatda yo'q (o'chirilgan yoki ID o'zgargan); 2 ta takroriy xodim ID'si hali bor (4 kartochka —
  «Yangi noyob ID berish»). Eng sekin so'rovlar ~1,3 s (asosan tarmoq).
- **Sinov:** noldan qurish 76 fayl xatosiz; policy matni o'ram olib tashlansa HEAD bilan bayt-bayt bir xil (faqat bp_sel farq);
  deploy yo'li (HEAD -> yangi ×2) va noldan qurish — policy va verify-db barmoq izi BIR XIL, ikki marta o'ralish yo'q; RLS
  matritsasi 18 foydalanuvchi (anon, har rol, bloklangan direktor, faol/bekor/yo'q bog'lanishli ota-ona) × har jadval ×
  ko'rish/yangilash/o'chirish/qo'shish = 4446 tekshiruv — farq faqat bus_positions ko'rishda; SQL: audit 29, camera 10, yoz 8,
  maosh ID testlari (eski/yangi chiqish bir xil); brauzer: 70 + 9, pasport ID 74/11/23/19, tez almashtirish 3 (7ba8190'da xato
  chiqishi nazorati bilan); ESLint no-undef — yangi nom yo'q. Avtobus 11 holat; ko'rib chiquvchining qiyin policy shakllari
  (view/boshqa sxema/qo'shtirnoqli nom/ikki jadvalli halqa, RESTRICTIVE, satr ichida `app.is_admin()`) — hammasida UPDATE ishlaydi;
  superuser bo'lmagan deploy roli va qulf kutishi — deploy to'xtamaydi.
- **Raqib ko'rigi (3 tekshiruvchi: ma'no, xavfsizlik, deploy + tasdiqlovchilar):** xavfsizlik — 2 (ketgan/o'chirilgan bola oilasi
  avtobusni ko'rardi; yo'nalish o'chirilganda joylashuv qolardi) — tuzatildi; ma'no — 2 (matndan ko'rinmaydigan halqa; «oxirgi
  bo'lishi shart» majburlanmagan) — tuzatildi; deploy — 1 (zanjirdan tashqari band jadval policy'lari K×20 s qulf kutishi) —
  tuzatildi (band jadval bilan sinov: zanjir 0,4 s, 1 ogohlantirish; keyingi deployda o'raldi).
- **Deploydan keyin (a600573) jonli qayta tekshiruv:** jonli admin.html — yangi (c1c594c+) versiya; anon — 13 jadval 200/0 qator,
  0,27–0,36 s (asosan tarmoq), change_log — 401 (ruxsat yo'q, avvalgidek); kamera jadvali (yagona katta jadval, 75 111 qator) deploydan
  oldingi o'lchovda 3,3 s'da 500/57014 edi. Direktor — sanash so'rovlari (butun jadval / oktyabr 3 252) ~0,3 s, camera_days ishlaydi;
  admin sahifalari tarmoq tufayli sezilarli tezlashmadi. «0 qatorli» PATCH (id = mavjud bo'lmagan qiymat; statement trigger yo'q —
  hech narsa o'zgarmaydi) 14 jadvalda (users ham) — rejalashtirishda 42P17/42501 yo'q (haqiqiy saqlash jonli sinalmadi).
  change_log — oxirgi 2 soatda 17 yozuv, hammasi oddiy to'lov/faktura/avans amallari (deploy yozuvlari ataylab yozilmaydi, shuning
  uchun tarix ularni ko'rsatmaydi). Admin 37 bo'lim — yozuv urinishi, xato so'rov, konsol xatosi 0; «Imtihonlar» tez almashtirish
  (5 marta, 120 ms) — xato yo'q; verify.html eski QR havolasidan ochiladi, noma'lum ID rad etiladi. Avtobus: anon 0 / xodim 2 —
  bular deploydan oldin ham shunday edi; «kirgan, lekin xodim emas» holati jonli tekshirilmadi (bunday hisob kerak), PG16 sinovlari bor.
- **Yangi topilma — bazadagi NAMUNA yozuvlar** (kod tuzatmasi PUB_DEMO faqat koddagi namunalarni yashiradi; bazaga ko'chirilganlari
  haqiqiy ma'lumot bo'lib ko'rinadi — 1 s'da yo'q, 10 s'da «Aziza Karimova» va b. chiqadi): maktab yutuqlari 5/5, o'quvchilar
  yutuqlari 4/6, yangiliklar 4/7, tadbirlar 2/5, savol-javob 5/9, qabul bosqichlari 4/4, rejalar 0/3 (index.html namuna massivlari
  bilan matn bo'yicha solishtirildi). Direktor ko'rib chiqadi (hujjatda ro'yxat); bosh sahifa raqamlari (440/32/100%) — Sozlamalarda.
- **Mustaqil ko'rik (skeptik + to'liqlik) bo'yicha qo'shimcha jonli tekshiruv:** anon 62 jadval — 29-oktyabr asosi bilan BIR XIL
  (faqat kamera jadvali endi xato bermaydi); direktor GET 61×200 + payroll_ids 403 (ruxsat yo'q, avvalgidek); «0 qatorli»
  PATCH/DELETE/INSERT/UPSERT 56 jadvalda — 42P17 yo'q (nazorat: payroll_ids 403 — bo'sh INSERT ham bazaga yetib boradi; 4 ta
  butun-sonli ID jadvalda sinov tahlilda to'xtaydi — ular server yozadigan jadvallar); auth/pay/ai xizmatlari 200 (AI modeli
  claude-opus-4-8 — amaldagi model, adaptive thinking, sampling parametrlari yo'q); change_log maxfiy maydonlari yashirin
  (3/3); yetim avtobus joylashuvi 0; sms_log tinch soat va «kuniga bitta» buzilmagan. Avtobus qoidasi: 3 faol bog'lanishdan 2 tasi
  o'tadi, 1 tasi ro'yxatda yo'q o'quvchiga (u ota-ona kabinetda «topilmadi» ko'radi — kod qayta beriladi).
- **Deploy kamchiligi (tuzatildi): `taqdimot.html` va `prezentatsiya.html` deploy.sh ro'yxatida YO'Q edi** — saytda iyul
  versiyalari (a3009d3 / 3b30158) qolgan, 1bcabdd (eski Firebase havolalari) va 7ba8190 (taqdimotdagi eskirgan da'volar) chiqmagan.
  Endi deploy.sh ularni joylaydi; statik fayllar (vendor/ — KaTeX, SheetJS, QR; assets/, uploads/, manifest, ikonalar) ham —
  faqat o'zgargani yoziladi (hozircha 31/31 saytda repo bilan bir xil); full-deploy.sh tekshiruvi hammasini solishtiradi.
  Sinov: qum quti — 1-ishga tushirish 49 o'rnatish, 2 .bak; 2-ishga tushirish 0 statik qayta yozish; buzilgan fayl «!!» bilan ushlandi.

## 44) Direktor qarorlari va joriy etish yo'l xaritasi (2026-10-30)
Direktor hujjatdagi 9 savolga javob berdi (D1–D9: ikki kishilik tasdiqlar, Moliya → HR maosh, SMS sozlamalari,
Telegram, haqsiz ta'til, o'quvchi ma'lumoti yopiq, telefonni ko'rish mumkin — yuklab olish yo'q, hujjatda sog'liq yo'q,
yillik to'lov yo'q) va keng joriy etish rejasini so'radi. Javoblar hujjatning «Qaror» ustuniga yozildi; yangi
«Yo'l xaritasi» varag'i: kamchiliklar, 5 bosqich va darvozalar (vaqt chizig'i), indikatorlar, Telegram tasdiqlash,
ochiq savollar, «Bu hafta». Texnik ro'yxat: `JORIY-ETISH-REJA.md` (har ish, hajmi, `fayl:qator`).
- **Tahlil:** 6 yo'nalish (tasdiqlar, «Bemor»/hamshira, xabarnoma/Telegram, maxfiylik, xavflar, indikatorlar) —
  kod bo'yicha, `fayl:qator` bilan; Telegram faktlari core.telegram.org'dan tekshirildi (request_contact, Contact.user_id,
  deep link ≤64 belgi, ~30 xabar/s, Gateway $0.01/kod).
- **Jonli o'lchov (faqat sonlar):** 10 hisob, hammasi ma'muriyat (o'qituvchi/ota-ona 0); 30 kunda 346 to'lov;
  sentyabr ~77% yig'ilgan; oktyabr davomati 0; 2099-09 sinov qatorlari 14; maosh to'lovi 0.
- **Yangi topilmalar (maxfiylik):** anonim so'rov `students_public`dan 380 o'quvchi (ism, sinf, ball) oladi — D6 ga zid;
  eski Firebase (alilazer-cd582) jonli, `students` 46 / `teachers` 6 hujjat hammaga o'qiladi (faqat son sanaldi);
  GitHub repozitoriy OCHIQ va GitHub Pages eski saytni ko'rsatadi. Repodagi shaxsiy ma'lumot (ism + ID + qarz, ota-ona
  telefoni) 1858f40 da olib tashlandi/psevdonimlandi (testlar o'zgarishsiz o'tdi); git tarixida qoladi — private kerak.
- **Asosiy xulosa:** xavf odamlar va tartibda; pulga ta'sir qiluvchi qarorlarda ikkinchi tasdiq yo'q va bazada
  majburlanmaydi (moliya fakturani to'g'ridan-to'g'ri yozadi); bitta server, zaxira/tiklash sinalmagan, ogohlantirish yo'q.
- **Raqib ko'rigi (3 tekshiruvchi: ish tartibi, faktlar/xavfsizlik/qonun, indikatorlar + tasdiqlovchi):** 54 topilma
  (25 tasdiqlangan, 29 qisman, rad etilgani yo'q) va 33 ta tushib qolgan narsa. Asosiylari kiritildi: xodimlar uchun D6
  o'qituvchi hisoblaridan oldin (hozir har xodim, o'qituvchi hisobi ochilsa u ham, barcha o'quvchini ko'radi); D2
  noyabrdan qo'lda tartib; ulanmagan sinflarda monitoring chegirmasi tushib qolishi — O'IBDO' vaqtincha kiritadi;
  Telegram faqat o'quvchi kartasidagi raqam bilan va faqat shaxsiy chatda; 24 soat faqat 100 ball uchun; darvozalar
  o'lchanadigan; «Bu hafta» tartibi (deploy key → keyin private; Firebase Storage ham yopiladi, loyiha hozircha
  o'chirilmaydi); 3-bosqich 16-aprelgacha (bayramlar); eski «7 bosqich» bo'limiga «eskirdi» izohi.

## 45) Yo'l xaritasi paketlari (PKG-1 … PKG-12) — 2026-10-31 … 2026-11-01
Direktor qarorlari (D1–D9) bo'yicha 12 paket; har biri PG16'da noldan va deploy yo'lida (barmoq izi teng), RLS matritsasi,
SQL ssenariylari va haqiqiy sahifalar bilan brauzerda sinaldi; har paketdan keyin avvalgi paketlarning sinovlari qayta o'tdi.
| Paket | Commit | Asosiy |
|---|---|---|
| 1 — ommaviy saytni yopish (D6/D8/D9) | a0b129a, 36690a0 | `students_public` yo'q; hujjat tekshiruvida sog'liq yo'q |
| 12 — texnik ishlar | e5e486b … 069676f, 6594c26 | OTP xatosi aniq, maktab IP limiti, «🩺 Tizim holati», hisobni bloklash, zaxira 60 kun |
| 3 — ta'til turlari (D5) | 065d1fb | o'z arizasi — haqsiz; kasallik va mehnat ta'tili — haqli |
| 8 — qabul bo'limi | 1c0c063 | murojaat → qo'ng'iroq → sinov darsi → qabul/rad; ketish sababi; tiklash |
| 2 — xodimlar ruxsatlari (D6/D7) | e1b9bfc | o'qituvchi faqat o'z sinfini ko'radi; kassa/moliya — qisqa ro'yxat; eksport faqat Direktorda |
| 4 — «Bemor» kuni (D1) | 3814424 | hamshira ma'lumotnoma bilan kiritadi → Moliya menejeri tasdiqlaydi |
| 5 — 100 ball (D1) | b0840d2 | O'IBDO' 24 ish soati → Direktor 24 ish soati |
| 6 — chegirma/grant, tavsiya (D1) | 05424e7 | Direktor + Moliya menejeri; tavsiya — birinchi to'lovdan keyin |
| 7 — maosh (D2) | 3c7bba6 | Moliya menejeri tayyorlaydi → HR tasdiqlaydi → to'lanadi |
| 9 — xabarnomalar (D3) | 4e7e6f8 | SMS vaqti/matni sozlamada; SMS jurnali; sinf e'lonlari; ommaviy eslatma; `install-sms-cron.sh` |
| 11 — hisobot va qulayliklar | 5a8bc8b | ikkinchi lavozim (`extraRoles`, `app.role_set`), 🔍 qidiruv, reja va tushum, haftalik hisobot, oshxona menyusi |
| 10 — Telegram (D4) | 37ac6f8 | kartadagi raqam bilan tasdiqlash; avval Telegram, keyin SMS; to'lov va e'lon navbati; Direktorga kunlik hisobot |
- **Deploydan keyin bir marta:** `migration/deploy/README.md` → «Bu versiyadan keyin BIR MARTA» (o'tish oylari, SMS cron,
  Telegram, ixtiyoriy bo'limlar). `change_log` triggerlari — 39.
- **Ochiq qolganlar (atayin):** davomatning «10:00 gacha» ulushi (kiritish vaqti saqlanmaydi); oshxona menyusi ommaviy saytda
  (sayt yopiq); qisman to'lovlarning vaqti saqlanmaydi (kesimlar to'liq to'langan fakturalar bo'yicha); cheklovchi rol
  triggerlari qo'shimcha lavozimda kesishma sifatida ishlaydi; Moliya menejerida faktura yaratish tugmasi yo'q (yopiq
  ma'lumot faqat Direktorda); xodim oylik summasini o'zgartirish qulflanmagan (tasdiqlangan summa vedomostda saqlanadi).

## 46) Jonli audit tayyorgarligi: kod bo'yicha topilmalar va tuzatmalar — 2026-11-05 … 2026-11-06
Jonli auditdan oldin har jarayon (qabul, kabinet, davomat/«Bemor»/100 ball, billing, xodim/maosh, hisoblar/tozalash) kod bo'yicha
xaritalandi va ikki mustaqil ko'rikdan o'tdi. Topilgan xatolar (deploydan OLDIN tuzatildi):
- **100 ball qamrovi (pul):** 5–9-sinf chegirma fanlari ro'yxatida «IT» ham alohida fan edi (`informatika` + `it`), uni hech kim
  kirita olmaydi -> yangi qoidada to'liq qamrov hech qachon bo'lmas, 20% / 100% chegirma yo'qolardi. Endi `it` — «Informatika»ning
  taxallusi: `admin.html` `monCanon` (hisob-faktura yig'ish bloki) va bazada `app.mon_canon` / `app.mon_disc_slugs` /
  `app.monitoring_avg` bir xil (ikkalasi bo'lsa — «Informatika» yozuvi olinadi).
  Faqat YANGI qoida oylarida (eski qoida oylarining o'rtachasi avvalgidek — «IT» alohida, kalitsiz yozuv fan nomidan) va yangi qoidada
  kalitsiz (`{sid}__{oy}__{fan}` bo'lmagan) yozuvlar bazadagidek sanalmaydi.
- **Tavsiya bonusi (pul):** `app.first_real_payment` faqat `paid` holatli to'lovni olardi; naqd, bank, terminal, Click (`applied`) va
  Uzum (`confirmed`) to'lovlari hisoblanmasdi -> bonusni tasdiqlab bo'lmasdi. Endi `paid` / `applied` / `confirmed`; avans ko'chirmasi
  (`reattr`) va sof puli (`app.student_real_net`: to'lovlar − faktura qaytarishlari) 0 bo'lgan o'quvchi hisoblanmaydi. Birinchi to'lov
  bekor/qaytarilsa yoki faktura to'liq qaytarilsa (`trg_referral_refund_revoke`) — tasdiqlangan tavsiya bekor, qo'llangani —
  ogohlantirish. Kutilayotgan tavsiyalar hisoblagichi (Direktor kunlik hisoboti, muddati o'tgan tasdiqlar) doim 0 edi — tuzatildi.
  Deploydan keyin «Tavsiya bonuslari» navbatida eski (naqd to'lovli) tavsiyalar paydo bo'ladi — bu kutilgan.
- **«Reja va tushum» ogohlantirishi:** «Bemor» qoidasi `sickNoteRefs`ni massiv deb tekshirardi (aslida obyekt) -> har to'g'ri chegirma
  ham buzilish bo'lib chiqardi. Endi yozish paytidagi qo'riqchi bilan bir xil shartlar (kun ma'lumotnomada, kunlar soni, summa bor-kun yo'q).
- **Ikkinchi lavozim:** asosiy roli boshqa xodimga «O‘qituvchi»/«Kurator» qo'shimcha lavozimi berilsa, «Tahrirlash» oynasida sinf/fan
  bo'limi ko'rinmas va har saqlashda biriktirilgan sinflar o'chardi. Shu xil kamchilik yana 5 joyda tuzatildi (`uHas` — bazadagi
  `app.u_has` bilan bir xil): sinf nomi o'zgarganda biriktiruv ko'chishi, sinf rahbarini almashtirish (bitta sinf — bitta rahbar),
  «Sinf rahbari» ro'yxati, foydalanuvchilar jadvalidagi «Biriktirilgan», «📚 Sinflar» ogohlantirishi. Sinf rahbari bo'limlari va
  sinfga e'lon yozish (`app.ann_can_write`) — faqat `app.is_homeroom_for` ruxsat beradigan lavozimlarda.
- **Kabinet:** davomatda «Bemor» kuni o'z rangi va izohi bilan; faqat «Sababli»/«Bemor» kunlari bo'lgan oy ham ko'rinadi.
  Bir nechta farzandli ota-onaning tanlagan farzandi saqlanmasdi (o'z `users` qatoriga upsert — RLS insert tekshiruvi 403, xato
  jim yutilardi) — endi PATCH (`updateDoc`).
- **E'lon navbati:** o'chirilgan e'lonning yuborilmagan `ann__` yozuvi endi `skipped` (`trg_tg_unqueue_announce`) — aks holda
  «E'lonlar» yoqilgach adashib yozilib o'chirilgan e'lon ham ota-onalarga ketardi.
- **Mayda:** qaytarish tasdig'ida «so‘m so‘m»; chek QR kodi endi sahifadagi mahalliy kutubxonadan (avval CDN'dan — u yopiq bo'lsa
  chekda QR chiqmasdi).
- **Deploy to'xtadi (2026-11-06, a3e2dec): `permission denied to set parameter "iqror.inv_reprice"`** (`invoice-guards.sql`, baza
  o'zgarmadi). Sabab: `reprice_invoice`dagi funksiya darajasidagi `SET iqror.inv_reprice = '1'` bandi (PKG-6) — Supabase'da migratsiya
  roli `postgres` superuser emas, maxsus (placeholder) parametr uchun bunday bandga ruxsat yo'q; lokal sinovlar superuser bilan
  bo'lgani uchun ko'rinmagan. Tuzatma: `public.reprice_invoice` — o'ram (`set_config(..., true)` bilan bayroq qo'yadi, chiqishda va
  xatoda olib tashlaydi), ish — `app.reprice_invoice_core`. Endi zanjir superuser BO'LMAGAN rol bilan ham sinaladi (Supabase'ga
  yaqin muhit): eski zanjir aynan shu xatoni beradi, yangisi — 0 xato, c1c594c (server holati) ustidan deploy yo'li ham 0 xato.
- **Zaxira (backup.sh):** xizmatlar `/home/ubuntu/iqror-repo`dan ishlaydi — `config.json` fayllari va Supabase `.env` sirlar
  zaxirasiga tushmasdi («sirlar: topilmadi»). Endi yo'l berilmagan bo'lsa — xizmat unit'ining WorkingDirectory'si va supabase-db
  konteynerining docker compose papkasidan avto-aniqlanadi.
Sinov: `migration/test-audit-fixes.sql` (yangi, repoda) 36/36; `test-public-close.sql` 92/92; `test-auth-rls.sql` — d388324 bilan
aynan bir xil; deploy yo'li (d388324 ustiga) barmoq izi = noldan qurilgan; o'zgarganlar — faqat 8 funksiya + 4 yangi funksiya.
`admin.html`dan ajratilgan haqiqiy kod bilan birlik testlari 13/13; brauzerda (lokal PostgREST + haqiqiy sahifalar) 46/46 + ko'p
farzandli ota-ona tanlovi, avvalgi versiyada xuddi shu joylarda yiqiladi; `auth` va `payments` npm testlari yashil.
Jonli audit mashqi (lokal nusxada, haqiqiy sahifalar, haqiqiy kirish formasi bilan): Phase 0 11/11, o'quvchi jarayoni 42/42;
yozuvlarni «SINOV»dan boshqasiga o'tkazmaydigan himoyali brauzer skripti va faqat yozib olingan ID'lar bo'yicha ishlaydigan tozalash
SQL'i (scratchpad; repoga kirmaydi) raqib ko'rigidan o'tkazilmoqda.
Jonli sozlamalar (faqat o'qildi): GoTrue'da e-mail tasdig'i yoqilgan (`mailer_autoconfirm=false`) — e-mail bilan ro'yxatdan o'tgan
ota-ona havolasiz kira olmaydi; ilova ishlatmaydigan GoTrue telefon ro'yxati ochiq va avto-tasdiqli (`ENABLE_PHONE_SIGNUP=false`
tavsiya). Ochiq savollar: HR'da xodimlar «⬇ Eksport» (kodda ataylab), maosh to'lovini bekor qilish UI'si yo'q.

## 47) Jonli audit natijalari — production (2887f4d), «SINOV» hisoblari bilan — 2026-11-06 kechqurun
Tayyorgarlik: o'tish oylari (chegirma/grant, maosh, «Bemor» kuni, 100 ball) egasining qarori bilan **2026-12** ga qo'yildi
(«Narx jadvali» → «TASDIQ QOIDALARI», to'rtta alohida «Saqlash»; monitoring muddati standart 5-kun yozildi). Barcha qadamlar
himoyalangan brauzer skripti orqali (faqat SINOV obyektlariga yozish; SMS/xabar yo'q; haqiqiy qatorlar bloklanadi).
- **0-bosqich** 11/11 — deploy jonli, sozlamalar, SINOV yo'qligi, boshlang'ich ko'rsatkichlar, MOL «kutilmoqda» bilan kira olmasligi.
- **O'quvchi** 42/42 — murojaat → sinov darsi → rad/qayta ochish → qabul (`SINOV-A`) → kontrakt chegirmasi (Direktor + Moliya) →
  ota-ona kodi → davomat → hamshira ma'lumotnomasi → «Bemor» → 100 ball → O'IBDO' taklifi → Direktor tasdig'i → grant →
  2098-01 test fakturasi → naqd 1 000 → chek → PIN'siz qaytarish → rasmiy hujjat + QR → e'lonlar → muzlatish / chiqarish /
  o'chirish-tiklash. S1-11 va S1-31 faqat sekin yuklanish sabab — qayta tekshiruvda to'g'ri.
- **O'qituvchi** 8/8 — karta IQT-037 (≈2 daqiqa ommaviy ro'yxatda, keyin o'chirildi), hisobga bog'lash, sinf/fan, 14 jadval yopiq,
  salbiy yozuv 42501, baho, monitoring faqat o'qish.
- **Xodim** 16/16 — karta IQX-018, kamera ID, «O'z hisobidan» 60 daq, ruhsat (haqsiz) + kasallik (haqli), ushlanma 1 125 so'm
  (kutilgandek), ikkinchi lavozim HR (4 salbiy holat rad etildi), 2099-12 vedomost: Moliya → HR tasdig'i → Direktor tasdig'i →
  1 000 so'm berish (oshirib berish 23514) → qayta ochish → REST bilan bekor.
- **Rollar** 6/6 — 9 rol × 22 jadval matritsaga to'liq mos (ortiqcha kirish yo'q), ommaviy tugmalar faqat Direktorda, kassir /
  qabulxona / hamshira taqiqlari 42501, Moliya menejeri va ota-ona ustunlari, ikkinchi lavozim darhol yoqilib-o'chadi.
- **Brauzer tomonidagi tozalash** 3/3; lokal to'liq zanjir P0→P4 83/83, snapshot: SINOV bo'lmagan qatorlar — 0 o'zgarish;
  tozalash SQL v4 lokal oxirgi holatda: dry run → commit → «VERIFIED: 0».
- **Topilmalar:** (1) MUHIM — takroriy maosh ID (IQT-016, IQX-001) «📤 HR'ga yuborish»ni bloklaydi («Takroriy maosh ID bor») →
  2026-12 maoshidan oldin kartochkada «Yangi noyob ID berish» bilan tuzatish shart. (2) Kichik, TUZATILDI — «Xodimlar
  davomati»da oy/kun tez almashtirilsa sekin kelgan eski yuklash yangisining ustiga yozilardi (boshqa oyning vedomost kartasi
  ko'rinardi) → `saGen` hisoblagichi. (3) Kuzatuv: qaytarish PIN'i o'rnatilmagan; maosh berishni bekor qilish UI'si yo'q (F6);
  kassirga maosh ko'rish huquqi bo'lsa «O'qituvchilar/Xodimlar» ochiladi (ataylab); haqiqiy qoida buzilishlari 0.
- **Egasi uchun:** `migration/sinov-audit/` (README + v4 SQL + ID fayli) — dry run → tibbiy fayl (Storage API) → zaxira → commit.

## 48) Admin menyusi guruhlarga ajratildi (raqobatchi saytlar kabi) — 2026-11-07
Deploy (77afde0) tekshirildi: productiondagi `admin.html`, `index.html`, `sw.js`, `/sb` shimlar repo bilan bayt-bayt bir xil; Direktor
paneli 44 bo'lim bilan xatosiz ochiladi. Keyin chap menyu yig'iladigan guruhlarga bo'lindi (`admin.html` → `NAV_GROUPS`):
«Tasdiqlash» (doim yuqorida) · Boshqaruv · O'quvchilar · O'quv jarayoni · Xodimlar · Moliya · Xizmatlar · Veb-sayt · Tizim.
Guruh sarlavhasi bosilsa — ichidagi bo'limlar ochiladi (bir vaqtda bitta guruh), faol bo'lim guruhi doim ochiq, yopiq guruh
sarlavhasida ichidagi belgilar yig'indisi (masalan yangi arizalar), rolga bitta bo'lim qolgan guruh — guruhsiz. 8 tadan kam
bo'limli rollar (o'qituvchi, Moliya menejeri, kassir…) — avvalgidek tekis ro'yxat. Telefonda: bitta gorizontal qator, guruh
nomlari ko'rinadi, ochiq guruh bo'limlari yonida. Lokal brauzer sinovi (kompyuter + telefon, Direktor / Moliya / O'qituvchi)
5/5, 0-bosqich regressiyasi 11/11, sahifa xatosi yo'q.

## 49) Chorak ta'tili — o'qituvchi va xodimlarning oyligi kesilmaydi — 2026-11-07
Deploy (64d9fbd) tekshirildi: guruhlangan menyu productionda ishlaydi. Savol: «choraklar orasidagi dam olish kunlarida oylik
kesilmasin; bayram kunlarini belgilash yetarlimi?» — **Ha.** «Xodimlar davomati» → «🎉 Bayram / ta'til kunlari»ga kiritilgan
kun (`school_holidays`) hisobda shunday ishlaydi (avvaldan bor mantiq, o'zgarmadi): yo'qlama ushlanmaydi va «Ruhsatsiz»ga
sanalmaydi, kunlik stavka o'zgarmaydi (oydagi jami ish kunlari bayramni ham o'z ichiga oladi — haq to'lanadigan dam kuni),
o'quvchilar uchun ham dars kuni emas (kasallik kunlari, monitoring/bonus muddatlari). Yangi (`admin.html` → `openHolidays`):
- **«Dan — Gacha» oralig'i**: ta'tilni bir martada kiritish (oraliqdagi har kun, shanba-yakshanba ham — ba'zi xodimlar shanba
  ishlaydi); ko'pi bilan 120 kun; oraliq ichida oldin kiritilgan bayram nomi o'zgarmaydi; tasdiqlash oynasida nechta kun va
  nechtasi dushanba–juma ekani yoziladi. Nomlar ro'yxati (Kuzgi/Qishki/Bahorgi/Yozgi ta'til + rasmiy bayramlar).
- Ro'yxatda ketma-ket bir xil nomli kunlar **bitta qator** («2026-10-26 — 2026-11-01 (7 kun)»), «O'chir» butun guruhni o'chiradi.
- Vedomosti **tasdiqlangan oy** — tasdiqlashdan oldin aniq xabar, hech narsa yozilmaydi (bazadagi qulf avvalgidek himoya qiladi).
- Oylik hisobot sarlavhasi «🎉 bayram / ta'til: 26–31 Kuzgi ta'til», kunlik ko'rinishda «🏖 Ta'til» belgisi; tugma nomi
  «🎉 Bayram / ta'til kunlari».
Lokal brauzer sinovi 15/15 (soxta baza): 3 500 000 so'mlik xodim oktyabrda kelmagan — oraliq kiritilgach «Ruhsatsiz» 21 → 16,
ushlanma 3 340 911 → 2 545 456 (5 ta ta'til ish kuni to'liq to'landi), kelgan xodim oyligi o'zgarmadi; tasdiqlangan oy rad
etildi; guruhni o'chirish, telefon ko'rinishi, sahifa xatosi yo'q. **Eslatma:** ta'til kunlarini o'sha oy vedomosti
tasdiqlanishidan (va maosh berilishidan) OLDIN kiriting; kiritish huquqi — Direktor va HR.

## 50) Yangi dizayn yo'nalishi — videodan tahlil va maket — 2026-11-08
Egasi «Dashboard V22» videosini yuborib, «dizaynini ko'chirsak bo'ladimi?» deb so'radi. Tahlil: bu uchinchi tomonning
dizayn namoyishi (React/Tailwind), raqobatchi maktab sayti emas. 1:1 nusxa olinmaydi (logotip, 3D rasmlar, suratlar,
matnlar — boshqa birovning ijodi), lekin uslubi (yalpiz → iliq fon, to'q yashil panel/banner, yumaloq oq kartalar,
katta raqamlar, pill diagrammalar, hafta kalendari, yengil animatsiya) bizning yashil-oltin ranglarimizga juda mos.
Mustaqil maket yasaldi: `docs/dizayn/iqror-boshqaruv-maket.html` (Direktor bosh sahifasi, soxta ma'lumot). Ichida:
«Bugun e'tibor talab qiladi» bloki, 4 ta haqiqiy tasdiqlash navbati, davomat, o'rtacha ball, to'lovlar va reja, qarzdorlik,
moliya, to'lov tushumi (Haftalik/Oylik), xodimlar bugun, xavf ostidagi o'quvchilar, haftalik hisobot, sinflar bo'yicha
o'rinlar, ta'til/bayram belgili hafta kalendari. Kompyuterda ikonali yon panel (8 guruh, ochiladigan ro'yxat — 44 bo'lim),
telefonda pastki menyu va «Menyu» oynasi. Shrift tanlash (Roboto Condensed / Manrope). 7 ta agentli tahlil + 2 tomonlama
ko'rib chiqish (23 topilma tuzatildi); tekshiruv 54/54. Saytga hali tatbiq etilmagan — egasining qarori kutilmoqda
(`docs/dizayn/admin-inventar.en.md` §5: bosqichma-bosqich joriy etish, ~7–11 ish kuni).

## 51) Yangi dizayn (v2) joriy etildi: umumiy ko'rinish + Direktor bosh sahifasi — 2026-11-09
Egasi tasdiqladi: shrift va logotiplar o'zgarmaydi, ruxsatlar o'zgarmaydi, ish faqat dizayn; 1- va 3-bosqich.
- **Bayroq:** `<html data-ui="v2">` (standart). Eski ko'rinish: `?ui=v1` yoki «Profil» → «Ko'rinish» (qurilmada eslab
  qolinadi). Barcha yangi CSS `<style id="ui-v2">` da, har qoida `html[data-ui="v2"]` bilan — v1 piksel-piksel avvalgidek.
- **1-bosqich:** kanvas fon, to'q yashil menyu paneli (guruhlar/akkordeon o'zgarmagan), oq kartalar r20 + yumshoq soya,
  pill tugmalar (asosiy — iliq rang), maydonlar, modal, toast; jadval zichligi va PDF uslublari tegilmagan.
- **3-bosqich:** `renderDashboardV2()` — salomlashuv + bugungi holat, «Bugun e'tibor talab qiladi», davomat, ball, to'lovlar,
  qarz yoshi, moliya, 6 oylik oqim (Kirim/Chiqim/Sof foyda), xodimlar bugun, tasdiqlash navbatlari, bayram/ta'til belgili
  hafta kalendari, xavf ostidagilar, sinflar, foydalanuvchilar. Faqat o'qiydi; tugmalar faqat bo'lim ochadi. Klassik
  sahifa bilan umumiy hisob: `dashCoreStats()`, `dashFinData()` (ikkinchisida so'rovlar parallel, ishlatilmaydigan
  `refunds` o'qilmaydi). Kirishdagi takroriy render so'rovlari birlashtirildi (`dv2Once`).
- **Tekshiruv (lokal):** barcha rollar × barcha bo'limlar × 1440/390 — xato 0, siljish yo'q, bo'lim soni v1 bilan teng;
  v1 nazorat rasmlari bir xil; bosh sahifa 11/11 (14 raqam paritet); menyu 5/5; bayram/ta'til 15/15; kontrast ≥ 5,2:1.
  Batafsil: `docs/dizayn/v2-joriy-etish.md`.

## 52) v2 deploy tekshiruvi va haqiqiy ma'lumot bo'yicha tuzatishlar — 2026-11-09
Deploy (8792a8b) productionda bayt-bayt bir xil. «Faqat o'qish» sinovi (SINOV Direktor; yozuvlar bloklangan, rasm/shaxsiy
ma'lumot yig'ilmagan): 44 bo'lim × kompyuter/telefon — xato 0, siljish yo'q; «Tasdiqlash» ~7 s. Maket bilan farq: chap menyu
(ikonali panel — 2-bosqich, so'ralmagan), yuqori sarlavha (logo qoidasi), maketdagi namunaviy ma'lumotlar. Haqiqiy
ma'lumotda chalg'ituvchi raqamlar (4 % davomat, 0/100 ball, ismsiz salomlashuv, 100 % marja, shu oy fakturalari qarzga
qo'shilgani) — bosh sahifa mantiqi tuzatildi: davomat jurnaldan (bugun / shu oy), ball baholanganlar bo'yicha yoki «—»,
ism zaxirasi, xarajat yo'qligi belgisi, muddati o'tgan qarz alohida, «bugun tushdi», kalendarda «O'quv taqvimi» tadbirlari.
«Tasdiqlash» navbatlari parallel yuklanadi. Lokal: production sharoiti (baho/xarajat/ism yo'q, jurnal bor) bilan sinaldi;
bosh sahifa 11/11, barcha rollar × bo'limlar xato 0, menyu 5/5, bayram/ta'til 15/15, v1 o'zgarmagan.

## 53) v2, 2-bosqich: yangi menyu (kompyuterda ikonali panel, telefonda pastki menyu) — 2026-11-09
Deploy (47b31a8) productionda bayt-bayt bir xil; «faqat o'qish» sinovi: 44 bo'lim × kompyuter/telefon — xato 0,
«Tasdiqlash» endi tez, bosh sahifa raqamlari to'g'ri (davomat jurnaldan, ball «—», muddati o'tgan qarz alohida, marja «—»).
- **Kompyuter (≥821px):** 80px to'q yashil ikonali panel (fixed); guruh bosilsa yonida oq ro'yxat (flyout), Esc /
  tashqariga bosish bilan yopiladi; faol guruh — yalpiz «pill»; past ekranlar uchun ixcham rejim (≤700 / ≤540px).
- **Telefon (≤820px):** pastki menyu — «Asosiy» + 3 guruh + «Menyu»; pastdan ochiladigan oyna (guruh yoki «Barcha
  bo'limlar»), × / fon / Esc bilan yopiladi; toast va kontent menyu ostida qolmaydi. Guruhsiz rollar: ≤5 bo'lim — hammasi.
- **O'zgarmagan:** `#tabs` tuzilmasi, guruhlar, belgilar, ruxsatlar (har rolda bo'limlar soni v1 bilan teng), shrift,
  logotip; `?ui=v1` — eski guruhlangan menyu. Barcha yangi CSS `html[data-ui="v2"]` bilan (352 selektor tekshirildi).
- **Tekshiruv (lokal):** menyu 19/19, bosh sahifa 11/11, bayram/ta'til 15/15, v1 menyu 5/5; barcha rollar × bo'limlar ×
  1440/390 (Direktor — 1024 va 1280×560 ham) — xato 0, siljish yo'q; v1 nazorat rasmlari oldingi commit bilan bir xil sharoitda: 22/27 bir xil, 5 tasida
  faqat vaqt / sinov skripti farqi. Batafsil: `docs/dizayn/v2-joriy-etish.md` («2-bosqich»).

## 54) Moliya: kassa va buxgalteriyani 1C uslubida yuritish — ish rejasi — 2026-11-09
Egasining so'rovi: kassir kunlik kirim, chiqim, qoldiq, hujjat raqami, kun boshi/oxiri, «kimga / kimdan qancha»
hisobotini avtomatik bersin; har xarajat balans uchun statiyaga bo'linsin; dizayn ishlari to'xtatilsin (parkovka).
- **O'rganildi (8 ta tahlil):** kassir ish kitobi (17 varaq: kunlik kassa, kirim orderlari, bank, zavxoz, qarzdorlar),
  Financial Tracker (ikki nusxa mazmunan bir xil, ma'lumot 9-noyabrgacha), KO-1 va KO-4 fotosuratlari; tizimning
  to'lov/xarajat/maosh/qaytarish kodi va bazasi (RLS, RPC); BHMS 21 (2025) hisob rejasi, provodkalar, kassa va fiskal
  chek qonunchiligi, 1C:Бухгалтерия для Узбекистана imkoniyatlari.
- **Asosiy topilmalar:** kunlik kassa — kuniga bitta qo'lda yozilgan qator, hujjatlarga bog'lanmagan; zanjir qo'lda
  tuzatilgan; bankdan olish/bankka topshirish kirim-chiqim deb yozilgan; order raqamlarida takror va bo'shliqlar; zavxoz
  puli berilganda xarajat; komissiyalar yozilmagan; yopilgan oy tahrirlangan; tizimda kassa hujjati, raqamlash, kun yopish,
  statiya va bosh kitob yo'q; ayrim moliya huquqlari ortiqcha keng. Aniq qator va summalar — egasiga alohida yopiq ilova
  (repozitoriyda emas).
- **Reja:** `docs/moliya/buxgalteriya-ish-reja.md` — 0 (qarorlar, 9–28-noyabr) → 1a kassa MVP (rasmiy boshlanish
  2027-01-04, 31.12 sanash bilan) → 1b → 2 statiyalar → 3 bank → 4 bosh kitob (2027-01-01 dan) → 5 hisobotlar → 6
  muvofiqlik; 75 statiya, 64 provodka qoidasi, 46 qaror (FD), 6 darvoza (fiskal chek, hisob siyosati, maosh, qabul
  sinovi, buyruqlar, yil yakuni). Uch mustaqil ko'rik (buxgalteriya, kod, to'liqlik) — 59 topilma kiritildi.
- **Dizayn:** 2-bosqich (6446f57) push qilingan; keyingi dizayn ishlari (ota-ona kabineti) egasi so'raguncha to'xtatilgan.

## 55) Moliya, 0-bosqich (A relizi): server vaqti, atomar qo'lda to'lov, huquqlar I, yagona tushum — 2026-11-10
Egasi barcha qarorlarni ijrochiga topshirdi (reja §6 tavsiyalari qabul qilindi).
- **`migration/fin-prereq.sql`** (zanjirda `telegram.sql` dan keyin): `app.counts_as_receipt` / `app.pay_day` /
  `app.fin_receipts` — admin.html isCashPay/payDay bilan aynan bir xil; indekslar (payments createdAt/status/studentId,
  staff_advances month, expenses date); `app.fin_server_ts` triggeri — payments/expenses/salary_payments/staff_advances/
  refunds da createdAt (va payments.statusAt, expenses.updatedAt) serverdan, qaytarish va maoshda byUid/byEmail serverdan
  (tizim yozuvlari tegilmaydi); `record_manual_payment` — qo'lda to'lov bitta tranzaksiyada, idempotent; RF-01/02/05
  (kassir va O'IBDO' xarajat va avans yozmaydi), RF-07 (credit_ledger o'chirilmaydi).
- `add-credit.sql` — avansni ko'paytirish faqat Direktor/server (RF-03). `telegram.sql` director_daily — kassa kuni bo'yicha,
  `:s:` bolalari va `reattr` siz, yangi «late» (bugun kiritilgan, oldingi kun sanasi bilan); `auth/tg-daily.cjs` qatori.
- admin.html outbox — `record_manual_payment` (yangi funksiya bo'lmasa eski 3 bosqichli yo'l). `verify-db.sh` — trigger,
  cheklov, indeks ham solishtiriladi.
- **Sinov (lokal):** test-fin-prereq 69/69; test-fin-race 9/9 (8 parallel bir xil payId — bir marta); JS↔SQL moslik 605/605;
  test-audit-fixes 36/36; test-public-close 92/92; test-auth-rls bazaviy bilan bir xil; payments npm test 192/0; auth npm test
  yashil; brauzer (kassir): onlayn + oflayn navbat 11/11, eski yo'l ishlaydi; barcha rollar bo'limlari xatosiz; zanjir bo'sh va
  ma'lumotli bazada qayta-qayta ishlaydi; verify-db: yangi zanjirga «BIR XIL», eski bazaga barcha farqlar ko'rsatildi.
- **Prod (faqat o'qish):** vedomost tasdig'i 2026-12 dan yoqilgan; takroriy maosh ID 2 ta (tuzatish kerak); noyabr vedomosti
  tizimda yo'q; SINOV Direktor hisobi va «2099-12» sinov vedomosti hali turibdi (tozalash kerak).
- Hujjatlar: `docs/moliya/oraliq-qoidalar.md` (16-noyabrdan), `docs/moliya/buyruq-namunalari.md` (G5).
- **Mustaqil ko'rik (3 tekshiruvchi + har jiddiy topilmaga skeptik) va tuzatmalar:** NaN / Infinity / bema'ni katta summa
  barcha pul RPC'larida rad (record_manual_payment, apply_payment, apply_to_invoice, add_credit, reattribute_avans) — avval
  NaN barcha fakturalarni «to'langan» qilardi; **RF-04 oldinga surildi**: apply_payment / apply_to_invoice musbat summani faqat
  shu payId'li payments qatori, ichki RPC bayrog'i, Direktor yoki server bilan qabul qiladi (eski mijozlar qatorni avval
  yozgani uchun ishlayveradi); add_credit — kassir yo'q; student_credit'ga to'g'ridan-to'g'ri yozish — faqat Direktor; takror
  to'lov ogohlantirishi kompyuter soati orqada bo'lsa ham ishlaydi (raw.capturedAt); sana bo'sh bo'lsa — kiritilgan kun; server
  kassa kunini o'zgartirsa — kassirga ogohlantirish va chek shu kun bilan; qayta urinib bo'lmaydigan rad etish «navbatda» deb
  ko'rsatilmaydi; payDay yaroqsiz sanada bazadagidek; forPeriod 500 belgi; verify-db — repo'da yo'q UNIQUE indeks ham 🟠.
  Sinov: test-fin-prereq 87/87, moslik 608/608, poyga 9/9, brauzer 12/12 (takror ogohlantirishi bilan), qolgan to'plamlar yashil.

## 56) Moliya, 1a-bosqich poydevori (kassa yadrosi — faqat lokal sinov zanjirida) va sinov stendi — 2026-11-10

**Holat: jonli tizimga CHIQMAGAN.** Kassa fayllari `run-all.sql` da «--dev \ir» bilan yozilgan — `deploy.sh` / `verify-db.sh`
ularni izoh deb o'tkazib yuboradi; faqat `bash migration/chain.sh --dev` (lokal sinov, o'quv stendi `--dev`) qo'shadi. Tayyor
bo'lganda qator boshidagi «--dev » olib tashlanadi.

- **`chain.sh --dev`**, `rls-initplan.sql` (yangi rol yordamchilari ro'yxatda: `is_accountant`, `kassa_operator`, `fin_list2`,
  `kassa_reader`).
- **`fin-core.sql`** — ma'lumotnoma jadvallari (hisobvaraqlar rejasi, statiyalar, kassa operatsiyalari qoidalari, tashkilot
  sozlamalari T1 / L1 / limit / kassaGoLive, imzo ro'yxatlari, kontragentlar, kassalar, raqam hisoblagichi); RLS — faqat o'qish
  (kassa / moliya rollari), yozish — faqat RPC. **`fin-seed.sql`** — 92 hisobvaraq (BHMS 21), 75 statiya (IN 7, EX 44, OP 24),
  21 eski toifa mosligi, 20 operatsiya qoidasi (hammasi `ON CONFLICT DO NOTHING`).
- **`kassa.sql`** — `cash_docs`, `cash_doc_lines`, `cash_days`, `cash_counts`, `cash_day_events`, `payment_allocations`,
  `fin_snapshots`; bazadagi himoya (RPC'ni chetlab o'tib ham buzib bo'lmaydi): bitta ochiq kun; kun boshi = kecha oxiri; kun
  oxiri = boshi + kirim − chiqim; qoldiq manfiy emas; yopilgan kunga hujjat yozilmaydi; tekshirilgan kun o'zgarmaydi; hujjat
  o'chirilmaydi, mazmuni o'zgarmaydi; tasdiqsiz o'tkazish yo'q; hisoblagich faqat +1.
- **`kassa-docs.sql`** — `kassa_receipt` (KO-1), `kassa_payout_request` → `kassa_doc_approve` (2-ro'yxat ≠ so'rovchi; T1 dan
  katta, rahbarga berish, qarz — Direktor ham) → `kassa_doc_pay`; `kassa_doc_reject`, `kassa_doc_cancel`, `kassa_doc_void` (shu
  kunda, raqam saqlanadi). Raqam — o'tkazishning OXIRGI qadami, kassa eksklyuziv qulfi ostida: ROLLBACK raqam yemaydi.
  Idempotent (`clientRef`); fiskal chek № majburiy va takrorlanmaydi; statiya ruxsat ro'yxati; asos hujjatisiz ≤ L1.
- **`kassa-day.sql`** — `kassa_opening_set` (faqat Direktor, kassa ishga tushguncha), `kassa_day_close` (farq = sanalgan −
  hisobdagi − hali o'tkazilmagan → shu kun sanasi bilan tizim hujjati: kamomad KO-2 Dt 5910, ortiqcha KO-1 Kt 9390; KO-4
  varaqlari; sha256 izi), `kassa_handover`, `kassa_day_verify` (≠ yopuvchi / o'tkazuvchi; bo'shliq, jamlar, iz), `kassa_day_reopen`
  (faqat Direktor, oxirgi tekshirilmagan kun), `kassa_shortage_decide` (4730 / 9430), `kassa_state`, `kassa_day_book`,
  `kassa_checks`. Oflayn / kech kiritish: olingan kuni ochiq bo'lsa — o'sha kunga, yopilgan bo'lsa — joriy kunga «kech»
  belgisi bilan; 48 soatdan eskisini faqat Direktor kiritadi.
- **`kassa-pay.sql`** + **`fin-prereq.sql`** (`record_manual_payment`, yangi ixtiyoriy `p_extra`): kassa ishga tushgach
  (`fin_org.kassaGoLive`) naqd o'quv to'lovi SHU tranzaksiyada KO-1 bilan: Kt 4010 (boshlangan davr), Kt 6310 (kelgusi oy,
  ortiqcha), naqdsiz Dt 6310 Kt 4010 (qo'llangan eski avans). Order o'tmasa to'lov ham yozilmaydi. Kassa fayllari zanjirda
  bo'lmasa — avvalgidek (dinamik chaqiruv). Eski 9 parametrli chaqiruvlar mos.
- **Moliya soati** (`app.fin_now` / `app.fin_today`, `fin-prereq.sql`): jonli bazada DOIM `now()`; faqat nomi «fx_…»,
  «…sinov…», «…test…» bo'lgan bazalarda siljitiladi (jonli bazada jadvalga yozib bo'lmaydi).
- **Sinovlar:** `test-kassa.sql` 198/198, `test-kassa-pay.sql` 41/41, `test-kassa-race.sh` 22/22 (8 seans × 200 hujjat, 10 %
  ROLLBACK; ikki katta chiqimdan bittasi; parallel tasdiqlar; poyga paytida kun yopish), eski to'plamlar yashil
  (`test-fin-prereq` 87, `test-audit-fixes` 36, `test-public-close` 92, `test-auth-rls` — bazaviy natija bilan bir xil,
  payments `npm test` 192, JS↔SQL moslik 608). Oddiy zanjir ikki marta ketma-ket xatosiz; unda kassa jadvallari yo'q.
  Lokal sinov bazalari UTF8 da quriladi (jonli baza kabi).
- **Sinov stendi (F0.20) — `sinov/`:** `install.sh`, `update.sh`, `reset.sh`, `remove.sh`, `lib-preflight.sh`, `server.cjs`,
  `seed.cjs`, `README.md`. Yangi domen kerak emas (asosiy sayt manzili, boshqa port — standart 8443 = brauzer uchun boshqa
  manzil). O'rnatish chiqishida parollar ko'rsatilmaydi (faqat `sudo cat /opt/iqror-sinov/accounts.txt`). Soxta server
  muhitida (haqiqiy nginx / Postgres / PostgREST, soxta docker / systemctl / ufw) 107 stsenariy va brauzerda 39 tekshiruv
  o'tdi; HTTP darajasidagi 68 tekshiruvdan 67 tasi o'tdi (bittasi — sinov skriptining o'zidagi noto'g'ri kutilma: kassir
  `is_staff` tarkibida emas, stend xatosi emas). Haqiqiy serverda hali ishga tushirilmagan.
- **Qilinmagan:** kassa yadrosining mustaqil (boshqa agentlar bilan) ko'rigi — ishga tushirish rad etildi; o'rniga muallifning
  o'z qayta ko'rigi (3 tuzatma: band kalitlar, qarordan keyin qayta ochish, fiskal № indeksi).

## 57) Moliya, 1a-bosqich: «Kassa» bo'limi va chop etish shakllari (faqat lokal sinov zanjirida) — 2026-11-10

**Holat: jonli tizimga CHIQMAGAN** (kassa fayllari hamon «--dev \ir»). admin.html dagi o'zgarishlar xavfsiz: bo'lim va «To'lov»
shaklidagi yangi qoidalar faqat serverda `kassa_state` funksiyasi bo'lsa (va Direktor «ishga tushirish kuni»ni belgilagan
bo'lsa) yoqiladi; kassasiz serverda sahifa avvalgidek ishlaydi (brauzer sinovi 12/12).

- **`assets/js/fin-kassa.js`** (yangi, kerak bo'lganda `import()` bilan yuklanadi; yangi CSS yo'q — mavjud `.page-head`,
  `.acc-kpis`, `.card`, `.tablewrap`, `.btn`, `.chip`, `#modal`): kun kartasi (kun boshi, kirim, chiqim, qoldiq),
  ogohlantirishlar (kecha yopilmagan, tasdiq kutayotgan / to'lanadigan so'rovlar, tekshirilmagan kunlar, qarorsiz kamomad,
  limit), ochiq kun hujjatlari (chop etish, shu kunda bekor qilish), so'rovlar (tasdiqlash, rad etish, bekor qilish, pulni
  berish), «+ Kirim» / «+ Chiqim so'rovi» shakllari (operatsiya qoidasiga qarab tomon tanlash: o'quvchi, xodim, kontragent
  — joyida qo'shish, «boshqa»; statiya; ko'p qatorli xarajat; asos hujjatisiz xarid; fiskal chek №), sanab yopish
  (nominallar, navbatdagi yozuvlar, komissiya), smena topshirish, tekshirish, qayta ochish, kamomad qarori, boshlang'ich
  qoldiq, sozlamalar (rekvizitlar, til, T1, L1, limit, ishga tushirish kuni), kun varag'i oynasi (hujjatlar, sanashlar,
  jurnal), «✅ Tasdiqlash» bo'limida kassa navbati.
- **`assets/js/fin-print.js`** (yangi) — KO-1 + «ПАТТА», KO-2, KO-4 (kassa kitobi varag'i + «Kassir hisoboti», varaqda
  qatorlar soni qat'iy va kun bilan birga saqlanadi — qayta chop etish aynan bir xil), sanash / topshirish-qabul
  dalolatnomasi. O'zbek kirill (standart), rus, lotin. Belgilar: «НУСХА», «БЕКОР ҚИЛИНГАН», «АЛМАШТИРИЛДИ», «СИНОВ»,
  «ҚОРАЛАМА». Tizim tuzgan matnlar (o'quv to'lovi asosi, sanash farqi) chop etish tilida qayta tuziladi.
  `fin-print.test.mjs` — 11 sinov (matn suratlari).
- **Chop etish jurnali** (`kassa.sql`: `cash_prints`; `kassa-day.sql`: `kassa_print_mark`, `kassa_doc_get`): birinchi chop
  etish — asl nusxa, keyingilari — «НУСХА»; «avvalgisi qog'ozga chiqmadi» deb asl nusxa qayta chiqarilsa — nazorat
  ro'yxatida (`kassa_checks.reissues30`) ko'rinadi; qayta ochib yopilgan kun varag'i — yangi asl nusxa («АЛМАШТИРИЛДИ»).
- **admin.html:** `KASSA` holati (`kassaInit` — saqlangan holat, `kassaProbe` — serverdan), menyuda «Kassa» («Moliya»
  guruhi; Direktor, Moliya menejeri, G'aznachi, Kassir), `renderKassa`, `finCtx`; «💵 To'lov» shakli — kassa ishga
  tushgach: naqd faqat kassa rollarida, fiskal chek № majburiy (Direktorga — istisno belgisi), sana — kassa kuni, natijada
  KO-1 raqami va «🖨 Kirim orderi va patta», to'lovchiga termal chek yo'q; kassa hujjat qabul qilmayotgan bo'lsa (kecha
  yopilmagan va h.k.) to'lov navbatga ham qo'yilmaydi; server rad etgan navbat yozuvi sababi bilan ko'rsatiladi; kassa
  yozuvi eski (kassasiz) yo'lga hech qachon tushmaydi. Ichki xarajat varaqasida «Fiskal chek emas — ichki hujjat».
  Tuzatildi: «To'lovlar» sahifasining kech tugagan yuklanishi boshqa bo'lim ochilgach xato berardi.
- **Sinovlar:** `test-kassa.sql` 223/223, `test-kassa-pay.sql` 50/50, `test-kassa-race.sh` 22/22; brauzerda (lokal stend,
  sintetik ma'lumot) ikki stsenariy — 36 va 35 tekshiruv — eski va yangi dizaynda: boshlang'ich qoldiq → kirim → chiqim
  so'rovi → tasdiq → to'lash → naqd o'quv to'lovi → bekor qilish → yopish → tekshirish → qayta chop etish; T1 dan katta
  chiqim, rad etish, smena topshirish, navbatdagi to'lov, kamomad va Direktor qarori, ertasi kun, qayta ochish, komissiya
  bilan yopish; 390 px da gorizontal siljish yo'q.
- **Qilinmagan:** mustaqil (boshqa agentlar bilan) ko'rik; F1.5 (naqd maosh / avans KO-2 orqali), F1.6 (qaytarish), F1.15
  (kunlik hisobot, Telegram), F1.16–F1.19.

## 58) Moliya, 1a-bosqich: maosh, avans, qaytarish va xarajatni kassaga bog'lash (faqat lokal sinov zanjirida) — 2026-11-10

**Holat: jonli tizimga CHIQMAGAN** (`kassa-links.sql` ham «--dev \ir»). Jonli zanjirga tegadigan yagona o'zgarish —
`refund-rpc.sql` dagi ruxsat sharti (kassa funksiyasi ichidan chaqirilganda ham ishlaydi; kassa yo'q joyda ta'siri yo'q).

- **`migration/kassa-links.sql`** (yangi): ustunlar (`method`, `cashDocId` — maosh, avans, qaytarish, xarajat; xarajatda
  `articleId`, `counterpartyId`); `kassa_salary_pay` (naqd — kassir yoki Direktor, KO-2 Dt 6710 Kt 5010 bilan bitta
  tranzaksiyada; vedomost tasdig'i yoqilmagan oy — faqat Direktor, nazorat ro'yxatida ko'rinadi; karta — Moliya menejeri /
  Direktor, kassa hujjatisiz); `kassa_refund_request` (Direktor: tasdiq = so'rov; summa = qaytarish + tanlansa avans; Dt 4010 /
  6310); `app.kassa_link_paid` — pul berilganda shu tranzaksiyada: qaytarish (`refund_invoice`), avans (`staff_advances`),
  xarajat (`expenses` ga ko'chirish: statiya → eski toifa); `app.kassa_link_void` — bekor qilinganda bog'langan yozuvni olib
  tashlash; `app.kassa_cash_guard` — kassa ishga tushgach naqd (yoki usulsiz) yozuvni to'g'ridan-to'g'ri kiritib bo'lmaydi,
  bog'langan qator o'zgarmaydi; xarajatga statiya toifadan o'zi qo'yiladi.
- **`kassa-docs.sql`:** `kassa_doc_pay` bog'langan amallarni bajaradi (qulf tartibi L1 → L4 saqlangan), `kassa_doc_void`
  maosh / avans / xarajat orderini bog'langan yozuvi bilan bekor qiladi (qaytarish orderi bekor qilinmaydi),
  `kassa_payout_request` — tasdiqlangan oy uchun avans so'rovini rad etadi. **`fin-seed.sql`:** «Ish haqi avansi» endi
  «+ Chiqim so'rovi» shaklida; qaytarishda «boshqa» tomon (biriktirilmagan to'lov). **`kassa-day.sql`:** kechikkan qaytarish
  (`refundsLate`, `staleRefunds`), vedomostsiz naqd maosh (`salaryGateOff30`).
- **admin.html (faqat kassa ishga tushgach o'zgaradi):** «Maosh berish» — to'lov usuli (naqd / karta), naqdda KO-2 raqami va
  chop etish; «Xodim avansi» — faqat karta / bank (naqd — «Kassa»ga yo'llanma); «Xarajat» — naqdsiz usul + kontragent, naqd —
  «Kassa»ga yo'llanma, kassadan ko'chgan qatorlar «Kassa» belgisi bilan (tahrirsiz); «Qaytarish» — usul, naqdda oluvchi
  F.I.Sh. va ariza sanasi. **fin-kassa.js:** tasdiqlangan qaytarishni to'lash, maosh orderini bekor qilish, kechikkan
  qaytarish ogohlantirishi. **fin-print.js:** maosh va qaytarish orderi matnlari chop etish tilida.
- **Sinovlar:** `test-kassa-links.sql` 68/68; `test-kassa.sql` 223, `test-kassa-pay.sql` 50, `test-kassa-race.sh` 22,
  `test-fin-prereq.sql` 87 (jonli va sinov zanjirida); brauzer: `e2e-kassa3` 26 (v1 va v2), oldingi stsenariylar 36 + 35,
  eski oqimlar — kassa ishga tushmagan holatda 12 va kassasiz jonli zanjirda 10 + 12.
- **Qilinmagan:** o'zaro hisob (`nc_offset`); mustaqil (boshqa agentlar bilan) ko'rik.

## 59) Moliya, 1a-bosqich: kunlik hisobot, nazorat ro'yxati, Telegram kassa bloki (F1.15; faqat lokal sinov zanjirida) — 2026-11-10

**Holat: jonli tizimga CHIQMAGAN** (kassa fayllari «--dev \ir»). Jonli zanjirga tegadigan yagona o'zgarish — `telegram.sql`
dagi `director_daily`: kassa funksiyasi (`app.kassa_daily`) bazada BO'LSA uni dinamik chaqiradi; bo'lmasa (hozirgi jonli
holat) javob avvalgidek, `kassa` kalitisiz (jonli zanjirda `test-fin-prereq` 87, `test-audit-fixes` 36, `test-public-close` 92).

- **Kunlik hisobot — RP-02 («kimdan / kimga qancha»).** `kassa_day_book` javobi kengaydi: `byParty` (tomon KALITI bo'yicha —
  o'quvchi kodi, xodim, kontragent; «boshqa» — yozilgan nom bo'yicha, harf kattaligi va bo'shliq farqisiz; tizim hujjati
  alohida; nom — ma'lumotnomadan), `byArticle` (statiya nomi va «ichki o'tkazma» belgisi bilan), `transfers` (bankdan
  olingan / bankka topshirilgan — daromad ham, xarajat ham emas), `channels` (shu kunda barcha usullar bo'yicha tushum —
  ma'lumot uchun), `pending`, `limit`. KO-4 ham, hisobot ham shu bitta javobdan tuziladi — jamlari bir xil (qabul mezoni
  «RP-02 = KO-4»). `fin-print.js: reportHtml` — A4, bir necha varaqqa o'tadi (jadval sarlavhasi takrorlanadi), 10 bo'lim
  (bo'sh bo'limlar tushib qoladi), ochiq kunda «QORALAMA», sinov kassasida «SINOV»; naqd o'quv to'lovi mosligi qatori
  («to'lovlar jadvalida X — kirim orderlarida Y: mos / FARQ BOR»). Ichki hisobot — ilova tilida (lotin); chop etish tili
  rus bo'lsa — ruscha. Chop etish jurnaliga yozilmaydi (raqamli hujjat emas). «Kassa»da: ochiq kun kartasida va kun
  oynasida «🖨 Kunlik hisobot»; kun oynasida «Kimdan / kimga qancha» jadvali.
- **Nazorat ro'yxati — RP-06.** `kassa_checks` kengaydi: moslik (`app.kassa_reconcile`, `kassa-links.sql`: P1 naqd o'quv
  to'lovi = KO-1, P4 naqd xarajat = KO-2, P5 maosh / avans = KO-2, P8 naqd qaytarish = KO-2 — har ikki tomondan, kassa ishga
  tushgan kundan), chop etilmagan KO-4, oflayn yozuv bilan yopilgan kunlar, limit (hozir va 30 kunda necha marta oshgan),
  hisobdorlardagi pul (berilgan − naqd qaytarilgan, eng eski ochiq sana, ish kunlari, 3 ish kunidan oshsa — muddati
  o'tgan), rahbar / ta'sischiga berilgan pul (shu oy / oldingi oylar). `fin-kassa.js: controlRows` — 20 tekshiruv, daraja
  (muhim / diqqat / ma'lumot / joyida) va matn; karta «Kassa» sahifasida 2-ro'yxat va Direktorga ko'rinadi (kassirga yo'q).
- **Telegram — RP-05.** `app.kassa_daily(day)`: kun varag'i jamlari (kun boshi + kirim − chiqim = kun oxiri, hujjatlar soni,
  sanalgan, farq, bank o'tkazmalari) va nazorat qatori (moslik, yopilmagan o'tgan kun, bekor qilishlar, farq — doim;
  qarorsiz kamomad, tekshirilmagan kun, tasdiq kutayotgan / berilmagan so'rov, kechikkan qaytarish, raqam bo'shlig'i,
  fiskal cheksiz, limit — bor bo'lsa). `auth/tg-daily.cjs: kassaLines` — matn; `--dry` shu matnni ko'rsatadi.
- **Tuzatish (CT-20):** sinov kassasidagi xarajat / avans orderi «Buxgalteriya» (`expenses`) va avans jadvaliga yozilmaydi
  (ilgari yozilib qolar edi — jonli «Buxgalteriya»ni ifloslantirishi mumkin edi); bekor qilish ham bog'langan yozuvsiz.
- **Sinovlar:** `test-kassa-report.sql` 52/52 (yangi); `test-kassa.sql` 223, `test-kassa-pay.sql` 50, `test-kassa-links.sql`
  68, `test-fin-prereq.sql` 87 (ikkala zanjir), `test-kassa-race.sh` 22; `fin-print.test.mjs` 16, `fin-kassa.test.mjs` 3
  (yangi), `fin-words.test.mjs` 7, `tg-daily.test.cjs` 39; brauzer: `e2e-kassa4` 24 (v1 va v2; 1440 va 390 px), oldingi
  stsenariylar va eski oqimlar qayta o'tkazildi.
- **Qilinmagan:** o'zaro hisob (`nc_offset`); F1.11, F1.16–F1.19; mustaqil (boshqa agentlar bilan) ko'rik.

## 60) Moliya, 1a-bosqich: o'zaro hisob — ish haqidan farzandining o'quv to'lovi (faqat lokal sinov zanjirida) — 2026-11-10

**Holat: jonli tizimga CHIQMAGAN.** Jonli zanjir fayllariga tegilmadi.

- **`kassa_offset(p)`** (`kassa-links.sql`; faqat Direktor, kassa ishga tushgach, xodimning yozma arizasi sanasi majburiy):
  BITTA tranzaksiyada — maosh to'lovi (`salary_payments`, usul `offset`; tasdiqlangan vedomost chegarasi mavjud darvoza
  trigeri bilan), o'quv to'lovi (`payments`, provider `offset`) va uning balansga qo'llanishi (`apply_payment`), naqdsiz
  dalolatnoma (ACT, o'z raqam seriyasi «Д-»): Dt 6710 Kt 4010 (joriy / o'tgan oy fakturasi) yoki Kt 6310 (kelgusi oy,
  ortiqchasi — avans). Kassadan pul chiqmaydi va kirmaydi — kassa kitobida (KO-4) yo'q, kassa kuni ochilmaydi. Qulf tartibi
  saqlangan (hujjat kaliti → o'quvchi navbati → maosh → kassa → hisoblagich); qayta yuborish — takror (yangi yozuvsiz).
- **`kassa_offset_void(id, reason)`**: faqat Direktor, faqat rasmiylashtirilgan kunning o'zida, sabab bilan — o'quv to'lovi
  teskari qilinadi (fakturalar va avans avvalgi holatga; keyin o'quvchi bo'yicha boshqa pul harakati bo'lgan bo'lsa — rad),
  maosh to'lovi olib tashlanadi, dalolatnoma raqami saqlanib «bekor qilingan» bo'ladi, ota-onaga yuborilmagan xabarnoma
  to'xtatiladi. Keyingi kunlarda — «Qaytarish» va buxgalter tuzatishi.
- **Umumiy qoida:** taqsimot hisobi `kassa_tuition_post` dan `app.kassa_tuition_alloc` ga ajratildi — naqd o'quv to'lovi
  (KO-1) va o'zaro hisob bitta qoida bilan; `app.tuition_reverse_core` ikkala hujjat turini teskari qiladi.
- **Moslik:** `app.kassa_reconcile` → `p5.ofs` (dalolatnoma ↔ maosh to'lovi ↔ o'quv to'lovi uch tomondan); nazorat ro'yxatida
  ko'rinadi. **Hisobotlarda:** o'quv to'lovi «tushgan to'lovlar»da alohida usul («O'zaro hisob (ish haqidan)») bilan,
  maosh — maosh to'lovi sifatida; ikkalasi teng — sof pul oqimi 0.
- **Ekran:** «Maosh berish» oynasida (kassa ishga tushgach, Direktorga) uchinchi usul — «O'zaro hisob»: o'quvchi qidiruvi,
  ariza sanasi; summa oldindan to'ldirilmaydi (butun maosh adashib o'tkazilmasin), tasdiq oynasi; natijada «🖨 Dalolatnoma».
  «Kassa» sahifasida yangi karta — «Naqdsiz dalolatnomalar» (boshlang'ich qoldiq, kamomad qarori, o'zaro hisob; oxirgi 3 oy):
  chop etish va (Direktorga, shu kuni) «Bekor». **Chop etish:** o'zaro hisob dalolatnomasi — matn, xodim, o'quvchi, asos
  (oy va ariza sanasi) chop etish tilida, rahbar / bosh buxgalter / xodim imzosi; boshqa dalolatnomalarda «Берилсин»
  yorlig'i olib tashlandi (kamomad qarorida — «Жавобгар шахс»).
- **Sinovlar:** `test-kassa-links.sql` 91/91 (+23: ruxsatlar, taqsimot, takror, vedomost chegarasi, atomarlik, bekor qilish,
  ertasi kun, moslik); `test-kassa-pay.sql` 50 (taqsimot ajratilgandan keyin o'zgarishsiz), `test-kassa.sql` 223,
  `test-kassa-report.sql` 52, `test-fin-prereq.sql` 87; `fin-print.test.mjs` 18; brauzer: `e2e-kassa5` 22 (v1 va v2),
  qolgan stsenariylar qayta o'tkazildi.
- **Qilinmagan:** F1.11, F1.16–F1.19; mustaqil (boshqa agentlar bilan) ko'rik.

## 61) Moliya, 1a-bosqich: davr surati va yopilgan davr qulfi (F1.16), maosh berish huquqini toraytirish (F1.11) — 2026-11-10

**Holat: jonli tizimga CHIQMAGAN** (`run-all.sql` da `--dev \ir fin-period.sql`). Jonli zanjir fayllariga tegilmadi.

- **Davr surati** (`fin-period.sql`; jadval `fin_snapshots` — `kassa.sql` dagi, faqat qo'shiladi): `fin_snapshot_take(p)` —
  faqat Direktor; tanlangan kun oxiri holati: qarzi, kelgusi oyga oldindan to'lovi yoki avansi bor o'quvchilar (fakturalari
  bilan), o'quvchiga biriktirilmagan tushumlar, kassalar qoldig'i, hujjat hisoblagichlari, tasdiqlangan vedomostlar bo'yicha
  to'lanmagan ish haqi, Direktor tasdiqlagan — hali berilmagan qaytarishlar va jamlar. Mazmun SHA-256 xeshi bilan saqlanadi;
  `fin_snapshot_get` xeshni qayta hisoblab solishtiradi (`hashOk`). Turi sanadan: 31-dekabr — yillik, oy oxiri — oylik, boshqa
  kun — qo'lda. Bir kun uchun bir necha surat mumkin (versiya); kun o'tgandan keyin olingani «kechikkan» deb belgilanadi
  (keyingi kunlar harakati aralashgan bo'lishi mumkin). Bu surat keyin bosh kitobning boshlang'ich qoldig'i uchun asos (F4.4).
- **Davr qulfi**: `fin_period_lock(sana, sabab)` — faqat Direktor; shu sanagacha (shu kun ham) to'lov (yangi yozuvning kassa
  kuni), «Buxgalteriya» xarajati, maosh to'lovi va xodim avansi kiritilmaydi, o'zgartirilmaydi, o'chirilmaydi (42501,
  `fin:locked`); server (onlayn to'lov webhook'lari) mustasno. Bugungi va kelajakdagi kun yopilmaydi; orqaga surish yoki olib
  tashlash — faqat sabab bilan, o'zgarishlar tarixiga yoziladi. Kassa hujjatlari doim bugungi kunga yoziladi — ularga qulf
  kerak emas. Barcha pul jadvallari uchun oy qulfi — 2-bosqich (F2.8).
- **Ekran:** «Kassa» sahifasida «Davr» tugmasi (Direktor va 2-ro'yxat): suratlar ro'yxati, «Xeshni tekshirish», JSON yuklab
  olish; Direktorga — surat olish (xohlasa shu sanagacha yopish bilan) va qulf sanasini o'zgartirish. Qulf bo'lsa sahifada
  eslatma; «To'lov», «Maosh berish», «Xarajat», «Xodim avansi» shakllarida eng erta sana — qulfdan keyingi kun.
- **Yil oxiri tartibi (tavsiya):** 31-dekabr kechqurun kassa yopilgach surat olinadi (qulfsiz — o'sha kuni yopib bo'lmaydi);
  qulf keyingi ish kuni qo'yiladi.
- **F1.11:** kassa ishga tushgach `canPaySalary` — faqat kassa operatori (naqd) va Moliya menejeri (karta); HR menejer
  vedomostni tasdiqlaydi, pul bermaydi. Server tomoni avvaldan bor (naqd yozuv faqat kassa funksiyasi orqali).
- **Sinovlar:** `test-fin-period.sql` 27/27 (ruxsatlar, surat mazmuni va xeshi, versiya, kechikkan belgi, qulf — har jadval,
  server mustasnosi, orqaga surish sababi, o'zgarmaslik, RLS); qolganlari o'zgarishsiz yashil: `test-kassa.sql` 223,
  `test-kassa-pay.sql` 50, `test-kassa-links.sql` 91, `test-kassa-report.sql` 52, `test-fin-prereq.sql` 87,
  `test-audit-fixes.sql` 36, `test-public-close.sql` 92, `test-kassa-race.sh` 22; JS 28; brauzer: yangi `e2e-kassa6` 20 (v1 va
  v2) va qolgan barcha stsenariylar qayta o'tkazildi (16 ta ishga tushirish, hammasi yashil).
- **Qilinmagan:** F1.18–F1.19, jonli zanjirga o'tkazish; mustaqil (boshqa agentlar bilan) ko'rik.

## 62) Moliya, 1a-bosqich: o'rnatishdan keyingi tekshiruv, reliz belgisi (F1.18) va ishga tushirish to'plami (F1.19) — 2026-11-10

**Holat: jonli tizimga CHIQMAGAN.** Kassa fayllari hamon `--dev` zanjirida. Jonli zanjirda faqat skriptlar o'zgardi
(`migration/deploy/full-deploy.sh`, `sinov/lib-preflight.sh` — yangi, faqat o'qiydigan tekshiruv qadami); SQL zanjiri o'zgarmagan.

- **`migration/kassa-checks.sql`** — faqat o'qiydi (`default_transaction_read_only`), istalgan payt ishga tushiriladi; chiqishida ism,
  telefon va summalar yo'q (identifikator, sana, son, farq). Modul o'rnatilmagan bazada faqat 1-band ishlaydi. Bandlar:
  1 — `search_path` belgilanmagan SECURITY DEFINER funksiyalar (butun `app` / `public`); 2 — reliz belgisi; 3 — obyektlar soni;
  4 — moliya funksiyalarida `search_path`; 5 — ichki `app.*` funksiyalarni mijoz rollari chaqira olmasligi (RLS ishlatadigan uchtasidan
  tashqari); 6 — ochiq funksiyalar: anon — yo'q, authenticated — ha; 7 — jadvallar: RLS, yozish huquqi va siyosati yo'q; 8 — himoya
  triggerlari; 9 — noyoblik indekslari; 10 — overload yo'q; 11 — kunlar zanjiri va boshlang'ich qoldiq dalolatnomasi; 12 — kun jamlari
  hujjatlardan; 13 — kun xeshi; 14 — raqamlash; 15 — KO-4 varaqlari; 16 — hujjat qatorlari; 17 — hujjat ↔ kun; 18 — o'quv to'lovi
  taqsimoti; 19 — bog'lanishlar (yo'q hujjat, sinov kassasi); 20 — moslik P1 / P4 / P5 / P8 (ishga tushgan kundan); 21 — surat xeshlari;
  22 — sozlamalar ziddiyati; 23 — holat (ma'lumot). Yakuniy qator: «✅ … muammo topilmadi» yoki «!! … N ta muammo qatori».
- **Reliz belgisi:** `migration/fin-version.sql` → `app.kassa_version()` (hozir 1); `kassa_state` javobida `version`. Sahifa
  (`fin-kassa.js`: `SERVER_VER`) farqni ko'rsa ogohlantiradi: server yangiroq — «sahifani yangilang», server eskiroq — «administratorga
  xabar bering». Server shartnomasi o'zgarganda uchalasi (SQL, JS, `kassa-checks.sql`) birga oshiriladi.
- **Ulanish:** `full-deploy.sh` «Keyingi tekshiruvlar»da (modul yo'q — bitta qator; modulda muammo — to'liq chiqish va «!!», chiqish
  kodi 2); sinov stendining yakuniy tekshiruvida; `migration/deploy/README.md` da izoh va qo'lda ishga tushirish buyrug'i.
- **Sozlamalar:** «⚙ Sozlamalar»da imzo egalari (1-ro'yxat — rahbar, 2-ro'yxat — bosh buxgalter / moliya; lavozim, to'liq F.I.Sh.,
  ixtiyoriy — tizimdagi hisobi; qo'shish va ro'yxatdan olish darhol saqlanadi) va tashkilotning ruscha nomi. Ilgari imzo egalarini
  kiritadigan ekran yo'q edi (funksiya bor edi) — yo'riqnoma yozishda aniqlandi. `kassa_refs` → `signers` (faqat Direktorga).
- **Ishga tushirish to'plami (hujjatlar):** `docs/moliya/ishga-tushirish.md`, `docs/moliya/yoriqnomalar.md`, `docs/moliya/shakllar.md`.
- **Qaror (jonli zanjirga o'tkazish):** hozir o'tkazilmadi — rejadagi yashirin o'rnatish kuni (≈ 21-dekabr), qabul sinovi va
  buxgalter ko'rigidan keyin, bir martalik commit bilan (`--dev ` belgilari olinadi). Bayroq bilan qisman o'tkazish rad etildi:
  zanjir har deployda `app.*` funksiyalariga EXECUTE ni qayta beradi, kassa fayllari qaytarib oladi — kassa fayllarisiz deploy
  ichki funksiyalarni ochiq qoldirardi.
- **Sinovlar:** yangi `test-kassa-checks.sql` 32/32 (bo'sh modul va uch kunlik haqiqiy ssenariy — toza; 23 xil ataylab buzilish —
  har biri aynan o'z bandida; qaytarilgach — toza; modulsiz baza). Tekshiruv fayli olti brauzer ssenariysidan keyingi bazalarda va
  parallel sinov bazasida (1 500 ga yaqin hujjat) ham toza. `test-kassa.sql` 225 (+2), qolgan SQL to'plamlari, `test-kassa-race.sh` 22,
  JS 28, `tg-daily` 39 — yashil; jonli zanjirda `test-fin-prereq` 87, `test-audit-fixes` 36, `test-public-close` 92. Brauzer: 16 ta
  ishga tushirish, hammasi yashil (`e2e-kassa6` 30: reliz ogohlantirishi, imzo egalari, telefon).
- **Yakka ko'rik (mustaqil ko'rik o'rniga) va tuzatishlar:**
  - *Davr qulfi ↔ kassa kunlari:* davr endi faqat shu sanagacha bo'lgan kassa kunlari yopilgan bo'lsa yopiladi
    (`app.fin_lock_ready`, `fin:open_day` — qulf ham, qulfli surat ham; sinov kassasi hisobga olinmaydi); yopilgan davrdagi kassa
    kuni qayta ochilmaydi; birinchi kassa kuni yopilgan davrga qo'yilmaydi. Ilgari ochiq kun turganda davrni yopish mumkin edi —
    kun keyin yopilganda farq hujjati yopilgan davrga yozilardi. `test-fin-period.sql` 32 (+5).
  - *Ruxsat tartibi:* `kassa_salary_pay` avval ruxsatni, keyin ma'lumotni tekshiradi (ilgari begona rol «kassa ishga
    tushirilmagan» javobini olardi). Yangi doimiy sinov (`test-kassa.sql` H9, 225): har bir ochiq moliya funksiyasi bo'sh ma'lumot
    bilan chaqirilganda begona rol va bloklangan hisobga (roli moliya menejeri + kassir bo'lsa ham) faqat 42501 qaytaradi.
  - *Ishga tushirish sanasi:* `fin_org_set` — «Kassa ishga tushadigan kun» bugungi yoki o'tgan kunga qo'yilganda shu kundan beri
    kassa orderisiz naqd yozuv (o'quv to'lovi, xarajat, maosh, avans, qaytarish) bo'lsa rad etadi (`kassa:live_gap`) — aks holda
    ular moslik tekshiruvida abadiy «ordersiz naqd harakat» bo'lib qolardi. `test-kassa-pay.sql` 51 (+1), `test-kassa-links.sql`
    92 (+1); bu ikki to'plamda kassa endi ordersiz naqd yozuvdan keyingi kuni ishga tushiriladi.
  - *Sinov stendi:* `sinov/update.sh --dry-run` (va o'rnatilgan stendda `install.sh --dry-run`) ba'zan soxta «❌ O'rinbosar sxemalar
    tekshiruvi xato» bilan to'xtardi — quruq rejimda o'qilmaydigan quvurga yozuvchi SIGPIPE olardi (`pipefail`). Tuzatildi
    (`lib-preflight.sh`). Stend lokal soxta server muhitida joriy versiya bilan sinaldi: o'rnatish va yangilash (`--dev`) — yakuniy
    tekshiruvda «Kassa tekshiruvi: muammo topilmadi (modul relizi 1)»; ssenariylar to'plami 105/107 (ikkitasi — sinov muhitining
    eskirgan sharti, skriptga bog'liq emas).
  - *Tekshirildi, o'zgarish talab qilmadi:* so'rovga soxta maydon qo'shish (holat, raqam, sana, tasdiqlar, «tizim hujjati»),
    qatorda mijoz bergan hisobvaraqlar, manfiy qator, juda uzun matn, kalit (`clientRef`) shakli, sanash summasi va nominallar,
    yo'q kassa — hammasi serverda rad etiladi yoki e'tiborga olinmaydi; dinamik SQL faqat migratsiya DDL'ida; sahifada foydalanuvchi
    matni hamma joyda ekranlanadi.
- **Qilinmagan:** jonli zanjirga o'tkazish; mustaqil (boshqa agentlar bilan) ko'rik; F1.20 — 1b-bosqich.

## 63) Moliya, 1a-bosqich: «Buxgalter» roli (minimal qism, F1.21 dan oldinga tortildi) — 2026-11-10

**Holat: jonli tizimga CHIQMAGAN** (rol faqat kassa moduli o'rnatilgan tizimda beriladi va ishlaydi). SQL zanjiri o'zgarmadi —
`app.is_accountant()`, `app.fin_list2()`, `app.kassa_reader()` avvaldan bor (`fin-core.sql`).

- **Sabab:** buxgalter — maktab xodimi; dekabrdagi qabul sinovida va ishga tushgach 2-ro'yxat vazifasini (so'rovni tasdiqlash, kunni
  tekshirish) o'z hisobi bilan bajarishi kerak. Server tomoni tayyor edi, sahifada rol umuman yo'q edi.
- **Sahifa (`admin.html`):** rol nomi «Buxgalter»; bo'limlari — «Tasdiqlash» (kassa so'rovlari navbati) va «Kassa»; pul amallari
  (kirim, chiqim so'rovi, pul berish, kunni yopish, sozlamalar) yo'q — server ham rad etadi. «Foydalanuvchilar»da rol tanlovda faqat
  kassa moduli o'rnatilgan bo'lsa ko'rinadi. Bo'limsiz qolgan rol uchun bo'sh holat: kassa holati kelguncha «Bo'limlar yuklanmoqda…»,
  modul yo'q tizimda — «rol uchun bo'limlar hali yoqilmagan» (xatosiz). D6 saqlanadi: buxgalter `is_staff` / `is_finance` ga
  kirmaydi, o'quvchi va xodim ma'lumotini ko'rmaydi. To'lovlar, xarajatlar, vedomost va eksportni o'qish — 1b (F1.21 ning qolgani).
- **Kichik tuzatish:** yopilgan kun tekshirilgan bo'lsa, «Kassa» sahifasidagi eslatma endi «tekshirilgan kun qayta ochilmaydi» deydi
  (ilgari «Direktor qayta ochishi kerak» deb chalg'itardi).
- **Sinov stendi:** `sinov/seed.cjs` — 10-hisob «Buxgalter» (kassa bo'limi bilan o'rnatilgan stendda ishlaydi).
- **Hujjatlar:** `yoriqnomalar.md` (buxgalter roli, kim nimani kiritadi), `shakllar.md`, `ishga-tushirish.md`, ish reja.
- **Sinovlar:** yangi brauzer ssenariysi `e2e-kassa7` 17 (v1 va v2: bo'limlar, navbat, tasdiqlash, kunni tekshirish, «Davr» faqat
  ko'rish, server rad etishlari, foydalanuvchi tahriri, telefon); eski oqimlar ssenariysida buxgalter — kassa moduli yo'q zanjirda
  bo'limsiz va xatosiz (11), modul bor — «Kassa» bilan (13). Server qoidalari `test-kassa.sql` da avvaldan (tasdiqlaydi, tekshiradi;
  kirim va so'rov yoza olmaydi).

## 64) Moliya, 1a-bosqich: kassa modulining yakka chuqur ko'rigi — topilmalar va tuzatishlar — 2026-11-11

**Holat: jonli tizimga CHIQMAGAN.** O'zgarishlar faqat `--dev` zanjiridagi kassa fayllarida (`fin-period.sql`, `kassa.sql`,
`kassa-day.sql`, `kassa-pay.sql`, `kassa-links.sql`, `kassa-checks.sql`) va `fin-kassa.js` da; jonli zanjir fayllariga tegilmadi.

- **Usul:** mustaqil ko'p agentli ko'rik ishga tushirilmadi (ruxsat berilmadi) — o'rniga modul yakka, «buzishga urinish» nuqtai
  nazaridan qayta ko'rildi. Har topilma avval sinov bazasida takrorlanib tasdiqlandi, keyin tuzatildi va doimiy testga aylandi.
- **Tasdiqlangan topilmalar va tuzatishlar:**
  1. *Yopilgan davrni mavjud to'lovni tahrirlash orqali chetlab o'tish* (`fin-period.sql`). Qulf faqat yangi to'lovni tekshirardi:
     mavjud to'lovning kuni (`raw.manual` / `raw.date`), summasi yoki kanali o'zgartirilsa, yopilgan oy tushumi orqaga o'zgarardi
     yoki yozuv yopilgan davrga «ko'chib» kelardi. Endi bunday o'zgarishda eski ham, yangi kun ham tekshiriladi; yozuvni bekor
     qilish yoki bekorini qaytarish ham yopilgan davrda rad etiladi (biriktirish, bo'lish, qaytarish — bugungi amal, avvalgidek).
     Sahifaning `setDoc`i — upsert: mavjud to'lovga oddiy belgi qo'yilganda («qo'lda tuzatildi») ham soxta «yopilgan davr» xatosi
     chiqardi (taklif qilingan INSERT qatorida kun hozirgi paytdan hisoblanardi). Endi mavjud qator uchun INSERT qatori
     tekshirilmaydi — o'zgarishni UPDATE tarmog'i tekshiradi. `test-fin-period.sql` L1e–L1g.
  2. *Kassa hujjatiga bog'langan to'lovni to'g'ridan-to'g'ri o'zgartirish* (`kassa-links.sql`, yangi `trg_kassa_pay_guard`).
     Naqd o'quv to'lovi (KO-1) yoki o'zaro hisob dalolatnomasiga bog'langan to'lov qatorining summasi, kanali, o'quvchisi,
     holati, kuni, havolasi va fiskal chek № ini moliya roli jadvalga to'g'ridan-to'g'ri yozib o'zgartira yoki bekor qila olardi
     (order o'zgarmay qolardi, moslik buzilardi). Endi bular faqat kassa funksiyalari yoki server orqali; bekor qilish — «Kassa»da
     hujjat orqali. Havolani ham faqat kassa qo'yadi. Izoh kabi boshqa maydonlar — avvalgidek; deploy paytidagi o'quvchi kalitini
     kanonlash (`invoice-guards.sql`) — mustasno. `test-kassa-pay.sql` LK1–LK3.
  3. *Bayroq tartibi* (`kassa-pay.sql`): `kassa_tuition_post` to'lov qatoriga order havolasi va fiskal № ni kassa bayrog'i
     o'chirilgandan keyin yozardi — yangi himoya bilan rad bo'lardi. Endi bayroq ichida.
  4. *Xodim ID sini qayta berish kassa yozuvida to'xtardi* (`kassa-links.sql`): «Yangi noyob ID berish» (`rekey_payroll_id`)
     KO-2 ga bog'langan maosh va avans qatorlarida xodim kalitini almashtira olmasdi. Endi faqat shu ustun o'zgarsa — ruxsat.
     `test-kassa-links.sql` S9c.
  5. *FD-28 (shaxsiy ma'lumot):* davr surati mazmunida o'quvchi va xodim ismlari bor — 2-ro'yxat (moliya menejeri, buxgalter)
     ularni funksiya orqali ham, jadvaldan to'g'ridan-to'g'ri ham ko'rardi. Endi jadvalni faqat Direktor o'qiydi; `fin_snapshot_get`
     2-ro'yxatga ismsiz (ID bilan) nusxa beradi (`masked`), xesh tekshiruvi to'liq mazmun bo'yicha. Sahifada fayl nomi
     «…-ismsiz.json» va eslatma. `test-fin-period.sql` S2, S2a, G3.
  6. *Biriktirilmagan to'lovni qaytarish hisobvarag'i* (`kassa-links.sql`): KO-2 qatori 6310 (olingan avanslar) dan yozilardi,
     aniqlanmagan tushum esa 6390 da turadi. Endi Dt 6390 Kt 5010, statiya OP-16. `test-kassa-links.sql` R6b.
  7. *Poyga* (`kassa-day.sql`): kunni qayta ochish yoki boshlang'ich qoldiqni kiritish davr yopilishi bilan bir paytda bo'lsa, qulf
     tekshiruvi eski qiymatni ko'rishi mumkin edi. Endi ikkalasi sozlama qatorini (`fin_org`) FOR SHARE bilan qulflaydi — davr
     yopilayotgan bo'lsa, u tugaguncha kutib, yangi qulf bilan tekshiradi.
- **Tekshirildi, o'zgarish talab qilmadi:** barcha ochiq kassa va moliya funksiyalari begona rollar (o'qituvchi, ota-ona, HR,
  o'quv bo'limi, bloklangan hisob) uchun faqat 42501 qaytaradi; so'rovga soxta maydonlar, mijoz bergan hisobvaraqlar, manfiy
  qator, kalit shakli, sanash summasi; sahifadagi foydalanuvchi matni (`fin-kassa.js`, `fin-print.js`, admin oynalari) hamma joyda
  ekranlanadi; to'ldirilgan bazada (≈ 1 500 hujjat) zanjirni qayta ishga tushirish; kunni qayta ochish + yil oxiri + qulf
  aralash ssenariysi — tekshiruv fayli toza. To'lovni o'zgartiradigan barcha server funksiyalari yangi himoya bilan solishtirildi
  (kassa funksiyalari — bayroq ostida; qolganlari bog'langan qatorga tegmaydi yoki rad etilishi to'g'ri).
- **`kassa-checks.sql`:** kutilgan obyektlar soni yangilandi (ichki funksiyalar 61, triggerlar 24; 8-band — `trg_kassa_pay_guard`).
- **Sinovlar:** `test-kassa.sql` 225, `test-kassa-pay.sql` 54 (+3), `test-kassa-links.sql` 93 (+1), `test-kassa-report.sql` 52,
  `test-fin-period.sql` 36 (+4), `test-kassa-checks.sql` 32, `test-fin-prereq.sql` 87, `test-audit-fixes.sql` 36,
  `test-public-close.sql` 92, `test-kassa-race.sh` 22 (keyin tekshiruv fayli toza), to'ldirilgan bazada zanjirni qayta
  ishga tushirish — OK; jonli zanjirda 87 / 36 / 92; JS 28. Brauzer: 18 ta ishga tushirish, hammasi yashil (449 tekshiruv;
  `e2e-kassa6` 31 — moliya menejeri yuklagan JSON ismsiz).
- **Qilinmagan:** mustaqil (ko'p agentli) ko'rik — ishga tushirishga ruxsat berilmadi; jonli zanjirga o'tkazish — rejadagi kunda.

## 65) Deploy tayyorligi: jonli versiyadan joriy versiyaga yangilanish yo'li tekshirildi — 2026-11-11

- **Jonli sayt holati (faqat o'qish, ochiq sahifa fayllari):** `admin.html` — `47b31a8` (9-noyabr; dizayn v2 1-bosqichi),
  `index.html` — joriy bilan bir xil, `assets/js/fin-kassa.js` — yo'q. Demak saytda hali yo'q: dizayn v2 2-bosqichi (`6446f57`),
  A relizi (`fin-prereq.sql` va bog'liq tuzatmalar), kassa moduli kodi (u `--dev` da — deploy bilan bazaga chiqmaydi, sahifada yashirin).
- **Lokal simulyatsiya (deploy.sh bilan aynan bir xil: `chain.sh | psql`, bitta tranzaksiya, lock_timeout):** `47b31a8` zanjiri +
  sintetik ma'lumot → joriy zanjir: 89 fayl, xatosiz, ma'lumot (soni va summalari) o'zgarmadi; qayta ishga tushirish xatosiz;
  `verify-db.sh` — «BIR XIL» (2984 obyekt); `kassa-checks.sql` — «kassa moduli o'rnatilmagan»; `predeploy-checks.sql` (yangi fayl)
  eski bazada xatosiz; `full-deploy.sh` keyingi tekshiruvidagi barcha «kutilgan» qiymatlar mos; kassa bloki uch holatda
  (modul yo'q / toza / ataylab buzilgan) to'g'ri; `deploy.sh` 5-bosqich markerlari joriy fayllarda bor.
- **Brauzer, yangilangan bazada:** yangi sahifa — to'lov 12/12, eski oqimlar 11/11, dizayn (kompyuter va telefon) xatosiz; eski
  sahifa (`47b31a8`, ochiq qolgan oynalar) — onlayn va oflayn naqd to'lov 9/9, yetim «pending» yo'q. Server kodi: payments 192,
  auth, `tg-daily` 39.
- **Kutiladigan ma'lumot qatori:** prod'da takroriy o'qituvchi/xodim ID 2 ta (A relizi tekshiruvidan ma'lum) — deploy xatosi emas,
  kartochkada «Yangi noyob ID berish» bilan bir martalik tuzatiladi.
- Deploy buyrug'i — `migration/deploy/full-deploy.sh` boshidagi qator (egasi ishga tushiradi).
- **2026-11-12: egasi deploy qildi; tekshiruv (faqat o'qish):** saytdagi 55 fayl (sahifalar, `/sb`, `assets`, `vendor`) `b4ee8e2`
  bilan bayt-bayt bir xil; A relizi bazada (`payments.statusAt`, `refunds.byUid`, `salary_payments.byUid` ustunlari;
  `director_daily` da yangi `late` kaliti; `record_manual_payment` bor va anonga yopiq — 42501); kassa moduli yo'q (`kassa_state`,
  `fin_snapshot_get` — 404, sahifada «Kassa» bo'limi yo'q); «🩺 Tizim holati» — auth, db, gotrue, eskiz, pay, ai, onlayn to'lov,
  zaxira — hammasi ✓; yangi dizayn: kompyuterda 80px ikonali panel, telefonda 5 bandli pastki menyu, sahifa xatolari yo'q.
  SINOV direktor hisobi bilan, har qanday yozuv so'rovi to'xtatilgan holda.

## 66) Moliya: buxgalter ko'zi bilan ko'rik, 1C bilan solishtirish; avans hisoboti (M1/M2) — 2026-11-12

**Holat: jonli tizimga CHIQMAGAN.** O'zgarishlar `--dev` zanjiridagi kassa fayllarida (`fin-seed.sql`, `kassa-docs.sql`,
`kassa-day.sql`, `kassa-links.sql`, `kassa-checks.sql`, `fin-version.sql`), `fin-kassa.js`, `fin-print.js` va `admin.html` ning
kassa ishga tushgandagi xarajat oynasida (kassasiz tizimda hech narsa o'zgarmaydi).

- **Buxgalter ko'rigi** (Claude Docs hisoboti «Kassa moduli: buxgalter ko'rigi va 1C bilan solishtirish»; yakka, buxgalter
  ko'zi bilan — mustaqil ko'p agentli ko'rik ishga tushirilmadi): 21 ta provodka, 17 ta kassa intizomi talabi, hisobdorlar,
  fiskal chek, davr yopish ko'rildi. Xulosa: to'sib qo'yuvchi topilma yo'q; 6 ta muhim (M1–M6), 12 ta hisob siyosati qarori
  buxgalter imzosini kutadi (21-noyabrgacha). 1C bilan: kassa nazorati bo'yicha 1C darajasida (server qulflari, o'zgarmas
  hujjatlar, kunlik moslik — undan qat'iyroq); to'liq buxgalteriya emas — bosh kitob (4-bosqich), hisobotlar (5-bosqich),
  soliqlar, asosiy vositalar va ish haqi soliqlari buxgalter dasturida qoladi. M1–M4 va M6 1b-bosqich boshiga qo'yildi.
- **M1 — avans hisoboti** (F2.6 dan oldinga tortilgan minimal qism): «Kassa» → «Avans hisoboti» (2-ro'yxat yoki Direktor).
  Naqdsiz dalolatnoma `nc_adv_report` (umumiy «D-» seriya, kassa kitobiga kirmaydi): har chek qatori Dt statiya hisobvarag'i
  Kt 4230 (hisobdor bo'yicha); xarajatlar «Buxgalteriya»ga o'zi ko'chadi (usul «hisobdor orqali», hujjatga bog'langan);
  hisobot sanasi (92 kun ichida), 1–40 qator, har qatorda chek yoki hujjat; hisobot qoldiqdan oshmaydi (ortiqcha sarf — F2.6);
  qayta yuborish — o'sha hujjat; bekor qilish — faqat kiritilgan kuni, sabab bilan (xarajatlar olib tashlanadi, qoldiq tiklanadi).
  Chop etish: dalolatnoma «Avans hisoboti» (uch tilda), izoh ustuni, qoldiq «oldin → keyin», hisobdor imzosi.
  «Buxgalteriya»da qo'lda «hisobdor orqali» xarajat endi yozilmaydi (aks holda ikki marta yozilib, qoldiq kamaymasdi) —
  server ham rad etadi; eski yozuvlarda usul ko'rinib turadi.
- **M2 — hisobotsiz yangi avans yo'q:** hisobdorda hisobot qilinmagan qoldiq bo'lsa, yangi avans so'rovi Direktor tasdig'ini
  ham kutadi (summasi T1 dan kichik bo'lsa ham); pul berishda hisobdor qulfi ostida yana tekshiriladi (ikki so'rov qoldiqsiz
  paytda yozilgan bo'lsa, ikkinchisi rad — xabarda «bekor qilib, qaytadan yozing» yo'li). Sahifa so'rovdan keyin bu haqda aytadi.
- **Nazorat:** «Hisobdorlardagi pul» = berilgan − qaytim − avans hisobotlari («reported» kaliti); moslikda P4 «adv» — hisobot ↔
  xarajatlar mos emas yoki hisobotsiz «hisobdor orqali» xarajat. Qulf tartibi: L0 hujjat → hisobdor (`iqror_acc`) → L4 kassa.
- **Modul relizi 2** (`fin-version.sql`, `SERVER_VER`, `kassa-checks.sql`: ochiq funksiyalar 34, ichki 62).
- **Hujjatlar:** `yoriqnomalar.md` (bank xarajati usullari, «Hisobdorlar», Direktor istisnosi), `shakllar.md` (Sh-1),
  `buxgalteriya-ish-reja.md` (holat, F1.26 Z-hisobot — M6, F1.27 tashkilotga naqd — M3, F2.6 toraydi).
- **Sinovlar:** `test-kassa-report.sql` 68 (+16: AV0–AV16 — rollar, rad holatlari, provodkalar, ko'chgan xarajatlar,
  nazorat, dup, bekor qilish, Direktor istisnosi, ikki so'rov poygasi, moslik buzilishi), `test-kassa.sql` 225,
  `test-kassa-pay.sql` 54, `test-kassa-links.sql` 93, `test-fin-period.sql` 36, `test-kassa-checks.sql` 32 (toza holatda
  avans va hisobot bilan), `test-fin-prereq.sql` 87, `test-audit-fixes.sql` 36, `test-public-close.sql` 92,
  `test-kassa-race.sh` 22; zanjirni qayta ishga tushirish — OK; JS 29 (`fin-print` 19). Brauzer: 18 ta ishga tushirish
  (7 kassa ssenariysi × 2 dizayn + to'lov va eski oqimlar, kassali va jonli zanjirda) — hammasi yashil, 448 tekshiruv;
  `e2e-kassa7` 26 — avans berish, avans hisoboti, bekor qilish, hisobotsiz qoldiqli xodimga yangi avans so'rovi (Direktorga
  boradi, sahifa aytadi); `e2e-kassa3` — xarajat oynasida endi 2 usul.
- **Qilinmagan:** mustaqil (ko'p agentli) ko'rik — ruxsat berilmadi; jonli zanjirga o'tkazish — rejadagi kunda.
  Keyingi: F1.26 (M6), F1.27 (M3), F1.22 (M4).

## 67) Moliya, 1b boshi: onlayn kassa (NKM) Z-hisoboti bilan solishtirish (F1.26, buxgalter ko'rigi M6) — 2026-11-12

**Holat: jonli tizimga CHIQMAGAN.** O'zgarishlar `--dev` zanjiridagi kassa fayllarida (`kassa.sql`, `kassa-day.sql`,
`kassa-checks.sql`, `fin-version.sql`), `fin-kassa.js`, `fin-print.js` va `auth/tg-daily.cjs` da (kassa bloki bo'lmasa — o'zgarishsiz).

- **Nima qiladi:** kun oxirida kassir NKM Z-hisobotining raqami va undagi sotuv jamlarini (naqd, bank kartasi; qaytarishlarsiz)
  kunni yopish oynasida kiritadi. Tizim solishtiradi: naqd ↔ shu kunning fiskal chekli kirim orderlari (bekor qilinganlarsiz;
  fiskal cheksiz istisno Z da bo'lmaydi), karta ↔ shu kunning terminal to'lovlari (kassa kuni bo'yicha, `fin_receipts` qoidasi).
  Ochiq kunda kutilgan summalar ko'rsatilmaydi — kassir qog'ozdagi raqamni yozadi; natija yopilgach aytiladi.
- **Saqlash:** fakt — kun hodisasi (`cash_day_events`, yangi tur `zreport`; faqat qo'shiladi, oxirgisi amalda, kim kiritgani bilan).
  Kutilgan summa va farq har safar hujjatlardan hisoblanadi (qayta ochilgan kun, kechikib kiritilgan terminal to'lovi ham).
- **Yo'llar:** Z yopishda kiritiladi (kerak bo'lsa-yu kiritilmasa — ogohlantirish); «Z-hisobot yo'q» — faqat sabab bilan; keyin
  kiritish yoki tuzatish — «Kassa kunlari» qatoridagi «Z» tugmasi (`kassa_day_z`: kassir, kassir o'rniga Direktor yoki Moliya
  menejeri; kun tekshirilguncha). Noto'g'ri Z ma'lumoti bilan kun yopilmaydi (xabar bilan qaytadi). Sinov kassasida Z yuritilmaydi.
- **Nazorat:** Z kiritilmagan / «yo'q» / mos emas — kun qatorida (tekshirilmagan kunda qizil), nazorat ro'yxatida («Onlayn kassa
  Z-hisoboti», qizil), Direktorning Telegram hisobotida; kunni tekshirishda izoh majburiy (sahifa va server: `kassa:z_note`).
  Tekshirilgan kunning Z i o'zgarmaydi.
- **Ko'rinish va chop etish:** kun oynasida Z (raqam, summalar, tizimdagi summalar va chek soni, holat); kunlik hisobotda (RP-02,
  o'zbek / rus) yangi bo'lim «Onlayn kassa (NKM) Z-hisoboti» — Z ↔ tizim, farq; kun jurnalida «Z-hisobot».
- **Modul relizi 3** (`kassa_day_z`; kun javobida «z», nazoratda «zreport»; `kassa-checks.sql`: ochiq funksiyalar 35, ichki 64).
- **Qo'llanma:** `yoriqnomalar.md` (kassir — kechqurun Z; buxgalter — tekshirishda Z ogohlantirishi, nazorat ro'yxati), reja — F1.26 ✅.
- **Sinovlar:** `test-kassa-report.sql` 90 (+22: Z0–Z16 — rollar va rad holatlari, keyin kiritish va dup, izoh talabi uch holatda
  (kiritilmagan / «yo'q» / farq), yopishda noto'g'ri Z, kutilgan summalar (bekor qilingan terminal va Click hisobga kirmaydi),
  ochiq kunda yashirin, nazorat, Telegram, kunlik hisobot, kerak bo'lmagan kun, sinov kassasi, ichki funksiyalar yopiq),
  `test-kassa-checks.sql` 32 (reliz 3), qolganlari o'zgarishsiz (225 / 54 / 93 / 36 / 87 / 36 / 92); JS 31 (`fin-print` 20,
  `fin-kassa` 4), `tg-daily` 42. Brauzer: yangi `e2e-kassa8` 28 (ikkala dizaynda) — xato Z bilan yopish, farq kun qatorida va
  nazoratda, izohsiz tekshirib bo'lmaydi, «Z» bilan tuzatish, izohsiz tekshirish, kun oynasi va kunlik hisobot, telefonda
  «Z-hisobot yo'q». `e2e-kassa2` — kassir Z ni kiritadigan qilib yangilandi; `e2e-kassa4` — nazorat ro'yxati 21 qator;
  `e2e-kassa6` — reliz 3. Jami 20 ta ishga tushirish, hammasi yashil (504 tekshiruv). Poyga 22; zanjirni qayta ishga tushirish —
  OK; oldingi relizdan (`fdb6a11`, reliz 2) yangilanish — xatosiz, `kassa-checks.sql` «muammo topilmadi (modul relizi 3)».
- **Qilinmagan:** mustaqil (ko'p agentli) ko'rik — ruxsat berilmadi; jonli zanjirga o'tkazish — rejadagi kunda.

## 68) Moliya, 1b: yuridik shaxsga kassadan naqd to'lov — ogohlantirish va Direktor tasdig'i (F1.27, buxgalter ko'rigi M3) — 2026-11-12

**Holat: jonli tizimga CHIQMAGAN.** O'zgarishlar `--dev` zanjiridagi fayllarda (`fin-core.sql`, `kassa-docs.sql`, `kassa-day.sql`,
`kassa-checks.sql`, `fin-version.sql`) va `fin-kassa.js` da.

- **Qoida:** «Xarajat» chiqim so'rovining oluvchisi yuridik shaxs kontragent (turi «yetkazib beruvchi» yoki «tashkilot») bo'lsa,
  so'rov Direktor tasdig'ini ham kutadi (summasi T1 dan kichik bo'lsa ham). Chegara — «⚙ Sozlamalar» → «Yuridik shaxsga kassadan
  naqd to'lov — Direktor tasdig'isiz chegara» (`fin_org.extra.orgCashMax`; bo'sh yoki 0 — har doim Direktor; faqat Direktor
  o'zgartiradi). Jismoniy shaxs (YaTT ham), «boshqa», bank, ta'sischi qoidaga kirmaydi; boshqa operatsiyalar o'zgarmaydi.
- **Sahifa:** so'rov oynasida yuridik shaxs tanlansa — sariq ogohlantirish (asosiy yo'l — bank o'tkazmasi yoki hisobdor shaxs;
  chegara qo'yilgan bo'lsa — matnda); yuborilgach «Direktor tasdig'i ham kerak» xabari; nazorat ro'yxatida yangi qator
  «Yuridik shaxslarga kassadan naqd to'lov» (oxirgi 30 kun: soni va summasi; «diqqat»).
- **Qaror va qo'llanma:** FD-47 (chegara va kontragent turlari — buxgalter tasdiqlaydi, Direktor sozlamaga kiritadi);
  `ishga-tushirish.md` 4-qadam (sozlama va kontragent turlari), `yoriqnomalar.md` (kassir, buxgalter, Direktor jadvali).
- **Modul relizi 4** (javobda «orgCash», nazoratda «orgCash30», sozlama `orgCashMax`; `kassa-checks.sql`: ichki funksiyalar 65).
  Deploy tekshiruvi (`kassa-checks.sql`, 10-band) yangi yordamchi funksiya nomi mavjud `app.kassa_num` bilan bir xil ekanini
  (overload) ushladi — mavjudidan foydalanildi.
- **Sinovlar:** `test-kassa-report.sql` 98 (+8: O0–O7 — standart «har doim Direktor», rollar va noto'g'ri qiymat, moliya tasdig'i
  yetmasligi, chegara 100 000 / 100 001, nazorat ro'yxati, boshqa operatsiyalar, ichki funksiya yopiq). M3 haqida bo'lmagan SQL
  to'plamlari va brauzer ssenariylarida sozlamada chegara katta qo'yildi — ularning oqimi o'zgarmadi (`e2e-kassa` chegarani
  sozlamalar oynasidan kiritib, saqlanganini tekshiradi). Yangi `e2e-kassa9` 12 (ikkala dizaynda): ogohlantirish (yetkazib beruvchi
  — bor, YaTT — yo'q, operatsiya almashsa — yo'qoladi), so'rov Direktorga boradi, Direktor chegara qo'yadi, kichik summa Direktorsiz,
  nazorat ro'yxatida qator.
  `e2e-kassa4` — nazorat ro'yxati 22 qator, yetkazib beruvchiga naqd to'lov «diqqat» bo'lib ko'rinadi; `e2e-kassa6` — reliz 4;
  `test-kassa-race.sh` — sozlamada chegara katta (poyga qoidani emas, parallellikni tekshiradi) — 22/22. Barcha SQL to'plamlari
  yashil (225 / 54 / 93 / 98 / 36 / 87 / 36 / 92 / 32); JS 31; `tg-daily` 42. Brauzer: 22 ta ishga tushirish, hammasi yashil
  (528 tekshiruv). Oldingi relizdan (`3d1dfa3`, reliz 3) yangilanish — xatosiz, `kassa-checks.sql` «muammo topilmadi (modul relizi 4)».
- **Qilinmagan:** mustaqil (ko'p agentli) ko'rik — ruxsat berilmadi; jonli zanjirga o'tkazish — rejadagi kunda.

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
