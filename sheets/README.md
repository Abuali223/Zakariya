# Google Sheets'ga avtomatik yozish (`iqror-sheets`)

Platformadagi ma'lumotlar Google Sheets jadvaliga **avtomatik va darhol** yoziladi: o'zgarish odatda 1–5 soniyada jadvalda
ko'rinadi. Yo'nalish faqat bitta — **platforma → jadval**: jadvalda nimadir o'zgartirilsa, platformaga ta'sir qilmaydi va
keyingi yozishda platformadagi qiymat bilan almashadi.

Jadvalni kim ko'rishini **Direktor hal qiladi** (Google'dagi «Ulashish» / «Share» tugmasi orqali).

## Jadvaldagi varaqlar

| Varaq | Nima bor | Qanday yangilanadi |
|---|---|---|
| **O'quvchilar** | Barcha o'quvchilar (arxivdagilar ham): ID, F.I.Sh., sinf, yo'nalish, til, holati (faol / sinov / muzlatilgan / chiqadi / chiqqan yoki bitirgan — arxiv), o'qishni boshlagan va chiqqan sana, tug'ilgan sana, ota-onasi va telefonlari, vasiy, manzil, shartnoma summasi, aka-uka chegirmasi, joriy qarz, qarzli oylar soni, avans (ortiqcha to'lov) | Har o'zgarishda to'liq |
| **Oylik to'lovlar** | Har bir hisob-faktura: oy, o'quvchi, sinf, asl summa, chegirma, hisoblangan, to'langan, qarz, holati, to'liq to'langan vaqti | O'zgargan qator o'z joyida; yangisi oxiriga |
| **To'lovlar** | Har bir to'lov: kassa kuni, kiritilgan vaqt, o'quvchi, summa, usul (Click, Uzum, naqd …), holati, tushumga kiradimi, qaysi oy uchun, to'lovchi (to'lov izohidagi maxfiy kod «[kod]» bo'lib yashirilgan), fiskal chek | O'zgargan qator o'z joyida; yangisi oxiriga |
| **Qarzdorlik** | Shu oygacha qarzi bor har o'quvchi: qarzli oylar, oylar soni, jami qarz, eng eski qarz oyi, avans, ota-ona telefonlari (katta qarzdan kichigiga) | Har o'zgarishda to'liq |
| **Oylik hisobot** | Har oy: o'quvchilar soni, hisoblangan, chegirma, to'langan, qarz, yig'im foizi, jami kirim, xarajat, foyda, qaytarilgan, kassaga tushgan pul jami va usullar bo'yicha | Har o'zgarishda to'liq |
| **Xarajatlar** | Har bir xarajat: sana, oy, toifa, summa, to'lov usuli, izoh | Har o'zgarishda to'liq |
| **Qaytarishlar** | Har bir qaytarish: sana, oy, o'quvchi, summa, qayerdan (hisob-faktura / avans), usul, sabab | Har o'zgarishda to'liq |

Raqamlar **admin paneldagi bilan bir xil** hisoblanadi: to'langan / qarz — «To'lovlar» va «Moliya» bo'limlaridagi qoida (bekor
qilingan yoki qaytarilgan hisob-faktura — 0), kassaga tushgan pul — kassa kuni bo'yicha, oy kirimi va xarajat — «Buxgalteriya»
hisobotidagidek, yig'im foizi — «Moliya»dagidek, arxiv — «Arxiv» bo'limidagi qoida.

**Jadvalga YOZILMAYDI:** JSHSHIR, metrika, salomatlik ma'lumotlari, o'quvchining ketish sababi (faqat «bitirgan» belgisi),
to'lovchining telefoni, xodimlarning alohida maoshi (xarajatlarda maosh — vedomost jami, admin paneldagidek).

Har kecha Toshkent vaqti bilan 03:00 dan keyin barcha varaqlar to'liq qayta yoziladi — qo'lda qilingan tahrirlar tuzaladi,
kalitli varaqlarda qatorlar tartibi tiklanadi.

## Xavfsizlik

* Jadvalda o'quvchilar va ota-onalarning **shaxsiy ma'lumotlari** bor. Faqat ishonchli xodimlarga, iloji bo'lsa **«Ko'ruvchi»**
  (Viewer) huquqi bilan ulashing. **«Havolaga ega har kim»** (Anyone with the link) qilib qo'ymang.
* **Xizmat hisobi kaliti** (`google-key.json`) — maxfiy. U faqat serverda turadi (ruxsati 600). Hech kimga yubormang, chatga yoki
  repoga yozmang. Kalit begona qo'lga tushgan bo'lsa — Google Cloud'da o'sha kalitni o'chiring va yangisini yarating (6-qadam).
* Xizmat bazadan faqat o'qiydi (maxsus funksiyalar orqali); platformadagi foydalanuvchilar — Direktor ham — bu funksiyalarni
  chaqira olmaydi.

## O'rnatish (bir marta, taxminan 15 daqiqa)

