# «Kassa» bo‘limini ishga tushirish to‘plami (F1.19)

**Holat:** tayyor, o‘qitish va ishga tushirishda ishlatiladi. Bo‘lim hali jonli tizimga chiqmagan (faqat sinov stendida).
Ism, lavozim, rekvizit va summalar bu yerda yozilmaydi (repozitoriy ommaviy) — `[___]` o‘rniga qog‘ozda to‘ldiriladi.

**To‘plam tarkibi**
| Hujjat | Kim uchun | Fayl |
|---|---|---|
| Ishga tushirish tartibi (shu fayl): taqvim, shartlar, texnik tartib, 31-dekabr, birinchi kunlar, orqaga qaytish | direktor, moliya menejeri, buxgalter, administrator | `docs/moliya/ishga-tushirish.md` |
| Rol bo‘yicha bir varaqli yo‘riqnomalar | kassir, moliya menejeri, buxgalter, direktor, HR, hisobdorlar | `docs/moliya/yoriqnomalar.md` |
| Shakllar ro‘yxati va qog‘oz shablonlari (avans hisoboti, «Қ» blankasi, sanash va daftarlarni yopish dalolatnomalari, qabul sinovi varag‘i) | kassir, buxgalter, komissiya | `docs/moliya/shakllar.md` |
| Buyruq namunalari (imzo ro‘yxatlari, komissiya, kassir, shakllar, hujjatlar aylanishi) | direktor, buxgalter | `docs/moliya/buyruq-namunalari.md` |
| Oraliq qoidalar (ishga tushguncha) | hamma | `docs/moliya/oraliq-qoidalar.md` |
| Ish reja (asoslar va qarorlar) | — | `docs/moliya/buxgalteriya-ish-reja.md` |

---

## 1. Taqvim
| Sana | Nima | Kim |
|---|---|---|
| 16-noyabrdan | Oraliq qoidalar amalda | hamma |
| 21-noyabr | Buxgalter hisob qismini ko‘rib chiqadi (hisobvaraqlar, statiyalar, operatsiyalar) — vaqtincha tasdiq | buxgalter |
| 12-dekabr | Buyruqlar imzolangan; fiskal kassa bo‘yicha yozma tasdiq; hisob siyosati qarorlari | direktor, buxgalter |
| 14–19-dekabr | Sinov stendida 1-qabul sinovi va o‘qitish | hamma rollar |
| 19-dekabr | Tizim vedomosti buxgalter hisobotidagi ish haqi fondiga mosligi yozma tasdiqlanadi | buxgalter |
| ≈ 21-dekabr | **Yashirin o‘rnatish**: bo‘lim jonli tizimga chiqadi, lekin «ishga tushadigan kun» bo‘sh — hamma oyna avvalgidek ishlaydi | administrator |
| 21–26-dekabr | 2-qabul sinovi (stendda), maosh kuni mashqi; **26-dekabr — qabul sinovi varaqlari imzolanadi** | hamma rollar |
| 31-dekabr (yoki oxirgi ish kuni) kechqurun | Komissiya sanashi, qog‘oz daftarlarni yopish, sozlamalar, boshlang‘ich qoldiq, davr surati | komissiya, direktor, buxgalter |
| Yanvarning birinchi kassa kuni (reja: 4-yanvar) | **Rasmiy boshlanish** | kassir |
| Birinchi 5 ish kuni | Parallel yuritish: kunlik nazorat varag‘i | moliya menejeri |
| Yanvar oxiri | Oy oxiri sanashi; yanvar avans hisobotlari kiritiladi; davrni yopish | komissiya, buxgalter, direktor |

Biror shart bajarilmasa — boshlanish sanasi suriladi (keyingi oyning birinchi ish kuni; boshlang‘ich qoldiq — o‘sha oy oxiridagi sanash).

