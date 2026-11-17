# «Kassa» bo‘limi: shakllar ro‘yxati va qog‘oz shablonlari (F1.19)

**Holat:** namuna. Qog‘oz shakllarni maktab buxgalteri tekshiradi va 4-buyruq («Birlamchi hujjatlarning o‘z shakllarini
tasdiqlash», `docs/moliya/buyruq-namunalari.md`) bilan tasdiqlaydi. Ism, lavozim, rekvizit va summalar bu yerda yozilmaydi
(repozitoriy ommaviy) — `[___]` o‘rniga qog‘ozda to‘ldiriladi. Shakllar hujjatlar tilida (o‘zbek kirill yoki rus) ko‘chirib
chop etilishi mumkin — mazmuni o‘zgarmasin.

## A. Tizim chop etadigan shakllar (qo‘lda to‘ldirilmaydi)
| Shakl | Qachon | Nusxa | Kim imzolaydi | Qayerda saqlanadi |
|---|---|---|---|---|
| **Kirim orderi (KO-1) + patta** | har naqd kirimda («💵 To‘lov», «+ Kirim») | 1 (order va uzib olinadigan patta) | bosh buxgalter (2-ro‘yxat), kassir | order — kassa hujjatlari jildida; patta — pul topshirgan shaxsda |
| **Chiqim orderi (KO-2)** | pul berilganda («Pulni berish», naqd maosh) | 1 | rahbar, bosh buxgalter, kassir; oluvchi — «Oldim», summa so‘z bilan, sana, imzo, shaxsni tasdiqlovchi hujjat | kassa hujjatlari jildida, ilovalari bilan |
| **Kassa kitobi varag‘i (KO-4)** | kun yopilganda | 2 (kassa kitobi varag‘i va «Kassir hisoboti») | kassir; tekshirgan buxgalter / moliya menejeri | 1-nusxa — kassa kitobi (yil oxirida tikiladi); 2-nusxa — orderlar bilan buxgalterga |
| **Kassani sanash dalolatnomasi** | har sanashda chop etish mumkin («Sanashlar» → «🖨 Dalolatnoma»): kun yopilishi (farq bo‘lsa — albatta), smena topshirish-qabul (qabul qiluvchi o‘z hisobidan «Qabul qildim» degandan keyin — tizim darhol chop etishni taklif qiladi; qabul qilinmagan yoki bekor qilingan topshirishda dalolatnoma yo‘q), komissiya sanashi | 2 | kassir (kassa egasi), komissiya a’zolari; smenada — topshirgan va qabul qilgan (ismlar tizimda sanash paytidagidek); pulni kassa egasi o‘rniga boshqa xodim sanagan bo‘lsa — u ham («Санади» qatori). Sanash vaqti, qaysi kassa kuni uchun ekani va smenada «qabul qilindi» vaqti yoziladi | kassa hujjatlari jildida |
| **Naqdsiz dalolatnoma** (boshlang‘ich qoldiq; qayta ishga tushirish; kamomad bo‘yicha qaror; o‘zaro hisob) | Direktor amali bilan | 2 | rahbar, bosh buxgalter; kamomad xodim zimmasiga qo‘yilganda (4730) — javobgar shaxs («Танишдим, розиман» qatori), qaror so‘z bilan; boshlang‘ich qoldiq / qayta ishga tushirishda — sanagan komissiya a’zolari (tizimga kiritilgan tarkib bo‘yicha); o‘zaro hisobda — xodim | buxgalteriyada |
| **Kunlik hisobot** | kun yopilgach (ichki hisobot) | 1 | — | moliya menejerida |

Belgilar: raqamli hujjat (order, KO-4 varag‘i, «Д-», «ЎҲ-», «А-» dalolatnomalari) qayta chop etilganda — «НУСХА» (kassani sanash
dalolatnomasi raqamli hujjat emas — chop etish jurnaliga yozilmaydi, qayta chop etilgani belgisiz; imzolangani jildda); kun qayta ochilib yopilgan bo‘lsa — «АЛМАШТИРИЛДИ» (avvalgi varaq bekor qilinib
saqlanadi); bekor qilingan hujjatda — «БЕКОР ҚИЛИНГАН»; yopilmagan kun varag‘ida — «ҚОРАЛАМА»; sinov kassasida — «СИНОВ».
Bekor qilingan order yirtib tashlanmaydi — jildda o‘z raqami o‘rnida saqlanadi.
Asl nusxani (order, KO-4 varag‘i) faqat kassir yoki Direktor chop etadi; boshqa rollar (buxgalter, moliya menejeri) chop etganda doim
«НУСХА» chiqadi va asl nusxa hali chop etilmagan hisoblanadi. «Chop etdi» qatorida — xodim kartasidagi ism (login / e-mail emas).
Rahbar va bosh buxgalter imzo qatori: «⚙ Sozlamalar»dagi ro‘yxatda shu lavozimda bitta faol shaxs bo‘lsa — uning F.I.Sh.; bir nechta
bo‘lsa — hujjatni tasdiqlagan foydalanuvchi, agar hisobi ulardan biriga bog‘langan bo‘lsa; aks holda bo‘sh (qo‘lda yoziladi).
Qayta ishga tushirish dalolatnomasi o‘z sarlavhasi bilan chiqadi (boshlang‘ich qoldiq dalolatnomasidan farqli).
«Hali o‘tkazilmagan yozuvlar» (kunni yopish dalolatnomasi, KO-4 «Kassir hisoboti», kunlik hisobot) ikki qismga ajratib yoziladi:
qurilma navbatidagi yozuvlar va server ishlamagan paytdagi «Қ» blankalari (soni, summasi, raqamlari).

