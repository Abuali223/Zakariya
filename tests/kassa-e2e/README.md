# «Kassa» brauzer ssenariylari (lokal stend)

Playwright ssenariylari `admin.html` dagi «Kassa» va unga bog‘langan ekranlarni (to‘lovlar, maosh, avans, qaytarish,
«Buxgalteriya», hisobotlar, chop etish) haqiqiy brauzerda bosib chiqadi. Server tomoni — repo zanjiridan noldan
qurilgan lokal baza + PostgREST; ma’lumotlar — sintetik urug‘. Har reliz oldidan ishga tushiriladi
(`docs/moliya/ishga-tushirish.md`, §3.2, 3-qadam).

## Xavfsizlik (majburiy)

* **Faqat lokal.** Stend jonli saytga, Supabase bulutiga, Telegram, Eskiz va to‘lov tizimlariga ulanmaydi. Brauzer
  kontekstida `127.0.0.1` / `localhost` dan boshqa barcha xostlar yopiq (`lib/common.cjs`, `launch()`); yagona istisno —
  supabase-js moduli: lokal to‘plam bo‘lsa — undan, bo‘lmasa esm.sh dan («Talablar»).
* **`E2E_PGHOST` faqat lokal sinov klasteriga qaraydi.** `stand.sh reset` `E2E_DB` bazasini o‘chirib, qaytadan quradi va
  `anon` / `authenticated` / `service_role` rollarini yaratadi. Baza nomi faqat `fx_*` (boshqa nomni `env.sh` va
  `lib/common.cjs` rad etadi; sinov soati `app.fin_clock` ham faqat shunday nomli bazada ishlaydi).
* **Repo’da sir yo‘q.** JWT siri `bash stand.sh setup` bilan `local/jwt-secret.txt` ga tasodifiy yaratiladi (600).
  `local/`, `local.env`, `*.local.json` git’ga kirmaydi (`.gitignore`). Bu papkaga parol, kalit, token, haqiqiy shaxsning
  e-mail’i yoki telefoni yozilmaydi.
* **Hisoblar paroldan foydalanmaydi.** Ssenariylar seansni o‘zi imzolaydi (`server.cjs` → `session()`) va brauzer
  xotirasiga qo‘yadi. Qo‘lda parol bilan kirish kerak bo‘lsa — ixtiyoriy `local/accounts.local.json`
  (`{ "<email>": { "uid", "salt", "hash", "displayName" } }`, scrypt; git’ga kirmaydi).
* **Ma’lumot faqat sintetik** (`seed/gen-seed.cjs`): «Sinov …» ismlar, `example.org` / `*.test` e-mail’lar, mavjud
  bo‘lmagan `998 00 …` telefonlar, nol identifikatorlar; qaytarish PIN kodi har urug‘da tasodifiy. Jonli baza nusxasi yoki
  haqiqiy maktab summalari ishlatilmaydi — yangi ssenariyda ham shunday.

## Talablar

| Nima | Izoh |
|---|---|
| PostgreSQL 16 (server + `psql`) | Superuser bilan ulanish (lokal sinov klasteri). Ulanish — `local.env` («Sozlamalar»). |
| PostgREST 12.2.x | Statik bajariluvchi fayl → `local/bin/postgrest` (yoki `E2E_POSTGREST_BIN`). Rasmiy relizlardan (GitHub, PostgREST v12.2.3) qo‘lda yuklab olinadi. |
| Node.js 18+ | `stand.sh`, `server.cjs`, urug‘ generatori, ssenariylar. |
| Playwright + Chromium | Global o‘rnatilgan bo‘lsa — o‘sha; bo‘lmasa `local/npm` ga (pastda). |
| supabase-js to‘plami (tavsiya) | `local/supabase-js.bundle.mjs` — brauzer internetsiz ishlaydi; bo‘lmasa modul esm.sh dan olinadi. |

Playwright va to‘plam (bir marta, internet kerak bo‘lgan yagona qadam; stend o‘zi tashqariga chiqmaydi):

