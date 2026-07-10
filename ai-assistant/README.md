# Iqror — AI yordamchi (assistant)

Bitta server, uchta vazifa. Barchasi **Claude AI** orqali ishlaydi va **Anthropic
kaliti faqat shu serverda** saqlanadi (saytga/gitga tushmaydi).

| Endpoint | Vazifa |
|---|---|
| `POST /chat` | Sayt uchun ota-onalar chatboti (narx, yo'nalish, qabul — UZ/RU). Maktab ma'lumoti asosida javob beradi. |
| `POST /student-summary` | Bitta o'quvchi bo'yicha ota-onaga tushunarli oylik xulosa (davomat/baho/monitoring/to'lov). |
| `POST /risk` | Orqada qolayotgan o'quvchilarni aniqlaydi (qoida) + har biriga AI tavsiya. |

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
| `anthropicKey` | Claude (Anthropic) API kaliti — **maxfiy**. Yoki `ANTHROPIC_API_KEY` muhit o'zgaruvchisi |
| `model` | Model (standart: eng kuchli) |
| `port` | Server porti (masalan 8791) |
| `allowOrigin` | Saytingiz manzili (CORS) — masalan `https://alilazer-cd582.web.app` |
| `riskAttendance` / `riskScore` | Xavf chegaralari (standart 80% / 60 ball) |

## 2. Tekshirish va ishga tushirish
```bash
node index.cjs test                 # kalit ishlaydimi
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
