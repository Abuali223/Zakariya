# Joriy etish rejasi — dasturchi uchun ishlar ro'yxati

Sana: 2026-10-30. Direktor uchun qisqa versiya — Claude hujjatining «Yo'l xaritasi» varag'ida
(bosqichlar, darvozalar, indikatorlar). Bu fayl — o'sha rejaning texnik tomoni: har ish, hajmi va kodning qaysi joyi.

- **Manba:** direktorning 9 qarori (D1–D9, pastda), 6 ta tahlil (kod bo'yicha, `fayl:qator` bilan) va jonli saytdagi
  umumiy o'lchovlar (faqat sonlar; ism/telefon olinmagan).
- **Hajm:** S — 1 kundan kam, M — 1–3 kun, L — 3 kundan ko'p (bitta dasturchi, testlar bilan). Jami ≈ 210 kun
  (0: ~30, 1: ~80, 2: ~40, 3: ~35, 4: ~25). Bu muddat emas — tezlikni maktab tomonidagi sinov, deploy va o'qitish belgilaydi.
- **Qoidalar:** yangi migratsiya `run-all.sql`da `rls-initplan.sql`dan YUQORIGA, zanjir himoya sarlavhasi bilan; yangi
  `SECURITY DEFINER` funksiya `search_path`ni o'zi belgilaydi; har tasdiq roli **aniq rol** bilan tekshiriladi
  (`is_finance()` g'aznachi va direktorni ham o'z ichiga oladi — ikki kishilik tasdiq bitta odamga aylanib qolmasin).

## Direktor qarorlari (2026-10-30)
| № | Qaror |
|---|---|
| D1 | Chegirma va grant — Direktor **va** Moliya menejeri tasdiqlaydi. «Bemor» kuni — hamshira ma'lumotnoma asosida (elektron nusxasi bilan) kiritadi, Moliya menejeri tasdiqlaydi, faqat tasdiqlangani to'lovga ta'sir qiladi. 100 ball — monitoring natijasidan keyin O'IBDO' 24 soat ichida kiritadi, Direktor 24 soat ichida tasdiqlaydi. Tavsiya bonusi — yangi o'quvchi to'lov qilgach, Moliya menejeri tasdig'i bilan. |
| D2 | Maoshni Moliya menejeri tayyorlaydi, HR menejer tasdiqlaydi. |
| D3 | Avtomatik SMS vaqti va matni — sayt administratori ichki sozlamalarda boshqaradi. |
| D4 | Ota-onaga Telegram orqali xabar — raqam tizimdagi raqam bilan bir xilligi tasdiqlangandan keyin. |
| D5 | Xodimning o'z arizasi bilan olgan ta'tiliga haq to'lanmaydi. |
| D6 | O'quvchi ma'lumoti ommaga ochiq emas; faqat o'quvchi, ota-ona, dars beruvchi o'qituvchilar, qabulxona, O'IBDO' va Direktor ko'radi. |
| D7 | Qabulxona va kassa ota-ona telefonini ko'radi, lekin o'z qurilmasiga yuklab ololmaydi. |
| D8 | Universitetga hujjatda JSHSHIR qoladi, sog'liq ma'lumoti ko'rsatilmaydi. |
| D9 | Yarim yillik, yillik va oldindan to'lov rejalari kerak emas (avans faqat ortiqcha to'lov uchun). |

## Jonli o'lchov (2026-10-30, umumiy sonlar)
- Hisoblar: 10 (3 direktor — biri vaqtinchalik sinov hisobi, 1 admin, 1 moliya menejeri, 1 marketing, 2 qabulxona,
  2 kassir). O'qituvchi/kurator/O'IBDO'/HR/ota-ona hisobi **yo'q**. Ro'yxatda: 35 o'qituvchi, 18 xodim, 380 o'quvchi
  (325 tasi ketmagan).
- Foydalanish: 30 kunda 346 to'lov (naqd 209, Click ~78, bank 28, terminal 24, Uzum 5; 4 tasida o'quvchi yo'q).
  Sentyabr fakturalarining ~77% summasi yig'ilgan; oktyabr (oy tugamagan) ~68%; 84 o'quvchi 1 oy qarzdor, 2+ oy — 0.
- O'quv qismi: oktyabrda davomat 0; 2099-09 oyiga yozilgan 14 sinov qatori; baho 12, monitoring 6, xarakteristika 0,
  30 kunda uy vazifasi 0; maosh to'lovi 0, ta'til 0.
- SMS (30 kun): 3 ta qo'lda eslatma (2 yuborilgan, 1 xato); avtomatik SMS ishlamayapti; tinch soat buzilishi 0.
- **Ochiq ma'lumot:** anonim so'rov `students_public`dan 380 qator (ism, sinf, ball, davomat) oladi; eski Firebase
  (alilazer-cd582) jonli — `students` 46, `teachers` 6 hujjat hammaga o'qiladi (`student_private` yopiq); GitHub
  repozitoriy ochiq va GitHub Pages eski Firebase saytini ko'rsatadi (`abuali223.github.io/Zakariya`, 200).
  Repodagi shaxsiy ma'lumotlar 1858f40 da olib tashlandi, lekin git tarixida qoladi — repozitoriy private qilinishi kerak.

