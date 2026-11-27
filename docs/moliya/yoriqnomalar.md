# «Kassa» bo‘limi: rol bo‘yicha qisqa yo‘riqnomalar (F1.19)

O‘qitishda (sinov stendida) tarqatiladi — 14-dekabrgacha (o‘qitish jadvali taklifi — `ishga-tushirish.md`, 1-bo‘lim); har bo‘lim — bir varaq. Bo‘lim «Moliya» → «Kassa» da. Tugma nomlari ekrandagidek.
Istisno: 6-bo‘lim (qabulxona) hamda 3-bo‘limdagi «Ota-ona kodi» va «Xodim kartasi ↔ login va o‘z maoshi» paragraflari 16-noyabr
haftasidagi yangilanish kuni beriladi (o‘qitishni kutmaydi; deploy chiqishida «… ta maosh vedomosti qatori … Direktor tasdig‘iga
o‘tkazildi» qatori bo‘lsa — Direktor o‘sha qatorlarni pul berilishidan oldin ko‘radi).
Hujjat raqamlari: **K-** kirim orderi (KO-1), **Ch-** chiqim orderi (KO-2), **D-** naqdsiz dalolatnoma (boshlang‘ich qoldiq,
kamomad qarori), **O‘H-** o‘zaro hisob dalolatnomasi, **A-** avans hisoboti (chop etishda kirillcha: К-, Ч-, Д-, ЎҲ-, А-). Har
turning o‘z raqami bor; raqamni tizim beradi, har yili 1 dan boshlanadi, bo‘shliq va takror bo‘lmaydi. To‘liq tartib: `docs/moliya/ishga-tushirish.md`; shakllar: `docs/moliya/shakllar.md`.

**Hamma uchun umumiy qoidalar**
1. Har kim faqat **o‘z hisobi** bilan ishlaydi; parol boshqaga berilmaydi (hujjatda kim yozgani, tasdiqlagani va pul bergani qoladi).
2. **Pul hujjatsiz olinmaydi va berilmaydi:** avval tizimda order, keyin pul. Chiqim — faqat tasdiqdan keyin.
3. Sana va raqamni tizim qo‘yadi; hujjat faqat **bugungi ochiq kunga** yoziladi.
4. Yozilgan hujjat o‘chirilmaydi va o‘zgartirilmaydi — xato bo‘lsa shu kuni **bekor qilinadi** (raqami saqlanadi) va to‘g‘risi yoziladi.
5. Bankka topshirilgan va bankdan olingan pul — kirim ham, xarajat ham emas (alohida operatsiya).
6. Javob kelmay qolgan oynada **ma’lumotni o‘zgartirib qayta yubormang**: shu oynadan avval boshqa ma’lumot (summa, tomon, asos,
   fiskal chek…) bilan yozilgan bo‘lsa, tizim «Bu oynadan avval boshqa ma’lumot bilan … yozilgan» deb rad etadi va ro‘yxatni
   yangilaydi — yozilgan hujjatni tekshiring; xato bo‘lsa uni bekor qilib, yangi oynada to‘g‘risini kiriting.
7. **Summa yozish** («Kassa» oynalari, «💵 To‘lov», «Buxgalteriya» xarajat va avans, «Maosh berish»): summa butun so‘mda, mingliklar
   orasida bo‘sh joy mumkin («2 900 000»); tiyin yozilmaydi (naqd pulda tiyin yo‘q; oxiridagi «,00» — mumkin). Nuqta yoki vergul
   mingliklar ajratkichi sifatida («2.900.000», «2,900,000») qabul qilinmaydi — tizim xabar beradi (raqam jim o‘zgarib ketmaydi).
   Rad etilgan amalda tizim sababini o‘zbekcha aytadi.

---

## 1. Kassir (G‘aznachi lavozimi) va kassir o‘rinbosari

Kassir — **G‘aznachi** lavozimidagi xodim, tizimda **«Kassir»** roli bilan ishlaydi. U kassa egasi: kirim («💵 To‘lov», «+ Kirim») va chiqim
(«+ Chiqim so‘rovi» → tasdiq → «Pulni berish») hujjatlarini yozadi, kunni ochadi (birinchi hujjat bilan) va yopadi, kunlik hisobotni
tayyorlaydi («🖨 Kunlik hisobot», «🖨 KO-4»). O‘rinbosar — buyruq bilan tayinlangan xodim: o‘z roliga qo‘shimcha «Kassir» roli
beriladi, kassada «Kassir» rolida ishlaydi (sarlavhada «Rol: … ▾» bo‘lsa — undan «Kassir»ni tanlab). «G‘aznachi» tizim roli kassa xodimiga berilmaydi (unda
moliya huquqlari bor) — hisobingizda shu rol bo‘lsa, Direktorga ayting. Naqd pulni faqat shu ikkisi oladi va beradi (Direktor —
faqat favqulodda holatda). Kassa ish kunlari — dushanba–juma (shanba, yakshanba va bayram kunlari yopiq).

**Ertalab.** «Kassa» sahifasini oching. Yuqorida kun kartasi: kun boshi, kirim, chiqim, kassadagi qoldiq va kassa egasi
(«kassir: …» — shu kuni birinchi kassa hujjatini yozgan kassir; smena qabul qilinsa — qabul qiluvchi). Qizil eslatma bo‘lsa —
avval uni bajaring. **Kecha yopilmagan bo‘lsa, bugun hujjat yozilmaydi** — avval kechagi kunni sanab yoping.

**Naqd o‘quv to‘lovi** (kassa ishga tushgan kundan):
1. Onlayn kassa apparatida (NKM) fiskal chek uring — chek to‘lovchiga beriladi.
2. «To‘lovlar» → «💵 To‘lov»: o‘quvchi, summa, to‘lovchi, **«Fiskal chek №»** (majburiy), usul — naqd → saqlash.
3. «🖨 Kirim orderi va patta»: patta — to‘lovchiga, order — kassada (imzo qo‘yiladi).
Bir nechta farzand uchun to‘lansa — **har o‘quvchiga alohida fiskal chek** uriladi va har to‘lov o‘z chek raqami bilan kiritiladi
(bitta chek raqami ikkinchi to‘lovda qabul qilinmaydi; raqamga belgi qo‘shib kiritmang — FD-49).
Tizim to‘lovni rad etsa (masalan, chek raqami takror) — oyna ochiq qoladi: ma’lumotni tuzatib, o‘sha oynada (o‘sha o‘quvchi uchun)
«Qabul qilish»ni qayta bosing — rad etilgan yozuv navbatdan almashtiriladi. Oyna yopilsa yoki boshqa o‘quvchi tanlansa, rad etilgan
yozuv ⏳ navbatda «Yuborilmadi» bo‘lib qoladi (kunni yopishda tanlanadi).
Tizim summani o‘zi taqsimlaydi: avval eng eski qarz, ortig‘i — avansga. Naqdsiz to‘lov (Click, terminal, bank) ham shu oynada
kiritiladi, lekin kassa orderi yozilmaydi va kassa qoldig‘iga kirmaydi. Kassa ishga tushgach naqd o‘quv to‘lovi **faqat shu oyna**
orqali yoziladi (kirim orderi va fiskal chek bilan): boshqa yo‘l bilan (to‘lov yozuvini to‘g‘ridan-to‘g‘ri kiritish yoki «naqd»ga
o‘zgartirish, «naqd» kanal bilan balansga qo‘llash) tizim qabul qilmaydi — Direktorga ham.

**To‘lov yozuvidagi «[kod]».** «To‘lovlar»da Click / Uzum to‘lovchisi yozgan matnda «[kod]» ko‘rinsa — bu ota-onaning yashirilgan
maxfiy kodi (kod to‘lov yozuvlarida ko‘rsatilmaydi). Yashirish biriktirishga ta’sir qilmaydi: kod to‘g‘ri bo‘lsa va matnda boshqa
o‘quvchining ID si yoki kodi bo‘lmasa, to‘lov o‘quvchiga avtomatik biriktiriladi. «⚠️ Biriktirilmagan to‘lovlar»da «[kod]» bo‘lsa — kodni hech kim (Direktor ham) ko‘rmaydi: to‘lovni
matndagi ID, ism yoki telefon bo‘yicha odatdagidek qo‘lda biriktiring («Biriktirish»); aniqlab bo‘lmasa — to‘lovchiga telefon
qiling yoki Direktorga ayting. Ota-ona kodni so‘rasa — qabulxonaga yuboring (6-bo‘lim).

