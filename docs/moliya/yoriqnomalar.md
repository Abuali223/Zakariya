# «Kassa» bo‘limi: rol bo‘yicha qisqa yo‘riqnomalar (F1.19)

O‘qitishda (sinov stendida) tarqatiladi; har bo‘lim — bir varaq. Bo‘lim «Moliya» → «Kassa» da. Tugma nomlari ekrandagidek.
Hujjat raqamlari: **K-** kirim orderi (KO-1), **Ch-** chiqim orderi (KO-2), **D-** naqdsiz dalolatnoma. Raqamni tizim beradi,
har yili 1 dan boshlanadi, bo‘shliq va takror bo‘lmaydi. To‘liq tartib: `docs/moliya/ishga-tushirish.md`; shakllar: `docs/moliya/shakllar.md`.

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

**Boshqa kirim** — «+ Kirim»: operatsiya tanlanadi («Bankdan naqd», «Hisobdordan qaytim», «Xodim qaytargan pul», «Forma va
tovarlar», «Boshqa kirim», «Qarz / ta’sischi mablag‘i» — bunisi Direktor tasdig‘i bilan), **kimdan** (ro‘yxatdan tanlanadi), summa,
asos (hujjat nomi, raqami, sanasi) → «Qabul qilish» → chop etish.

**Chiqim** — uch qadam:
1. «+ Chiqim so‘rovi»: operatsiya («Xarajat», «Ish haqi avansi», «Hisobdorga avans», «Bankka topshirish», «Rahbar / ta’sischiga»,
   «So‘mdagi qarzni qaytarish»), **kimga**, summa, statiya, asos hujjati → «So‘rov yuborish». Xarajatning oluvchisi xodim bo‘lmaydi
   (xodimga — avans yoki hisobdorga avans). Asos hujjatisiz xarid — faqat belgilangan chegaragacha va bitta statiya bilan.
2. Moliya menejeri yoki buxgalter tasdiqlaydi (katta summa, rahbarga berish va qarz — Direktor ham).
3. «So‘rovlar» ro‘yxatida «Pulni berish» → «🖨 Chiqim orderi» → oluvchi «Oldim» deb summa (so‘z bilan), sana va imzo qo‘yadi;
   shaxsini tasdiqlovchi hujjat ma’lumoti yoziladi. Kassada pul yetmasa tizim chiqimga yo‘l qo‘ymaydi.

**Maosh.** «Maosh» sahifasida «Maosh berish» → usul «Naqd» → chiqim orderi o‘zi yoziladi. Faqat tasdiqlangan vedomost chegarasida.
Naqd maoshni faqat kassir beradi. **Ish haqi avansi** — «+ Chiqim so‘rovi» orqali (yuqoridagi uch qadam).

**Ota-onaga pul qaytarish.** Direktor «↩ Qaytarish» orqali tasdiqlagach, «So‘rovlar»da paydo bo‘ladi → «Pulni berish» → chiqim
orderi; ota-onaning yozma arizasi orderga ilova qilinadi. Bir kundan ortiq kechiktirilmaydi (eslatma chiqadi).

**Xato qildim.** Shu kuni hujjat qatorida «Bekor» → sababi. Kassir faqat **o‘zi o‘tkazgan** orderni bekor qiladi; boshqasinikini —
moliya menejeri yoki Direktor. O‘quv to‘lovidan keyin o‘quvchi bo‘yicha boshqa pul harakati bo‘lgan bo‘lsa, bekor qilinmaydi —
Direktor «Qaytarish» qiladi. Qaytarish chiqim orderi bekor qilinmaydi.

**Smena almashsa** — «Smena topshirish»: pul sanaladi, qabul qiluvchi kassir tanlanadi, dalolatnoma chop etiladi, ikkalasi imzolaydi.

**Kechqurun.** «Kunni yopish»: kassadagi pulni sanang va **sanalgan summani** kiriting (nominallar bo‘yicha ham mumkin) → «Sanab
yopish». Farq bo‘lsa tizim shu kunga kamomad yoki ortiqcha hujjatini o‘zi yozadi — sababini izohga yozing. Keyin «🖨 KO-4»
(2 nusxa) va «🖨 Kunlik hisobot»: imzolab, orderlar va ilovalari bilan moliya menejeriga topshiring.

**Internet yoki tizim ishlamasa** — `ishga-tushirish.md`, 8-bo‘lim («Қ» blankasi to‘lovchiga berilmaydi; dalil — fiskal chek).

## 2. Moliya menejeri va buxgalter (2-ro‘yxat)

**Har kuni**
1. **Chiqim so‘rovlarini tasdiqlash:** «Kassa» → «So‘rovlar» → «Ko‘rish»: oluvchi, statiya, asos hujjati to‘g‘rimi → «Tasdiqlash»
   yoki «Rad etish» (sababi). O‘zingiz yuborgan so‘rovni o‘zingiz tasdiqlay olmaysiz.
2. **Kunni tekshirish:** kassir topshirgan KO-4, orderlar va ilovalarni ekrandagi kun bilan solishtiring → «Kassa kunlari» →
   «Tekshirish» → «qog‘oz va ilovalar olindi» belgisi → «Tekshirdim». Kunlar tartib bilan tekshiriladi; shu kuni hujjat o‘tkazgan
   yoki kunni yopgan shaxs tekshira olmaydi. Tekshirilgan kun endi o‘zgarmaydi.
3. **«Nazorat ro‘yxati»** (shu sahifada): qizil — bugun hal qilinadi (raqamlashda bo‘shliq, yopilmagan kecha, qarorsiz kamomad,
   kechikkan qaytarish, «Moslik» mos emas); sariq — shu hafta; «Moslik» qatori doim «hammasi mos» bo‘lishi kerak.
