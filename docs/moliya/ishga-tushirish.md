# «Kassa» bo‘limini ishga tushirish to‘plami (F1.19)

**Holat:** tayyor, o‘qitish va ishga tushirishda ishlatiladi. Bo‘lim hali jonli tizimga chiqmagan (faqat sinov stendida).
Egasining 2026-11-16 javoblari va 2026-11-17 ko‘rsatmasi (kassir tizimda «Kassir» roli bilan ishlaydi) kiritilgan (ro‘yxati —
`buxgalteriya-ish-reja.md`, 0-bosqich, «Egasi javoblari — 2026-11-16»).
Ism, lavozim, rekvizit va summalar bu yerda yozilmaydi (repozitoriy ommaviy) — `[___]` o‘rniga qog‘ozda to‘ldiriladi.

**To‘plam tarkibi**
| Hujjat | Kim uchun | Fayl |
|---|---|---|
| Ishga tushirish tartibi (shu fayl): taqvim, shartlar, texnik tartib, yil yakuni (30-dekabr kechqurun, 4-yanvar ertalab), birinchi kunlar, orqaga qaytish | direktor, moliya menejeri, buxgalter, administrator | `docs/moliya/ishga-tushirish.md` |
| Rol bo‘yicha bir varaqli yo‘riqnomalar | kassir, moliya menejeri, buxgalter, direktor, HR, hisobdorlar, qabulxona (ota-ona kodi) | `docs/moliya/yoriqnomalar.md` |
| Shakllar ro‘yxati va qog‘oz shablonlari (avans hisoboti, «Қ» blankasi, sanash va daftarlarni yopish dalolatnomalari, qabul sinovi varag‘i, buxgalter tasdiq varag‘i Sh-8) | kassir, buxgalter, komissiya | `docs/moliya/shakllar.md` |
| Buyruq namunalari (imzo ro‘yxatlari, komissiya, kassir, shakllar, hujjatlar aylanishi) | direktor, buxgalter | `docs/moliya/buyruq-namunalari.md` |
| Oraliq qoidalar (ishga tushguncha) | hamma | `docs/moliya/oraliq-qoidalar.md` |
| Ish reja (asoslar va qarorlar) | — | `docs/moliya/buxgalteriya-ish-reja.md` |

---

## 1. Taqvim
| Sana | Nima | Kim |
|---|---|---|
| 16-noyabrdan | Oraliq qoidalar amalda (e’lon qilingan) | hamma |
| 16-noyabr haftasi, yangilanishdan keyin | `yoriqnomalar.md`, 6-bo‘lim (ota-ona kodi) — qabulxonaga beriladi (o‘qitishni kutmaydi); Direktor deploy chiqishidagi «payer-code-mask» sonlarini ko‘radi (3-bo‘lim, «Ota-ona kodi») va «… ta maosh vedomosti qatori … Direktor tasdig‘iga o‘tkazildi» qatori bo‘lsa — o‘sha qatorlarni pul berilishidan oldin ko‘radi (3-bo‘lim, «Xodim kartasi ↔ login va o‘z maoshi») | Direktor; server huquqi bor shaxs (deploy chiqishidagi shu qatorlarni beradi) |
| 21-noyabr | Buxgalter hisob qismini (hisobvaraqlar, statiyalar, operatsiyalar), buyruq namunalari va qog‘oz shakllarni ko‘rib chiqadi — vaqtincha tasdiq (`shakllar.md`, Sh-8) | buxgalter |
| 12-dekabr | Buyruqlar va moddiy javobgarlik shartnomalari imzolangan; fiskal kassa bo‘yicha yozma tasdiq; hisob siyosati qarorlari (Sh-8 imzolangan) | direktor, buxgalter |
| 14-dekabrgacha | Sinov stendi o‘rnatilgan (§3.1); rollar bo‘yicha yo‘riqnomalar va qog‘oz shakllar tarqatilgan | server huquqi bor shaxs (stend), Direktor (tarqatish) |
| 14–18-dekabr (du–ju) | Sinov stendida o‘qitish va 1-qabul sinovi (taklif jadvali — pastda) | hamma rollar |
| 19-dekabr | Tizim vedomosti buxgalter hisobotidagi ish haqi fondiga mosligi yozma tasdiqlanadi (Sh-8, B19) | buxgalter |
| ≈ 21-dekabr (dushanba), ish vaqtidan keyin | **Yashirin o‘rnatish**: bo‘lim jonli tizimga chiqadi, lekin «ishga tushadigan kun» bo‘sh — hamma oyna avvalgidek ishlaydi (shart: 1-qabul sinovi va buxgalterning stenddagi ko‘rigi — yozma rozilik bilan) | server huquqi bor shaxs (§3) |
| 21–25-dekabr (du–ju) | 2-qabul sinovi (stendda), maosh kuni mashqi | hamma rollar |
| 26-dekabr | Qabul sinovi varaqlari (Sh-5) imzolangan; **shartlar (G1–G6) bo‘yicha yakuniy tekshiruv** | direktor |
| **30-dekabr (chorshanba) kechqurun**, kassa yopilgach | Komissiya sanashi, qog‘oz daftarlarni yopish, sozlamalar, boshlang‘ich qoldiq, «Kassa ishga tushadigan kun», berilmagan qaytarishlar ro‘yxati (§4) | komissiya, direktor, buxgalter (ikkalasi shaxsan) |
| 31-dekabr (payshanba) | **Kassa naqd pul qabul qilmaydi va bermaydi** (Click, Uzum va bank orqali to‘lovlar ishlayveradi) | kassir |
| 1–3-yanvar | Kassa yopiq (1-yanvar — bayram, 2–3-yanvar — dam olish) | — |
| 4-yanvar ertalab, birinchi kassa kuni ochilishidan oldin | «31-dekabr holati» davr surati qulf bilan (§4, 8–9-qadamlar); 31-dekabrda naqd harakat bo‘lgan bo‘lsa — avval qayta sanash | direktor, komissiya |
| 4-yanvar (dushanba) — birinchi kassa kuni | **Rasmiy boshlanish** (egasi qarori, 2026-11-16) | kassir (g‘aznachi) |
| Birinchi 5 ish kuni | Parallel yuritish: kunlik nazorat varag‘i | moliya menejeri |
| Yanvar oxiri | Oy oxiri sanashi; yanvar avans hisobotlari kiritiladi; davrni yopish | komissiya, buxgalter, direktor |

Biror shart bajarilmasa — boshlanish sanasi suriladi (keyingi oyning birinchi ish kuni — zaxira sana 1-fevral; boshlang‘ich qoldiq — o‘sha oy oxiridagi sanash).

**Kassa ish kunlari** — dushanba–juma; shanba, yakshanba va bayram kunlari kassa yopiq. Ish soatlarini Direktor ichki kassa
nizomiga yozadi (`buyruq-namunalari.md`, 6-bo‘lim, 1-band).

**O‘qitish — TAKLIF jadvali.** Davomiylikni egasi qabul qilgan (2026-11-16); kun va soat — taklif, Direktor tasdiqlaydi yoki
o‘zgartiradi. Hammasi sinov stendida, dushanba–juma; kassirlar — kassa yopilgandan keyin (ish soatlari nizomda belgilangach aniqlanadi).
| Kun | Kim | Davomiylik | Mazmun |
|---|---|---|---|
| 14-dekabr (du) | kassir (g‘aznachi) va o‘rinbosar | 90 daqiqa | kirim (fiskal chek bilan), chiqim so‘rovi va pul berish, kunni sanab yopish, chop etish |
| 15-dekabr (se) | moliya menejeri va buxgalter | 60 daqiqa | tasdiq, kunni tekshirish, nazorat ro‘yxati, avans hisoboti, KO-3, oylik to‘plam |
| 16-dekabr (ch) | kassir (g‘aznachi) va o‘rinbosar | 90 daqiqa | smena topshirish, qurilma navbati, «Қ» blankalari, xato hujjat, favqulodda holatlar (8-bo‘lim) |
| 16-dekabr (ch) | Direktor; HR | 30 daqiqa (har biri) | Direktor: sozlamalar, boshlang‘ich qoldiq, tasdiq, kamomad qarori, davr; HR: vedomost tasdig‘i |
| 17-dekabr (pa) | hisobdorlar (zavxoz, oshpaz va b.) | 20 daqiqa | «Hisobdorga avans», «Олдим», cheklar, avans hisoboti (Sh-1), qaytim |
| 17–18-dekabr (pa–ju) | har rol | — | 1-qabul sinovi (Sh-5 qatorlari) |
| 21–25-dekabr (du–ju) | hamma rollar | — | 2-qabul sinovi (yashirin o‘rnatishdan keyingi tuzatishlar bilan); maosh kuni mashqi |
| 26-dekabrgacha | har rol | — | Sh-5 varaqlari imzolanadi |

