// =====================================================================
// firebase-storage.js (SHIM) — Firebase Storage API'sini Supabase Storage ustida taqlid.
// ⚠️ Bu Firebase EMAS — Supabase adapteri. admin.html faqat shularni ishlatadi:
//   getStorage, ref, uploadBytes, getDownloadURL   (+ deleteObject qulaylik uchun)
// Yo'l (path) o'zgarmaydi: images/<folder>/<ts>_<name>, videos/<folder>/...
// =====================================================================
import { supabase } from "./_core.js";
import { STORAGE_BUCKET } from "./sb-config.js";

export function getStorage(_app) { return { __sb: true, bucket: STORAGE_BUCKET }; }

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

export async function getDownloadURL(r) {
  const { data } = supabase().storage.from(r._bucket).getPublicUrl(r._path);
  return data.publicUrl;
}

export async function deleteObject(r) {
  const { error } = await supabase().storage.from(r._bucket).remove([r._path]);
  if (error) throw error;
}