**Boshqa kirim** — «+ Kirim»: operatsiya tanlanadi («Bankdan naqd», «Hisobdordan qaytim», «Xodim qaytargan pul», «Kamomadni
qoplash (xodim)», «Forma va tovarlar», «Boshqa kirim», «Qarz / ta’sischi mablag‘i» — bunisi Direktor tasdig‘i bilan), **kimdan**
(ro‘yxatdan tanlanadi), summa, asos (hujjat nomi, raqami, sanasi) → «Qabul qilish» → chop etish. «Boshqa kirim»da pul **o‘quvchi
(ota-ona) yoki boshqa shaxsdan** bo‘lsa — onlayn kassada fiskal chek uriladi va **«Fiskal chek №»** kiritiladi (majburiy; apparat
ishlamasa — Direktor istisnosi, jurnalda qoladi); kontragent yoki xodimdan — talab qilinmaydi. Summa T1 chegarasidan katta bo‘lsa,
tizim «… so‘m qabul qilinsinmi?» deb so‘raydi — raqamni qayta tekshiring.

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
   Ro‘yxatda yo‘q tashkilotga («Boshqa» tomon) **asos hujjati bilan** xarajat ham yuridik shaxsga to‘lov hisoblanadi (xuddi shu
   ogohlantirish va Direktor tasdig‘i) — imkon bo‘lsa kontragentni qo‘shing; bozordan asos hujjatisiz xarid — «Asos hujjati yo‘q»
   belgisi bilan (ogohlantirishsiz).
   **Ishdan ketgan xodimga** (ro‘yxatda «(ketgan)») yangi ish haqi avansi va hisobdorga avans berilmaydi — tizim rad etadi; yakuniy
   hisob-kitob (naqd maosh, «Xodim qaytargan pul», «Hisobdordan qaytim», avans hisoboti) — mumkin. Xodim ketgunicha tasdiqlangan,
   lekin pul berilmagan avans so‘rovi ham berilmaydi — uni bekor qiling.
   Yangi kontragent («+ yangi») turini to‘g‘ri tanlang: korxona (MChJ, AJ) — «Yetkazib beruvchi» yoki «Tashkilot». «Jismoniy shaxs» va
   «Boshqa» turini buxgalter (yoki Direktor) tasdiqlaydi — ungacha kontragent yuridik shaxs hisoblanadi (ro‘yxatda «turi tasdiqlanmagan»).
2. Moliya menejeri yoki buxgalter tasdiqlaydi (katta summa, rahbarga berish va qarz — Direktor ham).
3. «So‘rovlar» ro‘yxatida «Pulni berish» → «🖨 Chiqim orderi» → oluvchi «Oldim» deb summa (so‘z bilan), sana va imzo qo‘yadi;
   shaxsini tasdiqlovchi hujjat ma’lumoti yoziladi. Kassada pul yetmasa tizim chiqimga yo‘l qo‘ymaydi. So‘rovni o‘zi tasdiqlagan xodim
   (masalan, qo‘shimcha «Kassir» roli bo‘lgan moliya menejeri) uning pulini bermaydi — boshqa kassir beradi. O‘zingizga (hisobingiz
   bog‘langan xodim kartasiga) boshqa xodim tasdiqlagan avans yoki hisobdorga avansni o‘zingiz berasiz — 2-ro‘yxat tasdig‘i bor, kunni
   boshqa xodim tekshiradi. Direktorga beriladigan pulni (FD-48) va qaytarishni ham kassir beradi. Tasdiqdan keyin kontragent
   turi o‘zgargan bo‘lsa (endi yuridik shaxs hisoblansa) yoki chegara pasaytirilgan bo‘lsa pul berilmaydi: so‘rov o‘zi Direktor
   tasdig‘iga qaytadi (qizil xabar) — Direktor tasdiqlagach pulni bering.

**Maosh.** «Maosh» sahifasida «Maosh berish» → usul «Naqd» → chiqim orderi o‘zi yoziladi. Faqat tasdiqlangan vedomost chegarasida.
Naqd maoshni faqat kassir beradi — vedomost bo‘yicha har kimga, o‘zingizga ham (Direktor o‘z maoshini naqd o‘zi olmaydi — uni ham
kassir beradi). **Ish haqi avansi** — «+ Chiqim so‘rovi» orqali (yuqoridagi uch qadam).

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
yoki Direktor «Bekor qilish» bilan qaytarib oladi. Topshirish 2 soatdan ortiq yoki ertasi kungacha qabul qilinmay qolsa — nazorat
ro‘yxatida «Qabul qilinmagan smena topshirish» (sariq) va Direktorning Telegram nazorat qatorida ko‘rinadi; boshqa kuni yozilgan
topshirish kartasida sanasi ham chiqadi. Dalolatnomada sanash va qabul qilish vaqti alohida yoziladi. Kassa egasi (kun kartasidagi kassir) yo‘q bo‘lsa, uning o‘rniga boshqa kassir
yoki Direktor topshiradi — kamida 2 kishilik komissiya bilan.

**Kechqurun.** Avval onlayn kassada (NKM) smenani yopib **Z-hisobot** chiqaring (karta terminali shu NKM da — bitta Z-hisobotda naqd
va karta birga). «Kunni yopish»: kassadagi pulni sanang va
**sanalgan summani** kiriting (nominallar bo‘yicha ham mumkin); pastda **Z-hisobot №** va undagi **sotuv jamlari** — naqd va bank
kartasi (qaytarishlarsiz) → «Sanab yopish». Tizim Z ni fiskal chekli kirim orderlari va terminal to‘lovlari bilan solishtiradi va
natijani aytadi; farq bo‘lsa buxgalter sababini so‘raydi. Z-hisobot qo‘lda bo‘lmasa — «Z-hisobot yo‘q» (sababi bilan), keyin
«Kassa kunlari» qatoridagi **«Z»** tugmasi bilan kiriting (xato yozilgan bo‘lsa ham shu tugma bilan — kun tekshirilguncha). Sanashda
farq bo‘lsa tizim shu kunga kamomad yoki ortiqcha hujjatini o‘zi yozadi — sababini izohga yozing. Keyin «🖨 KO-4» (2 nusxa) va
«🖨 Kunlik hisobot»ni imzolang: KO-4 ning 2-nusxasini orderlar, ilovalari va Z-hisobot bilan buxgalterga (kunni u tekshiradi),
kunlik hisobotni moliya menejeriga topshiring. Kunni **kassa egasi** (kun
kartasidagi kassir) yopadi; boshqa kassir uning o‘rniga yopsa — kamida 2 kishilik komissiya bilan (yoki avval smena topshiriladi).

**Kunni yopishda qurilma navbati va «Қ» blankalari.** Oyna ochilishidan oldin tizim shu qurilma navbatini (⏳) yuboradi;
yuborilmay qolganlari oynada ko‘rinadi va «hali o‘tkazilmagan yozuvlar» bo‘lib o‘zi hisobga olinadi — qo‘lda kiritmang. Navbat
boshqa qurilmada bo‘lsa — avval o‘sha qurilmani internetga ulang. Smena topshirishda e’lon qilingan, hali kelmagan yozuvlar oynada
alohida qatorda — ularni tizim o‘zi hisobga oladi (sanalgan pulga sig‘ganicha; sig‘magani farqda ayirilmaydi — oyna aytadi).
Navbatdagi to‘lovni yangi kalit bilan qayta kiritmang (qurilma yo‘qolgan bo‘lsa — Direktorga ayting). Kassaga tegishli bo‘lmagan
pul bilan rad etilgan navbat yozuvi (kassa ishga tushishidan oldingi pul) hisobga olinmaydi — oynada soni ko‘rinadi, ⏳ navbatda
ko‘ring. Boshqa sabab bilan rad etilgan («Yuborilmadi») yozuvlar oynada alohida, tizim xatosi bilan: har biri uchun tanlang —
pul kassada (qayta kiritilmagan) bo‘lsa **«Pul kassada — hisobga olinsin»**, to‘g‘ri ma’lumot bilan qayta kiritilgan yoki pul
qaytarilgan bo‘lsa **«Qayta kiritilgan yoki pul qaytarilgan — navbatdan o‘chirilsin»** (kun yopilgach / smena topshirilgach
o‘chiriladi); tanlanmaguncha oyna saqlamaydi, farq tanlovga qarab ko‘rinadi. Sinov kassasida navbat ko‘rsatilmaydi va e’lon
qilinmaydi — navbatdagi o‘quv to‘lovlari asosiy kassaga tushadi. «Kassa qoldig‘i oyna ochilgandan keyin o‘zgargan» xabari
chiqsa — oyna yangilanadi: pulni qayta sanab, yana yuboring (smena topshirishda ham). Natija xabarida tizim hisoblagan farq aytiladi.
**Server ishlamagan kunni** (ertasi kuni) yopayotgan bo‘lsangiz — hali kiritilmagan «Қ» blankalarini **«Server ishlamagan paytdagi
«Қ» blankalari»** maydonlariga yozing (soni, summasi, raqamlari): bu pul kassada bor, hisobda hali yo‘q. Kun yopilgach har birini
«💵 To‘lov» bilan kiriting (izohda — «Қ» raqami va pul olingan sana).