## 2. Boshlashdan oldingi shartlar (belgilab chiqiladi)
- [ ] **Fiskal kassa:** har naqd to‘lovga onlayn kassa cheki uriladi (yozma tasdiq). Naqd o‘quv to‘lovi tizimga faqat chek raqami bilan kiritiladi.
- [ ] **Buyruqlar** imzolangan: imzo ro‘yxatlari (1- va 2-ro‘yxat), inventarizatsiya komissiyasi, kassir va o‘rinbosari, to‘liq moddiy javobgarlik shartnomalari, shakllar, hujjatlar aylanishi grafigi, ichki kassa nizomi.
- [ ] **Hisob siyosati:** hisobvaraqlar, statiyalar va operatsiyalar ro‘yxatini buxgalter tasdiqlagan.
- [ ] **Maosh:** vedomost tasdig‘i yoqilgan (dekabrdan kechikmay), noyabr vedomosti tizimda sinov sifatida tasdiqlangan, dekabr vedomosti maosh kunidan oldin tasdiqlanadi; HR menejer hisobi faol.
- [ ] **Hisoblar (login):** kassir(lar), moliya menejeri, buxgalter, HR — har birining o‘z hisobi bor; parol boshqaga berilmaydi.
  Buxgalterga «Foydalanuvchilar»da **«Buxgalter»** roli beriladi (bu rol tanlovda kassa bo‘limi o‘rnatilgandan keyin paydo bo‘ladi;
  bo‘limlari — «Tasdiqlash» va «Kassa» (so‘rovni tasdiqlash yoki rad etish, kunni tekshirish, hujjatni bekor qilish, avans hisoboti),
  «To‘lovlar» va «Buxgalteriya» (faqat ko‘rish); qo‘shimcha lavozim berilmaydi — F1.21).
- [ ] **Qabul sinovi:** kassir, moliya menejeri, buxgalter va direktor stendda o‘z ssenariylarini bajarib, varaqni imzolagan (`shakllar.md`, Sh-5).
- [ ] **Bank bilan kassa limiti** kelishilgan (bo‘lmasa — limit 0: ortiqcha pul har kuni bankka topshiriladi).
- [ ] **Printer:** A4 (KO-1 + patta, KO-2, KO-4, dalolatnomalar); sinov varag‘i chop etilgan.
- [ ] **Hisobdorlar qoldig‘i:** zavxoz, oshpaz va boshqa hisobdorlardagi pul bo‘yicha 31-dekabr holatiga imzolangan ma’lumotnomalar.
- [ ] **Qog‘oz zaxira:** «Қ» blankalari va jurnali chop etilgan, raqamlangan (`shakllar.md`, Sh-2).

## 3. Texnik tartib (administrator)
Hamma buyruqlar serverda oddiy foydalanuvchidan; kalit va parollar hech qayerga ko‘chirilmaydi.

**3.1 Sinov stendi (qabul sinovi va o‘qitish shu yerda).** O‘rnatish va yangilash — `sinov/README.md`. Kassa bo‘limi bilan:
```bash
bash ~/iqror-repo/sinov/update.sh --dev
```
Yakuniy tekshiruvda «Kassa tekshiruvi: muammo topilmadi (modul relizi N)» qatori chiqishi kerak.

**3.2 Jonli zanjirga o‘tkazish (dasturchi, yashirin o‘rnatishdan oldin — bir marta).** Qabul sinovi va buxgalter ko‘rigidan keyin:
1. `migration/run-all.sql` dagi moliya qatorlaridan «`--dev `» belgisi olib tashlanadi (fin-core … fin-version; tartib o‘zgarmaydi).
2. `payments/_schema-columns.json` kanonik zanjirdan qayta tuziladi (`information_schema.columns`).
3. To‘liq sinov: SQL to‘plamlari (`test-kassa*.sql`, `test-fin-*.sql`, `test-kassa-checks.sql`, `test-audit-fixes.sql`,
   `test-public-close.sql`), `test-kassa-race.sh`, `node --test assets/js/*.test.mjs`, `payments` va `auth` `npm test`, brauzer ssenariylari.
4. Hujjatlardagi «faqat lokal sinov zanjirida» belgilari yangilanadi; commit.
Qisman o‘tkazish (bayroq bilan, ayrim deploylarda) **qilinmaydi**: zanjir har deployda ichki funksiyalar huquqini qayta
beradi va kassa fayllari ularni qaytarib oladi — kassa fayllarisiz deploy bu himoyani ochiq qoldiradi.

