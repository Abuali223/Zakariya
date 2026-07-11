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
| `click.serviceId` / `click.merchantId` | Click merchant kabinetidan (maxfiy emas) |
| `click.secretKey` | Click **maxfiy** kaliti (SECRET_KEY) — imzo tekshiruvi uchun |
| `uzum.*` | Uzum merchant ma'lumotlari (aniq maydonlar Uzum hujjatiga qarab) |

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

## 6. Uzum
`/uzum/webhook` — **asos (scaffold)**. Uzum merchant hisobingizdagi aniq maydon
nomlari, imzo (HMAC/shared secret) va prepare/confirm oqimini hujjatga qarab
`handleUzum()` ichida yakunlaymiz. Uzum hujjatini/kalitlarini bergач, ulaymiz.

## Xavfsizlik
- `service-account.json`, `click.secretKey`, `uzum.secret` — maxfiy. `.gitignore` bor.
- «paid» statusини faqat shu server yozadi (Firestore qoidalari mijozga taqiqlaydi).
- Har bir to'lov `payments` kolleksiyasida jurnalga yoziladi.
