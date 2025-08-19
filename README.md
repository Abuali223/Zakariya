# Arab Tili — Gibrid Platforma (PWA + Supabase)

**Uzbek UI**, **serversiz PWA**, **offline SRS**, **onlayn bo‘lsa Supabase bilan sinxron**. GitHub Pages’da bevosita ishlaydi.

## 🚀 Tez start (GitHub Pages)
1) Yangi repo oching (masalan, `arab-tili`).
2) Ushbu fayllarni yuklang (yoki `gh` bilan push qiling).
3) GitHub’da **Settings → Pages**: Source = `GitHub Actions` (workflow shu repoda bor).
4) Birinchi deploydan keyin sizning saytingiz `https://<username>.github.io/arab-tili/` da ochiladi.

> Agar Actions’dan foydalanmasangiz: **Settings → Pages → Source: `main` → `/ (root)`** qilib ham qo‘yishingiz mumkin (build talab qilinmaydi).

## 🔑 Supabase ulash (ixtiyoriy, lekin tavsiya)
1) https://supabase.com da project oching.
2) **Project Settings → API** dan
   - `Project URL`
   - `anon public key`
   ni oling.
3) `config.example.js` ni **`config.js`** nomi bilan nusxalab, o‘sha qiymatlarni qo‘ying.
4) Jadval va siyosatlar:

```sql
-- Progress jadvali
create table if not exists public.progress (
  user uuid not null,
  item text not null,
  correct int not null default 0,
  wrong int not null default 0,
  ef float8 not null default 2.5,
  interval int not null default 0,
  due bigint not null default 0, -- Date.now() ms
  updated_at bigint not null default 0,
  rev int not null default 0,
  primary key(user, item)
);

-- Row Level Security
alter table public.progress enable row level security;

create policy "read own progress"
on public.progress for select
using ( auth.uid() = user );

create policy "upsert own progress"
on public.progress for insert
with check ( auth.uid() = user );

create policy "update own progress"
on public.progress for update
using ( auth.uid() = user )
with check ( auth.uid() = user );
```

> **Eslatma:** Demo holatda kontent JSON’lari statik papkada. Istasangiz, CMS yoki Supabase jadvalidan dinamik tortishingiz mumkin.

## 🧠 SI (AI) endpointlari (ixtiyoriy)
Supabase **Edge Functions** orqali AI chat yoki talaffuz baholashni yozishingiz mumkin. Frontend `supabase.functions.invoke('tutor', ...)` ni chaqiradi.

Minimal misol (Deno, `tutor/index.ts`):
```ts
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

serve(async (req) => {
  const { q, level, topic } = await req.json();
  // TODO: LLM API chaqiring va javobni qaytaring
  return new Response(JSON.stringify({ answer: `Savol: ${q} (daraja: ${level}, mavzu: ${topic})` }), {
    headers: { "Content-Type": "application/json" },
  });
});
```

## 📦 Tuzilma
```
/assets/icons/         # PWA ikonlar
/content/*.json        # Mavzular va so‘zlar (statik JSON)
index.html             # UI va sahifalar
app.js                 # SRS, IndexedDB, Supabase sync, router
manifest.json          # PWA manifest
sw.js                  # Service Worker (oflayn)
config.example.js      # Supabase sozlamasini bu fayldan ko'chiring -> config.js
```

## 🧩 Kontentni kengaytirish
- Yangi mavzu qo‘shish uchun `content/` ichiga `mytopic.json` qo‘shing:
```json
{
  "title": "Mavzu nomi",
  "preview": "ك",
  "items": [{ "ar": "كِتَاب", "tr": "kitāb", "uz": "kitob" }]
}
```
- `PACKS` massiviga `app.js` ichida fayl nomini (`mytopic`) qo‘shing.

## 📱 PWA o‘rnatish
- Brauzer yuqorisidagi “Install”/“Add to Home Screen” orqali ilova sifatida o‘rnatiladi.
- Oflayn rejimda ham ishlaydi; onlayn bo‘lsa sinxronlashadi.

## 🛡 Maxfiylik
- O‘quvchi ma’lumotlari qurilmada (IndexedDB) saqlanadi; login qilinganda Supabase bilan sinxron bo‘ladi.
- RLS siyosati foydalanuvchi faqat o‘z progressini ko‘rishini kafolatlaydi.

## ❓ Savollar
Muammo bo‘lsa, `config.js` to‘g‘ri to‘ldirilganini, GitHub Pages yoqilganini va fayllar `index.html` bilan rootda turganini tekshiring.
