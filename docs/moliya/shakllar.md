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
| **Kassani sanash dalolatnomasi** | har sanashda chop etish mumkin («Sanashlar» → «🖨 Dalolatnoma»): kun yopilishi (farq bo‘lsa — albatta), smena topshirish, komissiya sanashi | 2 | kassir, komissiya a’zolari (smenada — topshirgan va qabul qilgan) | kassa hujjatlari jildida |
| **Naqdsiz dalolatnoma** (boshlang‘ich qoldiq; kamomad bo‘yicha qaror; o‘zaro hisob) | Direktor amali bilan | 2 | rahbar, bosh buxgalter; qarorda — javobgar shaxs; o‘zaro hisobda — xodim | buxgalteriyada |
| **Kunlik hisobot** | kun yopilgach (ichki hisobot) | 1 | — | moliya menejerida |

Belgilar: qayta chop etilganda — «НУСХА»; kun qayta ochilib yopilgan bo‘lsa — «АЛМАШТИРИЛДИ» (avvalgi varaq bekor qilinib
saqlanadi); bekor qilingan hujjatda — «БЕКОР ҚИЛИНГАН»; yopilmagan kun varag‘ida — «ҚОРАЛАМА»; sinov kassasida — «СИНОВ».
Bekor qilingan order yirtib tashlanmaydi — jildda o‘z raqami o‘rnida saqlanadi.

## B. Qog‘oz shakllar (shablonlar quyida)
| № | Shakl | Qachon | Kim to‘ldiradi |
|---|---|---|---|
| Sh-1 | Avans hisoboti | hisobdor pul sarflaganda (3 ish kuni ichida) | hisobdor shaxs; tekshiradi — buxgalter; tasdiqlaydi — rahbar |
| Sh-2 | «Қ» blankasi va jurnali | tizim (server) ishlamay qolganda | kassir |
| Sh-3 | Kassani sanash dalolatnomasi (boshlang‘ich qoldiq) | 31-dekabr kechqurun (tizim ishga tushmasidan oldin) | inventarizatsiya komissiyasi |
| Sh-4 | Qog‘oz order daftarlarini yopish dalolatnomasi | 31-dekabr kechqurun | kassir, buxgalter |
| Sh-5 | Qabul sinovi varag‘i | sinov stendida, ishga tushirishdan oldin | har rol |
| Sh-6 | Parallel yuritish kunlik nazorat varag‘i | birinchi 5 ish kuni | moliya menejeri |
| Sh-7 | Hisobdor shaxs qoldig‘i ma’lumotnomasi | 31-dekabr holatiga | hisobdor shaxs, buxgalter |

---

## Sh-1. Avans hisoboti

Qog‘ozdagi hisobot (cheklar bilan) — birlamchi hujjat. Tekshirilgach u tizimga «Kassa» → «Avans hisoboti» bilan kiritiladi: har chek —
bitta qator, xarajat «Buxgalteriya»ga o‘zi ko‘chadi, hisobdordagi qoldiq kamayadi. Tizim chop etgan dalolatnoma (tasdiqlovchi imzolar
bilan) shu qog‘oz hisobotga qo‘shib saqlanadi.

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

*Qoidalar:* muddat — 3 ish kuni (korporativ karta bo‘yicha — 10); har xarajat alohida qator va hujjat bilan; cheksiz xarajat qabul
qilinmaydi (istisno — rahbar ruxsati bilan tushuntirish xati); hisobot topshirilmaguncha yangi avans berilmaydi; buxgalter
tekshirgan qatorlarni moliya menejeri «Buxgalteriya»ga xarajat qilib kiritadi (to‘lov usuli — «Hisobdor shaxs orqali (avans hisoboti)»); yanvar
hisobotlari — yanvar yopilishidan oldin.