**Chop etish.** Orderning va KO-4 varag‘ining asl nusxasini kassir (yoki Direktor) chop etadi; buxgalter yoki moliya menejeri chop
etsa — doim «НУСХА» (asl nusxa hali chop etilmagan bo‘lib qoladi).

**Oy oxiri** — «KO-3» (kassa orderlari jurnali) va «Statiyalar» (oylik statiya matritsasi): oyni tanlab ko‘ring va chop eting
(«🖨 KO-3», «🖨 Chop etish»). Excel fayllar sizda yo‘q — ularni moliya menejeri, buxgalter yoki Direktor oladi. «Kassir»
rolida ochiladigan «Xodimlar davomati» → «Oylik hisobot» → «🖨 PDF / Hisobot» sizda ismsiz chiqadi (xodim — maosh ID va kamera
ID bilan; ismli nusxa — Direktor va HR’da; FD-28).

**Internet yoki tizim ishlamasa** — `ishga-tushirish.md`, 8-bo‘lim («Қ» blankasi to‘lovchiga berilmaydi; dalil — fiskal chek).
Internet uzilganda NKM oflayn chek rejimida ishlaydi. **NKM buzilsa** — soliq organida ro‘yxatdan o‘tgan maxsus kvitansiya daftari
(kassada); bunday to‘lovni tizimga Direktor «Fiskal cheksiz (istisno)» belgisi bilan kiritadi.
Kun yopilgandan keyin navbatda qolgan to‘lov «Navbatda · …» bo‘lib kutadi va keyingi kassa kuniga «kech» bo‘lib o‘zi o‘tadi —
o‘chirmang va qayta kiritmang. U faqat sahifa ishlatilayotganda yuboriladi (kechasi ochiq qolgan sahifa kassa kunini o‘zi ochmaydi):
ertalab sahifada biror joyni bosing. «Yuborilmadi — Direktor hal qiladi» yozuvini qayta yubormang — Direktorga ayting.

**Kassa ishga tushishidan oldingi pul.** Boshlang‘ich qoldiq sanashidan (30-dekabr kechqurun) oldin qurilmangiz internetga ulangan
va navbati (⏳) bo‘sh bo‘lsin. **31-dekabr kassa naqd pul qabul qilmaydi va bermaydi** (Click, Uzum, bank ishlaydi); istisno bo‘lsa —
eski qog‘oz order, tizimga o‘sha kuni kiriting va Direktorga ayting (4-yanvar ertalab pul qayta sanaladi). 1–3-yanvar kassa yopiq.
**4-yanvar ertalab** birinchi kassa hujjatini Direktor qayta sanash (kerak bo‘lsa) va «31-dekabr holati» suratini tugatganini
aytmaguncha yozmang. Ishga tushish kunidan oldin olingan pulni keyin **bugungi sana bilan qayta kiritmang** — u sanashga kirgan,
ikki marta hisoblanadi: bugungi sana bilan kiritilgan to‘lovni tizim oddiy bugungi to‘lov deb qabul qiladi (kirim orderi
yoziladi), farqini bilmaydi. Navbatda qolib ketgan yozuv internet qaytganda o‘zi o‘tadi (48 soatgacha;
kirim orderisiz); undan eskisini yoki qog‘ozda topilganini Direktor haqiqiy sanasi bilan kiritadi. Kassa to‘xtatilgan bo‘lsa
(«Kassa to‘xtatilgan» ogohlantirishi) — kassa hujjati (kirim, chiqim so‘rovi) yozilmaydi, tizim rad etadi; pul «Қ» blankalari bilan (o‘z raqamlari bilan) qabul
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

**To‘lovchi matnidagi «[kod]»** (moliya menejeri; buxgalter bu matnni ko‘rmaydi). Click / Uzum to‘lovida to‘lovchi yozgan matnda
(ism, «sinf», izoh) «[kod]» — ota-onaning yashirilgan maxfiy kodi (kod to‘lov yozuvlarida, eskilarida ham, ko‘rsatilmaydi).
Yashirish biriktirishga ta’sir qilmaydi: kod to‘g‘ri bo‘lsa va matnda boshqa o‘quvchining ID si yoki kodi bo‘lmasa, to‘lov
o‘quvchiga avtomatik biriktiriladi. «⚠️ Biriktirilmagan to‘lovlar»da
«[kod]» bo‘lsa — kodni hech kim (Direktor ham) ko‘rmaydi: to‘lovni matndagi ID, ism yoki telefon bo‘yicha odatdagidek qo‘lda
biriktiring («Biriktirish»); aniqlab bo‘lmasa — to‘lovchiga telefon qiling yoki Direktorga ayting. Ota-ona kodni so‘rasa —
qabulxonaga (6-bo‘lim).

**Vazifalar taqsimoti (egasi, 2026-11-16).** Chiqim so‘rovlarini asosan **moliya menejeri** tasdiqlaydi; yopilgan kunni tekshirish
(«Tekshirdim») va avans hisobotlarini kiritish — **buxgalterda**. Biri yo‘q kuni ikkinchisi o‘rnini bosadi; ikkalasi ham telefondan
tasdiqlay oladi. Ikkalasi ham yo‘q kuni oddiy chiqim tasdiqlanmaydi — Direktor 2-ro‘yxat o‘rniga tasdiqlay olmaydi.

**Har kuni**
1. **Chiqim so‘rovlarini tasdiqlash:** «Kassa» → «So‘rovlar» → «Ko‘rish»: oluvchi, statiya, asos hujjati to‘g‘rimi → «Tasdiqlash»
   yoki «Rad etish» (sababi). O‘zingiz yuborgan so‘rovni va o‘zingizga (hisobingiz bog‘langan xodim kartasiga, ikkinchi lavozim
   kartasi ham) beriladigan pulni o‘zingiz tasdiqlay olmaysiz — uni boshqa 2-ro‘yxat xodimi yoki Direktor tasdiqlaydi. Tasdiqlagan
   so‘rovingiz pulini o‘zingiz bermaysiz (qo‘shimcha «Kassir» roli bo‘lsa ham).
