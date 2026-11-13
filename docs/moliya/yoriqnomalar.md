# «Kassa» bo‘limi: rol bo‘yicha qisqa yo‘riqnomalar (F1.19)

O‘qitishda (sinov stendida) tarqatiladi; har bo‘lim — bir varaq. Bo‘lim «Moliya» → «Kassa» da. Tugma nomlari ekrandagidek.
Hujjat raqamlari: **K-** kirim orderi (KO-1), **Ch-** chiqim orderi (KO-2), **D-** naqdsiz dalolatnoma (boshlang‘ich qoldiq,
kamomad qarori), **O‘H-** o‘zaro hisob dalolatnomasi, **A-** avans hisoboti (chop etishda kirillcha: К-, Ч-, Д-, ЎҲ-, А-). Har
turning o‘z raqami bor; raqamni tizim beradi, har yili 1 dan boshlanadi, bo‘shliq va takror bo‘lmaydi. To‘liq tartib: `docs/moliya/ishga-tushirish.md`; shakllar: `docs/moliya/shakllar.md`.

**Hamma uchun umumiy qoidalar**
1. Har kim faqat **o‘z hisobi** bilan ishlaydi; parol boshqaga berilmaydi (hujjatda kim yozgani, tasdiqlagani va pul bergani qoladi).
2. **Pul hujjatsiz olinmaydi va berilmaydi:** avval tizimda order, keyin pul. Chiqim — faqat tasdiqdan keyin.
3. Sana va raqamni tizim qo‘yadi; hujjat faqat **bugungi ochiq kunga** yoziladi.
4. Yozilgan hujjat o‘chirilmaydi va o‘zgartirilmaydi — xato bo‘lsa shu kuni **bekor qilinadi** (raqami saqlanadi) va to‘g‘risi yoziladi.
5. Bankka topshirilgan va bankdan olingan pul — kirim ham, xarajat ham emas (alohida operatsiya).

---

## 1. Kassir (va kassir o‘rinbosari, g‘aznachi)

**Ertalab.** «Kassa» sahifasini oching. Yuqorida kun kartasi: kun boshi, kirim, chiqim, kassadagi qoldiq. Qizil eslatma bo‘lsa —
avval uni bajaring. **Kecha yopilmagan bo‘lsa, bugun hujjat yozilmaydi** — avval kechagi kunni sanab yoping.

**Naqd o‘quv to‘lovi** (kassa ishga tushgan kundan):
1. Onlayn kassada fiskal chek uring — chek to‘lovchiga beriladi.
2. «To‘lovlar» → «💵 To‘lov»: o‘quvchi, summa, to‘lovchi, **«Fiskal chek №»** (majburiy), usul — naqd → saqlash.
3. «🖨 Kirim orderi va patta»: patta — to‘lovchiga, order — kassada (imzo qo‘yiladi).
Tizim summani o‘zi taqsimlaydi: avval eng eski qarz, ortig‘i — avansga. Naqdsiz to‘lov (Click, terminal, bank) ham shu oynada
kiritiladi, lekin kassa orderi yozilmaydi va kassa qoldig‘iga kirmaydi.

**Boshqa kirim** — «+ Kirim»: operatsiya tanlanadi («Bankdan naqd», «Hisobdordan qaytim», «Xodim qaytargan pul», «Kamomadni
qoplash (xodim)», «Forma va tovarlar», «Boshqa kirim», «Qarz / ta’sischi mablag‘i» — bunisi Direktor tasdig‘i bilan), **kimdan**
(ro‘yxatdan tanlanadi), summa, asos (hujjat nomi, raqami, sanasi) → «Qabul qilish» → chop etish.