## 2. Boshlashdan oldingi shartlar (belgilab chiqiladi)
- [ ] **Fiskal kassa (G1):** har naqd va karta to‘lovi onlayn kassa apparatidan (NKM) chek bilan o‘tadi — yozma tasdiq 12-dekabrgacha
  (chek turi va ta’lim xizmatining IKPU kodini buxgalter belgilaydi). Karta terminali shu NKM da — kechqurun bitta Z-hisobot (naqd + karta).
  Apparat buzilganda — soliq organida ro‘yxatdan o‘tgan maxsus kvitansiya daftari (maktabda bor). Naqd o‘quv to‘lovi tizimga faqat chek
  raqami bilan kiritiladi; aka-uka / opa-singil to‘lovida har o‘quvchiga alohida chek.
- [ ] **Buyruqlar (G5)** 12-dekabrgacha imzolangan: imzo ro‘yxatlari (1- va 2-ro‘yxat), inventarizatsiya komissiyasi, kassir (g‘aznachi) va o‘rinbosari, to‘liq moddiy javobgarlik shartnomalari (kamida kassir va o‘rinbosar bilan, kerak bo‘lsa zavxoz bilan ham; matnni yurist yakunlaydi), shakllar, hujjatlar aylanishi grafigi, ichki kassa nizomi; 1-buyruq 5-bandi — ijroni Direktorning o‘zi nazorat qiladi.
- [ ] **Hisob siyosati (G2):** hisobvaraqlar, statiyalar va operatsiyalar ro‘yxatini buxgalter tasdiqlagan — tasdiq varag‘i `shakllar.md`, **Sh-8**
  (B1–B21): 21-noyabr — kassa qismi, buyruq namunalari va qog‘oz shakllar bo‘yicha vaqtincha tasdiq; 12-dekabr — imzo; B19 — 19-dekabr.
- [ ] **Maosh (G3):** vedomost tasdig‘i yoqilgan (dekabrdan kechikmay); 2 ta takroriy maosh ID ni Direktor xodim kartasidagi «Yangi noyob ID
  berish» tugmasi bilan tuzatgan (aks holda vedomost HR’ga yuborilmaydi); noyabr vedomosti noyabr maoshi berilishidan oldin tizimda
  tayyorlanib, HR tasdiqlagan; dekabr vedomosti — maosh qaysi kun bo‘lmasin, maosh kunidan oldin tasdiqlanadi (yanvarda bo‘lsa — maosh
  kuni mashqi shunga moslanadi); HR menejer hisobi faol (bo‘lmasa vedomost tasdiqlanmaydi); HR menejer va moliya menejeri hisobi
  vedomost yuborilishidan oldin (noyabr vedomostidan; kechi bilan — dekabr vedomostidan oldin va 30-dekabrdan kechikmay) xodim kartasiga bog‘langan: bog‘lanmagan
  bo‘lsa, ularning o‘z maosh qatori Direktor tasdig‘ini talab qilmaydi (5-buyruq: «HR / MM o‘z maoshi — direktor»; belgi vedomost
  yuborilganda qo‘yiladi).
- [ ] **Hisoblar (login):** kassir, o‘rinbosar, moliya menejeri, buxgalter, HR va Direktor — har birining o‘z hisobi bor; parol boshqaga berilmaydi.
  Kassir — **G‘aznachi** lavozimidagi xodim (HR kartasida lavozim «G‘aznachi»): «Foydalanuvchilar»da rol **«Kassir»** — kirim
  orderlari («💵 To‘lov», «+ Kirim»), chiqim («+ Chiqim so‘rovi» → tasdiq → «Pulni berish»), kunni ochish va yopish, kunlik hisobot
  («🖨 Kunlik hisobot», KO-4) — hammasi shu rolda (16-noyabr haftasidagi yangilanishdan HR lavozimi «G‘aznachi» bo‘lgan xodimning
  yangi hisobini tasdiqlashda tizim «Kassir» rolini tavsiya qiladi). O‘rinbosar — buyruq bilan tayinlangan boshqa xodim (moliya
  menejeri va HR emas): o‘z roliga qo‘shimcha **«Kassir»** roli beriladi («Foydalanuvchilar» → «➕ Lavozim»), kassada «Kassir» rolida
  ishlaydi (sarlavhada «Rol: … ▾» bo‘lsa — undan «Kassir»ni tanlab). **«G‘aznachi» tizim roli kassa xodimlariga berilmaydi** (unda moliya menejeri
  darajasidagi huquqlar bor — vazifalar ajratilishi, FD-30): hozir «G‘aznachi» rolidagi hisob naqd bilan ishlasa — Direktor uni
  «Tahrirlash»da «Kassir»ga almashtiradi. Naqd pulni faqat kassir va o‘rinbosar oladi va beradi (Direktor — faqat favqulodda holatda).
  Buxgalterga «Foydalanuvchilar»da **«Buxgalter»** roli beriladi (bu rol tanlovda kassa bo‘limi o‘rnatilgandan keyin paydo bo‘ladi;
  bo‘limlari — «Tasdiqlash» va «Kassa» (so‘rovni tasdiqlash yoki rad etish, kunni tekshirish, hujjatni bekor qilish, avans hisoboti),
  «To‘lovlar» va «Buxgalteriya» (faqat ko‘rish); qo‘shimcha lavozim berilmaydi — F1.21). Kassa hisoblari (kassir, o‘rinbosar,
  moliya menejeri, buxgalter), HR menejer va Direktorning o‘z hisobi **30-dekabrgacha** «Foydalanuvchilar» → «Tahrirlash»da **xodim
  kartasiga (HR yozuviga) bog‘langan**, kartada F.I.Sh. hujjatdagidek to‘liq: kassa hujjatlaridagi ism shu kartadan olinadi (foydalanuvchi o‘zi
  yozgan ism emas), kamomad qarori xodim kartasiga yoziladi; nazorat ro‘yxatida «Xodim kartasiga bog‘lanmagan kassa hisoblari» — «yo‘q»
  (HR va Direktor hisobi bu ro‘yxatga kirmaydi — «Foydalanuvchilar» ro‘yxatida ism ostidagi «🔗» belgisidan tekshiriladi; HR va moliya
  menejeri hisobini bog‘lash muddati — G3).
- [ ] **Qabul sinovi:** kassir, moliya menejeri, buxgalter va direktor stendda o‘z ssenariylarini bajarib, varaqni imzolagan (`shakllar.md`, Sh-5).
  Stendda kassir — «Kassir» hisobi bilan (stenddagi «G‘aznachi» hisobi bilan emas); o‘rinbosar sinovi uchun bitta stend hisobiga
  qo‘shimcha «Kassir» roli beriladi («Foydalanuvchilar» → «➕ Lavozim»).
- [ ] **Kassa limiti:** bankdan yozma javob (limit xati) kelguncha limit 0 — ortgan naqd pul har kuni bankka topshiriladi; bank
  kontragentlar ro‘yxatida «Bank» turi bilan.
- [ ] **Kassa joyi va printer** — hammasi 30-dekabrdagi sanashgacha (printer sanash kechasi D-1 dalolatnomasini chop etish uchun kerak):
  A4 printer (KO-1 + patta, KO-2, KO-4, dalolatnomalar), sinov varag‘i chop etilgan; seyf, «Olindi» / «To‘landi» shtamplari, hujjat jildlari.
- [ ] **Hisobdorlar qoldig‘i:** zavxoz, oshpaz va boshqa hisobdorlar qo‘lidagi eski pul **30-dekabrgacha** (kassa naqd ishlaydigan oxirgi
  kun) cheklar bilan hisobot yoki qoldiqni qaytarish orqali to‘liq yopilgan; buxgalter har biridan 31-dekabr holatiga nol qoldiq
  ma’lumotnomasini (`shakllar.md`, Sh-7) olgan. Tizim eski pulni ko‘rmaydi — yanvarda u bo‘yicha na avans hisoboti, na qaytim qabul qilinadi.
- [ ] **Qog‘oz zaxira:** «Қ» blankalari va jurnali chop etilgan, buxgalter raqamlagan (`shakllar.md`, Sh-2); rollar bo‘yicha yo‘riqnomalar
  va qog‘oz shakllar — 14-dekabrgacha.
- [ ] **Eski «biriktirilmagan» naqd to‘lovlar** yo‘qligi 30-dekabrgacha buxgalter bilan tekshirilgan (8-bo‘lim oxiri, cheklov (2)).
- [ ] **Taqvim va xabarnoma:** yanvar bayram va ta’til kunlari «Bayram / ta’til kunlari» ro‘yxatiga oldindan kiritilgan (avans hisoboti
  muddati shu ro‘yxat, shanba va yakshanbasiz sanaladi); «Xabarnomalar» → «📊 Direktorga kunlik hisobot»: kunlar — Du–Ju, soat — kassa
  yopilgandan keyin (standart 19:00).

