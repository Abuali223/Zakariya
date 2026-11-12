# Moliya bo‘limi: kassa va buxgalteriya hisobini 1C uslubida yuritish — ish rejasi

**Sana:** 2026-11-09 (dushanba). **Holat:** egasi (direktor) va maktab buxgalteri tasdig‘i uchun. **Asos:** namunalar,
kod va qonunchilik bo‘yicha 8 ta o‘rganish; uch yo‘nalishdagi loyiha; uch mustaqil ko‘rik (buxgalteriya, kod, to‘liqlik)
— barcha topilmalar kiritilgan yoki sababi bilan rad etilgan; `KIRIM-CHIQIM-TAHLIL.md`, `JORIY-ETISH-REJA.md` (D1–D9,
muhandislik qoidalari); kod `6446f57` holatida tekshirilgan.

**Qisqacha.** Har bir naqd pul harakati pul qo‘ldan chiqqan yoki kelgan paytda tizim yaratadigan, raqamlangan va
o‘zgarmas hujjatga aylanadi: kassa kirim orderi (ПКО, KO-1) yoki kassa chiqim orderi (РКО, KO-2). Kassirning kunlik
hisoboti (kun boshi, kirim, chiqim, kun oxiri, hujjat raqamlari, kimdan / kimga qancha) qo‘lda yozilmaydi — hujjatlardan
hisoblanadi; kassa kitobi (кассовая книга, KO-4) varaqlari kun yopilganda muzlatiladi. Har xarajat statiyaga (статья)
ega, statiya BHMS 21 hisobvarag‘iga bog‘langan — boshqaruv hisobi, bosh kitob va hisobotlar shundan quriladi. Ish 7
bosqichda (1-bosqich ikki qismga bo‘lingan): **0** — qarorlar, tayyorgarlik, 16-noyabrdan oraliq qoidalar; **1a** —
kassa (MVP): noyabr–dekabrda quriladi, dekabrda sinov stendida qabul sinovi va prod’da bayroq ostida yashirin o‘rnatish,
**rasmiy ishga tushirish — 2027-yil yanvardagi birinchi kassa kuni (rejada 4-yanvar)**, boshlang‘ich qoldiq — 31-dekabr
komissiya sanash dalolatnomasi; **1b** — yanvarda qo‘shimchalar; **2** — statiyalar hamma joyda, avans hisobotlari, oy
qulfi (fevral); **3** — bank va yo‘ldagi pul (mart); **4** — 2027-01-01 dan bosh kitob (aprel); **5** — hisobotlar
(may–iyun); **6** — muvofiqlik kengaytmalari. Ishga tushirish 6 ta darvozaga bog‘langan (§5); biri bajarilmasa sana
fevralning birinchi kassa kuniga suriladi, qamrov qisqarmaydi. Dizayn ishlari to‘xtatilgan: faqat mavjud komponentlar,
v1 va v2 ko‘rinishlarida. Jami mehnat ≈ 161 dasturchi-kun.

### Egasi uchun qisqa ko‘rinish
| Bosqich | Qachon | Nima o‘zgaradi |
|---|---|---|
| 0 — Qarorlar va tayyorgarlik | 9–28-noyabr | 14-noyabr — qarorlar yig‘ilishi; 16-noyabrdan dasturdagi o‘zgarishlarsiz «oraliq qoidalar» (§8.3: bankka topshirish xarajat emas, har kech pul sanaladi, kun boshi qo‘lda tuzatilmaydi…); tizimdagi ortiqcha huquqlar va pul yozishdagi kamchiliklar tuzatiladi |
| 1a — Kassa (asosiy qism) | quriladi 16-noyabr – 26-dekabr; rasmiy boshlanish — 2027-yil 4-yanvar | «Kassa» bo‘limi: har kirim va chiqim tizim raqamlagan order (KO-1 patta bilan, KO-2); kun boshi kechagi qoldiqdan avtomatik; chiqim to‘lovdan oldin tasdiqlanadi; kechqurun sanash va kunni yopish; KO-4 kassa kitobi chop etiladi; «kimdan / kimga qancha» kunlik hisoboti; direktorga Telegramda kunlik kassa |
| 1b — Qo‘shimchalar | 4–23-yanvar | ≤ 5 ish kunlik parallel yuritish, keyin Excel kunlik varag‘i to‘xtaydi; buxgalter roli; KO-3 jurnali; Excel’ga eksport; eslatmalar |
| 2 — Statiyalar hamma joyda | fevral | bankdan to‘langan xarajatlar ham statiya va kontragent bilan; zavxoz avans hisoboti; oyni qulflash |
| 3 — Bank va onlayn to‘lovlar | mart | bank ko‘chirmasini yuklash; Click, Uzum va terminal komissiyalari avtomatik |
| 4 — Bosh kitob (provodkalar) | aprel | 2027-yil 1-yanvardan provodkalar, aylanma-saldo vedomosti, oy yopish |
| 5 — Hisobotlar | may–iyun | balans (1-shakl), moliyaviy natijalar (2-shakl), pul oqimi, ota-onalar uchun to‘lov ma’lumotnomasi |
| 6 — Muvofiqlik | iyundan (kerak bo‘lsa oldinroq) | fiskal chek integratsiyasi, elektron imzo (ERI), maosh soliqlari moduli |

**Hozir egasidan kerak (2026-11-10 holati; qarorlar dasturchiga topshirilgan, fiskal kassa va buxgalter — bor):**
(1) 0-bosqich tuzatmalarini jonli tizimga o‘rnatish (`migration/deploy/README.md`, «To‘liq deploy»); (2) sinov stendini
o‘rnatish (`sinov/README.md`; kassa bilan — `update.sh --dev`) — qabul sinovi va o‘qitish shu yerda; (3) buxgalter
21-noyabrgacha hisob qismini (hisobvaraqlar, statiyalar, operatsiyalar — §4.2–4.6), `docs/moliya/shakllar.md` va buyruq
namunalarini ko‘rib chiqadi; (4) bank bilan kassa limiti bormi — javob; (5) 12-dekabrgacha: buyruqlar imzolanadi va
fiskal kassa bo‘yicha yozma tasdiq (G1, G5); (6) 14–26-dekabr: har rol stendda qabul sinovini o‘tkazib imzolaydi (G4).
Ishga tushirish tartibi va tekshiruv ro‘yxatlari — `docs/moliya/ishga-tushirish.md`.

**Belgilar.** `F<bosqich>.<n>` — vazifa; `FD-nn` — qaror; `IN-` / `EX-` / `OP-` — statiya (daromad / foyda-zararga
kiradigan xarajat / kirmaydigan operatsiya); `PR` — provodka qoidasi; `MC` — oy yopish qadami; `RP` — hisobot; `CT` —
nazorat; `RF` — huquq tuzatmasi; `RK` — xavf; `CL` — qonunchilik bandi; `G1…G6` — darvoza. **[BUX]** — buxgalter
tasdiqlaydigan hisob siyosati tanlovi; tavsiya doim yozilgan; egasi F0.1 da «[BUX] tavsiyalarini vaqtincha qabul
qilaman» deydi, buxgalter kassa qismini 21-noyabrgacha tasdiqlaydi; dastur tavsiyalar bo‘yicha quriladi, imzolarni faqat
rasmiy ishga tushirish kutadi. **Hajm:** S < 1 kun, M 1–3 kun, L > 3 kun (bitta dasturchi, testlar bilan); «kun» —
taxminiy mehnat. **Ommaviy repozitoriy:** ism, telefon, ID, kontragent va maktab summalari yo‘q (faqat sonlar, foizlar,
qonuniy stavkalar, sintetik qiymatlar); rekvizit va chegaralar RLS li sozlama jadvallarida; hisob siyosati to‘plami va
**yopiq ilova** (namunalardagi aniq qatorlar, summalar, huquqiy baho talab qiladigan topilmalar) repozitoriyga
kiritilmaydi. Har commit oldidan: shaxsiy ma’lumot, summa va maktab haqida huquqiy xavf yoki jarima bayonoti yo‘q.

---

## 1. Maqsad va qamrov

**1.1 Maqsad.** (1) Har pul harakati — raqamlangan, o‘zgarmas boshlang‘ich hujjat: kim, qancha, asos, statiya,
korrespondent hisobvaraq. (2) Kunlik kassa hisoboti hujjatlardan hisoblanadi; qo‘lda yozilgan qoldiq yo‘q. (3) Har
xarajat statiya orqali BHMS 21 hisobvarag‘iga bog‘langan.

**1.2 «1C kabi» bu yerda nimani anglatadi**
| «1С:Бухгалтерия 8 для Узбекистана» | Bu tizimda | Bosqich |
|---|---|---|
| Operatsiya turi hisobvaraq va statiyani to‘ldiradigan ПКО/РКО | Operatsiyalar katalogi (§4.5): Dt/Kt operatsiyadan, kassir statiya va tomonni tanlaydi | 1a |
| KO-4 kassa kitobi, varaqlar 1-yanvardan, 2 nusxa; orderlar jurnali va raqamlash nazorati | Hujjatlardan quriladigan, yopishda muzlatiladigan KO-4; uzluksiz server raqamlari; KO-3 | 1a / 1b |
| Qaydnoma doirasida maosh; to‘lovni hisob-kitob va avansga ajratish | Tasdiqlangan vedomost bilan cheklangan har kishilik KO-2; KO-1 da Kt 4010 + 6310 | 1a |
| Hisobdor shaxslar va avans hisoboti (АО-1); bank-mijoz | 4230 (1a), avans hisoboti (2); ko‘chirma importi va 5710 (3) | 1a–3 |
| Taqiqlash sanasi; oy yopish yordamchisi; ОСВ, kartochka, tahlil | Kun qulfi va 31.12 surati (1a), barcha pul jadvallari uchun oy qulfi (2); MC-1…MC-13 va hisobotlar (4) | 1a–4 |
| Reglamentlangan hisobotlar | 1- va 2-shakl (kichik korxona bo‘lmasa 3-, 4-shakl ham, FD-45) qoralamalari | 5 |

Qamrovga kirmaydi: 1C litsenziyasi yoki integratsiyasi, soliq hisobotlari, tovar bo‘yicha ombor, valyuta kassasi, bir
nechta kassa.

**1.3 Qamrov.** Ichida: 5010 kassa; barcha pul harakatlarida statiya; hisobdor shaxslar; bank va 5710; 2027-01-01 dan
boshqaruv bosh kitobi; hisobot qoralamalari; qaror qilingan muvofiqlik kengaytmalari. Tashqarida: soliqlarni hisoblash va
topshirish (buxgalter; tizim faqat hisob yozuvlarini beradi), sentyabr–oktyabr importi (2026-10-26 qarori), vizual qayta
dizayn, asosiy vositalar va yetkazib beruvchi hisob-fakturalari modullari (buxgalter jurnallari bilan).

**1.4 Buxgalterning roli.** Hisob siyosati to‘plamini (hisobvaraqlar, statiyalar, provodka qoidalari, shakllar,
raqamlash, imzo ro‘yxatlari, hujjatlar aylanishi grafigi) tasdiqlaydi; 2-ro‘yxat bo‘yicha imzolaydi va kunlarni
tekshiradi (yoki moliya menejeriga topshiradi); avans hisobotlari, qo‘lda jurnallar, boshlang‘ich qoldiq va oy yopishni
o‘tkazadi; A rejimda statutor registrlarni yuritadi (oylik eksport bilan); har bosqichning qabul sinovchisi.

---

## 2. Namunalar tahlili (topilgan muammolar va ularning yechimi)
Namunalar: kassir va buxgalter ish kitobi (9 varaq), «Financial Tracker» (ikki nusxa, mazmuni bir xil, 26 varaq), KO-1
shabloni va KO-4 sahifasi fotosuratlari. Faqat sonlar va foizlar; huquqiy baho talab qiladigan topilmalar va aniq
qatorlar — yopiq ilovada. Tuzilmalar — B-ilovada.

| № | Topilma | Yechim | Qayerda |
|---|---|---|---|
| S1 | Kunlik varaqda kuniga bitta qator, hujjat tafsiloti yo‘q; jamlar qo‘lda yoki «=a+b» bilan | Jamlar faqat o‘tkazilgan hujjatlardan | F1.9, RP-02 |
| S2 | Kun boshi qoldig‘i 3 marta hujjatsiz tuzatilgan; bir kirim 3 kun zanjirdan tashqarida | Kun boshi = kecha kun oxiri; farq faqat dalolatnoma orqali | CT-02 |
| S3 | Kunlik chiqim jamlari va xarajat reyestri ayrim kunlarda mos emas | Naqd chiqim faqat KO-2; KO-4 faqat KO-1/KO-2 dan | F1.4 |
| S4 | Bankdan olingan naqd kirim deb hisoblangan (oktyabr naqd kirimining 34,5 %, noyabr 51,4 %); bankka topshirish 2 marta xarajat deb yozilgan | `in_bank` / `out_bank` ichki o‘tkazma (5110 / 5710); daromad ham, xarajat ham emas | §4.5 |
| S5 | Sentyabr chiqimlarining 72 % raqamsiz; oktyabr Р/О da 7 takror, 10 bo‘shliq; П/О da 23 tadan 1 takror, 1 bo‘shliq; noyabrda raqam sakrashi | Server beradigan, tur va yil bo‘yicha uzluksiz seriyalar; bo‘shliq tekshiruvi | F1.3 |
| S6 | Imzo yo‘q; tasdiq matn ustunida, bitta rol 82–97 % qatorni tasdiqlagan, summaga bog‘liq emas | Ikki imzo ro‘yxati; to‘lovdan oldin 2-ro‘yxat tasdig‘i; T1; tekshiruvchi ≠ o‘tkazuvchi | F1.10 |
| S7 | Zavxozga xarid puli berilganda xarajat (oktyabr oziq-ovqatining 98 %), qaytim kirim; hisobdor varag‘i oktyabr boshida to‘xtagan | 4230 bo‘nak, qaytim KO-1, avans hisoboti, muddat nazorati | F1.4, F2.6 |
| S8 | «Oylik»da avans, hisob-kitob, ta’til puli va boshqa xarajatlar aralash; xodim bo‘yicha yo‘q; o‘zaro hisob naqd deb yozilgan | Faqat tasdiqlangan vedomostdan har kishilik to‘lov; 4210; o‘zaro hisob dalolatnomasi; KO-2 da maosh statiyasi taqiqlangan | F1.5 |
| S9 | Qaytarish «Boshqa» xarajat (biri ikki marta); «Boshqa»ning 43,2 % xarajat emas | Qaytarish = tasdiqlangan qaytarishga KO-2 (6310/4010); «Boshqa» izohli, ≤ 2 % | F1.6 |
| S10 | Ekvayring komissiyasi yozilmagan (Click/Uzum 1 %, terminal 0,2 % yoki 1 %); varaq hammasiga 1 %; kanal ustunlari to‘liq emas | 1a da kanal bloki; 3-bosqichda komissiya bilan 5710 | F3.4 |
| S11 | Ikki kirim kitobi ≈ 10 % farq; summalar matn; havolalar qator o‘rni bo‘yicha (6 tasi boshqa o‘quvchiga); yopilgan oy keyin tahrirlangan (+5,2 %) | Yagona manba — hujjatlar; 31.12 surati; oy qulfi | F1.16, F2.8 |
| S12 | Hisob kodlari yo‘q; fotoda «51.10» (= 5110) va rasmiy bo‘lmagan «40.11» (4010 guruhi) | BHMS 21 to‘rt xonali kod + analitika | FD-09 |
| S13 | KO-1 da joy, lavozim, F.I.Sh., bosh buxgalter va kassir qatorlari yo‘q, imlo xatolari; KO-4 da hujjat raqami bo‘sh, sana va varaq qo‘lda, 1 nusxa | Barcha rekvizitlar sozlamadan, server sanasi, muzlatilgan varaqlar, 2 nusxa | F1.14 |
| S14 | Kunlik sanash dalolatnomasi yo‘q; ortiqcha faqat izohda; bir kunning kassa hisoboti yo‘q | Majburiy kechki sanash; farq shu kun hujjatlashtiriladi | F1.9 |
| S15 | Izoh va kvitansiyalarda shaxsiy ma’lumot; mahalliy Excel fayllari | Ma’lumot faqat tizimda, RLS; cheklangan eksport | FD-28 |
| S16 | Tracker dekabr–iyun shablonlari noyabr xatolarini takrorlaydi; «Sof foyda» = kirim − barcha chiqim (o‘tkazmalar, qaytarish, avans bilan) | Sheet yangi oylarga ishlatilmaydi; natija faqat foyda-zarar statiyalaridan | FD-27 |

---

## 3. Hozirgi tizim — nima bor, nima yetishmaydi

**3.1 Qayta ishlatiladi**
| Komponent | Joyi | Nima uchun |
|---|---|---|
| Qo‘lda to‘lov shakli, outbox, takrorga qarshi himoya | admin.html:11784-11910, 11678-11716 | O‘quv to‘lovi KO-1 old qismi |
| `apply_payment` (atomar, idempotent, eng eski fakturadan, `credit_ledger`) | audit-7.sql:28-121 | KO-1 ortidagi hisob-kitob |
| Advisory lock, idempotentlik, `set_config(...,true)` bayrog‘i | audit-7.sql:62-89; refund-rpc.sql:47-71; invoice-guards.sql:152-166 | Kassa RPC namunasi |
| Maosh tasdig‘i, to‘lov chegarasi, kiritmalar qulfi | payroll-approval.sql:126-312 | Kun yopish namunasi; maosh KO-2 chegarasi |
| `APPROVAL_QUEUES`; `printHTML`; SheetJS; `downloadCSV` | admin.html:1434-1438; 2998-3004; 21; 2130-2139 | Navbatlar, chop etish, XLSX |
| `tkDay` / `payDay` / `isCashPay` / `CASH_PAY_ST`; `PROV_LBL` | admin.html:904-921; 896 | Serverda yagona kirim ta’rifi; kanal nomlari |
| RPC orqali ishlaydigan RLS jadvali; QR | `issued_documents` public-close.sql:126-147 | Yangi jadvallar shakli; patta QR |
| `chlog_attach`; `app.tashkent_now()`; `app.has_role()`; `payeeRef` | change-log.sql; attendance-sync.sql:45; reports-roles.sql:65; id-guards.sql:365-366 | Audit, server sanasi, aniq rol, «Кимга» |
| `students_billing`; test va deploy vositalari; `_setClient` | admin.html:2104-2106; test-audit-fixes.sql, predeploy-checks.sql, verify-db.sh; sb/_core.js:8 | Kassada tanlash; testlar; UI soxta mijoz bilan sinov |
| 21 xarajat toifasi; `payroll_lines` | admin.html:9086; payroll-approval.sql | Statiya xaritasi; maosh taqsimoti |

**3.2 Yetishmaydi**
| № | Kamchilik | Dalil |
|---|---|---|
| G1 | Kassa hujjati, raqamlash, KO-3 yo‘q | o‘rganishlar (code-ui, code-db) |
| G2 | Kun boshi/oxiri, sanash, kun qulfi yo‘q; qo‘lda to‘lov 31 kun orqaga; boshqa sanalar erkin | admin.html:11804, 11833-11836, 910-912, 9306, 8890, 9432 |
| G3 | «Jami tushgan» barcha usullarni qo‘shadi; chiqimlarda usul yo‘q | admin.html:11240-11244 |
| G4 | Chiqim 4 jadvalda; oy 1-kuni sanali `payroll__YYYY-MM` hisoblash qatori xarajatlar orasida | admin.html:9350-9420 |
| G5 | Mijoz soati va mijoz yuboradigan «kim» maydonlari | sb/firebase-firestore.js:24, 38-40; admin.html:9074, 11958 |
| G6 | Qo‘lda to‘lov 3 ta alohida so‘rov (yetim «pending») | admin.html:11695-11703 |
| G7 | Qaytarish asl qatorni o‘zgartiradi va tasdiq paytida balansni darhol o‘zgartiradi | refund-rpc.sql:72-84, 125; admin.html:11216-11219 |
| G8 | Statiya va bosh kitob yo‘q; `expenses` — sana, oy, toifa, summa, izoh | expenses-setup.sql:14-23 |
| G9 | Chop etishda raqam, so‘z bilan summa, rekvizit, imzo yo‘q; termal «TO‘LOV CHEKI» to‘lovchiga beriladi | admin.html:12014-12045 |
| G10 | Ortiqcha huquqlar (kassir xarajat/avans yozadi, `add_credit` va `apply_payment` chaqiradi; HR tasdiqlaydi va to‘laydi; g‘aznachi bazada to‘liq moliya; marketing xarajatlarni o‘qiydi; `credit_ledger` o‘chiriladi) | cashier-role.sql:33-37; audit-3.sql:66-93; add-credit.sql:36-42; audit-7.sql:46-49, 121; admin.html:1460, 1411; reports-roles.sql:106-109; credit-ledger.sql:34 |
| G11 | `director_daily` bo‘lingan to‘lov bolalari va `reattr` ni ham sanaydi | telegram.sql:445-458 va admin.html:904-907 |
| G12 | Click/Uzum `createdAt` — yakunlanish emas, tayyorlanish vaqti | payments/index.cjs:323-325, 493-495 |
| G13 | FK yo‘q, summa masshtabsiz, sana matn; `payments` da faqat PK | schema.sql:158-176 |
| G14 | verify-db trigger, cheklov, indeksni solishtirmaydi | verify-db.sh:22-47 |
| G15 | Outbox server tasdig‘idan oldin chek chiqaradi; xarajatni qayta yuborish takrorlaydi | admin.html:11870-11910, 9333 |
| G16 | Fiskal chek integratsiyasi yo‘q | payments/index.cjs sarlavhasi |
| G17 | Maosh darvozasi `payrollApprovalFrom` bo‘sh bo‘lsa o‘chiq; takroriy maosh ID «HR’ga yuborish»ni bloklaydi | payroll-approval.sql:23, 248-256; `SESSIYA-ISHLARI.md`:1218-1219 |
| G18 | `apply_payment` avansni to‘lov bilan birlashtiradi va faqat `{ok, credit, sid}` qaytaradi; bekor qilish tavsiya bonusini bekor qiladi; «to‘lov qabul qilindi» xabari bekor qilingandan keyin ham ketadi | audit-7.sql:80, 119; discount-approval.sql:402-421; telegram.sql:352-368; sms-worker.cjs:363-388 |

**3.3 Platforma cheklovlari**
1. Deploy 88 faylli zanjirni bitta tranzaksiyada qo‘llaydi; yangi fayllar `telegram.sql` va `rls-initplan.sql` orasiga
   (run-all.sql:117-119) `\if :{?iqror_chain}` himoyasi bilan.
2. supabase-grants.sql (zanjirda 32-o‘rin) barcha joriy va kelajakdagi jadvallarga anon/authenticated DML beradi va
   `app.*` ga EXECUTE ni qayta beradi: har yangi jadval o‘z faylida RLS + revoke; ichki yozuvchi yordamchilar EXECUTE ni
   o‘z faylida qaytarib oladi.