**Mashq (2026-11-12, lokal, modul relizi 9):** jonli versiya (3108d19) prod zanjiri bilan qurilgan baza ustiga «`--dev`»siz
zanjir (jonli `lock_timeout` bilan) — xatosiz; qayta qo‘llash — xatosiz; `kassa-checks.sql` — «muammo topilmadi»; toza
o‘rnatishda barcha SQL to‘plamlari yashil; `payments` (192) va `auth` sinovlari yashil. 2-qadamda `_schema-columns.json` ga
qo‘shiladigan ustunlar: `payments.cashDocId`, `payments.fiscalNo`, `refunds.method`, `refunds.cashDocId`.

**3.3 Yashirin o‘rnatish (≈ 21-dekabr, ish vaqtidan tashqari).**
```bash
cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash migration/deploy/full-deploy.sh
```
Deploy chiqishida tekshiriladi: «7/7 baza tekshiruvi — BIR XIL»; «✓ Kassa tekshiruvi: muammo topilmadi (modul relizi N)».
Keyin, hali hech narsa kiritmasdan:
- Direktor hisobida «Moliya» → «Kassa» ochiladi: «Kassa hali ishga tushirilmagan» kartasi va «ishga tushirilgan deb belgilanmagan» eslatmasi ko‘rinadi.
- «💵 To‘lov», «Maosh berish», «Xarajat», «Qaytarish» oynalari avvalgidek ishlaydi (fiskal chek maydoni yo‘q) — bitta haqiqiy to‘lovni kutib kuzatish kifoya, sinov to‘lovi kiritilmaydi.
- Sinash kerak bo‘lsa — faqat **sinov kassasida** («Kassa» sahifasidagi kassa tanlovi → «Sinov kassasi»): boshlang‘ich qoldiq,
  «+ Kirim» → «Boshqa kirim», «+ Chiqim so‘rovi» → «Xarajat» → tasdiq → «Pulni berish», chop etish («СИНОВ» belgisi bilan), kunni yopish.
  Sinov kassasi hujjatlari hisobotlarga, «Buxgalteriya»ga va Telegram hisobotiga kirmaydi. O‘quv to‘lovi bilan sinov o‘tkazilmaydi
  (ota-onaga xabar ketadi).
- Direktorga kunlik Telegram hisoboti matni (hech narsa yubormaydi): auth xizmati papkasida `node tg-daily.cjs --dry` (`auth/README.md`,
  «Telegram bot») — kassa bloki hali yo‘q bo‘lishi kerak; ishga tushgach — bor.

**3.4 Istalgan payt tekshirish (faqat o‘qiydi):**
```bash
sudo docker exec -i supabase-db psql -U postgres -d postgres -X -P pager=off < ~/iqror-repo/migration/kassa-checks.sql
```
Chiqishda ism, telefon va summalar yo‘q. «!!» bilan boshlangan qator — muammo; izohi `migration/deploy/README.md` da.

## 4. 31-dekabr (yoki dekabrning oxirgi ish kuni) kechqurun
Tartib muhim — yuqoridan pastga. Hamma amal Direktor hisobida, komissiya ishtirokida.
1. **Kun yakuni eski tartibda:** oxirgi qog‘oz kirim va chiqim orderlari yoziladi, kunlik varaq yopiladi. **Sanashdan oldin
   hamma naqd yozuv tizimda bo‘lsin:** to‘lov qabul qiladigan barcha qurilmalar (kompyuter, telefon) internetga ulanadi va
   navbati (⏳) bo‘shaguncha kutiladi; kassadan berilgan xarajat, maosh va avanslar ham kiritiladi. Sanashdan keyin topilgan
   kechikkan yozuv — pastdagi «Kechikib topilgan yozuv» bandi bo‘yicha.
2. **Komissiya kassani sanaydi** (nominallar bo‘yicha) va dalolatnoma tuzadi (`shakllar.md`, Sh-3): sanalgan summa, hisobdagi
   qoldiq, farq va uning sababi. Farq majburan tenglashtirilmaydi — Direktor qaror qiladi (kamomad — javobgar shaxsga yoki zararga; ortiqcha — daromadga).