2. **Kunni tekshirish:** kassir topshirgan KO-4, orderlar va ilovalarni ekrandagi kun bilan solishtiring → «Kassa kunlari» →
   «Tekshirish» → «qog‘oz va ilovalar olindi» belgisi → «Tekshirdim». Kunlar tartib bilan tekshiriladi; kunni yopgan (qayta ochilishidan
   oldin yopgan ham), shu kuni hujjat
   o‘tkazgan yoki bekor qilgan, shu kunning Z-hisobotini kiritgan yoki tuzatgan («Z» tugmasi), shu kungi smena topshirish-qabulida
   qatnashgan va kunni qayta ochgan shaxs tekshira olmaydi — kunni boshqa 2-ro‘yxat xodimi yoki Direktor tekshiradi (tizim sababini
   aytadi). Tekshirilgan kun endi o‘zgarmaydi. Kunda smena topshirilgan bo‘lsa, topshirish-qabul dalolatnomasi (ikkala imzo bilan)
   ham ilovada bo‘ladi.
   **Hali o‘tkazilmagan yozuvlar** bilan yopilgan kunda (qurilma navbati yozuvining kech kirim orderi hali kelmagan yoki server
   ishlamagan paytdagi «Қ» blankalari) oynada qizil blok chiqadi: kassir bilan aniqlang — navbat yuborilmaganmi (qurilma internetga
   ulansin), «Қ» yozuvlari kiritilganmi (izohida «Қ» raqami; blanka raqamlari oynada) — va sababini izohga yozing (majburiy).
   Navbat yozuvi kelgach (kech kirim orderi o‘sha kun bilan bog‘lanadi) izoh talab qilinmaydi.
   **Onlayn kassa Z-hisoboti** kiritilmagan, «yo‘q» deb belgilangan yoki tizimdagi summalar bilan mos kelmasa, oynada qizil
   ogohlantirish chiqadi — qog‘ozdagi Z bilan solishtiring: kassir xato yozgan bo‘lsa, u «Z» tugmasi bilan tuzatadi; haqiqiy farq
   bo‘lsa (masalan, chek urilgan, lekin order bekor qilingan) — sababini izohga yozib tekshirasiz. Kun yopilgandan keyin kiritilgan
   yoki tuzatilgan Z nazorat ro‘yxatida alohida ko‘rinadi — u ham qog‘ozdagi Z bilan solishtiriladi (farq yashirilgan bo‘lishi mumkin).
   Kech kirim orderi (oflayn chek) pul olingandan keyin yopilgan birinchi kunning Z i bilan solishtiriladi (odatda — pul olingan kun).
   Server ishlamagan kunda («Қ» blankalari bilan yopilgan) Z farqi «+», «Қ» yozuvlari kiritilgan kunda — xuddi shuncha «−»: «Қ»
   blankalarini kiritilgan orderlar bilan solishtiring va ikkala kunda izohga «Қ» raqamlarini yozing.
3. **«Nazorat ro‘yxati»** (shu sahifada): qizil — bugun hal qilinadi (raqamlashda bo‘shliq, yopilmagan kecha, qarorsiz kamomad,
   kechikkan qaytarish, «Moslik» mos emas, Z-hisobot farqi, hisobdorda **manfiy qoldiq** — qaytim yoki hisobot berilgan avansdan
   ko‘p: xato yozuv izi); sariq — shu hafta (shu jumladan yuridik shaxslarga kassadan naqd to‘lovlar, asos hujjati bilan «boshqa»
   tomonga to‘lovlar ham — har biri asosli ekanini
   tekshiring; to‘lov paytidagi belgi saqlanadi, kontragent keyin qayta tasniflansa ham ro‘yxatda qoladi; «Z-hisobot kun yopilgandan
   keyin o‘zgartirilgan» — kim va necha marta); «Moslik» qatori doim «hammasi mos» bo‘lishi kerak (xodim qaytargan pul orderi va avans /
   maosh yozuvi ham solishtiriladi). **«Kontragent turi»** (ma’lumot) — oxirgi 30 kunda turi o‘zgargan kontragentlar (kim, qachon,
   eski → yangi; tasdiqlangan bo‘lsa — kim tasdiqlagani) va turi tasdiqlanmagan «jismoniy shaxs» / «boshqa»lar: buxgalter tekshirib
   «✓ … — Jismoniy shaxs» tugmasi bilan tasdiqlaydi; korxona bo‘lsa — tasdiqlamay, turini «Yetkazib beruvchi» / «Tashkilot»ga o‘zgartiradi. Tasdiqlanguncha kontragent
   yuridik shaxs hisoblanadi (kassadan naqd to‘lovga Direktor tasdig‘i). Turni buxgalter o‘zi kiritsa yoki o‘zgartirsa — darhol
   tasdiqlangan; moliya menejeri turini, nomini yoki STIR’ini o‘zgartirsa — tasdiq bekor bo‘ladi. **«Xodimlar zimmasidagi kamomad»** — Direktor qarori bilan xodimga yozilgan kamomad va qoplangani: kassir
   «Kamomadni qoplash (xodim)» bilan qabul qiladi, qolganini ish haqidan ushlash — buxgalter (4-bosqichgacha qo‘lda). Qaror doim
   **xodim kartasiga** yoziladi (avvalgi «boshqa» tomonga yozilgan qarorlar ro‘yxatda «xodim kartasiga bog‘lanmagan» belgisi bilan
   qoladi va kassadan qoplanmaydi). **«Xodim kartasiga bog‘lanmagan kassa hisoblari»** (sariq) — «Kassir» (qo‘shimcha rol bo‘lsa
   ham), «G‘aznachi», moliya menejeri yoki buxgalter rolidagi hisob HR yozuviga bog‘lanmagan: kassa hujjatlarida uning ismi foydalanuvchining o‘zi yozgani bo‘ladi va
   kamomad qarorida javobgar o‘zi tanlanmaydi — Direktorga ayting («Foydalanuvchilar» → «Tahrirlash»da bog‘laydi). **«Sanash
   farqlari»** — kunni yopishdagi va smena topshirishdagi kamomad / ortiqcha alohida («yopishda −…, smenada +…»). **«Hali kelmagan
   «hali o‘tkazilmagan» yozuvlar»** (sariq) — kunni yopishda e’lon qilingan qurilma navbati yozuvining kech kirim orderi 2 kun
   (48 soat) ichida kelmagan (kun, soni, summasi; navbat yo‘qolgan, o‘chirilgan yoki yozuv o‘ylab topilgan bo‘lishi mumkin — kassir
   bilan aniqlang) va tekshirilmagan kunlarning «Қ» blankalari. **«Qabul qilinmagan smena topshirish»** (sariq) — topshirish o‘tgan
   kassa kunida yoki 2 soatdan ortiq qabul qilinmay turibdi (kimdan → kimga, sanalgan summa, qachondan): qabul qiluvchi qabul qilsin
   yoki topshiruvchi / Direktor bekor qilsin.
4. **Bank orqali to‘langan xarajatlar** (moliya menejeri) — «Buxgalteriya» → «+ Xarajat qo‘shish»: to‘lov usuli (bank o‘tkazmasi
   yoki korporativ karta), statiya, kontragent. Hisobdor shaxs sarflagan pul bu yerda emas — «Kassa» → «Avans hisoboti».
   Naqd xarajat bu yerda yozilmaydi — u kassa chiqim orderidan o‘zi ko‘chadi. Kassa **to‘xtatilgan** (yoki qayta ishga tushirish
   kunini kutayotgan) paytda xarajat, maosh va avans oynalarida ham to‘lov usuli tanlanadi: bank / karta — istalgan sana bilan; naqd —
   faqat to‘xtatilgan davr sanasi bilan (orderisiz; usulsiz yozuv naqd hisoblanadi).
   Yangi kontragent qo‘shilganda xuddi shu tur, nom va STIR bilan faol kontragent bo‘lsa, yangisi yaratilmaydi — o‘shasi tanlanadi.

**Maosh.** Vedomostni moliya menejeri tayyorlaydi, HR tasdiqlaydi. Karta orqali to‘lovni moliya menejeri «Maosh berish» → «Karta»
bilan yozadi (kassa orderisiz); naqd — faqat kassir. Xodim avansni kassaga qaytarsa (kassir — «Xodim qaytargan pul», OP-08),
vedomost avansni bazadan qaytgani ayirilgan holda oladi — vedomostni qaytimdan keyin tayyorlang (yuborilgan bo‘lsa — HR qaytaradi,
qayta yuboring); tasdiqlangan oy uchun avans qaytimi qabul qilinmaydi. Berilgan maosh qaytsa (OP-09) — shu oy berilgan summa
kamayadi: qolgani shu oy yana berilishi yoki keyingi oyga qoldiq bo‘lib o‘tishi mumkin.

