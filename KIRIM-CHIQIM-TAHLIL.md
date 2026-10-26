# Kirim-chiqim: Google Sheet («IQRO_Financial_Tracker_2026_2027») va tizim — tahlil

Sana: 2026-10-26. Manba: Sheet nusxasi (2026-10-24 holati; 26 varaq) va tizim kodi (`9ef9416`).
Tahlil 4 bosqichda qilindi: tizimdagi moliya modulining inventarizatsiyasi, Sheet formulalarining semantikasi,
farqlar jadvali + taklif, raqib-tekshiruv (har raqam qayta hisoblangan).

## 1. Qabul qilingan qarorlar (2026-10-26)
- **Hozircha faqat tahlil** — tizim kodi o'zgarmaydi. Topilmalar buxgalter bilan ko'rib chiqiladi.
- **Import yo'q** — sentyabr–oktyabr tarixi Sheet'da qoladi; noyabrdan tizim asosiy manba.
- **Pul hisoblash qoidalari tizimdagidek qoladi** (avtomatik chegirmalar, haqiqiy ish kunlari, referral 300 000 bir marta).

## 2. Sheet tuzilishi (qisqa)
- `Dashboard` (tanlangan oy — `C4`), `Lists` (ro'yxatlar), har oy uchun `<Oy> tushum` / `<Oy> chiqim` juftligi (Sentyabr … Avgust).
- **Tushum** — har o'quvchi uchun qator (sinf bloklari `--- 1A SINFI ---`): `A` ID, `B` ism, `C` sinf, `D` holat
  (Active / Joined Mid-Month / Exited Mid-Month / Inactive-Left), `E` faol kunlar (22), `F` to'liq narx,
  `G` prorata narx = `F/22·E` (oy o'rtasida kirgan/ketgan), 0 (chiqib ketgan), `H` doimiy chegirma % (0/0,05/0,1/0,5/1),
  `I` kasal kun → `J = I·40 000` (faqat `H ≤ 0,1`), `K` referral soni → `L = G·K·20 %` (faqat `H ≤ 0,1`),
  `M` Reward (None / Reward 20 / Reward 100) → `N`, `O` tasdiqlovchi, `P` jami tuzatish = `G·H + J + L + N` (Reward 100 → `G`),
  `Q` oy boshiga qoldiq = **oldingi varaqning o'sha qatoridagi `Y`** (manfiy = avans), `R` kutilgan = `max(0, G − P + Q)`,
  `S…W` to'langan: Naqd / POS / Click / Uzum / Bank (ba'zi kataklar `=1000000+1100000` ko'rinishida — bir necha to'lov),
  `X` jami to'langan, `Y` qoldiq = `(G − P + Q) − X` (manfiy bo'lishi mumkin), `Z` sana (erkin matn), `AA/AB` izoh.
- **Chiqim** — `A` ID (`IQRO-EXP-nnnn`, qator raqamidan formula), `B` to'langan sana, `C` oy, `D` toifa (13 ta),
  `E` «Subcategory» (amalda tavsif, ko'pincha ruscha, `Р/О-nn` kassa orderi raqami bilan), `F` tavsif, `G` kim so'radi,
  `H` kim tasdiqladi, `I` usul, `J` summa, `K` kimga, `L` chek №, `M` holat (Planned / Paid / Cancelled).
- **Dashboard** — tanlangan oy bo'yicha: jami/faol/yangi/ketgan/nofaol o'quvchilar; Kutilgan (`ΣR`), Haqiqiy (`ΣX`),
  Qarzdorlik (`ΣY`, sof: qarz − avans), Jami xarajat (`ΣJ`), Yig'im % (`ΣX/ΣR`); foyda = tushum − xarajat; to'lov usullari;
  chegirmalar tahlili (`ΣG·H`, `ΣJ`, `ΣL`, `ΣN`); xarajat toifalari; 12 oylik jadval; sinflar kesimida jadval.

## 3. Sheet'ning o'zida topilgan muammolar (buxgalter tekshirsin)
1. **«Noyabr tushum» buzilgan.** 347 qatorning hammasi «Active» (53 ta chiqib ketgan ham); oktyabrda qo'shilgan 11 o'quvchi
   varaqda yo'q — ularning qoldiqlari yo'qoladi: qarz 19 322 273 (IQ-0512 1 795 000; IQ-1019 527 273; IQ-0465, IQ-1018,
   IQ-1022, IQ-0497, IQ-0509 — 2 900 000 dan; IQ-1016 2 500 000) va avans −2 901 182 (IQ-0535 −2 900 000; IQ-1025 −818;
   IQ-0533 −364); sof 16 421 091. Dashboard'da Noyabr «Kutilgan» 1,33 mlrd bo'lib ko'rinishi shundan.
2. **Takroriy ID.** IQ-0474 — 1A da (`H = 0,1`) va 1B da (`H = 0`), ikkalasida ham to'lov bor; IQ-0250 («Saidov MuhammadAli»
   1V va «Saidov Muhammadali» 1A); IQ-0021 («Murodov MuhammadUmar» 1B va 1A). Bir bola bo'lsa — oktyabr Kutilgan/Qarzdorlik
   5 800 000 (IQ-0474 ning 4 190 000 qarzi bilan 9 990 000 gacha) ortiqcha.