3. **Qog‘oz order daftarlari yopiladi** (Sh-4): oxirgi П/О va Р/О raqamlari, ishlatilmagan blankalar bekor qilinadi; buxgalter imzolaydi.
4. **«Kassa» → «⚙ Sozlamalar»:** tashkilot nomi (hujjatlardagidek), STIR, joy, chop etish tili; T1 (shundan katta chiqimga Direktor
   tasdig‘i), L1 (asos hujjatisiz naqd xarid chegarasi), kassa limiti; **yuridik shaxsga kassadan naqd to‘lov chegarasi** (yetkazib
   beruvchi / tashkilotga shu summagacha Direktor tasdig‘isiz; bo‘sh yoki 0 — har doim Direktor; buxgalter hisob siyosatida
   tasdiqlaydi); **imzo egalari** (1-ro‘yxat — rahbar; 2-ro‘yxat — bosh buxgalter / moliya menejeri; to‘liq F.I.Sh., lavozimi,
   tizimdagi hisobi). Kontragentlar turi to‘g‘ri bo‘lsin: korxona (MChJ, AJ va b.) — «Yetkazib beruvchi» yoki «Tashkilot», yakka
   tadbirkor va fuqaro — «Jismoniy shaxs».
5. **«Boshlang‘ich qoldiqni kiritish»:** summa — komissiya sanagan pul; «Birinchi kassa kuni» — yanvarning birinchi kassa kuni;
   komissiya a’zolari. Tizim «Boshlang‘ich qoldiq» dalolatnomasini yozadi (D-1) — chop etilib, komissiya imzolaydi.
   Birinchi kassa kuni ochilguncha qoldiqni qayta kiritish mumkin (avvalgi dalolatnoma bekor bo‘ladi, raqami saqlanadi).
   **Sanashdan keyin va birinchi kassa kunidan oldin naqd pul harakati bo‘lsa** (masalan, ta’til kunlari qabul qilingan to‘lov) —
   birinchi kassa kuni ertalab pul qayta sanaladi va boshlang‘ich qoldiq qayta kiritiladi: u birinchi hujjatdan oldingi haqiqiy pulga teng bo‘lishi shart.
6. **«⚙ Sozlamalar» → «Kassa ishga tushadigan kun»** = birinchi kassa kuni. Shu kundan boshlab har naqd o‘quv to‘lovi kirim orderi
   va fiskal chek raqami bilan yoziladi. Sana 31-dekabr kechqurun (oldindan) kiritiladi. Bugungi yoki o‘tgan kun qo‘yilsa, tizim
   tekshiradi: shu kundan beri kassa orderisiz naqd yozuv (o‘quv to‘lovi, xarajat, maosh, avans, qaytarish) bo‘lsa — sozlama
   saqlanmaydi va sanani o‘sha yozuvlardan keyingi kunga qo‘yish so‘raladi (ular boshlang‘ich qoldiq sanashiga kiradi).
7. **To‘lanmagan qaytarishlar:** «↩ Qaytarish» orqali tasdiqlangan, lekin hali berilmagan pullar ro‘yxati (yangi yilda kassadan «Qaytarish» chiqim orderi bilan beriladi).
8. **Davr surati:** «Kassa» → «Davr» → «Yangi surat»: «Qaysi kun oxiri holati» = 31-dekabr → «Surat olish» («Shu sanagacha davrni
   yopish» belgisi bugungi sana uchun o‘zi o‘chadi — bugungi kun yopilmaydi). Suratda: o‘quvchilar qarzi va avanslari, biriktirilmagan tushumlar, kassa
   qoldig‘i, to‘lanmagan ish haqi, berilmagan qaytarishlar. «⬇ JSON» bilan yuklab (Direktor yuklagani — ismli to‘liq nusxa; moliya menejeri va buxgalterga ismsiz nusxa
   beriladi), arxivga qo‘yiladi.
9. **Davrni yopish** — keyingi ish kuni: «Davr» → «Shu sanagacha yopiq» = 31-dekabr → «Qulfni saqlash». Shundan keyin 31-dekabrgacha
   sanali to‘lov, xarajat, maosh to‘lovi va avans kiritilmaydi va o‘zgartirilmaydi (onlayn to‘lovlar bundan mustasno). Keyingi
   oylarda: davr faqat shu sanagacha bo‘lgan barcha kassa kunlari sanab yopilgan bo‘lsa yopiladi; yopilgan davrdagi kassa kuni
   qayta ochilmaydi (avval Direktor davrni sababi bilan qayta ochadi).