## 3. Texnik tartib (administrator)
Hamma buyruqlar serverda oddiy foydalanuvchidan; kalit va parollar hech qayerga ko‘chirilmaydi.
**Bajaruvchi** (egasi qarori, 2026-11-16) — server huquqi bor shaxs: deploylarni bajarayotgan egasi yoki u tayinlagan administrator.
Stend, yashirin o‘rnatish, tekshiruvlar va kerak bo‘lsa orqaga qaytarishni o‘sha shaxs bajaradi; birinchi 2 hafta texnik navbatchi ham
o‘sha (10-bo‘lim).

**3.1 Sinov stendi (qabul sinovi va o‘qitish shu yerda).** Shu haftadagi jonli yangilanish bilan birga, **14-dekabrdan oldin**
o‘rnatiladi. O‘rnatish va yangilash — `sinov/README.md`. Kassa bo‘limi bilan:
```bash
bash ~/iqror-repo/sinov/update.sh --dev
```
Yakuniy tekshiruvda «Kassa tekshiruvi: muammo topilmadi (modul relizi N)» qatori chiqishi kerak.
Relizi 11 dan oldingi stendni yangilaganda: o‘sha paytda o‘tkazilgan «Xodim qaytargan pul» (`in_staff_return`) orderlari bo‘lsa, ular
avans / maosh yozuvisiz yozilgan — yangilangach nazorat ro‘yxatidagi «Moslik» P5 «ret» qatorida (va `kassa-checks.sql` 20-bandida)
ko‘rinadi. Bu stenddagi eski sinov yozuvi (jonli tizimda bunday hujjat yo‘q — modul hali chiqmagan): qabul sinovidan oldin stend
ma’lumoti qayta yuklanadi yoki shu qator izohlanadi. Xuddi shunday, 24-band (vazifalar ajratilishi) eski sinov yozuvlarida «!!»
qatorlarini ko‘rsatishi mumkin: relizi 11 gacha tizim ruxsat bergan holatlar (masalan, Moliya menejeri o‘z kartasiga avansni tasdiqlagan,
tasdiqlovchining o‘zi pulni bergan, kunni bekor qilgan yoki smenada qatnashgan xodim tekshirgan), relizi 12 gacha — so‘rovni yolg‘iz
tasdiqlagan Direktor pulini o‘zi bergan, Direktor o‘ziga pulni o‘zi bergan, kunni qayta ochilishidan oldin yopgan xodim tekshirgan va band hozirgi rollar hamda xodim
kartasiga bog‘lanishlar bo‘yicha tekshiradi — hujjatdan keyin bog‘langan karta ham qatorga tushadi. Yangilash yordamchisi buni «Kassa
tekshiruvi … muammo» deb ko‘rsatadi; kod xatosi emas — stend ma’lumoti qayta yuklanadi yoki qatorlar qabul sinovidan oldin izohlanadi.

**3.2 Jonli zanjirga o‘tkazish (dasturchi, yashirin o‘rnatishdan oldin — bir marta).** Qabul sinovi va buxgalter ko‘rigidan keyin:
1. `migration/run-all.sql` dagi moliya qatorlaridan «`--dev `» belgisi olib tashlanadi (fin-core … fin-version; tartib o‘zgarmaydi).
2. `payments/_schema-columns.json` kanonik zanjirdan qayta tuziladi (`information_schema.columns`).
3. To‘liq sinov: SQL to‘plamlari (`test-kassa*.sql`, `test-fin-*.sql`, `test-kassa-checks.sql`, `test-audit-fixes.sql`,
   `test-public-close.sql`), `test-kassa-race.sh`, `node --test assets/js/*.test.mjs`, `payments` va `auth` `npm test`, brauzer
   ssenariylari — lokal stendda `bash tests/kassa-e2e/run-all.sh` (stendni ko‘tarish, hisoblar va kutilgan natijalar —
   `tests/kassa-e2e/README.md`; xulosa qatorlarida `fail=0`).
   Modul relizi o‘zgargan bo‘lsa, `kassa-checks.sql` dagi himoya mantig‘i barmoq izlari ham shu relizniki bo‘lishi kerak:
   `bash migration/kassa-fingerprints.sh` (lokal; `fin-version.sql` qoidasi) — `test-kassa-checks.sql` toza holati buni tekshiradi.
4. Hujjatlardagi «faqat lokal sinov zanjirida» belgilari yangilanadi; commit.
Qisman o‘tkazish (bayroq bilan, ayrim deploylarda) **qilinmaydi**: zanjir har deployda ichki funksiyalar huquqini qayta
beradi va kassa fayllari ularni qaytarib oladi — kassa fayllarisiz deploy bu himoyani ochiq qoldiradi.

**Mashq (2026-11-12, lokal, modul relizi 9):** jonli versiya (3108d19) prod zanjiri bilan qurilgan baza ustiga «`--dev`»siz
zanjir (jonli `lock_timeout` bilan) — xatosiz; qayta qo‘llash — xatosiz; `kassa-checks.sql` — «muammo topilmadi»; toza
o‘rnatishda barcha SQL to‘plamlari yashil; `payments` (192) va `auth` sinovlari yashil. 2-qadamda `_schema-columns.json` ga
qo‘shiladigan ustunlar: `payments.cashDocId`, `payments.fiscalNo`, `refunds.method`, `refunds.cashDocId`.

**3.3 Yashirin o‘rnatish (≈ 21-dekabr, dushanba, ish vaqtidan keyin — egasi tasdiqlagan, 2026-11-16).** Shart: 1-qabul sinovi
o‘tgan va buxgalter stenddagi ko‘rikdan keyin yozma rozilik bergan; yakuniy «ha» — egasi.
```bash
cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash migration/deploy/full-deploy.sh
```
Deploy chiqishida tekshiriladi: «7/7 baza tekshiruvi — BIR XIL»; «✓ Kassa tekshiruvi: muammo topilmadi (modul relizi N)».
Keyin, hali hech narsa kiritmasdan:
- Direktor hisobida «Moliya» → «Kassa» ochiladi: «Kassa hali ishga tushirilmagan» kartasi va «ishga tushirilgan deb belgilanmagan» eslatmasi ko‘rinadi.
- «💵 To‘lov», «Maosh berish», «Xarajat», «Qaytarish» oynalari avvalgidek ishlaydi (fiskal chek maydoni yo‘q) — bitta haqiqiy to‘lovni kutib kuzatish kifoya, sinov to‘lovi kiritilmaydi.
- Sinash kerak bo‘lsa — faqat **sinov kassasida** («Kassa» sahifasidagi kassa tanlovi → «Sinov kassasi»): boshlang‘ich qoldiq,
  «+ Kirim» → «Boshqa kirim», «+ Chiqim so‘rovi» → «Xarajat» → tasdiq → «Pulni berish», chop etish («СИНОВ» belgisi bilan), kunni yopish.
  «Boshqa kirim»da kimdan — kontragent yoki xodim tanlanadi (fiskal chek so‘ralmaydi); o‘quvchi yoki «Boshqa» shaxs tanlansa
  «Fiskal chek №» majburiy (Direktor — istisno belgisi bilan).
  Sinov kassasi hujjatlari hisobotlarga, «Buxgalteriya»ga va Telegram hisobotiga kirmaydi. O‘quv to‘lovi bilan sinov o‘tkazilmaydi
  (ota-onaga xabar ketadi). Sinov kassasini yopish va smena topshirish oynasida qurilma navbati ko‘rsatilmaydi va e’lon qilinmaydi
  (navbatdagi o‘quv to‘lovlari asosiy kassaga tushadi; tizim ham rad etadi).
- Direktorga kunlik Telegram hisoboti matni (hech narsa yubormaydi): auth xizmati papkasida `node tg-daily.cjs --dry` (`auth/README.md`,
  «Telegram bot») — kassa bloki hali yo‘q bo‘lishi kerak; ishga tushgach — bor.

**3.4 Istalgan payt tekshirish (faqat o‘qiydi):**
```bash
sudo docker exec -i supabase-db psql -U postgres -d postgres -X -P pager=off < ~/iqror-repo/migration/kassa-checks.sql
```
Chiqishda ism, telefon va summalar yo‘q. «!!» bilan boshlangan qator — muammo; izohi `migration/deploy/README.md` da. 23-band —
himoya mantig‘i izi: funksiya, himoya triggeri, o‘qish siyosati yoki cheklov shu relizdagidan farq qilsa (qo‘lda «tuzatilgan» baza)
deploydan oldin ham ko‘rinadi; 24-band — vazifalar ajratilishi (tasdiqsiz o‘tgan hujjat, o‘zi tasdiqlagan, pulni tasdiqlovchi bergan,
kunni unda qatnashgan xodim tekshirgan). Farq qaysi obyektda ekanini to‘liq solishtirish (faqat o‘qiydi; vaqtinchalik bazada kanonik
zanjirni quradi) — har haftalik ko‘rikda ham:
```bash
bash ~/iqror-repo/migration/verify-db.sh
```