3. `postgres` superuser emas: funksiya darajasidagi GUC `SET` xato (2887f4d) — bayroqlar `set_config(...,true)`; FORCE
   RLS yo‘q.
4. Qulflar: `apply_payment` avval `applied_payments` posbonini yozadi, keyin `iqror_pay:<sid>` va qator qulflari
   (audit-7.sql:63-75); `assign_payment` / `split_payment` avval payments qatorini qulflaydi (invoice-guards.sql:222-236;
   split-payment.sql:49, 84). Webhook’lar service_role (`app.is_system()`).
5. Yangi argumentsiz rol yordamchilari `v_fns` ga (rls-initplan.sql:64-66).
6. Imzo yangi faylda o‘zgarsa overload paydo bo‘ladi (reattribute-avans.sql:25-27): `refund_invoice`, `apply_payment`,
   `director_daily`, `student_id_high_water`, `students_billing` o‘z faylida tahrirlanadi.
7. `CREATE OR REPLACE` `proconfig` ni tozalaydi — har yangi SECURITY DEFINER `search_path` ni o‘zi belgilaydi; deploy
   paytida `change_log` yozmaydi (change-log.sql:64) — backfill’lar deploy’dan keyin jurnalga yoziladigan RPC bilan.
8. Shim `id` bo‘yicha upsert qiladi (sb/firebase-firestore.js:139) — yangi jadvallarda `id`; admin.html 12 054 qator;
   deploy.sh `assets/**` ni ko‘chiradi; sw.js `.js` ni avval tarmoqdan oladi; verify-db prod serverida vaqtinchalik baza
   yaratadi (verify-db.sh:68-71), jonli bazaga yozmaydi.

---

## 4. Maqsadli model

### 4.0 Asosiy tanlovlar (ziddiyatlar va ko‘rik topilmalari bo‘yicha)
1. **Ishga tushirish — yanvardagi birinchi kassa kuni** (0 + 1a ≈ 64 dasturchi-kun 14-dekabrgacha sig‘maydi; yil boshidan
   raqamlar 1 dan; 31.12 sanash 5010 va bosh kitob qoldig‘ini bir yo‘la tasdiqlaydi). Zaxira — 1-fevral (FD-01).
2. **KO-2 to‘lovdan oldin 2-ro‘yxat tasdig‘i** (Buxgalteriya hisobi to‘g‘risidagi qonun, 13-modda); > T1 — direktor ham;
   moliya menejeri 1-ro‘yxatga kirmaydi; T1 va L1 ni faqat direktor o‘zgartiradi.
3. **Fiskal chek — darvoza (G1)**: naqd KO-1 da fiskal chek raqami majburiy; termal patta va to‘lovchiga termal chek yo‘q;
   oflaynda tizim varaqasi yo‘q (VM 943-qaror, 1-ilova, 4, 30, 31, 33-band; SK 221-modda).
4. **Sanash farqi o‘sha kun sanasi bilan** tizim hujjatiga aylanadi (kamomad Dt 5910, ortiqcha Kt 9390); qarorni
   direktor qiladi (5910 → 4730 yoki 9430) — BHMS 19, 69, 70, 72-band.
5. **O‘quv to‘lovi KO-1:** Kt 4010 — boshlangan davr fakturasiga, Kt 6310 — ortiqcha va kelgusi oy fakturasiga, avansdan
   qoplangan qism — naqdsiz Dt 6310 Kt 4010; `apply_payment` 1a da o‘zgarmaydi.
6. **Kassa qulfi:** har pul hujjati, bekor qilish va yopish kassa bo‘yicha eksklyuziv qulf ostida (manfiy qoldiq yo‘q).
7. **Oflayn / kech kiritish:** hujjat o‘z kuniga (ochiq bo‘lsa), aks holda joriy ochiq kunga sanashdagi «hali
   o‘tkazilmagan» qatori bilan; qog‘oz «Қ» — faqat direktor ruxsati bilan.
8. **Qaytarish:** tasdiq (direktor, usul) va to‘lov (kassir, KO-2) ajratilgan; balans KO-2 sanasida.
9. **Bekor qilish:** o‘quv to‘lovi — rolsiz yadro funksiya, faqat keyin pul harakati bo‘lmasa, xabarnoma bekor qilinadi;
   maosh/avans/xarajat — eski qator `sourceSnapshot` ga ko‘chadi.
10. **Buxgalteriya tuzatishlari [BUX]:** soliq kassadan to‘lanmaydi (SK 74-modda); forma — qayta sotish 2910/9020/9120;
    oziq-ovqat 1010 orqali; SK 483-modda imtiyozi — 8840; maosh hisoblash maosh oyi oxiri sanasi bilan; rahbar/ta’sischiga
    berilgan pul 4290 (xodim) / 4890 (ta’sischi).
11. **UI:** alohida, kerak bo‘lganda yuklanadigan `assets/js/fin-*.js`; tasdiq navbatlari admin.html da oldindan
    ro‘yxatga olinadi; yangi CSS yo‘q.
12. **Qurilmaydi (so‘rov bo‘lsa):** yetkazib beruvchi hisob-fakturalari, asosiy vositalar reyestri, byudjet-fakt,
    valyuta kassasi, bir nechta kassa; narxlarni sanaga bog‘lash shart emas (faktura tarkibi saqlanadi, F2.7).

### 4.1 Arxitektura: hujjat → provodka → registr → hisobot
Hujjatlar (KO-1, KO-2, sanash va topshirish-qabul dalolatnomalari, o‘zaro hisob, boshlang‘ich qoldiq, avans hisoboti,
bank satri, qo‘lda jurnal) → har hujjatda saqlanadigan Dt/Kt qatorlari (1a), bosh kitob yozuvlari (4) → registrlar (KO-4,
KO-3, hisobdorlar, o‘quvchi hisob-kitoblari, bank, bosh kitob) → hisobotlar (kunlik hisobot, statiya matritsasi,
Telegram, OSV, 1/2-shakl, pul oqimi). Qoidalar: (1) yagona manba — hujjatlar; (2) raqam, sana va vaqtni server beradi
(`app.fin_today()`); (3) o‘tkazilgan hujjat tahrirlanmaydi — bekor qilish, qayta ochish yoki storno (Nizom 143, 25-band);
(4) KO-4 da faqat 5010; (5) ichki o‘tkazma daromad ham, xarajat ham emas; (6) har KO-2 qatorida statiya, hisobvaraq
o‘tkazishda tasdiqlangan xaritadan yoziladi va keyin o‘zgarmaydi; (7) kassir bajaradi, 2-ro‘yxat tasdiqlaydi va
tekshiradi, direktor katta summaga ruxsat beradi, farq bo‘yicha qaror qiladi va qayta ochadi.

### 4.2 Ishchi hisobvaraqlar rejasi (BHMS 21, 2025; 191-buyruq, ro‘yxat 3593 / 3593-1) [BUX, FD-09]
Turlar: А aktiv, П passiv, КА kontraktiv, Т tranzit (9050 ham — daromadni kamaytiradi), БТ balansdan tashqari; (*) —
namunalarda yo‘q, ixtiyoriy. Ruscha nomlar `gl_accounts.nameRu` da.

| Kod | T | Rasmiy nomi | Ishlatilishi | Anal. |
|---|---|---|---|---|
| 0130 / 0140 / 0150 / 0160* / 0190 | А | Mashina va asbob-uskunalar / Mebel va ofis jihozlari / Kompyuter jihozlari va hisoblash texnikasi / Transport vositalari / Boshqa asosiy vositalar | asosiy vositalar (buxgalter reyestri) | FA |
| 0230–0290 / 0530 | КА | …eskirishi / Dasturiy ta’minotning amortizatsiyasi | qo‘lda jurnal | FA |
| 0430* | А | Dasturiy ta’minot | doimiy litsenziya | FA |
| 0820 / 0830* / 0870 | А | Asosiy vositalarni xarid qilish / Nomoddiy aktivlarni xarid qilish / Operativ ijaraga olingan asosiy vositalarga kapital qo‘yilmalar | kapital qo‘yilma; ijaradagi bino (0870 da qoladi [BUX]) | C |
| 1010 / 1050* / 1080 / 1090 | А | Xom ashyo va materiallar / Qurilish materiallari / Inventar va xo‘jalik jihozlari / Boshqa materiallar | oziq-ovqat zaxirasi, kitob, idish, sarf | A |
| 2010 / 2910* | А | Asosiy ishlab chiqarish / Ombordagi tovarlar | xizmat tannarxi (→ 9130) / sotish uchun forma | A, DEP |
| 3110 / 3120 / 3190 | А | Oldindan to‘langan operativ ijara haqi / …xizmat haqi / Boshqa kelgusi davr xarajatlari | oldindan to‘lov (MC-4) | C |
| **4010** | А | Xaridorlar va buyurtmachilardan olinadigan to‘lovlar | o‘quv haqi («40.11» → 4010 + to‘lovchi turi) | S, M, P |
| 4210 / 4220* / **4230** / 4290 | А | Ish haqi bo‘yicha / Xizmat safarlariga / Umumxo‘jalik xarajatlari uchun / Xodimlarga berilgan boshqa bo‘naklar | avans; safar; zavxoz, oshpaz, karta; xodim-rahbarga berilgan | E |
| 4310 / 4330 | А | TMZ uchun mol yetkazib beruvchilarga / Boshqa berilgan bo‘naklar | oldindan to‘lov | C |
| 4410 / 4520 | А | Byudjetga / Davlat maqsadli jamg‘armalariga bo‘nak to‘lovlari | ortiqcha soliq (qayta tasnif) | TX |
| 4610* / 4720* / 4730 / 4790 / 4890 / 4910 | А / КА | Ta’sischilarning ustav kapitali ulushlari bo‘yicha qarzi / Berilgan qarzlar bo‘yicha xodimlar qarzi / Moddiy zararni qoplash bo‘yicha xodimlar qarzi / Xodimlarning boshqa qarzlari / Boshqa debitorlik qarzlar / Shubhali qarzlar rezervi | ta’sischi; xodim qarzi, tasdiqlangan kamomad; ta’sischiga berilgan pul (4890); rezerv | C, E, S |
| **5010** / 5020* / 5210* | А | Milliy valyutadagi pul mablag‘lari / Chet el valyutasidagi pul mablag‘lari / Mamlakat ichidagi chet el valyutasi hisobvaraqlari | **kassa (KO-4 ning yagona hisobvarag‘i)**; valyuta — faqat zarur bo‘lsa | K, B |
| **5110** / 5530 | А | Hisob-kitob hisobvarag‘i / Boshqa maxsus hisobvaraqlar | bank; korporativ karta (FD-35) | B |
| **5710** | А | Yo‘ldagi pul mablag‘ (o‘tkazma)lari | POS, Click, Uzum, Payme, QR; bankka topshirilgan naqd | CH |
| 5910 | А | Kamomadlar va qiymatliklarning buzilishidan yo‘qotishlar | qarori kutilayotgan kamomad | E |
| 6010 / **6310** / 6390 | П | Mol yetkazib beruvchilar va pudratchilarga to‘lovlar / Xaridorlar va buyurtmachilardan olingan bo‘naklar / Boshqa olingan bo‘naklar | yetkazib beruvchi; o‘quvchi avansi; aniqlanmagan kirim | C, S, P |
| 6410 / 6520 / 6610* | П | Byudjetga to‘lovlar bo‘yicha qarzlar / Davlat maqsadli jamg‘armalariga to‘lovlar / To‘lanadigan dividendlar | JShDS va soliqlar; ijtimoiy soliq, INPS; dividend | TX, C |
| **6710** / 6720 | П | Ish haqi bo‘yicha xodimlar bilan hisob-kitoblar / Deponentlangan ish haqi | ish haqi | E |
| 6810* / 6820 / 7820* | П | Qisqa muddatli kreditlar / Qisqa muddatli qarzlar / Uzoq muddatli qarzlar | qarzlar | C |
| 6910 / 6970 / 6990 | П | To‘lanadigan operativ ijara / Hisobdor shaxslarga bo‘lgan qarzlar / Boshqa majburiyatlar | ijara; ortiqcha sarf; ushlanma, agentlik tushumi | C, E |
| 8330 / 8530 / 8710 / 8720 / 8840 / 8910* | П | Pay va ulushlar / Tekinga olingan mulk / Hisobot davrining taqsimlanmagan foydasi / Jamg‘arilgan foyda / Maqsadli foydalaniladigan soliq imtiyozlari / Kelgusi xarajatlar va to‘lovlar rezervlari | ustav; 8840 → 8530; natija; SK 483-modda maqsadli mablag‘i (FD-40); ta’til rezervi (FD-46) | — |
| 9020* / 9120* / **9030** / **9050** / 9130 | Т | Tovarlarni sotishdan daromadlar / Sotilgan tovarlarning tannarxi / Ishlar bajarish va xizmatlar ko‘rsatishdan daromadlar / Xaridorlar va buyurtmachilarga berilgan chegirmalar / Bajarilgan ish va ko‘rsatilgan xizmatlarning tannarxi | forma; o‘quv haqi; chegirma va grant; tannarx | SV, M, DT |
| 9220* / 9330* / 9360 / 9380* / 9390 | Т | Boshqa aktivlarning chiqib ketishi / Undirilgan jarima, penya va ustamalar / Kreditor va deponent qarzlarni hisobdan chiqarishdan daromadlar / Qaytarilmaydigan moliyaviy yordam / Boshqa operatsion daromadlar | boshqa daromad, kassa ortiqchasi | A |
| **9410 / 9420 / 9430** | Т | Sotish xarajatlari / Ma’muriy xarajatlar / Boshqa operatsion xarajatlar | davr xarajatlari, bank va ekvayring komissiyasi | A |
| 9530* / 9540* / 9610* / 9620* / 9690 / 9810* / 9820* | Т | Foiz daromadlari / Kurs farqidan daromad / Foiz xarajatlari / Kurs farqidan zarar / Moliyaviy faoliyat bo‘yicha boshqa xarajatlar / Foyda solig‘i bo‘yicha xarajatlar / Foydadan boshqa soliq xarajatlari | moliyaviy; 9810/9820 — faqat 8840 tartibida | TX |
| 9910 / 0000 | Т / texnik | Yakuniy moliyaviy natija / (BHMS 21 da yo‘q) | oy oxirida 8710 ga; boshlang‘ich qoldiq texnik hisobi (0 bo‘lishi shart) | — |
| 001 / 006 / 007 / 014 | БТ | Operativ ijaraga olingan asosiy vositalar / Qat’iy hisobdagi blankalar / Hisobdan chiqarilgan to‘lovga qobiliyatsiz debitorlar qarzi / Foydalanishdagi inventar | ijaradagi bino; «Қ» va kvitansiya daftarlari; hisobdan chiqarilgan qarz; inventar | — |

013 faqat maqsadli ishlatish talab qilinmaydigan imtiyozlar uchun (BHMS 21, 450-band) — maktab imtiyoziga emas.

### 4.3 Analitika
S o‘quvchi (kanonik `studentId`); P to‘lovchi turi (ota-ona / tashkilot / boshqa); E xodim (`payeeRef`); C kontragent
(`fin_counterparties`); K / B kassa / bank hisobi; CH kanal (pos, click, uzum, payme, qr, cash_in_transit); SV / M xizmat
va oy; DT chegirma turi (aka-uka, xodim farzandi, monitoring 20/100, grant, tavsiya, kontrakt — F2.7); A statiya; DEP
xarajat markazi (ta’lim / ma’muriyat / sotish-qabul, `staff.position`); TX soliq turi; FA asosiy vosita.

### 4.4 Statiyalar katalogi — to‘liq jadval [BUX, FD-10]
Qoidalar: bitta katalog — **IN** 7, **EX** 44, **OP** 24 (OP-23 texnik), jami **75**; statiya har KO-1/KO-2, bank, avans
hisoboti qatori va har foyda-zarar provodkasida majburiy; atributlar — tur, bitta standart hisobvaraq (ikki xarajat
markazi kerak bo‘lsa — ikki statiya), 2- va 4-shakl satri, eski toifa, ruxsat etilgan operatsiyalar, tasdiq, faollik;
ikkinchi tomon hujjatdan (KO-2 → Kt 5010, avans hisoboti → Kt 4230, vedomost → Kt 6710). **KO-2 da hech qachon:** EX-01…
EX-06, EX-44, EX-45, EX-47. EX-49 «Boshqa» izoh bilan, oylik qayta tasnif, maqsad ≤ 2 %. CF: O operatsion, I
investitsiya, F moliyaviy, Tax 4-shakl soliq bo‘limi; raqam — 4-shakl satri; «ichki» — pul hisoblari orasida.

| Kod | Nomi | Standart provodka | 2-shakl · CF |
|---|---|---|---|
| IN-01 | Ta’lim xizmati (oylik to‘lov) | hisoblash Dt 4010 Kt 9030; tushum Dt 5010/5110/5710 Kt 4010/6310 | 010 · O·010 |
| IN-02 | Tayyorlov kursi | IN-01 kabi | 010 · O·010 |
| IN-03 | Qo‘shimcha xizmatlar* | Dt 4010/5010 Kt 9030 | 010 · O·010 |
| IN-04 | Forma va boshqa tovarlar sotuvi | Dt 5010 Kt 9020 + Dt 9120 Kt 2910 (agentlik shartnomasi bo‘lsa Kt 6990) | 010 · O·010 |
| IN-05 | Chegirmalar va grantlar | Dt 9050 Kt 4010 (6310) | 010 (−) · — |
| IN-06 | Boshqa operatsion daromad (kassa ortiqchasi, hisobdan chiqarilgan qarz, jarima, beg‘araz yordam) | Kt 9390 / 9360 / 9330 / 9380 | 090 · O·040 |
| IN-07 | Moliyaviy daromad | Kt 9530 / 9540 | 130/150 · F·110; 221 |

| Kod | Nomi | Dt (Kt) | 2-shakl · CF |
|---|---|---|---|
| EX-01 | O‘qituvchilar ish haqi | 2010 (6710) | 020 · O·030 |
| EX-02 | Xizmat ko‘rsatuvchi xodimlar ish haqi | 2010 (6710) | 020 · O·030 |
| EX-03 | Ma’muriy xodimlar ish haqi | 9420 (6710) | 060 · O·030 |
| EX-04 | Qabul va marketing xodimlari ish haqi | 9410 (6710) | 050 · O·030 |
| EX-05 | Bir martalik mukofot, moddiy yordam | 9430 (6710) | 070 · O·030 |
| EX-06 | Ijtimoiy soliq | ish haqi xarajat hisobvarag‘i (6520) | 020/060/050 · Tax·200 |
| EX-07 | Xodimlar ovqati va ish kiyimi (soliq agenti belgisi) | 2010 (4230/5010) | 020 · O·020 |
| EX-08 | Xodim yollash va malaka oshirish | 9430 (6010/4230) | 070 · O·020 |
| EX-10 | Bino ijarasi | 2010 (6910/5110) | 020 · O·020 |
| EX-11 | Elektr energiyasi | 2010 (5110) | 020 · O·020 |
| EX-12 | Gaz va isitish yoqilg‘isi | 2010 (5110/4230) | 020 · O·020 |
| EX-13 | Suv, kanalizatsiya, chiqindi | 2010 (5110/4230) | 020 · O·020 |
| EX-14 | Internet va telefon | 9420 (5110) | 060 · O·020 |
| EX-15 | Joriy ta’mir va texnik xizmat | 2010 (4230/5110) | 020 · O·020 |
| EX-16 | Xo‘jalik va tozalash vositalari | 2010 (4230/5010) | 020 · O·020 |
| EX-17 | Qo‘riqlash va yong‘in xavfsizligi | 2010 (5110) | 020 · O·020 |
| EX-20 | Oziq-ovqat mahsulotlari | xarid 1010 (4230/5010/5110) → oylik chiqim dalolatnomasi 2010 (1010) [FD-31] | 020 · O·020 |
| EX-21 | Oshxona inventari va idishlar | 1080 → 2010 (+014) | 020 · O·020 |
| EX-22 | O‘quvchilar avtobusi (pudratchilar) | 2010 (5110/5010) | 020 · O·020 |
| EX-23 | Taksi, yetkazib berish, yo‘l kira | 9420 (4230/5010) | 060 · O·020 |
| EX-25 | Darsliklar va kitoblar | 1080 → 2010 (+014) | 020 · O·020 |
| EX-26 | O‘quv qurollari va laboratoriya* | 2010 (4230) | 020 · O·020 |
| EX-27 | Autsors o‘qitish (robototexnika va b.) | 2010 (5110) | 020 · O·020 |
| EX-28 | O‘quvchilar tadbirlari va bayramlar | 2010 (4230/5010) | 020 · O·020 |
| EX-29 | Olimpiada, imtihon, sertifikatlash | 2010 (5110/4230) | 020 · O·020 |
| EX-30 | Tibbiy xarajatlar | 2010 (4230) | 020 · O·020 |
| EX-31 | Elektron jurnal va o‘quv platformalari | 2010; oldindan 3120 (5110) | 020 · O·020 |
| EX-32 | Kanselyariya va chop etish | 9420 (4230/5010) | 060 · O·020 |
| EX-33 | Dasturiy ta’minot, xosting, ERI | 9420; oldindan 3120 (5110) | 060 · O·020 |
| EX-34 | Buxgalteriya xizmati (autsors) | 9420 (5110) | 060 · O·020 |
| EX-35 | Yuridik, audit, konsalting | 9430 (5110) | 070 · O·020 |
| EX-36 | Litsenziya, davlat boji, ruxsatnomalar | 9420 (5110; naqd — 4230 orqali) | 060 · Tax·200 |
| EX-37 | Vakillik va yig‘ilishlar | 9420 (4230) | 060 · O·020 |
| EX-38 | Reklama | 9410 (5110/4230) | 050 · O·020 |
| EX-39 | Marketing xizmatlari | 9410 (5110) | 050 · O·020 |
| EX-40 | Bank komissiyasi | 9430 (5110) | 070 · O·040 |
| EX-41 | Ekvayring va to‘lov tizimlari komissiyasi | 9430 (5710[CH]) | 070 · O·040 |
| EX-42 | Homiylik va xayriya | 9430 (5010/5110) | 070 · O·040 |
| EX-43 | Jarima va penyalar | 9430 (6410/6990) | 070 · O·040 |
| EX-44 | Eskirish va amortizatsiya | 2010/9420 (02xx/0530) | 020/060 · — |
| EX-45 | Umidsiz qarz, kamomad, yo‘qotish (soliq agenti belgisi) | 9430 (4910/4010/5910/4730) | 070 · — |
| EX-46 | Moliyaviy xarajatlar | 9610/9620/9690 | 180/200/210 · F·110; 221 |
| EX-47 | Soliq imtiyozi bo‘yicha hisoblangan soliq (8840 ga) | 9430/9810/9820 (6410) | 070/250/260 · — |
| EX-49 | Boshqa xarajatlar (izoh majburiy) | 9430 | 070 · O·040 |

