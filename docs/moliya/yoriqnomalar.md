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

**Ertalab.** «Kassa» sahifasini oching. Yuqorida kun kartasi: kun boshi, kirim, chiqim, kassadagi qoldiq va kassa egasi
(«kassir: …» — shu kuni birinchi kassa hujjatini yozgan kassir; smena qabul qilinsa — qabul qiluvchi). Qizil eslatma bo‘lsa —
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
   Yangi kontragent («+ yangi») turini to‘g‘ri tanlang: korxona (MChJ, AJ) — «Yetkazib beruvchi» yoki «Tashkilot». «Jismoniy shaxs» va
   «Boshqa» turini buxgalter (yoki Direktor) tasdiqlaydi — ungacha kontragent yuridik shaxs hisoblanadi (ro‘yxatda «turi tasdiqlanmagan»).
2. Moliya menejeri yoki buxgalter tasdiqlaydi (katta summa, rahbarga berish va qarz — Direktor ham).
3. «So‘rovlar» ro‘yxatida «Pulni berish» → «🖨 Chiqim orderi» → oluvchi «Oldim» deb summa (so‘z bilan), sana va imzo qo‘yadi;
   shaxsini tasdiqlovchi hujjat ma’lumoti yoziladi. Kassada pul yetmasa tizim chiqimga yo‘l qo‘ymaydi. So‘rovni o‘zi tasdiqlagan xodim
   (masalan, qo‘shimcha «kassir» lavozimli moliya menejeri) uning pulini bermaydi — boshqa kassir beradi. Tasdiqdan keyin kontragent
   turi o‘zgargan bo‘lsa (endi yuridik shaxs hisoblansa) pul berilmaydi: so‘rov o‘zi Direktor tasdig‘iga qaytadi (qizil xabar) —
   Direktor tasdiqlagach pulni bering.

**Maosh.** «Maosh» sahifasida «Maosh berish» → usul «Naqd» → chiqim orderi o‘zi yoziladi. Faqat tasdiqlangan vedomost chegarasida.
Naqd maoshni faqat kassir beradi. **Ish haqi avansi** — «+ Chiqim so‘rovi» orqali (yuqoridagi uch qadam).

**Ota-onaga pul qaytarish** (o‘quvchi avansini qaytarish ham). Direktor tasdiqlagach, «So‘rovlar»da paydo bo‘ladi → «Pulni berish» →
chiqim orderi; ota-onaning yozma arizasi orderga ilova qilinadi. Bir kundan ortiq kechiktirilmaydi (eslatma chiqadi). Tasdiqdan keyin
faktura yoki o‘quvchi avansi o‘zgargan bo‘lsa, tizim pulni bermaydi — Direktorga ayting (so‘rovni bekor qilib, qaytadan tasdiqlaydi).

**Xato qildim.** Shu kuni hujjat qatorida «Bekor» → sababi. Kassir faqat **o‘zi o‘tkazgan** orderni bekor qiladi; boshqasinikini —
moliya menejeri yoki Direktor. Smena topshirilib qabul qilingan bo‘lsa, undan **oldin** o‘tkazilgan orderni (o‘zingiznikini ham)
kassir bekor qilmaydi — u topshirish-qabul sanashiga kirgan («Bekor» tugmasi ko‘rinmaydi): xato bo‘lsa moliya menejeri, buxgalter
yoki Direktor bekor qiladi, farq kunni yopishda ko‘rinadi. O‘quv to‘lovidan keyin o‘quvchi bo‘yicha boshqa pul harakati bo‘lgan
bo‘lsa, bekor qilinmaydi — Direktor «Qaytarish» qiladi. Qaytarish chiqim orderi bekor qilinmaydi. Hisobdorga avans orderidan avans
hisoboti yoki qaytim yozilgan bo‘lsa — avval o‘sha hisobot (buxgalter) yoki qaytim bekor qilinadi. «Xodim qaytargan pul» orderi:
avans qaytimi (OP-08) — oy vedomosti shu orada tasdiqlangan bo‘lsa bekor qilinmaydi (Direktor oyni qayta ochadi); maosh qaytimi
(OP-09) — qaytgan maosh keyin qayta berilgan bo‘lsa bekor qilinmaydi (avval keyingi maosh orderi bekor qilinadi). Ish haqi avansi
yoki naqd maosh orderidan kassaga qaytim yozilgan bo‘lsa — avval o‘sha qaytim orderi, keyin avans / maosh orderi bekor qilinadi.

