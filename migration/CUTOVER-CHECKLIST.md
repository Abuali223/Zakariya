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
8. ☐ **SMTP**: parol-tiklash/tasdiq emaillari uchun sozlangan.
9. ☐ URL rewrite (import'dan keyin bir marta):
   ```bash
   SUPABASE_URL=https://api.iqror.uz STORAGE_BUCKET=public \
     DATABASE_URL="$PGURL" node migration/rewrite-storage-urls.cjs   # avval DRY=1 bilan
   ```

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
- `migration/run-shim-test.cjs` — Firestore-shim tarjimasi **17/17 PASS** (tarmoqsiz)
- `migration/test-rls.cjs` — RLS **25/25 PASS** (haqiqiy PostgreSQL 16)
- `migration/switch-backend.cjs supabase --dry` — 9 o'rin, xatosiz