10. Hujjat raqamlari (K-, Ch-, D-) yangi yilda 1 dan boshlanadi — bu avtomatik.

**Kechikib topilgan yozuv (ishga tushish kunidan oldingi naqd pul, tizimga keyin kiritiladi).** Bu pul boshlang‘ich qoldiq
sanashiga kirgan — uni **bugungi sana bilan qayta kiritish uni ikki marta hisoblaydi** (kassada ortiqcha kirim orderi va
fiskal chek paydo bo‘ladi). Tartib:
- **Direktor** yozuvni **haqiqiy sanasi** bilan kiritadi: «💵 To‘lov» → «Naqd» → «Sana» = pul olingan kun (ishga tushish kunidan
  oldin; oyna buni ko‘rsatadi) — kirim orderisiz va fiskal cheksiz yoziladi, kassa qoldig‘i o‘zgarmaydi. To‘lov sanasi 31 kundan
  eski bo‘lsa — «💵 To‘lov» uni qabul qilmaydi (bugungi sanaga ham surmaydi), buxgalter bilan hal qilinadi. Kassadan berilgan
  xarajat, maosh yoki avans — «Buxgalteriya»dagi o‘z oynasida haqiqiy sanasi bilan, usul «Naqd — kassa ishga tushishidan oldin
  berilgan» (avansda — shu belgi); kassa chiqim orderi yozilmaydi.
- **Boshqa rollar** (kassir, g‘aznachi, moliya menejeri) bunday yozuvni o‘zi kirita olmaydi — tizim rad etadi. Faqat kassir yoki
  g‘aznachi qurilmasi navbatida qolib ketgan yozuv (ishga tushishdan oldin yozilgan, 48 soatdan eski emas) internet qaytganda o‘zi
  o‘tadi — u ham kirim orderisiz; undan eskisini Direktor kiritadi.
- Bunday yozuvlar nazorat ro‘yxatida «Kassa ishga tushishidan oldingi naqd yozuvlar (keyin kiritilgan)» qatorida ko‘rinadi
  (ma’lumot uchun): buxgalter ularni sanash dalolatnomasi bilan solishtiradi. Davr qulfi (8–9-qadamlar) ularga ham amal qiladi.

## 5. Birinchi kassa kuni
- [ ] Ertalab «Kassa»: «Oxirgi qoldiq» = boshlang‘ich qoldiq = kassadagi haqiqiy pul (farq bo‘lsa — birinchi hujjatdan oldin qayta sanab, qayta kiriting); qizil ogohlantirish yo‘q.
- [ ] Birinchi naqd o‘quv to‘lovi: fiskal chek urildi → «💵 To‘lov» (chek raqami bilan) → «🖨 Kirim orderi va patta»; patta to‘lovchiga, order kassada.
- [ ] Birinchi chiqim: «+ Chiqim so‘rovi» → moliya menejeri «Tasdiqlash» → kassir «Pulni berish» → «🖨 Chiqim orderi», oluvchi imzosi.
- [ ] Kechqurun: «Kunni yopish» — pul sanaladi, summa kiritiladi; «🖨 KO-4» ikki nusxa (kassa kitobi varag‘i va kassir hisoboti) va «🖨 Kunlik hisobot».
- [ ] Moliya menejeri yoki buxgalter: qog‘ozlarni olib, «Tekshirish» → «Tekshirdim».
- [ ] Direktor: Telegram hisobotida kassa bloki (kirim, chiqim, qoldiq, sanash) va nazorat qatori.

## 6. Parallel yuritish (birinchi 5 ish kuni)
Excel yuritilmaydi. Moliya menejeri har kuni (≈ 10 daqiqa) nazorat varag‘ini to‘ldiradi (`shakllar.md`, Sh-6). Chiqish sharti —
**ketma-ket 3 ish kuni**: sanalgan pul = tizimdagi qoldiq; har order qog‘oz manbasi bilan; Click / Uzum kabinetidagi summalar =
kunlik hisobotdagi «kanallar» bloki; bankka topshirish va bankdan olish = bank hujjatlari; raqamlar uzluksiz, bekor qilishlar
izohlangan; Telegram = kunlik hisobot; nazorat ro‘yxatida «Moslik» qatori — «hammasi mos»; tushuntirilmagan farq yo‘q.