```bash
cd tests/kassa-e2e
mkdir -p local/npm && cd local/npm && npm init -y >/dev/null
npm install playwright @supabase/supabase-js@2 esbuild
npx playwright install chromium
echo "export * from '@supabase/supabase-js';" > entry.mjs
npx esbuild entry.mjs --bundle --format=esm --platform=browser --outfile=../supabase-js.bundle.mjs
```

## Sozlamalar (`local.env`)

Standartlar `env.sh` da (`lib/common.cjs` da ham xuddi shu). O‘zgartirish — shu papkada `local.env` (git’ga kirmaydi):

| O‘zgaruvchi | Standart | Ma’nosi |
|---|---|---|
| `E2E_PGHOST` | `/var/run/postgresql` | PostgreSQL soketi papkasi yoki xost (faqat lokal) |
| `E2E_PGPORT` | `5432` | port |
| `E2E_PGUSER` | `postgres` | superuser |
| `E2E_DB` | `fx_e2e` | stend bazasi (faqat `fx_*`) |
| `E2E_PGRST_PORT` | `59182` | PostgREST (127.0.0.1) |
| `E2E_WEB_PORT` | `59183` | sahifalar + `/rest`, `/auth`, `/storage` emulyatsiyasi (127.0.0.1) |
| `E2E_LOCAL` | `./local` | git’ga kirmaydigan holat: sir, `postgrest.conf`, urug‘, id’lar, loglar, natijalar |
| `E2E_POSTGREST_BIN` | `local/bin/postgrest` | PostgREST fayli |
| `E2E_OUT` | `local/out/shots` | skrinshotlar (`run-all.sh` har ishga tushirishda — `local/out/<vaqt>/shots`) |
| `E2E_SUPABASE_BUNDLE` | `local/supabase-js.bundle.mjs` | supabase-js to‘plami |

Namuna (`local.env`):

```bash
E2E_PGHOST=/var/run/postgresql
E2E_PGPORT=5432
E2E_DB=fx_e2e
```

## Ishga tushirish

```bash
cd tests/kassa-e2e
bash stand.sh setup          # bir marta: local/, JWT siri, dasturlar tekshiruvi → «tayyor: …»
bash run-all.sh              # to‘liq to‘plam (25 o‘tish, ≈ 10 daqiqa) — reliz oldidan shu buyruq
```

`run-all.sh` har o‘tishdan oldin stendni noldan quradi (ssenariylar kunlarni yopadi, hujjat o‘tkazadi — holat
qayta ishlatilmaydi), oxirida stendni to‘xtatadi. Natija: `local/out/<vaqt>/summary.txt` (har qator:
`k5.v2: rc=0 | JAMI (v2): 22/22 | fail=0`), har ssenariy chiqishi `local/out/<vaqt>/<teg>.out`, skrinshotlar
`local/out/<vaqt>/shots/`. Oxirgi qator: `NATIJA: 25 ta o'tish — hammasi o'tdi (…)` — aks holda muammoli qatorlar soni
(chiqish kodi ≠ 0).

Tanlab ishga tushirish: `bash run-all.sh k5 k3 pay:prod legacy:dev ui` (`kN`, `pay:dev|prod`, `legacy:dev|prod`, `ar`, `sl`, `ui`).
Dizayn bitta — yangi (v2): eski dizayn (v1) egasining qarori bilan 2026-11-24 da olib tashlangan; «k5:v2» kabi eski yozuv ham
qabul qilinadi, «:v1» — rad (qator muammo deb sanaladi).

Bitta ssenariyni qo‘lda (tuzatish paytida):

```bash
bash stand.sh reset dev                  # baza noldan (dev zanjir — kassa moduli bilan) + urug‘ + xizmatlar
node scenarios/e2e-kassa5.cjs            # yagona — yangi dizayn (v2)
bash stand.sh reset prod                 # jonli zanjir (kassasiz) — to‘lov va eski oqimlar uchun
node scenarios/e2e-pay.cjs
bash stand.sh down                       # xizmatlarni to‘xtatish
bash stand.sh psql -c "select app.fin_today()"   # stend bazasiga psql
```