| Kod | Nomi | Provodka | CF |
|---|---|---|---|
| OP-01 | Bankdan naqd olish | Dt 5010 Kt 5110 (+ EX-40 bank tomonida) | ichki |
| OP-02 | Bankka topshirish | Dt 5710 Kt 5010 → Dt 5110 Kt 5710 | ichki |
| OP-03 | Ekvayring / Click / Uzum hisob-kitobi | Dt 5110 + Dt 9430 (EX-41) Kt 5710 | ichki |
| OP-04 | O‘z hisoblari, kassalar, karta o‘rtasida | Dt 5530/5010 Kt 5110/5010 | ichki |
| OP-05 | Valyuta ayirboshlash | Dt 5010/5110 Kt 5020/5210 | ichki |
| OP-06 | Hisobdor shaxsga avans | Dt 4230/4220/4290 Kt 5010/5110/5530 | O·040 |
| OP-07 | Hisobdor bilan hisob-kitob | Dt 5010 Kt 4230; Dt 6970 Kt 5010 | O·040 |
| OP-08 | Ish haqi avansi | Dt 4210 Kt 5010/5110 | O·030 |
| OP-09 | Ish haqi to‘lovi (naqd, karta, deponent) | Dt 6710/6720 Kt 5010/5110 | O·030 |
| OP-10 | Ushlanmalarni o‘tkazish | Dt 6710 Kt 6990 → Dt 6990 Kt 5110 | O·030 |
| OP-11 | Ish haqi ↔ o‘quv to‘lovi o‘zaro hisobi | Dt 6710 Kt 4010/6310 | — |
| OP-12 | JShDS va INPS (faqat bank) | Dt 6410 / 6520 Kt 5110 | O·030 |
| OP-13 | Ijtimoiy soliq (faqat bank) | Dt 6520 Kt 5110 | Tax·200 |
| OP-14 | Boshqa soliqlar; soliq qaytimi (faqat bank) | Dt 6410 Kt 5110; Dt 5110 Kt 6410/4410 | Tax·200 |
| OP-15 | Ota-onaga qaytarish | Dt 6310/4010 Kt 5010/5110/5710 | O·010 (−) |
| OP-16 | Aniqlanmagan tushum va biriktirish | Dt 5010/5110/5710 Kt 6390 → Dt 6390 Kt 4010/6310 | O·010 |
| OP-17 | Yetkazib beruvchilar bilan hisob-kitob | Dt 4310/4330/6010/6910 Kt 5110/5010 | O·020 |
| OP-18 | Asosiy vosita, nomoddiy aktiv, ijaradagi binoga qo‘yilma | Dt 0820/0830/0870 Kt 5010/5110/4230 | I·060/070 |
| OP-19 | So‘mdagi qarz olish / qaytarish | Dt 5010/5110 Kt 6820/6810/7820 (va teskari) | F·150 |
| OP-20 | Ta’sischi: ustav hissasi; dividend | Dt 5110 Kt 4610; Dt 6610 Kt 5110 | F·130/120 |
| OP-21 | Rahbar yoki ta’sischiga berilgan pul | Dt 4290 (xodim) / 4890 (ta’sischi) Kt 5010 | O·040 |
| OP-22 | Xodimlar bilan boshqa hisob-kitob (qarz, zarar, kamomad) | Dt 4720/4730 Kt 5010 va teskari | I·090 / O·040 |
| OP-23 | Boshlang‘ich qoldiq (texnik) | balans hisobvarag‘i ↔ 0000 | — |
| OP-24 | Sotish uchun tovar xaridi | Dt 2910 Kt 6010/5010/4230 | O·020 |

**Moslik — tizimdagi 21 toifa (admin.html:9086):** Maosh → hisoblash EX-01…EX-04, to‘lov OP-09/OP-08 (`payroll__` —
hisoblash, naqd emas); Soliq → OP-12…14; Bank → EX-40 (topshirish — OP-02); Ijara EX-10; Avtobus EX-22; Oziq-ovqat
EX-20; Kommunal EX-11/12/13; Xo‘jalik tovarlari EX-16; Kanselyariya EX-32; Med chiqim EX-30; Kitoblar EX-25; Hayriya
EX-42; Boshqa → bo‘linadi, qoldig‘i EX-49; Ta‘mir EX-15 (bino yaxshilash OP-18); Inventar EX-21/EX-16 yoki OP-18;
Outsource EX-34; Marketing EX-38/39; Qaytarilgan OP-15; Korporativ karta OP-04/OP-06 (toifa olinadi); Dasturiy ta‘minot
EX-33 (EX-31, OP-18); IT-PARK — buxgalter belgilaydi. **Tracker 13 toifasi:** Oylik OP-09/08/11; Kommunal EX-11…14;
Oziq ovqat EX-20 (+EX-07, EX-37); Transport EX-22/23; Akademik EX-25/26/29; Marketing EX-38/39; Outsource EX-34/27/17;
Ta’minot EX-15/16/21; HR EX-08; Administratsiya EX-32/14/37; Soliqlar OP-12…14; Asosiy vosita OP-18; Boshqa — bo‘linadi
(topshirish OP-02, qaytarish OP-15, forma OP-24, qoldig‘i EX-49). Zavxoz maqsadlari va bankdagi 35 ta to‘lov maqsadi
namunasi uchun taklif qoidalari F2.6 va F3.3 da.

### 4.5 Kassa operatsiyalari katalogi [BUX, FD-11]
| Operatsiya | Shakl | Nomi | Dt | Kt | Statiya | Ruxsat / yaratadi | Bosq. |
|---|---|---|---|---|---|---|---|
| `in_tuition` | KO-1 | O‘quv haqi (naqd) | 5010 | 4010 + 6310 | IN-01/02 | «💵 To‘lov» dan avtomatik; fiskal chek № | 1a |
| `in_bank` | KO-1 | Bankdan naqd | 5010 | 5110 | OP-01 | kassir | 1a |
| `in_acc_return` | KO-1 | Hisobdordan qaytim | 5010 | 4230 | OP-07 | kassir | 1a |
| `in_staff_return` | KO-1 | Xodim qaytargan pul | 5010 | 6710 / 4210 | OP-09/08 | kassir | 1a |
| `in_sale` | KO-1 | Forma va tovarlar | 5010 | 9020 (+ Dt 9120 Kt 2910) | IN-04 | kassir; fiskal chek № | 1a |
| `in_other` | KO-1 | Boshqa kirim | 5010 | 9390 / 6390 (noma’lum) | IN-06 / OP-16 | kassir; izoh majburiy | 1a |
| `in_funding` | KO-1 | Qarz / ta’sischi mablag‘i | 5010 | 6820 / 4610 | OP-19/20 | direktor ruxsati | 1a |
| `in_surplus` | KO-1 | Kassa ortiqchasi | 5010 | 9390 | IN-06 | tizim, kun yopishda | 1a |
| `out_expense` | KO-2 | Xarajat | statiya hisobvarag‘i | 5010 | EX (ruxsat ro‘yxati), OP-17/18/24 | 2-ro‘yxat; > T1 direktor; oluvchi kontragent; asos hujjatisiz ≤ L1, bitta statiya | 1a |
| `out_salary` | KO-2 | Ish haqi | 6710 | 5010 | OP-09 | to‘lovdan avtomatik; tasdiqlangan vedomost va to‘lov qaydnomasi | 1a |
| `out_advance` | KO-2 | Ish haqi avansi | 4210 | 5010 | OP-08 | avans shaklidan; 2-ro‘yxat | 1a |
| `out_accountable` | KO-2 | Hisobdorga avans | 4230 | 5010 | OP-06 | 2-ro‘yxat | 1a |
| `out_refund` | KO-2 | Qaytarish | 6310 / 4010 | 5010 | OP-15 | direktor tasdiqlagan qaytarish; ariza | 1a |
| `out_bank` | KO-2 | Bankka topshirish | 5710 | 5010 | OP-02 | 2-ro‘yxat | 1a |
| `out_handover` | KO-2 | Rahbar / ta’sischiga | 4290 / 4890 | 5010 | OP-21 | direktor; oluvchi turi majburiy; xarajat emas | 1a |
| `out_shortage` | KO-2 | Kassa kamomadi | 5910 | 5010 | OP-22 | tizim, kun yopishda; qaror — direktor | 1a |
| `out_loan_repay` | KO-2 | So‘mdagi qarzni qaytarish | 6820 | 5010 | OP-19 | direktor | 1a |
| `out_overspend` | KO-2 | Ortiqcha sarfni qoplash | 6970 | 5010 | OP-07 | tasdiqlangan avans hisobotidan | 2 |
| `nc_offset` | dalolatnoma | O‘zaro hisob | 6710 | 4010 / 6310 | OP-11 | yozma ariza + direktor; KO-4 da emas | 1a |
| `nc_opening` | dalolatnoma | Boshlang‘ich qoldiq | 5010 / 4230 | 0000 | OP-23 | komissiya; buxgalter; direktor | 1a |
| `nc_adv_report` | AO | Avans hisoboti | statiya hisobvaraqlari | 4230 | EX / OP-24 | tasdiqlovchi ≠ yaratuvchi | 2 |

Kassadan soliq to‘lash operatsiyasi yo‘q. Kassa qismi hisobvaraqlari ishga tushirishdan oldin tasdiqlanadi (G2) — «bo‘sh
qoldirib keyin to‘ldirish» yo‘q; xarita o‘zgarsa faqat yangi hujjatlarga ta’sir qiladi.

### 4.6 Provodka qoidalari — to‘liq jadval
Kelishuvlar: yozuv = sarlavha + ≥ 2 qator, Σ Dt = Σ Kt; manba kaliti `(sourceTable, sourceId, kind, version)`; 5010 /
5110 / 5530 / 5710 / 9xxx / 2010 qatorlarida statiya; qulflangan kun yoki oyga yozuv yo‘q; tuzatish — ochiq davrda
storno, qulflangan davrga bugungi sana bilan teskari yozuv [BUX, FD-20]. Hech qachon provodka qilinmaydi:
`payroll__YYYY-MM` qatori; pending / prepared / created / canceled / reversed / refunded to‘lovlar; `reattr` va bo‘lingan
to‘lov bolalari naqd sifatida; fakturadagi `credit` / `cash` provayderi; moliya auditining `fix_` yo‘li. Manba: NEW —
yangi hujjat; AUTO — mavjud hodisa (sverka-provodkachi); BANK — ko‘chirma; MAN — buxgalter jurnali. Bosqich: hujjat /
bosh kitob.

| ID | Hodisa | Dt | Kt | Manba · bosq. |
|---|---|---|---|---|
| PR-01 | O‘quv haqi hisoblash (birinchi hisoblangan kun) | 4010 | 9030 (yalpi; prorata — kamroq daromad) | AUTO · 4 |
| PR-02 | Chegirma turi bo‘yicha | 9050 | 4010 | AUTO (F2.7) · 4 |
| PR-03 | 100 % grant | 9050 | 4010 | AUTO · 4 |
| PR-04 | To‘lovdan keyingi chegirma; bemor kuni krediti | 9050; bemor kuni — 9030 storno [FD-32] | 4010 (6310) | AUTO · 4 |
| PR-05 | Boshqa sababli qayta narxlash | 4010 / 9030 | 9030 / 4010 | AUTO · 4 |
| PR-06 | To‘lanmagan faktura bekor / o‘chirildi | PR-01/02 storno | | AUTO · 4 |
| PR-07 | Naqd o‘quv haqi (`in_tuition`) | 5010 | 4010 (boshlangan davr) + 6310 (ortiqcha, kelgusi oy) | NEW · 1a / 4 |
| PR-08 | Avans fakturaga qo‘llandi | 6310 | 4010 | AUTO; KO-1 dagi naqdsiz qator · 1a / 4 |
| PR-09 | POS to‘lovi | 5710[pos] | 4010 / 6310 | AUTO · 4 |
| PR-10 | Click / Uzum (yakunlangan sana) | 5710[CH] | 4010 / 6310 | AUTO (F3.1) · 4 |
| PR-11 | Ota-onadan bank o‘tkazmasi | 5110 | 4010 / 6310 | BANK · 3 / 4 |
| PR-12 | Ekvayer hisob-kitobi | 5110 (sof) + 9430[EX-41] | 5710 (yalpi) | BANK · 3 / 4 |
| PR-13 | Aniqlanmagan tushum (naqd ham), biriktirish | 5010/5110/5710; 6390 | 6390; 4010/6310 | AUTO / `in_other` · 1a / 4 |
| PR-14 | Ish beruvchi to‘lagan o‘quv haqi | 5110 | 4010/6310 [P = tashkilot] | BANK · 3 / 4 |
| PR-15 | Naqd qaytarish (`out_refund`, to‘lov sanasi) | 4010 / 6310 | 5010 | NEW · 1a / 4 |
| PR-16 | O‘tkazma / karta / provayder qaytarishi | 4010 / 6310 | 5110 / 5710 | AUTO · 3 / 4 |
| PR-17 | Talab qilinmagan avans (muddat o‘tgan) | 6310 | 9390 | MAN · 4 |
| PR-18 | Undirib bo‘lmaydigan o‘quv haqi (+007; moddiy naf belgisi) | 9430 / 4910 | 4010 | MAN · 4 |
| PR-19 | Avansni o‘quvchilar o‘rtasida ko‘chirish | 6310[S1] | 6310[S2] | AUTO · 4 |
| PR-20 | `add_credit` / direktor tuzatmasi | — avtomatik emas; sabab bilan MAN | | MAN · 4 |
| PR-21 | Moliya auditi «Qo‘llash» | 6390 / 6310 | 4010 | MAN; hech qachon Dt 5010 · 4 |
| PR-22 | O‘zaro hisob (`nc_offset`) | 6710 | 4010 / 6310 | NEW · 1a / 4 |
| PR-23 | Ortiqcha to‘lov (D9) | 5010/5110/5710 | 6310 | NEW / AUTO · 1a / 4 |
| PR-24 | Maosh hisoblash — maosh oyining oxirgi kuni | 2010 / 9420 / 9410 | 6710 | AUTO (qayta ochilsa storno + versiya) · 4 |
| PR-25 | JShDS (stavka sozlamadan; SK 381; 378-16 ariza va xorijiy o‘qituvchilar chiqariladi) | 6710 | 6410 | FD-38 dan keyin AUTO, aks holda MAN · 4 |
| PR-26 | INPS JShDS ichida (ro‘yxat 3577, 3-band; stavka manbasi tasdiqlanmagan) | 6410 | 6520 | PR-25 kabi · 4 |
| PR-27 | Ijtimoiy soliq (SK 405; xorijiy o‘qituvchilar — 483-modda 68-qism) | PR-24 xarajat hisobvarag‘i | 6520 | PR-25 kabi · 4 |
| PR-28 | Naqd maosh (`out_salary`) | 6710 | 5010 | NEW · 1a / 4 |
| PR-29 | Kartaga maosh | 6710 | 5110 | BANK · 3 / 4 |
| PR-30 | Maosh avansi (`out_advance`); MC-2 da yopiladi | 4210 | 5010 / 5110 | NEW · 1a / 4 |
| PR-31 | 3 ish kunidan keyin olinmagan ish haqi | 6710 | 6720 | MAN · 4 |
| PR-32 | Sud qarori bo‘yicha ushlanma | 6710; 6990 | 6990; 5110 | MAN / BANK · 4 |
| PR-33 | JShDS + INPS, ijtimoiy soliq o‘tkazildi | 6410; 6520 | 5110 | BANK · 3 / 4 |
| PR-34 | Qaytarilmagan hisobdor puli ish haqidan (rozilik bilan) | 6710 | 4230 | MAN · 4 |
| PR-35 | Xarid uchun avans (`out_accountable`) | 4230 / 4220 / 4290 | 5010 | NEW · 1a / 4 |
| PR-36 | Avans hisoboti qatori | 1010/1080/1090/2010/94xx/0820/2910 | 4230 | NEW · 2 / 4 |
| PR-37 | Qaytim (`in_acc_return`) | 5010 | 4230 | NEW · 1a / 4 |
| PR-38 | Ortiqcha sarf; qoplash | xarajat; 6970 | 6970; 5010 | AO / KO-2 · 2 / 4 |
| PR-39 | Korporativ karta: to‘ldirish; sarf | 5530 (4230); 4230 | 5110; 5530 | BANK / AO · 3 / 4 |
| PR-40 | Ijara: hisoblash; to‘lov; oldindan (+001) | 2010; 6910; 3110 | 6910; 5110; 5110 | MAN / BANK · 4 |
| PR-41 | Kommunal va xizmatlar | statiya hisobvarag‘i (6010) | 5110 / 5010 (6010) | BANK / KO-2 / MAN · 1a–4 |
| PR-42 | Oziq-ovqat: xarid; oylik chiqim dalolatnomasi; choraklik inventarizatsiya [FD-31] | 1010; 2010 | 4230/5010/5110; 1010 | AO / KO-2 / MAN · 1a–4 |
| PR-43 | Kitob, kanselyariya, xo‘jalik, kichik inventar | 1080/1090/2010/9420 (+014) | 4230/5010/5110 | AO / KO-2 · 1a–2 |
| PR-44 | Yetkazib beruvchiga oldindan to‘lov va hisob | 4310/4330; 6010 | 5110/5010; 4310/4330 | MAN · 4 |
| PR-45 | Asos hujjatisiz naqd xarid (≤ L1, bitta statiya) | statiya hisobvarag‘i | 5010 | NEW · 1a / 4 |
| PR-46 | QQS yo‘q (SK 243-modda 10-band; 267-modda — tannarxda) | — | — | — |
| PR-47 | Kapital qo‘yilma; topshirish (0870 o‘zida qoladi [BUX]) | 0820/0830/0870; 01xx/0430 | 5010/5110/4230; 0820/0830 | KO-2 / AO / MAN · 1a / 4 |
| PR-48 | Eskirish | 2010 / 9420 | 02xx / 0530 | MAN (MC-3) · 4 |
| PR-49 | Bankdan naqd (`in_bank`) + komissiya | 5010; 9430 | 5110; 5110 | NEW + BANK · 1a / 3 |
| PR-50 | Bankka naqd (`out_bank`), bank kirimi | 5710; 5110 | 5010; 5710 | NEW + BANK · 1a / 3 |
| PR-51 | O‘tkazma komissiyasi | 9430 | 5110 | BANK · 3 |
| PR-52 | Kassadan kassaga (faqat ikkinchi kassa bo‘lsa) | 5010[K2] | 5010[K1] | NEW · — |
| PR-53 | Soliq qaytimi | 5110 | 6410 / 4410 | BANK · 3 |
| PR-54 | So‘mdagi qarz olindi / qaytarildi | 5010/5110 ↔ 6820/6810/7820 | | KO-1 / KO-2 / BANK · 1a |
| PR-55 | Valyutadagi majburiyat va qayta baholash (FD-42) | 5020/6820; 9540/9620 | | MAN · 4 |
| PR-56 | Ustav kapitaliga hissa | 4610; 5110 | 8330; 4610 | MAN / BANK · 4 |
| PR-57 | Dividend: e’lon; JShDS; to‘lov | 8710 (joriy yil) / 8720 (o‘tgan yillar); 6610; 6610 | 6610; 6410; 5110 | MAN · 4 |
| PR-58 | Rahbar / ta’sischiga naqd (`out_handover`) | 4290 / 4890 | 5010 | NEW; shu oyda tasnif; xarajat emas · 1a / 4 |
| PR-59 | Kassa ortiqchasi (kun yopishda) | 5010 | 9390 | NEW · 1a / 4 |
| PR-60 | Kassa kamomadi (kun yopishda); direktor qarori | 5910; qaror: 4730 (yozma rozilik yoki to‘liq moddiy javobgarlik) / 9430 (aybdor yo‘q) | 5010; qaror: 5910 | NEW · 1a / 4 |
| PR-61 | Oziq-ovqat / material kamomadi (inventarizatsiya) | 5910 → 4730 / 9430 | 1010 / 1090 | MAN · 4 |
| PR-62 | Forma: xarid; sotuv; tannarx | 2910; 5010; 9120 | 6010/5010/4230; 9020; 2910 | KO-2 / KO-1 · 1a / 4 |
| PR-63 | SK 483-modda imtiyozi: shartli soliq; 8840; davr tugaganda [FD-40] | 9430/9810/9820; 6410; 8840 | 6410; 8840; 8530 | MAN (MC-12) · 4 |
| PR-64 | Kelgusi davr xarajatlarini hisobdan chiqarish | 2010 / 9420 | 3110/3120/3190 | MAN (MC-4) · 4 |

**Oy yopish (4-bosqich; qayta bajarilsa natija o‘zgarmaydi) [BUX, FD-39]:** MC-1 to‘liqlik (manbalar o‘tkazilgan, ochiq
kun va raqam bo‘shlig‘i yo‘q, manfiy kassa yo‘q, 5710 ≤ T+3 yoki izohlangan, bank satrlari, oylik sanash dalolatnomasi,
vedomost tasdiqlangan yoki vaqtinchalik hisoblash, rahbar/ta’sischiga berilganlar tasniflangan, 5910 qarorlari, muddati
o‘tgan 4230/4290 izohlangan); MC-2 Dt 6710 Kt 4210 (PR-24 dan keyin); MC-3 eskirish; MC-4 kelgusi davr xarajatlari;
MC-5 maosh soliqlari (yo‘q bo‘lsa); MC-6 taqdimot qayta tasnifi (4010 kredit → 6310; 6410/6520 debet → 4410/4520; 6010
debet → 43xx; 1-kuni teskari); MC-7 Dt 9130 Kt 2010; MC-8 Dt 9030 Kt 9050; MC-9 daromadlar → 9910; MC-10 9910 →
xarajatlar; MC-11 9910 → 8710 (yil oxirida 8710 → 8720); MC-12 8840 va maqsadli foydalanish reyestri; MC-13 qulf
(faqat direktor sabab bilan ochadi; kechikkan Click/Uzum qaytarishlari — joriy davrga tuzatma). Sintetik oy modeli
(63 yozuv) barcha tekshiruvlardan o‘tgan (balans, 5710 kanal bo‘yicha, 9xxx = 0, 2-shakl = MC-11, aktiv = passiv +
kapital, KO-4 = sanalgan) va F4.3 da SQL testiga aylanadi.

### 4.7 Kassa jarayoni
**Kun holatlari:** (yo‘q) → ochiq (birinchi hujjat bilan, oldingi harakatli kun yopilgan bo‘lsa) → yopilgan (sanashdan
keyin) → tekshirilgan (2-ro‘yxat). Direktor faqat oxirgi yopilgan, tekshirilmagan kunni, keyin hujjat bo‘lmasa, qayta
ochadi. **Invariantlar (bazada):** I1 bitta ochiq kun; I2 kun faqat oldingi kun yopilgan bo‘lsa ochiladi; I3 kun boshi =
kecha kun oxiri; I4 kun oxiri = boshi + kirim − chiqim; I5 kun oxiri ≥ 0 (kassa qulfi ostida); I6 tekshirilgan kun
o‘zgarmaydi. Harakatsiz kunda varaq yo‘q.