## 7. Oy oxiri
1. Oyning oxirgi ish kuni — komissiya sanashi: kunni Direktor yoki moliya menejeri komissiya ishtirokida yopadi (yopish oynasida
   komissiya a’zolari kiritiladi — kamida 2 kishi), sanash dalolatnomasi chop etilib imzolanadi.
2. Barcha kunlar «Tekshirilgan»; nazorat ro‘yxatida qizil qator yo‘q; `kassa-checks.sql` — «muammo topilmadi».
3. Yanvar avans hisobotlari (qog‘oz, Sh-1) buxgalterga topshirilgan va «Kassa» → «Avans hisoboti» bilan kiritilgan.
4. «KO-3» jurnali (oy) chop etilib bosh buxgalter imzolaydi; Excel nusxasi buxgalter dasturiga olinadi (buxgalter va Moliya
   menejerida — ismsiz, FD-28; to‘liq nusxa kerak bo‘lsa — Direktor yuklaydi); jurnal oynasida qoldiqlar mos (ogohlantirish yo‘q).
   «Statiyalar» — oylik statiya matritsasi chop etilib imzolanadi; «Oylik to‘plam (Excel)» (KO-3, statiyalar, kassa kunlari,
   hisobdorlar) buxgalterga topshiriladi.
5. «Davr» → surat (oy oxiri) → keyingi ish kuni qulf (oyning oxirgi kassa kuni yopilmagan bo‘lsa tizim davrni yopmaydi).

## 8. Favqulodda holatlar
| Holat | Nima qilinadi |
|---|---|
| Internet uzildi | Fiskal chek uriladi (kassa apparati oflayn rejimda). «💵 To‘lov» qurilmada navbatga yoziladi; to‘lovchiga tizimdan varaqa berilmaydi — dalil fiskal chek. Internet qaytgach yozuv o‘zi o‘tadi va kirim orderi chiqadi. Navbatda yozuv turganida kun yopilsa — «Hali o‘tkazilmagan yozuvlar» soni va summasi o‘zi to‘ldiriladi (bu pul kassada bor, hisobda hali yo‘q); yozuv keyin o‘tganda navbatdagi ochiq kunga «kech» belgisi bilan tushadi. 48 soatdan eski yozuvni faqat Direktor kiritadi. |
| Tizim (server) ishlamayapti | Ichki «Қ» blankasi to‘ldiriladi (to‘lovchiga berilmaydi), jurnalga yoziladi; fiskal chek uriladi. Tizim tiklangach yozuvlar shu kungi sana bilan kiritiladi (izohda — «Қ» raqami va pul olingan sana), jurnalda order raqami belgilanadi. |
| Fiskal kassa ishlamayapti | Faqat soliq organida ro‘yxatdan o‘tgan maxsus kvitansiya daftari; naqd to‘lovni tizimga kiritishda Direktor «Fiskal cheksiz (istisno)» belgisini qo‘yadi — jurnalda qoladi. |
| Order xato yozildi | **Shu kuni:** hujjat qatorida «Bekor» (sababi bilan) — raqam saqlanadi, to‘g‘risi yangi raqam bilan yoziladi. **Kun yopilgan, tekshirilmagan:** Direktor «Qayta ochish» (faqat oxirgi kun). **Tekshirilgan kun:** o‘zgarmaydi — buxgalter tuzatish hujjati bilan. |
| Sanashda farq | Tizim shu kun sanasi bilan kamomad (chiqim) yoki ortiqcha (kirim) hujjatini o‘zi yozadi; dalolatnoma chop etiladi; kamomad bo‘yicha Direktor qarori («Qaror»): xodim hisobiga yoki zararga. Xodim hisobiga bo‘lsa — u pulni kassaga «+ Kirim» → «Kamomadni qoplash (xodim)» bilan qaytaradi (qarordagi summadan oshmaydi); qolgani nazorat ro‘yxatida («Xodimlar zimmasidagi kamomad») ko‘rinadi. |
| Xodim avans yoki maoshni kassaga qaytardi | «+ Kirim» → «Xodim qaytargan pul»: xodim, **qaysi oy**, statiya (avans — OP-08, maosh — OP-09). Avans qaytimi shu oy avansidan ayiriladi — oy vedomosti tasdiqlangan bo‘lsa qabul qilinmaydi (OP-09 bilan yoki Direktor oyni qayta ochadi); maosh qaytimi shu oy berilgan maoshni kamaytiradi (qayta berilishi mumkin). |
| O‘quvchi ketdi, oldindan to‘lagan puli (avansi) qaytariladi | Direktor: o‘quvchining «📋» → «↩ Avansni naqd qaytarish» (summa — joriy avansgacha, ariza sanasi, oluvchi F.I.Sh.); kassir «So‘rovlar» → «Pulni berish». Avans pul berilganda kamayadi; xarajat sifatida yozilmaydi. Naqdsiz qaytarish — hozircha yo‘q. |
| Kecha yopilmagan | Bugun hujjat yozilmaydi — avval kechagi kun sanab yopiladi. |
| Sahifada «sahifani yangilang» ogohlantirishi | Tizim yangilangan: Ctrl+Shift+R (telefonda — sahifani yopib qayta ochish). |

