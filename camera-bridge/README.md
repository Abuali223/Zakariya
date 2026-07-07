# Iqror — Yuz terminali → davomat ko'prigi (camera-bridge)

Kirish qismidagi **yuz tanaydigan terminal** (Hikvision / ZKTeco / Dahua) tanigan har bir
shaxsni avtomatik davomatga aylantiradi:

- har bir kelish `checkins` jurnaliga yoziladi (admin panel → **Kirish nazorati**);
- o'quvchi uchun o'sha kun **Keldi / Kech** deb belgilanadi (dars vaqtiga qarab);
- `students.attendance` foizi avtomatik yangilanadi (sayt/kabinet bilan bir xil formula);
- xodimlar (o'qituvchilar) uchun kelish vaqti qayd etiladi — kechikish nazorati uchun.

Ko'prik **Firebase Admin SDK** (xizmat hisobi) orqali yozadi. Shuning uchun uni **maktabdagi
ishonchli, doim yoniq kompyuterda** (mini-PC yoki server) ishga tushiring — terminal shu
kompyuterga voqea yuboradi.

---

## 1. Tayyorgarlik

1. **Node.js 18+** o'rnating.
2. Firebase konsolidan **xizmat hisobi kaliti** oling:
   *Project settings → Service accounts → Generate new private key* → faylni
   `service-account.json` deb shu papkaga saqlang. ⚠️ Bu faylni hech kimga bermang, git'ga qo'ymang.
3. Har bir o'quvchi/xodimni terminalda ro'yxatga oling (yuzini enroll qiling) va terminaldagi
   **shaxs ID** (Person ID / Employee No / PIN) ni eslab qoling.
4. Admin panelda o'sha shaxsning **«Kamera ID»** maydoniga xuddi shu ID ni yozing.
   (O'quvchilar → Tahrir → Kamera ID; O'qituvchilar → Tahrir → Kamera ID.)

## 2. Sozlash

```bash
cd camera-bridge
npm install
cp config.example.json config.json
```

`config.json` ni to'ldiring:

| Maydon | Ma'nosi |
|---|---|
| `serviceAccount` | Xizmat hisobi kaliti yo'li (`./service-account.json`) |
| `attendanceStart` | Dars boshlanish vaqti, `"08:30"` — shundan keyin kelgan **Kech** |
| `lateGraceMinutes` | Kechikishga yon berish (masalan `5` daqiqa) |
| `deviceId` | Terminal nomi (jurnalда ko'rinadi) |
| `port` | Webhook porti (masalan `8787`) |
| `webhookToken` | Maxfiy satr — faqat terminal yuborishi uchun (URL/sarlavhada uzatiladi) |

## 3. Ishga tushirish

```bash
node index.cjs
# Iqror camera-bridge tinglayapti :8787 ...
```

Doimiy ishlashi uchun `pm2` yoki `systemd` dan foydalaning:
```bash
npm i -g pm2 && pm2 start index.cjs --name iqror-bridge && pm2 save
```

## 4. Terminalni ko'prikka ulash

Ko'prik `http://<mini-pc-ip>:8787/?token=SIZNING_TOKEN` manziliga **POST** kutadi. Terminalни
o'sha manzilga voqea yuboradigan qilib sozlang (interfeys modelga qarab farq qiladi):

- **Hikvision:** *Configuration → Network → Advanced → HTTP Listening* (yoki *Event → Alarm/
  Linkage → HTTP host*) — server IP, port va URL ni kiriting.
- **ZKTeco:** *Comm → Cloud Server / ADMS* yoki push-SDK orqali HTTP manzilга yuboriladi.
- **Dahua:** *Network → Access Platform / HTTP Push* orqali.

Ko'prik keng tarqalgan maydon nomlarini o'zi tushunadi
(`personId`, `employeeNoString`, `pin`, `userId`, `card`; vaqt: `time`, `dateTime`, `happenTime`).
Agar terminalingiz boshqa formatда yuborsa — menga bitta namuna (payload) yuboring, moslashtirib beraman.

**Kutiladigan (normal) format** (agar o'zingiz proksi orqali yuborsangiz):
```json
{ "cameraId": "1042", "time": "2026-09-01T08:05:00", "deviceId": "kirish-1", "direction": "in" }
```

Sinov:
```bash
node index.cjs test-event 1042 2026-09-01T08:05:00
# {"ok":true,"personType":"student","status":"present",...}
```

## 5. Kelmaganlarni «Yo'q» qilish (kun oxirida)

Terminal faqat **kelganlarni** biladi. Kelmaganlarni avtomatik «Yo'q» qilish uchun har kuni
dars tugagach quyidagini ishga tushiring (cron):

```bash
node index.cjs mark-absent            # bugun
node index.cjs mark-absent 2026-09-01 # aniq sana
```

Cron misoli (har kuni 15:00 da):
```
0 15 * * 1-6  cd /opt/iqror/camera-bridge && /usr/bin/node index.cjs mark-absent >> bridge.log 2>&1
```

---

## Maxfiylik (muhim)

- Terminal yuz **shablonlarini o'zida** saqlaydi. Ko'prik faqat **ID + vaqt** ni oladi —
  yuz rasmlari bulutga yuklanmaydi.
- Bolalarning biometrik ma'lumoti — maxfiy toifa. **Ota-onalar yozma roziligini** oling va
  O'zbekiston «Shaxsga doir ma'lumotlar» qonuni talablariga rioya qiling.
- `service-account.json` va `webhookToken` — maxfiy. Git'ga qo'ymang, tarqatmang.