**Kassirning kuni** (faqat mavjud komponentlar: `.page-head`, `.card`, `.tablewrap table`, `.btn`, `.chip`, `#modal`)
| Payt | Ekran | Avtomatik | Kiritiladi |
|---|---|---|---|
| Ertalab | «Kassa» kun kartasi | sana, kun boshi, holat, ogohlantirishlar (kecha ochiq, oflayn yozuvlar, to‘lanadigan qaytarishlar, tasdiq kutayotgan KO-2, limit) | kecha ochiq bo‘lsa — sanab yopish |
| O‘quv to‘lovi | «💵 To‘lov» (mavjud shakl) | KO-1 raqami, sana, Kt taqsimoti, asos; KO-1 + patta chop | o‘quvchi, summa, to‘lovchi, **fiskal chek №** |
| Boshqa kirim | «Kassa» → «+ Kirim» | raqam, Dt/Kt, statiya, shablon | kimdan (tur + tanlash), summa, asos |
| Chiqim | «Kassa» → «+ Chiqim» → so‘rov → tasdiq → to‘lash | Dt/Kt, maosh chegarasi, avans qulfi, manfiy qoldiq rad, tasdiqsiz «To‘lash» faol emas | statiya, oluvchi, summa, asos hujjati |
| Xato | «Bekor» (shu kun) | raqam saqlanadi, «БЕКОР ҚИЛИНГАН», o‘quv to‘lovi taqsimoti teskari, xabarnoma bekor | sabab |
| Kechqurun | «Kunni yopish» | hisobdagi qoldiq, oxirgi raqamlar, navbatdagi yozuvlar, farq → shu kun 5910/9390 hujjati va dalolatnoma; varaqlar muzlatiladi; KO-4 2 nusxa | sanalgan summa yoki nominallar; izoh; komissiya imzosi |
| Tekshiruv | «✅ Tasdiqlash» → «Kassa: tekshirish» | KO-4 dagi tekshiruvchi qatori (sonlar so‘z bilan) | «qog‘oz va ilovalar olindi» |
| Direktor | Telegram + «Kassa: qaror va qayta ochish» | kassa bloki va nazorat qatori | kamomad qarori, qayta ochish, kech kiritish |

**Oflayn va kech kiritish.** (1) Internet uzilsa o‘quv to‘lovi outbox’ga yoziladi; tizim to‘lovchiga varaqa bermaydi —
dalil NKM oflayn cheki (48 soatda operatorga; VM 943, 1-ilova, 31-band); KO-1 sinxronlashdan keyin. (2) Yozuv
`capturedAt` ni saqlaydi (server tekshiradi: ≤ 48 soat). (3) Olingan kun hali ochiq bo‘lsa — o‘sha kunga; yopilgan bo‘lsa —
joriy ochiq kunga, o‘sha kun sanashidagi «hali o‘tkazilmagan yozuvlar (soni, summasi)» qatoriga bog‘lanib (ikki marta
sanash va yarim tunda qotish yo‘q). (4) Boshqa qurilmadan yopilsa — topshirish-qabul dalolatnomasida qayd etiladi. (5)
Server ishlamasa — ichki qog‘oz «Қ» blankalari (006; to‘lovchiga berilmaydi), keyin direktor ruxsati bilan kech kiritish;
NKM ishlamasa — faqat soliq organida ro‘yxatdan o‘tgan maxsus kvitansiya daftari (33-band). (6) Bitta kassa, bitta
kompyuter, smenalar; har almashuvda topshirish-qabul sanashi (FD-16).

**Nazoratlar**
| № | Qoida | Bosq. |
|---|---|---|
| CT-01 | Kassa hujjati faqat server sanasi bilan, bugungi ochiq kunga; naqdsiz qo‘lda to‘lov 31 kun, lekin oxirgi yopilgan oydan oldinga emas | 1a |
| CT-02 | Kun boshi = kecha kun oxiri; birinchi kun — sanash dalolatnomasidan | 1a |
| CT-03 | Yopishda sanash majburiy; farq shu kun hujjatlashadi; varaqlar muzlaydi; xesh | 1a |
| CT-04 | Kecha yopilmaguncha bugun hujjat yo‘q (I2) | 1a |
| CT-05 | Tekshiruvchi ≠ o‘tkazuvchilar (RPC) va ≠ yopuvchi (CHECK); tizim hujjatlari hech kimni o‘tkazuvchi qilmaydi | 1a |
| CT-06 | Qayta ochish — faqat direktor, sabab bilan, oxirgi tekshirilmagan kun; qayta chop «АЛМАШТИРИЛДИ», eskisi bekor | 1a |
| CT-07 | KO-2 — to‘lovdan oldin 2-ro‘yxat tasdig‘i (≠ so‘rovchi); > T1, rahbarga berish, qarz — direktor ham; tasdiqlangan vedomost va qaytarish qo‘shimcha talab qilmaydi [BUX]; T1/L1 — faqat direktor | 1a |
| CT-08 | Naqd maoshni faqat kassir (favqulodda — direktor) to‘laydi | 1a / 1b |
| CT-09 | Naqd xarajat, maosh, avans faqat kassa RPC lari orqali; to‘g‘ridan-to‘g‘ri yozish yopilguncha har kuni moslik P1/P4/P5/P8 | 1a–2 |
| CT-10 | Raqam hisoblagichi — oxirgi qulf; noyob (kassa, tur, yil, raqam); bo‘shliq tekshiruvi | 1a |
| CT-11 | O‘zgarmaslik: UPDATE faqat RPC bayrog‘i bilan bekor qilish, DELETE yo‘q; yopilgandan keyin storno | 1a |
| CT-12 | Manfiy qoldiqli KO-2 rad etiladi — kassa eksklyuziv qulfi ostida | 1a |
| CT-13 | Limit (hujjat bo‘lmasa 0) — ogohlantirish; maosh puli 3 ish kuni — rasmiy (bank) ish kunlari taqvimi bo‘yicha [BUX] | 1a |
| CT-14 | Farq yopishda shu kun sanasi bilan 5910 / 9390 hujjati; komissiya imzolaydi; qaror — direktor | 1a |
| CT-15 | Oflayn: to‘lovchiga varaqa yo‘q; «hali o‘tkazilmagan» qatori; qurilma navbatida yozuv bo‘lsa yopish tugmasi bloklanadi (faqat UI) | 1a |
| CT-16 | `clientRef` noyob (takror yozuv yo‘q) | 1a |
| CT-17 | `postedAt = now()`, `createdBy = app.uid()` | 1a |
| CT-18 | `chlog_attach`; yopish / tekshirish / qayta ochish / bekor qilish faktlari ustunlarda | 1a |
| CT-19 | Oyning oxirgi ish kuni komissiya sanashi (BHMS 19, 5-band); birinchisi 31-dekabr | 1a / 2 |
| CT-20 | `sinov` kassa (o‘z hisoblagichlari, hisobotlarga kirmaydi) | 1a |
| CT-21 | Aholidan naqd KO-1 fiskal chek raqamisiz o‘tmaydi (istisno — direktor, jurnal, RP-06) | 1a |
| CT-22 | Har KO-1/KO-2 da tomon majburiy: tur + kalit; erkin matn faqat «boshqa» uchun, belgilanadi | 1a |
| CT-23 | Statiya ruxsat ro‘yxati (EX-01…06, 44, 45, 47 KO-2 da yo‘q) | 1a |
| CT-24 | `out_expense` oluvchisi xodim bo‘lolmaydi; asos hujjatisiz ≤ L1 va bitta statiya | 1a |
| CT-25 | 4230 / 4290 muddati RP-06 / RP-07 va Telegramda; rahbarga berilgan pul oy ichida tasniflanadi | 1a / 2 |
| CT-26 | Tasdiqlangan qaytarish 1 bank kunidan oshsa — ogohlantirish | 1a |
| CT-27 | 31.12 xeshli surati; yopilgan oyga orqaga yozish rad (42501, tizim mustasno); 2-bosqichda barcha pul jadvallari uchun oy qulfi | 1a / 2 |

### 4.8 Bank va yo‘ldagi pul
5110 — har bank hisobi; 5710 — har kanal (pos, click, uzum, payme, qr, cash_in_transit), har oy kanal bo‘yicha yopiladi.
1a: faqat `in_bank` / `out_bank` va kunlik «kanallar bo‘yicha pul» bloki; bankdan to‘langan xarajatlarni ishga
tushirishdan boshlab moliya menejeri «Buxgalteriya» shaklida usul va statiya bilan kiritadi. 3-bosqich: 2027-01-01 dan
ko‘chirma importi; naqd olish ↔ KO-1 (+komissiya), topshirish ↔ KO-2, o‘quv haqi ↔ payments, ekvayer — sof 5110,
komissiya 9430 (kutilgan stavka tekshiruvi), maosh, soliq, yetkazib beruvchi, karta; qo‘lda kiritilgan bank yozuvlari
bilan takror tekshiruvi.

### 4.9 Hisobdor shaxslar
Berish — KO-2 `out_accountable` (taxminiy maqsad statiyasi); qaytim — KO-1. Avans hisoboti (2-bosqich, «А-»): sana,
hujjat, yetkazib beruvchi, statiya, hisobvaraq, chek surati (yopiq bucket); tasdiqlovchi ≠ yaratuvchi; ortiqcha sarf →
6970 → `out_overspend`. Yanvar hisobotlari qog‘oz shablonda (F1.19), yanvar qulfidan oldin kiritiladi. Muddat ≤ 3 ish kuni,
karta — 10 [BUX, FD-14]; muddati o‘tsa ogohlantirish (bloklash — sozlama). Boshlang‘ich qoldiq — imzolangan
ma’lumotnomalardan (F0.7). Rahbar/ta’sischiga berilgan pul: xodim — 4290, ta’sischi — 4890; buxgalter shu oyda tasniflaydi:
dividend (qaror + JShDS ushlash, ushlanmasa majburiyat), hisobdan chiqarish (moddiy naf, SK 376-modda) yoki ish haqi;
hech qachon xarajat emas [FD-26].

### 4.10 Maosh
D2 o‘zgarmaydi: moliya menejeri tayyorlaydi → HR tasdiqlaydi → kassir to‘laydi. Shart (G3, F0.18):
`payrollApprovalFrom` (eng kechi 2026-12), takroriy maosh ID tuzatilgan, HR hisobi faol, noyabr vedomosti tizimda sinov
sifatida tasdiqlangan, dekabr vedomosti maosh kunidan oldin tasdiqlangan, FD-44 tasdig‘i. Oylik to‘lov qaydnomasi:
2-ro‘yxat tasdig‘i + direktor imzosi [BUX]; keyin har naqd to‘lov — mavjud darvoza bilan cheklangan har kishilik KO-2.
Darvoza o‘chiq bo‘lsa naqd maosh rad etiladi (istisno — har hujjat bo‘yicha direktor ruxsati, RP-06). Karta to‘lovini
moliya menejeri yozadi (KO yo‘q). O‘zaro hisob (`nc_offset`): yozma ariza + direktor; bitta RPC `salary_payments`
(offset) va `payments` (provider `offset`) yozadi, `apply_payment` ni chaqiradi; KO-4 da emas. Avanslar 4210 da, MC-2 da
hisoblashdan keyin yopiladi. `payroll__YYYY-MM` naqd ko‘rinishlardan chiqariladi (1a — ID filtri; 2 — `kind =
'accrual'`), 4-bosqichda xodim bo‘yicha oy oxiri sanali hisoblash bilan almashtiriladi. Soliqlar — FD-38.

### 4.11 Qaytarishlar
Direktor tasdiqlaydi (refund-rpc.sql:35-39) va usulni tanlaydi (standart — asl kanal); ariza sanasi va asl chek havolasi
yoziladi. Naqd: «To‘lanishi kerak» ro‘yxatida; kassir KO-2 `out_refund` bilan, to‘liq F.I.Sh. va yozma ariza ilova (VM
943, 1-ilova, 35–38-band); balans KO-2 sanasida o‘zgaradi; qaytarish cheki NKM da (6-bosqichgacha qo‘lda); 1 bank kunidan
oshsa ogohlantirish; oldin bankdan naqd olish shartmi — [BUX, FD-25]. Naqdsiz — hozirgidek. Qaytarish debitorlikni
tiklaydi yoki avansni yopadi; ko‘rsatilmagan xizmat — daromad storno; hech qachon xarajat emas. Avansning bir qismini
qaytarish (`refund_credit`) — kerak bo‘lsa (F2.11).

### 4.12 Davrni yopish
Kun: sanash → yopish → tekshirish. Oy (kassa): oxirgi ish kuni komissiya sanashi (INV-16, oxirgi KO raqamlari), KO-3,
statiya matritsasi, nazorat ro‘yxati; barcha pul jadvallari uchun oy qulfi (F2.8). Oy (bosh kitob): MC-1…MC-13 5-ish
kunigacha [BUX] (4-bosqich). Yil: 31-dekabr (yoki dekabrning oxirgi ish kuni) komissiya sanashi (oylik + yillik) =
tizimning boshlang‘ich qoldig‘i; qog‘oz daftarlarni yopish dalolatnomasi (006); 31.12 23:59 surati (F1.16); hisoblagichlar
1-yanvarda qayta boshlanadi; yillik inventarizatsiya (egasi — buxgalter): asosiy vositalar, materiallar, hisob-kitoblar
(solishtirish dalolatnomalari bilan), blankalar; bosh kitob boshlang‘ich qoldig‘i — sub-registrlar nazorat hisoblari
bilan solishtirilgach (F4.4); KO-4 varaqlari yil oxirida muqova va varaqlar soni guvohnomasi bilan tikiladi (F2.12).

### 4.13 Rollar va tasdiqlar
| Imkoniyat | Kassir / g‘aznachi | Moliya menejeri | Buxgalter (1b) | Direktor | HR |
|---|---|---|---|---|---|
| Kassa hujjatlarini ko‘rish | R | R | R | R | — |
| Naqd o‘quv to‘lovi; boshqa KO-1; KO-2 bo‘yicha pul berish; naqd maosh/avans | ✓ | — | — | favqulodda | — |
| Naqdsiz qo‘lda to‘lov | ✓ | ✓ | — | ✓ | — |
| KO-2 so‘rovi | ✓ | ✓ (1b dan) | — | ✓ | — |
| KO-2 tasdig‘i, 2-ro‘yxat (≠ so‘rovchi) | — | ✓ | ✓ | — | — |
| > T1, rahbarga berish, qarz; qaytarish; kamomad qarori; qayta ochish; kech kiritish | — | — | — | A | — |
| Oylik to‘lov qaydnomasi | — | ✓ (2) | ✓ (2) | A (1) | — |
| Karta to‘lovi; o‘zaro hisob | — / tayyorlaydi | ✓ / tayyorlaydi | — | ✓ / A | — |
| Shu kunning o‘zida bekor qilish | o‘zinikini | ✓ | ✓ | ✓ | — |
| Kunni yopish (sanash) | ✓ | o‘rniga, 2 kishilik dalolatnoma | — | o‘rniga, 2 kishilik dalolatnoma | — |
| Kunni tekshirish (≠ o‘tkazuvchi / yopuvchi) | — | ✓ | ✓ | ✓ | — |
| Storno; boshlang‘ich qoldiq; statiya va qoidalar | — | so‘raydi; —; R | ✓; kiritadi; ✓ | A; tasdiqlaydi; ✓ | — |
| T1, L1, limit, imzo ro‘yxatlari, boshlang‘ich raqamlar | — | — | — | ✓ | — |
| XLSX eksport | yo‘q (chop etadi) | ID bilan, ismsiz | ID bilan, ismsiz | to‘liq | — |
| Oylik vedomost (D2) | — | tayyorlaydi | R | ✓ | tasdiqlaydi |

O‘IBDO‘, marketing (faqat yig‘ma RPC), qabulxona va o‘qituvchilar kassa hujjatlarini ko‘rmaydi. 1b gacha KO-2 so‘rovini
kassir yaratadi, moliya menejeri tasdiqlaydi; moliya menejeri yo‘q kunlar uchun buyruq bilan ikkinchi 2-ro‘yxat shaxsi.
**Imzo ro‘yxatlari [BUX, FD-08]:** 1-ro‘yxat — direktor, buyruqdagi o‘rinbosar (moliya menejeri emas); 2-ro‘yxat — bosh
buxgalter (autsors ham), moliya menejeri; KO-1/pattadagi «Бош бухгалтер» qatorini kassada kim imzolashini buxgalter hal
qiladi; KO-2 — rahbar (1) + bosh buxgalter (2), turli shaxslar; «tasdiqlangan vedomost rahbar imzosi o‘rnini bosadi» —
faqat buxgalter tasdiqlasa. Buxgalter roli faqat asosiy rol, `is_staff` / `is_finance` ga kirmaydi (D6).

| RF | Huquq tuzatmasi | Dalil | Bosq. |
|---|---|---|---|
| RF-01 | Kassir xarajat yozmaydi va o‘chirmaydi | audit-3.sql:66-73; audit-4.sql:268-270 | 0 |
| RF-02 | Kassir `staff_advances` ga to‘g‘ridan-to‘g‘ri yozmaydi | audit-3.sql:87-93 | 0 |
| RF-03 | `add_credit` musbat summa — faqat direktor va server | add-credit.sql:36-42 | 0 |
| RF-04 | Kassir `apply_payment` ni to‘g‘ridan-to‘g‘ri chaqirmaydi: tranzaksiya bayrog‘i `iqror.money_rpc` yoki `apply_payment_core`; F0.15 dan bitta reliz keyin, majburiy qayta yuklash bilan | audit-7.sql:45-49, 121; invoice-guards.sql:219-236; split-payment.sql:84 | 0 |
| RF-05 | O‘IBDO‘ xarajat yozmaydi | audit-3.sql:66-71 | 0 |
| RF-06 | Qaytarish va maoshda `byUid` ni server qo‘yadi | refund-rpc.sql:75; admin.html:9074 | 0 |
| RF-07 | `credit_ledger` faqat qo‘shiladi | credit-ledger.sql:34 | 0 |
| RF-08 | Naqd to‘lov faqat kassa rollarida: UI — ishga tushirishda; RLS — toza haftadan keyin, orqaga qaytarish migratsiyasi bilan | admin.html:1460; audit-3.sql:76, 87-93 | 1a / 1b |
| RF-09 | To‘g‘ridan-to‘g‘ri payments yozuvi detektor haftasidan keyin yopiladi; «Bekor» va qo‘lda qaytarish RPC ga | cashier-role.sql:33-37; admin.html:9861, 11417-11422 | 2 |
| RF-10 | Faktura to‘lov maydonlari faqat bayroq bilan (webhook RPC lari ham; service_role testlari); `student_credit` — direktor | discount-approval.sql:480-496; audit-9.sql:22-30 | 2 |
| RF-11 | G‘aznachi = kassa operatori | reports-roles.sql:106-109 | 2 |
| RF-12 | Marketing faqat yig‘ma RPC | audit-3.sql:67 | 2 |

### 4.14 Raqamlash [BUX, FD-05]
| Seriya | Boshlanish | Ko‘rinish |
|---|---|---|
| KO1 / KO2 (kassa bo‘yicha, 1-yanvardan qayta) | ishga tushirishda 1 (B variantida — 2026 qog‘oz maksimumi + 1) | «№ 1234»; KO-4 da «К-1234» / «Ч-567» (rus «П-» / «Р-») |
| KO4 varaqlari | 1 | «Варақ N» |
| «Д-» dalolatnomalar; «ЎҲ-» o‘zaro hisob; «А-» avans hisoboti; «JV» jurnal | 1 | til bo‘yicha prefiks |
| `sinov` kassa | o‘z hisoblagichlari | «СИНОВ», hisobotlarga kirmaydi |

Raqamni server o‘tkazishda oxirgi qulf sifatida beradi; sequence va identity yo‘q; ajratish va yozish orasida
`exception when others` yo‘q; qoralama va so‘rovda raqam yo‘q; bekor qilingan raqamini saqlaydi; yil = ish kuni yili;
bo‘shliq tekshiruvi (`lastNo = count = max(no)`) tekshiruv va oy yopishni bloklaydi.

### 4.15 Chop etish (`printHTML`)
| Shakl | Qog‘oz | Mazmun | Bosq. |
|---|---|---|---|
| KO-1 + «ПАТТА» | A5 albom / A4 ning yuqori yarmi (132 + 6 + 56 mm); termal variant yo‘q | nom, STIR, joy; №, sana; Dt 5010 / Kt (4010 + 6310) analitika bilan; statiya «Мақсадли йўналиш белгиси» da; raqam va so‘z bilan summa; «Олинди», «Асоси», «Иловаси»; to‘lovchi, bosh buxgalter (2), kassir imzolari; **«Фискал чек №»**, pattada «Фискал чек эмас» | 1a |
| KO-2 | A5 kitob / A4 yarmi | qatorlar (Dt / analitika / statiya), Kt 5010; «Берилсин»; asos; ilova; rahbar (1) va bosh buxgalter (2); «Олдим» + so‘z bilan + imzo; shaxs hujjati qatori qo‘lda (saqlanmaydi) | 1a |
| KO-4 | A4, 20 mm tikish chetligi, varaqda qatorlar soni qat’iy | «КАССА {sana} учун», «Варақ N»; 1–5 ustunlar; kun boshi / jami / oxiri; «Шу жумладан»; sanalgan va farq; kassir; tekshiruvchi qatori; 2-nusxa «КАССИР ҲИСОБОТИ»; «АЛМАШТИРИЛДИ» | 1a |
| Sanash va topshirish-qabul dalolatnomalari, kunlik hisobot | A4 | komissiya, oxirgi raqamlar, nominallar, hisobdagi va sanalgan, o‘tkazilmagan yozuvlar, direktor qarori qatori | 1a |
| O‘zaro hisob dalolatnomasi; KO-3; yil muqovasi; avans hisoboti; ota-ona ma’lumotnomasi (QR) | A4 | — | 1b / 2 / 5 |

Sozlamalar (FD-07): o‘zbek kirill (rus bor, lotin — so‘rov bo‘yicha); «2027 йил 4 январь»; «1 234 567=89», nol «–»,
tegishli emas «X»; so‘z bilan — bosh harf, tiyin 2 raqam; belgilar «БЕКОР ҚИЛИНГАН», «НУСХА», «АЛМАШТИРИЛДИ», «СИНОВ»;
pastda hujjat ID, vaqt, foydalanuvchi; to‘lovchi hujjati termal printerda chiqmaydi, ichki termal varaqalarda «Фискал чек
эмас — ички ҳужжат». `sumWords` / `countWords` har tilda ≥ 30 misol bilan sinaladi.