## 4. Yil yakuni: 30-dekabr kechqurun va 4-yanvar ertalab
Tartib muhim — yuqoridan pastga. Hamma amal Direktor hisobida, komissiya ishtirokida (egasi qarori, 2026-11-16):
- **30-dekabr (chorshanba) kechqurun, kassa yopilgandan keyin** — 1–7-qadamlar. Direktor va buxgalter shaxsan qatnashadi.
- **31-dekabr (payshanba) kassa naqd pul qabul qilmaydi va bermaydi** (Click, Uzum va bank orqali to‘lovlar ishlayveradi): sanalgan
  pul = boshlang‘ich qoldiq. **1–3-yanvar** kassa yopiq. Bu kunlarda kassa hujjati baribir yozilmaydi — tizim birinchi kassa kunini kutadi.
- **31-dekabr istisnosi.** Istisno tariqasida 31-dekabr kuni naqd pul olinsa yoki berilsa — eski qog‘oz orderda yoziladi va tizimga
  o‘sha kuni avvalgidek (kirim / chiqim ordersiz) kiritiladi; qog‘oz daftarlar o‘sha amaldan keyin yopiladi (Sh-4 dalolatnomasi yangi
  oxirgi raqam bilan qayta tuziladi). **4-yanvar ertalab**, birinchi kassa kuni ochilishidan oldin komissiya pulni qayta sanaydi (yangi Sh-3) va boshlang‘ich
  qoldiq qayta kiritiladi (5-qadam). Tizim buni o‘zi talab qilmaydi — qayta sanalmasa, farq birinchi kunni yopishda kassirga chiqadi.
- **4-yanvar (dushanba) ertalab, birinchi kassa kuni ochilishidan oldin** — 8–9-qadamlar (davr surati va qulf).

1. **Kun yakuni eski tartibda:** oxirgi qog‘oz kirim va chiqim orderlari yoziladi, kunlik varaq yopiladi. **Sanashdan oldin
   hamma naqd yozuv tizimda bo‘lsin:** to‘lov qabul qiladigan barcha qurilmalar (kompyuter, telefon) internetga ulanadi va
   navbati (⏳) bo‘shaguncha kutiladi; kassadan berilgan xarajat, maosh va avanslar ham kiritiladi. Sanashdan keyin topilgan
   kechikkan yozuv — pastdagi «Kechikib topilgan yozuv» bandi bo‘yicha.
2. **Komissiya kassani sanaydi** (nominallar bo‘yicha) va dalolatnoma tuzadi (`shakllar.md`, Sh-3): sanalgan summa, hisobdagi
   qoldiq, farq va uning sababi. Komissiya: rais — Direktor; a’zolar — bosh buxgalter va moliya menejeri; kassir (g‘aznachi) a’zo
   emas, sanashda qatnashadi. Farq majburan tenglashtirilmaydi — Direktor qaror qiladi (kamomad — javobgar shaxsga yoki zararga; ortiqcha — daromadga).
3. **Qog‘oz order daftarlari yopiladi** (Sh-4): oxirgi П/О va Р/О raqamlari, ishlatilmagan blankalar bekor qilinadi; buxgalter imzolaydi.
4. **«Kassa» → «⚙ Sozlamalar»** (egasi qarorlari, 2026-11-16): tashkilot nomi va tashkiliy-huquqiy shakli — ro‘yxatdan o‘tish
   guvohnomasidagidek (buxgalter tekshiradi), STIR, joy, chop etish tili; T1 (shundan katta chiqimga Direktor tasdig‘i) — summa
   buyruqdagi bilan bir xil (Direktor o‘zi yozadi; 0 qolsa har chiqim Direktor tasdig‘ini kutadi); L1 (asos hujjatisiz naqd xarid
   chegarasi) — **0**, hujjatsiz xarid yo‘q (juda kerak bo‘lsa keyin kichik chegara va faqat bitta statiya); kassa limiti — bankdan yozma
   javob kelguncha **0**; **yuridik shaxsga kassadan naqd to‘lov chegarasi** (yetkazib beruvchi / tashkilotga shu summagacha Direktor
   tasdig‘isiz; bo‘sh yoki 0 — har doim Direktor; buxgalter hisob siyosatida tasdiqlaydi) — **0**: har biri Direktor tasdig‘i bilan,
   asosiy yo‘l — bank o‘tkazmasi; **imzo egalari** (1-ro‘yxat — Direktor va buyruq bilan tayinlangan o‘rinbosar, moliya menejeri emas;
   2-ro‘yxat — bosh buxgalter / moliya menejeri; to‘liq F.I.Sh., lavozimi, tizimdagi hisobi). Kontragentlar turi to‘g‘ri bo‘lsin: korxona (MChJ, AJ va b.) — «Yetkazib beruvchi» yoki «Tashkilot», yakka
   tadbirkor va fuqaro — «Jismoniy shaxs», bank — «Bank». «Jismoniy shaxs» va «Boshqa» turini buxgalter yoki Direktor kiritadi yoki tasdiqlaydi
   (nazorat ro‘yxati → «Kontragent turi»): kassir yoki moliya menejeri kiritgani tasdiqlanguncha yuridik shaxs hisoblanadi (kassadan
   naqd to‘lovga Direktor tasdig‘i kerak).
5. **«Boshlang‘ich qoldiqni kiritish»:** summa — komissiya sanagan pul; «Birinchi kassa kuni» — 2027-01-04 (yanvarning birinchi kassa kuni);
   komissiya a’zolari. Tizim «Boshlang‘ich qoldiq» dalolatnomasini yozadi (D-1) — chop etilib, komissiya imzolaydi (dalolatnomada
   komissiya tarkibi kiritilganidek chiqadi va har a’zoga imzo qatori bor).
   Birinchi kassa kuni ochilguncha qoldiqni qayta kiritish mumkin (avvalgi dalolatnoma bekor bo‘ladi, raqami saqlanadi).
   **Sanashdan keyin va birinchi kassa kunidan oldin naqd pul harakati bo‘lsa** (masalan, 31-dekabr istisnosi) —
   birinchi kassa kuni (4-yanvar) ertalab pul qayta sanaladi va boshlang‘ich qoldiq qayta kiritiladi: u birinchi hujjatdan oldingi haqiqiy pulga teng bo‘lishi shart.
   «Birinchi kassa kuni» odatda ishga tushadigan kunning o‘zi (6-qadam). Undan oldin bo‘lsa va o‘sha kuni kassa hujjati yozilsa — kassa
   **o‘sha kundan** ishlagan hisoblanadi: ishga tushgach o‘sha kun sanasi bilan kassa hujjatisiz naqd yozuv kiritilmaydi (Direktorga
   ham), «Moslik» uni ham tekshiradi.
6. **«⚙ Sozlamalar» → «Kassa ishga tushadigan kun»** = birinchi kassa kuni. Shu kundan boshlab har naqd o‘quv to‘lovi kirim orderi
   va fiskal chek raqami bilan, faqat «💵 To‘lov» orqali yoziladi (to‘lov yozuvini to‘g‘ridan-to‘g‘ri kiritish yoki «naqd» kanal bilan
   balansga qo‘llash — Direktorga ham yo‘q). Sana 30-dekabr kechqurun (oldindan) kiritiladi: 2027-01-04. Bugungi yoki o‘tgan kun qo‘yilsa, tizim
   tekshiradi: shu kundan beri kassa orderisiz naqd yozuv (o‘quv to‘lovi, xarajat, maosh, avans, qaytarish) bo‘lsa — sozlama
   saqlanmaydi va sanani o‘sha yozuvlardan keyingi kunga qo‘yish so‘raladi (ular boshlang‘ich qoldiq sanashiga kiradi).
