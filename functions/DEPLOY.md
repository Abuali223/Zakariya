# AI yordamchi — Cloud Function deploy (Firebase)

Chatbot va AI xulosalar shu funksiya orqali ishlaydi. Firebase'da server = **Cloud
Functions** (hosting faqat statik sayt). Kalit Firestore `secrets/ai` dan olinadi
(admin paneldan kiritilgan), shuning uchun bu yerga kalit yozilmaydi.

## Deploy ikki yo'l bilan

### Yo'l 1 — o'zingiz deploy qilasiz (kompyuterdan)
Bir marta quyidagilar kerak:
```bash
# 1) Node.js 20+ va Firebase CLI
npm install -g firebase-tools

# 2) O'z Google akkauntingiz bilan kiring (Owner bo'lgan)
firebase login

# 3) Loyihani oling va bog'liqliklarni o'rnating
git clone https://github.com/abuali223/zakariya.git
cd zakariya/functions && npm install && cd ..

# 4) Deploy
firebase deploy --only functions --project alilazer-cd582
```
Oxirida quyidagicha manzil chiqadi:
```
Function URL (ai(us-central1)): https://ai-XXXXXXXX-uc.a.run.app
```
Shu **manzilni** admin panel → Sozlamalar → AI yordamchi → «AI server manzili» ga yozing.
Tamom — chatbot ishlaydi.

### Yo'l 2 — men (Claude) deploy qilaman
Buning uchun loyiha xizmat-hisobiga ikkita rol berish kerak (Google Cloud Console → IAM):
Xizmat hisobi: **`firebase-adminsdk-fbsvc@alilazer-cd582.iam.gserviceaccount.com`**
Rollar:
- **Cloud Functions Admin** (`roles/cloudfunctions.admin`)
- **Service Account User** (`roles/iam.serviceAccountUser`)
- **Cloud Build Editor** (`roles/cloudbuild.builds.editor`)
- **Artifact Registry Administrator** (`roles/artifactregistry.admin`)

(Yoki oddiyroq: **Editor** + **Service Account User**.) Rol bergач ayting — men
deploy qilib, manzilni panelga o'zim yozib qo'yaman.

## Tekshirish
Deploy'dan keyin brauzerда `<FUNCTION_URL>/health` ni oching — `{"ok":true}` chiqishi kerak.
`config/ai.url` shu bazaviy manzil bo'ladi; sayt unga `/chat`, admin `/student-summary` qo'shadi.

## Xarajat
- Blaze rejasida. Chatbot so'rovlari arzon (effort «low»). Cloud Functions bepul
  kvota katta; kunlik oz sonli so'rov deyarli bepul. Anthropic kaliti bo'yicha alohida hisob.