**Smena almashsa** — ikki bosqichda, ikkala kassir kassa yonida:
1. Topshiruvchi — «Smena topshirish»: pulni qabul qiluvchi bilan birga sanaydi, sanalgan summani kiritadi, qabul qiluvchi kassirni
   tanlaydi. Shundan qabul qilinguncha kassada hujjat yozilmaydi, bekor qilinmaydi va kun yopilmaydi (sariq ogohlantirish).
2. Qabul qiluvchi **o‘z hisobidan** kiradi: «Smenani qabul qilish» kartasida summani tekshirib — «Qabul qildim». Shundagina kassa
   unga o‘tadi (kun kartasida «kassir: …»); farq bo‘lsa tizim kamomad yoki ortiqcha hujjatini **topshiruvchi** nomidan yozadi.
   Topshirish-qabul dalolatnomasi shundan keyin chop etiladi (ikkala ism bilan) — ikkalasi imzolaydi.

Summa mos kelmasa qabul qiluvchi «Rad etish» bosadi (sababi bilan) — topshiruvchi qayta sanab, yangidan topshiradi; topshiruvchi
yoki Direktor «Bekor qilish» bilan qaytarib oladi. Kassa egasi (kun kartasidagi kassir) yo‘q bo‘lsa, uning o‘rniga boshqa kassir
yoki Direktor topshiradi — kamida 2 kishilik komissiya bilan.

**Kechqurun.** Avval onlayn kassada (NKM) smenani yopib **Z-hisobot** chiqaring. «Kunni yopish»: kassadagi pulni sanang va
**sanalgan summani** kiriting (nominallar bo‘yicha ham mumkin); pastda **Z-hisobot №** va undagi **sotuv jamlari** — naqd va bank
kartasi (qaytarishlarsiz) → «Sanab yopish». Tizim Z ni fiskal chekli kirim orderlari va terminal to‘lovlari bilan solishtiradi va
natijani aytadi; farq bo‘lsa buxgalter sababini so‘raydi. Z-hisobot qo‘lda bo‘lmasa — «Z-hisobot yo‘q» (sababi bilan), keyin
«Kassa kunlari» qatoridagi **«Z»** tugmasi bilan kiriting (xato yozilgan bo‘lsa ham shu tugma bilan — kun tekshirilguncha). Sanashda
farq bo‘lsa tizim shu kunga kamomad yoki ortiqcha hujjatini o‘zi yozadi — sababini izohga yozing. Keyin «🖨 KO-4» (2 nusxa) va
«🖨 Kunlik hisobot»: imzolab, orderlar, ilovalari va Z-hisobot bilan moliya menejeriga topshiring. Kunni **kassa egasi** (kun
kartasidagi kassir) yopadi; boshqa kassir uning o‘rniga yopsa — kamida 2 kishilik komissiya bilan (yoki avval smena topshiriladi).

**Oy oxiri** — «KO-3» (kassa orderlari jurnali) va «Statiyalar» (oylik statiya matritsasi): oyni tanlab ko‘ring va chop eting
(«🖨 KO-3», «🖨 Chop etish»). Excel fayllar sizda yo‘q — ularni moliya menejeri, buxgalter yoki Direktor oladi.

**Internet yoki tizim ishlamasa** — `ishga-tushirish.md`, 8-bo‘lim («Қ» blankasi to‘lovchiga berilmaydi; dalil — fiskal chek).