7. **To‘lanmagan qaytarishlar:** «↩ Qaytarish» orqali tasdiqlangan, lekin hali berilmagan pullar ro‘yxati (yangi yilda kassadan «Qaytarish» chiqim orderi bilan beriladi).
8. **Davr surati — «31-dekabr holati»** (yil yakuni surati; **4-yanvar ertalab, birinchi kassa kuni ochilishidan oldin**; 31-dekabr
   istisnosi bo‘lsa — kechikkan yozuvlar kiritilib, qayta sanash va 5-qadamdan keyin): «Kassa» → «Davr» → «Yangi surat»: «Qaysi kun
   oxiri holati» = 31-dekabr, **«Shu sanagacha davrni yopish»** belgisi qo‘yilgan holda → «Surat olish» — surat va qulf bitta amalda
   (davrni yopib bo‘lmasa, surat ham olinmaydi). 30-dekabrda «31-dekabr holati» olinmaydi (kelajakdagi sana), 31-dekabrda esa qulf bilan
   olinmaydi (bugungi kun yopilmaydi) — shuning uchun 4-yanvar ertalab. Surat — olingan paytdagi holat, ro‘yxatda «kechikib olingan»
   belgisi bilan chiqadi: kassa kuni ochilishidan oldin olinsa, unga yanvar kassa hujjatlari aralashmaydi (kassa qoldig‘i =
   boshlang‘ich qoldiq), yanvarda surat olinguncha (1–3-yanvar va 4-yanvar ertalab) kelgan onlayn to‘lovlar (Click, Uzum, bank) esa
   kirgan bo‘ladi — buxgalter ularni «To‘lovlar»dagi shu kunlar ro‘yxati bilan ayiradi. Suratda: o‘quvchilar qarzi va avanslari, biriktirilmagan tushumlar, kassa
   qoldig‘i, to‘lanmagan ish haqi, berilmagan qaytarishlar. «⬇ JSON» bilan yuklab (Direktor yuklagani — ismli to‘liq nusxa; moliya menejeri va buxgalterga ismsiz nusxa
   beriladi), ismli nusxa Direktorning xavfsiz arxiviga qo‘yiladi.
9. **Davrni yopish** — 8-qadamdagi belgi bilan surat bilan birga (alohida kerak bo‘lsa: «Davr» → «Davr qulfini o‘zgartirish» →
   «Shu sanagacha yopiq» = 31-dekabr → «Qulfni saqlash»). Qulfdan **oldin** 31-dekabrgacha sanali kechikkan yozuvlar kiritilgan
   bo‘lsin (pastdagi «Kechikib topilgan yozuv»). Shundan keyin 31-dekabrgacha
   sanali to‘lov, xarajat, maosh to‘lovi va avans kiritilmaydi va o‘zgartirilmaydi (onlayn to‘lovlar bundan mustasno); o‘sha davr
   to‘lovini qaytarish, biriktirish yoki holatini o‘zgartirish ham (tushum o‘zgaradi) — avval davr sababi bilan qayta ochiladi. Keyingi
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
- **Boshqa rollar** (kassir, moliya menejeri va b.) bunday yozuvni o‘zi kirita olmaydi — tizim rad etadi. Faqat kassir
  qurilmasi navbatida qolib ketgan yozuv (ishga tushishdan oldin yozilgan, 48 soatdan eski emas) internet qaytganda o‘zi
  o‘tadi — u ham kirim orderisiz; undan eskisini Direktor kiritadi.
- Bunday yozuvlar nazorat ro‘yxatida «Kassa ishga tushishidan oldingi naqd yozuvlar (keyin kiritilgan)» qatorida ko‘rinadi
  (ma’lumot uchun): buxgalter ularni sanash dalolatnomasi bilan solishtiradi. Davr qulfi (8–9-qadamlar) ularga ham amal qiladi —
  31-dekabrgacha sanali yozuv 4-yanvar ertalabki qulfdan keyin kiritilmaydi (Direktorga ham; avval davr sababi bilan qayta ochiladi).
- Bu tartib faqat **kassa ishlamagan kunlar** uchun: kassa **birinchi** ishga tushgan kundan (birinchi kassa hujjati ishga tushadigan
  kundan oldin yozilgan bo‘lsa — o‘sha kundan) oldingi sana yoki kassa to‘xtatilgan
  davr ichidagi sana (9-bo‘lim; bu davr yozuvlari «Kassani to‘xtatish va qayta ishga tushirish» qatorida). Kassa ishlagan kun
  sanasi bilan (kassa to‘xtatilib qayta ishga tushirilgandan keyin ham — oldingi davrning yopilgan kuni) kassa hujjatisiz naqd yozuv
  kiritilmaydi: naqd o‘quv to‘lovi bugungi kirim orderi bilan yoziladi, xarajat, maosh va avans — faqat «Kassa» orqali (tizim rad
  etadi: «kassa kuni edi»).

## 5. Birinchi kassa kuni (4-yanvar)
- [ ] Ertalab, birinchi hujjatdan oldin (Direktor): 31-dekabrda naqd harakat bo‘lgan bo‘lsa — kechikkan yozuvlar kiritilgan, komissiya
  qayta sanagan va boshlang‘ich qoldiq qayta kiritilgan; «31-dekabr holati» surati qulf bilan olingan (4-bo‘lim, 8–9-qadamlar) —
  tugagach kassirga ayting (kassir shungacha kassa hujjati yozmaydi).
- [ ] Ertalab «Kassa»: «Oxirgi qoldiq» = boshlang‘ich qoldiq = kassadagi haqiqiy pul (farq bo‘lsa — birinchi hujjatdan oldin qayta sanab, qayta kiriting); qizil ogohlantirish yo‘q.
- [ ] Birinchi naqd o‘quv to‘lovi: NKM da fiskal chek urildi → «💵 To‘lov» (chek raqami bilan) → «🖨 Kirim orderi va patta»; patta to‘lovchiga, order kassada.
- [ ] Birinchi chiqim: «+ Chiqim so‘rovi» → moliya menejeri «Tasdiqlash» → kassir «Pulni berish» → «🖨 Chiqim orderi», oluvchi imzosi.
- [ ] Kechqurun: NKM Z-hisoboti (naqd + karta, bitta) → «Kunni yopish» — pul sanaladi, summa va Z-hisobot kiritiladi; «🖨 KO-4» ikki nusxa (kassa kitobi varag‘i va kassir hisoboti) va «🖨 Kunlik hisobot».
- [ ] Buxgalter (u yo‘q kuni — moliya menejeri): qog‘ozlarni olib, «Tekshirish» → «Tekshirdim».
- [ ] Direktor: Telegram hisobotida kassa bloki (kirim, chiqim, qoldiq, sanash) va nazorat qatori. Hisobot kunlari va soati — «Xabarnomalar» →
  «📊 Direktorga kunlik hisobot»: kunlar — Du–Ju (yangi o‘rnatishda standart shunday; mavjud bazada «Sh» belgilangan bo‘lsa — olib tashlanadi), soat — kassa yopilgandan keyin (standart 19:00).
  Hisobot yuborilgandan keyin (kechqurun) va hisobot yuborilmagan kunlarda (shanba, yakshanba, bayram) tushgan to‘lovlar keyingi hisobotda
  «🌙 Oldingi hisobotdan keyin …» qatorida chiqadi; vaqtinchalik xato bilan yetkazilmagan hisobot keyingi tekshiruvda (15 daqiqadan keyin) qayta yuboriladi.
- [ ] Kassa yopilgach 15 daqiqalik qo‘ng‘iroq: kassir, moliya menejeri, texnik navbatchi (10-bo‘lim).

## 6. Parallel yuritish (birinchi 5 ish kuni)
Excel yuritilmaydi. Moliya menejeri har kuni (≈ 10 daqiqa) nazorat varag‘ini to‘ldiradi (`shakllar.md`, Sh-6). Chiqish sharti —
**ketma-ket 3 ish kuni**: sanalgan pul = tizimdagi qoldiq; har order qog‘oz manbasi bilan; Click / Uzum kabinetidagi summalar =
kunlik hisobotdagi «kanallar» bloki; bankka topshirish va bankdan olish = bank hujjatlari; raqamlar uzluksiz, bekor qilishlar
izohlangan; Telegram = kunlik hisobot; nazorat ro‘yxatida «Moslik» qatori — «hammasi mos»; tushuntirilmagan farq yo‘q.
Click / Uzum kabinetlari va bank hujjatlarini ko‘rish imkonini moliya menejeriga Direktor beradi (egasi qarori, 2026-11-16); chiqish
sharti bajarilgach parallel yuritishni tugatish qarorini Direktor imzolaydi (Sh-6).

## 7. Oy oxiri
1. Oyning oxirgi ish kuni — komissiya sanashi: kunni Direktor yoki moliya menejeri komissiya ishtirokida yopadi (yopish oynasida
   komissiya a’zolari kiritiladi — kamida 2 kishi), sanash dalolatnomasi chop etilib imzolanadi.
2. Barcha kunlar «Tekshirilgan»; nazorat ro‘yxatida qizil qator yo‘q; `kassa-checks.sql` — «muammo topilmadi».
3. Yanvar avans hisobotlari (qog‘oz, Sh-1) buxgalterga topshirilgan va «Kassa» → «Avans hisoboti» bilan kiritilgan.
4. «KO-3» jurnali (oy) chop etilib bosh buxgalter imzolaydi; Excel nusxasi buxgalter dasturiga olinadi (buxgalter va Moliya
   menejerida — ismsiz, FD-28; to‘liq nusxa kerak bo‘lsa — Direktor yuklaydi va xavfsiz arxivida saqlaydi, buxgalterga ismsiz nusxa
   beriladi); jurnal oynasida qoldiqlar mos (ogohlantirish yo‘q).
   «Statiyalar» — oylik statiya matritsasi chop etilib imzolanadi; «Oylik to‘plam (Excel)» (KO-3, statiyalar, kassa kunlari,
   hisobdorlar) buxgalterga topshiriladi.