**Xodimdan qaytgan pul** — xodim tanlangach oynada uning qoldig‘i ko‘rinadi; summa undan oshmaydi (tizim ham qabul qilmaydi):
- «Hisobdordan qaytim» — hisobdordagi hisobot qilinmagan avans qoldig‘idan;
- «Xodim qaytargan pul» — **qaysi oy** avansi yoki maoshi qaytayotgani tanlanadi (majburiy). Avans qaytsa (statiya OP-08) — shu oy
  naqd avans qoldig‘idan; oy vedomosti tasdiqlangan bo‘lsa qabul qilinmaydi (avans maoshdan ushlangan): pul «OP-09» bilan qabul
  qilinadi yoki Direktor oyni qayta ochadi. Berilgan maosh qaytsa (OP-09) — shu oy naqd berilgan maoshdan. Avans va maosh
  yozuvini tizim o‘zi tuzatadi: vedomost avansni qaytgani ayirilgan holda ushlaydi, qaytgan maosh yana berilishi mumkin;
- «Kamomadni qoplash (xodim)» — Direktor qarori bilan xodim zimmasiga yozilgan kassa kamomadidan.

**Chiqim** — uch qadam:
1. «+ Chiqim so‘rovi»: operatsiya («Xarajat», «Ish haqi avansi», «Hisobdorga avans», «Bankka topshirish», «Rahbar / ta’sischiga»,
   «So‘mdagi qarzni qaytarish»), **kimga**, summa, statiya, asos hujjati → «So‘rov yuborish». Xarajatning oluvchisi xodim bo‘lmaydi
   (xodimga — avans yoki hisobdorga avans). Asos hujjatisiz xarid — faqat belgilangan chegaragacha va bitta statiya bilan.
   **Yuridik shaxsga** (yetkazib beruvchi yoki tashkilot) kassadan naqd to‘lov cheklangan: oynada sariq ogohlantirish chiqadi, so‘rov
   Direktor tasdig‘ini ham kutadi (sozlamadagi chegaradan katta bo‘lsa). Asosiy yo‘l — bank o‘tkazmasi yoki hisobdor shaxs orqali.
2. Moliya menejeri yoki buxgalter tasdiqlaydi (katta summa, rahbarga berish va qarz — Direktor ham).
3. «So‘rovlar» ro‘yxatida «Pulni berish» → «🖨 Chiqim orderi» → oluvchi «Oldim» deb summa (so‘z bilan), sana va imzo qo‘yadi;
   shaxsini tasdiqlovchi hujjat ma’lumoti yoziladi. Kassada pul yetmasa tizim chiqimga yo‘l qo‘ymaydi.

**Maosh.** «Maosh» sahifasida «Maosh berish» → usul «Naqd» → chiqim orderi o‘zi yoziladi. Faqat tasdiqlangan vedomost chegarasida.
Naqd maoshni faqat kassir beradi. **Ish haqi avansi** — «+ Chiqim so‘rovi» orqali (yuqoridagi uch qadam).

**Ota-onaga pul qaytarish.** Direktor «↩ Qaytarish» orqali tasdiqlagach, «So‘rovlar»da paydo bo‘ladi → «Pulni berish» → chiqim
orderi; ota-onaning yozma arizasi orderga ilova qilinadi. Bir kundan ortiq kechiktirilmaydi (eslatma chiqadi).

**Xato qildim.** Shu kuni hujjat qatorida «Bekor» → sababi. Kassir faqat **o‘zi o‘tkazgan** orderni bekor qiladi; boshqasinikini —
moliya menejeri yoki Direktor. O‘quv to‘lovidan keyin o‘quvchi bo‘yicha boshqa pul harakati bo‘lgan bo‘lsa, bekor qilinmaydi —
Direktor «Qaytarish» qiladi. Qaytarish chiqim orderi bekor qilinmaydi. Hisobdorga avans orderidan avans hisoboti yoki qaytim
yozilgan bo‘lsa — avval o‘sha hisobot (buxgalter) yoki qaytim bekor qilinadi. «Xodim qaytargan pul» orderi: avans qaytimi (OP-08)
— oy vedomosti shu orada tasdiqlangan bo‘lsa bekor qilinmaydi (Direktor oyni qayta ochadi); maosh qaytimi (OP-09) — qaytgan maosh
keyin qayta berilgan bo‘lsa bekor qilinmaydi (avval keyingi maosh orderi bekor qilinadi). Ish haqi avansi yoki naqd maosh orderidan
kassaga qaytim yozilgan bo‘lsa — avval o‘sha qaytim orderi, keyin avans / maosh orderi bekor qilinadi.