`dev` — `migration/chain.sh --dev` (kassa moduli o‘rnatilgan); `prod` — jonli zanjir: kassa o‘rnatilmagan holatda eski
oqimlar o‘zgarmaganini tekshiradi.

## Kutilgan natija

Hamma qatorda `rc=0` va `fail=0`; tekshiruvlar soni — quyidagicha (ssenariyga tekshiruv qo‘shilsa yoki olib tashlansa —
shu jadval ham yangilanadi):

| Teg | Fayl | Nimani tekshiradi | Tekshiruvlar |
|---|---|---|---|
| k1 | `e2e-kassa.cjs` | to‘liq kun sikli: boshlang‘ich qoldiq, sozlamalar, kirim, chiqim so‘rovi → tasdiq → pul berish, naqd o‘quv to‘lovi, bekor qilish, kunni yopish va tekshirish, qayta chop etish | 39 |
| k2 | `e2e-kassa2.cjs` | limit, asos hujjatisiz xarid, 2-ro‘yxat + Direktor, rad etish, ikki bosqichli smena topshirish, navbatdagi to‘lov, kamomad / ortiqcha, qayta ochish | 40 |
| k3 | `e2e-kassa3.cjs` | naqd va karta orqali maosh, ish haqi avansi, qaytarish (Direktor tasdig‘i), xarajat «Buxgalteriya»ga; to‘xtatilgan kassada usul tanlovi | 28 |
| k4 | `e2e-kassa4.cjs` | kunlik hisobot (RP-02), nazorat ro‘yxati (RP-06: eskirgan smena topshirish), dalolatnomalar va «НУСХА», kutilayotgan smena kartasi | 36 |
| k5 | `e2e-kassa5.cjs` | o‘zaro hisob (maosh hisobidan farzand to‘lovi), dalolatnoma, bekor qilish | 22 |
| k6 | `e2e-kassa6.cjs` | davr surati va qulfi, maosh berish huquqi | 31 |
| k7 | `e2e-kassa7.cjs` | Buxgalter (2-ro‘yxat): tasdiq, kunni tekshirish (qayta ochilishidan oldin yopgan xodim — yo‘q), chop etish faqat «НУСХА», nazorat ro‘yxati, «Davr» | 32 |
| k8 | `e2e-kassa8.cjs` | onlayn kassa Z-hisoboti bilan solishtirish; kech kirim — NKM smenasi kuniga, Z tuzatilgani nazoratda | 35 |
| k9 | `e2e-kassa9.cjs` | yuridik shaxsga naqd to‘lov: ogohlantirish, Direktor tasdig‘i, chegara; kontragent turini tasdiqlash, ikki marta bosish | 18 |
| k10 | `e2e-kassa10.cjs` | KO-3 jurnali, chop etish, Excel (FD-28) | 17 |
| k11 | `e2e-kassa11.cjs` | RP-08 statiya matritsasi, oylik kassa to‘plami (Excel) | 17 |
| k12 | `e2e-kassa12.cjs` | eslatmalar (muddati o‘tgan avans), RP-22 KPI | 13 |
| k13 | `e2e-kassa13.cjs` | to‘liq Buxgalter roli: faqat ko‘rish, telefon yo‘q, ismsiz hisobotlar, «Profil» | 39 |
| k14 | `e2e-kassa14.cjs` | ikki bosqichli smena topshirish («Qabul qildim», «Rad etish», komissiya), yopish / topshirishdan oldin navbat yuborilishi va kassa:stale, «Yuborilmadi» yozuvlari uchun tanlov, sinov kassasi navbatsiz, «Қ» blankalari, #kc-ho / #kc-skip, kamomad qarori (javobgar kartasi) | 41 |
| k15 | `e2e-kassa15.cjs` | qaytarish oynasi kaliti (kassa ishga tushgan: usul qulfi, naqd ↔ naqdsiz rad), Direktor o‘ziga pul bermasligi (FD-48), «To‘lov» oynasida rad etilgan yozuvni almashtirish, pul maydonlari, to‘xtatilgan kassa usul tanlovi | 29 |
| k16 | `e2e-kassa16.cjs` | T1 (katta kirim qayta so‘raladi; chiqim — 2-ro‘yxat + Direktor), server rad etsa «Tasdiqlash» qayta yoqiladi, ishdan ketgan xodim, asosiy ↔ sinov kassa (sinov kassasida navbat yo‘q) | 31 |
| k17 | `e2e-kassa17.cjs` | FD-28 fayllari: qarzdorlar CSV («Moliya»), «Buxgalteriya» A4 hisoboti, xodimlar davomati oylik hisoboti — Direktorga (davomatda HR’ga ham) ismli; Moliya menejeri, buxgalter va kassirga ismsiz (o‘quvchi ID, xodim maosh ID’si — «Kamera ID»siz xodimning ruhsati ham, «-ismsiz», izoh), qolgan ustunlar qatorma-qator va jamlar bir xil; ekrandagi ro‘yxat ism bilan | 27 |
| k18 | `e2e-kassa18.cjs` | «Kassir» roli (egasi, 2026-11-17): asosiy rol «Kassir» — ochiq kunda kassa kitobi varag‘i (qoralama), kunni yopish, yopilgan kunning yakuniy kunlik hisoboti va kassa kitobi varag‘i («НУСХА»); Direktor: rol tanlovida yangi «Kassir» / «G‘aznachi» yozuvlari, «G‘aznachi» lavozimli kartaga bog‘langan yangi xodimga «Kassir» oldindan tanlanadi (kirim, chiqim so‘rovi, pul berish — k1; ochiq kun hisoboti — k4) | 9 |
| pay | `e2e-pay.cjs` | kassirning qo‘lda to‘lovi (onlayn va oflayn navbat) | dev 12, prod 12 |
| legacy | `e2e-legacy.cjs` | kassa ishga tushmagan / o‘rnatilmagan holatda eski oqimlar; qaytarish oynasi (oddiy yo‘l): javob yo‘qolgach o‘zgartirilgan qayta yuborish rad | dev 17, prod 15 |
| ar | `e2e-arxiv.cjs` | o‘quvchilar arxivi (egasi, 2026-11-18): chiqarilgan / bitirgan o‘quvchi faol sondan chiqadi (jami, sinf kartasi, bosh sahifa, kassir ro‘yxati), qidiruvda arxivga havola, kelajak sana bilan chiqarish, «🗄 Arxiv» va filtrlar, 📨 ma’lumotnoma (QR, telefon / to‘lovsiz), 🎓 bitiruv, baho va monitoring jurnallari, ↩️ qaytarish, qabulxona ⏹️, uning ma’lumotnomasi (baho / davomat — student_certificate), O‘IBDO‘ menyusida Arxiv, kassir qidiruvi; qabulxona ichki ma’lumotnomasi (oyna va «🖨 Ichki hisobot») — davomat, baho, xarakteristika yig‘madan, oylik xulosa «ko‘rsatilmaydi» | 30 |
| sl | `e2e-sales.cjs` | «Sotuvchi» roli (egasi, 2026-11-19): menyuda yagona «Ota-onalar bilan aloqa» bo‘limi, faol oilalar (arxivdagisiz) niqoblangan raqam bilan, «📞 Raqamni ko‘rsatish» → tel: havolasi va jurnal yozuvi, hisoblagich, ota-ona ismi bo‘yicha qidiruv; 🔍 qidiruv, to‘lov navbati, tahrir / eksport tugmasi yo‘q; kirishda konsol xatosi va RLS rad etgan so‘rov yo‘q; REST (sotuvchi seansi): o‘quvchi, shaxsiy karta, faktura — bo‘sh, jurnal va Direktor jurnali — rad, o‘zini Direktor qila olmaydi; Direktor: bo‘lim «O‘quvchilar» guruhida, «Sotuvchilar jurnali», «Foydalanuvchilar»dagi rol tanlovi, «Tahrirlash» oynasida sotuvchi ism-familiyasini o‘zgartirish (rol va holat o‘zgarmaydi) | 15 |
| ui | `e2e-ui.cjs` | yagona dizayn (egasi, 2026-11-24): qurilmada eski tanlov (`iqror_ui = 'v1'`) va manzilda `?ui=v1` bo‘lsa ham yangi dizayn ochiladi, eski tanlov o‘chiriladi; kompyuterda ikonali panel, telefonda pastki menyu; Direktor bosh sahifasi yangi (klassik bloklar yo‘q); «Profil»da dizayn almashtirgichi yo‘q; sahifa xatolari yo‘q — 5 rol × 1440 / 390 | 42 |

