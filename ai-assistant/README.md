# Iqror — AI yordamchi (assistant)

Bitta server, uchta vazifa. Barchasi **Claude AI** orqali ishlaydi va **Anthropic
kaliti faqat shu serverda** saqlanadi (saytga/gitga tushmaydi).

| Endpoint | Vazifa |
|---|---|
| `POST /chat` | Sayt uchun ota-onalar chatboti (narx, yo'nalish, qabul — UZ/RU). Faqat ommaviy maktab ma'lumoti (sayt kontakti, tariflar, yo'nalishlar, qabul, FAQ) asosida — o'quvchi/ota-ona ma'lumoti kontekstga QO'SHILMAYDI. |
| `POST /student-summary` | Bitta o'quvchi bo'yicha ota-onaga oylik xulosa. ⚠️ **Standart holda O'CHIQ** — `410 {"error":"disabled","message":"Bu xizmat vaqtincha o‘chirilgan"}`. |
| `POST /risk` | Orqada qolayotgan o'quvchilar + AI tavsiya. ⚠️ **Standart holda O'CHIQ** (410). |

**O'quvchi ma'lumoti tashqi AI xizmatiga ketmaydi.** `/student-summary` va `/risk` o'quvchi ismi, davomati, bahosi va qarzini
Anthropic'ga yuborardi — shaxsiy ma'lumotni uchinchi tomonga berish uchun huquqiy asos (huquqshunos ruxsati) kerak. Ruxsatdan
keyin `config.json`da `"allowStudentData": true` qiling va xizmatni qayta ishga tushiring (`sudo systemctl restart iqror-ai`) —
yo'llar avvalgidek (ruxsat tekshiruvi bilan) ishlaydi; kod saqlangan. CLI'dagi `summary` va AI tavsiyali `risk` ham shu
sozlamaga bo'ysunadi (`node index.cjs risk norec` — faqat qoida bo'yicha ro'yxat, AI'siz — ishlayveradi).

**To'lov qoidasi (chatbot):** maktabda to'lov FAQAT OYLIK — yillik, yarim yillik, choraklik reja va oldindan to'lov chegirmasi
YO'Q. Bu tizim matnida qat'iy yozilgan (bazadagi FAQ boshqacha desa ham), bazadagi eski FAQ/tarif matnidagi shunday jumlalar
esa AI'ga umuman berilmaydi.

## 1. Tayyorgarlik
```bash
cd ai-assistant
npm install
cp config.example.json config.json      # to'ldiring
```
`config.json`:
| Maydon | Ma'nosi |
|---|---|
| `serviceAccount` | Firebase xizmat hisobi kaliti yo'li (git'ga qo'ymang) |
| `anthropicKey` | Claude (Anthropic) API kaliti — **maxfiy**. Uch manzildan biri: shu yerda, `ANTHROPIC_API_KEY` muhit o'zgaruvchisi, YOKI **admin panel → Sozlamalar → AI yordamchi** (Firestore `secrets/ai` ga yoziladi, faqat server o'qiydi). config.json bo'sh bo'lsa server avtomatik `secrets/ai` dan oladi. |
| `model` | Model (standart: eng kuchli) |
| `port` | Server porti (masalan 8791) |
| `allowOrigin` | Saytingiz manzili (CORS) — masalan `https://alilazer-cd582.web.app` |
| `riskAttendance` / `riskScore` | Xavf chegaralari (standart 80% / 60 ball) |
| `allowStudentData` | `false` (standart) — `/student-summary`, `/risk` o'chiq (410). `true` — faqat huquqshunos ruxsatidan keyin |

## 2. Tekshirish va ishga tushirish
```bash
npm test                            # birlik testlari (tarmoqsiz: 410, /chat konteksti, to'lov qoidasi)
node index.cjs test                 # kalit ishlaydimi (Anthropic'ga haqiqiy so'rov; npm run check-key)
node index.cjs chat "narx qancha?"  # chatbotni sinash
node index.cjs summary IQ-0002      # bitta o'quvchi xulosasi
node index.cjs risk                 # xavf ostidagilar
node index.cjs serve                 # HTTP server (/chat, /student-summary, /risk)
```
Doimiy ishlashi uchun `pm2`/`systemd`. Sayt bilan gaplashishi uchun **HTTPS** manzil kerak
(domen yoki statik IP + reverse-proxy). CORS `allowOrigin` orqali sizning saytga ruxsat beriladi.

## 3. Saytga ulash (config/ai)
Sayt chatboti server manzilini `config/ai` hujjatidan oladi. Admin panel orqali yoki
qo'lda Firestore'da yozing:
```
config/ai = { "url": "https://<server-domeningiz>", "enabled": true }
```
`url` bo'lsa — saytda «Yordam» chatboti va admin paneldagi «AI xulosa» tugmasi paydo bo'ladi.
`url` bo'lmasa — hech narsa ko'rinmaydi (xavfsiz standart).

## Xavfsizlik
- `anthropicKey`, `service-account.json`, `config.json` — **maxfiy**. `.gitignore` bor, git'ga tushmaydi.
- Server Firestore'ni **Admin SDK** orqali o'qiydi; sayt esa faqat `config/ai` (ochiq) ni ko'radi.
- Chatbot faqat maktab ma'lumoti asosida javob beradi va noaniq narsani o'ylab topmaydi (prompt qoidasi).
- Narx: har so'rov arzon; effort «low» ishlatilgan (tez va tejamli). Hajmga qarab Anthropic hisobida ko'rinadi.
