# Iqror — O'qituvchi tanlovi AI-grader

Maktabga o'qituvchi tanlashda nomzodlarni **kasbiy imtihon** orqali baholaydigan
sun'iy intellekt xizmati. Ikki ishni bajaradi:

1. **Savol yaratish** — mutaxassislik (fan) bo'yicha professional, ochiq (yozma javob
   talab qiladigan) imtihon savollarini Claude yordamida yaratadi.
2. **Baholash** — nomzodlarning `/imtihon` sahifasida bergan javoblarini Claude
   (kuchli AI ekspert) bilan baholaydi: har bir javobga ball + izoh, so'ng umumiy
   daraja (Boshlang‘ich / O‘rta / Yuqori / Ekspert), umumiy ball, kuchli/zaif tomon
   va tavsiya. Natija admin paneldagi **«O‘qituvchi tanlovi»** bo'limida ko'rinadi.

AI serverda ishlaydi va **Anthropic (Claude) API kaliti** talab qiladi. Kalit faqat
shu xizmatda saqlanadi — saytga yoki brauzerga tushmaydi. Firestore'ga Admin SDK
orqali yozadi, shuning uchun ishonchli kompyuterda ishga tushiring.

## 1. Tayyorgarlik

1. **Node.js 18+** o'rnating.
2. Anthropic konsolidan **API kaliti** oling (console.anthropic.com). Xarajat juda
   arzon: bitta imtihonni baholash bir necha *sent* turadi.
3. Firebase konsolidan **xizmat hisobi kaliti** oling → `service-account.json` deb
   shu papkaga saqlang. ⚠️ Bu faylni va API kalitni hech kimga bermang, git'ga qo'ymang.

## 2. Sozlash

```bash
cd ai-grader
npm install
cp config.example.json config.json
```

`config.json`:

| Maydon | Ma'nosi |
|---|---|
| `serviceAccount` | Firebase xizmat hisobi kaliti yo'li (`./service-account.json`) |
| `anthropicKey` | Anthropic API kaliti (`sk-ant-...`). Yoki `ANTHROPIC_API_KEY` muhit o'zgaruvchisi |
| `model` | Claude modeli (standart: `claude-opus-4-8` — eng kuchli) |

## 3. Savollarni yaratish

Har bir mutaxassislik uchun bir marta savol to'plamini yarating:

```bash
node index.cjs generate "Matematika" 5
node index.cjs generate "Ingliz tili" 5
node index.cjs generate "Boshlang‘ich ta’lim" 5
```

Bu `exam_questions/<slug>` hujjatiga savollarni yozadi. Nomzod `/imtihon`
sahifasida shu mutaxassislikni tanlaganda o'sha savollarni ko'radi.
(Savollarni admin panelda ko'rib/tahrirlab ham bo'ladi — Firestore'da.)

## 4. Javoblarni baholash

Nomzodlar javob yuborgach, baholash uchun ishga tushiring:

```bash
node index.cjs grade
```

Bu `applications` dagi barcha yangi (baholanmagan) arizalarni oladi, har birini
Claude bilan baholaydi va natijani yozadi. Admin panelda darhol ko'rinadi.

Avtomatik ishlashi uchun cron bilan qo'ying (masalan har 10 daqiqada):

```
*/10 * * * *  cd /opt/iqror/ai-grader && /usr/bin/node index.cjs grade >> grader.log 2>&1
```

## Qanday baholaydi

- Har bir javob **alohida** ekspert sifatida baholanadi (fan chuqurligi, to'g'rilik,
  misollar, metodika) → 0–100 ball + izoh.
- Keyin barcha baholar asosida **umumiy xulosa** chiqariladi: daraja, umumiy ball,
  kuchli/zaif tomonlar, tavsiya.
- Yozma/uslub emas, **javob mazmuni** baholanadi.

## Maxfiylik va xavfsizlik

- `service-account.json` va `anthropicKey` — maxfiy. Git'ga qo'ymang (`.gitignore` bor).
- Nomzod javoblari va AI natijalari faqat **admin/zavuch**ga ko'rinadi (Firestore qoidalari).
- Yakuniy ishga olish qarorini AI emas, **maktab ma'muriyati** qabul qiladi — AI faqat
  yordamchi baho beradi.