Jami: 25 o‘tish, 647 tekshiruv (kassa 504, to‘lov 24, eski oqimlar 32, arxiv 30, sotuvchi 15, yagona dizayn 42).

**Holat (2026-11-24).** Oxirgi to‘liq yashil o‘tish — 2026-11-24 (faqat yangi dizayn): 25 o‘tish, 647 tekshiruv — hammasi o‘tdi
(≈ 10 daqiqa). Kod — eski dizayn (v1) olib tashlangandan keyingi holat (`SESSIYA-ISHLARI.md` §86; «Sotuvchi» oilalari — §85, 14-raund
tuzatishlari): kassa, to‘lov, eski oqimlar, arxiv va sotuvchi ssenariylari faqat yangi dizaynda; yangi `ui` — eski tanlov va `?ui=v1`
bilan ham yangi dizayn ochilishi.

**Oldingi holat (2026-11-20).** To‘liq yashil o‘tish — 2026-11-20: har ssenariy ikkala dizaynda (v1 va v2), 44 o‘tish, 1154 tekshiruv
(oxirgi ikki dizaynli to‘liq o‘tish — 2026-11-24, 735cae3: `SESSIYA-ISHLARI.md` §85, 13- va 14-mustaqil tekshiruv).
Kod — «Sotuvchi» roli va uning uch raund mustaqil tekshiruvi tuzatishlari hamda RLS orqali vaqt bo‘yicha sizishni yopish (anon
yopiq ro‘yxati, RLS yordamchilari plpgsql, policy darvozalari — `SESSIYA-ISHLARI.md` §85): kassa (k1–k18), qo‘lda to‘lov (pay),
eski oqimlar (legacy) va arxiv (ar) shu o‘zgarishlardan keyin ham o‘tadi; `sl` — Direktor «Foydalanuvchilar» → «Tahrirlash»
oynasida sotuvchi ism-familiyasini o‘zgartiradi (rol va holat o‘zgarmaydi, bazada tekshiriladi; 3-tekshiruvdan oldingi admin.html
da bu maydonlar yo‘q — tekshiruv yiqiladi).