## 9. Orqaga qaytish
**Ish jarayoni (tizimdan vaqtincha voz kechish).** Qaror — Direktor. (1) **To‘xtatishdan oldin:** joriy kassa kuni sanab
yopiladi; tasdiq kutayotgan va tasdiqlangan (puli berilmagan) kassa so‘rovlari bajariladi yoki bekor qilinadi — aks holda tizim
kassani to‘xtatmaydi va to‘sqinlik qilayotgan kun yoki so‘rovlar ro‘yxatini ko‘rsatadi. (2) Kassa «Қ» blankalari va jurnali bilan
ishlaydi; blankalar **o‘z raqamlari** bilan (alohida daftar) — tizim raqamlari qayta ishga tushganda tizimdagi oxirgi raqamdan
uzluksiz davom etadi, qog‘oz raqamlari bilan aralashmaydi. (3) Excel kunlik varag‘i tizimdagi oxirgi kun oxiri qoldig‘idan qayta
boshlanadi. (4) Tizimda yozilgan hujjatlar haqiqiy bo‘lib qoladi — o‘chirilmaydi. (5) Oyni buxgalter birlashtiradi (tizim + qog‘oz).
(6) Qayta ishga tushirish — yangi komissiya sanashidan (pastda, «Texnik — qayta ishga tushirish»).

**Texnik — to‘xtatish.** (1) «⚙ Sozlamalar» → «Kassa ishga tushadigan kun» bo‘shatiladi yoki keyinga suriladi (faqat Direktor).
Saqlashdan oldin oyna oqibatlarini sanab tasdiq so‘raydi («KASSANI TO‘XTATISH»). Kassa ishlab turgan bo‘lsa (kassa kuni bor)
kassa **to‘xtatiladi**: sana bo‘sh saqlanadi (surilgan sana faqat hodisa jurnalida qoladi — qayta ishga tushirish baribir sanash
bilan), «💵 To‘lov», maosh, avans, xarajat va qaytarish oynalari avvalgi (ordersiz) tartibga qaytadi; «Kassa» bo‘limi va yozilgan
hujjatlar joyida qoladi, yangi kassa hujjati yozilmaydi; «Kassa» sahifasida «Kassa to‘xtatilgan» ogohlantirishi turadi. Kim,
qachon va qaysi sanadan to‘xtatgani hodisa jurnaliga yoziladi. To‘xtatilgan kassada oxirgi kassa kuni qayta ochilmaydi — tuzatish
qayta ishga tushirish sanashida (farq dalolatnomasida) aks etadi. (2) Kod xatosi bo‘lsa — oldingi versiyaga qaytariladi (`git revert`
\+ deploy; sayt fayllari va server kodi — deploy chiqishidagi «Orqaga qaytarish» buyruqlari). (3) Bazadagi obyektlar o‘chirilmaydi,
zaxiradan tiklash — faqat maslahatlashib. Davr qulfi qayta ochilsa — sababi bilan.