### 4.16 Avtomatlashtirish xaritasi
| Mavjud oqim | Natija | KO-4 | Vazifa |
|---|---|---|---|
| Qo‘lda naqd to‘lov (admin.html:11784-11910) | payments + `apply_payment` + KO-1 bitta tranzaksiyada | ha | F0.15, F1.4 |
| Qo‘lda bank / terminal / Uzum | o‘sha atomar RPC, KO yo‘q | yo‘q | F0.15 |
| Click / Uzum webhook’lari | 1a da tegilmaydi; yakunlangan vaqt — 3-bosqich | yo‘q | F3.1 |
| Qaytarish (admin.html:11913-11967) | tasdiq → naqd bo‘lsa KO-2 | naqd | F1.6 |
| Maosh va avans (admin.html:8847-9084, 9423-9479) | naqd → KO-2; karta → yo‘q; o‘zaro hisob → `nc_offset` | naqd | F1.5 |
| Maosh hisoblash qatori (admin.html:9350-9420) | naqd emas; `kind = 'accrual'`; bosh kitob | yo‘q | F1.15, F2.4, F4.7 |
| Buxgalteriya xarajat shakli (admin.html:9305-9343) | naqd — faqat «Kassa» KO-2; naqdsiz — usul + statiya + kontragent | naqd | F1.13, F2.1 |
| Zavxoz puli; bankdan / bankka; rahbarga; forma; qarz | `out_accountable` / `in_acc_return`; `in_bank` / `out_bank`; `out_handover`; `in_sale`; `out_loan_repay` | ha | F1.4 |
| Biriktirish, bo‘lish, avans ko‘chirish | kassa hujjati yo‘q (bosh kitobda — 4) | yo‘q | F4.3 |
| Moliya auditi «Qo‘llash»; korporativ karta | naqd emas, provider `fix`; to‘ldirish + avans hisoboti | yo‘q | F2.9, F3.5 |
| Telegram `director_daily`; termal chek | filtr, kassa bloki, nazorat qatori; to‘lovchiga chek yo‘q | — | F0.12, F1.15, F1.13 |

**Qo‘lda qoladi:** kechki sanash va inventarizatsiya (qonun; tizim dalolatnomani tayyorlaydi); qog‘oz imzolar (ERI —
F6.2); fiskal chek raqamini kiritish (F6.1); bank satrlari va komissiyalar (F3.2–F3.4); bankdan to‘langan xarajatni
kiritish (F3.2 gacha); avans hisobotidagi ortiqcha sarf (F2.6 gacha); soliq provodkalari (F4.7 / F6.3); rahbarga berilganni
tasniflash va statutor hisobot topshirish (buxgalter).

**Statiya bo‘yicha to‘liqlik:** kassa xarajati — ishga tushirishdan; bankdan to‘langan xarajat — ishga tushirishdan
(qo‘lda), F3.2 dan import bilan; hisobdor xaridlari — F2.6 (yanvar qog‘ozda, qulfdan oldin kiritiladi); maosh — RP-09 da
2-bosqichdan (`payroll_lines` × lavozim), bosh kitobda 4-bosqichdan; karta va komissiya — 3-bosqich; eskirish va kelgusi
davr — 4-bosqich; 2026-yil noyabr–dekabr — F2.3 orqali, «qisman» belgisi bilan.

### 4.17 Texnik dizayn asoslari
- **Migratsiyalar** (`rls-initplan.sql` dan yuqorida, zanjir himoyasi, qayta bajariladigan, o‘z revoke’lari bilan):
  `fin-prereq.sql` (0), `fin-core.sql` + `kassa.sql` (1a), `fin-rights.sql` (1b / 2, orqaga qaytarish migratsiyalari
  bilan), `fin-exp.sql` (2), `fin-bank.sql` (3), `fin-gl.sql` (4). Mavjud funksiyalar o‘z faylida tahrirlanadi.
  Yordamchilar `is_accountant`, `fin_reader`, `kassa_reader`, `kassa_operator` — `v_fns` ga.
- **1a jadvallari:** `gl_accounts`, `fin_articles`, `fin_category_map`, `fin_op_rules`, `fin_org` (sozlamalar;
  T1/L1/limit — direktor), `fin_signatories`, `fin_counterparties` (minimal), `cash_desks`, `doc_counters`, `cash_docs`
  (tur, holat draft/approved/posted/void, kassa, yil, raqam, `businessDay`, `capturedAt`, tomon, asos hujjati,
  `fiscalNo`, `sourceSnapshot`, `reversalOf`, noyob `clientRef`, tasdiqlar), `cash_doc_lines` (statiya, hisobvaraq,
  summa, analitika, xarita versiyasi), `payment_allocations`, `cash_days` (qoldiqlar, sanalgan, farq, o‘tkazilmagan
  yozuvlar, `cashierUid`, xesh, kim yopgan/tekshirgan), `cash_day_events`, `cash_counts`, `fin_snapshots`; hammasida
  `id`. Eski jadvallarga faqat bo‘sh bo‘lishi mumkin bo‘lgan ustunlar (`cashDocId`, `statusAt`, `fiscalNo`,
  `articleId`, `method`, refund `status` va boshqalar).
- **Yozish:** faqat SECURITY DEFINER RPC (`search_path`, aniq rol); yozish siyosatlari yo‘q; eski qator va hujjat bitta
  tranzaksiyada; triggerlar faqat himoya qiladi, provodka qilmaydi; boshlang‘ich ma’lumot `ON CONFLICT DO NOTHING`.
- **Qulflar tartibi:** L0 `iqror_doc:<clientRef>` → L1 `iqror_pay:<kanonik sid>` → L2 maosh triggerlari → L3 biznes
  qatorlari → L4 `iqror_desk:<desk>` (eksklyuziv) → L5 `doc_counters` (oxirgi). Webhook’lar faqat L1–L3.
- **O‘quv KO-1:** L1 ostida surat → `apply_payment` → farq: 4010 / 6310 / naqdsiz 6310→4010; `payment_allocations`.
- **Bekor qilish:** rolsiz `app.tuition_reverse_core` (namuna — `app.reprice_invoice_core`), keyin pul harakati
  bo‘lmasa; `notify_queue` `'pay__<id>'` «skipped»; `kassa_void_replace` tavsiya bonusini yangi to‘lovga o‘tkazadi; maosh
  avansi qulflangan oyda — storno.
- **`createdAt`** (F0.14): tizim bo‘lmaganlar uchun `now()`, UPDATE da eski qiymat; tizim (webhook, Click prepare)
  mustasno. **Webhook’lar:** payments da faqat shu trigger va 2-bosqichda faqat jurnal yozadigan detektor.
- **Bosh kitob (4):** yangi hujjatlar o‘z RPC sida; eski va onlayn manbalar deterministik sverka-provodkachi orqali
  (storno + versiya; qulflangan davr — joriy davrda tuzatma); provodka triggerlari yo‘q.
- **Test soati:** `app.fin_today()` faqat test bazasida saqlangan soatni o‘qiydi. **UI:** `assets/js/fin-kassa.js`,
  `fin-print.js`, `fin-words.js`, `fin-xlsx.js`; ro‘yxatga olish `buildTabs` (admin.html:1809-1842), `NAV_GROUPS`
  (1882), `ROLE_TABS` (1408-1411), `renderTab` (2029-2063); navbat stublari admin.html da; yangi CSS yo‘q; eksport —
  rol tekshiruvli RPC.

### 4.18 Hisobotlar katalogi
| ID | Hisobot | Bosq. |
|---|---|---|
| RP-01 | KO-4 kassa kitobi (kun / davr, 2 nusxa) | 1a |
| RP-02 | Kassirning kunlik hisoboti: kun boshi, KO-1 va KO-2 ro‘yxati, jamlar, kun oxiri, sanash va farq, statiya bo‘yicha, tomon bo‘yicha («kimdan / kimga qancha»), o‘tkazmalar, kanallar (ma’lumot), kutilayotganlar, limit | 1a |
| RP-03 / 04 | KO-3 jurnallari; kassa kitobi XLSX (FD-28) | 1b |
| RP-05 | Telegram kassa bloki + nazorat qatori (moslik, ochiq kunlar, bekor qilishlar, farqlar) | 1a |
| RP-06 | Nazorat ro‘yxati (ochiq / tekshirilmagan kunlar, bekor qilish, qayta ochish, farq va 5910, KO-1 siz naqd, tasdiq kutayotgan KO-2, eski qaytarishlar, oflayn, fiskal istisno, «boshqa» tomonlar, limit, raqamlash, 4230/4290 muddati) | 1a |
| RP-07 | Hisobdor kartochkasi (yosh — 2) | 1a–2 |
| RP-08 / 09 | Oy statiya matritsasi (kassa — ✅ 1b, `kassa_matrix`); barcha usullar bo‘yicha matritsa (o‘quv va kalendar yili, maosh taqsimoti) | 1b / 2 |
| RP-10 / 11 / 12 | Kontragent ko‘chirmasi; kanallar bo‘yicha pul; bank reyestri va 5710 qoldiqlari | 2 / 3 |
| RP-13…16 | Jurnal, OSV, kartochka va tahlillar; oylik eksport to‘plami E1–E8: kassa qismi E1–E4 (✅ 1b, F1.22 — KO-3, statiya matritsasi, kassa kunlari, hisobdorlar), bosh kitob qismi E5–E8 (jurnal, OSV, kartochkalar, tahlillar) | 4 |
| RP-17…21 | 1/2-shakl (FD-45 bo‘yicha 3/4 ham); BHMS 9 pul oqimi (230 + 220 + 221 = 240); hisoblash asosidagi matritsa; ota-ona ma’lumotnomasi; nazorat hisobotlari | 5 |
| RP-22 | Haftalik KPI (o‘z vaqtida yopilgan kunlar, tekshirilmagan, farqlar, EX-49 ulushi, muddati o‘tgan avanslar) — ✅ 1b, `kassa_kpi` | 1b |

---

## 5. Bosqichlar
**Mehnat va kalendar.** Hajm — mehnat, muddat emas. Mehnat: 0 ≈ 11,5 (+ ≈ 6 kun maktab tomonida); 1a ≈ 53; 1b ≈ 7,5;
2 ≈ 27,5; 3 ≈ 16,5; 4 ≈ 26; 5 ≈ 8,5; 6 ≈ 10,5; **jami ≈ 161 dasturchi-kun**. 0 + 1a ≈ 64 kun, 9-noyabr – 31-dekabr esa
45 ish kuni (Du–Sh, 8-dekabr va 1-yanvar bayram): bitta dasturchining odatiy tezligida sig‘maydi, reja shu repozitoriyda
kuzatilgan tezlikka tayanadi va darvozalar bilan himoyalanadi. **Yo‘l nazorati — 28-noyabr:** yadro (F1.1–F1.4) lokal
stendda boshidan oxirigacha ishlasa yanvar tasdiqlanadi, aks holda ishga tushirish 1-fevralga suriladi (boshlang‘ich
qoldiq — yanvar oxiridagi sanash).

| Darvoza | Shart | Muddat |
|---|---|---|
| G1 Fiskal | Har naqd va POS to‘lovga ro‘yxatdan o‘tgan NKM / virtual kassa (yozma); bo‘lmasa — ishga tushirishgacha ro‘yxatdan o‘tkazish | 12-dekabr |
| G2 Hisob siyosati | FD-04, 05, 07, 09…14, 20, 21, 26 tasdiqlangan | 21-noyabr (vaqtincha) / 12-dekabr |
| G3 Maosh | F0.18; FD-44 yozma; dekabr vedomosti maosh kunidan oldin tasdiqlangan | 19-dekabr / 31-dekabr |
| G4 Qabul sinovi | Kassir, moliya menejeri, buxgalter, direktor sinov stendida imzolagan | 26-dekabr |
| G5 Buyruqlar | F0.3 imzolangan | 12-dekabr |
| G6 Yil yakuni | 31.12 sanash, qog‘oz daftarlarni yopish, sozlamalar | 31-dekabr |

### 0-bosqich — Qarorlar, tayyorgarlik, oraliq qoidalar (9–28-noyabr)
Maqsad: 1a uchun qarorlar va siyosat, qarorga bog‘liq bo‘lmagan kod tuzatmalari, oraliq qoidalar, maosh va stend tayyorligi.

**Holat (2026-11-10, A relizi):** F0.1 bajarildi (egasi qarorlarni topshirdi, §6). Kodda bajarildi va lokal sinovdan
o‘tdi: F0.10 (`verify-db.sh` — trigger, cheklov, indeks), F0.11 (sinov to‘plami: `test-fin-prereq.sql`,
`test-fin-race.sh`, `test-fin-parity.cjs`; superuser bo‘lmagan zanjir egasi bilan to‘liq qurish lokalda mumkin emas —
Supabase event trigger’ni supautils orqali ruxsat beradi; deploy bitta tranzaksiyada bo‘lgani uchun xavfsiz), F0.12
(`app.counts_as_receipt`, `app.pay_day`, `app.fin_receipts`; `director_daily` + «kechikib kiritilgan» qatori), F0.13,
F0.14, F0.15 (`record_manual_payment`, admin outbox), F0.16 (RF-01, 02, 03, 05, 06, 07). F0.19 — `docs/moliya/oraliq-qoidalar.md`.
Mustaqil ko‘rikdan keyin: **F0.17 (RF-04) shu relizga kirdi** — `apply_payment` / `apply_to_invoice` musbat summani faqat
payments qatori, ichki RPC bayrog‘i, Direktor yoki server bilan qabul qiladi (eski mijozlar ishlayveradi, majburiy qayta
yuklash kerak emas); NaN / Infinity summalar barcha pul RPC’larida rad etiladi; `student_credit` — faqat RPC’lar orqali.
F0.18 (prod, faqat o‘qish): vedomost tasdig‘i 2026-12 dan yoqilgan; takroriy maosh ID 2 ta — tuzatilishi kerak; noyabr
vedomosti tizimda tayyorlanmagan. F0.3 — `docs/moliya/buyruq-namunalari.md`.

**Egasining javoblari (2026-11-10):** naqd va terminal to‘lovlari uchun ro‘yxatdan o‘tgan onlayn / virtual kassa (fiskal
chek) **bor** — G1 uchun yozma tasdiq (F0.5) qoldi; buxgalter — **maktab xodimi**, rejaning hisob qismini 21‑noyabrgacha
ko‘rib chiqadi (G2); kassa limiti bo‘yicha javob **yo‘q** (F0.4 ochiq — tizimda limit 0, ya’ni faqat ogohlantirish);
sinov nusxasi **yangi domen ochmasdan** — asosiy sayt manzilida, boshqa portda (standart 8443).

**F0.20 tayyor (`sinov/`):** `install.sh` / `update.sh` / `reset.sh` / `remove.sh` — alohida `iqror_sinov` bazasi, ikkinchi
PostgREST (faqat 127.0.0.1, o‘z JWT siri), kirish emulyatsiyasi bilan Node server, alohida nginx bloki; faqat to‘qima
ma’lumot; jonli baza, nginx sayt fayli va xizmatlarga tegmaydi (`--dry-run` bor). Soxta server muhitida (haqiqiy nginx,
Postgres, PostgREST) 107 stsenariy va brauzerda 39 tekshiruv o‘tdi; haqiqiy serverda hali ishga tushirilmagan — egasi
o‘rnatadi (`sinov/README.md`). Qoldi: maktab tomonidagi F0.2, F0.4–F0.8.

| ID | H | kun | Vazifa | Bog‘liq | Qabul mezoni |
|---|---|---|---|---|---|
| F0.1 | S | 0,5 | Qarorlar yig‘ilishi (egasi, MM, buxgalter, kassirlar); [BUX] vaqtincha qabul; kassa modeli | — | 14-noyabrda imzolangan |
| F0.2 | M | 2 | Hisob siyosati to‘plami (repozitoriydan tashqarida), hujjatlar aylanishi grafigi bilan | F0.1 | Kassa qismi 21-noyabr (G2) |
| F0.3 | S | 0,5 | Buyruqlar: imzo ro‘yxatlari; inventarizatsiya komissiyasi; o‘z shakllari; hujjatlar aylanishi grafigi; kassir va o‘rinbosar; to‘liq moddiy javobgarlik shartnomalari; ichki kassa nizomi | F0.1 | 12-dekabr (G5) |
| F0.4 | S | 0,5 | Kassa limiti (yanvarda bankka ma’lumotnoma) | — | Limit ma’lum |
| F0.5 | S | 0,5 | Fiskal holat: NKM / virtual kassa, IKPU, Click/Uzum/QR; VM 943, 4-band bo‘yicha yozma xulosa | — | Yozma javob (G1) |
| F0.6 | S | 0,5 | Ishga tushirish ma’lumotlari (nom, STIR, joy, imzolar, nominallar, printer) | F0.1 | Sozlamaga kiritiladi |
| F0.7 | S | 0,5 | Hisobdorlar qoldig‘i bo‘yicha imzolangan ma’lumotnomalar (31.12) | — | Imzolangan |
| F0.8 | S | 0,5 | Bank ko‘chirmasi namunasi | — | Olingan |
| F0.9 | S | 0,5 | Noyabr solishtiruvi (faqat o‘qish), ochiq masalalar — yopiq ilovaga | — | Topshirilgan |
| F0.10 | S | 0,5 | verify-db: trigger, cheklov, indeks izlari | — | Farqlar ro‘yxati |
| F0.11 | M | 2 | Lokal test bazasi: superuser bo‘lmagan zanjir egasi, PostgREST, saqlanadigan test soati, `test-kassa.sql`, parallel skript | — | Faqat ROLLBACK |
| F0.12 | S | 0,5 | Yagona kirim ta’rifi; `director_daily` tuzatmasi; JS↔SQL moslik | F0.11 | admin.html bilan bir xil |
| F0.13 | S | 0,5 | Indekslar (payments, staff_advances, expenses) | — | EXPLAIN |
| F0.14 | S | 0,5 | Server vaqtlari (`createdAt`, `statusAt`; tizim mustasno) | F0.11 | payments `npm test` yashil |
| F0.15 | M | 2 | `record_manual_payment` atomar RPC; outbox shu orqali | F0.14 | Yetim «pending» yo‘q; qayta yuborish «dup» |
| F0.16 | S | 0,5 | Huquqlar I: RF-01, 02, 03, 05, 06, 07 | F0.15 | Rol testlari |
| F0.17 | M | 2 | RF-04 (bayroq / core), bitta reliz keyin, majburiy qayta yuklash | F0.16 | Kassir assign/split ishlaydi; direktor yo‘llari ishlaydi |
| F0.18 | S | 0,5 | Maosh tayyorligi (G3): sozlama, ID takrori, HR hisobi, noyabr vedomosti tizimda | — | Noyabr tasdiqlangan |
| F0.19 | S | 0,5 | Oraliq qoidalar varag‘i (§8.3); Sheet funksiyalari inventari; Drive «faqat ko‘rish» sanasi | F0.1 | Tarqatilgan |
| F0.20 | M | 2 | Sinov va o‘qitish stendi (auth + REST + admin.html, sintetik ma’lumot, alohida kalitlar); UAT stsenariylari | F0.11 | Kassir to‘liq kunni o‘tkazadi; prod o‘qitishga ishlatilmaydi |

Foydalanuvchi: 16-noyabrdan oraliq qoidalar; Telegram jami kassa hisoboti bilan bir xil. Testlar: F0.11 to‘plami,
payments `npm test`, mavjud SQL to‘plamlari, rol testlari.

### 1a-bosqich — Kassa MVP (qurish 16-noyabr – 26-dekabr; jonli — yanvarning birinchi kassa kuni)
Maqsad: Excel kunlik varaqlari, qog‘oz orderlar va tracker kassa reyestri o‘rniga raqamlangan KO-1/KO-2, sanash bilan
yopiladigan kun, KO-4 chop etish, o‘tkazma va naqdsizni ajratish, Telegram.