**Smena almashsa** — «Smena topshirish»: pul sanaladi, qabul qiluvchi kassir tanlanadi, dalolatnoma chop etiladi, ikkalasi imzolaydi.

**Kechqurun.** Avval onlayn kassada (NKM) smenani yopib **Z-hisobot** chiqaring. «Kunni yopish»: kassadagi pulni sanang va
**sanalgan summani** kiriting (nominallar bo‘yicha ham mumkin); pastda **Z-hisobot №** va undagi **sotuv jamlari** — naqd va bank
kartasi (qaytarishlarsiz) → «Sanab yopish». Tizim Z ni fiskal chekli kirim orderlari va terminal to‘lovlari bilan solishtiradi va
natijani aytadi; farq bo‘lsa buxgalter sababini so‘raydi. Z-hisobot qo‘lda bo‘lmasa — «Z-hisobot yo‘q» (sababi bilan), keyin
«Kassa kunlari» qatoridagi **«Z»** tugmasi bilan kiriting (xato yozilgan bo‘lsa ham shu tugma bilan — kun tekshirilguncha). Sanashda
farq bo‘lsa tizim shu kunga kamomad yoki ortiqcha hujjatini o‘zi yozadi — sababini izohga yozing. Keyin «🖨 KO-4» (2 nusxa) va
«🖨 Kunlik hisobot»: imzolab, orderlar, ilovalari va Z-hisobot bilan moliya menejeriga topshiring.

**Oy oxiri** — «KO-3» (kassa orderlari jurnali) va «Statiyalar» (oylik statiya matritsasi): oyni tanlab ko‘ring va chop eting
(«🖨 KO-3», «🖨 Chop etish»). Excel fayllar sizda yo‘q — ularni moliya menejeri, buxgalter yoki Direktor oladi.

**Internet yoki tizim ishlamasa** — `ishga-tushirish.md`, 8-bo‘lim («Қ» blankasi to‘lovchiga berilmaydi; dalil — fiskal chek).

## 2. Moliya menejeri va buxgalter (2-ro‘yxat)

Buxgalterning o‘z hisobi va roli bor — **«Buxgalter»** (Direktor «Foydalanuvchilar»da beradi; qo‘shimcha lavozim bu rolga
berilmaydi — buxgalter kassirni nazorat qiladi). To‘rt bo‘lim ochiladi:
- **«Tasdiqlash»** va **«Kassa»** — 2-ro‘yxat nazorati: kassir so‘rovlarini tasdiqlash yoki rad etish, kunni tekshirish,
  o‘tkazilgan hujjatni bekor qilish, avans hisoboti (o‘tkazilganda xarajat «Buxgalteriya»ga o‘zi tushadi), nazorat ro‘yxati, KO-3,
  statiyalar, KPI, chop etish, «Davr»ni ko‘rish;
- **«To‘lovlar»** (faqat ko‘rish) — oy bo‘yicha hisob-fakturalar, to‘lovlar (kassa, bank, terminal, Click/Uzum), qaytarishlar,
  avanslar, biriktirilmagan to‘lovlar (sana, provayder, summa), o‘quvchining to‘lov tarixi (📋);
- **«Buxgalteriya»** (faqat ko‘rish) — kirim, chiqim, xarajatlar ro‘yxati va toifalari, xodim avanslari, berilgan maosh, **oylik
  vedomost** (holati va qatorlari), A4 oylik hisobot.

