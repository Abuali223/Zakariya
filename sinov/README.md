# IQROR — sinov nusxasi (o‘qitish va qabul sinovi stendi)

Kassir, moliya menejeri, buxgalter va direktor yangi imkoniyatlarni **haqiqiy ma’lumotga tegmasdan** mashq qilishi uchun
alohida nusxa. Yangi domen kerak emas: asosiy sayt bilan bir serverda, lekin **boshqa portda** ochiladi
(masalan `https://<sayt domeni>:8443/admin.html`). Brauzer uchun bu — boshqa manzil: xotirasi, keshi va oflayn navbati
asosiy saytdan to‘liq ajratilgan, shuning uchun sinov to‘lovi hech qachon haqiqiy bazaga tushmaydi.

## Nimadan iborat

| Qism | Nomi (qat’iy) | Izoh |
|---|---|---|
| Baza | `iqror_sinov` | shu Postgres ichida alohida baza; faqat **to‘qima** ma’lumot («Sinov O‘quvchi 01» …) |
| API | `iqror-sinov-rest` konteyneri | ikkinchi PostgREST, faqat `127.0.0.1`, o‘z JWT siri bilan |
| Server | `iqror-sinov` xizmati | sahifalar + kirish (faqat sinov hisoblari) + API’ga ko‘prik; tashqi serverga ulana olmaydi |
| nginx | `iqror-sinov` fayli | alohida fayl, asosiy sayt sertifikati bilan; mavjud sayt fayliga tegilmaydi |
| Papka | `/opt/iqror-sinov` | sahifalar nusxasi, sirlar va sinov hisoblari (faqat root) |

Stend **hech qachon** SMS, Telegram xabari yubormaydi, to‘lov tizimiga ulanmaydi, fayl yuklamaydi. Har sahifa tepasida qizil
«SINOV NUSXASI — haqiqiy ma’lumot emas» belgisi turadi, chop etiladigan hujjatlarda ham shu yozuv chiqadi.

## O‘rnatish

Serverda, oddiy foydalanuvchi sifatida (sudo’siz — kerakli joyda o‘zi so‘raydi):

```bash
cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- sinov
bash ~/iqror-repo/sinov/install.sh --dry-run      # avval: faqat tekshiradi, hech narsani o‘zgartirmaydi
bash ~/iqror-repo/sinov/install.sh                # o‘rnatadi (qayta ishga tushirish xavfsiz)
```

- 8443‑port band bo‘lsa: `bash ~/iqror-repo/sinov/install.sh --port 9443`.
- Kassa bo‘limi (hali ishga tushirilmagan migratsiyalar) bilan mashq qilish uchun: `--dev` bayrog‘ini qo‘shing.
- Tashqaridan ochilmasa — hosting panelidagi (tashqi) firewall’da shu portni oching.
- Biror tekshiruv o‘tmasa skript to‘xtaydi, hech narsani o‘zgartirmaydi va «Topilgan holat» blokini chiqaradi — shu blokni
  yuborsangiz kifoya (unda parol va kalitlar yo‘q).

## Sinov hisoblari

O‘rnatishda 9 ta hisob yaratiladi: Direktor, Moliya menejeri, 2 ta Kassir, G‘aznachi, HR, O‘IBDO‘, O‘qituvchi, Qabulxona.
Loginlar ekranda ko‘rsatiladi, **parollar ko‘rsatilmaydi** — ularni faqat serverda ko‘rasiz:

```bash
sudo cat /opt/iqror-sinov/accounts.txt
```

Bu faylni va parollarni hech kimga (dasturchiga ham) yubormang; har bir xodimga faqat o‘z qatorini bering. Bu parollar
haqiqiy tizimda ishlamaydi, haqiqiy parollar esa stendda ishlamaydi.

## Kundalik buyruqlar

```bash
bash ~/iqror-repo/sinov/update.sh     # har oddiy deploy’dan keyin: yangi sahifalar va baza o‘zgarishlari (mashq ma’lumotlari saqlanadi)
bash ~/iqror-repo/sinov/reset.sh      # yangidan boshlash: baza qaytadan quriladi, toza to‘qima ma’lumot (parollar saqlanadi)
bash ~/iqror-repo/sinov/remove.sh     # o‘chirish (baza va parollar qoladi);  --yes bilan — baza va papka ham o‘chadi
```

Har birida `--dry-run` bor.

## Xavfsizlik

- Jonli baza (`postgres`) o‘zgartirilmaydi: unga faqat «`iqror_sinov` bazasini yaratish / o‘chirish» buyrug‘i uchun ulanadi.
  Baza nomi skriptlarda qat’iy tekshiriladi.
- Mavjud nginx sayt fayli, ishlab turgan xizmatlar va konteynerlar o‘zgartirilmaydi va qayta ishga tushirilmaydi; nginx
  faqat `nginx -t` dan o‘tgach qayta yuklanadi, o‘tmasa stend fayli qaytarib olinadi.
- Stend o‘z JWT siri bilan ishlaydi: stend kaliti bilan haqiqiy tizimga, haqiqiy tizim kaliti bilan stendga kirib bo‘lmaydi.
- Kirish urinishlari cheklangan (bitta hisobga 15 daqiqada 8 xato parol; bitta manzildan 10 daqiqada 40 urinish).
- Stend internetdan ochiq bo‘ladi — unga hech qachon haqiqiy o‘quvchi, ota-ona yoki pul ma’lumotini kiritmang.