**Hisobdorlar.** Pul «Hisobdorga avans» bilan beriladi (bu xarajat emas); so‘rovda **avans maqsadini** (taxminiy statiya, masalan «Kanselyariya») ko‘rsatish mumkin — avans hisobotida qator statiyasi shundan taklif qilinadi. Hisobdor 3 ish kuni (shanba, yakshanba va «Bayram / ta’til kunlari» sanalmaydi) ichida avans hisobotini (qog‘oz, `shakllar.md` Sh-1) cheklari bilan topshiradi; qaytim — «+ Kirim» → «Hisobdordan qaytim». Buxgalter (yoki moliya menejeri) hisobotni tekshiradi va **«Kassa» → «Avans hisoboti»**ga kiritadi: hisobdorni tanlaydi (oynada uning yopilmagan avanslari va maqsadi ko‘rinadi), har chek — bitta qator (statiya, summa, chek raqami va sanasi), «Tasdiqqa yuborish». Hisobot **tasdiq kutadi**: uni kirituvchidan boshqa 2-ro‘yxat xodimi (buxgalter / Moliya menejeri) yoki Direktor «Kassa» → so‘rovlar jadvalida yoki «Tasdiqlash» bo‘limida qog‘ozdagi hisobot va cheklar bilan solishtirib tasdiqlaydi — shunda hisobot o‘tkaziladi («Avans hisoboti № A-…»), xarajat «Buxgalteriya»ga ko‘chadi, hisobdordagi qoldiq kamayadi; hujjat chop etilib qog‘oz hisobotga qo‘shiladi (unda kim kiritgani va kim tasdiqlagani yoziladi). Xato bo‘lsa — tasdiqlovchi rad etadi (sababi bilan) yoki kirituvchi bekor qiladi. Bir hisobdorda bir vaqtda bitta tasdiq kutayotgan hisobot bo‘ladi. Hisobot kiritilgandan keyin hisobdorga yangi avans berilgan yoki undan qaytim olingan bo‘lsa, tasdiq rad etiladi — hisobot bekor qilinib, qayta kiritiladi. Hisobdorning o‘zi (hisobi xodim kartasiga bog‘langan buxgalter yoki moliya menejeri) o‘z hisobotini kiritmaydi, tasdiqlamaydi va bekor qilmaydi. Statiya — kassa xarajati (EX), asosiy vosita (OP-18, Dt 0820) yoki sotish uchun tovar (OP-24, Dt 2910); yetkazib beruvchiga qarz (OP-17) avans hisoboti bilan yopilmaydi — u kassa «Xarajat» orderi yoki bank orqali to‘lanadi.

**Ortiqcha sarf.** Hisobot hisobdordagi qoldiqdan katta bo‘lsa (hisobdor o‘z pulidan qo‘shgan), oyna buni ko‘rsatadi va so‘raydi: qoldiq qatorlarga tartib bilan yopiladi, qolgani — **hisobdorga qarzimiz** (6970). Tasdiqdan keyin kassir **«+ Chiqim so‘rovi» → «Ortiqcha sarfni qoplash»** bilan pulni beradi: oynada qarz ko‘rinadi va summa to‘ldiriladi; summa qarzdan oshmaydi; so‘rovni 2-ro‘yxat tasdiqlaydi. Qarz nazorat ro‘yxatida («Hisobdorlarga qarzimiz») ko‘rinadi. Ortiqcha sarfi qoplangan hisobot bekor qilinmaydi — avval qoplash orderi bekor qilinadi. Avansi umuman yo‘q xodimga hisobot kiritilmaydi.

**Hisobdorlar kartochkasi (RP-07).** «Kassa» → «Hisobdorlar»: qoldig‘i (4230), qarzimiz (6970) yoki tasdiq kutayotgan hisoboti bor xodimlar — eng eski yopilmagan avans sanasi va yoshi (ish kunlarida; 3 kundan oshsa — «muddati o‘tgan»). «Kartochka» — yopilmagan avanslar (qaytim va hisobotlar eng eski avansdan boshlab yopadi; maqsadi bilan), barcha hujjatlar (avans, qaytim, avans hisoboti, ortiqcha sarfni qoplash) — har birining 4230 / 6970 ga ta’siri va ketma-ket qoldiq; «🖨 Chop etish» (xodim bilan solishtirish va imzo uchun).

Xato bo‘lsa — shu kuni «Naqdsiz dalolatnomalar» ro‘yxatida «Bekor». Qaytim ham qoldiqdan oshmaydi; hisoboti yoki qaytimi yozilgan avans orderi bekor qilinmaydi (avval hisobot yoki qaytim bekor qilinadi). Manfiy qoldiq (xato yozuv izi) nazorat ro‘yxatida qizil, oylik to‘plamda (E4) alohida belgi bilan ko‘rinadi. Oldingi avansi hisobotsiz qolgan xodimga yangi avans faqat Direktor tasdig‘i bilan beriladi. Muddati o‘tgan qoldiqlar nazorat ro‘yxatida ko‘rinadi, «Kassa» sahifasining yuqorisida eslatma chiqadi («Avans hisoboti muddati o‘tgan hisobdorlar: N ta») va Direktorning Telegram nazorat qatorida ham bo‘ladi.

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

**Yil bo‘yicha (har oy yopilgach yangilanadi) — RP-09.** «Buxgalteriya» → **«📊 RP-09 matritsa»**: o‘quv yili (sentyabr–avgust) yoki
kalendar yili; statiya × oy jadvali — barcha pul harakati (kassa orderlari; kassadan tashqari o‘quv to‘lovlari — Click / Uzum / Payme,
terminal, bank, o‘zaro hisob; «Buxgalteriya» xarajatlari; qaytarishlar; maosh va avans to‘lovlari) yoki «Ko‘rinish»da bitta usul.
Hisobdor xarajatlari (avans hisoboti — pul oldin avans sifatida berilgan) va hisoblangan maosh (tasdiqlangan vedomost × lavozim →
EX-01…EX-04) — alohida, pul jamiga kirmaydi; ichki o‘tkazma (bankka topshirish, bankdan olish, korporativ karta) — belgili, sof oqimga
kirmaydi. Yashil belgilar: «Jami = Σ hujjatlar» (har manba jami matritsa jamiga teng) va «kassa orderlari»; «≈ toifadan» — statiya eski
xarajat toifasidan olingan (yozuvda statiya yo‘q); «statiyasiz toifalar» — shu xarajatlarga statiya tanlab qayta saqlang. «Maosh
taqsimoti»: tasdiqlangan oyda taqsimot «Maosh» qatori bilan teng bo‘lishi kerak (farq bo‘lsa yoki qator yozilmagan bo‘lsa — «💼 Oylik
maoshni yozish»); «aniqlanmagan» lavozim statiyasi buxgalter bilan kelishiladi (Sh-8, B22). «⬇ Excel (XLSX)» — to‘rt varaq: Matritsa,
Usullar, Maosh taqsimoti, Nazorat; faylda ism yo‘q.

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
qo‘yiladi. Ismli to‘liq fayllar (davr surati, KO-3, oylik to‘plam) Direktorning xavfsiz arxivida saqlanadi, buxgalterga ismsiz nusxa
beriladi.

**Boshqa ismsiz fayllar** (FD-28; egasi qarori, 2026-11-16) — 16-noyabr haftasidagi yangilanishdan Direktordan boshqalarga: izoh,
fayl nomi yoki sarlavhada
«-ismsiz», ism o‘rniga ID (A4 hisobotlarda muallif — rol nomi); jamlar Direktor nusxasidagidek.
- «Moliya» → qarzdorlar «⬇ CSV» (moliya menejeri) — `qarzdorlar-<oy>-ismsiz.csv`: birinchi qatorda izoh, «O‘quvchi ID» ustuni,
  qolgan ustunlar o‘zgarmagan.
- «Buxgalteriya» → «📄 A4 hisobot» (moliya menejeri, buxgalter) — «Xodim (maosh ID)» ustuni; sarlavhada tuzgan xodim — ism o‘rniga
  rol nomi, imzo qatorida — sizning lavozimingiz («Direktor» emas).
- «Xodimlar davomati» → «Oylik hisobot» → «🖨 PDF / Hisobot» (moliya menejeri, kassir) — xodim maosh ID va kamera ID bilan;
  lavozim, ruxsat sababi va vedomostni tayyorlagan / tasdiqlagan shaxs ismi chiqmaydi.

Ismli nusxa — Direktorda (davomat hisoboti HR’da ham); ekrandagi ro‘yxatlar o‘zgarmagan.