## Ko'rikdan keyingi tartib (2026-10-30, 54 topilma — hammasi tasdiqlangan yoki qisman)
- **Darvoza** odamlar bilan ishni to'xtatadi (hisob ochish, o'qitish, ulash); dasturlash oldinroq boshlanishi mumkin.
- **D6 faqat sayt emas:** `students_sel` = `is_staff() OR is_cashier() OR owner` (cashier-role.sql:22) — o'qituvchi hisobi
  ochilishi bilan u ham 380 o'quvchini ko'radi. Shuning uchun xodimlar uchun D6 **1-bosqichda, o'qituvchi hisoblaridan oldin**
  (HR va marketing — 0-bosqichda, HR hisobi ochilishidan oldin).
- **D2 vaqtinchalik tartib noyabrdan:** Moliya oylik hisobotni tayyorlaydi, HR imzolaydi, keyin «Maosh berish» (canPaySalary
  admin.html:1032 hozir tasdiqsiz to'laydi). Tizimdagi darvoza (payroll_runs) — 2-bosqich.
- **Monitoring vaqtincha:** ulanmagan sinflarda M-1 monitoringi yo'q → 90+/100 chegirmasi tushib qoladi (admin.html:7811-7822);
  O'IBDO' kiritadi (hisobi 0-bosqichda). «Bemor» — D1 bo'yicha faqat tasdiqlangan kun; oqim tayyor bo'lguncha bunday kun yo'q.
- **Telegram:** raqam faqat o'quvchi kartasidagi ota/ona raqami bilan solishtiriladi (kabinet kodi — ID + 12 belgi, tasdiqsiz,
  parent-link-canon.sql:101-139); faqat shaxsiy chat (`chat.type === 'private'`), bot guruhga qo'shilmaydi; `parentPhone`
  o'zgarishi change_log'ga yoziladi (hozir yozilmaydi — change-log.sql:126).
- **24 soat** faqat 100 ball uchun (O'IBDO' + Direktor); kalendar soati, dam olish/bayram sanalmaydi. Boshqa oqimlar: «faktura
  chiqarilgan kuni tasdiqlanmagan» = muddati o'tgan; maosh — to'lov kunigacha.

## 0-bosqich — Tozalash va xavfsizlik (2–20-noyabr, ≈30 kun)