Pul qabul qilish va berish, kassaga so‘rov yuborish, xarajatni qo‘lda yozish, tahrirlash va o‘chirish buxgalterda yo‘q (tugmalar
ko‘rinmaydi, server ham rad etadi). O‘quvchi ismi, ID, sinfi ko‘rinadi; telefon, manzil, sog‘liq kartasi, baholar, davomat
jurnali, xodim kartochkalari — yo‘q (D6/D7). To‘lovchi yozgan matn (ism, «sinf», izoh) va ota-ona telefoni to‘lov yozuvlarida
ham ko‘rsatilmaydi. Chegirma va uning sababi (monitoring 20% / 100%, kasal kunlar soni va summasi) ko‘rinadi — hisob uchun
kerak; kasallik sanalari — yo‘q. Excel va A4 hisobot buxgalterda **ismsiz** (o‘quvchi — ID, xodim — maosh ID’si; FD-28).

**Har kuni**
1. **Chiqim so‘rovlarini tasdiqlash:** «Kassa» → «So‘rovlar» → «Ko‘rish»: oluvchi, statiya, asos hujjati to‘g‘rimi → «Tasdiqlash»
   yoki «Rad etish» (sababi). O‘zingiz yuborgan so‘rovni o‘zingiz tasdiqlay olmaysiz.
2. **Kunni tekshirish:** kassir topshirgan KO-4, orderlar va ilovalarni ekrandagi kun bilan solishtiring → «Kassa kunlari» →
   «Tekshirish» → «qog‘oz va ilovalar olindi» belgisi → «Tekshirdim». Kunlar tartib bilan tekshiriladi; shu kuni hujjat o‘tkazgan
   yoki kunni yopgan shaxs tekshira olmaydi. Tekshirilgan kun endi o‘zgarmaydi. **Onlayn kassa Z-hisoboti** kiritilmagan, «yo‘q»
   deb belgilangan yoki tizimdagi summalar bilan mos kelmasa, oynada qizil ogohlantirish chiqadi — qog‘ozdagi Z bilan solishtiring:
   kassir xato yozgan bo‘lsa, u «Z» tugmasi bilan tuzatadi; haqiqiy farq bo‘lsa (masalan, chek urilgan, lekin order bekor qilingan)
   — sababini izohga yozib tekshirasiz.
3. **«Nazorat ro‘yxati»** (shu sahifada): qizil — bugun hal qilinadi (raqamlashda bo‘shliq, yopilmagan kecha, qarorsiz kamomad,
   kechikkan qaytarish, «Moslik» mos emas, Z-hisobot farqi, hisobdorda **manfiy qoldiq** — qaytim yoki hisobot berilgan avansdan
   ko‘p: xato yozuv izi); sariq — shu hafta (shu jumladan yuridik shaxslarga kassadan naqd to‘lovlar — har biri asosli ekanini
   tekshiring); «Moslik» qatori doim «hammasi mos» bo‘lishi kerak (xodim qaytargan pul orderi va avans / maosh yozuvi ham
   solishtiriladi). **«Xodimlar zimmasidagi kamomad»** — Direktor qarori bilan xodimga yozilgan kamomad va qoplangani: kassir
   «Kamomadni qoplash (xodim)» bilan qabul qiladi, qolganini ish haqidan ushlash — buxgalter (4-bosqichgacha qo‘lda). Kassir hisobi
   xodim kartasiga bog‘lanmagan bo‘lsa qaror «boshqa» tomonga yoziladi va kassadan qoplanmaydi (ro‘yxatda belgi bilan) — kassir
   hisoblarini xodim kartasiga bog‘lab qo‘ying.
4. **Bank orqali to‘langan xarajatlar** (moliya menejeri) — «Buxgalteriya» → «+ Xarajat qo‘shish»: to‘lov usuli (bank o‘tkazmasi
   yoki korporativ karta), statiya, kontragent. Hisobdor shaxs sarflagan pul bu yerda emas — «Kassa» → «Avans hisoboti».
   Naqd xarajat bu yerda yozilmaydi — u kassa chiqim orderidan o‘zi ko‘chadi.