**Holat (2026-11-10):** server yadrosi, «Kassa» ekranlari, chop etish shakllari va mavjud pul oqimlarining kassaga
ulanishi yozildi va lokal sinovdan o‘tdi — hali **faqat lokal sinov zanjirida** (`run-all.sql` da «--dev \ir»;
`chain.sh --dev`), jonli tizimga chiqmaydi. F1.1 `fin-core.sql` + `fin-seed.sql` (92 hisobvaraq, 75 statiya, 21 toifa
mosligi, 20 operatsiya qoidasi); F1.2 `kassa.sql` (jadvallar, I1–I6 va o‘zgarmaslik triggerlari, chop etish jurnali); F1.3
raqamlash va kassa qulfi; F1.4 `kassa-docs.sql` (KO-1, KO-2 so‘rov → tasdiq → to‘lash, bekor qilish, fiskal chek №) va
`kassa-pay.sql` (naqd o‘quv to‘lovi KO-1 bilan bitta tranzaksiyada, taqsimot 4010 / 6310); F1.5 naqd maosh
(`kassa_salary_pay`: maosh to‘lovi + KO-2 bitta tranzaksiyada, vedomost chegarasi; karta — KO siz) va ish haqi avansi
(«+ Chiqim so‘rovi» → tasdiq → pul berilganda avans yoziladi; oy vedomosti qulfi) va o‘zaro hisob (`kassa_offset`: xodimning
yozma arizasi bo‘yicha ish haqidan farzandining o‘quv to‘lovi — maosh to‘lovi, o‘quv to‘lovi va naqdsiz dalolatnoma Dt 6710
Kt 4010 / 6310 bitta tranzaksiyada, faqat Direktor; shu kuni bekor qilish — `kassa_offset_void`; KO-4 da yo‘q); F1.6 qaytarish (Direktor tasdiqlaydi —
balans o‘zgarmaydi; kassir pulni berganda `refund_invoice` shu tranzaksiyada; 1 kundan kechiksa ogohlantirish); F1.7 shu
kunda bekor qilish (o‘quv to‘lovi, maosh, avans, xarajat — bog‘langan yozuv bilan birga); F1.9 va F1.10 `kassa-day.sql`
(boshlang‘ich qoldiq, sanab yopish, farq hujjati, smena topshirish, tekshirish, qayta ochish, kamomad qarori, oflayn / kech
kiritish, o‘qish funksiyalari); F1.12 «Kassa» bo‘limi (`assets/js/fin-kassa.js`); F1.13 mavjud oynalar ulandi («💵 To‘lov»:
fiskal chek №, KO-1; «Maosh berish»: usul; «Xodim avansi» va «Xarajat»: naqd — faqat «Kassa» orqali, naqdsiz — usul +
statiya (toifadan) + kontragent; «Qaytarish»: usul; kassa xarajati «Buxgalteriya»ga o‘zi ko‘chadi; kassa ishga tushgach
naqd yozuvni funksiyani chetlab kiritib bo‘lmaydi — `kassa-links.sql`); F1.14 chop etish (`fin-print.js`: KO-1 + patta,
KO-2, KO-4 2 nusxa, sanash dalolatnomasi — o‘zbek kirill, rus, lotin; «НУСХА» belgisi server jurnaliga tayanadi); F1.15
kunlik hisobot RP-02 (`reportHtml`: kun yakuni, kirim va chiqim orderlari, «kimdan / kimga qancha» — tomon kaliti
bo‘yicha, statiya bo‘yicha, ichki o‘tkazmalar, kanallar, kutilayotganlar, limit; KO-4 bilan bitta server javobidan
tuziladi — jamlari bir xil; ichki hisobot bo‘lgani uchun ilova tilida, chop tili rus bo‘lsa — ruscha), nazorat ro‘yxati
RP-06 («Kassa» sahifasida, 2-ro‘yxat va direktor uchun: 20 tekshiruv, jumladan moslik P1 / P4 / P5 / P8 —
`app.kassa_reconcile`, hisobdorlardagi pul muddati, rahbarga berilgan pul, limit, chop etilmagan KO-4) va Telegram RP-05
(`director_daily` → `app.kassa_daily`: kun jamlari, sanash va farq, bank o‘tkazmalari, nazorat qatori; kassa moduli
bo‘lmasa yoki ishlatilmasa — blok yo‘q); F1.16 `fin-period.sql` — davr surati (`fin_snapshot_take`: o‘quvchilar bo‘yicha
qarz va avanslar, aniqlanmagan tushumlar, kassa qoldig‘i, hisoblagichlar, to‘lanmagan ish haqi, berilmagan qaytarishlar;
o‘zgarmaydi, SHA-256 xeshi qayta hisoblab tekshiriladi; yillik / oylik / qo‘lda, bir kun uchun bir necha versiya) va
davr qulfi (`fin_period_lock`: shu sanagacha to‘lov, xarajat, maosh to‘lovi va avans kiritilmaydi, o‘zgartirilmaydi —
42501; mavjud to‘lovning kuni, summasi yoki kanali o‘zgarsa yoki u bekor qilinsa — eski va yangi kun tekshiriladi;
server (webhook) mustasno; orqaga surish faqat sabab bilan, o‘zgarishlar tarixida; davr faqat shu sanagacha
bo‘lgan kassa kunlari yopilgan bo‘lsa yopiladi, yopilgan davrdagi kassa kuni qayta ochilmaydi); «Kassa» sahifasida «Davr»
oynasi (Direktor — surat va qulf; 2-ro‘yxat — ko‘rish, xeshni tekshirish, JSON yuklab olish — ismsiz, faqat ID bilan:
FD-28, ismli surat jadvalini faqat Direktor o‘qiydi), sana maydonlarida eng erta
sana = qulfdan keyingi kun; F1.11 — kassa ishga tushgach «Maosh berish»ni faqat kassa operatori (naqd) va Moliya
menejeri (karta) ochadi, HR menejer pul bermaydi (server ham rad etadi); F1.18 — `migration/kassa-checks.sql`
(o‘rnatishdan keyingi, faqat o‘qiydigan tekshiruv: 1–10-bandlar tuzilma va huquqlar — `search_path`, ichki `app.*`
funksiyalarning EXECUTE huquqi, RLS va yozish huquqlari, himoya triggerlari, indekslar; 11–22-bandlar ma’lumot
yaxlitligi — kunlar zanjiri, kun jamlari va xeshi, raqamlash, varaqlar, hujjat qatorlari, taqsimot, bog‘lanishlar, moslik
P1 / P4 / P5 / P8, surat xeshlari; chiqishida shaxsiy ma’lumot va summa yo‘q), deploy markeri `app.kassa_version()`
(`fin-version.sql`; sahifa o‘zi kutgan reliz bilan solishtirib «sahifani yangilang» / «server yangilanmagan» deb
ogohlantiradi), `full-deploy.sh` va sinov stendining yakuniy tekshiruviga ulangan; F1.19 — ishga tushirish to‘plami
(`docs/moliya/ishga-tushirish.md` — taqvim, shartlar, texnik tartib, 31-dekabr, birinchi kunlar, favqulodda holatlar,
orqaga qaytish; `yoriqnomalar.md` — rol bo‘yicha bir varaqli yo‘riqnomalar; `shakllar.md` — shakllar ro‘yxati va qog‘oz
shablonlari: avans hisoboti, «Қ» blankasi va jurnali, sanash va daftarlarni yopish dalolatnomalari, qabul sinovi va
parallel yuritish varaqlari); «⚙ Sozlamalar»da imzo egalari (1- va 2-ro‘yxat) va ruscha nom; «Buxgalter» roli (F1.21 dan
oldinga tortilgan minimal qism: «Tasdiqlash» va «Kassa» — so‘rovni tasdiqlash, kunni tekshirish, nazorat ro‘yxati; pul
amallari yo‘q; rol faqat kassa moduli o‘rnatilgan tizimda beriladi; o‘qish huquqlari — 1b). Kassa hujjatiga bog‘langan
to‘lov qatorini (KO-1, o‘zaro hisob dalolatnomasi) faqat kassa funksiyalari o‘zgartiradi (`trg_kassa_pay_guard`: summa,
kanal, o‘quvchi, holat, kun, havola, fiskal № — boshqa yo‘l bilan rad; bekor qilish — hujjat orqali); biriktirilmagan
to‘lovni qaytarish — Dt 6390 Kt 5010 (OP-16). Avans hisoboti (F2.6 dan oldinga tortilgan minimal qism, buxgalter ko‘rigi
M1/M2): «Kassa» → «Avans hisoboti» — naqdsiz dalolatnoma (`nc_adv_report`), har chek qatori Dt statiya hisobvarag‘i Kt 4230,
xarajat «Buxgalteriya»ga o‘zi ko‘chadi (usul «hisobdor orqali»; qo‘lda bunday xarajat yozilmaydi), hisobdor qoldig‘i =
berilgan − qaytim − hisobotlar; hisobot qoldiqdan oshmaydi (ortiqcha sarf — F2.6); oldingi avansi hisobotsiz xodimga yangi
avans — faqat Direktor tasdig‘i bilan (so‘rovda ham, pul berishda ham tekshiriladi); moslikda P4 «adv». Onlayn kassa
Z-hisoboti (F1.26, buxgalter ko‘rigi M6): kunni yopishda Z raqami va undagi naqd va karta sotuvi kiritiladi, tizim fiskal chekli
KO-1 va terminal to‘lovlari bilan solishtiradi; kiritilmagan, «yo‘q» yoki mos emas — kun qatori, nazorat ro‘yxati, Telegram,
kunni tekshirishda izoh majburiy; keyin kiritish / tuzatish — «Z» tugmasi; kunlik hisobotda Z bo‘limi. Yuridik shaxsga (yetkazib
beruvchi / tashkilot) kassadan naqd xarajat (F1.27, M3): so‘rov oynasida ogohlantirish, Direktor tasdig‘i (chegara — sozlama,
standart 0), nazorat ro‘yxatida oxirgi 30 kun. KO-3 kassa orderlari jurnali (F1.22, M4): oy yoki chorak bo‘yicha, bekor
qilinganlari bilan, qoldiqlar mosligi, chop etish (KO-3 shakli, uch tilda) va XLSX (summa — son, sana — Excel sanasi; FD-28:
kassirda yo‘q, Moliya menejeri va buxgalterga ismsiz — ID bilan, jismoniy shaxs hujjatining asosi va sababisiz; Direktorga
to‘liq). RP-08 oylik statiya matritsasi (`kassa_matrix`): statiya × kun, bank bilan ichki o‘tkazma alohida, kunlik jamlar va
qoldiq — KO-3 va KO-4 bilan o‘zaro tekshiriladi; chop etish haftalar kesimida, Excel — kunlar bo‘yicha. Buxgalter uchun oylik
kassa to‘plami (`kassa_month_pack`, E1–E4): bitta Excel — KO-3, statiyalar, kassa kunlari (KO-4 jamlari, sanash, Z),
hisobdorlar (4230); 2-ro‘yxatga ismsiz (FD-28). Eslatmalar (F1.24): muddati o‘tgan avans hisoboti — «Kassa» sahifasida va
Telegram nazorat qatorida (qolganlari — yopilmagan / tekshirilmagan kun, 5910, eski qaytarish, limit — avvaldan). RP-22 haftalik
KPI (F1.25, `kassa_kpi`): o‘z vaqtida yopilgan kunlar, tekshirilmagan, farqlar, EX-49 ulushi (maqsad ≤ 2 %), muddati o‘tgan
avanslar — «KPI» oynasi (8 hafta) va dushanba kungi Telegram qatori. Modul relizi 8. Sinov kassasi (CT-20)
hujjatlari «Buxgalteriya» va avans jadvallariga ko‘chmaydi. Bo‘lim faqat serverda kassa funksiyalari bo‘lganda
ko‘rinadi; ishga tushirish kunigacha barcha oynalar avvalgidek ishlaydi. Sinovlar: `test-kassa.sql` 225,
`test-kassa-pay.sql` 54, `test-kassa-links.sql` 93, `test-kassa-report.sql` 126, `test-fin-period.sql` 36,
`test-kassa-checks.sql` 32 (toza holat va har band uchun ataylab buzilgan holat), `test-kassa-race.sh` 22 (8 × 200
parallel, 10 % ROLLBACK), `fin-print.test.mjs` 27, `fin-words.test.mjs` 7, `fin-kassa.test.mjs` 5, `tg-daily.test.cjs`
45; brauzerda o‘n ikkita to‘liq stsenariy (287 tekshiruv) eski va yangi dizaynda, 1440 va 390 px; kassasiz va «kassa
o‘rnatilgan, ishga tushmagan» holatda eski oqimlar (36 tekshiruv). Yakka chuqur ko‘rik ikki marta o‘tkazildi (topilmalar
va tuzatishlar — `SESSIYA-ISHLARI.md`, 62- va 64-bo‘limlar); buxgalter ko‘zi bilan ko‘rik — 2026-11-12 (Claude Docs
hisoboti, `SESSIYA-ISHLARI.md` 66-bo‘lim): to‘sib qo‘yuvchi topilma yo‘q, 6 ta muhim (M1–M6; M1–M4 va M6 bajarildi —
66–69-bo‘limlar; M5 — bankdan limit xati, maktab), 12 ta hisob siyosati qarori buxgalter imzosini kutadi. Qoldi: jonli zanjirga o‘tkazish — yashirin o‘rnatish
kunida, qabul sinovi va buxgalter ko‘rigidan keyin (`ishga-tushirish.md`, 3.2-band), mustaqil (ko‘p agentli) ko‘rik —
hali o‘tkazilmagan; F1.20 (RLS relizi) — 1b-bosqichda.

| ID | H | kun | Vazifa | Bog‘liq | Qabul mezoni |
|---|---|---|---|---|---|
| F1.1 | M | 2,5 | `fin-core.sql`: rol yordamchilari, ma’lumotnoma jadvallari, `fin_org`, `fin_signatories`, `fin_counterparties`, kassalar, hisoblagichlar; RLS + revoke | F0.11; FD-09/10/11 | To‘g‘ridan-to‘g‘ri DML rad; ma’lumotni buxgalter ko‘rgan |
| F1.2 | M | 2 | `kassa.sql`: jadvallar, o‘zgarmaslik, kun va davr qulfi triggerlari, eski ustunlar | F1.1 | I1–I6 testlari |
| F1.3 | M | 2,5 | Raqamlash + kassa qulfi; parallel testlar (8 × 200, 10 % ROLLBACK, yil chegarasi, `apply_payment` bilan; ikki katta KO-2) | F1.2 | 0 bo‘shliq, 0 takror, 0 deadlock; KO-2 dan bittasi o‘tadi |
| F1.4 | L | 5 | O‘tkazish yadrosi: naqd o‘quv KO-1 taqsimoti; `kassa_post` (ruxsat ro‘yxati, tomon, L1, xodimga xarajat yo‘q); fiskal chek № | F1.3, F0.15; FD-12, 14, 29 | P1, P4 = 0; idempotent; har qoidaga test |
| F1.5 | M | 2,5 | Maosh va avans to‘lovi; o‘zaro hisob; darvozasiz naqd rad; to‘lov qaydnomasi | F1.4, F0.18; FD-15, 24 | P5 = 0 |
| F1.6 | M | 2 | Qaytarishni ajratish (`refund_approve` / `kassa_refund_pay`), refund-rpc.sql o‘zida | F1.4; FD-25 | P8 = 0; overload yo‘q |
| F1.7 | M | 2,5 | Bekor qilish: `kassa_void`, `tuition_reverse_core`, `kassa_void_replace`, xabarnoma bekor | F1.4–F1.6; FD-20 | Keyin harakat bo‘lsa rad; xabar ketmaydi |
| F1.8 | M | 2 | Oflayn va kech kiritish (`capturedAt`, «hali o‘tkazilmagan», direktor ruxsati) | F1.4; FD-19, 23 | Yarim tun testi: ikki marta sanash va qotish yo‘q |
| F1.9 | L | 4 | Kun sikli: ochish, yopish (farq → 5910/9390, qat’iy qatorli varaqlar, xesh), topshirish-qabul, tekshirish, qayta ochish, kamomad qarori, o‘qish RPC lari | F1.4–F1.8; FD-18, 21, 22 | Zanjir; 31.12 testi; KO-4 = sanalgan |
| F1.10 | M | 2,5 | KO-2 oldindan tasdiq (2-ro‘yxat, > T1 direktor); navbatlar admin.html da | F1.1, F1.4; FD-08, 17 | Tasdiqsiz KO-2 o‘tmaydi |
| F1.11 | S | 0,5 | RF-08 UI: to‘lovlar faqat RPC orqali, `canPaySalary` toraytiriladi | F1.5 | HR/MM rad |
| F1.12 | L | 6 | «Kassa» bo‘limi: kun kartasi, hujjatlar, shakllar, tomon tanlash, oynalar, sozlamalar | F1.9, F1.10 | v1/v2, 1440/390 px; yangi CSS yo‘q |
| F1.13 | M | 3 | Mavjud oqimlarni ulash (to‘lov shakli fiskal № bilan, maosh/avans usuli, qaytarish, Buxgalteriya: usul + statiya + kontragent; termal chek to‘lovchiga yo‘q) | F1.4–F1.6, F1.12 | RPC ni chetlab o‘tadigan naqd yo‘l yo‘q |
| F1.14 | L | 5 | Chop etish: KO-1 + patta, KO-2, KO-4, dalolatnomalar; `fin-words.js` | F1.9; FD-05, 07, 08 | Matn suratlari; ≥ 30 misol |
| F1.15 | M | 2 | RP-02, RP-06, Telegram bloki va nazorat qatori | F1.9, F0.12 | RP-02 = KO-4; `--dry` = RP-02 |
| F1.16 | M | 2 | 31.12 xeshli surati; orqaga yozishni cheklash | F1.2 | Yopilgan oyga yozuv rad (42501) |
| F1.17 | L | 5 | Testlar: SQL, parallel, JS, statik UI (`_setClient`), stendda Playwright | F1.1–F1.16 | Hammasi yashil |
| F1.18 | S | 1 | `kassa-checks.sql`, predeploy tekshiruvlari (`search_path`, `app.*` EXECUTE), deploy markeri | F1.17 | Faqat o‘qish rejimida |
| F1.19 | S | 1 | Ishga tushirish to‘plami: yo‘riqnoma, shakllar, avans hisoboti shabloni, «Қ» (006), yopish va sanash dalolatnomalari, orqaga qaytish yo‘riqnomasi | F1.14 | O‘qitishda ishlatiladi |

**Qabul mezonlari (1a).** AC1.1 raqamlar faqat serverdan, uzluksiz, ROLLBACK raqam yemaydi. AC1.2 naqd o‘quv to‘lovi
— payments, taqsimot va KO-1 bitta tranzaksiyada; qatorlar = taqsimot; server sanasi; fiskal № yoki direktor istisnosi.
AC1.3 P1/P4/P5/P8 har kuni 0; F1.20 dan keyin to‘g‘ridan-to‘g‘ri yozuv rad. AC1.4 kun boshi = kecha oxiri, manfiy qoldiq
qulf ostida rad, kecha ochiq bo‘lsa hujjat yo‘q. AC1.5 yopilgan kun o‘zgarmaydi (faqat direktor qayta ochadi; trigger
testi). AC1.6 farq shu kun 5910/9390 hujjati; KO-4 = sanalgan; 31.12 testi. AC1.7 tekshiruvchi ≠ o‘tkazuvchi/yopuvchi;
KO-4 da tekshiruvchi va sonlar so‘z bilan. AC1.8 KO-1 + patta, KO-2, KO-4, dalolatnoma o‘zbek kirill va rus tilida,
barcha rekvizitlar bilan; varaq raqamlari qayta chop etishda bir xil. AC1.9 o‘tkazmalar kirim/xarajatga kirmaydi.
AC1.10 naqdsiz va o‘zaro hisob KO-4 da yo‘q. AC1.11 rol matritsasi UI va RPC da; anon hech narsa ko‘rmaydi. AC1.12
oflaynda to‘lovchiga varaqa yo‘q, ikki marta sanash va qotish yo‘q, «Қ» faqat ruxsat bilan. AC1.13 `director_daily`
to‘g‘ri; prod tekshiruvi `--dry`. AC1.14 har KO-2 2-ro‘yxat tasdig‘idan keyin; T1/L1 — direktor. AC1.15 tomon majburiy,
RP-02 kalit bo‘yicha guruhlaydi. AC1.16 ruxsat ro‘yxati, xodimga `out_expense` yo‘q, L1. AC1.17 v1 va v2, kompyuter va
telefon, yangi CSS yo‘q. AC1.18 har o‘zgarish `change_log` da, sabablar bilan. AC1.19 parallel yuritishdan chiqish:
3 ish kuni sanash = tizim, har KO qog‘oz manbasi bilan belgilangan, Click/Uzum kabinet = kanal bloki, bank = o‘tkazmalar,
tushuntirilmagan farq yo‘q. AC1.20 webhook’lar tegilmagan (payments `npm test`, service_role testlari). AC1.21 31.12
surati saqlangan, yopilgan oyga orqaga yozish rad.

Foydalanuvchi: «Kassa» bo‘limi; har naqd to‘lovga patta bilan KO-1, har chiqimga tasdiqdan keyin KO-2; kechqurun sanash,
KO-4 (2 nusxa), imzo; MM / buxgalter «Tekshirdim»; direktor Telegramda kassa va nazorat qatori; HR va MM naqd maosh
bermaydi; naqd xarajat «Buxgalteriya»da yozilmaydi. Testlar: F1.17 va har rol uchun UAT imzo varag‘i.

### 1b-bosqich — Parallel yuritish va keyin (4–23-yanvar)
| ID | H | kun | Vazifa | Bog‘liq | Qabul |
|---|---|---|---|---|---|
| F1.20 | S | 0,5 | RF-08 RLS relizi (toza haftadan keyin), orqaga qaytarish migratsiyasi bilan | F1.11; 7 kun P4/P5 = 0 | To‘g‘ridan-to‘g‘ri yozuv rad |
| F1.21 | M | 2,5 | `accountant` roli: yorliqlar, tablar, ~10 jadval SELECT siyosati, `can_see_salary`, `students_billing`, `v_fns` | F1.1; FD-18, 28 | Rol testlari; ro‘yxat yopiq |
| F1.22 | M | 2,5 | ✅ KO-3 (kassa orderlari jurnali: chop etish, XLSX; `kassa_journal`, rol tekshiruvli; Excel — FD-28 bo‘yicha `kassa_journal_export`: kassirda yo‘q, 2-ro‘yxatga ismsiz, Direktorga to‘liq) — buxgalter ko‘rigi M4; ✅ RP-08 oylik statiya matritsasi (`kassa_matrix`; chop etish — haftalar, XLSX — kunlar); ✅ oylik kassa to‘plami E1–E4 (`kassa_month_pack`: KO-3, statiyalar, kassa kunlari, hisobdorlar; FD-28) | F1.9 | XLSX raqamli; yanvar to‘plami fevral boshida |
| F1.23 | S | 0,5 | O‘zaro hisob dalolatnomasi chop etish; sozlamalar | F1.5 | — |
| F1.24 | S | 1 | ✅ Eslatmalar (yopilmagan va tekshirilmagan kun, 5910, eski qaytarish, muddati o‘tgan avans, limit) — «Kassa» sahifasida, nazorat ro‘yxatida va Telegram nazorat qatorida | F1.15 | RP-06 va Telegramda |
| F1.25 | S | 0,5 | ✅ RP-22 haftalik KPI (`kassa_kpi`: «KPI» oynasi — 8 hafta; dushanba kungi Telegram qatori) | F1.15 | Direktor ko‘radi |
| F1.26 | S | 1 | ✅ Kunni yopishda onlayn kassa (NKM) Z-hisoboti: naqd va karta sotuvi kiritiladi, fiskal chekli KO-1 va terminal to‘lovlari bilan solishtiriladi; keyin kiritish / tuzatish — «Z» (buxgalter ko‘rigi M6) | F1.9 | Farq nazorat ro‘yxatida va Telegramda; tekshirishda izoh |
| F1.27 | S | 0,5 | ✅ Kontragent-tashkilotga (yetkazib beruvchi / tashkilot) kassadan naqd to‘lovda ogohlantirish va Direktor tasdig‘i; chegara — «⚙ Sozlamalar» (standart 0 — har doim), nazorat ro‘yxatida (M3) | F1.10 | Qoidaga test |

Chiqish: AC1.19; Excel kunlik varag‘i to‘xtagan.

### 2-bosqich — Statiyalar hamma joyda, hisobdorlar, oy qulfi (25-yanvar – 27-fevral)
| ID | H | kun | Vazifa | Bog‘liq | Qabul |
|---|---|---|---|---|---|
| F2.1 | M | 2 | `expense_save`: naqdsiz reyestr (usul, statiya qatorlari, kontragent, hujjat №, ilova, server muallif; bekor qilish) | F1.1 | Takror yo‘q; har qatorda statiya |
| F2.2 | M | 2 | Kontragentlar to‘liq (STIR, hisob, MFO, shartnoma); RP-10 | F1.1 | Seed’da shaxsiy ma’lumot yo‘q |
| F2.3 | S | 0,5 | Noyabr–yanvar xarajatlariga statiya (sinov ishga tushirishi → buxgalter RPC si) | F1.1; FD-10 | Buxgalter imzolaydi |
| F2.4 | M | 2 | `expenses.kind = 'accrual'` va o‘quvchi kodlar | — | Naqd ko‘rinishda hisoblash yo‘q |
| F2.5 | M | 2,5 | RP-09 (maosh taqsimoti, XLSX) | F2.1, F2.3 | Jami = Σ hujjatlar |
| F2.6 | L | 5 | Avans hisobotlari: ortiqcha sarf (6970 va qaytarish orderi), suratlar, tasdiq, RP-07 yoshi; zavxoz maqsadlaridan statiya taklifi (minimal qism — 1a da, `nc_adv_report`) | F1.4; FD-14, 31 | Qoldiq formulasi; yanvar qulfdan oldin |
| F2.7 | M | 2,5 | Faktura tarkibi (`grossAmount`, `discountParts`), noyabrdan backfill | FD-32 | 100 % fakturada mos (±1 so‘m) |
| F2.8 | M | 3 | Oylik sanash dalolatnomasi, topshirish-qabul, oy oxiri ro‘yxati; barcha pul jadvallari uchun oy qulfi (tizim mustasno) | F1.9, F1.16 | Qulflangan oyga yozuv rad; webhook’lar ishlaydi |
| F2.9 | L | 5 | Huquqlar II (RF-09…12): detektor → revoke; provider `fix`; barcha pul RPC larida bayroq | F1.13 | 7 kun 0 yozuv, keyin revoke |
| F2.10 | M | 2 | 9 rol + anon REST RLS matritsasi | F2.9 | Barcha rad etishlar |
| F2.11 | S | 0,5 | `refund_credit` (FD-25 talab qilsa) | F1.6 | — |
| F2.12 | S | 0,5 | KO-3 A4; yil muqovasi va guvohnoma; patta QR | F1.14 | — |