3. **ID'siz to'lovlar** (hech kimning balansiga tushmagan, lekin «usullar» plitkasida bor): sentyabr 12 000 000
   (29-qator 1 200 000; «Sharahmedov Imronbek» 2 900 000 Uzum — keyin IQ-1015 bo'lgan, lekin Q = 0; «Хамидова Марзия»
   2 900 000; 601–608-qatorlar avgust tushumi 5 000 000); oktyabr 5 800 000 («Хамидова Марзия», hali ham ID'siz).
4. **Chiqib ketganlar.** 10 tasida avans −16 600 000 abadiy «osilib» qolgan; 4 tasiga pul chiqimda qaytarilgan (IQ-0212
   2 900 000; IQ-0196, IQ-0234, IQ-0366 — 1 000 000 dan) — avans ham turadi, chiqim ham: ikki marta hisob. 6 tasida
   qarz 11 810 000 (IQ-0007, IQ-0246, IQ-0331 — 2 900 000 dan; IQ-0027 1 900 000; IQ-0029 610 000; IQ-0039 600 000)
   «Kutilgan tushum»da turadi. IQ-0366 ga 11.09 da 1 000 000 qaytarilgan, lekin oktyabrda «Active», `Q = −1 000 000` —
   oktyabr Kutilgan 1 000 000 kam.
5. **Chegirma o'zgarishlari tasdiqlovchisiz** (sentyabr → oktyabr): IQ-0310, IQ-0273 — 100 % yo'qolgan; IQ-0256, IQ-0406,
   IQ-0491, IQ-0382, IQ-0300 — 10 % yo'qolgan; IQ-0204 — 10 % paydo bo'lgan. Oktyabrda `O` (tasdiqlovchi) hech qayerda yo'q.
6. **Narxsiz o'quvchilar:** IQ-0527 (3A), IQ-1017 (7A) — `F` bo'sh, 0 so'mga hisoblangan.
7. **Chiqim:** Хабибжонов 1 450 000 qaytarish sentyabr va oktyabrda ikki marta; 8.10 da izohsiz 94 802 305 «Oylik» summasi
   (sana `8.102026`); 40-qator 400 000 izohsiz; `Р/О` raqamlari takrorlangan (78, 79, 80, 89, 108, 143 — 133 raqamli
   qatordan 127 noyob), sentyabrda 171 qatordan faqat 45 tasi raqamlangan; sanalar 40 ga yaqin ko'rinishda
   (`16.09.206`, `14.09.2020`, `21.09.2025`).
8. **Bankka topshirilgan tushum xarajat deb yozilgan** (30 000 000 — 11.09; 20 000 000 — 14.10) — foyda shuncha kam
   ko'rinadi: haqiqiy sof foyda sentyabr 280 563 700 (Sheet: 250 563 700), oktyabr 163 899 130 (Sheet: 143 899 130).
   Shuningdek «Boshqa»da ijara (14 800 000 + 1 500 000; 13 218 000) va O'qituvchilar kuni (12 210 000); «Oylik»da
   «Irodaopa marketing» 19 100 000; «Soliqlar»da tadbir oldindan to'lovi 1 030 000; 100 000 «камзур пули кайтди» —
   bu forma qaytarishi, o'quvchi to'lovi emas.
9. **Kelgusi oylar shabloni (Iyul)** iyundan farq qiladi: 5 qatorda ID boshqa o'quvchiga o'tgan (18, 73, 265, 320, 421-qatorlar),
   4 qator boshqa o'quvchining qoldig'ini ko'chiradi (Σ 98 600 000) — `Q` qator o'rniga bog'langani uchun. Dashboard'da
   Iyul Kutilgan (7,53 mlrd) < Iyun (7,89 mlrd).

## 4. Raqamlar (Sheet bo'yicha, qayta hisoblangan)
| | Sentyabr | Oktyabr |
|---|---|---|
| Qatorlar / noyob ID | 336 / 335 | 368 / 365 (30 ta yangi) |
| Holatlar | Active 280, Joined 4, Left 52 | Active 308, Joined 5, Exited 2, Left 53 |
| To'liq narx `ΣF` | 961 940 000 | 1 048 740 000 (2 bo'sh) |
| Prorata narx `ΣG` | 807 649 090,91 | 885 153 636,36 |
| Tuzatishlar `ΣP` | 68 150 000 (faqat `G·H`) | 66 410 000 = 62 350 000 (`G·H`) + 4 060 000 (Reward 20 × 7) |
| Oy boshi qoldiq `ΣQ` | 0 | 138 591 090,91 |
| **Kutilgan `ΣR`** | 739 499 090,91 | 995 974 727,27 (12 qatorda 38 640 000 avans «kesilgan») |
| **Haqiqiy `ΣX`** | 600 908 000 | 562 260 000 |
| — Naqd / POS / Click / Uzum / Bank | 397 632 000 / 39 520 000 / 115 670 000 / 21 640 000 / 26 446 000 | 325 966 000 / 49 014 000 / 115 610 000 / 24 030 000 / 47 640 000 |
| **Qoldiq `ΣY`** (sof) | 138 591 090,91 = qarz 202 652 545,45 (101) − avans 64 061 454,55 (28) | 395 074 727,27 = qarz 453 444 272,73 (175) − avans 58 369 545,45 (29) |
| Yig'im % | 81,26 % | 56,45 % |
| **Xarajat `ΣJ`** | 350 344 300 (171 qator) | 418 360 870 (137 qator) |
| — toifalar | Oylik 149 443 900; Boshqa 84 514 400; Oziq ovqat 76 232 000; Transport 28 110 000; Ta'minot 7 834 000; Administratsiya 3 180 000; Soliqlar 1 030 000 | Oylik 225 253 870 (shundan izohsiz/vedomost 153 112 305); Boshqa 64 604 000; Oziq ovqat 63 311 000; Transport 52 100 000; Marketing 12 000 000; Ta'minot 1 092 000 |
| Sof foyda (Sheet) | 250 563 700 | 143 899 130 |
| Tasdiqlovchi (chiqim) | Finance Manager 140, Principal 28, Head of Academic 2, bo'sh 1 | Finance Manager 133, Principal 4 |
| Usul / holat / chek № (chiqim) | 100 % Cash / 100 % Paid / hech qachon | 100 % Cash / 100 % Paid / hech qachon |