4. **Bank orqali to‘langan xarajatlar** — «Buxgalteriya» → «+ Xarajat qo‘shish»: to‘lov usuli (bank o‘tkazmasi, korporativ karta yoki
   hisobdor shaxs orqali), statiya, kontragent.
   Naqd xarajat bu yerda yozilmaydi — u kassa chiqim orderidan o‘zi ko‘chadi.

**Maosh.** Vedomostni moliya menejeri tayyorlaydi, HR tasdiqlaydi. Karta orqali to‘lovni moliya menejeri «Maosh berish» → «Karta»
bilan yozadi (kassa orderisiz); naqd — faqat kassir.

**Hisobdorlar.** Pul «Hisobdorga avans» bilan beriladi (bu xarajat emas). Hisobdor 3 ish kuni ichida avans hisobotini (qog‘oz,
`shakllar.md` Sh-1) cheklari bilan topshiradi; qaytim — «+ Kirim» → «Hisobdordan qaytim». Buxgalter hisobot bo‘yicha xarajatni
«Buxgalteriya»ga kiritadi. Muddati o‘tgan qoldiqlar nazorat ro‘yxatida ko‘rinadi.

**Oy oxiri.** Hamma kun «Tekshirilgan»; nazorat ro‘yxati toza; avans hisobotlari kiritilgan → Direktor «Davr»da surat oladi va
davrni yopadi. «Davr» oynasida suratlarni ko‘rish, «Tekshirish» (xesh) va «⬇ JSON» sizga ham ochiq.

## 3. Direktor

**Bir marta (ishga tushirishda):** «⚙ Sozlamalar» (tashkilot nomi, STIR, joy, chop etish tili, T1, L1, kassa limiti, imzo egalari,
ishga tushadigan kun) va «Boshlang‘ich qoldiqni kiritish» — `ishga-tushirish.md`, 4-bo‘lim.

**Har kuni**
- **Telegram hisoboti:** kassa qatori (kirim, chiqim, qoldiq; sanaldi / farq) va «Kassa nazorati» qatori. Nazorat qatori bo‘sh
  bo‘lmasa — «Kassa» → «Nazorat ro‘yxati».
- **Tasdiqlash:** T1 dan katta chiqim, rahbar yoki ta’sischiga beriladigan pul, qarz — «So‘rovlar» → «Tasdiqlash».
- **Qaytarish:** «↩ Qaytarish» (sababi, ariza sanasi, usul). Naqd bo‘lsa pulni kassir beradi; balans pul berilganda o‘zgaradi.
- **O‘zaro hisob:** xodim yozma ariza bilan ish haqidan farzandining o‘quv haqini to‘lasa — «Maosh berish» → «O‘zaro hisob»
  (o‘quvchi, ariza sanasi, summa). Kassadan pul chiqmaydi; dalolatnoma chop etiladi. Xato bo‘lsa — shu kuni «Bekor».

**Faqat Direktor qiladigan amallar**
| Amal | Qayerda | Eslatma |
|---|---|---|
| Kamomad bo‘yicha qaror | «Qarori kutilayotgan kamomadlar» → «Qaror» | xodim hisobiga yoki zararga; dalolatnoma |
| Yopilgan kunni qayta ochish | «Kassa kunlari» → «Qayta ochish» | faqat oxirgi, tekshirilmagan kun; sababi yoziladi |
| Fiskal cheksiz naqd to‘lov (istisno) | «💵 To‘lov» → «Fiskal cheksiz» | faqat kassa apparati ishlamaganda; jurnalda qoladi |
| 48 soatdan eski oflayn yozuvni kiritish | «💵 To‘lov» | «Қ» blankasi asosida |
| Davr surati va davrni yopish / qayta ochish | «Davr» | yopish — shu sanagacha kassa kunlari yopilgach; qayta ochish — sababi bilan, tarixda qoladi |
| Sozlamalar, imzo egalari, boshlang‘ich qoldiq | «⚙ Sozlamalar» | chegaralarni faqat Direktor o‘zgartiradi |

Kassir yo‘qligida kunni Direktor yoki moliya menejeri yopishi mumkin — kamida 2 kishilik komissiya bilan.

## 4. HR menejer
- Vedomostni tekshirib **tasdiqlaysiz** — maosh kunidan oldin. Tasdiqlanmagan oy uchun naqd maosh berilmaydi.
- Kassa ishga tushgach **pul bermaysiz**: «Maosh berish» tugmasi sizda ko‘rinmaydi (naqd — kassir, karta — moliya menejeri).
- Ish haqi avansi so‘rovini kassir yoki moliya menejeri yuboradi; tasdiqlangan vedomostdan ortiq avans berilmaydi.

## 5. Hisobdor shaxs (zavxoz, oshpaz va boshqalar)
1. Pulni kassadan **chiqim orderi** bilan olasiz («Hisobdorga avans») — orderga «Oldim», summa, sana, imzo.
2. Har xarid uchun chek yoki hisob-faktura oling (sana, sotuvchi, nima, summa ko‘rinib tursin).
3. **3 ish kuni ichida** avans hisobotini (qog‘oz shakl, `shakllar.md` Sh-1) cheklari bilan buxgalterga topshiring.
4. Ortgan pulni kassaga qaytaring — kassir **kirim orderi** yozadi («Hisobdordan qaytim»), pattasi sizda qoladi.
5. Avvalgi pul bo‘yicha hisobot topshirilmaguncha yangi pul so‘ralmaydi. Hisobdor puli — shaxsiy xarajat uchun emas.
