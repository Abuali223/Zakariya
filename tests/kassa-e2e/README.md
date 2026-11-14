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
bash run-all.sh              # to‘liq to‘plam (30 o‘tish, ≈ 10–15 daqiqa) — reliz oldidan shu buyruq
```

`run-all.sh` har o‘tishdan oldin stendni noldan quradi (ssenariylar kunlarni yopadi, hujjat o‘tkazadi — holat
qayta ishlatilmaydi), oxirida stendni to‘xtatadi. Natija: `local/out/<vaqt>/summary.txt` (har qator:
`k5.v1: rc=0 | JAMI (v1): 22/22 | fail=0`), har ssenariy chiqishi `local/out/<vaqt>/<teg>.out`, skrinshotlar
`local/out/<vaqt>/shots/`. Oxirgi qator: `NATIJA: 30 ta o'tish — hammasi o'tdi (…)` — aks holda muammoli qatorlar soni
(chiqish kodi ≠ 0).

Tanlab ishga tushirish: `bash run-all.sh k5:v1 k3:v2 pay:prod legacy:dev` (`kN:v1|v2`, `pay:dev|prod`, `legacy:dev|prod`).

Bitta ssenariyni qo‘lda (tuzatish paytida):

```bash
bash stand.sh reset dev                  # baza noldan (dev zanjir — kassa moduli bilan) + urug‘ + xizmatlar
node scenarios/e2e-kassa5.cjs v2         # v1 — eski dizayn, v2 — yangi dizayn (ikkalasi ham o‘tishi kerak)
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
| k1 | `e2e-kassa.cjs` | to‘liq kun sikli: boshlang‘ich qoldiq, sozlamalar, kirim, chiqim so‘rovi → tasdiq → pul berish, naqd o‘quv to‘lovi, bekor qilish, kunni yopish va tekshirish, qayta chop etish | v1 36, v2 36 |
| k2 | `e2e-kassa2.cjs` | limit, asos hujjatisiz xarid, 2-ro‘yxat + Direktor, rad etish, smena topshirish, navbatdagi to‘lov, kamomad / ortiqcha, qayta ochish | v1 35, v2 35 |
| k3 | `e2e-kassa3.cjs` | naqd va karta orqali maosh, ish haqi avansi, qaytarish (Direktor tasdig‘i), xarajat «Buxgalteriya»ga | v1 26, v2 26 |
| k4 | `e2e-kassa4.cjs` | kunlik hisobot (RP-02), nazorat ro‘yxati (RP-06) | v1 24, v2 24 |
| k5 | `e2e-kassa5.cjs` | o‘zaro hisob (maosh hisobidan farzand to‘lovi), dalolatnoma, bekor qilish | v1 22, v2 22 |
| k6 | `e2e-kassa6.cjs` | davr surati va qulfi, maosh berish huquqi | v1 31, v2 31 |
| k7 | `e2e-kassa7.cjs` | Buxgalter (2-ro‘yxat): tasdiq, kunni tekshirish, nazorat ro‘yxati, «Davr» | v1 26, v2 26 |
| k8 | `e2e-kassa8.cjs` | onlayn kassa Z-hisoboti bilan solishtirish | v1 28, v2 28 |
| k9 | `e2e-kassa9.cjs` | yuridik shaxsga naqd to‘lov: ogohlantirish, Direktor tasdig‘i, chegara | v1 12, v2 12 |
| k10 | `e2e-kassa10.cjs` | KO-3 jurnali, chop etish, Excel (FD-28) | v1 17, v2 17 |
| k11 | `e2e-kassa11.cjs` | RP-08 statiya matritsasi, oylik kassa to‘plami (Excel) | v1 17, v2 17 |
| k12 | `e2e-kassa12.cjs` | eslatmalar (muddati o‘tgan avans), RP-22 KPI | v1 13, v2 13 |
| k13 | `e2e-kassa13.cjs` | to‘liq Buxgalter roli: faqat ko‘rish, telefon yo‘q, ismsiz hisobotlar, «Profil» | v1 39, v2 39 |
| pay | `e2e-pay.cjs` | kassirning qo‘lda to‘lovi (onlayn va oflayn navbat) | dev 12, prod 12 |
| legacy | `e2e-legacy.cjs` | kassa ishga tushmagan / o‘rnatilmagan holatda eski oqimlar | dev 13, prod 11 |

Jami: 30 o‘tish, 700 tekshiruv (kassa 2 × 326, to‘lov 24, eski oqimlar 24).

**Holat (2026-11-14).** Oxirgi to‘liq yashil o‘tish — 2026-11-13, kassa moduli mustaqil ko‘rigi tuzatishlaridan oldingi
kod bilan (k13 da o‘shanda 38 ta edi; 39-tekshiruv — «Profil» — keyingi tuzatish bilan qo‘shilgan). Ko‘rik tuzatishlari
(ayniqsa smena topshirish, oflayn navbat, kunni yopish va chop etish bo‘yicha guruhlar) kassa ekranlaridagi ba’zi oqimlarni
o‘zgartirdi — masalan, smena topshirish endi ikki bosqichli (qabul qiluvchi «Qabul qildim» deb tasdiqlaydi), yopish va
topshirish shakllari avval navbatdagi yozuvlarni yuboradi. Shunday oqimlarga tegadigan tekshiruvlar reliz oldidan
yangilanadi va to‘plam qayta o‘tkaziladi; sonlar o‘zgarsa — yuqoridagi jadval ham.

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
* Tekshiruv: `ok(nom, shart, tafsilot)` → `PASS …` / `FAIL …` qatori; oxirida `JAMI (v1|v2): o‘tgan/jami` va chiqish kodi
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