5. «Davr» → surat (oy oxiri) → keyingi ish kuni qulf (oyning oxirgi kassa kuni yopilmagan bo‘lsa tizim davrni yopmaydi; oy kunlaridan
   biri hali bog‘lanmagan «hali o‘tkazilmagan» yozuvlar — kech kirim orderi kelmagan qurilma navbati yozuvi yoki «Қ» blankalari —
   bilan yopilgan va tekshirilmagan bo‘lsa ham: avval navbat yuboriladi, qolganini 2-ro‘yxat kunni izoh bilan tekshirib tasdiqlaydi).

## 8. Favqulodda holatlar
| Holat | Nima qilinadi |
|---|---|
| Internet uzildi | Fiskal chek uriladi (kassa apparati oflayn rejimda). «💵 To‘lov» qurilmada navbatga yoziladi; to‘lovchiga tizimdan varaqa berilmaydi — dalil fiskal chek. Internet qaytgach yozuv o‘zi o‘tadi va kirim orderi chiqadi. **Kunni yopish** avval qurilma navbatini yuboradi; yuborilmay qolgan yozuvlar oynada ko‘rinadi va har biri o‘z kaliti bilan «hali o‘tkazilmagan yozuv» sifatida o‘zi hisobga olinadi (bu pul kassada bor, hisobda hali yo‘q; qo‘lda kiritilmaydi, yopish to‘xtatilmaydi) — shu payt o‘tib ketganini tizim ayirmaydi (natija xabarida aytiladi). Navbat **boshqa** qurilmada bo‘lsa — avval o‘sha qurilma internetga ulanadi va navbati o‘tadi (aks holda farq chiqadi). Oyna ochilgandan keyin kassa qoldig‘i o‘zgarsa (masalan, navbat shu orada o‘tdi) tizim yopmaydi: oyna yangi qoldiq bilan qayta ochiladi, pul qayta sanaladi (smena topshirishda ham). Smena topshirishda e’lon qilingan, hali kelmagan yozuvlarni tizim qabul qiluvchining kunni yopishi va keyingi smena topshirishida o‘zi hisobga oladi (oynada alohida qator) — navbat topshiruvchi qurilmasida qolgan bo‘lsa ham farq chiqmaydi; ular kichigidan boshlab sanalgan pulga sig‘guncha ayiriladi, sig‘magani ayirilmaydi — u bog‘lanmagan bo‘lib qoladi (kunni tekshirishda izoh; keyin kelsa, o‘sha yopishdagi ortiqcha va kelgan kungi kamomad birgalikda haqiqiy farqni beradi), yopish to‘xtamaydi. O‘sha to‘lov yangi kalit bilan qayta kiritilgan bo‘lsa (eski navbat yozuvi endi kelmaydi; qurilmada qolgan bo‘lsa — o‘chiriladi) va sanalgan pul yetsa, yopishda shu summaga kamomad, keyingi sanashda esa xuddi shuncha ortiqcha chiqadi: kamomad haqiqiy emas — Direktor uni xodim hisobiga emas, «Hisobdan chiqarish» bilan yopadi (ortiqcha uni qoplaydi), ikkala kun izohida sababi yoziladi. Server kassaga tegishli emas deb rad etgan navbat yozuvi (kassa ishga tushishidan oldingi yoki to‘xtatilgan davr puli, yopilgan oy sanasi) yopishda e’lon qilinmaydi — oynada soni ko‘rsatiladi. Boshqa sabab bilan rad etilgan («Yuborilmadi») yozuvlar oynada alohida, server xatosi bilan ko‘rsatiladi va har biri uchun tanlov so‘raladi (tanlanmaguncha oyna saqlamaydi): pul kassada (qayta kiritilmagan) — «hali o‘tkazilmagan yozuv» bo‘lib e’lon qilinadi; to‘g‘ri ma’lumot bilan qayta kiritilgan yoki pul qaytarilgan — e’lon qilinmaydi va kun yopilgach (smena topshirilgach) navbatdan o‘chiriladi. Avval hammasi e’lon qilinardi: «💵 To‘lov» oynasida rad etilgan to‘lov (masalan, fiskal chek raqami takror) tuzatilib qayta kiritilgach ham pul ikki marta ayirilib, soxta kamomad chiqardi. Shu oynadan o‘sha o‘quvchi uchun tuzatilib qayta kiritilganda rad etilgan yozuv navbatdan o‘zi almashtiriladi (boshqa o‘quvchi tanlansa — qoladi). Kun yopilgandan keyin navbatdagi yozuv kutib turadi («Navbatda · Bugungi kassa kuni yopilgan …» — o‘chirilmaydi) va keyingi ochiq kassa kuniga «kech» belgisi bilan tushadi (pul olingan payt saqlanadi) — yopishdagi yozuv bilan bog‘lanadi; u faqat sahifa ishlatilayotganda (oxirgi 30 daqiqada bosilgan yoki yozilgan) yuboriladi — kechasi yoki dam olish kuni ochiq qolgan brauzer kassa kunini o‘zi ochmaydi (ertalab sahifani bir bosish yetarli). Onlayn kassa Z-hisoboti bilan u chek tushgan NKM smenasi kuniga solishtiriladi — pul olingandan keyin yopilgan birinchi kassa kuni (odatda pul olingan kun; kun yopilgandan keyin olingan bo‘lsa — keyingi yopilgan kun; bunday kun bo‘lmasa, masalan yakshanba olingan pul, — order kuni): yozuv kelguncha o‘sha kunda Z farqi ko‘rinishi mumkin. 2 kun (48 soat) ichida kelmagan yozuv nazorat ro‘yxatida sariq («Hali kelmagan «hali o‘tkazilmagan» yozuvlar»); bunday kunni tekshirishda izoh majburiy. 48 soatdan eski yozuvni faqat Direktor kiritadi. Navbat bo‘shamaguncha kassa to‘xtatilmaydi (9-bo‘lim). |
| Tizim (server) ishlamayapti | Ichki «Қ» blankasi to‘ldiriladi (to‘lovchiga berilmaydi), jurnalga yoziladi; fiskal chek uriladi. Tizim **o‘sha kuni, kun yopilishidan oldin** tiklansa — yozuvlar shu kunga kiritiladi (izohda — «Қ» raqami), kun odatdagidek yopiladi. **Server ishlamagan kun yopilmay qolgan bo‘lsa** (masalan, ertasi ertalab tiklandi): (1) avval o‘sha kun yopiladi — «Kunni yopish» oynasidagi **«Server ishlamagan paytdagi «Қ» blankalari»** maydonlariga hali kiritilmagan blankalar soni, summasi va raqamlari yoziladi (bu pul kassada bor, hisobda hali yo‘q — sanashdan ayiriladi, farq chiqmaydi; yozilmasa — o‘sha kun ortiqcha, keyingi kun kamomad chiqadi); (2) keyin har bir «Қ» yozuvi joriy kassa kuniga kiritiladi (izohda — «Қ» raqami va pul olingan sana), jurnalda order raqami belgilanadi. O‘sha kunni tekshirishda izoh majburiy (2-ro‘yxat blankalarni kiritilgan orderlar bilan solishtiradi); kun tekshirilguncha oy davri yopilmaydi. **Z-hisobot:** fiskal cheklar server ishlamagan kunda urilgan (o‘sha kun Z ida bor), «Қ» yozuvlari esa kiritilgan kunga tushadi («kech» emas) — server ishlamagan kunda Z farqi «+», «Қ» yozuvlari kiritilgan kunda xuddi shuncha «−». Ikkala kunni tekshirishda izoh majburiy: tekshiruvchi «Қ» blankalarini kiritilgan orderlar bilan solishtiradi va ikkala kun izohiga «Қ» raqamlarini yozadi. |
| Fiskal kassa (NKM) ishlamayapti | Faqat soliq organida ro‘yxatdan o‘tgan maxsus kvitansiya daftari (maktabda bor, kassada saqlanadi); naqd to‘lovni tizimga kiritishda Direktor «Fiskal cheksiz (istisno)» belgisini qo‘yadi — jurnalda qoladi. Internet uzilganda NKM oflayn chek rejimida ishlaydi — kvitansiya daftari faqat apparat buzilganda. |
| Order xato yozildi | **Shu kuni:** hujjat qatorida «Bekor» (sababi bilan) — raqam saqlanadi, to‘g‘risi yangi raqam bilan yoziladi. **Kun yopilgan, tekshirilmagan:** Direktor «Qayta ochish» (faqat oxirgi kun). **Tekshirilgan kun:** o‘zgarmaydi — buxgalter tuzatish hujjati bilan. |
| Sanashda farq | Tizim shu kun sanasi bilan kamomad (chiqim) yoki ortiqcha (kirim) hujjatini o‘zi yozadi; dalolatnoma chop etiladi; kamomad bo‘yicha Direktor qarori («Qaror»): xodim hisobiga yoki zararga. Xodim hisobiga bo‘lsa — u pulni kassaga «+ Kirim» → «Kamomadni qoplash (xodim)» bilan qaytaradi (qarordagi summadan oshmaydi); qolgani nazorat ro‘yxatida («Xodimlar zimmasidagi kamomad») ko‘rinadi. |
| Xodim avans yoki maoshni kassaga qaytardi | «+ Kirim» → «Xodim qaytargan pul»: xodim, **qaysi oy**, statiya (avans — OP-08, maosh — OP-09). Avans qaytimi shu oy avansidan ayiriladi — oy vedomosti tasdiqlangan bo‘lsa qabul qilinmaydi (OP-09 bilan yoki Direktor oyni qayta ochadi); maosh qaytimi shu oy berilgan maoshni kamaytiradi (qayta berilishi mumkin). |
| O‘quvchi ketdi, oldindan to‘lagan puli (avansi) qaytariladi | Direktor: o‘quvchining «📋» → «↩ Avansni naqd qaytarish» (summa — joriy avansgacha, ariza sanasi, oluvchi F.I.Sh.); kassir «So‘rovlar» → «Pulni berish». Avans pul berilganda kamayadi; xarajat sifatida yozilmaydi. Naqdsiz qaytarish — hozircha yo‘q. |
| Kecha yopilmagan | Bugun hujjat yozilmaydi — avval kechagi kun sanab yopiladi (kechasi server ishlamagan bo‘lsa — «Қ» blankalari bilan, yuqoriga qarang). |
| Sahifada «sahifani yangilang» ogohlantirishi | Tizim yangilangan: Ctrl+Shift+R (telefonda — sahifani yopib qayta ochish). |