**Kassa orqali o‘tgan to‘lov** (naqd o‘quv to‘lovi, o‘zaro hisob) summasi, o‘quvchisi, sanasi yoki usuli «To‘lovlar»dan
o‘zgartirilmaydi va bekor qilinmaydi — xato bo‘lsa shu kuni hujjat «Kassa»da bekor qilinadi, keyin esa Direktor «Qaytarish»
qiladi (1-bo‘lim, «Xato qildim»). Yopilgan davrdagi to‘lovning sanasi, summasi, usuli o‘zgartirilmaydi va u bekor qilinmaydi;
**holati va o‘quvchisi ham** — biriktirilmagan to‘lovni qaytarish yoki biriktirish, holatini o‘zgartirish o‘sha oy tushumini
o‘zgartiradi, tizim rad etadi (bo‘lish — tushum o‘zgarmaydi, ruxsat). Kerak bo‘lsa Direktor «Davr»da davrni sababi bilan qayta
ochadi, amaldan keyin qayta yopadi. «↩ Fakturadan» (provayder qaytargan pul) fakturaning kassa hujjati bilan to‘langan qismini
ayirmaydi — u «↩ Qaytarish» bilan (kassa orqali) qaytariladi. Naqd pul naqdsiz yorliq bilan («bank», «terminal») yozilgan bo‘lsa,
kassa uni ko‘rmaydi — bank ko‘chirmasi va Z-hisobot bilan solishtirganda aniqlanadi (`ishga-tushirish.md`, 8-bo‘lim oxiridagi cheklovlar).

**Kassa ishga tushishidan oldingi naqd avans yoki maosh yozuvi** («Buxgalteriya»da, kassa orderisiz) bo‘yicha kassaga qaytim
(«Xodim qaytargan pul») yozilgan bo‘lsa, o‘sha xodim va oy bo‘yicha sof summa manfiy bo‘ladigan qilib yozuv o‘chirilmaydi,
kamaytirilmaydi va boshqa oy / usulga o‘tkazilmaydi — avval qaytim orderi bekor qilinadi (shu kuni) yoki buxgalter bilan tuzatiladi.

## 3. Direktor

**Bir marta (ishga tushirishda):** «⚙ Sozlamalar» (tashkilot nomi, STIR, joy, chop etish tili, T1, L1, kassa limiti, imzo egalari,
ishga tushadigan kun) va «Boshlang‘ich qoldiqni kiritish» — 30-dekabr kechqurun; «31-dekabr holati» surati qulf bilan — 4-yanvar
ertalab, birinchi kassa kuni ochilishidan oldin (`ishga-tushirish.md`, 4-bo‘lim); tugagach kassirga ayting (kassir shungacha kassa
hujjati yozmaydi). Oldindan: kassa hisoblarini, HR menejer hisobini
va o‘zingiznikini 30-dekabrgacha xodim kartasiga bog‘lang (kartada F.I.Sh. to‘liq; HR menejer va moliya menejeri hisobini — vedomost
yuborilishidan oldin, aks holda ularning o‘z maosh qatori sizning tasdig‘ingizni talab qilmaydi); 2 ta takroriy maosh ID — xodim
kartasida «Yangi noyob ID berish» (aks holda vedomost HR’ga yuborilmaydi); buxgalterga «Buxgalter» roli — yashirin o‘rnatishdan
keyin; kassirga (G‘aznachi lavozimidagi xodim) — «Kassir» roli, o‘rinbosarga — qo‘shimcha «Kassir» roli («Foydalanuvchilar» →
«➕ Lavozim»); «G‘aznachi» rolini kassa xodimiga bermang (unda moliya huquqlari bor): hozir shu roldagi hisob naqd bilan ishlasa —
«Tahrirlash»da rolini «Kassir»ga almashtiring; «Bayram / ta’til kunlari»ga yanvar bayram va ta’til kunlari; «Xabarnomalar» → «📊 Direktorga kunlik hisobot»: kunlar — Du–Ju,
soat — kassa yopilgandan keyin (standart 19:00).

**Xodim kartasi ↔ login va o‘z maoshi (16-noyabr haftasidagi yangilanish).** Bu paragraf yangilanish kuni beriladi (o‘qitishni
kutmaydi). Xodim kartasining login hisobiga bog‘lanishini faqat siz o‘zgartirasiz («Foydalanuvchilar» → «Tahrirlash»); HR menejer bu bog‘lanishni o‘zgartira olmaydi va o‘zi bog‘langan kartani
o‘chira olmaydi, o‘zgarishlar «O‘zgarishlar tarixi»da «Bog‘langan login» bo‘lib ko‘rinadi. HR menejer va moliya menejerining o‘z maosh
qatori — karta qanday bog‘langan bo‘lmasin — sizning tasdig‘ingizda. Yangilanishda avval yuborilgan yoki tasdiqlangan oylardagi
shunday qatorlar ham sizning tasdig‘ingizga o‘tkaziladi: deploy chiqishida «… ta maosh vedomosti qatori … Direktor tasdig‘iga
o‘tkazildi» qatori bo‘lsa — o‘sha qatorlarni pul berilishidan oldin «Oylik vedomost»da ko‘rib chiqing.

**Ota-ona kodi (Click / Uzum; 16-noyabr haftasidagi yangilanish).** Bu paragraf yangilanish kuni beriladi (o‘qitishni kutmaydi).
To‘lov yozuvlarida ota-onaning maxfiy kodi hech kimga (sizga ham) ko‘rsatilmaydi — o‘rnida «[kod]». Eski to‘lov yozuvlarida
ko‘ringan kodlar yangilanishda bir marta avtomatik almashtiriladi. Deployni bajargan shaxsdan deploy chiqishidagi
«payer-code-mask: …» qatorini oling (ikkita bo‘lsa — ikkalasini); undagi sonlardan sizga uchtasi kerak: nechta o‘quvchi kodi
almashtirildi, to‘lov matnida ochilgan kodlar bilan qilingan nechta faol ota-ona — farzand bog‘lanishi bor va shundan nechtasi
ota-ona bo‘lmagan (xodim) hisobida. Bog‘lanishlarga tegilmaydi (uzilmaydi): ularning ko‘pi — kodni Click / Uzum’ga o‘zi yozgan
ota-onaning o‘z bog‘lanishi. Ota-ona bo‘lmagan hisobdagilarini esa birma-bir, hisob egasi bilan ko‘rib chiqing (ro‘yxatni deployni
bajargan shaxs chiqarib beradi). Deploy chiqishida bu qator bo‘lmasa — hech narsa almashtirilmagan (hammasi 0). Eski kod
Click / Uzum to‘lovida ishlayveradi, kabinetga farzand qo‘shishda — yo‘q; ota-onaga yangi kod berish (siz bersangiz ham) —
6-bo‘limdagi tartibda.

**Har kuni**
- **Telegram hisoboti:** kassa qatori (kirim, chiqim, qoldiq; sanaldi / farq — kunni yopishdagi va smena topshirishdagi alohida)
  va «Kassa nazorati» qatori (muddati o‘tgan avans, qabul qilinmay qolgan smena topshirish ham). Nazorat qatori bo‘sh bo‘lmasa — «Kassa» → «Nazorat ro‘yxati». Dushanba
  kuni — qo‘shimcha «Kassa — o‘tgan hafta» qatori (haftalik ko‘rsatkichlar); batafsil — «Kassa» → «KPI».
- **Tasdiqlash:** T1 dan katta chiqim (T1 0 qolsa — har chiqim), yuridik shaxsga kassadan naqd to‘lov (chegara 0 — har biri),
  rahbar yoki ta’sischiga beriladigan pul, qarz — «So‘rovlar» → «Tasdiqlash». Oddiy chiqimni 2-ro‘yxat o‘rniga tasdiqlay olmaysiz
  (moliya menejeri ham, buxgalter ham yo‘q kuni chiqim kutadi — ular telefondan tasdiqlay oladi). O‘zingizga
  (bog‘langan xodim kartangizga) beriladigan pulda Direktor bosqichini o‘zingiz imzolaysiz (FD-48) — 2-ro‘yxat tasdig‘i baribir kerak,
  pulni kassir beradi.
- **Pul berish (favqulodda, kassir yo‘q):** faqat 2-ro‘yxat tasdiqlagan so‘rov bo‘yicha uchinchi shaxsga. Qaytarishni (so‘rovning o‘zi
  sizning tasdig‘ingiz), o‘zingizga beriladigan pulni (avans, hisobdorga avans, rahbarga berish, naqd maosh — FD-48) va o‘zingiz yolg‘iz
  tasdiqlagan «Qarz / ta’sischi mablag‘i» kirimini tizim sizga bermaydi va qabul qildirmaydi («Pulni berish» / «Qabul qilish» tugmasi
  ko‘rinmaydi) — pulni kassir beradi / qabul qiladi. Vedomost tasdig‘iga o‘tish oyidan oldingi oy uchun o‘z maoshingizni naqd hech
  kim bermaydi (kassir vedomostsiz oyda naqd maosh bermaydi) — u karta orqali yoziladi.