### Google tomonida

1. **Loyiha.** <https://console.cloud.google.com> → yuqoridagi loyiha tanlovi → «New project» → nom, masalan `iqror-sheets` → «Create».
2. **Google Sheets API.** «APIs & Services» → «Library» → `Google Sheets API` → «Enable».
3. **Xizmat hisobi.** «APIs & Services» → «Credentials» → «Create credentials» → «Service account» → nom, masalan `iqror-sheets` →
   «Create and continue» → rol tanlash shart emas → «Done». Ro'yxatdan shu hisobni oching → «Keys» → «Add key» →
   «Create new key» → **JSON** → «Create». Kompyuteringizga JSON fayl yuklanadi — bu kalit (maxfiy).
   Hisobning emailini yozib oling: `iqror-sheets@<loyiha>.iam.gserviceaccount.com`.
4. **Jadval.** Google Drive'da yangi **Google Sheets** jadvali yarating (masalan «Iqror — hisobotlar»). «Ulashish» (Share) →
   3-qadamdagi xizmat hisobi emailini qo'shing → huquq **«Muharrir»** (Editor) → «Yuborish». Jadval havolasidagi `/d/` va
   `/edit` orasidagi qism — **jadval ID** (`spreadsheetId`).
   Google Workspace (tashkilot) hisobida tashqi hisobga ulashish taqiqlangan bo'lsa — administrator ruxsat berishi kerak.

### Serverda

5. **Deploy** (baza qismi va xizmat kodi): `bash ~/iqror-repo/deploy.sh`. Deploy `/opt/iqror/sheets` papkasini yaratadi va
   bazaga navbat va varaq funksiyalarini qo'shadi. Xizmat hali o'rnatilmagan bo'lsa, deploy faqat eslatma chiqaradi.
6. **Kalit.** JSON faylni serverga `scp` bilan ko'chiring (chat yoki pochta orqali emas), so'ng:

   ```bash
   sudo install -o iqror -g iqror -m 600 ~/<yuklangan-kalit>.json /opt/iqror/sheets/google-key.json
   rm ~/<yuklangan-kalit>.json
   ```

7. **Sozlama** (namunadan nusxa — faqat birinchi marta; keyin faqat tahrirlanadi).

   ```bash
   sudo install -o iqror -g iqror -m 600 /opt/iqror/sheets/config.example.json /opt/iqror/sheets/config.json
   sudo nano /opt/iqror/sheets/config.json
   ```

   * `supabaseUrl` va `serviceRoleKey` — `/opt/iqror/payments/config.json` dagi bilan bir xil;
   * `sheets.spreadsheetId` — 4-qadamdagi jadval ID.

   Qolgan maydonlar (odatda tegilmaydi): `enabled` (`false` — xizmat to'xtab turadi), `keyFile` (kalit fayli, standart
   `google-key.json`), `pollMs` (navbatni tekshirish oralig'i, standart 2000 ms), `fromMonth` (pastda, «Jadval juda
   kattalashsa»), `perMinute` (Google'ga daqiqasiga so'rovlar, standart 50).
8. **Sinab ko'rish** (bitta to'liq yozish va chiqish):

   ```bash
   cd /opt/iqror && sudo -u iqror /usr/bin/node sheets/index.cjs --once
   ```

   «bir martalik to'liq yozish tugadi» chiqsa — jadvalda 7 ta varaq paydo bo'ladi. Xato chiqsa — pastdagi «Muammolar».
9. **Doimiy xizmat.**

   ```bash
   sudo cp ~/iqror-repo/migration/deploy/iqror-sheets.service /etc/systemd/system/
   sudo systemctl daemon-reload && sudo systemctl enable --now iqror-sheets
   sudo journalctl -u iqror-sheets -n 20 --no-pager
   ```

   Keyingi deploylarda `deploy.sh` xizmat kodini yangilab, uni o'zi qayta ishga tushiradi. Kunlik zaxira (`backup.sh`)
   sirlar fayliga `sheets/config.json` va `sheets/google-key.json` ham kiradi.

## Kundalik foydalanish

* Varaqlar **«ogohlantirish bilan» himoyalangan**: qo'lda tahrir qilmoqchi bo'lsangiz Google ogohlantiradi. Tahrir keyingi
  yozishda platformadagi qiymat bilan almashadi — ma'lumotni platformada o'zgartiring.
* **O'z hisob-kitoblaringiz uchun** shu jadvalda yangi varaq oching (masalan «Tahlil») va formulalar bilan platforma varaqlariga
  murojaat qiling — platforma o'z varaqlaridan boshqasiga tegmaydi. Masalan (jadval tili o'zbekcha / ruscha bo'lsa — `;`,
  inglizcha bo'lsa — `,`):
  `=SUMIF('Oylik to''lovlar'!B:B; "2026-11"; 'Oylik to''lovlar'!J:J)` — noyabr qarzi,
  `=QUERY(Qarzdorlik!A:K; "select B, G where G > 1000000 order by G desc")` — 1 mln dan katta qarzdorlar.
