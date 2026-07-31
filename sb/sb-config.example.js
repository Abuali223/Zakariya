// sb-config.js — Supabase ulanish sozlamalari (NAMUNA).
// VPS tayyor bo'lgach: bu faylni `sb-config.js` deb nusxalang va qiymatlarni to'ldiring:
//   cp sb/sb-config.example.js sb/sb-config.js
// HAQIQIY sb/sb-config.js repoga QO'SHILMAYDI (sb/.gitignore'da).
//
// SUPABASE_ANON_KEY — "ochiq" (public) kalit; RLS himoya qiladi, shuning uchun
// frontend'da bo'lishi normal. SERVICE_ROLE kalitini bu yerga QO'YMANG — u faqat serverda!

export const SUPABASE_URL = "https://api.iqror.uz";           // yoki http://<vps-ip>:8000
export const SUPABASE_ANON_KEY = "PASTE_ANON_KEY_HERE";       // Supabase .env dagi ANON_KEY
export const STORAGE_BUCKET = "public";                        // rasm/video bucket nomi