**Kassa ishga tushishidan oldingi pul.** Boshlang‘ich qoldiq sanashidan oldin qurilmangiz internetga ulangan va navbati (⏳)
bo‘sh bo‘lsin. Ishga tushish kunidan oldin olingan pulni keyin **bugungi sana bilan qayta kiritmang** — u sanashga kirgan,
ikki marta hisoblanadi: bugungi sana bilan kiritilgan to‘lovni tizim oddiy bugungi to‘lov deb qabul qiladi (kirim orderi
yoziladi), farqini bilmaydi. Navbatda qolib ketgan yozuv internet qaytganda o‘zi o‘tadi (48 soatgacha;
kirim orderisiz); undan eskisini yoki qog‘ozda topilganini Direktor haqiqiy sanasi bilan kiritadi. Kassa to‘xtatilgan bo‘lsa
(«Kassa to‘xtatilgan» ogohlantirishi) — kassa hujjati yozilmaydi; pul «Қ» blankalari bilan (o‘z raqamlari bilan) qabul
qilinadi va tizimga **oxirgi kassa kunidan keyingi sana** bilan kiritiladi: oxirgi kassa kuni va undan oldingi sana bilan tizim
qabul qilmaydi (to‘xtatilgan kunning o‘zida, kun yopilgandan keyin olingan pul — ertasi kuni). Navbatda qolib, to‘xtatilgan kassa
qabul qilmagan to‘lovni kassa qayta ishga tushgach ham **qayta yubormang** — Direktorga ayting (pul kassada sanalgan bo‘lsa, kirim
orderi uni ikkinchi marta hisoblaydi va kamomad sizga chiqadi). Qayta ishga tushirish — Direktor,
komissiya sanashi bilan (`ishga-tushirish.md`, 9-bo‘lim); sanashdan keyin kiritilgan naqd yozuv sanashga kirmaydi — qayta sanash
kerak bo‘ladi (aks holda birinchi kassa kuni ochilmaydi).

## 2. Moliya menejeri va buxgalter (2-ro‘yxat)

Buxgalterning o‘z hisobi va roli bor — **«Buxgalter»** (Direktor «Foydalanuvchilar»da beradi; qo‘shimcha lavozim bu rolga
berilmaydi — buxgalter kassirni nazorat qiladi). To‘rt bo‘lim ochiladi:
- **«Tasdiqlash»** va **«Kassa»** — 2-ro‘yxat nazorati: kassir so‘rovlarini tasdiqlash yoki rad etish, kunni tekshirish,
  o‘tkazilgan hujjatni bekor qilish (smena topshirishda sanalgan orderni ham — kassir uni bekor qilmaydi; kassa egasi bo‘lmagan xodim
  bekor qilsa, o‘sha kungi kamomadda standart javobgar bo‘lmaydi — Direktor tanlaydi), avans hisoboti (o‘tkazilganda xarajat
  «Buxgalteriya»ga o‘zi tushadi), nazorat ro‘yxati, KO-3, statiyalar, KPI, chop etish, «Davr»ni ko‘rish;
- **«To‘lovlar»** (faqat ko‘rish) — oy bo‘yicha hisob-fakturalar, to‘lovlar (kassa, bank, terminal, Click/Uzum), qaytarishlar,
  avanslar, biriktirilmagan to‘lovlar (sana, provayder, summa), o‘quvchining to‘lov tarixi (📋);
- **«Buxgalteriya»** (faqat ko‘rish) — kirim, chiqim, xarajatlar ro‘yxati va toifalari, xodim avanslari, berilgan maosh, **oylik
  vedomost** (holati va qatorlari), A4 oylik hisobot.

«Buxgalteriya»dagi **«Foyda» — taxminiy**: hisob-fakturalar bo‘yicha to‘langan o‘quv to‘lovi (qaytarilgani ayirilgan) minus **barcha**
chiqimlar ro‘yxati — kassa xarajat orderlari, avans hisobotlari, bank va karta xarajatlari. Asosiy vosita va sotish uchun tovar ham shu
ro‘yxatda («Inventar» / «Boshqa» toifasida, izoh statiya nomi bilan boshlanadi: «Sotish uchun tovar xaridi: …»). Forma sotuvi va o‘quv
to‘lovidan boshqa kirimlar unga kirmaydi — ular kassa hisobotlarida (KO-3 jurnali, RP-08 statiyalar matritsasi). Haqiqiy moliyaviy natija —
4-bosqichda (bosh kitob).