## Sh-2. «Қ» blankasi (ichki vaqtinchalik kvitansiya) va jurnali
Faqat tizim (server) ishlamay qolganda. **To‘lovchiga berilmaydi** — to‘lovchi fiskal chek oladi. Blankalar oldindan raqamlanadi
(Қ-0001 …), buzilgani bekor qilinib saqlanadi. Tizim tiklangach har blanka tizimga kiritiladi va jurnalda order raqami yoziladi.

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
Komissiya: rais — [lavozim, F.I.Sh.]; a’zolar — [lavozim, F.I.Sh.], [lavozim, F.I.Sh.]; moddiy javobgar shaxs — kassir [F.I.Sh.]

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

*Eslatma:* shu dalolatnomadagi «haqiqatda mavjud» summa tizimga boshlang‘ich qoldiq sifatida kiritiladi. Tizim ishga tushgach
sanash dalolatnomalarini (kun yopilishi, smena, oy oxiri) tizimning o‘zi chop etadi.

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
Rol: [kassir / moliya menejeri / buxgalter / direktor / HR] · F.I.Sh.: [___] · Sana: [___] · Qurilma: ☐ kompyuter ☐ telefon

| № | Ssenariy | Bajarildi | Izoh |
|---|---|---|---|
| 1 | Naqd o‘quv to‘lovi: fiskal chek № bilan; kirim orderi va patta chop etildi | ☐ | |
| 2 | Ortiqcha to‘lov (avansga) va kelgusi oy uchun to‘lov — taqsimot to‘g‘ri | ☐ | |
| 3 | Boshqa kirim («Bankdan naqd», «Hisobdordan qaytim» — qoldiqdan katta summa rad etildi) | ☐ | |
| 3a | «Xodim qaytargan pul»: oy tanlandi, oynada avans qoldig‘i / berilgan maosh ko‘rindi; avans qaytimidan keyin vedomostda avans kamaydi | ☐ | |
| 3b | «Kamomadni qoplash (xodim)»: xodim zimmasidagi kamomaddan qabul qilindi, nazorat ro‘yxatida qoldiq kamaydi | ☐ | |
| 4 | Chiqim so‘rovi → tasdiq → pul berish; chiqim orderi chop etildi | ☐ | |
| 5 | T1 dan katta chiqim — Direktor tasdig‘isiz berilmadi | ☐ | |
| 6 | Xato orderni shu kuni bekor qilish | ☐ | |
| 7 | Naqd maosh (tasdiqlangan vedomost chegarasida); ish haqi avansi | ☐ | |
| 8 | Qaytarish: Direktor tasdig‘i → kassir pulni berdi | ☐ | |
| 9 | Smena topshirish | ☐ | |
| 10 | Kunni farq bilan yopish; KO-4 (2 nusxa), sanash dalolatnomasi, kunlik hisobot | ☐ | |
| 11 | Kunni tekshirish («Tekshirdim»); kamomad bo‘yicha qaror | ☐ | |
| 12 | Nazorat ro‘yxati va Telegram hisobotidagi kassa qatori tushunarli | ☐ | |
| 13 | Davr surati va davrni yopish; yopilgan sanaga yozuv rad etildi | ☐ | |
| 14 | Internet uzilganda to‘lov navbatga tushdi, keyin o‘zi o‘tdi | ☐ | |
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
«[Tashkilot nomi]» · [sana] holatiga
Men, [lavozim, F.I.Sh.], shuni tasdiqlaymanki, menda hisobdorlik asosida olingan va hali hisobot berilmagan pul qoldig‘i
[raqam bilan] so‘m ([so‘z bilan]); shundan hujjatlari bor, hali hisobotga kiritilmagan xarajatlar — [___] so‘m, naqd qoldiq — [___] so‘m.
Hisobdor shaxs: [___] (imzo) · Buxgalter: [___] (imzo)
*Bu qoldiq yangi yilda hisobdor kartochkasining boshlang‘ich qoldig‘i bo‘ladi.*