**Maosh.** Vedomostni moliya menejeri tayyorlaydi, HR tasdiqlaydi. Karta orqali to‘lovni moliya menejeri «Maosh berish» → «Karta»
bilan yozadi (kassa orderisiz); naqd — faqat kassir. Xodim avansni kassaga qaytarsa (kassir — «Xodim qaytargan pul», OP-08),
vedomost avansni bazadan qaytgani ayirilgan holda oladi — vedomostni qaytimdan keyin tayyorlang (yuborilgan bo‘lsa — HR qaytaradi,
qayta yuboring); tasdiqlangan oy uchun avans qaytimi qabul qilinmaydi. Berilgan maosh qaytsa (OP-09) — shu oy berilgan summa
kamayadi: qolgani shu oy yana berilishi yoki keyingi oyga qoldiq bo‘lib o‘tishi mumkin.

**Hisobdorlar.** Pul «Hisobdorga avans» bilan beriladi (bu xarajat emas). Hisobdor 3 ish kuni ichida avans hisobotini (qog‘oz,
`shakllar.md` Sh-1) cheklari bilan topshiradi; qaytim — «+ Kirim» → «Hisobdordan qaytim». Buxgalter (yoki moliya menejeri) hisobotni
tekshiradi va **«Kassa» → «Avans hisoboti»**ga kiritadi: hisobdorni tanlaydi, har chek — bitta qator (statiya, summa, chek raqami va
sanasi). Xarajat «Buxgalteriya»ga o‘zi ko‘chadi, hisobdordagi qoldiq kamayadi; «Avans hisoboti № A-…» chop etiladi va qog‘oz
hisobotga qo‘shiladi. Hisobot qoldiqdan katta bo‘lsa — ortiqcha sarf alohida «Xarajat» orderi bilan beriladi. Xato bo‘lsa — shu kuni
«Naqdsiz dalolatnomalar» ro‘yxatida «Bekor». Qaytim ham qoldiqdan oshmaydi; hisoboti yoki qaytimi yozilgan avans orderi bekor
qilinmaydi (avval hisobot yoki qaytim bekor qilinadi). Manfiy qoldiq (xato yozuv izi) nazorat ro‘yxatida qizil, oylik to‘plamda
(E4) alohida belgi bilan ko‘rinadi. Oldingi avansi hisobotsiz qolgan xodimga yangi avans faqat Direktor tasdig‘i bilan
beriladi. Muddati o‘tgan qoldiqlar nazorat ro‘yxatida ko‘rinadi, «Kassa» sahifasining yuqorisida eslatma chiqadi («Avans hisoboti
muddati o‘tgan hisobdorlar: N ta») va Direktorning Telegram nazorat qatorida ham bo‘ladi.

**Har hafta (dushanba)** — **«KPI»** (haftalik ko‘rsatkichlar, RP-22): oxirgi 8 hafta bo‘yicha kun o‘sha kuni yopildimi,
tekshirilmagan kunlar, sanash farqlari, «Boshqa xarajatlar» (EX-49) ulushi (maqsad ≤ 2 %; oshsa — qayta tasniflang) va hafta
oxirida avans hisoboti muddati o‘tgan hisobdorlar. Rang bilan ajratilgan ko‘rsatkichni kassir bilan shu hafta tuzating.