## B. Qog‘oz shakllar (shablonlar quyida)
| № | Shakl | Qachon | Kim to‘ldiradi |
|---|---|---|---|
| Sh-1 | Avans hisoboti | hisobdor pul sarflaganda (3 ish kuni ichida) | hisobdor shaxs; tekshiradi — buxgalter; tasdiqlaydi — rahbar |
| Sh-2 | «Қ» blankasi va jurnali | tizim (server) ishlamay qolganda; kassa to‘xtatilganda (`ishga-tushirish.md`, 9-bo‘lim) | kassir |
| Sh-3 | Kassani sanash dalolatnomasi (boshlang‘ich qoldiq) | 30-dekabr kechqurun (tizim ishga tushmasidan oldin; 31-dekabrda istisno naqd harakat bo‘lsa — 4-yanvar ertalab qayta sanashda yana); to‘xtatilgan kassani qayta ishga tushirishda | inventarizatsiya komissiyasi |
| Sh-4 | Qog‘oz order daftarlarini yopish dalolatnomasi | 30-dekabr kechqurun (31-dekabrda istisno amal bo‘lsa — o‘sha amaldan keyin qayta tuziladi) | kassir, buxgalter |
| Sh-5 | Qabul sinovi varag‘i | sinov stendida, ishga tushirishdan oldin (26-dekabrgacha imzolanadi) | har rol |
| Sh-6 | Parallel yuritish kunlik nazorat varag‘i | birinchi 5 ish kuni | moliya menejeri |
| Sh-7 | Hisobdor shaxs qoldig‘i ma’lumotnomasi | 31-dekabr holatiga (nol qoldiq: pul 30-dekabrgacha yopiladi) | hisobdor shaxs, buxgalter |
| Sh-8 | Hisob siyosati va kassa tartibi — buxgalter tasdiq varag‘i | 21-noyabr — vaqtincha ko‘rik; 12-dekabr — imzo; B19 — 19-dekabr | bosh buxgalter; direktor |

---

## Sh-1. Avans hisoboti

Qog‘ozdagi hisobot (cheklar bilan) — birlamchi hujjat. Tekshirilgach u tizimga «Kassa» → «Avans hisoboti» bilan kiritiladi: har chek —
bitta qator, xarajat «Buxgalteriya»ga o‘zi ko‘chadi, hisobdordagi qoldiq kamayadi. Tizim chop etgan dalolatnoma (tasdiqlovchi imzolar
bilan) shu qog‘oz hisobotga qo‘shib saqlanadi. Hisobdor shaxs buxgalter yoki moliya menejerining o‘zi bo‘lsa — hisobotni u tekshirmaydi
va tizimga kiritmaydi: boshqa 2-ro‘yxat xodimi yoki Direktor (tizim ham rad etadi).

«[Tashkilot nomi]» · Avans hisoboti № [___] · [sana]
«TASDIQLAYMAN»: rahbar [___] (imzo) · summa: [___] so‘m

Hisobdor shaxs: [F.I.Sh., lavozimi] · Avansning maqsadi: [___]

| Ko‘rsatkich | Summa |
|---|---|
| Oldingi avansdan qoldiq / ortiqcha sarf | [___] |
| Kassadan olindi: chiqim orderi № [___], sana [___] | [___] |
| **Jami olingan** | [___] |
| **Sarflandi** (jadval bo‘yicha) | [___] |
| Qoldiq kassaga qaytarildi: kirim orderi № [___], sana [___] | [___] |
| Ortiqcha sarf (to‘lanishi kerak) | [___] |