* Platforma varaqlarining **nomini o'zgartirmang va o'chirmang** — platforma yangisini yaratadi.

## Holatni tekshirish

```bash
sudo systemctl status iqror-sheets --no-pager
sudo journalctl -u iqror-sheets -n 50 --no-pager
sudo docker exec -i supabase-db psql -U postgres -d postgres -c "select beat, holder, info from app.sheets_state"
sudo docker exec -i supabase-db psql -U postgres -d postgres -c "select count(*) from app.sheets_outbox"
```

`info` ichida: `lastOk` — oxirgi muvaffaqiyatli yozish, `lastFull` — oxirgi to'liq yozish kuni, `lastError` — oxirgi xato
(bo'lmasa `null`), `tabs` — varaqlardagi qatorlar soni. Navbat (`sheets_outbox`) odatda 0 ga yaqin; Google ishlamay turganda
o'sadi va tiklangach bo'shaydi.

## Muammolar

| Jurnaldagi xabar | Sabab va yechim |
|---|---|
| «Jadvalga ruxsat yo'q … HTTP 403» | Jadval xizmat hisobiga ulashilmagan yoki ulashuv olib tashlangan — 4-qadam («Muharrir»). Ulashuv qaytarilgach xizmat o'zi davom etadi, yo'qolgan o'zgarish bo'lmaydi. |
| «Jadval topilmadi … HTTP 404» | `spreadsheetId` noto'g'ri yoki jadval o'chirilgan — 7-qadam. |
| «Xizmat hisobi kaliti noto'g'ri yoki o'chirilgan» | Kalit Google Cloud'da o'chirilgan — yangi JSON kalit (3-qadam), so'ng 6-qadam. |
| «Google Sheets sinxronlash ishlamayapti: …» | `config.json` yoki kalit fayli to'liq emas / o'qilmaydi (xabarda aniq sababi bor). Xizmat har 5 daqiqada qayta tekshiradi. |
| «Boshqa nusxa ishlayapti» (`--once` da) | Xizmat ishlab turibdi — `--once` kerak emas. Baribir kerak bo'lsa: `sudo systemctl stop iqror-sheets`, so'ng `--once`, so'ng `sudo systemctl start iqror-sheets`. |
| «yozilmadi (N-urinish) … HTTP 429 / 5xx» yoki tarmoq xatosi | Google kvotasi yoki internet uzilishi. Xizmat kutib qayta urinadi; o'zgarishlar navbatda saqlanadi va tiklangach yetkaziladi. |

**Jadval juda kattalashsa** (Google chegarasi — bitta jadvalda 10 mln katak; odatda bir necha yil yetadi): `config.json` da
`"fromMonth": "2026-09"` qo'ying — «Oylik to'lovlar», «To'lovlar», «Oylik hisobot», «Xarajatlar», «Qaytarishlar» faqat shu oydan
boshlab yoziladi («O'quvchilar» va «Qarzdorlik» — doim to'liq). Eski davr uchun avval jadvalning nusxasini saqlab qo'ying
(«Fayl» → «Nusxa yaratish»).

**Vaqtincha o'chirish:** `config.json` da `"enabled": false` (xizmat jim kutadi) yoki `sudo systemctl disable --now iqror-sheets`.
Xizmat to'xtagach 15 daqiqadan keyin baza o'zgarishlarni navbatga yig'ishni to'xtatadi; qayta yoqilganda hamma varaq to'liq qayta
yoziladi. **Boshqa jadvalga o'tish:** `spreadsheetId` ni o'zgartiring — xizmat buni o'zi sezib, yangi jadvalga to'liq yozadi.

## Dasturchi uchun

* Baza: `migration/sheets-sync.sql` — o'zgarishlar navbati (`app.sheets_outbox`, triggerlar), holat va ijara (`app.sheets_state`),
  varaq funksiyalari (`public.sheets_tab`), xizmat RPC'lari (`sheets_beat`, `sheets_pull`, `sheets_ack`, `sheets_full_begin`,
  `sheets_full_end`, `sheets_release` — faqat `service_role`). Sinov: `migration/test-sheets-sync.sql`.
* Xizmat: `index.cjs` (asosiy sikl, ijara, to'xtash), `sync.cjs` (navbat → varaqlar, birlashtirilgan yozish),
  `google.cjs` (Sheets API v4: JWT RS256, token, qayta urinish, kvota), `fake-google.cjs` (faqat sinov uchun xotiradagi
  o'xshash). Sinov: `node sheets/sheets.test.cjs` (tarmoqsiz).
* Yangi varaq yoki ustun qo'shish: `sheets-sync.sql` dagi varaq funksiyasi (`header`, `money`, `rows`) va `sync.cjs` dagi `TABS`
  / `SRC`; kerak bo'lsa yangi jadvalga trigger. Sarlavha o'zgarsa varaq avtomatik to'liq qayta yoziladi.