**Oldingi holat (2026-11-19).** To‘liq yashil o‘tish — 2026-11-19: 42 o‘tish, 1124 tekshiruv — hammasi o‘tdi (≈ 16 daqiqa).
Kod — platformaning to‘liq auditi tuzatishlaridan keyingi holat (8 yo‘nalish, 66 topilma, uch raund mustaqil tekshiruv —
`SESSIYA-ISHLARI.md` §84): to‘lov yozuvi faqat ishonchli yo‘ldan, moliya rollari fakturani «to‘landi» qila olmaydi, avans darhol
ochiq qarzga, avans va maosh yozuvini o‘chirish / kamaytirish faqat Direktor — kassa (k1–k18), qo‘lda to‘lov (pay) va eski oqimlar
(legacy) shu o‘zgarishlardan keyin ham o‘tadi; arxiv ssenariysi (ar) qabulxona ichki ma’lumotnomasi (oyna va «🖨 Ichki hisobot»)
davomat, baho va xarakteristikani `student_certificate` yig‘masidan ko‘rsatishini ham tekshiradi (30 tekshiruv; audit tuzatishidan
oldingi admin.html da 28/30).

**Oldingi holat (2026-11-16).** To‘liq yashil o‘tish — 2026-11-16: 38 o‘tish, 1046 tekshiruv — hammasi o‘tdi (≈ 14 daqiqa).
Kod — modul relizi 12 va FD-28 fayllari (qarzdorlar CSV, «Buxgalteriya» A4 hisoboti, xodimlar davomati oylik hisoboti —
Direktordan boshqalarga ismsiz nusxa): ularni yangi k17 tekshiradi — ismsiz nusxa Direktor nusxasi bilan qatorma-qator va
jamlari bo‘yicha solishtiriladi; k17 tekshiruvlari mahsulot kodini vaqtincha buzib (FD-28 o‘zgarishini qaytarib yoki ismsiz
nusxadagi qiymatni o‘zgartirib) yiqilishi ko‘rsatilgan. Oldingi to‘liq o‘tish — 2026-11-15 (reliz 12: kassa moduli mustaqil
ko‘rigi va yakuniy ko‘rik tuzatishlaridan keyingi kod; 36 o‘tish, 992 tekshiruv). O‘sha ko‘rikda o‘zgargan oqimlar (ikki bosqichli
smena topshirish, yopish va topshirishdan oldin navbat yuborilishi va kassa:stale, «Yuborilmadi» yozuvlari uchun tanlov, sinov
kassasi, qaytarish oynasi kaliti, Direktor o‘ziga pul bermasligi, chop etish belgilari, T1, ishdan ketgan xodim) k14–k16 va
yangilangan k1–k13, pay, legacy da tekshiriladi; har yangi tekshiruv mahsulot kodini vaqtincha eski holatiga qaytarib yiqilishi
ko‘rsatilgan.