### Ommaviy saytni yopish (D6) — birinchi navbatda
- [M] Ota-ona kabineti `students_public` o'rniga faqat o'z farzandlarini o'qiydi (`owns_student_doc` RLS bor) + `child_card(sid)` RPC (sinfdagi o'rni va soni) — index.html:1631-1690, 1889-1960, 2165-2168, 2607-2615
- [S] `students_public` anon/authenticated'dan olinadi va o'chiriladi; RLS matritsa + verify-db; deploy.sh:222-224 markeri — security-2c.sql:23-30, rls.sql:77-83
- [S] «A'lochilar» bo'limi, menyu havolasi, hero tugmasi va ishlatilmaydigan reyting/qidiruv kodi olib tashlanadi — index.html:605, 633, 735-745, 1282-1321, 1538-1629; admin.html:562 (posterImage)
- [S] Ismli yutuqlar/sharhlar: ismsiz («7-sinf o'quvchisi») yoki direktor belgilagan rozilik bayrog'i; 4 namuna qatori o'chiriladi — index.html:1346-1361, 1455-1470; admin.html:666-675
- [M] Hujjatni tekshirish: `issued_documents` + `issue_doc_token(sid, kind)` + anon `verify_doc(token)` (faqat «haqiqiy, berilgan sana, turi»); kod hujjatga bitta, ko'p marta tekshiriladi, taxmin qilib bo'lmaydi (128 bit); eski `?id=` QR → «maktabga murojaat qiling»; QR token URL'ga — verify.html:43-65; admin.html:3369-3375; index.html:1925-1927
- [S] D6 (xodimlar, birinchi qadam): HR va marketing_mgr `students_sel`dan chiqariladi; HR uchun `camera_id_owner(cam)` RPC (faqat «band/bo'sh», ismsiz) — cashier-role.sql:22; auth-hardening.sql:43-48; admin.html:5003-5005, 5345-5347, 5426-5428, 5481-5483
- [S] AI'ning `/student-summary` va `/risk` yo'llari huquqshunos javobigacha o'chiriladi (sahifalar chaqirmaydi, lekin server yo'li ochiq) — ai-assistant/index.cjs:114-189, 325-341
- [S] «Ochiq natijalar» va'dalari matndan olinadi — index.html:7, 901, 913-918 (RU 1023, 1035-1040); taqdimot.html:191, 210, 224, 241-247, 331; prezentatsiya.html:173, 235
- [M] O'quvchi rasm/posterlari yopiq papkaga + signed URL; eski URL'lar ko'chiriladi — storage-rls.sql:27-28; admin.html:468-476, 4107
- [S] (ixtiyoriy) Bosh sahifa raqamlari `public_counts()` RPC'dan — index.html:2392-2395

### Telefon eksporti (D7), hujjat (D8), to'lov rejalari (D9), haqsiz ta'til (D5)
- [S] `exportStudents` / `exportStudentsPDF` — faqat direktor; boshqalarga tugma yashirin — admin.html:1655-1661, 1977-2030, 2894, 2925
- [S] O'quvchi bo'yicha chop etishda raqam niqobi (direktordan boshqasiga) — admin.html:3320, 3367-3426
- [S] Kassir uchun o'qituvchi/xodim CSV (telefon + maosh) yashiriladi — admin.html:3477-3481
- [S] «Sifat» oynasi qabulxonaga raqamni emas, faqat «noto'g'ri/yo'q» belgisini ko'rsatadi — admin.html:2836-2879
- [S] Rasmiy profil va ota-ona yuklab oladigan hujjatdan «Sog'liq holati» olinadi, JSHSHIR qoladi — admin.html:3313-3321, 3376; index.html:1928-1933
- [S] «Yillik to'lovda chegirma» va FAQ namunasi olinadi; chatbotga «faqat oylik to'lov» qoidasi — index.html:939, 1059, 1239-1240; ai-assistant/index.cjs:99-108 (bazadagi FAQ qatorini direktor tahrirlaydi)
- [S] To'lov oynasi: «kelgusi oylar uchun ham» matni, qarzdan ortiq summaga tasdiq; «oldindan to'langan» → «ortiqcha to'lov (avans)» — admin.html:8603-8605, 1630, 6502-6507
- [S] `staff_leaves.paid` (backfill `paid = type <> 'ruhsat'`, CHECK, change_log) — staff-leaves.sql:17-29; change-log.sql:138
- [M] `attMetrics`: haqsiz ta'til kuni ish kunida `dailyRate` ushlaydi (erkin soatlilar va kamera uzilishi kunida ham) — admin.html:4753-4815 (4775)
- [S] Uch joyga ulash (oylik hisobot, maosh oynasi, kunlik ko'rinish) + «Ruhsat (haqsiz)» ustuni, PDF, yorliqlar — admin.html:5141-5200, 6215-6242, 5022, 5578, 5245
- [S] D2 uchun: finance_mgr'ga «Xodimlar davomati» (staffatt) tabi — ROLE_TABS admin.html:1013; vaqtinchalik tartib: Moliya hisobot → HR imzo → «Maosh berish»
- [S] 9-qaror: bazadagi FAQ qatorini direktor admin panelda o'chiradi (kod uni olib tashlamaydi; chatbot ham o'qiydi)

### Zaxira, kuzatuv, kirish huquqlari
- [S] Serverda tekshirish: root crontab, cron xizmati, `/var/log/iqror-backup.log`da bugungi «backup OK» (+ auth + storage)
- [S] Sirlar zaxirasi: Supabase docker `.env`, har `config.json`, `sb/sb-config.js`, nginx va systemd fayllari — backup.sh
- [M] Shifrlangan nusxa O'zbekistondagi boshqa joyga (boshqa provayder yoki maktab diski; restic/rclone); xorijga faqat huquqshunos ruxsati bilan
- [M] Tiklash yo'riqnomasi + to'liq tiklash mashqi (DB + auth + storage + xizmatlar), RTO yoziladi; har chorakda
- [S] Tashqi kuzatuv (sayt, `/authapi/health`, `/pay/health`, `/ai/health`) + ikki kishiga Telegram ogohlantirish
- [S] Chuqur health: `select 1`, GoTrue, Eskiz tokeni va balansi, oxirgi muvaffaqiyatli webhook vaqti
- [S] `otp_gc` / `login_attempts_gc`ni rejalashtirish, journald hajmi
- [S] Sinov hisobini o'chirish: `child_claims`, `users`, `auth.users`, refresh tokenlar (paneldagi «O'chirish» faqat `users` qatorini o'chiradi — admin.html:4330); SQL buyrug'ini direktorga beriladi
- [S] GitHub: Pages'ni o'chirish va `main`dan `.github/workflows/pages.yml`ni olib tashlash; deploy key (faqat o'qish) → sinov deploy → keyin repo private (deploy.sh:26 `git fetch` ochiq URL'dan oladi)
- [S] Eski Firebase (alilazer-cd582): Firestore **va Storage** qoidalari «hammasi yopiq» (main: storage.rules `read: if true`); loyihani o'chirish — eksport saqlangani tasdiqlangandan keyin
- [M] Ishdan bo'shatish tartibi: auth serverda «bloklash» (rolni olish + status + GoTrue sessiyalari), Foydalanuvchilar bo'limida tugma
- [S] Qaror: `is_admin`/`is_zavuch` statusni tekshirsinmi (rls.sql:28-30; auth-hardening.sql:58-61) yoki faqat rolni olish kirishni yopadi deb hujjatlash
- [S] Ikkinchi texnik mas'ul; kalit va parollar ro'yxati xavfsiz joyda

### Ma'lumot tozaligi va ish tartibi
- [S] 24 namuna yozuv, bosh sahifa raqamlari, 2099-09 davomat qatorlari
- [S] Biriktirilmagan to'lovlar, yetim fakturalar, 2 takroriy maosh ID, yo'q o'quvchiga bog'lanish — predeploy-checks.sql, «Ma'lumot sifati» paneli
- [M] 31-oktyabr qoldiqlari: Sheet ↔ tizim, har o'quvchi bo'yicha (moliya tasdiqlaydi)
- [S] Chegirma toifalari (51) va alohida narxlar (~23) kartalarda
- [S] Telefonlar sifati (noto'g'ri / yo'q / faqat xorijiy)
- [S] Oylik ish taqvimi (kim, nima, qachon) va rollar jadvali — direktor imzolaydi

## 1-bosqich — Pul qarorlari tasdig'i, D1 (16-noyabr – 25-dekabr, ≈80 kun)

### Xodimlar uchun D6 — o'qituvchi hisoblaridan OLDIN
- [M] `app.student_class_key()` (classKeyOf bilan bir xil — admin.html:2032) + yangi `students_sel`: director/zavuch/reception/egasi + teacher/kurator/homeroom faqat o'z sinflari; `is_staff()` o'zgarmaydi (boshqa policy'lar ishlatadi)
- [M] Kassa/moliya uchun `students_billing` ko'rinishi (ism, sinf, holat, sanalar); kassaga ota-ona telefoni (D7: ko'radi, yuklab olmaydi); ball/davomat/rasm yo'q — admin.html:7951, 5938, 7147, 7244, 2927
- [S] admin/admin_head: «Kasal bolalar» va fikrlar bo'yicha qaror; olimpiada, reyting, `inv_sel` (marketing'siz, `marketing_fee_stats()` RPC) toraytiriladi — sick-panel.sql:15-18; reception-access.sql:75-77
- [M] 18 foydalanuvchilik RLS matritsasi D6 qoidasi bilan qayta; har rol bo'yicha brauzer sinovi

### Ota-onalarni ulashga tayyorlik (pilotdan oldin)
- [M] Rozilik matni ro'yxatdan o'tishda (huquqshunos ko'rgan) + `users.consentAt`
- [S] OTP: Eskiz xatosida aniq xato, muvaffaqiyatsiz yuborish limitga sanalmaydi, ~8 s timeout — auth/index.cjs:135-142
- [S] Maktab IP'si uchun OTP limiti (otpMaxPerIpHour 20 — auth/config.example.json:14) va nginx `limit_req`
- [S] Eskiz'da maktab nomi bilan jo'natuvchi (koddagi standart «4546» — payments/sms.cjs:75; serverdagi sozlama tekshiriladi)
- [S] nginx gzip/brotli; [S] KaTeX/SheetJS/QR faqat kerakli bo'limda (admin.html:19-22); [S] «yangi versiya» banneri
- [M] «Haftalik hisobot» sahifasi (direktor, 8 ko'rsatkich) — hozir hech qayerda yo'q

### Umumiy asos
- [S] `app.my_role()` / `app.has_role(text)`: aniq rol + `users.status='active'`; `app.approval_actor()` (chlog_actor kabi — change-log.sql:43-51)
- [M] Tasdiq RPC namunasi: SECURITY DEFINER, advisory lock, turli tasdiqlovchi, muddat (soat parametri — test uchun), effektiv holat ko'rinishi: muddat «dangasa» hisoblanadi (cron'siz — prod'da cron yo'q)
- [M] «Tasdiqlash» bo'limi: rol navbatlari (direktor, finance_mgr, hr, zavuch), nishonlar, 24 soat hisoblagichi — admin.html:1010-1013, 1418-1445
- [S] Yangi jadvallar `chlog_attach` + CHLOG_TBL/CHLOG_FLD yorliqlari — change-log.sql:126-153; admin.html:5603-5611; full-deploy.sh trigger soni
- [M] (ixtiyoriy) Eslatma ishchisi: muddatdan 6 soat oldin va muddat o'tganda xabar (Telegram/SMS) — muddat to'g'riligi unga bog'liq emas

### «Bemor» kuni — hamshira va Moliya menejeri
- [S] `nurse` roli: `app.is_nurse()`, ROLE_LABEL/ROLE_TABS, foydalanuvchi muharriri, `students_sel` va `hol_sel`ga aniq ruxsat (is_staff'ni kengaytirmasdan), `rls-initplan` v_fns; POS_ROLE «hamshira» → nurse — admin.html:536, 1007-1013, 4272-4278, 4341-4344; cashier-role.sql:22; school-holidays.sql:34; auth/phone.test.cjs:189
- [S] `app.is_finance_mgr()` — direktor yoki finance_mgr, g'aznachisiz
- [M] `sick_notes`: sanalar → maktab kunlari, ma'lumotnoma raqami, muassasa, fayl yo'li, holat, kiritgan/tasdiqlagan, qo'llangan faktura; RLS: hamshira faqat `pending` kiritadi; o'chirish yo'q; ko'rib chiqilgandan keyin tahrir yo'q; ustma-ust tushish taqiqlanadi
- [M] `review_sick_note(p_id, p_decision, p_reason)` (tasdiqlovchi ≠ kirituvchi) + `sick_note_checks(p_id)` (shu kunlar davomati va kamera kirish vaqti)
- [M] Yopiq `medical` bucket (public=false, hajm va tur cheklovi), yo'l bo'yicha RLS, upsert yo'q; mijozda EXIF tozalash, signed URL (60–300 s) — sb/firebase-storage.js:16-31
- [M] Hamshira sahifasi (o'quvchi qidiruvi, sana oralig'i → maktab kunlari, majburiy fayl) va «Kasal bolalar» → Moliya navbati (oldindan ko'rish, kamera bilan zid kunlar) — admin.html:7842-7876
- [M] O'qituvchining «Bemor» tugmasi pulga ta'sir qilmaydi; o'tish sanasi `config/finance.sickApprovalFrom` — admin.html:2037, 2178, 2211-2219
- [M] Billing: `sickMap` tasdiqlangan ma'lumotnomalardan; ish kuni va bayram filtri; qo'llangan ID'lar fakturada — admin.html:7784-7807; invoice-guards.sql:110-117
- [L] Har kun bir marta; kech tasdiq → keyingi faktura yoki avans; ikki oyga to'g'ri kelgan ma'lumotnoma — admin.html:8378-8394, 8433
- [M] Bazada tekshiruv: `sickDaysApplied/sickAmount` = tasdiqlangan, hali qo'llanmagan kunlar × sickRate
- [M] Sog'liq maydoni alohida `student_health` jadvaliga (hamshira, direktor, ota-ona) — schema.sql:47; reception-access.sql:55-62
- [M] (ixtiyoriy) Ma'lumotnomani ko'rishni jurnalga yozuvchi server endpointi; saqlash muddati ishchisi
- [S] Ota-ona kabineti: «Bemor» belgisi, ma'lumotnoma holati, fakturada «Kasal kunlar: N × narx» qatori — index.html:2008-2062, 2410-2414

### 100 ball — O'IBDO' (24 soat) va Direktor (24 soat)
- [M] `monitoring` audit ustunlari (enteredAt/approvedAt/approvedBy, trigger bilan) + `monitoring_rounds` (T0 = sinf raundini yopish; qayta ochish faqat direktor, sabab bilan); yopiq raundda ballni o'zgartirish bloklanadi — schema.sql:79-88; admin.html:2413-2420
- [M] Chegirma fanlari ro'yxati konfiguratsiyaga + `app.monitoring_avg(sid, period)` (o'rtacha va qamrov n/N) — admin.html:7472-7483
- [M] `monitoring_bonus` + `bonus_propose` (zavuch, muddat ichida, o'rtacha ≥100, to'liq qamrov) / `bonus_decide` (direktor, muddat ichida); muddat o'tsa — direktorga «muddati o'tgan» (qaror savollarga bog'liq)
- [S] T0 = fan o'qituvchilari kiritish muddati tugagan payt (sozlama), O'IBDO''ning o'z tugmasi emas; to'liq qamrov sharti 90+ (20%) uchun ham
- [S] Davomat kiritilgan vaqtni saqlash (indikator «o'sha kuni 10:00 gacha» uchun) — attendance-sync.sql
- [M] UI: O'IBDO' — «Raundni yakunlash», nomzodlar va hisoblagich; Direktor navbati — admin.html:2361-2436
- [M] Billing: 100% faqat tasdiqlangan bonus bilan; aka-uka hisobida ham shu — admin.html:7548, 7682-7684, 7811-7822
- [M] To'langan fakturaga kech tasdiq → avans (credit_ledger sababi bilan); chegirma tasdig'ida ham ishlatiladi — invoice-guards.sql:64-73

### Chegirma va grant — Direktor + Moliya menejeri
- [M] `discount_requests` (tur, parametrlar, amal qilish oylari, sabab, hujjat, holat, so'ragan/direktor/moliya — kim, qachon, izoh); RLS: faqat `pending` kiritish; to'g'ridan-to'g'ri yangilash yo'q
- [M] `discount_decide(p_id, p_approve, p_note)`: direktor slotiga faqat `director`, moliya slotiga faqat `finance_mgr`, bitta odam ikkalasiga emas; ikkinchi tasdiqda `student_private`ga yozadi
- [S] `student_private` chegirma maydonlariga (specialCategory, contractAmount, siblingDiscount, teacherId) mijoz yozuvi bloklanadi (reception-guard.sql:130-132 namunasi)
- [M] UI: kartada tasdiqlangan chegirma faqat o'qish uchun; «Chegirma so'rash» oynasi; Olimpiada «🎓 Grant» so'rov yaratadi — admin.html:573-578, 2705-2721, 3674-3681, 4046-4051
- [M] Navbatlar: pul ta'siri (keyingi oy oldin/keyin) va hujjat bilan
- [M] Billing: amal qilish muddati; generatsiyada kutilayotgan so'rovlar ro'yxati — admin.html:7770-7840, 8248-8437
- [S] Hozirgi chegirmalar: bir martalik ro'yxat → «meros» sifatida tasdiqlash yoki qayta tasdiqlash (direktor qarori)
- [M] Aka-uka 10% YANGI paydo bo'lsa (yangi o'quvchi, telefon yoki familiya o'zgarishi) — so'rov sifatida ikki tasdiqqa tushadi — admin.html:7515-7597
- [S] (direktor rozi bo'lsa) narx jadvali va `sickRate` o'zgarishi Direktor tasdig'i bilan — staff-access.sql:91-96; audit-4.sql:272-278
- [M] PG16 rol matritsasi + brauzer e2e

### Tavsiya bonusi — to'lovdan keyin, Moliya menejeri
- [M] `referral_requests` (pending_payment → eligible → approved/rejected → applied/revoked; birinchi to'lov sanasi va fakturasi)
- [M] Birinchi haqiqiy to'lovni aniqlash; qaytarilsa yoki bekor qilinsa — revoke — audit-7.sql:90-101
- [S] `referral_decide` (faqat finance_mgr, faqat `eligible`dan)
- [M] `pmReferralMaps` faqat tasdiqlanganlarni oladi; `referral_ledger` BEFORE INSERT va `reprice_invoice` tekshiruvi — admin.html:7753-7768; discounts.sql:114-132; invoice-guards.sql:123-131
- [S] Moliya navbati «Tavsiya bonuslari»; kartada holat belgisi; summa (300 000) sozlamaga — admin.html:7729

### Bazada himoya (ekranni chetlab o'tib bo'lmasin)
- [S] `invoices.approvalRefs` (jsonb) — shim haqiqiy ustun talab qiladi (discounts.sql:12-14)
- [M] `invoices` BEFORE INSERT/UPDATE: grant, ≥50%, kontrakt, monitoring-100, tavsiya → shu o'quvchi va oy uchun tasdiqlangan yozuvga ishora; o'tish sanasidan oldingi oylar tegilmaydi — audit-9.sql:21-24; invoice-guards.sql:34-45
- [M] To'g'ridan-to'g'ri faktura yozuvini toraytirish (g'aznachi huquqi), summa/chegirma faqat RPC orqali
- [S] `discountInfo`, `referralUsedIds` change_log'ga — change-log.sql:128
- [M] REST orqali chetlab o'tish sinovlari (har rol), PG16 + PostgREST

### Hisoblar va o'qitish (pilotga tayyorgarlik)
- [S] Xodimlar telefonlarini kanonik qilish va dublikatlarni tozalash (avto-bog'lanish uchun) — auth/index.cjs:171-197
- [M] HR'ga cheklangan rollar ro'yxati bilan tasdiq yoki ommaviy tasdiq ekrani — staff-user-link.sql:46-60; admin.html:4264-4338
- [M] Sinf/fan biriktirish dars jadvalidan + yillik yangilash
- [M] Rollar bo'yicha 1 sahifalik qo'llanmalar (o'zbek + rus), skrinshotlar bilan

## 2-bosqich — Pilot: 2–3 sinf (11-yanvar – 5-fevral, ≈35 kun)

### Maosh: Moliya tayyorlaydi → HR tasdiqlaydi (D2)
- [M] `payroll_runs` / `payroll_lines` (oy, holat, tayyorlagan/tasdiqlagan, har xodim qatori va tarkibi); RLS `can_see_salary`, yozuv faqat RPC
- [M] `payroll_submit` (finance_mgr yoki direktor), `payroll_decide` (hr, tayyorlagan ≠ tasdiqlagan, qaytarish izoh bilan), `payroll_reopen` (direktor)
- [L] Oy hisobini yagona funksiyaga ajratish (hisobot, vedomost va to'lov bir xil; Kamera ID'siz xodimlar ham) — admin.html:5126-5255, 6098-6321
- [M] Moliya: «Oylik vedomost» ekrani (finance_mgr uchun tab); HR: ko'rib chiqish navbati, qatorma-qator farq; PDF «Tayyorladi / Tasdiqladi» — admin.html:5076-5122
- [M] To'lov darvozasi: `salary_payments` BEFORE INSERT tasdiqlangan qatorni talab qiladi; ushlanma faqat o'qish uchun — audit-3.sql:75-81
- [M] Tasdiqlangan oy uchun kiritmalar qulfi (ta'til, tanaffus, o'rinbosarlik, bayram, avans)
- [S] «Oylik maoshni yozish» faqat tasdiqlangan jamidan — admin.html:6587-6641
- [M] Testlar; dekabr–yanvar maoshi eski usul bilan parallel solishtiriladi

### Pilotni qo'llab-quvvatlash
- [M] Kunlik solishtiruv: Click/Uzum kabinet eksporti va bank ko'chirmasi ↔ `payments`; farqlar ro'yxati
- [S] Biriktirilmagan va qo'lda qaytarish kutayotgan to'lovlar uchun ogohlantirish
- [S] Har sinf uchun kod varaqalari (ID + kod + QR + o'zbek/rus yo'riqnoma) — admin.html:3013-3018
- [M] Bog'lanishlar paneli: o'quvchiga ulangan hisoblar, bekor qilish, kodni yangilash — security-2b.sql:70-71
- [M] D7 to'liq: `app.mask_phone()`, qabulxona uchun niqoblangan ko'rinish, `reveal_parent_phone(sid, which, reason)` (kunlik limit), `pii_access_log`, direktor audit ekrani — reception-access.sql:35-62
- [S] `staff_checkins`: HR/moliya/kassa faqat xodim kamera ID'larini ko'radi, o'quvchi skanlari faqat `class_arrivals` orqali — staff-attendance.sql:43; camera-days.sql:33-46
- [S] Pilot sinflari: kamida bitta 5–9-sinf, bitta kichik sinf, bitta rus sinfi; pilot o'qituvchilari qog'ozni ham yuritadi — pilot qisqa
- [S] AI xulosalari qaytadan yoqilsa — faqat psevdonim bilan (huquqshunos javobidan keyin) — ai-assistant/index.cjs:114-189
- [M] Pilot sinflar ma'lumotida o'qituvchi/kurator/ota-ona policy'lari uchun EXPLAIN va indekslar

## 3-bosqich — Butun maktab (8-fevral – 2-aprel, ≈35 kun)

### SMS sozlamalari (D3)
- [S] `notify-settings` jadvali: tur bo'yicha yoqish, kunlar, vaqt, oy kuni, matn (SMS va Telegram alohida), umumiy tinch soat; RLS — direktor (yoki tanlangan administrator); `config`ga emas (u anon'ga ochiq — audit-4.sql:282-292)
- [M] `sms-worker.cjs auto`: har ishga tushishda sozlamani o'qiydi, o'qiy olmasa — yubormaydi; bitta cron (har 15 daqiqa, flock) — payments/sms-worker.cjs; payments/README.md:172-192
- [S] Qo'lda «Eslatma» ham shu matn va tinch soatni oladi — auth/sms-remind.cjs:60-96
- [M] Sozlamalar → «📱 Xabarnomalar» kartasi: oldindan ko'rish, SMS bo'laklari, **faol (Eskiz tasdiqlagan) va qoralama matn** — payments/eskiz-template.cjs; payments/eskiz-shablon.cjs:43-50
- [M] `/authapi/sms-tpl-check`: Eskiz shablonlariga moslik (hech narsa yubormaydi)
- [S] SMS jurnali (direktor/moliya): tur, holat, xato, niqoblangan raqam
- [S] Eskiz'da brend jo'natuvchi nomi (hozir test nomi 4546) — payments/sms.cjs:75

### Telegram (D4)
- [M] `telegram_links` + `telegram_link_tokens` (HMAC-xesh, 10 daqiqa, bir martalik), RLS yoqilgan, mijozga yozuv yo'q
- [M] `app.tg_recipients(student_key)` — kimga yuborishni bitta SQL funksiya hal qiladi (ota/ona raqami yoki tasdiqlangan bog'lanish)
- [S] `server/telegram.cjs`: sendMessage/setWebhook, 429 retry_after, 403 (bloklagan) aniqlash
- [S] Auth serverda `tg-webhook` (secret_token tekshiruvi, update_id bir marta), `tg-link-start/status`, `tg-unlink` — auth/index.cjs:329-396
- [M] Bot: `/start <token>` → rozilik matni → «📱 Raqamni ulashish» (request_contact) → `contact.user_id === from.id`, forward emas, raqam mos → ulandi; testlar
- [S] Kabinet kartasi «Telegramni ulash» / holat / uzish — index.html:1649-1690
- [S] Raqam o'zgarsa — `reverify`; yiliga qayta tasdiq — auth/index.cjs:302-321
- [L] Kanal marshruti: Telegram birinchi, yetkazilmasa — SMS (+998); kanallar bo'yicha takror himoyasi; sekundiga ~20 xabar
- [M] Qo'lda «Eslatma» kanalni ko'rsatadi; `/stop`, `/sozlamalar`; `my_chat_member` (bloklash); «To'lov qabul qilindi» xabari; direktor ko'rinishi

### To'lqinlar uchun
- [L] O'qituvchi/kurator ekranlarining rus tilidagi varianti — rus sinflari to'lqinidan oldin
- [S] `student_private.parentPhone/parentPhone2` o'zgarishi change_log'ga (Telegram tekshiruvining asosi) — change-log.sql:126
- [S] D3 birinchi yoqishda `newLookbackDays` o'tgan fakturalar uchun xabar ketmasligi — payments/sms-worker.cjs:169-180
- [M] supabase-js'ni o'zimizda va versiyasini qotirish; service worker versiyalangan — sb/_core.js:4; sw.js:22-31
- [S] Qurilmalar ro'yxati bo'yicha sinov; pinch-zoom
- [S] SMTP (xorijiy raqamli ota-onalar email bilan kiradi — Telegram uchun ham shart)
- [M] SMS ishlamasa: direktor/HR beradigan bir martalik tiklash kodi
- [S] Server ishlamasa — qog'oz davomat va kassa kvitansiyasi tartibi; ish vaqtidan keyin navbatchi

## 4-bosqich — Barqaror ish (apreldan, ≈25 kun)
- [M] CI: `npm test` (payments, auth, server) + PG16 zanjir + verify-db — deploydan oldin
- [S] Bog'liqliklarni qotirish (lockfile, aniq versiyalar); `main` va relizlar tartibi (tag bo'yicha orqaga qaytish)
- [S] `statement_timeout` rollar bo'yicha; `pg_stat_statements` haftalik ko'rigi; server shim `get()` sahifalash (PGRST max-rows)
- [S] `staff_checkins` saqlash muddati, mijoz `raw`ni olmaydi
- [L] Katta jadvallar (fakturalar, to'lovlar, skanlar) uchun filtrlangan/yig'ma RPC'lar
- [M] Yuk sinovi (~60 xodim + ~400 ota-ona, oy boshi)
- [L] Issiq zaxira server (O'zbekistonda) yoki replika + DNS almashtirish tartibi
- [M] TOTP ikki bosqichli kirish (direktor, moliya, HR)
- [S] Ma'lumot oqimlari ro'yxati (huquqshunos uchun), [M] huquqshunos ko'rigi, [M] rozilik matni va qabul, [S] saqlash muddatlari
- [L] admin.html'ni rol/modullarga bo'lish
- [M] Arxitektura va ekspluatatsiya qo'llanmasi (SESSIYA-ISHLARI.md dan)

## Indikatorlar qayerdan hisoblanadi
| Indikator | Manba / formula | Bugun o'lchanadimi |
|---|---|---|
| To'lov yig'ilishi | `invoices` (month=M, bekor/qaytarilganlarsiz): Σmin(paidAmount, amount) / Σamount; 3 nuqtada saqlanadi | ha |
| Qarz muddati | o'tgan oylar bo'yicha `amount − paidAmount > 0` oylari soni har o'quvchiga: 1 / 2 / 3+ | ha |
| Davomat kiritilishi | `attendance.days` kalitlari / dars bo'lgan sinf-kunlar (dam olish va `school_holidays`siz); SQL'da (1000 qator cheklovi) | ha |
| Ota-onalar ulanishi | faol `child_claims` (parent roli, faol) bilan bog'langan o'qiyotgan o'quvchilar / o'qiyotganlar, sinf bo'yicha | ha |
| Xodimlar hisobi va faolligi | `users.staffRefId` bilan bog'langanlar / faol `teachers`+`staff`; faollik — `auth.users.last_sign_in_at` (server tomonda) | qisman |
| Muddati o'tgan tasdiqlar | tasdiq jadvallaridagi effektiv holat = muddati o'tgan / 24 soatdan oshgan kutish | yangi vosita |
| Zaxira | `/var/log/iqror-backup.log` + eng yangi `db_*.sql.gz` yoshi va hajmi; oylik tiklash mashqi | yangi vosita |
| Biriktirilmagan to'lov / yetim faktura | `payments` (status unmatched yoki studentId bo'sh) / `invoices` (o'quvchisi yo'q) | ha |
| Solishtiruv farqi | provayder eksporti va bank ko'chirmasi ↔ `payments` (usul va kun bo'yicha) | kichik o'zgarish |
| Kamera qamrovi | `camera_days(from, to)` (≤62 kun) + kutilgan xodimlar; <30% — uzilish kuni | ha |
| SMS | `sms_log` (tur × holat), tinch soat (Toshkent vaqti); OTP — `otp_codes` soni | qisman |
| Xizmatlar | tashqi uptime tekshiruvi har 5 daqiqada | yangi vosita |
| Rollar o'zgarishi | `change_log` (tbl='users', rol/status/biriktirish) | ha |
| Muvaffaqiyatsiz kirishlar | `auth_login_attempts` (ok=false), `otp_codes.attempts`, `child_claim_attempts` (server tomonda) | ha (server) |
