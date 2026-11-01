// =====================================================================
// firebase-storage.js (SHIM) — Firebase Storage API'sini Supabase Storage ustida taqlid.
// ⚠️ Bu Firebase EMAS — Supabase adapteri. admin.html faqat shularni ishlatadi:
//   getStorage, ref, uploadBytes, getDownloadURL   (+ deleteObject qulaylik uchun)
//   + YOPIQ bucket'lar uchun (masalan «medical» — ma'lumotnoma nusxalari, nurse-sick.sql):
//     getStorage(app, 'medical'), uploadBytesNoOverwrite (upsert'siz — mavjud fayl almashtirilmaydi),
//     getSignedURL (vaqtinchalik imzolangan havola; ommaviy URL bunday bucket'da ishlamaydi).
// Yo'l (path) o'zgarmaydi: images/<folder>/<ts>_<name>, videos/<folder>/...
// =====================================================================
import { supabase } from "./_core.js";
import { STORAGE_BUCKET } from "./sb-config.js";

export function getStorage(_app, bucket) { return { __sb: true, bucket: bucket || STORAGE_BUCKET }; }

export function ref(storage, path) {
  return { _path: path, _bucket: (storage && storage.bucket) || STORAGE_BUCKET };
}

export async function uploadBytes(r, file, metadata) {
  const { error } = await supabase().storage
    .from(r._bucket)
    .upload(r._path, file, {
      upsert: true,
      contentType: (metadata && metadata.contentType) || (file && file.type) || undefined,
    });
  if (error) throw error;
  return { ref: r, metadata: metadata || {} };
}

// Ustiga yozmasdan yuklash: shu yo'lda fayl bo'lsa XATO (yopiq bucket'larda upsert ruxsati yo'q — faqat INSERT).
export async function uploadBytesNoOverwrite(r, file, metadata) {
  const { error } = await supabase().storage
    .from(r._bucket)
    .upload(r._path, file, {
      upsert: false,
      contentType: (metadata && metadata.contentType) || (file && file.type) || undefined,
    });
  if (error) throw error;
  return { ref: r, metadata: metadata || {} };
}

// Imzolangan (vaqtinchalik, 60–300 soniya) havola — yopiq bucket fayli; ruxsat RLS (storage.objects SELECT) bilan.
export async function getSignedURL(r, seconds) {
  const sec = Math.min(300, Math.max(60, Math.round(Number(seconds) || 120)));
  const { data, error } = await supabase().storage.from(r._bucket).createSignedUrl(r._path, sec);
  if (error) throw error;
  return data.signedUrl;
}

export async function getDownloadURL(r) {
  const { data } = supabase().storage.from(r._bucket).getPublicUrl(r._path);
  return data.publicUrl;
}

export async function deleteObject(r) {
  const { error } = await supabase().storage.from(r._bucket).remove([r._path]);
  if (error) throw error;
}