**Ma’lum va qabul qilingan cheklovlar (mustaqil ko‘rik, relizlar 11–12).** (1) Naqd pul naqdsiz yorliq bilan («bank», «terminal») yozilsa,
kassa uni ko‘rmaydi — bu bank ko‘chirmasi va onlayn kassa Z-hisoboti solishtiruvida aniqlanadi (RF-09 / F2.9). (2) Kassa ishga
tushgach eski «biriktirilmagan» naqd to‘lov yozuvi biriktirilmaydi va bo‘linmaydi (ilova bunday yozuvni yaratmaydi; bo‘lsa —
Direktor buxgalter bilan hal qiladi). (3) HR kartasidagi oylik maydonlari va stavka paneli yozayotganda raqam bo‘lmagan belgini o‘zi
olib tashlaydi (maydonda ko‘rinadi; naqd pul emas). (4) «↩ Fakturadan» va qaytarish so‘rovlarida faqat raqamlar o‘qiladi — summa
oyna va server chegarasidan oshmaydi. (5) Reliz 11 dan oldin buxgalter yoki moliya menejeri chop etgan «asl nusxa» asl nusxa bo‘lib
qoladi (endi ular doim «НУСХА» chop etadi). (6) Naqdsiz qaytarish to‘liq bajarilgach (yoki yangi summa qolgan to‘langan summadan
oshsa) o‘sha oynadan qayta yuborish «Qaytarib bo‘lmaydi: hozir … to‘langan» deb rad etiladi — «takror» yoki «boshqa ma’lumot bilan
yozilgan» xabari o‘rniga; ikkinchi qaytarish baribir yozilmaydi. (7) Vedomost tasdig‘iga o‘tish oyidan oldingi oy uchun Direktorning
o‘z maoshini naqd hech kim bermaydi (kassir — vedomostsiz oyda, Direktor — o‘ziga, FD-48): u karta orqali yoziladi. (8) Kunni yopishda
«Qayta kiritilgan …» deb navbatdan o‘chirilgan «Yuborilmadi» yozuvi avval smena topshirishda e’lon qilingan bo‘lsa, tizim uni baribir
«smena topshirishda e’lon qilingan, hali kelmagan» deb hisobga oladi — yuqoridagi «Internet uzildi» qatoridagi tartib (soxta kamomad
Direktor tomonidan «Hisobdan chiqarish» bilan yopiladi, ikkala kun izohida sababi yoziladi). **Egasi qabul qildi (2026-11-16);**
(2)-cheklov bo‘yicha tizimda eski «biriktirilmagan» naqd to‘lovlar yo‘qligi 30-dekabrgacha buxgalter bilan tekshiriladi.

## 9. Orqaga qaytish
**Ish jarayoni (tizimdan vaqtincha voz kechish).** Qaror — Direktor. (1) **To‘xtatishdan oldin:** to‘lov qabul qiladigan
qurilmalar navbati (⏳) bo‘shaguncha kutiladi; kutilayotgan smena topshirish qabul qilinadi yoki bekor qilinadi (qabul qilinmagan
topshirishda tizim kassani to‘xtatmaydi); joriy kassa kuni sanab yopiladi; tasdiq kutayotgan va tasdiqlangan (puli berilmagan)
kassa so‘rovlari bajariladi yoki bekor qilinadi — aks holda tizim kassani to‘xtatmaydi va to‘sqinlik qilayotgan kun yoki so‘rovlar
ro‘yxatini ko‘rsatadi. Tayyorlangan, hali boshlanmagan qayta ishga tushirishda sana bo‘shatilsa (kassa yana to‘xtatiladi) ham — xuddi
shu shartlar; shu payt qayta ishga tushirish kunining birinchi hujjati yozilayotgan bo‘lsa, tizim «Kassada hozir hujjat yozilmoqda»
deydi — bir oz kutib qayta saqlanadi (kun ochilgan bo‘lsa — avval u sanab yopiladi). Oxirgi kassa kuni **«Hali o‘tkazilmagan yozuvlar»** (qurilma navbati) bilan yopilgan va ularning kech kirim
orderi hali kelmagan bo‘lsa ham tizim to‘xtatmaydi: bu pul kassada bor, hisobda hali yo‘q — to‘xtatilgandan keyin u to‘g‘ri
yozilmaydi (qayta ishga tushgach kirim orderi uni komissiya sanashiga qo‘shimcha, ikkinchi marta hisoblardi). Direktor kunni qayta
ochadi, navbat o‘tgach (yozuvlar o‘sha kunga tushadi) kun qayta sanab yopiladi, keyin kassa to‘xtatiladi; kun tekshirilgan bo‘lsa —
navbat keyingi kassa kuniga «kech» tushadi, o‘sha kun yopilgach to‘xtatiladi. Oxirgi kun hali kiritilmagan **«Қ» blankalari**
(server ishlamagan kun, 8-bo‘lim) bilan yopilgan bo‘lsa — avval «Қ» yozuvlari kiritiladi (ular yangi kassa kuniga tushadi), o‘sha kun
yopiladi, keyin kassa to‘xtatiladi. (2) Kassa «Қ» blankalari va jurnali bilan
ishlaydi; blankalar **o‘z raqamlari** bilan (alohida daftar) — tizim raqamlari qayta ishga tushganda tizimdagi oxirgi raqamdan
uzluksiz davom etadi, qog‘oz raqamlari bilan aralashmaydi. (3) Excel kunlik varag‘i tizimdagi oxirgi kun oxiri qoldig‘idan qayta
boshlanadi. (4) Tizimda yozilgan hujjatlar haqiqiy bo‘lib qoladi — o‘chirilmaydi. (5) Oyni buxgalter birlashtiradi (tizim + qog‘oz).
(6) Qayta ishga tushirish — yangi komissiya sanashidan (pastda, «Texnik — qayta ishga tushirish»).