**Texnik — qayta ishga tushirish** (Direktor, komissiya ishtirokida; to‘xtatilgan davrdagi barcha naqd yozuvlar va qurilmalar
navbati avval tizimga kiritilgan bo‘lsin — 4-bo‘lim, 1-qadam):
1. Komissiya kassadagi pulni sanaydi va dalolatnoma tuzadi (`shakllar.md`, Sh-3).
2. «Kassa» → **«Qayta ishga tushirish»**: sanalgan summa, qayta ishga tushadigan kun (bugun yoki keyingi kun, oxirgi kassa
   kunidan keyin), komissiya a’zolari. Tizim summani tizimdagi oxirgi kun oxiri qoldig‘i bilan solishtiradi: farq —
   to‘xtatilgan davrdagi naqd harakat (qog‘oz «Қ» bo‘yicha). U kassirga kamomad yoki ortiqcha sifatida yozilmaydi — tizim texnik
   dalolatnoma yozadi («Д-», asos «Qayta ishga tushirish: sanash dalolatnomasi»; ko‘p bo‘lsa Dt 5010 Kt 0000, kam bo‘lsa
   Dt 0000 Kt 5010; farq bo‘lmasa dalolatnoma yozilmaydi). Kun ochilguncha qayta kiritish mumkin (avvalgi dalolatnoma bekor bo‘ladi).
   **Qayta ishga tushadigan kun — to‘xtatilgan davrdagi oxirgi kassa hujjatisiz naqd yozuvdan keyingi kun:** shu kun yoki keyingi
   sana bilan bunday yozuv bo‘lsa tizim qoldiqni qabul qilmaydi (bugun shunday yozuv bo‘lgan bo‘lsa — ertangi kun). Sanashdan
   keyin, kassa qayta ishga tushguncha yana naqd yozuv kiritilsa — u sanashga kirmagan: komissiya qayta sanaydi va qoldiq qayta
   kiritiladi (qayta ishga tushadigan kun bugun bo‘lib, yozuv ham bugungi sana bilan bo‘lsa, 3-qadamni tizim qabul qilmaydi —
   qoldiq ertangi kun bilan qayta kiritiladi).
3. «⚙ Sozlamalar» → «Kassa ishga tushadigan kun» = o‘sha kun (boshqa sana qabul qilinmaydi). Shu kuni birinchi kun boshi =
   sanalgan summa; hujjatlar raqami tizimdagi oxirgi raqamdan davom etadi.
4. Buxgalter: nazorat ro‘yxatida **«Kassani to‘xtatish va qayta ishga tushirish»** qatori — har qayta ishga tushirish bo‘yicha
   farq va to‘xtatilgan davrda kassa hujjatisiz yozilgan naqd kirim va chiqim; ularni «Қ» jurnali va «Д-» dalolatnoma bilan
   solishtiradi. To‘xtatilgan davrda orqa sana bilan (oxirgi kassa kunidan oldingi sana) kiritilgan yozuvlar alohida ko‘rsatiladi;
   farq shu harakatlar bilan tushuntirilmasa — «izohlanmagan farq» (sariq): bu kamomad yoki ortiqcha, «Қ» jurnali bilan tekshiriladi.
   KO-3 jurnali va «Statiyalar»da farq «Qayta ishga tushirish farqi» qatorida alohida ko‘rsatiladi
   (kun boshi + kirim − chiqim + farq = kun oxiri). Kassa keyin yana to‘xtatilishi va qayta ishga tushirilishi mumkin — har gal
   shu tartibda, o‘z sanashi va dalolatnomasi bilan.

## 10. Qo‘llab-quvvatlash (birinchi 2 hafta)
Har kuni 15 daqiqalik qo‘ng‘iroq (kassir, moliya menejeri, administrator). Kassa ish soatlarida navbatchi. Muhimlik: ishni
to‘xtatadigan xato — o‘sha kuni (tuzalmasa — «Қ» blankalari); noqulaylik — 2 ish kuni; istak — keyingi yangilanish. Har hafta —
nazorat ro‘yxati, «Kassa» → «KPI» (haftalik ko‘rsatkichlar; dushanba kungi Telegram hisobotida ham) va `kassa-checks.sql`
natijasi ko‘rib chiqiladi.
