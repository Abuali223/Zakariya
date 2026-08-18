# Cutover + parallel-sinov ro'yxati (VPS bosqichi)

Bu — Supabase VPS tayyor bo'lgach bajariladigan **oxirgi bosqich**. Har bir band
belgilanadi (☐ → ☑). Muammo bo'lsa — chiqqan xatoni menga tashlang.

---

## A. Frontend'ni Supabase'ga ulash (kod tomoni — men tayyorladim)

1. ☐ `sb/sb-config.js` yarating (namunadan):
   ```bash
   cp sb/sb-config.example.js sb/sb-config.js
   # sb/sb-config.js ni oching, to'ldiring:
   #   SUPABASE_URL      = https://api.iqror.uz
   #   SUPABASE_ANON_KEY = <.env dagi ANON_KEY>
   #   STORAGE_BUCKET    = public
   ```
2. ☐ `/sb/` papka frontend bilan birga deploy qilinsin (index.html yonida `/sb/...`).
3. ☐ Backendni Supabase shimlarga o'tkazing (bitta buyruq, qaytariladi):
   ```bash
   node migration/switch-backend.cjs supabase        # (avval --dry bilan ko'ring)
   ```
   Bu barcha HTML importlarини `https://www.gstatic.com/firebasejs/10.12.5`
   dan `/sb` ga o'zgartiradi (Firebase SDK → Supabase shim). Rollback:
   `node migration/switch-backend.cjs firebase`.

## B. Supabase sozlamalari (dashboard/.env)

4. ☐ **Auth → Providers → Email**: yoqilgan. "Confirm email" — xohishga ko'ra.
5. ☐ **Auth → Providers → Google**: OAuth yoqilgan, Client ID/Secret kiritilgan,
   redirect URL: `https://api.iqror.uz/auth/v1/callback` (+ sayt domeningiz).