**Texnik — to‘xtatish.** (1) «⚙ Sozlamalar» → «Kassa ishga tushadigan kun» bo‘shatiladi yoki keyinga suriladi (faqat Direktor).
Saqlashdan oldin oyna oqibatlarini sanab tasdiq so‘raydi («KASSANI TO‘XTATISH»). Kassa ishlab turgan bo‘lsa (kassa kuni bor)
kassa **to‘xtatiladi**: sana bo‘sh saqlanadi (surilgan sana faqat hodisa jurnalida qoladi — qayta ishga tushirish baribir sanash
bilan), «💵 To‘lov», maosh, avans, xarajat va qaytarish oynalari avvalgi (ordersiz) tartibga qaytadi — faqat **to‘xtatilgan davr
sanasi** bilan (oxirgi kassa kunidan keyingi kunlar): oxirgi kassa kuni va undan oldingi sana bilan kassa hujjatisiz naqd yozuv hech
kimga kiritilmaydi (u kunlar kassa hujjatlari bilan yopilgan; tuzatish — qayta ishga tushgach, «Kassa» orqali). To‘xtatilgan kunning
o‘zida, kun yopilgandan keyin olingan pul ertasi kuni (o‘sha sana bilan) kiritiladi. Qurilma navbatidan kech kelgan, oxirgi kassa
kuni (yoki undan oldingi) sanali to‘lovni tizim qabul qilmaydi — uni **qayta ishga tushgach ham qayta yubormang** (pul kassada
sanalgan bo‘lsa, kirim orderi uni ikkinchi marta hisoblaydi va birinchi yopishda kassirga kamomad chiqadi). Navbat oynasida u
**«Yuborilmadi — Direktor hal qiladi»** bo‘lib turadi: «Hammasini qayta yuborish» uni yubormaydi, navbatdan faqat Direktor o‘chiradi.
Kun yopilgandan keyin olingan bo‘lsa — u to‘xtatilgan davr puli, navbatdan o‘chirilib ertangi sana bilan qayta kiritiladi (qayta
ishga tushirish sanashidan oldin); boshqasini Direktor buxgalter bilan hal qiladi. «Kassa» bo‘limi va yozilgan
hujjatlar joyida qoladi, yangi kassa hujjati yozilmaydi; «Kassa» sahifasida «Kassa to‘xtatilgan» ogohlantirishi turadi (ochiq
kun qolgan bo‘lsa — sahifa uni sanab yopishni so‘raydi, «Kunni yopish» ishlaydi). Kim,
qachon va qaysi sanadan to‘xtatgani hodisa jurnaliga yoziladi. Kassa to‘xtatilgan yoki qayta ishga tushirish kunini kutayotgan paytda
naqd (yoki usuli ko‘rsatilmagan) xarajat, maosh va avans yozuvi **sanasiz** kiritilmaydi va sanasi bo‘shatilmaydi (kassa ishlaganda ham
— sanasi bo‘shatilmaydi). To‘xtatilgan kassada oxirgi kassa kuni qayta ochilmaydi — tuzatish
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
   Dt 0000 Kt 5010; farq bo‘lmasa dalolatnoma yozilmaydi). Dalolatnoma «Qayta ishga tushirish» sarlavhasi bilan, komissiya a’zolari
   imzo qatorlari bilan chop etiladi. Kun ochilguncha qayta kiritish mumkin (avvalgi dalolatnoma bekor bo‘ladi).
   **Qayta ishga tushadigan kun — to‘xtatilgan davrdagi oxirgi kassa hujjatisiz naqd yozuvdan keyingi kun:** shu kun yoki keyingi
   sana bilan bunday yozuv bo‘lsa tizim qoldiqni qabul qilmaydi (bugun shunday yozuv bo‘lgan bo‘lsa — ertangi kun). **Sanashdan
   keyin, birinchi kassa kuni ochilguncha to‘xtatilgan davr sanasi bilan (oxirgi kassa kunidan keyingi kun) kassa hujjatisiz naqd
   yozuv kiritilsa** (navbatdan kech o‘tgan to‘lov, kech kelgan chek
   ham) — u sanashga kirmagan: tizim 3-qadamni qabul qilmaydi va birinchi qayta ochilgan kunni ochmaydi (bunday yozuvlar soni,
   kirimi va chiqimi ko‘rsatiladi; «Kassa» sahifasida qizil ogohlantirish) — aks holda farq birinchi yopishda kassirga kamomad yoki
   ortiqcha bo‘lib tushardi. Komissiya pulni qayta sanaydi va qoldiq qayta kiritiladi: o‘sha kun bilan — avvalgi dalolatnoma bekor
   bo‘ladi; qayta ishga tushirish kuni o‘tib ketgan bo‘lsa — avval «⚙ Sozlamalar»da ishga tushadigan kun bo‘shatiladi (kassa yana
   to‘xtatiladi), keyin qoldiq yangi kun bilan kiritiladi (qayta ishga tushadigan kun bugun bo‘lib, yozuv ham bugungi sana bilan
   bo‘lsa — ertangi kun bilan). **Qurilma navbati:** sanashdan **oldin** olingan to‘lov — kirim ordersiz (pul sanashga kirgan);
   sanashdan **keyin** olingan (kuni qayta ishga tushirish kunidan oldin) to‘lov qayta ishga tushirish kuni yoki undan keyin
   yuborilsa — kirim orderi bilan joriy kassa kuniga «kech» yoziladi (pul sanashga kirmagan, endi kassada); kassa hali kutayotgan
   paytda yuborilsa — yuqoridagidek qayta sanash kerak bo‘ladi. **Bir kechalik to‘xtatish** (qayta ishga tushirish kuni — oxirgi
   kassa kunining ertasi) to‘xtatilgan davr kunini qoldirmaydi: to‘xtatilgan kuni, kun yopilgandan keyin naqd harakat bo‘lgan bo‘lsa,
   qayta ishga tushirish kunini kamida bir kun keyin qo‘ying (u harakat oxirgi kassa kunining ertasi sanasi bilan kiritiladi).
3. «⚙ Sozlamalar» → «Kassa ishga tushadigan kun» = o‘sha kun (boshqa sana qabul qilinmaydi). Shu kuni birinchi kun boshi =
   sanalgan summa; hujjatlar raqami tizimdagi oxirgi raqamdan davom etadi. Shu kunni kutayotganda (ishga tushadigan kun hali
   qo‘yilmagan, kassa to‘xtatilgan bo‘lsa ham) qayta ishga tushirish kuni va keyingi sana bilan kassa hujjatisiz naqd yozuv
   kiritilmaydi — u yangi kassa davrining harakati («Kassa» orqali). Ishga tushadigan kun qo‘yilmay, qayta ishga tushirish kuni
   o‘tib ketsa — eski tartib davom etadi, lekin o‘sha kun va keyingi sana bilan kassa hujjatisiz naqd yozuv bo‘lsa, tizim kassani
   o‘sha kundan ishga tushirmaydi: komissiya qayta sanaydi va qoldiq ulardan keyingi kun bilan kiritiladi.
4. Buxgalter: nazorat ro‘yxatida **«Kassani to‘xtatish va qayta ishga tushirish»** qatori — har qayta ishga tushirish bo‘yicha
   farq va to‘xtatilgan davrda (sanasi oxirgi kassa kunidan keyin) kassa hujjatisiz yozilgan naqd kirim va chiqim; ularni «Қ» jurnali
   va «Д-» dalolatnoma bilan solishtiradi. To‘xtatilgan davrda orqa sana bilan (oxirgi kassa kuni yoki undan oldingi sana) kiritilgan
   yozuvlar alohida ko‘rsatiladi (endi tizim bunday yozuvni qabul qilmaydi — qator himoya uchun qoladi);
   farq shu harakatlar bilan tushuntirilmasa — «izohlanmagan farq» (sariq): bu kamomad yoki ortiqcha, «Қ» jurnali bilan tekshiriladi.
   «Moslik» qatori kassa ishlagan **barcha** davrlarni tekshiradi (birinchi ishga tushgan kundan, to‘xtatilgan davrlarsiz; kassa
   to‘xtatilgan bo‘lsa — oxirgi kassa kunigacha): oldingi davrdagi orderisiz naqd yozuv to‘xtatish va qayta ishga tushirishdan keyin
   ham ko‘rinib turadi. «Kassa ishga tushishidan oldingi naqd yozuvlar» qatori — sanasi kassa birinchi ishga tushgan kundan oldin.
   KO-3 jurnali va «Statiyalar»da farq «Qayta ishga tushirish farqi» qatorida alohida ko‘rsatiladi
   (kun boshi + kirim − chiqim + farq = kun oxiri). Kassa keyin yana to‘xtatilishi va qayta ishga tushirilishi mumkin — har gal
   shu tartibda, o‘z sanashi va dalolatnomasi bilan.

## 10. Qo‘llab-quvvatlash (birinchi 2 hafta)
Texnik navbatchi (kassa ish soatlarida) — server huquqi bor shaxs: egasi yoki u tayinlagan administrator (egasi qarori, 2026-11-16).
Har kuni kassa yopilgach 15 daqiqalik qo‘ng‘iroq (kassir, moliya menejeri, navbatchi). Muhimlik: ishni
to‘xtatadigan xato — o‘sha kuni (tuzalmasa — «Қ» blankalari); noqulaylik — 2 ish kuni; istak — keyingi yangilanish. Har hafta (dushanba) —
nazorat ro‘yxati, «Kassa» → «KPI» (haftalik ko‘rsatkichlar; dushanba kungi Telegram hisobotida ham), `kassa-checks.sql` va
`verify-db.sh` natijasi ko‘rib chiqiladi (ikkalasi faqat o‘qiydi).