Pul qabul qilish va berish, kassaga so‘rov yuborish, xarajatni qo‘lda yozish, tahrirlash va o‘chirish buxgalterda yo‘q (tugmalar
ko‘rinmaydi, server ham rad etadi). O‘quvchi ismi, ID, sinfi ko‘rinadi; telefon, manzil, sog‘liq kartasi, baholar, davomat
jurnali, xodim kartochkalari — yo‘q (D6/D7). To‘lovchi yozgan matn (ism, «sinf», izoh) va ota-ona telefoni to‘lov yozuvlarida
ham ko‘rsatilmaydi. Chegirma va uning sababi (monitoring 20% / 100%, kasal kunlar soni va summasi) ko‘rinadi — hisob uchun
kerak; kasallik sanalari — yo‘q. Excel va A4 hisobot buxgalterda **ismsiz** (o‘quvchi — ID, xodim — maosh ID’si; FD-28).

**Har kuni**
1. **Chiqim so‘rovlarini tasdiqlash:** «Kassa» → «So‘rovlar» → «Ko‘rish»: oluvchi, statiya, asos hujjati to‘g‘rimi → «Tasdiqlash»
   yoki «Rad etish» (sababi). O‘zingiz yuborgan so‘rovni va o‘zingizga (hisobingiz bog‘langan xodim kartasiga, ikkinchi lavozim
   kartasi ham) beriladigan pulni o‘zingiz tasdiqlay olmaysiz — uni boshqa 2-ro‘yxat xodimi yoki Direktor tasdiqlaydi. Tasdiqlagan
   so‘rovingiz pulini o‘zingiz bermaysiz (qo‘shimcha «kassir» lavozimi bo‘lsa ham).
2. **Kunni tekshirish:** kassir topshirgan KO-4, orderlar va ilovalarni ekrandagi kun bilan solishtiring → «Kassa kunlari» →
   «Tekshirish» → «qog‘oz va ilovalar olindi» belgisi → «Tekshirdim». Kunlar tartib bilan tekshiriladi; kunni yopgan, shu kuni hujjat
   o‘tkazgan yoki bekor qilgan, shu kunning Z-hisobotini kiritgan yoki tuzatgan («Z» tugmasi), shu kungi smena topshirish-qabulida
   qatnashgan va kunni qayta ochgan shaxs tekshira olmaydi — kunni boshqa 2-ro‘yxat xodimi yoki Direktor tekshiradi (tizim sababini
   aytadi). Tekshirilgan kun endi o‘zgarmaydi. Kunda smena topshirilgan bo‘lsa, topshirish-qabul dalolatnomasi (ikkala imzo bilan)
   ham ilovada bo‘ladi.
   **Onlayn kassa Z-hisoboti** kiritilmagan, «yo‘q» deb belgilangan yoki tizimdagi summalar bilan mos kelmasa, oynada qizil
   ogohlantirish chiqadi — qog‘ozdagi Z bilan solishtiring: kassir xato yozgan bo‘lsa, u «Z» tugmasi bilan tuzatadi; haqiqiy farq
   bo‘lsa (masalan, chek urilgan, lekin order bekor qilingan) — sababini izohga yozib tekshirasiz. Kun yopilgandan keyin kiritilgan
   yoki tuzatilgan Z nazorat ro‘yxatida alohida ko‘rinadi — u ham qog‘ozdagi Z bilan solishtiriladi (farq yashirilgan bo‘lishi mumkin).