| № | Sana | Hujjat (chek / hisob-faktura) № | Kimdan olingan (sotuvchi) | Nima uchun | Summa | Statiya (buxgalter to‘ldiradi) |
|---|---|---|---|---|---|---|
| 1 | | | | | | |
| 2 | | | | | | |
| … | | | | | | |
| | | | | **Jami** | | |

Ilova: [___] ta hujjat, [___] varaq.
Hisobdor shaxs: [___] (imzo), sana [___] · Hisobotni tekshirdi — buxgalter: [___] (imzo), sana [___]
Tasdiqlangan summa: [___] so‘m ([summa so‘z bilan]).

*Qoidalar:* muddat — 3 ish kuni (tizim shanba, yakshanba va «Bayram / ta’til kunlari»ni sanamaydi; korporativ karta bo‘yicha — 10); har xarajat alohida qator va hujjat bilan; statiya — kassa xarajati
(EX), asosiy vosita (OP-18) yoki sotish uchun tovar (OP-24), yetkazib beruvchiga qarz (OP-17) avans hisobotida yopilmaydi; cheksiz xarajat qabul
qilinmaydi (istisno — rahbar ruxsati bilan tushuntirish xati); hisobot topshirilmaguncha yangi avans berilmaydi (istisno — Direktor
tasdig‘i, tizim uni o‘zi talab qiladi); tekshirilgan hisobotni buxgalter (yoki moliya menejeri) **«Kassa» → «Avans hisoboti»** bilan
kiritadi — xarajatlar «Buxgalteriya»ga o‘zi ko‘chadi (usul «hisobdor orqali»), hisobdordagi qoldiq kamayadi; «Buxgalteriya»ga qo‘lda
(bank / karta yoki boshqa usul bilan) **kiritilmaydi** — xarajat ikki marta yozilib, hisobdor qoldig‘i kamaymay qolardi; yanvar
hisobotlari — yanvar yopilishidan oldin.

## Sh-2. «Қ» blankasi (ichki vaqtinchalik kvitansiya) va jurnali
Faqat tizim (server) ishlamay qolganda. **To‘lovchiga berilmaydi** — to‘lovchi fiskal chek oladi. Blankalarni buxgalter oldindan
chop etib raqamlaydi (Қ-0001 …; 30-dekabrdagi sanashgacha), ular kassada saqlanadi; buzilgani bekor qilinib saqlanadi. Tizim tiklangach har blanka tizimga kiritiladi (izohda — «Қ» raqami) va jurnalda
order raqami yoziladi. Server ishlamagan kun hali yopilmagan bo‘lsa — avval o‘sha kun yopiladi: kiritilmagan blankalar soni, summasi
va raqamlari «Kunni yopish» oynasidagi «Server ishlamagan paytdagi «Қ» blankalari»ga yoziladi, keyin blankalar kiritiladi
(`ishga-tushirish.md`, 8-bo‘lim).
Kassa **to‘xtatilganda** ham (orqaga qaytish, `ishga-tushirish.md`, 9-bo‘lim) shu blankalar ishlatiladi: raqamlari o‘z daftari bo‘yicha —
tizimning kirim / chiqim order raqamlari bilan aralashmaydi (qayta ishga tushganda tizim o‘z oxirgi raqamidan davom etadi); bu davrda
tizimga kiritilgan yozuvlar kassa orderisiz bo‘ladi — «Order №» ustuni bo‘sh qoladi; tizimdagi sanasi — oxirgi kassa kunidan keyingi
kun (oxirgi kassa kuni va undan oldingi sana bilan tizim qabul qilmaydi).

**Blanka:**
«Қ» № [___] · sana [___], vaqt [___]
☐ Kirim ☐ Chiqim · Kimdan / kimga: [F.I.Sh.] · O‘quvchi (o‘quv to‘lovi bo‘lsa): [F.I.Sh., sinfi yoki ID]
Summa: [raqam bilan] so‘m ([so‘z bilan]) · Asos: [___] · Fiskal chek №: [___]
Kassir: [___] (imzo) · Chiqimda — oluvchi: [___] (imzo)
Tizimga kiritildi: sana [___], order № [___], kiritgan: [___]

**Jurnal:**
| «Қ» № | Sana, vaqt | Kirim / chiqim | Kimdan / kimga | Summa | Fiskal chek № | Tizimga kiritilgan sana | Order № | Imzo |
|---|---|---|---|---|---|---|---|---|
| | | | | | | | | |

Kun oxirida kassir: jurnal bo‘yicha jami kirim [___], chiqim [___]; sanalgan pul [___]; imzo. 48 soatdan ortiq kechikkan
yozuvni tizimga Direktor kiritadi.