- **Qaytarish:** «↩ Qaytarish» (sababi, ariza sanasi, usul). Naqd bo‘lsa pulni kassir beradi; balans pul berilganda o‘zgaradi.
  «Avans ham» belgilansa avans ham **naqd beriladi** (bitta chiqim orderida) — tasdiqlashda «qaytarish X + avans Y = jami Z» ko‘rinadi.
  Javob kelmay qayta bosilsa ikkinchi so‘rov yozilmaydi; shu faktura, to‘lov yoki avans bo‘yicha hali berilmagan so‘rovlar bilan jami
  qaytariladigan summadan oshsa — rad etiladi (avval o‘sha so‘rov beriladi yoki bekor qilinadi). **Naqdsiz** qaytarish ham shunday:
  kassada hali berilmagan naqd so‘rov bilan jami oshsa — rad etiladi. Birinchi yuborishdan keyin oynadagi usul o‘zgarmaydi (boshqa
  usul — oynani qayta ochib). Javob kelmay qolgach summa, «avans ham» yoki usul o‘zgartirilib qayta yuborilsa — rad etiladi va
  birinchi yozilgani ko‘rsatiladi («Bu oynadan avval boshqa ma’lumot bilan qaytarish yozilgan (…)»): ro‘yxatni tekshiring, boshqasi
  kerak bo‘lsa — yangi oynada. Yopilgan davr to‘lovini qaytarish — avval davrni qayta ochib.
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
| Kamomad bo‘yicha qaror | «Qarori kutilayotgan kamomadlar» → «Qaror» | oynada kassa egasi (kun kassiri), pulni kim sanagani, kassa egasidan boshqa kassa orderi o‘tkazgan yoki bekor qilgan xodimlar va shu kungi smena topshirishlar ko‘rinadi; xodim hisobiga — faqat **xodim kartasiga**: kassa egasi pulni o‘zi sanagan, kassani olgandan beri kassa orderini undan boshqa hech kim (siz ham, moliya menejeri ham) o‘tkazmagan va bekor qilmagan hamda hisobi kartaga bog‘langan bo‘lsa uning kartasi tanlangan bo‘ladi, aks holda (kassir o‘rniga sanalgan, egasi aniqlanmagan, kassaga boshqa xodim ham tekkan, hisob bog‘lanmagan — sababi oynada yoziladi) javobgar xodimni o‘zingiz tanlaysiz; yoki zararga; dalolatnoma; xodim hisobiga — u pulni kassaga «Kamomadni qoplash (xodim)» bilan qaytaradi (qolgani nazorat ro‘yxatida). Kamomad smena topshirishda e’lon qilingan navbat yozuvidan bo‘lsa-yu, o‘sha to‘lov keyin yangi kalit bilan qayta kiritilgan bo‘lsa — keyingi sanashda xuddi shuncha ortiqcha chiqadi: xodim hisobiga emas, «Hisobdan chiqarish» (ishga-tushirish §8) |
| Yopilgan kunni qayta ochish | «Kassa kunlari» → «Qayta ochish» | faqat oxirgi, tekshirilmagan kun; sababi yoziladi; qayta ochgan kunni o‘zingiz tekshirmaysiz (2-ro‘yxat tekshiradi) |
| Fiskal cheksiz naqd to‘lov (istisno) | «💵 To‘lov» → «Fiskal cheksiz» | faqat kassa apparati ishlamaganda; jurnalda qoladi |
| 48 soatdan eski oflayn yozuvni kiritish | «💵 To‘lov» | «Қ» blankasi asosida; kassir qurilmasi navbatidagi o‘sha yozuv o‘chiriladi (kunni yopishda e’lon qilingan bo‘lsa — u bog‘lanmay qoladi, kun izoh bilan tekshiriladi) |
| Navbatdagi «Yuborilmadi — Direktor hal qiladi» yozuvi | ⏳ To‘lov navbati | qayta yuborilmaydi («Hammasini qayta yuborish» ham yubormaydi): pul ikki marta hisoblanishi mumkin — buxgalter bilan hal qilib, navbatdan o‘zingiz o‘chirasiz (`ishga-tushirish.md`, 9-bo‘lim) |
| Kassa ishga tushishidan oldingi (yoki kassa to‘xtatilgan davrdagi) kechikib topilgan naqd yozuv | «💵 To‘lov» → «Naqd», «Sana» = pul olingan kun; xarajat, maosh, avans — «Buxgalteriya» oynalarida «Naqd — kassa ishga tushishidan … oldin berilgan» | kirim / chiqim orderisiz va fiskal cheksiz, kassa qoldig‘i o‘zgarmaydi (pul sanashga kirgan); bugungi sana bilan kiritilmaydi — ikki marta hisoblanadi; faqat kassa ishlamagan kun sanasi bilan (birinchi ishga tushgan kundan oldin yoki to‘xtatilgan davrda) — kassa ishlagan kun sanasi bilan tizim qabul qilmaydi; nazorat ro‘yxatida ko‘rinadi (`ishga-tushirish.md`, 4-bo‘lim) |
| Kassani to‘xtatish (orqaga qaytish) | «⚙ Sozlamalar» → «Kassa ishga tushadigan kun»ni bo‘shatish yoki keyinga surish | oldin qurilmalar navbati bo‘shagan, kutilayotgan smena topshirish qabul qilingan yoki bekor qilingan, kun yopilgan, so‘rovlar bajarilgan yoki bekor qilingan bo‘lsin (aks holda tizim rad etib, ro‘yxatini ko‘rsatadi) — tayyorlangan, hali boshlanmagan qayta ishga tushirishda sanani bo‘shatganda ham; shu payt birinchi hujjat yozilayotgan bo‘lsa — «hozir hujjat yozilmoqda», bir oz kutib qayta saqlang; oxirgi kun «hali o‘tkazilmagan yozuvlar» bilan yopilgan va ular hali kelmagan bo‘lsa — kunni qayta oching, navbat o‘tgach qayta yoping (kun tekshirilgan bo‘lsa — navbat tushgan keyingi kunni yoping); hali kiritilmagan «Қ» blankalari bilan yopilgan bo‘lsa — «Қ» yozuvlari kiritilib, ular tushgan yangi kun yopiladi; oyna oqibatlarini sanab tasdiq so‘raydi; hodisa jurnalga yoziladi (`ishga-tushirish.md`, 9-bo‘lim) |
| Kassani qayta ishga tushirish | «Kassa» → «Qayta ishga tushirish» (komissiya sanagan summa, kun), keyin «⚙ Sozlamalar»da ishga tushadigan kun = o‘sha kun | farq (to‘xtatilgan davrdagi naqd harakat) texnik «Д-» dalolatnoma bilan yoziladi — kamomad / ortiqcha emas; nazorat ro‘yxatida «Kassani to‘xtatish va qayta ishga tushirish»; sanashdan keyin kassa hujjatisiz naqd yozuv kiritilsa — qayta sanash (tizim birinchi kunni ochmaydi, «Kassa»da qizil ogohlantirish) |
| Davr surati va davrni yopish / qayta ochish | «Davr» | yopish — shu sanagacha kassa kunlari yopilgach; qayta ochish — sababi bilan, tarixda qoladi (yopilgan davr to‘lovini qaytarish, biriktirish yoki holatini o‘zgartirish uchun ham — amaldan keyin qayta yopiladi) |
| Naqd pulni o‘quvchi balansiga qo‘llash (kassa ishga tushgach) | faqat «💵 To‘lov» | to‘lov yozuvini to‘g‘ridan-to‘g‘ri kiritish, «naqd» kanal bilan qo‘llash yoki bo‘lishda «naqd» qism — Direktorga ham yo‘q (kirim orderisiz bo‘lardi); «Moliya tekshiruvi» → «Qo‘llash» (osilib qolgan mavjud pul, yangi pul kirmaydi) kanal yorlig‘i «Aralash» bilan ishlaydi |
| Oldingi avansi hisobotsiz xodimga yangi avans (istisno) | «So‘rovlar» → «Tasdiqlash» | kassa tartibidan istisno; so‘rovda «Direktor tasdig‘i» talabi o‘zi qo‘yiladi |
| Moliya menejeri yoki buxgalterga beriladigan pul (avans, hisobdorga avans) | «So‘rovlar» → «Tasdiqlash» | ular o‘zlariga beriladigan pulni tasdiqlay olmaydi — 2-ro‘yxat bosqichini Direktor imzolaydi (boshqa 2-ro‘yxat xodimi ham tasdiqlay oladi); Direktor tasdig‘i ham kerak bo‘lsa — o‘sha bir tasdiq bilan |
| Yuridik shaxsga kassadan naqd to‘lov | «So‘rovlar» → «Tasdiqlash» | chegara — «⚙ Sozlamalar» (bo‘sh — har doim Direktor); asosiy yo‘l — bank; turi tasdiqlanmagan «jismoniy shaxs» / «boshqa» ham yuridik shaxs hisoblanadi; tur so‘rovdan keyin o‘zgargan bo‘lsa — so‘rov tasdiqda yoki pul berishda Direktorga qaytadi |
| Kontragent turini tasdiqlash (buxgalter ham) | «Nazorat ro‘yxati» → «Kontragent turi» → «✓ …» | «Jismoniy shaxs» / «Boshqa» — faqat haqiqiy fuqaro yoki YaTT; Direktor yoki buxgalter kiritgan / o‘zgartirgan tur darhol tasdiqlangan |
| Sozlamalar, imzo egalari, boshlang‘ich qoldiq | «⚙ Sozlamalar» | chegaralarni faqat Direktor o‘zgartiradi |
| KO-3, oylik kassa to‘plami, qarzdorlar CSV va «Buxgalteriya» A4 hisobotining to‘liq (ismli) nusxasi | «Kassa» → «KO-3» → «⬇ Excel»; «Statiyalar» → «⬇ Oylik to‘plam»; «Moliya» → qarzdorlar «⬇ CSV»; «Buxgalteriya» → «📄 A4 hisobot» | boshqalarga ismsiz nusxa chiqadi (FD-28; «Xodimlar davomati» oylik hisoboti HR’da ham ismli); ismli faylda shaxsiy ma’lumot bor — ehtiyot bilan saqlanadi |