3. **«Nazorat ro‘yxati»** (shu sahifada): qizil — bugun hal qilinadi (raqamlashda bo‘shliq, yopilmagan kecha, qarorsiz kamomad,
   kechikkan qaytarish, «Moslik» mos emas, Z-hisobot farqi, hisobdorda **manfiy qoldiq** — qaytim yoki hisobot berilgan avansdan
   ko‘p: xato yozuv izi); sariq — shu hafta (shu jumladan yuridik shaxslarga kassadan naqd to‘lovlar — har biri asosli ekanini
   tekshiring; to‘lov paytidagi belgi saqlanadi, kontragent keyin qayta tasniflansa ham ro‘yxatda qoladi; «Z-hisobot kun yopilgandan
   keyin o‘zgartirilgan» — kim va necha marta); «Moslik» qatori doim «hammasi mos» bo‘lishi kerak (xodim qaytargan pul orderi va avans /
   maosh yozuvi ham solishtiriladi). **«Kontragent turi»** (ma’lumot) — oxirgi 30 kunda turi o‘zgargan kontragentlar (kim, qachon,
   eski → yangi) va turi tasdiqlanmagan «jismoniy shaxs» / «boshqa»lar: buxgalter tekshirib «✓ … — Jismoniy shaxs» tugmasi bilan
   tasdiqlaydi; korxona bo‘lsa — tasdiqlamay, turini «Yetkazib beruvchi» / «Tashkilot»ga o‘zgartiradi. Tasdiqlanguncha kontragent
   yuridik shaxs hisoblanadi (kassadan naqd to‘lovga Direktor tasdig‘i). Turni buxgalter o‘zi kiritsa yoki o‘zgartirsa — darhol
   tasdiqlangan; moliya menejeri turini, nomini yoki STIR’ini o‘zgartirsa — tasdiq bekor bo‘ladi. **«Xodimlar zimmasidagi kamomad»** — Direktor qarori bilan xodimga yozilgan kamomad va qoplangani: kassir
   «Kamomadni qoplash (xodim)» bilan qabul qiladi, qolganini ish haqidan ushlash — buxgalter (4-bosqichgacha qo‘lda). Qaror doim
   **xodim kartasiga** yoziladi (avvalgi «boshqa» tomonga yozilgan qarorlar ro‘yxatda «xodim kartasiga bog‘lanmagan» belgisi bilan
   qoladi va kassadan qoplanmaydi). **«Xodim kartasiga bog‘lanmagan kassa hisoblari»** (sariq) — kassir, g‘aznachi, moliya
   menejeri yoki buxgalter hisobi HR yozuviga bog‘lanmagan: kassa hujjatlarida uning ismi foydalanuvchining o‘zi yozgani bo‘ladi va
   kamomad qarorida javobgar o‘zi tanlanmaydi — Direktorga ayting («Foydalanuvchilar» → «Tahrirlash»da bog‘laydi). **«Sanash
   farqlari»** — kunni yopishdagi va smena topshirishdagi kamomad / ortiqcha alohida («yopishda −…, smenada +…»).
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
sanasi). Hisobdorning o‘zi (hisobi xodim kartasiga bog‘langan buxgalter yoki moliya menejeri) o‘z hisobotini kiritmaydi va bekor
qilmaydi — boshqa 2-ro‘yxat xodimi yoki Direktor kiritadi; hisobotni ikkinchi shaxs tasdiqlashi (to‘liq АО-1 tartibi) — 2-bosqichda
(F2.6). Statiya — kassa xarajati (EX), asosiy vosita (OP-18, Dt 0820) yoki sotish uchun tovar (OP-24, Dt 2910); yetkazib beruvchiga
qarz (OP-17) avans hisoboti bilan yopilmaydi — u kassa «Xarajat» orderi yoki bank orqali to‘lanadi. Xarajat «Buxgalteriya»ga o‘zi ko‘chadi, hisobdordagi qoldiq kamayadi; «Avans hisoboti № A-…» chop etiladi va qog‘oz
hisobotga qo‘shiladi. Hisobot qoldiqdan katta bo‘lsa — ortiqcha sarf alohida «Xarajat» orderi bilan beriladi. Xato bo‘lsa — shu kuni
«Naqdsiz dalolatnomalar» ro‘yxatida «Bekor». Qaytim ham qoldiqdan oshmaydi; hisoboti yoki qaytimi yozilgan avans orderi bekor
qilinmaydi (avval hisobot yoki qaytim bekor qilinadi). Manfiy qoldiq (xato yozuv izi) nazorat ro‘yxatida qizil, oylik to‘plamda
(E4) alohida belgi bilan ko‘rinadi. Oldingi avansi hisobotsiz qolgan xodimga yangi avans faqat Direktor tasdig‘i bilan
beriladi. Muddati o‘tgan qoldiqlar nazorat ro‘yxatida ko‘rinadi, «Kassa» sahifasining yuqorisida eslatma chiqadi («Avans hisoboti
muddati o‘tgan hisobdorlar: N ta») va Direktorning Telegram nazorat qatorida ham bo‘ladi.