## Sh-3. Kassani sanash dalolatnomasi (boshlang‘ich qoldiq uchun)

«[Tashkilot nomi]» · Kassadagi pul mablag‘larini inventarizatsiya qilish dalolatnomasi № [___]
[joy], [sana], [vaqt] · Asos: [sana]dagi № [___] buyruq
Komissiya: rais — direktor [F.I.Sh.]; a’zolar — bosh buxgalter [F.I.Sh.], moliya menejeri [F.I.Sh.]; moddiy javobgar shaxs (komissiya
a’zosi emas, sanashda qatnashadi) — kassir (G‘aznachi lavozimi) [F.I.Sh.]

**Kassirning tilxati:** inventarizatsiya boshlanishiga qadar barcha kirim va chiqim hujjatlari buxgalteriyaga topshirildi, menga
ishonib topshirilgan barcha pul kirim qilindi, chiqib ketgani hisobdan chiqarildi. Kassir: [___] (imzo)

| Nominal | Soni | Summa |
|---|---|---|
| 200 000 | | |
| 100 000 | | |
| 50 000 | | |
| 20 000 | | |
| 10 000 | | |
| 5 000 | | |
| 2 000 | | |
| 1 000 | | |
| tangalar | | |
| **Jami naqd pul** | | |

Haqiqatda mavjud: [raqam bilan] so‘m ([so‘z bilan]) · Hisob ma’lumoti bo‘yicha (kunlik varaq qoldig‘i): [___] so‘m
Natija: ☐ farq yo‘q ☐ ortiqcha [___] so‘m ☐ kamomad [___] so‘m
Oxirgi order raqamlari: kirim № [___], chiqim № [___]
Farq sababi bo‘yicha kassirning tushuntirishi: [___]
Rahbar qarori: [___] (imzo, sana)
Komissiya raisi: [___] · A’zolar: [___], [___] · Kassir: [___] (imzolar)

*Eslatma:* shu dalolatnomadagi «haqiqatda mavjud» summa tizimga boshlang‘ich qoldiq sifatida kiritiladi (30-dekabr kechqurun;
31-dekabrda istisno naqd harakat bo‘lsa — 4-yanvar ertalab, birinchi kassa kuni ochilishidan oldin yangi dalolatnoma bilan qayta
sanalib, qayta kiritiladi). Tizim ishga tushgach
sanash dalolatnomalarini (kun yopilishi, smena, oy oxiri) tizimning o‘zi chop etadi. **Qayta ishga tushirishda** (`ishga-tushirish.md`,
9-bo‘lim) ham shu shakl: «hisob ma’lumoti» — tizimdagi oxirgi kun oxiri qoldig‘i va to‘xtatilgan davrdagi «Қ» jurnali jamlari;
«haqiqatda mavjud» summa «Kassa» → «Qayta ishga tushirish»ga kiritiladi, tizimdagi qoldiq bilan farqi texnik «Д-» dalolatnoma
bilan yoziladi (kamomad / ortiqcha emas).

## Sh-4. Qog‘oz order daftarlarini yopish dalolatnomasi

«[Tashkilot nomi]» · Dalolatnoma № [___] · [joy], [sana]
Biz, quyida imzo chekuvchilar — [lavozim, F.I.Sh.], [lavozim, F.I.Sh.], kassir [F.I.Sh.] — shuni tasdiqlaymizki, [sana] holatiga:
1. Qog‘ozda yuritilgan kirim orderlari daftari **№ [___] raqamli order bilan yopildi**; [yil] davomida № [___] dan № [___] gacha
   orderlar yozilgan, shundan bekor qilingani — [___] ta (raqamlari: [___]).
2. Chiqim orderlari daftari **№ [___] raqamli order bilan yopildi**; № [___] dan № [___] gacha, bekor qilingani — [___] ta ([___]).
3. Ishlatilmagan blankalar: kirim — [___] ta (№ [___]–[___]), chiqim — [___] ta (№ [___]–[___]) — bekor qilindi (chizib tashlandi).
4. Kunlik kassa varaqlari (Excel) [sana] kuni oxiridagi qoldiq [___] so‘m bilan yopildi; bu qoldiq Sh-3 dalolatnomasi bilan solishtirildi.
5. [sana]dan boshlab kassa hujjatlari faqat axborot tizimining «Kassa» bo‘limida rasmiylashtiriladi; raqamlash 1 dan boshlanadi.
6. Yopilgan daftarlar va varaqlar arxivga topshirildi; saqlash muddati — kamida 5 yil.
Imzolar: [___], [___], kassir [___] · Bosh buxgalter: [___]