Chegirma darajalari (oktyabr): 0 % — 317, 10 % — 26, 50 % — 12, 100 % — 13; 5 % — hech kim. Kasal kun va referral ikki oyda
ham ishlatilmagan (0). Reward 20 — 7 o'quvchi (580 000 dan).

## 5. Tizim bilan solishtirish
### 5.1 Tushum (o'quvchi to'lovlari)
| Sheet | Tizimda | Holat |
|---|---|---|
| Oylik varaq, ID, ism, sinf | `invoices` (har o'quvchi-oy uchun faktura), `students` | **bor** (sinf — hozirgi sinf bo'yicha guruhlanadi, faktura sinfi ham saqlanadi) |
| Holat (Active / Joined / Exited / Left), faol kunlar | `payStatus` + `activeFrom` / `stopFrom` / `pauses`; prorata haqiqiy ish kunlari bo'yicha | **qisman** — sanalar bilan, qo'lda kun yozilmaydi |
| To'liq narx (`F`) | `price_table` (til-sinf-yo'nalish) yoki «Kontrakt» | **qisman** — o'quvchiga alohida narx faqat «Kontrakt» orqali |
| Doimiy chegirma % (`H`) | avtomatik: aka-uka 10 %, xodim farzandi 50 %, olimpiada 100 %; monitoring 20 / 100 % | **qisman** — qo'lda % va tasdiqlovchi yo'q, 5 % yo'q |
| Kasal kun 40 000 (`I`, `J`) | o'tgan oy davomatidagi «kasal» kunlar × `sickRate` | **bor** (bir oy kechikish bilan) |
| Referral 20 %/oy (`K`, `L`) | 300 000 bir marta | **qisman** — qoida boshqa |
| Reward 20/100 (`M`, `N`) | o'tgan oy tasdiqlangan monitoring ≥ 90 / ≥ 100 | **qisman** — qo'lda belgilash yo'q, eng yuqori daraja olinadi (yig'ilmaydi) |
| Tasdiqlovchi (`O`) | — | **yo'q** |
| Oy boshi qoldiq (`Q`), kutilgan (`R`), oy oxiri qoldiq (`Y`) | qarz — ochiq fakturalar (eng eskisi birinchi to'lanadi), avans — `student_credit`; alohida ko'rinadi | **qisman** — bitta qatorda `Q → R → Y` ko'rinishi yo'q |
| To'lov usullari (`S…W`) | `payments.provider`: cash / terminal (= POS) / click / uzum / bank | **bor** (o'quvchi-oy qatorida ustun-ustun ko'rinmaydi) |
| Sana, izoh (`Z`, `AA`) | har to'lov alohida yozuv (sana, izoh), `pay_notes` | **bor** (yaxshiroq) |
| ID'siz to'lovlar | «Biriktirilmagan to'lovlar» → «Biriktirish» / bo'lish | **bor** (yaxshiroq) |
| Qaytarish | «To'lovlar → ↩ Qaytarish» (direktor + PIN), kirimni kamaytiradi | **bor** (yaxshiroq); faqat avansni naqd qaytarish yo'li yo'q |

### 5.2 Chiqim (xarajatlar)
Tizimda («Buxgalteriya → + Xarajat qo'shish»): **sana, toifa, summa, izoh** — shu to'rttasi. Sheet'dagi **yo'q** maydonlar:
kim tasdiqladi, `Р/О` №, usul, kimga berildi, kim so'radi, chek №, holat, muallif. Oy sanadan olinadi (alohida tanlanmaydi).
Toifalar: tizimda 21 ta, Sheet'da 13 ta — mosligi 9-bo'limda. Xarajat chek chop etish, toifalar bo'yicha diagramma/jadval,
A4 direktor hisoboti — **bor**.

### 5.3 Dashboard
| Sheet | Tizimda | Holat |
|---|---|---|
| Oy tanlash | Buxgalteriya / Moliya / To'lovlar — bor; Statistika moliya bloki — faqat joriy oy | **qisman** |
| Jami / faol / yangi / ketgan / nofaol o'quvchi | joriy ro'yxat bo'yicha; oy bo'yicha hisoblanmaydi | **qisman** |
| Kutilgan tushum (qoldiq bilan) | yo'q; «yig'ildi + kutilmoqda» faqat shu oy fakturasi | **yo'q** |
| Haqiqiy tushum | «Kirim» — shu oy fakturasiga to'langan; kassa bo'yicha tushgan pul — «To'lovlar → Hisobot» | **qisman** (asos farq qiladi, 7-bo'lim) |
| Qarzdorlik (sof) | qarz va avans alohida | **qisman** |
| Jami xarajat, toifalar, to'lov usullari | bor | **bor** |
| Yig'im % | faqat shu oy fakturasi asosida | **qisman** |
| Chegirmalar tahlili | fakturada ustunlar bor, yig'indi yo'q | **yo'q** |
| 12 oylik jadval (Sentyabr–Avgust) | 6–8 oylik grafiklar; jadval va o'quv yili ramkasi yo'q | **qisman** |
| Sinflar kesimida (faol / kutilgan / haqiqiy / qarz / yig'im %) | «To'lovlar»da sinf sarlavhasida yig'ildi/qarz; Moliyada sinf (parallel) bo'yicha daromad | **qisman** |
| Excel / CSV eksport | moliya jadvallarida yo'q (o'quvchilar ro'yxatida bor) | **yo'q** |

Jami: tushumning 27 ustunidan 9 **bor**, 15 **qisman**, 3 **yo'q**; chiqimning 13 ustunidan 3 bor, 2 qisman, 8 yo'q;
Dashboard'ning 17 blokidan 5 bor, 8 qisman, 4 yo'q.

## 6. Qoidalar farqi (raqamlar bilan) — tizim qoidalari qoladi, oqibatlari
| № | Mavzu | Sheet | Tizim | Oqibat |
|---|---|---|---|---|
| D1 | Prorata bo'luvchisi | doim 22 kun | haqiqiy Du–Ju ish kunlari: 2026-09 **22**, 10 **22**, 11 21, 12 23, 2027-01 21, 02 20, 03 23, 04 22, 05 21, 06 22 | sentyabr–oktyabr bir xil; noyabrdan farq: 10 kun × 2 900 000 → Sheet 1 318 182, tizim noyabr 1 380 952 |
| D2 | «Active», lekin E < 22 (IQ-0455: 17 kun, to'liq hisoblangan) | mumkin | sanalar hal qiladi | — |
| D3 | Doimiy 10 / 50 / 100 % | qo'lda (oktyabr: 26 / 12 / 13 o'quvchi = 62 350 000) | avtomatik; qo'lda faqat «Kontrakt» | 51 o'quvchi kartasida belgilanishi kerak: «Aka-uka chegirmasi — Ha», «Xodim farzandi», «Olimpiada»; aka-uka avtomatikasi Sheet bermagan oilalarga ham 10 % qo'shishi mumkin |
| D4 | 5 % darajasi | bor, ishlatilmagan | yo'q | — |
| D5 | Reward 20 / 100 | qo'lda (7 o'quvchi × 580 000) | o'tgan oy tasdiqlangan monitoring ≥ 90 / ≥ 100 | monitoring tizimda tasdiqlanmasa — 0 % |
| D6 | Yig'ilish | 10 % + Reward 20 = 30 % (IQ-0312: 870 000) | eng yuqori daraja (580 000) | IQ-0312 ga oyiga −290 000 |
| D7 | Kasal kun | o'sha oy, qo'lda | o'tgan oy davomati, keyingi faktura | bir oy kechikish; davomatda «kasal» belgilanishi shart |
| D8 | Referral | 20 % × G × soni, har oy | 300 000 bir marta | 10 oyda 5 800 000 vs 300 000 (Sheet'da ishlatilmagan) |
| D9 | Yaxlitlash | kasr (2 240 909,09) | butun so'm | ahamiyatsiz |
| D10 | Alohida narx (`F`) | o'quvchi bo'yicha (≈ 23 o'quvchi 1 500 000 … 2 700 000) | sinf narxi yoki «Kontrakt» | shu o'quvchilar «Kontrakt» yoki `price_table`da alohida yo'nalish bilan |

## 7. KPI asosi: kassa va faktura
Sheet **kassa asosida** ishlaydi (shu oy tushgan pul), tizimdagi «Kirim» **faktura asosida** (shu oy fakturasiga to'langan;
eng eski qarz birinchi to'lanadi). Sheet raqamlari tizimga kirgan taqdirda ko'rinadigan manzara: sentyabr fakturalariga
536 846 545 (72,60 %; 64 061 455 avansga), oktyabr fakturalariga 440 044 364 / 818 743 636 (**53,75 %**; oktyabr naqdining
128 197 545 so'mi sentyabr qarziga ketadi) — Sheet'dagi 562 260 000 / 56,45 % emas. Sof qoldiq ikkalasida bir xil:
395 074 727. Ikkala asos ham ko'rsatilishi kerak: «tushum» — kassa, «qarz» — faktura.

## 8. Keyinroq qilinsa — taklif (hajm bo'yicha tartibda)
1. **Hisobotlar (baza o'zgarmaydi):** Kutilgan (qoldiq bilan), Yig'im % ikki asosda, Sof balans; sinflar jadvali
   (hozirgi / faktura sinfi); 12 oylik jadval (sentyabr–avgust); chegirmalar tahlili; Statistika'da oy tanlagich;
   Excel/CSV eksport Sheet formatida (SheetJS tizimda allaqachon bor).
2. **Xarajat reyestri:** `expenses` ga tasdiqlovchi, `Р/О` № (erkin matn), usul (standart naqd), kimga, tur
   (xarajat / bankka topshirish / eski), muallif; toifalar: Akademik, HR, Administratsiya, Tadbirlar, «Bankka topshirish»
   (foydaga kirmaydi); huquqlar toraytiriladi (marketing ko'rmasin). Holat/tasdiq oqimi, raqamlash — **yo'q** (Sheet'da hamma
   qator Paid, chek № hech qachon yozilmagan).
3. **«Tushum registri» ekrani:** har o'quvchi uchun oy bo'yicha qator — holat, ish kunlari, narx, chegirmalar, oy boshi qoldiq,
   kutilgan, usullar bo'yicha to'lov, avansdan, jami, oy oxiri qoldiq, sanalar, izoh; qatorga bosilsa — to'lov tarixi; eksport.
4. **Import (rad etildi):** Sheet → tizim faqat dry-run va solishtiruv bilan; oldin 3-bo'limdagi savollarga javob kerak.
5. **Chegirma modeli (rad etildi):** o'quvchi kartasida «Doimiy chegirma %», «Kim tasdiqladi», «Sabab».
6. **Kassa:** avansni naqd qaytarish (`refund_credit`), kunlik kassa qoldig'i (naqd tushum − naqd xarajat − maosh − avans − qaytarish).

## 9. Noyabrdan tizimda yuritish — amaliy tavsiyalar
- **To'lovlar:** har to'lov «To'lovlar»da usuli bilan (Naqd / Terminal / Bank / Uzum qo'lda; Click va Uzum onlayn o'zi tushadi).
  ID'siz to'lov — «Biriktirilmagan» ro'yxatidan biriktiriladi. Qaytarish — faqat «↩ Qaytarish», xarajat sifatida yozilmaydi.
- **Chiqim:** «Buxgalteriya → + Xarajat qo'shish»; izohga `Р/О` raqami va kimga berilgani yoziladi (alohida maydon hozircha yo'q).
  Bankka topshirilgan tushum **xarajat emas** — yozilmaydi.
- **Maosh:** faqat «Maosh berish (xodimga)» va «Xodim avansi» orqali; «Oylik maoshni yozish» oyiga bir marta. Sentyabr–oktyabr
  qoldig'i bor xodimlar uchun birinchi berishda izoh.
- **Chegirmalar:** Sheet'dagi 51 chegirmali o'quvchi kartasi tekshiriladi (aka-uka, xodim farzandi, olimpiada); Reward uchun
  monitoring tasdig'i.
- **Toifalar mosligi (Sheet → tizim):** Oylik → Maosh (faqat «Maosh berish» orqali); Kommunal to'lovlar → Kommunal; Oziq ovqat →
  Oziq-ovqat; Transport → Avtobus; Akademik → Kitoblar / Boshqa; Marketing → Marketing; Outsource → Outsource (buxgalteriya);
  Ta'minot/Xo'jalik → Xo'jalik tovarlari; HR → Boshqa; Administratsiya → Kanselyariya / Boshqa; Soliqlar → Soliq;
  Asosiy vosita → Inventar; «Boshqa» ichidagilar: ijara → Ijara, remont → Ta'mir, internet/platforma → Dasturiy ta'minot,
  kitob → Kitoblar, med → Med chiqim, hayriya → Hayriya, tadbir → Boshqa.
- **Noyabr Sheet'i** ishlatilsa — avval 3.1 tuzatilsin (holatlar, 11 yangi o'quvchi); yaxshisi tizimdan eksport bilan solishtirish.