**O‘quvchi pullari hujjatlarida.** Qaytarish chiqim orderida faktura qismining hisobvarag‘i (4010 — boshlangan davr, 6310 — kelgusi oy)
pul **berilgan** kunga ko‘ra aniqlanadi: so‘rov oy oxirida tasdiqlanib, pul keyingi oyda berilsa, tizim qatorni o‘zi to‘g‘rilaydi (summa va
tasdiq o‘zgarmaydi), kun jurnalida «Qaytarish hisobvarag‘i qayta aniqlandi» yozuvi qoladi. Oflayn navbatda kechagi (hali ochiq) kunda
olingan to‘lov ham kechagi kun oyi bo‘yicha taqsimlanadi. O‘zaro hisob dalolatnomasida o‘quvchining avvalgi avansi fakturaga qo‘llangan
bo‘lsa, kirim orderidagi kabi «ma’lumot uchun» qatori (Dt 6310 Kt 4010) chiqadi — u dalolatnoma summasiga kirmaydi.

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

Kassa to‘xtatilib qayta ishga tushirilgan oyda KO-3 va «Statiyalar»da **«Qayta ishga tushirish farqi»** qatori bor:
davr boshi + kirim − chiqim + farq = davr oxiri. Farq — texnik «Д-» dalolatnoma (to‘xtatilgan davrdagi naqd harakat; kassa
kitobiga kirmaydi): uni nazorat ro‘yxatidagi «Kassani to‘xtatish va qayta ishga tushirish» qatori (to‘xtatilgan davrda kassa
hujjatisiz yozilgan naqd kirim va chiqim) va qog‘oz «Қ» jurnali bilan solishtiring. «Kassa ishga tushishidan oldingi naqd
yozuvlar (keyin kiritilgan)» qatori — Direktor kechikib kiritgan, sanashga kirgan yozuvlar (sanasi kassa birinchi ishga tushgan
kundan oldin): sanash dalolatnomasi bilan solishtiring. «Moslik» qatori kassa ishlagan barcha davrlarni tekshiradi — to‘xtatish va
qayta ishga tushirishdan keyin ham oldingi davr nomuvofiqliklari ko‘rinib turadi.

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
- **Telegram hisoboti:** kassa qatori (kirim, chiqim, qoldiq; sanaldi / farq — kunni yopishdagi va smena topshirishdagi alohida)
  va «Kassa nazorati» qatori (muddati o‘tgan avans ham). Nazorat qatori bo‘sh bo‘lmasa — «Kassa» → «Nazorat ro‘yxati». Dushanba
  kuni — qo‘shimcha «Kassa — o‘tgan hafta» qatori (haftalik ko‘rsatkichlar); batafsil — «Kassa» → «KPI».
- **Tasdiqlash:** T1 dan katta chiqim, rahbar yoki ta’sischiga beriladigan pul, qarz — «So‘rovlar» → «Tasdiqlash».
- **Qaytarish:** «↩ Qaytarish» (sababi, ariza sanasi, usul). Naqd bo‘lsa pulni kassir beradi; balans pul berilganda o‘zgaradi.
  «Avans ham» belgilansa avans ham **naqd beriladi** (bitta chiqim orderida) — tasdiqlashda «qaytarish X + avans Y = jami Z» ko‘rinadi.
  Javob kelmay qayta bosilsa ikkinchi so‘rov yozilmaydi; shu faktura, to‘lov yoki avans bo‘yicha hali berilmagan so‘rovlar bilan jami
  qaytariladigan summadan oshsa — rad etiladi (avval o‘sha so‘rov beriladi yoki bekor qilinadi).