## Sh-5. Qabul sinovi varag‘i (sinov stendida)
Rol: [kassir (G‘aznachi lavozimi; «Kassir» roli) / o‘rinbosar (qo‘shimcha «Kassir» roli — sarlavhada «Rol: … ▾» bo‘lsa, undan tanlab) /
moliya menejeri / buxgalter / direktor / HR] · F.I.Sh.: [___] · Sana: [___] · Qurilma: ☐ kompyuter ☐ telefon

| № | Ssenariy | Bajarildi | Izoh |
|---|---|---|---|
| 1 | Naqd o‘quv to‘lovi: fiskal chek № bilan; kirim orderi va patta chop etildi | ☐ | |
| 2 | Ortiqcha to‘lov (avansga) va kelgusi oy uchun to‘lov — taqsimot to‘g‘ri | ☐ | |
| 3 | Boshqa kirim («Bankdan naqd», «Hisobdordan qaytim» — qoldiqdan katta summa rad etildi; «Boshqa kirim» o‘quvchi / boshqa shaxsdan — fiskal chek №siz qabul qilinmadi, kontragentdan — chek so‘ralmadi) | ☐ | |
| 3a | «Xodim qaytargan pul»: oy tanlandi, oynada avans qoldig‘i / berilgan maosh ko‘rindi; avans qaytimidan keyin vedomostda avans kamaydi | ☐ | |
| 3b | «Kamomadni qoplash (xodim)»: xodim zimmasidagi kamomaddan qabul qilindi, nazorat ro‘yxatida qoldiq kamaydi | ☐ | |
| 4 | Chiqim so‘rovi → tasdiq → pul berish; chiqim orderi chop etildi | ☐ | |
| 5 | T1 dan katta chiqim — Direktor tasdig‘isiz berilmadi; asos hujjati bilan «boshqa» tomonga (tashkilot) xarajatda sariq ogohlantirish chiqdi | ☐ | |
| 6 | Xato orderni shu kuni bekor qilish | ☐ | |
| 7 | Naqd maosh (tasdiqlangan vedomost chegarasida); ish haqi avansi | ☐ | |
| 8 | Qaytarish: Direktor tasdig‘i → kassir pulni berdi | ☐ | |
| 8a | Qaytarish oynasi: javob kelmagach summa yoki «avans ham» o‘zgartirilib qayta yuborildi — rad etildi, birinchi yozilgani ko‘rsatildi; birinchi yuborishdan keyin usul o‘zgarmadi | ☐ | |
| 9 | Smena topshirish ikki bosqichda: topshiruvchi yozdi — qabul qilinguncha kassada hujjat yozilmadi; qabul qiluvchi o‘z hisobidan «Qabul qildim» (yoki «Rad etish») — dalolatnomada ikkala ism; kassa egasi o‘rniga topshirish komissiyasiz rad etildi | ☐ | |
| 10 | Kunni farq bilan yopish; KO-4 (2 nusxa), sanash dalolatnomasi, kunlik hisobot | ☐ | |
| 11 | Kunni tekshirish («Tekshirdim»); kamomad bo‘yicha qaror | ☐ | |
| 12 | Nazorat ro‘yxati va Telegram hisobotidagi kassa qatori tushunarli | ☐ | |
| 13 | Davr surati va davrni yopish; yopilgan sanaga yozuv rad etildi | ☐ | |
| 14 | Internet uzilganda to‘lov navbatga tushdi, keyin o‘zi o‘tdi | ☐ | |
| 14a | Navbatda to‘lov turganida kun yopildi: u oynada «hali o‘tkazilmagan» bo‘lib hisobga olindi (farq yo‘q); keyingi kuni «kech» bo‘lib o‘tdi | ☐ | |
| 14b | Server ishlamagan kun ertasi kuni «Қ» blankalari bilan yopildi (farq yo‘q); «Қ» yozuvlari kiritildi; kun izoh bilan tekshirildi | ☐ | |
| 14c | Smena navbatdagi yozuv bilan topshirildi; qabul qiluvchi kunni boshqa qurilmadan yopdi — oynada «Smena topshirishda e’lon qilingan, hali kelmagan» qatori, farq yo‘q; yozuv keyingi kuni «kech» kelib bog‘landi | ☐ | |
| 14d | «💵 To‘lov» rad etildi (fiskal chek № takror), o‘sha oynada tuzatilib qayta kiritildi — navbatda rad etilgan yozuv qolmadi; boshqa «Yuborilmadi» yozuvi yopish oynasida alohida, tanlov bilan («Pul kassada» / «Qayta kiritilgan …»), farq tanlovga mos; sinov kassasi yopilganda navbat ko‘rinmadi | ☐ | |
| 15 | Buxgalter: «To‘lovlar» va «Buxgalteriya» — oy ma’lumoti ko‘rinadi, yozish tugmalari yo‘q, telefon va to‘lovchi matni ko‘rinmaydi | ☐ | |
| 16 | Buxgalter: oylik vedomost (holati, qatorlar) — faqat ko‘rish; A4 oylik hisobot — ismsiz (o‘quvchi va xodim ID bilan) | ☐ | |