6. ☐ **Auth → Anonymous sign-ins**: YOQILGAN (o'quv-platforma.html anonim kiradi).
7. ☐ **Storage**: `public` bucket bor va *public* (o'qish ochiq) — rasm/video uchun.
   Storage RLS (kim yuklaydi) — `rls.sql` dan keyin ishga tushiring:
   ```bash
   psql "$PGURL" -f migration/storage-rls.sql     # hamma o'qiydi, faqat admin yozadi
   ```
8. ☐ **SMTP**: parol-tiklash/tasdiq emaillari uchun sozlangan.
9. ☐ URL rewrite (import'dan keyin bir marta):
   ```bash
   SUPABASE_URL=https://api.iqror.uz STORAGE_BUCKET=public \
     DATABASE_URL="$PGURL" node migration/rewrite-storage-urls.cjs   # avval DRY=1 bilan
   ```

## B2. Server xizmatlari (AI yordamchi + to'lov) — Supabase'ga ko'chirilgan

Bu ikki Node xizmati Firebase Admin SDK o'rniga **Supabase service_role** ishlatadi
(`server/backend.js` `config.backend` bilan tanlaydi). Biznes-mantiq o'zgarmadi.

10. ☐ `server/` da paket o'rnating: `cd server && npm install` (@supabase/supabase-js).
11. ☐ **AI yordamchi** (`ai-assistant/`):
    ```bash
    cp ai-assistant/config.example.json ai-assistant/config.json
    # to'ldiring: backend="supabase", supabaseUrl, serviceRoleKey, anthropicKey, allowOrigin
    node ai-assistant/index.cjs serve      # :8791 (/chat, /student-summary, /risk)
    ```
    Frontend `config/ai.url` ni shu xizmat manziliga (masalan `https://api.iqror.uz/ai`) yo'naltiring.
12. ☐ **To'lov** (`payments/`):
    ```bash
    cp payments/config.example.json payments/config.json
    # to'ldiring: backend="supabase", supabaseUrl, serviceRoleKey, click{serviceId,secretKey}
    node payments/index.cjs                 # :8790 (/click/prepare, /click/complete, /uzum)
    ```
    Click merchant kabinetida prepare/complete URL'larini shu xizmatga qo'ying;
    **Click sandbox** bilan bitta test to'lovni oxirigacha tekshiring.
13. ☐ Anthropic kaliti + Click secret — faqat server config/ENV'da (saytga tushmaydi).
14. ☐ Nginx: `api.iqror.uz` → Supabase(8000); `/ai` → 8791; `/pay` → 8790 (reverse-proxy).

> **Eslatma:** `ai-grader/` **kerak emas** (o'tkazilmadi). `functions/` — faqat Firebase
> (admin-claim sync + AI endpoint); Supabase'da ular O'RNIGA `storage-rls.sql` (yuklash
> huquqi) + `ai-assistant` ishlaydi, shuning uchun `functions/` ko'chirilmaydi.

## C. Funksional sinov (har bir ROL bo'yicha — eski Firebase natijasi bilan solishtiring)

### Kirish / Auth
10. ☐ Email+parol bilan kirish (admin, ota-ona) — `signInWithEmailAndPassword`
11. ☐ Google bilan kirish (popup → redirect fallback) — `signInWithOAuth`
12. ☐ Ro'yxatdan o'tish (yangi ota-ona) — `createUserWithEmailAndPassword`
13. ☐ Chiqish (logout) — `signOut`; sahifa yangilanганда holat saqlanadi (persistence)
14. ☐ Parolni o'zgartirish (admin panel) — `updatePassword`
15. ☐ o'quv-platforma.html anonim kirib, progress saqlanadi — `signInAnonymously`

### Ota-ona kabineti (index.html)
16. ☐ Farzand baholari, davomat, to'lovlar ko'rinadi
17. ☐ Chorak profili (xarakteristika + fan izohlari) ko'rinadi
18. ☐ Rasmiy profil PDF + QR yaratiladi; `verify.html?id=...` tekshiradi
19. ☐ **BEGONA ota-ona boshqa bola ma'lumotini KO'RMAYDI** (RLS) ★

### O'qituvchi / kurator / sinf rahbari (admin.html)
20. ☐ O'qituvchi FAQAT o'z fani izohini ko'radi/yozadi (izolyatsiya) ★★
21. ☐ Baho/davomat kiritish; monitoring (zavuch tasdiqlaydi)
22. ☐ Sinf rahbari/kurator/zavuch UMUMIY xarakteristika yozadi;
   oddiy fan o'qituvchisi umumiyni YOZA OLMAYDI ★
23. ☐ Rasm/video yuklash ishlaydi (Storage) — `uploadBytes`/`getDownloadURL`

### Admin (to'liq CRUD)
24. ☐ Yangilik, galereya, fikrlar, o'qituvchilar, narxlar, FAQ — qo'shish/tahrir/o'chirish
25. ☐ O'quvchi qo'shish + shaxsiy (PII) ma'lumot — faqat admin ko'radi ★
26. ☐ Real-time yangilanish (onSnapshot → Supabase Realtime) — ikki oynada sinang

### Server xizmatlari (AI + to'lov)
26b. ☐ AI chat javob beradi (`/chat`); ota-onaga oylik xulosa (`/student-summary`);
   xavf ro'yxati (`/risk`) — ma'lumot Supabase'dan o'qiladi
26c. ☐ Click test to'lovi: prepare → complete → invoice "paid" bo'ladi (sandbox)

### Ommaviy sayt (login shart emas)
27. ☐ Bosh sahifa, galereya, natijalar (faqat 90+ a'lochilar), rasmlar ko'rinadi
28. ☐ Ariza/qabul formasi yuboriladi (enrollments/applications insert)

## D. Xavfsizlik sinovi (RLS jonli tekshiruv)
29. ☐ Login qilmagan foydalanuvchi `student_private` (PII) ni O'QIY OLMAYDI
30. ☐ `secrets` jadvali mijozga umuman ko'rinmaydi
31. ☐ Ota-ona/o'qituvchi boshqa sinf yoki fan ma'lumotini ko'ra olmaydi
32. ☐ (ixtiyoriy) `migration/test-rls.cjs` ni jonli bazaga qarshi yuguring

## E. Cutover (100% muvofiq bo'lgach)
33. ☐ DNS/domenни yangi frontend'ga o'tkazing (`iqror.uz` → Supabase-frontend)
34. ☐ Kunlik backup cron (pg_dump + Storage) yoqilgan
35. ☐ **Firebase kamida 1 oy zaxirada** (rollback: `switch-backend.cjs firebase` + eski deploy)

---

### Kodni tekshirish (VPS'siz allaqachon bajarilgan ✅)
- `migration/run-shim-test.cjs` — Firestore-shim (frontend) tarjimasi **17/17 PASS** (tarmoqsiz)
- `server/sb-admin.test.cjs` — server-shim (Admin SDK) tarjimasi **13/13 PASS**
- `payments/flow.test.cjs` — to'lov oqimi (prepare→complete→paid) **9/9 PASS**
- `migration/test-rls.cjs` — RLS **25/25 PASS** (haqiqiy PostgreSQL 16)
- `migration/switch-backend.cjs supabase --dry` — 9 o'rin, xatosiz