- **Ketgan o‘quvchining avansini naqd qaytarish:** o‘quvchining «📋» (to‘lov / avans tarixi) → «↩ Avansni naqd qaytarish» (yoki faktura
  «↩ Qaytarish» oynasida, usul «Naqd» bo‘lsa, «O‘quvchi avansini naqd qaytarish»): joriy avans ko‘rinadi; summa (standart — butun avans),
  sabab, oluvchi F.I.Sh., ariza sanasi. So‘rov = tasdiq; kassir «Pulni berish» bilan chiqim orderi (Dt 6310, OP-15) yozadi — avans **pul
  berilgan kuni** kamayadi (avans jurnali va qaytarishlar ro‘yxatiga yoziladi). Avans shu orada o‘zgargan bo‘lsa pul berilmaydi — so‘rovni
  bekor qilib, qaytadan tasdiqlang. Faqat naqd va faqat kassa ishga tushgach (naqdsiz — keyingi bosqichda); xarajat sifatida yozilmaydi.
- **O‘zaro hisob:** xodim yozma ariza bilan ish haqidan farzandining o‘quv haqini to‘lasa — «Maosh berish» → «O‘zaro hisob»
  (o‘quvchi, ariza sanasi, summa). Kassadan pul chiqmaydi; dalolatnoma chop etiladi. Xato bo‘lsa — shu kuni «Bekor».