Har rol o‘ziga tegishli qatorlarni bajaradi (qolganlariga «—»). Xulosa: ☐ qabul qilaman ☐ quyidagi tuzatishlardan keyin: [___]
Imzo: [___]

## Sh-6. Parallel yuritish: kunlik nazorat varag‘i
Sana: [___] · To‘ldirdi (moliya menejeri): [___]

| № | Tekshiruv | Ha / yo‘q | Farq va sababi |
|---|---|---|---|
| 1 | Kassada sanalgan pul = tizimdagi kun oxiri qoldig‘i | | |
| 2 | Har kirim va chiqim orderining qog‘oz manbasi bor (chek, ariza, hisob-faktura, vedomost) | | |
| 3 | Oflayn navbat bo‘sh; «Қ» jurnalidagi har yozuv tizimga kiritilgan | | |
| 4 | Click / Uzum kabinetidagi kunlik summa = kunlik hisobotdagi «kanallar» bloki | | |
| 5 | Bankka topshirilgan / bankdan olingan pul = bank hujjati | | |
| 6 | Order raqamlari uzluksiz; bekor qilinganlarning sababi yozilgan | | |
| 7 | Direktorga kelgan Telegram hisoboti = kunlik hisobot | | |
| 8 | Nazorat ro‘yxati: «Moslik» — «hammasi mos»; qizil qator yo‘q | | |
| 9 | Kun tekshirildi («Tekshirdim»), KO-4 imzolandi | | |

Ketma-ket 3 ish kuni hammasi «ha» va tushuntirilmagan farq yo‘q bo‘lsa — parallel yuritish tugaydi (Direktor qarori: [___], sana [___]).

## Sh-7. Hisobdor shaxs qoldig‘i ma’lumotnomasi
«[Tashkilot nomi]» · [sana] holatiga (yil yakunida — 31-dekabr holatiga)
Men, [lavozim, F.I.Sh.], shuni tasdiqlaymanki, menda hisobdorlik asosida olingan va hali hisobot berilmagan pul qoldig‘i
[raqam bilan] so‘m ([so‘z bilan]); shundan hujjatlari bor, hali hisobotga kiritilmagan xarajatlar — [___] so‘m, naqd qoldiq — [___] so‘m.
Hisobdor shaxs: [___] (imzo) · Buxgalter: [___] (imzo)
*Yil yakunida qoldiq **nol** bo‘lishi shart: eski pul 30-dekabrgacha (kassa naqd ishlaydigan oxirgi kun) cheklar bilan hisobot yoki
qaytim orqali to‘liq yopiladi. Yangi tizim eski pulni ko‘rmaydi — yanvarda u bo‘yicha na avans hisoboti, na qaytim qabul qilinadi
(egasi qarori, 2026-11-16).*

## Sh-8. Hisob siyosati va kassa tartibi — buxgalter tasdiq varag‘i
«[Tashkilot nomi]» · Bosh buxgalter tasdig‘i uchun · Asos: ish reja (`buxgalteriya-ish-reja.md`, §4.2–4.6, §6), G2 darvozasi

Har band bo‘yicha: «Tizimda hozir» — tavsiya (egasi 2026-11-10 da vaqtincha qabul qilgan, dastur shu bo‘yicha qurilgan). Rozi
bo‘lsangiz — «Roziman» ustuniga ☑; boshqacha bo‘lsa — «Tuzatish» ustuniga o‘z tanlovingizni yozing. Hisobvaraqlar, statiyalar va
operatsiyalarni ekranda o‘zgartirib bo‘lmaydi — tuzatish yashirin o‘rnatishgacha (≈ 21-dekabr) dasturchiga yetib borishi kerak.
**Muddatlar:** 21-noyabr — kassa qismi (B1–B13), buyruq namunalari va qog‘oz shakllar bo‘yicha vaqtincha ko‘rik; **12-dekabr** — varaq
imzolanadi; B19 — 19-dekabr. Imzo bo‘lmasa, boshlanish 1-fevralga suriladi (G2). Ism va summalar bu varaqqa yozilmaydi (summalar —
buyruq va «⚙ Sozlamalar»da); hisob siyosati to‘plami repozitoriyga kiritilmaydi.

