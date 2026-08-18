# server/ — Supabase data qatlami (server xizmatlari uchun)

Server xizmatlari (`ai-assistant`, `payments`) Firebase'dan Supabase'ga o'tganda
Firebase Admin SDK o'rniga **Supabase service_role** ishlatadi. Bu papka o'sha
almashtirishni beradi — biznes-mantiq (AI promptlari, Click imzosi) **o'zgarmaydi**.

## Fayllar
- **`sb-admin.js`** — Firebase Admin (Firestore) yuzasini Supabase service_role
  ustida taqlid qiladi: `db.collection(t).doc(id).get()/set()/update()/delete()`,
  `.where(f,op,v).get()`, `FieldValue.serverTimestamp()`, `verifyToken()`.
  service_role RLS'ni chetlab o'tadi (Admin SDK kabi).
- **`backend.js`** — `config.backend` bilan tanlaydi:
  `"supabase"` → `sb-admin.js`; aks holda Firebase Admin SDK (rollback uchun).
  Xizmatlar shuni chaqiradi: `const { db, FieldValue } = require('../server/backend.js')({...CFG, __dir:__dirname})`.
- **`sb-admin.test.cjs`** — tarjima sinovi (real paketsiz, soxta mijoz). 13/13 PASS.

## O'rnatish (VPS'da)
```bash
cd server && npm install          # @supabase/supabase-js
# keyin har bir xizmat config.json'ida:
#   "backend": "supabase", "supabaseUrl": "...", "serviceRoleKey": "..."
```

## Backendni tanlash
| config.backend | Data qatlami | Qachon |
|---|---|---|
| `"supabase"` | Supabase service_role | Migratsiyadan keyin (asosiy) |
| `"firebase"` (default) | Firebase Admin SDK | Rollback / eski tizim |

`serviceRoleKey` va `anthropicKey`/Click secret — FAQAT server config/ENV'da,
saytga hech qachon tushmaydi. `config.json` `.gitignore`'da.