**Oy oxiri.** Hamma kun «Tekshirilgan»; nazorat ro‘yxati toza; avans hisobotlari kiritilgan → **«KO-3»** (kassa orderlari jurnali):
oy tanlanadi, jamlar va «davr boshi + kirim − chiqim = davr oxiri» tekshiriladi, «🖨 KO-3» chop etilib imzolanadi, «⬇ Excel» —
buxgalter dasturi uchun (summalar son, sana — Excel sanasi) → **«Statiyalar»** (oylik statiya matritsasi, RP-08): oy tanlanadi,
kirim va chiqim statiyalar bo‘yicha (bank bilan ichki o‘tkazma alohida — daromad ham, xarajat ham emas), «🖨 Chop etish» —
haftalar kesimida, imzolanadi; «⬇ Oylik to‘plam (Excel)» — buxgalter uchun bitta fayl, to‘rt varaq: E1 KO-3, E2 statiyalar
(kunlar bo‘yicha), E3 kassa kunlari (KO-4 jamlari, sanash va farq, Z-hisobot), E4 hisobdorlar (oy boshi, berildi, qaytdi,
hisobot, oy oxiri) → Direktor «Davr»da surat oladi va davrni yopadi.

KO-3 Excel va oylik to‘plam tugmalari Moliya menejeri, buxgalter va Direktorda (kassir chop etadi). Sizning fayllaringiz ismsiz
(FD-28, fayl nomida «-ismsiz»): o‘quvchi — ID, xodim — tabel kodi, boshqa jismoniy shaxs — nomsiz, ularning hujjatlaridagi asos
va bekor qilish sababi chiqmaydi; yetkazib beruvchi, tashkilot va bank nomi va asosi qoladi; to‘liq nusxa — Direktorda. «Davr» oynasida
suratlarni ko‘rish, «Tekshirish» (xesh) va «⬇ JSON» sizga ham ochiq. Sizga yuklanadigan JSON —
ismsiz (o‘quvchi va xodim faqat ID bilan, fayl nomida «-ismsiz»); ismli to‘liq nusxa faqat Direktorda — arxivga Direktor yuklagani
qo‘yiladi.

**Kassa orqali o‘tgan to‘lov** (naqd o‘quv to‘lovi, o‘zaro hisob) summasi, o‘quvchisi, sanasi yoki usuli «To‘lovlar»dan
o‘zgartirilmaydi va bekor qilinmaydi — xato bo‘lsa shu kuni hujjat «Kassa»da bekor qilinadi, keyin esa Direktor «Qaytarish»
qiladi (1-bo‘lim, «Xato qildim»). Yopilgan davrdagi to‘lovning sanasi, summasi, usuli o‘zgartirilmaydi va u bekor qilinmaydi.

## 3. Direktor

**Bir marta (ishga tushirishda):** «⚙ Sozlamalar» (tashkilot nomi, STIR, joy, chop etish tili, T1, L1, kassa limiti, imzo egalari,
ishga tushadigan kun) va «Boshlang‘ich qoldiqni kiritish» — `ishga-tushirish.md`, 4-bo‘lim.

**Har kuni**
- **Telegram hisoboti:** kassa qatori (kirim, chiqim, qoldiq; sanaldi / farq) va «Kassa nazorati» qatori (muddati o‘tgan avans
  ham). Nazorat qatori bo‘sh bo‘lmasa — «Kassa» → «Nazorat ro‘yxati». Dushanba kuni — qo‘shimcha «Kassa — o‘tgan hafta» qatori
  (haftalik ko‘rsatkichlar); batafsil — «Kassa» → «KPI».
- **Tasdiqlash:** T1 dan katta chiqim, rahbar yoki ta’sischiga beriladigan pul, qarz — «So‘rovlar» → «Tasdiqlash».
- **Qaytarish:** «↩ Qaytarish» (sababi, ariza sanasi, usul). Naqd bo‘lsa pulni kassir beradi; balans pul berilganda o‘zgaradi.
- **O‘zaro hisob:** xodim yozma ariza bilan ish haqidan farzandining o‘quv haqini to‘lasa — «Maosh berish» → «O‘zaro hisob»
  (o‘quvchi, ariza sanasi, summa). Kassadan pul chiqmaydi; dalolatnoma chop etiladi. Xato bo‘lsa — shu kuni «Bekor».