| № | Nima qaror qilinadi | Tizimda hozir (tavsiya) | Muddat | Roziman | Tuzatish (yozing) |
|---|---|---|---|---|---|
| B1 | Kassa qismi (hisobvaraqlar, statiyalar, operatsiyalar), buyruq namunalari, qog‘oz shakllar (Sh-1…Sh-7); ish rejimi; buxgalteriya dasturi | Ish rejimi A: tizim kassa hujjatlari va boshqaruv hisobini yuritadi, rasmiy registrlar buxgalter dasturida qoladi (FD-03); oylik Excel to‘plam buxgalter dasturiga moslanadi — dastur nomi: [___] | 21.11 vaqtincha / 12.12 | ☐ | |
| B2 | Kassa kitobi (KO-4) tarkibi | Faqat naqd pul (5010); naqdsiz to‘lov va o‘zaro hisob — varaqda faqat ma’lumot blokida (FD-04) | 21.11 / 12.12 | ☐ | |
| B3 | Hujjatlarni raqamlash | KO-1 va KO-2 alohida; har yili 1-yanvardan 1 dan, uzilishsiz, raqamni server beradi; KO-4 varaqlari ham 1 dan; dalolatnoma, o‘zaro hisob va avans hisobotining o‘z raqamlari (FD-05) | 21.11 / 12.12 | ☐ | |
| B4 | Chop etish ko‘rinishi | O‘zbek kirill (rus va lotin ham bor; tilni Direktor «⚙ Sozlamalar»da tanlaydi); summa «1 234 567=89»; KO-4 ikki nusxa; pul harakati bo‘lmagan kunga varaq chiqmaydi (FD-07) | 21.11 / 12.12 | ☐ | |
| B5 | Hujjatdagi hisobvaraqlar | BHMS 21 to‘rt xonali kodlari + analitika (eski «40.11» o‘rniga 4010 + to‘lovchi turi); kassa qismidagi hisobvaraqlar ro‘yxati — ish reja §4.2 (FD-09) | 21.11 / 12.12 | ☐ | |
| B6 | Statiyalar katalogi | 75 statiya (IN 7, EX 44, OP 24) va eski toifalarni moslash jadvali (§4.4); «Boshqa xarajatlar» ulushi 2 % dan oshmaydi; eski «IT-PARK» → EX-33 «Dasturiy ta’minot, xosting, ERI» (FD-10) | 21.11 / 12.12 | ☐ | |
| B7 | Kassa operatsiyalari (Dt / Kt) | Ish reja §4.5: kassadan soliq to‘lanmaydi; so‘mdagi qarzni kassadan qaytarish mumkin; rahbar va ta’sischiga beriladigan pul — alohida operatsiya; ro‘yxatda yo‘q operatsiya kassadan o‘tmaydi (FD-11) | 21.11 / 12.12 | ☐ | |
| B8 | Naqd o‘quv to‘lovi kirim orderida | Boshlangan oy uchun — 4010; ortiqcha va kelgusi oy uchun — 6310 (avans); avansdan yopilgan qism — naqdsiz yozuv 6310 → 4010 (FD-12) | 21.11 / 12.12 | ☐ | |
| B9 | Bankka topshirilgan va bankdan olingan naqd pul | Topshirish — «yo‘ldagi pul» (5710) orqali; olish — Dt 5010 Kt 5110; bank komissiyasi — bank tomonida (FD-13) | 21.11 / 12.12 | ☐ | |
| B10 | Xarid puli (hisobdor) | 4230; avans hisoboti 3 ish kuni ichida (korporativ karta — 10 kun), maktab ish kunlari bo‘yicha (shanba, yakshanba va «Bayram / ta’til kunlari» sanalmaydi); xodimga — faqat «Hisobdorga avans»; hujjatsiz xarid chegarasi L1 = 0 (egasi qarori) (FD-14) | 21.11 / 12.12 | ☐ | |
| B11 | Xato kassa hujjati | Faqat o‘sha kuni bekor qilinadi; oxirgi tekshirilmagan kunni faqat Direktor qayta ochadi; boshqa hollarda — teskari yozuv (storno), tahrirlash yo‘q (FD-20). Tekshirilgan kun uchun storno hujjatini buxgalter yozadi — bu huquqni berish egasining qarori (tizimda 2-bosqichdan) | 21.11 / 12.12 | ☐ | |
| B12 | Kechki sanashdagi farq | Ruxsat etilgan farqsiz; o‘sha kuni hujjat: kamomad — 5910, ortiqcha — 9390; kamomad bo‘yicha Direktor qarori: xodimdan undirish (4730 — yozma rozilik yoki moddiy javobgarlik shartnomasi bilan) yoki xarajatga (9430) (FD-21) | 21.11 / 12.12 | ☐ | |
| B13 | Rahbar yoki ta’sischiga kassadan pul | Xarajat emas — qarz: xodim — 4290, ta’sischi — 4890; o‘sha oy ichida tasniflanadi (dividend, ish haqi yoki hisobdan chiqarish); har doim Direktor tasdig‘i; iloji boricha bank orqali (FD-26) | 21.11 / 12.12 | ☐ | |
| B14 | Kassadan olingan oziq-ovqat | 1010 (materiallar) + oy oxirida chiqim dalolatnomasi + har chorakda inventarizatsiya; oziq-ovqat statiyasi tizimda hozir 1010 ga bog‘langan — yanvar orderlariga shu yoziladi; variant — darhol xarajat; oshxona idishlari va kitoblar — 1080 + 014 (FD-31) | 12.12 | ☐ | |
| B15 | Ota-onaga naqd qaytarish puli manbai | Tavsiya yo‘q — buxgalter tanlaydi. Qolgan tartib belgilangan: Direktor tasdiqlaydi va usulni tanlaydi, kassir chiqim orderi bilan beradi; 1 bank kunidan ko‘p kechiksa ogohlantirish (FD-25) | 12.12 | — | ☐ kassadagi tushumdan ☐ avval bankdan olinadi |
| B16 | Imzo tartibi; kirim orderi (KO-1) va pattadagi «Bosh buxgalter» qatori | 1-ro‘yxat — Direktor va buyruq bilan tayinlangan o‘rinbosar (moliya menejeri emas); 2-ro‘yxat — bosh buxgalter va moliya menejeri; har chiqim orderiga ikki xil shaxs imzo qo‘yadi, 2-ro‘yxat tasdig‘i pul berilishidan oldin (FD-08). «Bosh buxgalter» qatori bo‘yicha tavsiya yo‘q | 12.12 | ☐ | «Bosh buxgalter» qatori: ☐ buxgalter ☐ moliya menejeri |
| B17 | Naqd maosh | Faqat kassir beradi — har xodimga alohida chiqim orderi va oylik to‘lov qaydnomasi bilan; tasdiqlangan vedomost (qaytarishda — Direktor tasdig‘i) orderdagi rahbar tasdig‘i o‘rnini bosadi; karta orqali to‘lov va o‘zaro hisobni moliya menejeri yozadi (FD-15) | 12.12 | ☐ | |
| B18 | Direktorga beriladigan pul (avans, naqd maosh, rahbarga berish) | Direktor bosqichini Direktor o‘zi imzolaydi, 2-ro‘yxat tasdig‘i baribir kerak, pulni faqat kassir beradi; 2-ro‘yxat xodimi o‘ziga beriladigan pulni o‘zi tasdiqlamaydi; vedomost tasdig‘iga o‘tishdan oldingi oy uchun Direktor maoshi faqat karta orqali (FD-48) | 12.12 | ☐ | |
| B19 | Tizim vedomosti = ish haqi fondi | Buxgalter tizimdagi vedomost o‘z hisobotidagi ish haqi fondiga mosligini yozma tasdiqlaydi; mos kelmasa — tuzatish rejasi bilan (FD-44, G3) | 19.12 | ☐ | |
| B20 | O‘zaro hisob va moddiy naf | Xodim farzandining o‘quv to‘lovini ish haqidan ushlash — dalolatnoma + yozma ariza + Direktor tasdig‘i; xodim farzandiga chegirma moddiy naf (SK 376-modda) hisoblanadimi — buxgalterning yozma xulosasi (FD-24) | 12.12 | ☐ | Xulosa: |
| B21 | Kontragentlar turi va STIR | Ishga tushishdan oldin doimiy kontragentlar turi va STIR tekshiriladi: korxona — «Yetkazib beruvchi» yoki «Tashkilot», yakka tadbirkor va fuqaro — «Jismoniy shaxs», bank — «Bank»; yuridik shaxsga kassadan naqd to‘lov chegarasi — 0 (har biri Direktor tasdig‘i bilan; egasi qarori; FD-47) | 12.12 | ☐ | |

21-noyabrdagi vaqtincha ko‘rik (B1–B13, buyruq namunalari, shakllar): ☐ o‘tkazildi, sana [___]; tuzatishlar: ☐ yo‘q ☐ ilovada, [___] varaq

Umumiy xulosa: ☐ hammasiga roziman ☐ «Tuzatish» ustunidagi o‘zgarishlar bilan roziman

Bosh buxgalter: ____ (F.I.Sh., imzo, sana)

Direktor: ____ (F.I.Sh., imzo, sana)