Foydalanuvchi: har xarajatda statiya va kontragent, RP-09, zavxoz avans hisoboti, oylik dalolatnoma, oy qulfi. Testlar:
SQL va REST, oy qulfi + service_role webhook’lar. Chiqish: EX-49 ≤ 2 %, yanvar avanslari kiritilgan, tracker chiqimi yopiq.

### 3-bosqich — Bank, yo‘ldagi pul, onlayn kanallar (1–27-mart)
| ID | H | kun | Vazifa | Bog‘liq | Qabul |
|---|---|---|---|---|---|
| F3.1 | M | 2 | To‘lov serveri yakunlangan vaqtni yozadi; sanali qaytarishlar (migratsiya serverdan oldin) | F0.14 | Yarim tundan o‘tgan to‘lov to‘g‘ri kunda |
| F3.2 | L | 4 | Bank jadvallari; 2027-01-01 dan import, xeshli takrorsizlik, qoldiq tekshiruvi, qo‘lda yozuvlar bilan solishtirish | FD-36 | Qayta import hech narsa qo‘shmaydi |
| F3.3 | L | 5 | Moslashtirish va tasniflash (35 namuna) + qo‘lda moslashtirish ekrani | F3.2; FD-13, 33, 34 | Har satr moslashgan yoki izohlangan; ≥ 80 % avtomatik |
| F3.4 | M | 2,5 | 5710 kanal bo‘yicha, komissiya (EX-41), ochiq qoldiqlar | F3.3 | 5710 har oy yopiladi |
| F3.5 | S | 0,5 | Korporativ karta (5530 / 4230) | F3.3, F2.6; FD-35 | Karta xarajat emas |
| F3.6 | M | 2 | RP-11; Click/Uzum kabinet bilan kunlik solishtirish | F3.4 | Farqlar kunlik |
| F3.7 | S | 0,5 | (ixtiyoriy) barcha kanallar uchun `payment_allocations` | F1.4 | Webhook testlari |

Foydalanuvchi: ko‘chirma yuklash, avtomatik moslashtirish, komissiyalar; bank varaqlari to‘xtaydi. Testlar: import,
moslashtirish, 5710, webhook’lar.

### 4-bosqich — Bosh kitob 2027-01-01 dan (29-mart – 1-may)
| ID | H | kun | Vazifa | Bog‘liq | Qabul |
|---|---|---|---|---|---|
| F4.1 | M | 2 | `fin-gl.sql`: yozuvlar, qatorlar, davrlar; balans va davr himoyasi | F1.1 | Balanssiz / qulflangan yozuv rad |
| F4.2 | M | 2,5 | Yangi hujjatlar uchun RPC ichida provodka; 1-yanvardan back-post | F4.1 | Har hujjatda balansli yozuv |
| F4.3 | L | 5 | Sverka-provodkachi + tungi sverka; versiyalash; muammolar ro‘yxati; sintetik model SQL testi | F4.1, F2.7, F3.1; FD-31…34, 40, 41 | Ikki ishga tushirish — 0 o‘zgarish |
| F4.4 | M | 2,5 | 31.12.2026 boshlang‘ich qoldiq: sub-registr ↔ nazorat hisoblari solishtiruvi, 31.12 suratidan, direktor tasdig‘i | F4.1, F1.16; FD-37, 42 | Jamlar mos; 0000 = 0 sun’iy tenglashtirishsiz |
| F4.5 | M | 3 | Oy yopish yordamchisi MC-1…MC-13, qulf | F4.3; FD-39 | 9xxx = 0; qulf ishlaydi |
| F4.6 | L | 5 | Jurnal, OSV, kartochka, tahlillar; XLSX | F4.2 | OSV → kartochka → hujjat |
| F4.7 | M | 2,5 | Maosh: xodim bo‘yicha, oy oxiri sanasi, stavkalar sozlamadan; soliqlar FD-38 dan keyin | F4.3; FD-38, 44 | Sintetik G testi; 4210 = 0 |
| F4.8 | M | 2 | Qo‘lda jurnal, storno, qayta tasnif; SK 483 shablonlari | F4.1 | Sabab majburiy |
| F4.9 | S | 0,5 | RP-16 eksport E1–E8 (1C shabloni — FD-03 bo‘yicha) | F4.6 | OSV ga qayta yig‘iladi |
| F4.10 | S | 0,5 | Solishtiruvlar: 5010 = KO-4; 4010 − 6310; 5710; 4230 | F4.3 | MC-1 talab qiladi |
| F4.11 | S | 0,5 | Maqsadli foydalanish reyestri (MC-12) | F4.8; FD-40 | 8840 bilan mos |

Foydalanuvchi: buxgalterga jurnal, OSV, kartochkalar, oy yopish; yanvar–mart ≈ 1-maygacha yopiladi. Testlar: sintetik
model, sverka o‘zgarmasligi, boshlang‘ich qoldiq. Chiqish: uchta toza yopilish (B rejim asosi).

### 5-bosqich — Hisobotlar (3-may – 5-iyun) va 6-bosqich — muvofiqlik (iyundan yoki FD-29 bo‘yicha oldin)
| ID | H | kun | Vazifa | Bog‘liq | Qabul |
|---|---|---|---|---|---|
| F5.1 | M | 2,5 | 1/2-shakl qoralamasi (FD-45 bo‘yicha 3/4 ham) | F4.5 | 400 = 780; 270 = MC-11 |
| F5.2 | M | 2 | BHMS 9 pul oqimi statiyalar bo‘yicha | F4.3 | 230 + 220 + 221 = 240 |
| F5.3 | S | 0,5 | Hisoblash asosidagi matritsa | F4.5 | = 2-shakl 270 |
| F5.4 | S | 1 | Ota-ona ma’lumotnomasi (QR), ish beruvchi dalolatnomalari | F1.4 | Raqam o‘zgarmaydi; jurnal |
| F5.5 | M | 2 | Nazorat hisobotlari | F4.3 | MC-13 dan oldin |
| F5.6 | S | 0,5 | Muvofiqlik taqvimi va eslatmalar | — | Direktor va MM ko‘radi |
| F6.1 | L | 5 | Fiskal integratsiya (virtual kassa, Click `submit_items`, Payme/Uzum) | FD-29 | Har naqd/POS fiskal yoki belgilangan |
| F6.2 | M | 2 | KO-4 ni ERI bilan imzolash | FD-43 | Qog‘oz imzosi to‘xtashi mumkin |
| F6.3 | M | 2,5 | Maosh soliqlari moduli + INPS reyestri | FD-38 | Hisobot bilan mos |
| F6.4 | S | 0,5 | ESF maydonlari; ish beruvchi dalolatnomalari | FD-34 | — |
| F6.5 | S | 0,5 | B rejimga o‘tish ro‘yxati | FD-43 | 3 toza yopilish + yozma rozilik |

### 5.9 Haftalik jadval
| Hafta | Sanalar | Dasturchi | Maktab tomoni |
|---|---|---|---|
| W46 | 9–14-noyabr | F0.10–F0.13, F0.11 | **14-noyabr: qarorlar yig‘ilishi**; oraliq qoidalar varag‘i |
| W47 | 16–21-noyabr | F0.14–F0.16 deploy; F1.1–F1.2 | **16-noyabrdan oraliq qoidalar**; **21-noyabr: G2 (vaqtincha)**; F0.18 |
| W48 | 23–28-noyabr | F1.3–F1.4; F0.17; F0.20 | **28-noyabr: namoyish va yo‘l nazorati** |
| W49 | 30-noyabr – 5-dekabr | F1.5–F1.8 | noyabr vedomosti tizimda (to‘lov eski usulda) |
| W50 | 7–12-dekabr | F1.9–F1.11, F1.13 | **12-dekabr: G1, G2 (imzo), G5** |
| W51 | 14–19-dekabr | F1.12, F1.14–F1.17 | UAT 1-raund; o‘qitish; **19-dekabr: FD-44 (G3)** |
| W52 | 21–26-dekabr | tuzatishlar; F1.18–F1.19; **21-dekabr: yashirin deploy** + `sinov` smoke (o‘quv to‘lovisiz) | UAT 2-raund, **26-dekabr: G4**; o‘qitish (kassirlar, o‘rinbosar, hisobdorlar, HR); maosh kuni mashqi |
| W53 | 28-dekabr – 2-yanvar | qo‘llab-quvvatlash | **31-dekabr: sanash dalolatnomasi, daftarlarni yopish, sozlamalar (G6)**; dekabr vedomosti (G3) |
| W01 | 4–9-yanvar | qo‘llab-quvvatlash | **4-yanvar: rasmiy ishga tushirish**; parallel yuritish; birinchi tizim maosh kuni; Excel to‘xtaydi (≈ 9-yanvar) |
| W02–W03 | 11–23-yanvar | 1b | kunlik qo‘ng‘iroq; haftalik ko‘rik |
| W04–W08 | 25-yanvar – 27-fevral | 2 | 30-yanvar: oylik sanash; buxgalter 2026 yilni 1-martgacha topshiradi |
| W09–W12 | 1–27-mart | 3 | bank eksporti; 31.12.2026 qoldiqlari |
| W13–W17 | 29-mart – 1-may | 4 | solishtiruv → boshlang‘ich qoldiq; yanvar–mart yopilishi |
| W18–W22 | 3-may – 5-iyun | 5 | B rejimni baholash |
| W23 dan | iyun | 6 | qaror bo‘yicha |

---

## 6. Qarorlar
**2026-11-10 — egasining qarori:** barcha qarorlar ijrochiga topshirildi — quyidagi jadvaldagi **tavsiyalar qabul
qilindi** (FD-01…FD-46; [BUX] bandlar buxgalter ko‘rib chiqquncha vaqtincha amalda). Faqat maktabning o‘zi beradigan
ma’lumotlar ochiq qoladi: fiskal kassa holati (G1), buxgalter va imzo ro‘yxatlari (G2, G5), bank kassa limiti (F0.4),
ishga tushirish rekvizitlari (F0.6), hisobdorlar qoldig‘i (F0.7), bank ko‘chirmasi namunasi (F0.8).

Dastur tavsiyalar bo‘yicha quriladi; imzolarni faqat ishga tushirish kutadi. Ta’sir: K — kod, D — ma’lumot, S — sozlama,
J — ish jarayoni.

| ID | Qaror | Tavsiya | Kim · muddat · ta’sir |
|---|---|---|---|
| FD-01 | Ishga tushirish sanasi | Yanvarning birinchi kassa kuni (4-yanvar), 31.12 sanash bilan; dekabrda yashirin o‘rnatish va UAT; zaxira — 1-fevral; 14-dekabr — tavsiya etilmaydi | Egasi · 14-noyabr · J |
| FD-02 | Dasturchi ustuvorligi | 0–1a yanvargacha birinchi; faqat boshlangan xavfsizlik ishlari va avariyalar aralashadi | Egasi · 14-noyabr · J |
| FD-03 | Ish rejimi | A: tizim hujjatlari + boshqaruv bosh kitobi, statutor registrlar buxgalterda; B — 3 toza yopilish + rozilik + ERI yoki imzolangan nusxalardan keyin | [BUX] · 14-noyabr · J |
| FD-04 | KO-4 tarkibi | Faqat 5010; naqdsiz va o‘zaro hisob — ma’lumot blokida | [BUX] · 21-noyabr · K |
| FD-05 | Raqamlash | KO-1/KO-2 alohida, kalendar yili, server, uzluksiz, yanvardan 1 dan; KO-4 varaqlari 1 dan | [BUX] · 21-noyabr · S |
| FD-06 | KO-1 va printer | Har naqd to‘lovga KO-1 + patta (A5 / A4 yarmi); termal patta yo‘q | Egasi · 21-noyabr · J |
| FD-07 | Chop etish | O‘zbek kirill (rus bor); «КАССА»; «1 234 567=89»; KO-4 2 nusxa; harakatsiz kunga varaq yo‘q; «юз» | [BUX] · 21-noyabr · S |
| FD-08 | Imzo ro‘yxatlari | 1: direktor, o‘rinbosar; 2: bosh buxgalter, MM; KO-2 — 1 + 2 turli shaxslar, to‘lovdan oldin 2-ro‘yxat; rekvizitlar sozlamadan | Egasi + [BUX] · 12-dekabr · S, J |
| FD-09 | Hujjatdagi hisobvaraqlar | BHMS 21 kodlari + analitika; «40.11» → 4010 + to‘lovchi turi; kassa qismi ishga tushirishdan oldin tasdiqlanadi | [BUX] · 21-noyabr · D |
| FD-10 | Statiyalar | 75 statiya va ikki moslik; «Boshqa» ≤ 2 %; IT-PARK — buxgalter | [BUX] · 21-noyabr · D |
| FD-11 | Operatsiyalar | §4.5 (kassadan soliq yo‘q; `out_loan_repay` 1a da; 4290/4890) | [BUX] · 21-noyabr · D |
| FD-12 | O‘quv KO-1 krediti | 4010 boshlangan davrga, 6310 ortiqcha va kelgusi oyga; avansdan — naqdsiz 6310→4010 | [BUX] · 21-noyabr · K |
| FD-13 | Bankka / bankdan | Topshirish 5710 orqali; olish Dt 5010 Kt 5110; komissiya bank tomonida | [BUX] · 21-noyabr · D |
| FD-14 | Xarid puli | 4230 + avans hisoboti ≤ 3 ish kuni (karta 10); hujjatsiz xarid ≤ L1, bitta statiya; xodimga — faqat hisobdor operatsiyasi | [BUX] + Egasi · 21-noyabr · S |
| FD-15 | Naqd maosh | Faqat kassir; har kishiga KO-2 + qaydnoma; karta va o‘zaro hisob — MM | Egasi + [BUX] · 21-noyabr · K |
| FD-16 | Naqd qabul va kassa modeli | Kassir, g‘aznachi, direktor; bitta kassa, smenalar, topshirish-qabul sanashi | Egasi · 14-noyabr · J |
| FD-17 | KO-2 ruxsati | T1 — direktor belgilaydi; ≤ T1 2-ro‘yxat, > T1 direktor ham; 1a dan oldindan tasdiq | Egasi · 21-noyabr · S |
| FD-18 | Tekshiruvchi | 2-ro‘yxat (buxgalter yoki MM, direktor ham), o‘tkazmagan va yopmagan; buxgalter hisobi 1b | Egasi + [BUX] · 21-noyabr · K |
| FD-19 | Kun intizomi | Server sanasi; kecha avval yopiladi; boshqa shaxs — 2 kishilik dalolatnoma; kassa uchun orqaga yozish 0; oflayn §4.7 | Egasi · 21-noyabr · K |
| FD-20 | Tuzatishlar | Shu kun bekor qilish; oxirgi tekshirilmagan kunni direktor qayta ochadi; aks holda storno; tahrir yo‘q | [BUX] · 21-noyabr · K |
| FD-21 | Sanash farqi | Bardoshsiz; shu kun 5910 / 9390; qaror — direktor: 4730 (yozma rozilik yoki shartnoma) yoki 9430 | [BUX] · 21-noyabr · K |
| FD-22 | Limit va maosh puli | Bank limiti (hujjatsiz 0), faqat ogohlantirish; 3 ish kuni rasmiy taqvim bo‘yicha | Egasi + [BUX] · 21-noyabr · S |
| FD-23 | Oflayn naqd | Qabul qilinadi: NKM oflayn cheki; tizim varaqa bermaydi; bitta kompyuter | Egasi · 21-noyabr · K |
| FD-24 | O‘zaro hisob, imtiyozlar | Dalolatnoma + yozma ariza + direktor; moddiy naf (SK 376) bo‘yicha buxgalter xulosasi; belgilar | [BUX] + Egasi · 21-noyabr · J |
| FD-25 | Qaytarish | Direktor tasdiqlaydi va usul (asl kanal); kassir KO-2 bilan; balans to‘lov sanasida; 1 bank kuni; bankdan naqd olish shartmi — buxgalter | Egasi + [BUX] · 21-noyabr · K |
| FD-26 | Rahbar / ta’sischiga pul | 4290 / 4890; shu oyda tasnif; xarajat emas | [BUX] + Egasi · 21-noyabr · D |
| FD-27 | Tarix, Sheet, Excel | Sentyabr–oktyabr importsiz; noyabr–dekabr yetishmagan xarajatlar buxgalter imzolagan sinov bilan; oraliq qoidalar; Excel soyasi yo‘q; Sheet ≈ 15-yanvardan faqat ko‘rish | Egasi · 14-noyabr · J |
| FD-28 | Eksport | Ismli XLSX — faqat direktor; MM va buxgalter — ID bilan (D7 saqlanadi; o‘zgartirish faqat egasi imzosi bilan) | Egasi · 21-noyabr · K |
| FD-29 | Fiskal chek | G1 darvoza; naqd KO-1 da fiskal № majburiy; to‘lovchiga tizim cheki yo‘q; chek turi — buxgalter; integratsiya 6-bosqichda | Egasi + [BUX] · 12-dekabr · J, K |
| FD-30 | G‘aznachi | Kassir bilan teng; bazadagi moliya huquqlari olinadi | Egasi · 23-yanvar · K |
| FD-31 | Materiallar | Oziq-ovqat 1010 + oylik chiqim dalolatnomasi + choraklik inventarizatsiya (variant — to‘g‘ridan-to‘g‘ri); kitob va idish 1080 + 014; kapital 0820/0870; asosiy vositalar — buxgalter | [BUX] · 23-yanvar · D |
| FD-32 | Daromad | Yalpi 9030, chegirma 9050 turi bo‘yicha; prorata — kamroq daromad; bemor kuni — 9030 storno (variant 9050); tavsiya 9050 (variant 9410) | [BUX] · 23-yanvar · D |
| FD-33 | Aniqlanmagan tushum, komissiya | 6390 (30 kunda ko‘rik); kanallar 5710 orqali; komissiya ko‘chirmadan | [BUX] · 27-fevral · D |
| FD-34 | Ish beruvchi to‘lovi | O‘quvchi bo‘yicha, to‘lovchi — tashkilot; oylik ma’lumotnoma; ESF — so‘rov bo‘yicha | [BUX] · 27-fevral · D |
| FD-35 | Korporativ karta | Alohida karta hisobi bo‘lsa 5530 + 4230; aks holda 4230 ↔ 5110 | [BUX] · 27-fevral · D |
| FD-36 | Bank formati | Bank-mijoz CSV/XLSX (hujjat №, STIR, hisob raqami) | Egasi · 27-fevral · K |
| FD-37 | Bosh kitob boshlanishi | 2027-01-01; buxgalter qoldiqlari + tizimdagi 5010 va o‘quvchilar (31.12 surati); avval solishtiruv | [BUX] · 27-mart · D |
| FD-38 | Maosh provodkalari | Xodim bo‘yicha, lavozimdan xarajat markazi, oy oxiri sanasi; stavkalar sozlamada; soliqlar FD-44 dan keyin avtomatik | [BUX] · 27-mart · D, K |
| FD-39 | Oy yopish | 5-ish kunigacha, qulf; faqat direktor ochadi; kechikkanlar — joriy davrga | [BUX] · 23-yanvar · K |
| FD-40 | Soliq holati va imtiyoz | SK 483-modda shartlarini buxgalter tasdiqlaydi; 8840 + reyestr (013 emas); QQS va boshqa soliqlar hisoblanmaydi (tasdiq bilan); forma — qayta sotish | [BUX] · 27-mart · D |
| FD-41 | Depozit va umidsiz qarz | 6310 da, shartnoma bo‘yicha; direktor buyrug‘i bilan hisobdan chiqarish (007); moddiy naf tekshiruvi | [BUX] · 27-mart · D |
| FD-42 | Boshlang‘ich qoldiq majburiyatlari | Yopiq ilova ro‘yxati bo‘yicha buxgalter (kerak bo‘lsa yurist) tasdiqlaydi; valyutada bo‘lsa qayta baholash bilan | [BUX] + Egasi · 27-mart · D |
| FD-43 | Imzo va B rejim | Hozir KO-4 har kuni chop etilib imzolanadi; ERI keyin; B — 3 toza yopilishdan keyin | Egasi + [BUX] · aprel · J |
| FD-44 | Ish haqi fondi mosligi | Tizim vedomosti buxgalter hisobotidagi fond bilan bir xilligi yozma tasdiqlanadi (yoki tuzatish rejasi) | [BUX] · 19-dekabr · J |
| FD-45 | Korxona o‘lchami | Kichik bo‘lsa 1/2-shakl; aks holda 1–4-shakl va izohlar | [BUX] · 27-mart · K |
| FD-46 | Ta’til rezervi | 8910 yuritilmaydi (standart) — buxgalter hal qiladi | [BUX] · 27-mart · D |
| FD-47 | Yuridik shaxsga kassadan naqd to‘lov | Standart — har to‘lov Direktor tasdig‘i bilan (chegara 0); amaldagi qonunchilik bo‘yicha chegara va kontragent turlari («yetkazib beruvchi» / «tashkilot» — yuridik shaxs; YaTT — «jismoniy shaxs») buxgalter tasdiqlaydi, Direktor «⚙ Sozlamalar»ga kiritadi | [BUX] · 12-dekabr · J |

---

## 7. Xavflar va nazorat; qonunchilik nazorat ro‘yxati