**Faqat Direktor qiladigan amallar**
| Amal | Qayerda | Eslatma |
|---|---|---|
| Kamomad bo‘yicha qaror | «Qarori kutilayotgan kamomadlar» → «Qaror» | xodim hisobiga yoki zararga; dalolatnoma; xodim hisobiga — u pulni kassaga «Kamomadni qoplash (xodim)» bilan qaytaradi (qolgani nazorat ro‘yxatida) |
| Yopilgan kunni qayta ochish | «Kassa kunlari» → «Qayta ochish» | faqat oxirgi, tekshirilmagan kun; sababi yoziladi |
| Fiskal cheksiz naqd to‘lov (istisno) | «💵 To‘lov» → «Fiskal cheksiz» | faqat kassa apparati ishlamaganda; jurnalda qoladi |
| 48 soatdan eski oflayn yozuvni kiritish | «💵 To‘lov» | «Қ» blankasi asosida |
| Davr surati va davrni yopish / qayta ochish | «Davr» | yopish — shu sanagacha kassa kunlari yopilgach; qayta ochish — sababi bilan, tarixda qoladi |
| Oldingi avansi hisobotsiz xodimga yangi avans (istisno) | «So‘rovlar» → «Tasdiqlash» | kassa tartibidan istisno; so‘rovda «Direktor tasdig‘i» talabi o‘zi qo‘yiladi |
| Yuridik shaxsga kassadan naqd to‘lov | «So‘rovlar» → «Tasdiqlash» | chegara — «⚙ Sozlamalar» (bo‘sh — har doim Direktor); asosiy yo‘l — bank |
| Sozlamalar, imzo egalari, boshlang‘ich qoldiq | «⚙ Sozlamalar» | chegaralarni faqat Direktor o‘zgartiradi |
| KO-3 va oylik kassa to‘plamining to‘liq (ismli) Excel nusxasi | «Kassa» → «KO-3» → «⬇ Excel»; «Statiyalar» → «⬇ Oylik to‘plam» | boshqalarga ismsiz nusxa chiqadi (FD-28); ismli faylda shaxsiy ma’lumot bor — ehtiyot bilan saqlanadi |

Kassir yo‘qligida kunni Direktor yoki moliya menejeri yopishi mumkin — kamida 2 kishilik komissiya bilan.

## 4. HR menejer
- Vedomostni tekshirib **tasdiqlaysiz** — maosh kunidan oldin. Tasdiqlanmagan oy uchun naqd maosh berilmaydi.
- Kassa ishga tushgach **pul bermaysiz**: «Maosh berish» tugmasi sizda ko‘rinmaydi (naqd — kassir, karta — moliya menejeri).
- Ish haqi avansi so‘rovini kassir yoki moliya menejeri yuboradi; tasdiqlangan vedomostdan ortiq avans berilmaydi.
- Xodim avansni kassaga qaytarsa, vedomostda avans qaytgani ayirilgan holda ko‘rinadi; oy tasdiqlangach avans qaytimi qabul
  qilinmaydi (kerak bo‘lsa Direktor oyni qayta ochadi).

## 5. Hisobdor shaxs (zavxoz, oshpaz va boshqalar)
1. Pulni kassadan **chiqim orderi** bilan olasiz («Hisobdorga avans») — orderga «Oldim», summa, sana, imzo.
2. Har xarid uchun chek yoki hisob-faktura oling (sana, sotuvchi, nima, summa ko‘rinib tursin).
3. **3 ish kuni ichida** avans hisobotini (qog‘oz shakl, `shakllar.md` Sh-1) cheklari bilan buxgalterga topshiring.
4. Ortgan pulni kassaga qaytaring — kassir **kirim orderi** yozadi («Hisobdordan qaytim»; hisobot qilinmagan qoldiqdan oshmaydi),
   pattasi sizda qoladi.
5. Avvalgi pul bo‘yicha hisobot topshirilmaguncha yangi pul so‘ralmaydi. Hisobdor puli — shaxsiy xarajat uchun emas.
