# Iqror — To'lov serveri (Click + Uzum)

Ota-ona kabinetdagi **oylik to'lov** hisob-fakturasini Click yoki Uzum orqali
to'laganda, to'lov tizimi shu serverga chaqiruv (callback) yuboradi. Server
imzoni tekshirib, `invoices/<id>` hujjatini **«paid»** qiladi. Admin panelda va
kabinetda darhol «To'landi» ko'rinadi.

> ⚠️ **Pul bilan ishlaydi.** Maxfiy kalitlar faqat shu serverda saqlanadi
> (saytga/gitga tushmaydi). Serverni **HTTPS** orqasida, ishonchli joyda
> ishlating (statik IP yoki domen kerak — to'lov tizimi shu manzilga murojaat qiladi).

## 1. Tayyorgarlik
1. Node.js 18+.
2. Firebase **xizmat hisobi kaliti** → `service-account.json` (shu papkaga). Git'ga qo'ymang.
3. **Merchant kalitlari:** Click va Uzum merchant kabinetlaridan.

## 2. Sozlash
```bash
cd payments
npm install
cp config.example.json config.json
```
`config.json`:
| Maydon | Ma'nosi |
|---|---|
| `serviceAccount` | Firebase xizmat hisobi yo'li |
| `port` | Server porti (masalan 8790) |
| `uzum.serviceId` | Uzum kabinetidagi **xizmat ID** (serviceId) |
| `uzum.login` / `uzum.password` | Uzum callback'lari uchun **Basic-auth** login/parol (kabinetdan) — parol **MAXFIY** |
| `uzum.accountField` | Uzum `params` ichidagi hisob-faktura maydoni nomi (kabinetda belgilaysiz, masalan `invoice`) |
| `uzum.amountUnit` | `tiyin` (default — Uzum so'm×100 yuboradi) yoki `som` |
| `click.serviceId` / `click.merchantId` | (Ixtiyoriy) Click merchant kabinetidan (maxfiy emas) |
| `click.secretKey` | (Ixtiyoriy) Click **maxfiy** kaliti (SECRET_KEY) — imzo tekshiruvi uchun |

## 3. Ishga tushirish
```bash
node index.cjs
# Iqror to'lov serveri tinglayapti :8790  (/click/prepare, /click/complete, /uzum)
```
Doimiy ishlashi uchun `pm2`/`systemd`. Tashqi HTTPS manzil kerak (masalan `nginx` reverse-proxy + domen).

## 4. Click merchant kabinetida URL sozlash
Click **SHOP-API** (Merchant API) uchun ikki manzilni kiriting:
- **Prepare URL:** `https://<domeningiz>/click/prepare`
- **Complete URL:** `https://<domeningiz>/click/complete`

Click ikki bosqichda chaqiradi (Prepare → Complete). Imzo:
`md5(click_trans_id + service_id + SECRET_KEY + merchant_trans_id [+ merchant_prepare_id] + amount + action + sign_time)`.
Bu server imzoni tekshiradi, summani hisob-faktura bilan solishtiradi, ikki marta
to'lashning oldini oladi va faqat to'g'ri to'lovda «paid» qiladi.

## 5. Saytda to'lov havolasi (config/payments)
Kabinet «Click» tugmasini `config/payments` hujjatidagi ochiq IDlardan tuzadi.
Admin panel orqali yoki qo'lda Firestore'da quyidagini yozing:
```
config/payments = {
  clickServiceId: "<service_id>",
  clickMerchantId: "<merchant_id>",
  uzumUrlTemplate: "https://checkout.uzum.uz/pay?amount={amount}&order={invoice}"   // Uzum tayyor bo'lganda
}
```
`clickServiceId`/`clickMerchantId` — maxfiy EMAS (to'lov havolasida ko'rinadi).
**`secretKey` bu yerga YOZILMAYDI** — u faqat shu serverdagi `config.json` da.

## 6. Uzum Merchant API (asosiy usul) — TO'LIQ
Uzum **5 ta endpoint** ni chaqiradi (server-to-server, har birida **Basic auth**
`login:password`). Server so'rovni tekshirib, `invoices/<id>` ni boshqaradi:

| Endpoint | Vazifa | Natija |
|---|---|---|
| `POST /uzum/check`   | hisob-faktura bor/to'lanmaganini tekshirish | `status:OK` |
| `POST /uzum/create`  | tranzaksiya yaratish (rezerv) | `status:CREATED` |
| `POST /uzum/confirm` | to'lov tasdiqlandi → invoice **«paid»** ★ | `status:CONFIRMED` |
| `POST /uzum/reverse` | qaytarish (refund) → invoice **«reversed»** | `status:REVERSED` |
| `POST /uzum/status`  | tranzaksiya holati | joriy status |

Xato javobi: `{ serviceId, timestamp, status:"FAILED", errorCode }`. Kodlar:
`10001` auth, `10005` params yetarli emas, `10006` serviceId noto'g'ri,
`10007` allaqachon to'langan, `10008` topilmadi, `99999` summa/tekshiruv xatosi.

**Xavfsizlik:** har chaqiruvda `serviceId` va Basic-auth login/parol tekshiriladi;
summa hisob-faktura bilan solishtiriladi (default **tiyin** = so'm×100); ikki marta
to'lash/tasdiqlash oldi olinadi (idempotent).

### Uzum kabinetida sozlash
1. **Callback (webhook) manzili** sifatida quyidagini kiriting:
   `https://<domeningiz>/pay/uzum` — Uzum unga `/check`, `/create`, `/confirm`,
   `/reverse`, `/status` qo'shib chaqiradi (masalan `https://iqroacademy.uz/pay/uzum/check`).
2. **Basic-auth** login va parolni belgilang → `config.json` dagi `uzum.login`/`uzum.password`.
3. **Hisob (account) parametri** nomini belgilang (masalan `invoice`) →
   `config.json` dagi `uzum.accountField`. Uzum bu maydonda hisob-faktura `id` sini yuboradi.
4. **serviceId** ni `config.json` ga yozing.

> ⚠️ **Summa birligi** (tiyin/so'm) va `params` maydon nomi kabinet sozlamasiga
> bog'liq — jonli rejimga o'tishdan oldin **kichik test to'lov** bilan tekshiring.

Sinov:  `node payments/uzum.test.cjs`  (soxta Supabase ustida to'liq oqim).

## 7. SMS xabarnomalari (Eskiz.uz) — faktura + qarzdorlik eslatmasi

`sms-worker.cjs` **cron** bilan ishlaydigan alohida jarayon. Ikki vazifa:
1. **Yangi faktura:** oxirgi `newLookbackDays` (default 14) kunda yaratilgan,
   to'lanmagan (`amount>0`) fakturalar uchun ota-ona telefoniga bir marta SMS.
2. **Qarzdorlik:** oyning **10-sanasidan keyin** (`reminderDayOfMonth`) to'lanmagan
   fakturalar uchun **haftada 2 marta** (`reminderDays`, default Dushanba+Payshanba) eslatma.

Takror ketmasligi uchun har SMS `sms_log` jadvaliga yoziladi
(id: `<invoiceId>__new` yoki `<invoiceId>__debt__<sana>`). Telefon
`student_private.parentPhone` (bo'lmasa `parentPhone2`) dan olinadi.

### 7.1 Sozlash (`config.json` → `sms`)
| Maydon | Ma'nosi |
|---|---|
| `enabled` | `true`/`false` — SMS'ni yoqish/o'chirish |
| `dryRun` | `true` bo'lsa **yubormaydi**, faqat log qiladi (sinov uchun) |
| `eskizEmail` / `eskizPassword` | Eskiz kabinet emaili/paroli — **MAXFIY** (token o'zi yangilanadi) |
| `token` | (Muqobil) Eskiz panelidan olingan tayyor token — email/parol o'rniga |
| `from` | Jo'natuvchi nomi (nickname). Eskiz'da tasdiqlangan bo'lishi shart (test: `4546`) |
| `newLookbackDays` | Yangi faktura xabarlari uchun necha kun orqaga qaraladi (default 14) |
| `reminderDayOfMonth` | Shu sanadan **keyin** qarzdorlik eslatiladi (default 10) |
| `reminderDays` | Hafta kunlari (0=Yak … 6=Shan). Default `[1,4]` = Dush+Pay |
| `templates.new` / `templates.debt` | SMS matni. O'rinbosarlar: `{name} {month} {amount} {due}` |

> ⚠️ **Eskiz moderatsiyasi:** Eskiz ixtiyoriy matn yubormaydi — SMS matni
> Eskiz panelida **oldindan tasdiqlangan shablonga** mos bo'lishi kerak.
> `templates.new`/`templates.debt` matnini Eskiz'da tasdiqlang (yoki tasdiqlangan
> matnni shu yerga qo'ying). `from` (nickname) ham tasdiqlangan bo'lsin.

### 7.2 Sinov (hech narsa yubormaydi)
```bash
cd payments
node sms-worker.cjs --dry            # kimga qanday SMS ketishini ko'rsatadi
```

### 7.3 Ishga tushirish
```bash
node sms-worker.cjs                  # ikkalasi (qarzdorlik faqat reminderDays kunlari)
node sms-worker.cjs new              # faqat yangi faktura xabarlari
node sms-worker.cjs debt             # faqat qarzdorlik (kun tekshiruvisiz, majburiy)
```

### 7.4 CRON (tavsiya)
`crontab -e` (yo'llarni o'zingizniki bilan almashtiring; ustma-ust tushmasin — `flock`):
```
# Yangi faktura xabarlari — har 2 soatda
0 */2 * * *  cd /home/ubuntu/iqror-repo/payments && flock -n /tmp/iqror-sms.lock node sms-worker.cjs new  >> /var/log/iqror-sms.log 2>&1
# Qarzdorlik eslatmasi — Dush va Pay, 10:00 (10-sanadan keyingilar avtomat filtrlanadi)
0 10 * * 1,4 cd /home/ubuntu/iqror-repo/payments && flock -n /tmp/iqror-sms.lock node sms-worker.cjs debt >> /var/log/iqror-sms.log 2>&1
```
> `reminderDays` `config.json`da ham bor — cron kuni bilan mos bo'lsin (yoki `debt`
> rejimи kun tekshiruvisiz majburiy ishlaydi, cron kunini o'zi belgilaydi).

### 7.5 Migratsiya
`sms_log` jadvali kerak:
```bash
sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/sms-log.sql
```

## Xavfsizlik
- `service-account.json`, `click.secretKey`, `uzum.secret` — maxfiy. `.gitignore` bor.
- «paid» statusини faqat shu server yozadi (Firestore qoidalari mijozga taqiqlaydi).
- Har bir to'lov `payments` kolleksiyasida jurnalga yoziladi.