| ID | Xavf | Chora |
|---|---|---|
| RK-01 | Buxgalter band yoki rad etadi | [BUX] vaqtincha qabul; G2; A rejim; buxgalter roli 1b |
| RK-02 | Dasturchi vaqti boshqa reja bilan raqobat | FD-02; yo‘l nazorati; fevral zaxirasi; yashirin o‘rnatish |
| RK-03 | Vedomost va buxgalter hisoboti nomuvofiq | FD-44 (G3) maosh kunidan oldin; soliqlar FD-38 dan keyin |
| RK-04 | Fiskal chek talablari; patta chek deb tushunilishi | G1; fiskal № majburiy; «Фискал чек эмас»; VM 943, 4-band xulosasi; F6.1 |
| RK-05 | Kassa limiti hujjati | F0.4; ogohlantirish |
| RK-06 | Kitobni chetlab o‘tish | Kunlik P1; detektor → revoke (F2.9) |
| RK-07 | Raqamlash buzilishi | Oxirgi qulf; yutuvchi handler yo‘q; parallel testlar |
| RK-08 | Webhook’larga ta’sir | Provodka triggeri yo‘q; L4/L5 webhook’da yo‘q; service_role testlari |
| RK-09 | Yangi jadval ochiq qolishi | RLS + revoke; verify-db; REST testlari; predeploy tekshiruvlari |
| RK-10 | Boshlang‘ich qoldiq sifati | Komissiya sanashi (farq majburlanmaydi); imzolangan ma’lumotnomalar; solishtiruv (F4.4) |
| RK-11 | ERI yo‘q | KO-4 har kuni chop etilib imzolanadi; ERI 6-bosqichda |
| RK-12 | Qat’iy ketma-ketlik noqulayligi | Ertalab tez yopish; dalolatnoma bilan o‘rniga yopish |
| RK-13 | Vazifalar ajratilishiga qarshilik | Buyruq (FD-15); o‘qitish |
| RK-14 | Tekshiruv rasmiyatchilikka aylanishi | Buxgalter ko‘rigi; RP-22 |
| RK-15 | Oflayn chekka holatlar | Bitta kompyuter; «hali o‘tkazilmagan» qatori; direktor ruxsati |
| RK-16 | Chop etish va eksportda shaxsiy ma’lumot | RLS; ismsiz eksport; shaxs hujjati saqlanmaydi |
| RK-17 | Ishga tushirish va maosh kuni bir haftada | Maosh mashqi; G3; direktor istisnosi |
| RK-18 | Qamrov kirib kelishi | 1a / 1b ajratilgan; §4.0 №12 |
| RK-19 | Imtiyoz shartlari va maqsadli foydalanish | FD-40; 8840 reyestri; berilgan pul xarajat emas |
| RK-20 | Faktura chegirmasi aralash (admin.html:10560) | F2.7 4-bosqichdan oldin |
| RK-21 | Bank formati noma’lum | F0.8; qo‘lda kiritish zaxirasi |
| RK-22 | Eski tablar revoke’dan keyin yozishi | Detektor haftasi; majburiy qayta yuklash |
| RK-23 | Superuser bo‘lmagan cheklovlar | `set_config`; lokal zanjir shunday egasi bilan |
| RK-24 | Prod’da sinov xabarnomasi | Smoke faqat o‘quv to‘lovisiz; `kassa_void` xabarni bekor qiladi |
| RK-25 | Stend yo‘qligi prod’da mashqqa undaydi | F0.20 |
| RK-26 | Sheet parallel yuritilishi | Oraliq qoidalar; inventar; «faqat ko‘rish» sanasi |
| RK-27 | Yagona 2-ro‘yxat tasdiqlovchisi yo‘q kuni | Ikkinchi 2-ro‘yxat shaxsi; telefondan tasdiq |

Ustuvorlik: **M0** — ishga tushirishdan oldin; **M1** — dastlabki oylarda; **K** — keyin.

| № | Talab | Manba | Tizim / jarayon | Ust. |
|---|---|---|---|---|
| CL-01 | O‘z shakllari buyruq bilan, majburiy rekvizitlar (joy, lavozim, ism, imzo) | Qonun 14-modda; Nizom 143, 6, 11-band | F0.3; F1.14 | M0 |
| CL-02 | Ikki imzo ro‘yxati; 2-ro‘yxatsiz hujjat haqiqiy emas | Qonun 13-modda | F0.3; F1.10 | M0 |
| CL-03 | Kassa hujjatida tuzatish yo‘q; buzilgan blanka ilova | Qonun 14; Nizom 143, 25, 50-band | o‘zgarmaslik; storno | M0 |
| CL-04 | Saqlash ≥ 5 yil | Qonun 29; Nizom 143, 26-band | o‘chirish yo‘q; arxiv | M0 |
| CL-05 | ERI yoki har kuni imzolangan nusxa | Nizom 143, 3–5-band | KO-4 har kuni | M0 |
| CL-06 | Qaytarish: ariza, chek, F.I.Sh. li KO-2, 1 bank kuni, qaytarish cheki | VM 943, 1-ilova, 35–38-band | F1.6; CT-26 | M0 |
| CL-07 | Kassa limiti; maosh puli ≤ 3 ish kuni | MB yo‘riqnomasi (ro‘yxat 3003), 6, 17–24-band | F0.4; CT-13 | M0 |
| CL-08 | Har naqd va POS to‘lovga fiskal chek; ikkilamchi fiskal tizim taqiqi; oflayn 48 soat; maxsus kvitansiya daftari | PF-5813, 5-band; VM 943, 1-ilova, 4, 6, 30, 31, 33-band | G1; CT-21; F6.1 | M0 / K |
| CL-09 | Chekda to‘g‘ri IKPU | SK 223-modda 5-qism | F0.5 | M0 |
| CL-10 | Kvitansiya daftarlari va «Қ» — qat’iy hisobdagi blankalar | BHMS 19, 5-band; 006 | yopish dalolatnomasi; oylik inventarizatsiya | M0 |
| CL-11 | Shaxsiy ma’lumotni kamaytirish | D6 / D7 | RLS; ismsiz eksport | M0 |
| CL-12 | Kun / oy qulfi | ichki nazorat | CT-04, CT-27; F2.8 | M0 |
| CL-13 | Oylik komissiya inventarizatsiyasi (INV-16); moddiy javobgar almashganda inventarizatsiya | BHMS 19, 5, 8, 60–61-band | 31.12; F2.8; topshirish-qabul | M1 |
| CL-14 | Natija o‘sha oyda; qaror rahbarda; aybdor bo‘lmasa — xarajat | BHMS 19, 69, 70, 72-band | CT-14; FD-21 | M0 |
| CL-15 | Choraklik oziq-ovqat inventarizatsiyasi | BHMS 19, 5-band | 1010 (FD-31) | M1 |
| CL-16 | Click / Uzum / QR fiskalizatsiyasi | VM 943, 1a-ilova | F0.5; F6.1 | M1 |
| CL-17 | Avans hisoboti muddati siyosatda | VM 424, 22-band (tavsiya) | FD-14 | M1 |
| CL-18 | Soliq bank orqali naqdsiz | SK 74-modda | kassadan soliq yo‘q | M0 |
| CL-19 | Moddiy naf bo‘yicha soliq agenti; o‘zaro hisobga rozilik | SK 376-modda | FD-24, FD-41 | M1 |
| CL-20 | Hujjatlar aylanishi grafigi buyruq bilan | Nizom 143, 52–53-band | F0.3 | M0 |
| CL-21 | Maosh soliqlari va INPS reyestri 15-sanagacha | SK 381, 405; ro‘yxat 3577 | buxgalter; F4.7 | buxgalter |
| CL-22 | Ota-onaning JShDS imtiyozi hujjatlari | SK 378-modda 16-band | patta; F5.4 | K |
| CL-23 | Ilovalarga «Олинди» / «Тўланди»; sana tartibida tikish | Nizom 143, 18–19, 28-band | qog‘oz shtamp | M0 |
| CL-24 | Bank o‘tkazmasi uchun ESF (mansabdor fikri) | normativ hujjat emas | F6.4 | K |
| CL-25 | Yillik hisobot 1-martgacha; kichik bo‘lmasa 1–4-shakl | 181-buyruq, 7, 9–10, 13-band | F5.1; FD-45 | K |

---

## 8. Sinov, ishga tushirish, parallel yuritish, o‘qitish, Excel/Sheet’dan voz kechish
**8.1 Sinov** (faqat lokal stek va sinov stendi, sintetik / SINOV ma’lumot): `test-kassa.sql` (bitta tranzaksiya,
ROLLBACK, test soati; raqamlash, idempotentlik, bekor qilish, I1–I6, triggerlar, 9 rol + anon, oflayn, qaytarish, fiskal
/ tomon / ruxsat / L1, davr qulfi); `test-kassa-race.sh` (8 × 200 ROLLBACK bilan; `apply_payment` bilan 500 aralashuv;
ikki katta KO-2; yopish paytida o‘tkazish; yil chegarasi; yarim tundan keyingi sinxronlash); PostgREST rad etish testlari;
`node --test` (so‘zlar, shablonlar, XLSX); statik UI (`_setClient`); stendda Playwright (v1/v2, 1440/390: 3 to‘lov —
biri ortiqcha, biri kelgusi oyga; qaytim; T1 dan katta xarajat; topshirish; bekor qilish; farq bilan yopish; tekshirish);
regressiya (payments `npm test`, test-audit-fixes, test-public-close, test-auth-rls). Moslik: P1 KO-1 = naqd to‘lovlar;
P2 KO-4 zanjiri; P3 hisoblagichlar; P4 naqd xarajat = KO-2; P5 maosh/avans = KO-2; P6 bosh kitob 5010 = KO-4; P7 mavjud
P = I + C auditi (admin.html:9910-10019); P8 qaytarish = KO-2.

**8.2 Prod xavfsizligi.** Odatiy bitta tranzaksiyali deploy, ish vaqtidan tashqari; verify-db; `kassa-checks.sql`
faqat o‘qish rejimida. Yashirin o‘rnatish ≈ 21-dekabr (`kassaGoLive` bo‘sh). Prod tekshiruvi — faqat o‘qish yoki `sinov`
kassada o‘quv to‘lovisiz operatsiyalar (`in_other` / `out_expense`, «СИНОВ»); o‘quv to‘lovi smoke yo‘q (ota-onaga xabar
navbatga tushadi), majbur bo‘lsa — telefonsiz SINOV o‘quvchi va `'pay__<id>'` «skipped». `main` kassa testga
ishlatilmaydi. Ommaviy amal yo‘q: backfill — sinov ishga tushirishi, keyin buxgalter RPC si. Xabar faqat `--dry`; SMS
faqat +998 va testda emas. Repozitoriyda sir va rekvizit yo‘q. SINOV kassa hujjatlari belgilangan sinov yozuvi sifatida
qoladi. Orqaga qaytarish: git revert yoki `kassaGoLive` ni tozalash; obyektlar o‘chirilmaydi; RF-08 uchun tiklash
migratsiyasi tayyor.

**8.3 Oraliq qoidalar (16-noyabrdan; kodsiz, bir varaq).** (1) Har xarajat o‘sha kuni «Buxgalteriya»ga, izohda Р/О
raqami va kimga. (2) O‘quv to‘lovi faqat tizimda; tracker tushum to‘ldirilmaydi. (3) Bankka topshirish va bankdan olish
— kirim ham, xarajat ham emas. (4) Har kech kassir va MM sanab, qisqa dalolatnoma imzolaydi. (5) Zavxoz qog‘ozda joriy
qoldiq va chek; qaytim kirim orderi bilan. (6) Kun boshi qo‘lda tuzatilmaydi. (7) Maosh va avans faqat tizimdagi
«Maosh berish» va «Xodim avansi» orqali; noyabr vedomosti tizimda tasdiqlanadi. (8) Qaytarish faqat «↩ Qaytarish»
orqali. (9) Qog‘oz order daftarlari 31-dekabrda dalolatnoma bilan yopiladi. (10) Sheet faqat tarix uchun.

**8.4 O‘tish.** 21-dekabr: navbat bo‘shligi, deploy, verify-db, `kassa-checks.sql`, `sinov` smoke, `tg-daily --dry`.
31-dekabr (yoki oxirgi ish kuni) kechqurun: komissiya sanashi → `kassa_opening` (farq majburlanmaydi, direktor hal
qiladi); buxgalter daftarlarni yopish dalolatnomasini imzolaydi (006); direktor `kassaGoLive`, imzolar, limit, T1, L1 ni
kiritadi; F0.7 qoldiqlari; to‘lanmagan qaytarishlar ro‘yxati; 31.12 23:59 surati. 4-yanvar: rasmiy boshlanish.

**8.5 Parallel yuritish (≤ 5 ish kuni, AC1.19 bajarilguncha).** MMning kunlik ro‘yxati (≈ 10 daqiqa): sanash = tizim;
har KO qog‘oz manbasi va outbox / «Қ» jurnali bilan belgilangan; Click/Uzum kabinet = kanal bloki; bank = `in_bank` /
`out_bank`; raqamlar uzluksiz, bekor qilishlar izohlangan; Telegram = RP-02; P1/P4/P5/P8 = 0. Excel soyasi yuritilmaydi.

**8.6 Orqaga qaytish (ish jarayoni).** «Қ» blankalari oxirgi tizim raqamidan davom etadi; Excel oxirgi tizim kun oxiridan
qayta boshlanadi; tizim hujjatlari haqiqiy qoladi; buxgalter oyni birlashtiradi; qayta ishga tushirish yangi sanashdan.

**8.7 O‘qitish** (faqat stendda): kassirlar va o‘rinbosar 2 × 90 daqiqa; MM 60; buxgalter 60; direktor 30; HR 30
(vedomost tasdig‘i — maosh kunidan oldin); hisobdorlar (zavxoz, oshpaz) 20 daqiqa («Олдим», cheklar, qaytim, yanvar
avans hisoboti); keyingi bosqichlar 30–60 daqiqa.

**8.8 Qo‘llab-quvvatlash.** 2 hafta kunlik 15 daqiqalik qo‘ng‘iroq; kassa soatlarida navbatchi; P1 — o‘sha kuni (aks holda
«Қ»), P2 — 2 kun, P3 — keyingi reliz; server ishlamasa — NKM oflayn cheki + outbox yoki «Қ» + kech kiritish; NKM ishlamasa
— maxsus kvitansiya daftari; haftalik ko‘rik (RP-22).

**8.9 Voz kechish.**
| Artefakt | O‘rniga | To‘xtaydi |
|---|---|---|
| Excel kunlik varaqlari | KO-4 + RP-02 | parallel yuritish chiqishi (≈ 9-yanvar) |
| Excel kirim orderlari va qog‘oz П/О, Р/О daftarlari | KO-1 + patta, KO-2 | 31-dekabr (yopish dalolatnomasi; arxiv ≥ 5 yil) |
| Tracker chiqim | KO-2 + Buxgalteriya reyestri | parallel yuritish chiqishi |
| Tracker tushum va shablonlar | tizim fakturalari va to‘lovlari | 16-noyabrdan to‘ldirilmaydi |
| Tracker Dashboard | RP-02, RP-08/09, Moliya ekranlari, RP-19 | 2-bosqich |
| Zavxoz varag‘i | hisobdor kartochkasi + avans hisoboti | ishga tushirish |
| Bank varaqlari | bank importi | 3-bosqich |
| Buxgalterning Excel KO-1 / KO-4 | tizim chop etishlari | ishga tushirish |

Sheet funksiyalari inventari (F0.19): har varaq — kim, nima uchun, o‘rnini nima bosadi yoki «egasi voz kechdi»; Drive
«faqat ko‘rish» sanasini egasi belgilaydi (tavsiya ≈ 15-yanvar).

---

## 9. Talablar → vazifalar
| Talab | Qayerda |
|---|---|
| REQ-01 «Xuddi 1C kabi» | §1.2, §4; F1.1–F1.16, F2.6, F3.2–F3.4, F4.1–F4.6, F5.1 |
| REQ-02 / 03 Kunlik kirim va chiqim | KO-1 / KO-2 (F1.4, F1.10); RP-02 (F1.15); RP-08 (F1.22) |
| REQ-04 Qoldiq | KO-4 kun oxiri (F1.9); KPI (F1.12); Telegram (F1.15) |
| REQ-05 Hujjat raqami | F1.3; FD-05; chop etish F1.14 |
| REQ-06 / 07 Kun boshi va oxiridagi kassa | I3, sanash dalolatnomasi, farq shu kun (F1.9, FD-21, §8.4) |
| REQ-08 / 09 Kimga / kimdan qancha | KO-2 «Берилсин», KO-1 «Олинди», tomon majburiy (CT-22), RP-02 (F1.15), kontragentlar (F1.1, F2.2) |
| REQ-10 Hammasi avtomatik | §4.16 (avtomatik hujjatlar, qo‘lda qoladigan qadamlar); F3.3, F4.3, F4.5 |
| REQ-11 Har xarajat statiya bo‘yicha | CT-23, F1.4, F1.13, F2.1, F2.6, §4.4, F2.3, RP-08/09, F4.3, F5.1; to‘liqlik jadvali §4.16 |
| REQ-12 Ish rejasi | §5, §5.9, §6 |
| REQ-13 Dizayn to‘xtatilgan | mavjud komponentlar; AC1.17; alohida modul |
| REQ-14 Namunalarni o‘rganish | §2, B-ilova, §4.15 |
| CON-01 Sentyabr–oktyabr Sheet’da | FD-27; §8.3; §8.9 |
| CON-02 Pul hisoblash qoidalari o‘zgarmaydi | bosh kitob faktura summasini oladi; F2.7 summani o‘zgartirmaydi |
| CON-03 D1–D9 | D2 — §4.10; D6/D7 — FD-28; D9 — PR-23 |
| CON-04 Prod xavfsizligi | §8.1–§8.2 |
| CON-05 Ommaviy repozitoriy | belgilar, yopiq ilova, sozlamalar |
| CON-06 Muhandislik qoidalari | §3.3, §4.17, F0.10, F1.18 |

---

## A-ilova. Manbalar
Qonunchilik (lex.uz): Buxgalteriya hisobi to‘g‘risidagi qonun (O‘RQ-404) — https://lex.uz/docs/-2931253 ; Hujjatlar va
hujjatlar aylanishi nizomi (IMV 143, ro‘yxat 3538) — https://lex.uz/docs/-7041901 ; BHMS 21 (191-buyruq, ro‘yxat 3593) —
https://lex.uz/uz/docs/7282737 , https://lex.uz/ru/docs/7282759 (eski 1181: https://lex.uz/ru/docs/417624) ; BHMS 19
(ro‘yxat 3548) — https://lex.uz/docs/-7058433 ; BHMS 9 (ro‘yxat 3592) — https://lex.uz/docs/-7282782 ; Moliyaviy
hisobotlar nizomi (181-buyruq, ro‘yxat 3567) — https://lex.uz/uz/docs/7194594 ; Soliq kodeksi — https://lex.uz/docs/-4674902 ;
MB yo‘riqnomasi (ro‘yxat 3003) — https://lex.uz/ru/docs/3716827 ; MB kassa qoidalari 2687 (2019 dan kuchsiz, namuna) —
https://lex.uz/acts/2683847 , https://lex.uz/docs/-2683844 ; PF-5813 — https://lex.uz/docs/-4502381 ; VM 943 —
https://lex.uz/docs/-4603329 ; PF-246 — https://lex.uz/docs/-7897630 ; PQ-403 — https://lex.uz/docs/7231946 ; VM 424 —
https://lex.uz/docs/-6139421 ; INPS tartibi (ro‘yxat 3577) — https://lex.uz/uz/docs/7231786 .
1C va amaliyot: https://1c.uz/v8/generic_products/uz_accounting.php ; https://1c.uz/v8/accounting2.0-3.0.php ;
https://scloud.ru/ask_question/bank-i-kassa/formirovanie-kassovoy-knigi-ko-4-v-1s-8-3-bukhgalterii-3-0/ ;
https://42clouds.com/ru-ru/manuals/uchet-kassovyh-operaczij-v-1s-buhgalteriya/ ; https://buh.ru/articles/faq/47496/ ;
https://buhexpert8.ru/?p=244283 ; https://buxgalter.uz/publish/doc/text211644_kak_vesti_kassovuyu_knigu111 ;
https://buxgalter.uz/publish/doc/text217782_kak_oformit_prihodnyy_kassovyy_order2 ;
https://buxgalter.uz/publish/doc/text213124_zapolnenie_avansovogo_otcheta_v_uzbekistane_obrazec_i_oformlenie_v_1s ;
https://buxgalter.uz/ru/publish/doc/text211689_provodki_po_zarplate_v_uzbekistane_nachislenie_uderjaniya_vyplata ;
https://docs.click.uz/merchant-api/fiscalization ; https://developer.help.paycom.uz/metody-merchant-api/setfiscaldata/ .
Tasdiqlanmagan: INPS stavkasi manbasi; admin ilovasiga VM 943, 4-band tatbiqi; korxona o‘lchami; SK 483 ning qo‘shimcha
daromadga tatbiqi; QR majburiyatining maktabga tatbiqi.

## B-ilova. Namunaviy varaqlar tuzilmasi (summasiz)
- **Kunlik kassa varag‘i:** A Sana | B Kun boshiga qoldiq | C Tushum | D Jami chiqim | E Kun oxiriga qoldiq (`=B+C−D`) |
  F Click | G Uzum | H Пластик Карта Узкарт | I Банк Х/Р тушган | J П/К.Клик.Узум услуга 1 % | K Банкдан тушган пуллар |
  L прочи тушумлар | M укиш пули; kuniga bitta qator (Du–Sh), hujjat ro‘yxati yo‘q.
- **Kirim orderlari:** oktyabr — B «Сана», D «Кимдан» (boshida `П/О-N`), E «нима учун», F «сумма»; noyabr — A «Сана»,
  B «№» (butun son), C «Кимдан», D «нима учун», E «сумма».
- **Tracker chiqim:** A ID `<prefiks>-EXP-nnnn` (har oy qaytadan), B sana, C oy, D toifa (13), E tavsif (`Р/О-N`, 9+
  yozilish shakli), F tavsif, G kim so‘radi, H tasdiqlovchi, I usul, J summa, K kimga, L chek № (noyabrda Р/О), M holat.
- **Tracker tushum:** A ID, B ism, C sinf, D holat, E kunlar, F–G narx va prorata, H chegirma %, I–N kasal kun, tavsiya,
  mukofot, O tasdiqlovchi, P tuzatish, Q oy boshi qoldig‘i, R kutilgan, S–W to‘langan (Naqd/POS/Click/Uzum/Bank), X jami,
  Y qoldiq, Z sana (matn), AA kvitansiya raqami (noyabr, naqd), AB izoh.
- **Kassir kirim kitoblari:** A sinf / ID, B ism, C Naqd, D Click, E Uzum, F Terminal, G sana, H jami, I izoh; Bank yo‘q.
- **«Jami»:** C–E oylar (boshqa varaqqa qator o‘rni bo‘yicha havola), F jami, J tizim bilan solishtirish izohi, K to‘lov,
  M farq (`F − K`).
- **Bank aylanmasi:** sana | to‘lov maqsadi | kirim | chiqim; hujjat №, kontragent, STIR, hisob raqami yo‘q.
- **Zavxoz hisobi:** Sana | Kun boshiga qoldiq | Maqsadi | Berilgan | Ishlatilgan | Qaytim | Qoldiq | Izoh.
- **KO-1 shabloni (foto):** A–H order, I kesish chizig‘i, J–M «патта»; «Форма КО-1», «сонли ҒАЗНА КИРИМ ОРДЕРИ», sana;
  jadval «Дебет» | «Кредит» (корреспондент / таҳлилий / мақсадли йўналиш) | «Пул миқдори»; «Олинди», «Асоси»,
  «Қиймати ёзув билан», «Иловаси», «Топширди»; patta: «Олинди», «Асоси», «Қиймати сўз билан», «Қабул қилди». Yo‘q: joy,
  lavozim va F.I.Sh., bosh buxgalter va kassir qatorlari.
- **KO-4 sahifasi (foto):** «Касса за {sana}» (qo‘lda), «Лист {N}»; ustunlar 1–5: hujjat raqami (bo‘sh) | kimdan /
  kimga | korrespondent hisob | kirim | chiqim; kun boshi, jami, kun oxiri; format so‘m=tiyin, ajratgichsiz
  (`1234567=89`), nol «-», tegishli emas «X»; kassir va buxgalter imzosi, «… {N} приходных и {M} расходных получил».
- **Yangi formatlar:** «№ 1234»; KO-4 da «К-1234» / «Ч-567»; «Варақ N»; «Д-n», «ЎҲ-n», «А-n», «JV-n»; «2027 йил 4
  январь»; «1 234 567=89»; har seriya 1-yanvardan 1 dan.