Kassa egasi (kun kassiri) yo‘qligida kunni boshqa kassir, Direktor yoki moliya menejeri yopishi, smenani — boshqa kassir yoki
Direktor topshirishi mumkin — kamida 2 kishilik komissiya bilan (kassir o‘rniga; dalolatnomada kassa egasi va pulni sanagan xodim
alohida ko‘rinadi). Smena topshirish qabul qilinmay qolsa (qabul qiluvchi kelmadi) — «Kassa»dagi kartada «Bekor qilish».

## 4. HR menejer
- Vedomostni tekshirib **tasdiqlaysiz** — maosh kunidan oldin (noyabr vedomosti — noyabr maoshi berilishidan oldin; dekabr
  vedomosti — maosh qaysi kun bo‘lmasin, undan oldin). Tasdiqlanmagan oy uchun naqd maosh berilmaydi. Hisobingiz faol bo‘lsin —
  aks holda vedomost tasdiqlanmaydi.
- Kassa ishga tushgach **pul bermaysiz**: «Maosh berish» tugmasi sizda ko‘rinmaydi (naqd — kassir, karta — moliya menejeri).
- Ish haqi avansi so‘rovini kassir yoki moliya menejeri yuboradi, 2-ro‘yxat (katta summa — Direktor ham) tasdiqlaydi. Oy vedomosti
  **tasdiqlangach o‘sha oy uchun avans umuman berilmaydi** (yangi so‘rov ham, avval tasdiqlangan so‘rov puli ham) — kerak bo‘lsa Direktor
  oyni qayta ochadi. Vedomost tasdiqlanguncha avans summasini tizim vedomost bilan cheklamaydi — uni tasdiqlovchi tekshiradi.
- Xodim avansni kassaga qaytarsa, vedomostda avans qaytgani ayirilgan holda ko‘rinadi; oy tasdiqlangach avans qaytimi qabul
  qilinmaydi (kerak bo‘lsa Direktor oyni qayta ochadi).
- O‘z maosh qatoringizni (moliya menejerinikini ham) Direktor tasdiqlaydi. Xodim kartasining login hisobiga bog‘lanishini faqat
  Direktor o‘zgartiradi; o‘zingiz bog‘langan kartani o‘chira olmaysiz (kerak bo‘lsa — Direktorga ayting).

## 5. Hisobdor shaxs (zavxoz, oshpaz va boshqalar)
1. Pulni kassadan **chiqim orderi** bilan olasiz («Hisobdorga avans») — orderga «Oldim», summa, sana, imzo.
2. Har xarid uchun chek yoki hisob-faktura oling (sana, sotuvchi, nima, summa ko‘rinib tursin) — chek yoki fakturasiz xarid
   qilinmaydi (hujjatsiz xarid chegarasi L1 = 0).
3. **3 ish kuni ichida** avans hisobotini (qog‘oz shakl, `shakllar.md` Sh-1) cheklari bilan buxgalterga topshiring.
4. Ortgan pulni kassaga qaytaring — kassir **kirim orderi** yozadi («Hisobdordan qaytim»; hisobot qilinmagan qoldiqdan oshmaydi),
   pattasi sizda qoladi.
5. Avvalgi pul bo‘yicha hisobot topshirilmaguncha yangi pul so‘ralmaydi. Hisobdor puli — shaxsiy xarajat uchun emas.
6. **Yil yakuni:** qo‘lingizdagi eski pul **30-dekabrgacha** (kassa naqd ishlaydigan oxirgi kun) cheklar bilan hisobot yoki qaytim
   orqali to‘liq yopiladi; buxgalterga 31-dekabr holatiga nol qoldiq ma’lumotnomasini (`shakllar.md` Sh-7) imzolab berasiz. Yangi
   tizim eski pulni ko‘rmaydi — yanvarda u bo‘yicha na hisobot, na qaytim qabul qilinadi.

## 6. Qabulxona xodimi (ota-onaning maxfiy kodi)
«Kassa» bilan ishlamaysiz; bu varaq — ota-ona kabinetiga farzand qo‘shish kodi haqida. Varaq 16-noyabr haftasidagi yangilanish
kuni beriladi (o‘qitishni kutmaydi) va o‘sha kundan amalda.
- Click / Uzum to‘lovida ota-ona yozgan maxfiy kod to‘lov yozuvlarida saqlanmaydi — o‘rnida «[kod]». Eski to‘lov yozuvlarida
  ko‘ringan kodlar yangilanishda bir marta avtomatik almashtiriladi.
- Almashtirilgan (eski) kod bilan Click / Uzum orqali to‘lov ishlayveradi, lekin ota-ona kabinetida farzand qo‘shib bo‘lmaydi —
  ota-ona «Bu kod almashtirilgan — yangi kodni maktabdan oling» xabarini ko‘radi. Kabinetga avval qo‘shilgan farzandlar uzilmaydi.
- Ota-ona shu xabar bilan kelsa yoki qo‘ng‘iroq qilsa:
  1. Shaxsini tekshiring — kod faqat o‘quvchining ota-onasiga beriladi (har qanday kod so‘rovida shunday): telefon orqali — faqat
     o‘quvchi kartasidagi «Ota telefoni» yoki «Ona telefoni» raqamidan qo‘ng‘iroq qilganga (ro‘yxatdagi «Ota-ona tel.» ustunida —
     otaning raqami) yoki shu raqamga o‘zingiz qayta qo‘ng‘iroq qilib; boshqa holda — faqat shaxsan: shaxsni tasdiqlovchi
     hujjatdagi F.I.Sh. o‘quvchi kartasidagi «Ota (F.I.Sh)» yoki «Ona (F.I.Sh)» bilan mos kelsa.
  2. «O‘quvchilar» ro‘yxatida o‘quvchini toping va «Kod» ustunidagi (telefonda — «Kod (ota-onaga)») joriy kodni bering: 📋 tugmasi
     o‘quvchi ID va kodni birga nusxalaydi.
  3. Ayting: Click / Uzum ilovasida saqlangan to‘lovlar eski kod bilan ham ishlayveradi — ularni o‘zgartirish shart emas; yangi kod
     kabinetga farzand qo‘shish uchun kerak.