## Ssenariy yozish va tahrirlash

Har ssenariy — mustaqil Node skripti; umumiy qismi `lib/common.cjs` da:

```js
const E = require('../lib/common.cjs');
const { session, ids, q } = E;                 // q(sql) — stend bazasida postgres nomidan so‘rov (natija — matn)
const b = await E.launch();                    // chromium; tashqi xostlar yopiq
const ctx = await b.newContext({ timezoneId: 'Asia/Tashkent' });
await ctx.addInitScript(([k, v]) => localStorage.setItem(k, v),
  ['sb-127-auth-token', JSON.stringify(session(ids.R_KAS, 'kassir@example.org', { displayName: 'SINOV' }))]);
const pg = await ctx.newPage();
await pg.goto(E.BASE + '/admin.html');
```

* Rollar: `ids.R_DIR` (Direktor), `ids.R_MOL` (moliya menejeri), `ids.R_KAS` (kassir), `ids.R_REC`, `ids.R_TCH` va
  boshqalar — `local/ids.json` (urug‘ generatori yaratadi, keyingi qurishlarda o‘sha id’lar).
* Tekshiruv: `ok(nom, shart, tafsilot)` → `PASS …` / `FAIL …` qatori; oxirida `JAMI (v2): o‘tgan/jami` va chiqish kodi
  (0 — faqat hammasi o‘tsa). `run-all.sh` oxirgi `JAMI` qatorini va `FAIL` / `XATO` qatorlar sonini yig‘adi.
* Sana: ilova `app.fin_today()` ga tayanadi; kunni surish — `app.fin_clock` (`k2`, `k8`, `k12` dagi kabi), oxirida
  albatta o‘chiriladi.
* Urug‘ga bog‘liq qiymatlar (ism, summa) — bazadan o‘qiladi (`q(...)`), ssenariyga yozib qo‘yilmaydi.
* Yangi ssenariy `run-all.sh` dagi `run()` ga (teg bilan) va shu README jadvaliga qo‘shiladi.

## Muammolar

| Belgi | Nima qilish kerak |
|---|---|
| `JWT siri yo'q` | `bash stand.sh setup` |
| `zanjir XATO` | `local/logs/chain.log` — birinchi `ERROR` va undan oldingi `-> fayl` qatori |
| `xizmatlar ko'tarilmadi` | `local/logs/postgrest.log`, `local/logs/server.log`; port band bo‘lsa — `local.env` da boshqa port |
| `STEND QURILMADI` (summary) | `local/out/<vaqt>/reset.out` |
| ssenariy yarim yo‘lda to‘xtadi | baza holati o‘zgargan — qayta ishga tushirishdan oldin `bash stand.sh reset dev` |