**Faqat Direktor qiladigan amallar**
| Amal | Qayerda | Eslatma |
|---|---|---|
| Kamomad bo‘yicha qaror | «Qarori kutilayotgan kamomadlar» → «Qaror» | oynada kassa egasi (kun kassiri), pulni kim sanagani, kassa egasidan boshqa kassa orderi o‘tkazgan yoki bekor qilgan xodimlar va shu kungi smena topshirishlar ko‘rinadi; xodim hisobiga — faqat **xodim kartasiga**: kassa egasi pulni o‘zi sanagan, kassani olgandan beri kassa orderini undan boshqa hech kim (siz ham, moliya menejeri ham) o‘tkazmagan va bekor qilmagan hamda hisobi kartaga bog‘langan bo‘lsa uning kartasi tanlangan bo‘ladi, aks holda (kassir o‘rniga sanalgan, egasi aniqlanmagan, kassaga boshqa xodim ham tekkan, hisob bog‘lanmagan — sababi oynada yoziladi) javobgar xodimni o‘zingiz tanlaysiz; yoki zararga; dalolatnoma; xodim hisobiga — u pulni kassaga «Kamomadni qoplash (xodim)» bilan qaytaradi (qolgani nazorat ro‘yxatida) |
| Yopilgan kunni qayta ochish | «Kassa kunlari» → «Qayta ochish» | faqat oxirgi, tekshirilmagan kun; sababi yoziladi; qayta ochgan kunni o‘zingiz tekshirmaysiz (2-ro‘yxat tekshiradi) |
| Fiskal cheksiz naqd to‘lov (istisno) | «💵 To‘lov» → «Fiskal cheksiz» | faqat kassa apparati ishlamaganda; jurnalda qoladi |
| 48 soatdan eski oflayn yozuvni kiritish | «💵 To‘lov» | «Қ» blankasi asosida |
| Kassa ishga tushishidan oldingi (yoki kassa to‘xtatilgan davrdagi) kechikib topilgan naqd yozuv | «💵 To‘lov» → «Naqd», «Sana» = pul olingan kun; xarajat, maosh, avans — «Buxgalteriya» oynalarida «Naqd — kassa ishga tushishidan … oldin berilgan» | kirim / chiqim orderisiz va fiskal cheksiz, kassa qoldig‘i o‘zgarmaydi (pul sanashga kirgan); bugungi sana bilan kiritilmaydi — ikki marta hisoblanadi; faqat kassa ishlamagan kun sanasi bilan (birinchi ishga tushgan kundan oldin yoki to‘xtatilgan davrda) — kassa ishlagan kun sanasi bilan tizim qabul qilmaydi; nazorat ro‘yxatida ko‘rinadi (`ishga-tushirish.md`, 4-bo‘lim) |
| Kassani to‘xtatish (orqaga qaytish) | «⚙ Sozlamalar» → «Kassa ishga tushadigan kun»ni bo‘shatish yoki keyinga surish | oldin qurilmalar navbati bo‘shagan, kutilayotgan smena topshirish qabul qilingan yoki bekor qilingan, kun yopilgan, so‘rovlar bajarilgan yoki bekor qilingan bo‘lsin (aks holda tizim rad etib, ro‘yxatini ko‘rsatadi); oxirgi kun «hali o‘tkazilmagan yozuvlar» bilan yopilgan bo‘lsa — kunni qayta oching, navbat o‘tgach qayta yoping (kun tekshirilgan bo‘lsa — navbat tushgan keyingi kunni yoping); oyna oqibatlarini sanab tasdiq so‘raydi; hodisa jurnalga yoziladi (`ishga-tushirish.md`, 9-bo‘lim) |
| Kassani qayta ishga tushirish | «Kassa» → «Qayta ishga tushirish» (komissiya sanagan summa, kun), keyin «⚙ Sozlamalar»da ishga tushadigan kun = o‘sha kun | farq (to‘xtatilgan davrdagi naqd harakat) texnik «Д-» dalolatnoma bilan yoziladi — kamomad / ortiqcha emas; nazorat ro‘yxatida «Kassani to‘xtatish va qayta ishga tushirish»; sanashdan keyin kassa hujjatisiz naqd yozuv kiritilsa — qayta sanash (tizim birinchi kunni ochmaydi, «Kassa»da qizil ogohlantirish) |
| Davr surati va davrni yopish / qayta ochish | «Davr» | yopish — shu sanagacha kassa kunlari yopilgach; qayta ochish — sababi bilan, tarixda qoladi |
| Oldingi avansi hisobotsiz xodimga yangi avans (istisno) | «So‘rovlar» → «Tasdiqlash» | kassa tartibidan istisno; so‘rovda «Direktor tasdig‘i» talabi o‘zi qo‘yiladi |
| Moliya menejeri yoki buxgalterga beriladigan pul (avans, hisobdorga avans) | «So‘rovlar» → «Tasdiqlash» | ular o‘zlariga beriladigan pulni tasdiqlay olmaydi — 2-ro‘yxat bosqichini Direktor imzolaydi (boshqa 2-ro‘yxat xodimi ham tasdiqlay oladi); Direktor tasdig‘i ham kerak bo‘lsa — o‘sha bir tasdiq bilan |
| Yuridik shaxsga kassadan naqd to‘lov | «So‘rovlar» → «Tasdiqlash» | chegara — «⚙ Sozlamalar» (bo‘sh — har doim Direktor); asosiy yo‘l — bank; turi tasdiqlanmagan «jismoniy shaxs» / «boshqa» ham yuridik shaxs hisoblanadi; tur so‘rovdan keyin o‘zgargan bo‘lsa — so‘rov tasdiqda yoki pul berishda Direktorga qaytadi |
| Kontragent turini tasdiqlash (buxgalter ham) | «Nazorat ro‘yxati» → «Kontragent turi» → «✓ …» | «Jismoniy shaxs» / «Boshqa» — faqat haqiqiy fuqaro yoki YaTT; Direktor yoki buxgalter kiritgan / o‘zgartirgan tur darhol tasdiqlangan |
| Sozlamalar, imzo egalari, boshlang‘ich qoldiq | «⚙ Sozlamalar» | chegaralarni faqat Direktor o‘zgartiradi |
| KO-3 va oylik kassa to‘plamining to‘liq (ismli) Excel nusxasi | «Kassa» → «KO-3» → «⬇ Excel»; «Statiyalar» → «⬇ Oylik to‘plam» | boshqalarga ismsiz nusxa chiqadi (FD-28); ismli faylda shaxsiy ma’lumot bor — ehtiyot bilan saqlanadi |

Kassa egasi (kun kassiri) yo‘qligida kunni boshqa kassir, Direktor yoki moliya menejeri yopishi, smenani — boshqa kassir yoki
Direktor topshirishi mumkin — kamida 2 kishilik komissiya bilan (kassir o‘rniga; dalolatnomada kassa egasi va pulni sanagan xodim
alohida ko‘rinadi). Smena topshirish qabul qilinmay qolsa (qabul qiluvchi kelmadi) — «Kassa»dagi kartada «Bekor qilish».

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
